/**
 * Integração segura SuperFrete — token por loja em fretes_secrets (Admin SDK only).
 */

import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";

export const SUPERFRETE_USER_AGENT = "MasterPalm (contato@mastepalm.com.br)";
export const SUPERFRETE_API_BASE = "https://api.superfrete.com";
export const FRETES_SECRETS_DOC = "fretes_secrets";
export const FRETES_PUBLIC_DOC = "fretes";

const LEGACY_SUPERFRETE_TOKEN_PATHS = [
  "superfrete_token",
  "superfreteToken",
  "apiToken",
];

/** Máscara segura: •••• + últimos 4 caracteres. */
export function maskToken(token) {
  const t = String(token ?? "").trim();
  if (t.length <= 4) return "••••";
  return `••••${t.slice(-4)}`;
}

export function normalizeCep(raw) {
  return String(raw ?? "").replace(/\D/g, "");
}

export function isValidCep(cep) {
  const c = normalizeCep(cep);
  return c.length === 8;
}

/** Detecta token legado exposto em documentos públicos (não migra). */
export function detectLegacySuperFreteToken(publicFretes = {}, draftFreteConfig = {}) {
  const pub = publicFretes && typeof publicFretes === "object" ? publicFretes : {};
  const draft =
    draftFreteConfig && typeof draftFreteConfig === "object"
      ? draftFreteConfig
      : {};

  const sf = pub.superfrete;
  if (sf && typeof sf === "object" && String(sf.token ?? "").trim()) {
    return true;
  }

  for (const key of LEGACY_SUPERFRETE_TOKEN_PATHS) {
    if (String(pub[key] ?? "").trim()) return true;
    if (String(draft[key] ?? "").trim()) return true;
  }

  return false;
}

/** Remove campos legados de token do mapa público de fretes. */
export function stripSuperFreteLegacyFromPublic(data) {
  const out =
    data && typeof data === "object"
      ? JSON.parse(JSON.stringify(data))
      : {};

  if (out.superfrete && typeof out.superfrete === "object") {
    const sf = { ...out.superfrete };
    delete sf.token;
    if (Object.keys(sf).length === 0) {
      delete out.superfrete;
    } else {
      out.superfrete = sf;
    }
  }

  for (const key of LEGACY_SUPERFRETE_TOKEN_PATHS) {
    delete out[key];
  }

  return out;
}

/** Valida escrita cliente em config/fretes — sem segredos SuperFrete. */
export function fretesPublicWriteSafe(data) {
  if (!data || typeof data !== "object") return true;
  if (detectLegacySuperFreteToken(data, {})) return false;

  const integrations = data.integrations?.superfrete;
  if (integrations && typeof integrations === "object") {
    if ("token" in integrations) return false;
    if ("apiToken" in integrations) return false;
  }

  return true;
}

function logSuperFrete(phase, detail) {
  console.info(`[SUPERFRETE][${phase}] ${detail}`);
}

function logSuperFreteFail(phase, detail) {
  console.warn(`[SUPERFRETE][${phase}][FALHA] ${detail}`);
}

function requireAuthUid(request) {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Faça login para continuar.");
  }
  return uid;
}

function parseSandbox(value) {
  return value === true || value === "true" || value === 1;
}

function buildQuotePayload({
  cepOrigem,
  cepDestino,
  pesoGrams,
  altura,
  largura,
  comprimento,
  valorDeclarado,
}) {
  const alt = Math.max(1, Math.round(Number(altura) || 10));
  const lar = Math.max(10, Math.round(Number(largura) || 20));
  const comp = Math.max(15, Math.round(Number(comprimento) || 30));
  const pesoKg = Math.max(0.3, Number(pesoGrams) / 1000);

  return {
    from: { postal_code: normalizeCep(cepOrigem) },
    to: { postal_code: normalizeCep(cepDestino) },
    package: {
      height: alt,
      width: lar,
      length: comp,
      weight: pesoKg,
    },
    options: {
      insurance_value: Number(valorDeclarado) > 0 ? Number(valorDeclarado) : 10,
      receipt: false,
      own_hand: false,
    },
  };
}

function mapQuoteResponse(data) {
  const arr = Array.isArray(data) ? data : [];
  const opcoes = arr.map((s) => ({
    nome: s.name ?? "SuperFrete",
    preco: Number(s.price) || 0,
    prazo: s.delivery_time ?? 0,
    empresa: s.company?.name ?? "SuperFrete",
    servico_id: s.id,
  }));
  opcoes.sort((a, b) => a.preco - b.preco);
  return opcoes;
}

/**
 * @param {object} deps
 * @param {import('firebase-admin/firestore').Firestore} deps.db
 * @param {Function} deps.canManageStoreConfigServerSide
 * @param {Function} deps.checkRateLimit
 * @param {Function} deps.getCallableIdentifier
 * @param {Function} deps.fetchWithTimeout
 * @param {string} deps.collectionLojas
 * @param {import('firebase-functions/v2/https').CallableRequest} deps.request
 * @param {object} [deps.overrides] test hooks
 */
export function createSuperFreteHandlers(deps) {
  const {
    db,
    canManageStoreConfigServerSide,
    checkRateLimit,
    getCallableIdentifier,
    fetchWithTimeout,
    collectionLojas,
    request,
    overrides = {},
  } = deps;

  const fetchImpl = overrides.fetchWithTimeout ?? fetchWithTimeout;

  async function requireStoreAdmin(lojaId) {
    const uid = requireAuthUid(request);
    const email = request.auth?.token?.email ?? "";
    const id = String(lojaId ?? "").trim();
    if (!id) {
      throw new HttpsError("invalid-argument", "Informe a loja.");
    }
    const allowed = await canManageStoreConfigServerSide({
      lojaId: id,
      uid,
      email,
    });
    if (!allowed) {
      throw new HttpsError(
        "permission-denied",
        "Sem permissão para configurar fretes desta loja.",
      );
    }
    return { uid, lojaId: id, email };
  }

  async function readSecrets(lojaId) {
    const ref = db
      .collection(collectionLojas)
      .doc(lojaId)
      .collection("config")
      .doc(FRETES_SECRETS_DOC);
    const snap = await ref.get();
    if (!snap.exists) return null;
    const sf = snap.data()?.superfrete;
    const token = String(sf?.token ?? "").trim();
    if (!token) return null;
    return {
      token,
      sandbox: parseSandbox(sf?.sandbox),
      data: sf,
    };
  }

  async function readPublicFretes(lojaId) {
    const ref = db
      .collection(collectionLojas)
      .doc(lojaId)
      .collection("config")
      .doc(FRETES_PUBLIC_DOC);
    const snap = await ref.get();
    return snap.exists ? snap.data() ?? {} : {};
  }

  async function readDraftFreteConfig(lojaId) {
    const ref = db
      .collection(collectionLojas)
      .doc(lojaId)
      .collection("draft_config")
      .doc("config");
    const snap = await ref.get();
    if (!snap.exists) return {};
    const fc = snap.data()?.frete_config;
    return fc && typeof fc === "object" ? fc : {};
  }

  async function assertStorePublishedForQuote(lojaId) {
    const lojaSnap = await db.collection(collectionLojas).doc(lojaId).get();
    if (!lojaSnap.exists) {
      throw new HttpsError("not-found", "Loja não encontrada.");
    }
    const data = lojaSnap.data() ?? {};
    if (data.published === false) {
      throw new HttpsError("failed-precondition", "Loja não publicada.");
    }
    return data;
  }

  async function callSuperFreteMe(token, sandbox) {
    const url = `${SUPERFRETE_API_BASE}/api/v8/me`;
    const resp = await fetchImpl(
      url,
      {
        method: "GET",
        headers: {
          Accept: "application/json",
          Authorization: `Bearer ${token}`,
          "User-Agent": SUPERFRETE_USER_AGENT,
        },
      },
      15000,
    );

    if (resp.status === 401) {
      const err = new HttpsError(
        "permission-denied",
        "Token inválido ou expirado. Gere um novo token na SuperFrete e tente novamente.",
      );
      err.details = { code: "TOKEN_INVALIDO" };
      throw err;
    }

    if (!resp.ok) {
      logSuperFreteFail("TESTE", `status=${resp.status} code=HTTP_ERRO`);
      if (resp.status >= 500) {
        throw new HttpsError(
          "unavailable",
          "SuperFrete temporariamente indisponível. Tente novamente em alguns minutos.",
        );
      }
      throw new HttpsError(
        "internal",
        "Não foi possível validar o token na SuperFrete.",
      );
    }

    const txt = await resp.text();
    const trim = txt.trim().toLowerCase();
    if (trim.startsWith("<!") || trim.startsWith("<html")) {
      throw new HttpsError(
        "failed-precondition",
        "Resposta inválida da SuperFrete. Verifique o ambiente (sandbox/produção).",
      );
    }

    let data;
    try {
      data = JSON.parse(txt);
    } catch {
      throw new HttpsError("internal", "Resposta inválida da SuperFrete.");
    }

    const displayName =
      data?.name ?? data?.firstname ?? data?.email ?? undefined;
    return {
      displayName: displayName ? String(displayName) : undefined,
      sandbox,
    };
  }

  async function callSuperFreteCalculator(token, payload) {
    const url = `${SUPERFRETE_API_BASE}/api/v8/calculator`;
    const resp = await fetchImpl(
      url,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
          Accept: "application/json",
          "User-Agent": SUPERFRETE_USER_AGENT,
        },
        body: JSON.stringify(payload),
      },
      20000,
    );

    if (resp.status === 401) {
      throw new HttpsError(
        "permission-denied",
        "Integração SuperFrete precisa ser reconfigurada. Gere um novo token.",
      );
    }

    if (!resp.ok) {
      logSuperFreteFail("QUOTE", `status=${resp.status} code=HTTP_ERRO`);
      if (resp.status >= 500) {
        throw new HttpsError(
          "unavailable",
          "SuperFrete temporariamente indisponível. Tente novamente em alguns minutos.",
        );
      }
      throw new HttpsError("internal", "Erro ao consultar frete via SuperFrete.");
    }

    const body = await resp.text();
    const bodyTrim = body.trim().toLowerCase();
    if (bodyTrim.startsWith("<!") || bodyTrim.startsWith("<html")) {
      throw new HttpsError(
        "internal",
        "SuperFrete retornou resposta inválida. Verifique a integração.",
      );
    }

    return JSON.parse(body);
  }

  async function superFreteTestConnection() {
    const { lojaId, token, sandbox } = request.data ?? {};
    const { uid, lojaId: storeId } = await requireStoreAdmin(lojaId);
    const t = String(token ?? "").trim();
    if (!t) {
      throw new HttpsError("invalid-argument", "Informe o token da SuperFrete.");
    }

    const identifier = getCallableIdentifier(request);
    await checkRateLimit("superFreteTestConnection", identifier);

    logSuperFrete("TESTE", `INICIO lojaId=${storeId} uid=${uid}`);

    const sb = parseSandbox(sandbox);
    const me = await callSuperFreteMe(t, sb);

    return {
      ok: true,
      provider: "superfrete",
      displayName: me.displayName,
      sandbox: sb,
    };
  }

  async function superFreteSaveConfig() {
    const { lojaId, token, cepOrigem, sandbox } = request.data ?? {};
    const { uid, lojaId: storeId } = await requireStoreAdmin(lojaId);
    const t = String(token ?? "").trim();
    if (!t) {
      throw new HttpsError("invalid-argument", "Informe o token da SuperFrete.");
    }
    if (!isValidCep(cepOrigem)) {
      throw new HttpsError("invalid-argument", "Informe um CEP de origem válido.");
    }

    const identifier = getCallableIdentifier(request);
    await checkRateLimit("superFreteSaveConfig", identifier);

    const sb = parseSandbox(sandbox);
    logSuperFrete("SAVE", `INICIO lojaId=${storeId} uid=${uid}`);

    await callSuperFreteMe(t, sb);

    const lojaRef = db.collection(collectionLojas).doc(storeId);
    const publicRef = lojaRef.collection("config").doc(FRETES_PUBLIC_DOC);
    const secretsRef = lojaRef.collection("config").doc(FRETES_SECRETS_DOC);
    const draftRef = lojaRef.collection("draft_config").doc("config");

    const now = FieldValue.serverTimestamp();

    await db.runTransaction(async (tx) => {
      const pubSnap = await tx.get(publicRef);
      const pubBase = pubSnap.exists ? pubSnap.data() ?? {} : {};
      const cleaned = stripSuperFreteLegacyFromPublic(pubBase);

      const publicPatch = {
        ...cleaned,
        cepOrigem: normalizeCep(cepOrigem),
        integrations: {
          ...(cleaned.integrations ?? {}),
          superfrete: {
            configured: true,
            enabled: true,
            sandbox: sb,
          },
        },
        updatedAt: now,
      };

      delete publicPatch.superfrete;

      const legacyDeletes = {
        superfrete: FieldValue.delete(),
        superfrete_token: FieldValue.delete(),
        superfreteToken: FieldValue.delete(),
        apiToken: FieldValue.delete(),
      };

      tx.set(secretsRef, {
        schemaVersion: 1,
        superfrete: {
          token: t,
          sandbox: sb,
          updatedAt: now,
          updatedByUid: uid,
          lastValidatedAt: now,
          lastValidationStatus: "ok",
        },
      }, { merge: true });

      tx.set(publicRef, { ...publicPatch, ...legacyDeletes }, { merge: true });

      const draftSnap = await tx.get(draftRef);
      if (draftSnap.exists) {
        const draft = draftSnap.data() ?? {};
        const fc = { ...(draft.frete_config ?? {}) };
        delete fc.superfrete_token;
        delete fc.superfreteToken;
        tx.set(
          draftRef,
          {
            frete_config: {
              ...fc,
              cep_origem: normalizeCep(cepOrigem),
              superfrete_sandbox: sb,
              superfrete_configured: true,
              superfrete_token: FieldValue.delete(),
              superfreteToken: FieldValue.delete(),
            },
            updatedAt: now,
          },
          { merge: true },
        );
      }
    });

    return {
      ok: true,
      configured: true,
      maskedToken: maskToken(t),
      sandbox: sb,
    };
  }

  async function superFreteGetConfigStatus() {
    const { lojaId } = request.data ?? {};
    const { lojaId: storeId } = await requireStoreAdmin(lojaId);

    const identifier = getCallableIdentifier(request);
    await checkRateLimit("superFreteGetConfigStatus", identifier);

    const [publicFretes, draftFc, secrets] = await Promise.all([
      readPublicFretes(storeId),
      readDraftFreteConfig(storeId),
      readSecrets(storeId),
    ]);

    const legacy = detectLegacySuperFreteToken(publicFretes, draftFc);
    const integrations = publicFretes.integrations?.superfrete ?? {};
    const configured = !!secrets?.token || integrations.configured === true;

    let maskedToken = null;
    if (secrets?.token) {
      maskedToken = maskToken(secrets.token);
    } else if (legacy) {
      maskedToken = "••••????";
    }

    return {
      configured,
      sandbox: secrets?.sandbox ?? parseSandbox(integrations.sandbox),
      maskedToken,
      lastValidationStatus: secrets?.data?.lastValidationStatus ?? null,
      lastValidationAt: secrets?.data?.lastValidatedAt ?? null,
      legacyTokenNeedsRotation: legacy,
      enabled: integrations.enabled !== false,
    };
  }

  async function superFreteQuote() {
    const data = request.data ?? {};
    const lojaId = String(data.lojaId ?? "").trim();

    if (data.token) {
      throw new HttpsError(
        "invalid-argument",
        "Token não deve ser enviado na cotação.",
      );
    }

    if (!lojaId) {
      throw new HttpsError("invalid-argument", "Informe a loja.");
    }

    const identifier = `${getCallableIdentifier(request)}:${lojaId}`;
    await checkRateLimit("superFreteQuote", identifier);

    await assertStorePublishedForQuote(lojaId);

    const secrets = await readSecrets(lojaId);
    if (!secrets?.token) {
      return { sucesso: false, opcoes: [], erro: "SUPERFRETE_NAO_CONFIGURADO" };
    }

    const publicFretes = await readPublicFretes(lojaId);
    const cepOrigem =
      normalizeCep(data.cepOrigem) ||
      normalizeCep(publicFretes.cepOrigem) ||
      normalizeCep(publicFretes.cep_origem);

    const cepDestino =
      normalizeCep(data.destinationCep) ||
      normalizeCep(data.cepDestino) ||
      normalizeCep(data.cep);

    if (!isValidCep(cepOrigem) || !isValidCep(cepDestino)) {
      throw new HttpsError("invalid-argument", "CEP de origem ou destino inválido.");
    }

    const pkg = data.package && typeof data.package === "object" ? data.package : {};
    const peso =
      data.peso ??
      pkg.weightGrams ??
      pkg.peso ??
      publicFretes.pesoEmbalagem ??
      300;

    const payload = buildQuotePayload({
      cepOrigem,
      cepDestino,
      pesoGrams: peso,
      altura: data.altura ?? pkg.altura ?? 10,
      largura: data.largura ?? pkg.largura ?? 20,
      comprimento: data.comprimento ?? pkg.comprimento ?? 30,
      valorDeclarado:
        data.valorDeclarado ?? data.insuranceValue ?? pkg.valorDeclarado ?? 10,
    });

    logSuperFrete("QUOTE", `INICIO lojaId=${lojaId}`);

    const raw = await callSuperFreteCalculator(secrets.token, payload);
    const opcoes = mapQuoteResponse(raw);

    return { sucesso: true, opcoes };
  }

  /** Wrapper legado — rejeita token no payload. */
  async function calcularSuperFreteSecure() {
    const data = request.data ?? {};
    if (data.token) {
      logSuperFreteFail("QUOTE", "code=TOKEN_NO_PAYLOAD_REJEITADO");
      throw new HttpsError(
        "invalid-argument",
        "Token não deve ser enviado na cotação.",
      );
    }

    const lojaId = String(data.lojaId ?? "").trim();
    if (!lojaId) {
      throw new HttpsError(
        "invalid-argument",
        "Informe a loja para calcular frete via SuperFrete.",
      );
    }

    request.data = {
      lojaId,
      cepOrigem: data.cepOrigem,
      destinationCep: data.cepDestino ?? data.destinationCep,
      peso: data.peso,
      altura: data.altura,
      largura: data.largura,
      comprimento: data.comprimento,
      valorDeclarado: data.valorDeclarado,
    };

    return superFreteQuote();
  }

  async function superFreteCreateCheckout() {
    const data = request.data ?? {};
    const lojaId = String(data.lojaId ?? "").trim();
    await requireStoreAdmin(lojaId);

    const identifier = getCallableIdentifier(request);
    await checkRateLimit("superFreteCreateCheckout", identifier);

    const secrets = await readSecrets(lojaId);
    if (!secrets?.token) {
      throw new HttpsError(
        "failed-precondition",
        "SuperFrete não configurada para esta loja.",
      );
    }

    const servicoId = data.servicoId ?? data.service;
    if (servicoId == null) {
      throw new HttpsError("invalid-argument", "Serviço de frete inválido.");
    }

    const body = {
      service:
        typeof servicoId === "number"
          ? servicoId
          : parseInt(String(servicoId), 10) || 0,
      from: data.from,
      to: data.to,
      package: data.package,
      options: {
        insurance_value:
          Number(data.valorDeclarado) > 0 ? Number(data.valorDeclarado) : 10,
        receipt: false,
        own_hand: false,
      },
    };

    if (data.pedidoRef) {
      body.external_order_id = String(data.pedidoRef);
    }

    const url = `${SUPERFRETE_API_BASE}/api/v8/checkout`;
    const resp = await fetchImpl(
      url,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${secrets.token}`,
          Accept: "application/json",
          "User-Agent": SUPERFRETE_USER_AGENT,
        },
        body: JSON.stringify(body),
      },
      25000,
    );

    if (!resp.ok) {
      logSuperFreteFail("CHECKOUT", `status=${resp.status}`);
      throw new HttpsError("internal", "Não foi possível criar envio na SuperFrete.");
    }

    const parsed = await resp.json();
    return {
      sucesso: true,
      id: parsed.id,
      protocol: parsed.protocol ?? parsed.id,
      message: "Pedido adicionado ao carrinho da SuperFrete",
    };
  }

  return {
    superFreteTestConnection,
    superFreteSaveConfig,
    superFreteGetConfigStatus,
    superFreteQuote,
    calcularSuperFreteSecure,
    superFreteCreateCheckout,
  };
}
