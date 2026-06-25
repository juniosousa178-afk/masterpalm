/**
 * Integração segura Melhor Envio — token por loja em fretes_secrets (Admin SDK only).
 */

import { FieldValue } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import {
  FRETES_PUBLIC_DOC,
  FRETES_SECRETS_DOC,
  maskToken,
  normalizeCep,
  isValidCep,
} from "./superFreteIntegration.js";

export const MELHOR_ENVIO_API_BASE = "https://melhorenvio.com.br/api/v2";
export const MELHOR_ENVIO_SANDBOX_BASE = "https://sandbox.melhorenvio.com.br/api/v2";
export const MELHOR_ENVIO_USER_AGENT = "MasterPalm (contato@mastepalm.com.br)";

const LEGACY_ME_TOKEN_PATHS = [
  "melhor_envio_token",
  "melhorEnvioToken",
];

function logMelhorEnvio(phase, detail) {
  console.info(`[MELHOR_ENVIO][${phase}] ${detail}`);
}

function logMelhorEnvioFail(phase, detail) {
  console.warn(`[MELHOR_ENVIO][${phase}][FALHA] ${detail}`);
}

function parseSandbox(value) {
  return value === true || value === "true" || value === 1;
}

export function getMelhorEnvioApiBase(sandbox) {
  return parseSandbox(sandbox) ? MELHOR_ENVIO_SANDBOX_BASE : MELHOR_ENVIO_API_BASE;
}

/** Detecta token legado exposto em documentos públicos (não migra). */
export function detectLegacyMelhorEnvioToken(publicFretes = {}, draftFreteConfig = {}) {
  const pub = publicFretes && typeof publicFretes === "object" ? publicFretes : {};
  const draft =
    draftFreteConfig && typeof draftFreteConfig === "object"
      ? draftFreteConfig
      : {};

  const me = pub.melhorEnvio;
  if (me && typeof me === "object" && String(me.token ?? "").trim()) {
    return true;
  }

  for (const key of LEGACY_ME_TOKEN_PATHS) {
    if (String(pub[key] ?? "").trim()) return true;
    if (String(draft[key] ?? "").trim()) return true;
  }

  const fc = draft.frete_config;
  if (fc && typeof fc === "object" && String(fc.melhor_envio_token ?? "").trim()) {
    return true;
  }

  return false;
}

/** Remove campos legados de token do mapa público de fretes. */
export function stripMelhorEnvioLegacyFromPublic(data) {
  const out =
    data && typeof data === "object"
      ? JSON.parse(JSON.stringify(data))
      : {};

  if (out.melhorEnvio && typeof out.melhorEnvio === "object") {
    const me = { ...out.melhorEnvio };
    delete me.token;
    if (Object.keys(me).length === 0) {
      delete out.melhorEnvio;
    } else {
      out.melhorEnvio = me;
    }
  }

  for (const key of LEGACY_ME_TOKEN_PATHS) {
    delete out[key];
  }

  return out;
}

export function fretesPublicMelhorEnvioWriteSafe(data) {
  if (!data || typeof data !== "object") return true;
  return !detectLegacyMelhorEnvioToken(data, {});
}

export function buildMelhorEnvioHeaders(token) {
  return {
    Accept: "application/json",
    Authorization: `Bearer ${token}`,
    "Content-Type": "application/json",
    "User-Agent": MELHOR_ENVIO_USER_AGENT,
  };
}

async function callMelhorEnvioMe(token, sandbox, lojaId, fetchImpl) {
  const base = getMelhorEnvioApiBase(sandbox);
  const url = `${base}/me`;
  const resp = await fetchImpl(url, {
    method: "GET",
    headers: buildMelhorEnvioHeaders(token),
  });
  const text = await resp.text();
  if (resp.status === 401 || resp.status === 403) {
    logMelhorEnvioFail("TESTE", `lojaId=${lojaId} status=${resp.status} code=TOKEN_INVALIDO`);
    throw new HttpsError(
      "permission-denied",
      "Token inválido ou expirado. Gere um novo token no Melhor Envio e tente novamente.",
      { code: "TOKEN_INVALIDO" },
    );
  }
  if (resp.status === 429) {
    throw new HttpsError(
      "resource-exhausted",
      "Muitas tentativas em pouco tempo. Aguarde alguns minutos e tente novamente.",
      { code: "RATE_LIMIT" },
    );
  }
  if (resp.status >= 500) {
    throw new HttpsError(
      "unavailable",
      "Melhor Envio temporariamente indisponível. Tente novamente em alguns minutos.",
      { code: "API_INDISPONIVEL" },
    );
  }
  if (!resp.ok) {
    throw new HttpsError(
      "internal",
      "Não foi possível validar o token no Melhor Envio. Tente novamente.",
      { code: "ERRO_INTERNO_NAO_TRATADO" },
    );
  }
  try {
    return JSON.parse(text);
  } catch {
    throw new HttpsError(
      "internal",
      "Resposta inválida do Melhor Envio.",
      { code: "ERRO_INTERNO_NAO_TRATADO" },
    );
  }
}

export function createMelhorEnvioHandlers(deps) {
  const {
    db,
    canManageStoreConfigServerSide,
    checkRateLimit,
    getCallableIdentifier,
    fetchWithTimeout,
    collectionLojas,
    request,
  } = deps;

  async function requireStoreAdmin(lojaId) {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Faça login para continuar.");
    }
    const email = request.auth?.token?.email ?? "";
    const id = String(lojaId ?? "").trim();
    if (!id) {
      throw new HttpsError("invalid-argument", "Informe a loja.");
    }
    const allowed = await canManageStoreConfigServerSide({ lojaId: id, uid, email });
    if (!allowed) {
      throw new HttpsError(
        "permission-denied",
        "Sem permissão para configurar fretes desta loja.",
        { code: "PERMISSION_DENIED" },
      );
    }
    return { uid, lojaId: id };
  }

  async function readPublicFretes(lojaId) {
    const snap = await db
      .collection(collectionLojas)
      .doc(lojaId)
      .collection("config")
      .doc(FRETES_PUBLIC_DOC)
      .get();
    return snap.exists ? snap.data() ?? {} : {};
  }

  async function readDraftFreteConfig(lojaId) {
    const snap = await db
      .collection(collectionLojas)
      .doc(lojaId)
      .collection("draft_config")
      .doc("config")
      .get();
    if (!snap.exists) return {};
    const data = snap.data() ?? {};
    return data.frete_config && typeof data.frete_config === "object"
      ? data.frete_config
      : {};
  }

  async function readSecrets(lojaId) {
    const snap = await db
      .collection(collectionLojas)
      .doc(lojaId)
      .collection("config")
      .doc(FRETES_SECRETS_DOC)
      .get();
    if (!snap.exists) return null;
    const me = snap.data()?.melhor_envio;
    const token = String(me?.token ?? "").trim();
    if (!token) return null;
    return {
      token,
      sandbox: me?.sandbox === true,
      data: me,
    };
  }

  async function melhorEnvioTestConnection() {
    const { lojaId, token, sandbox } = request.data ?? {};
    const { uid, lojaId: storeId } = await requireStoreAdmin(lojaId);
    const t = String(token ?? "").trim();
    if (!t) {
      throw new HttpsError("invalid-argument", "Informe o token do Melhor Envio.");
    }

    const identifier = getCallableIdentifier(request);
    await checkRateLimit("melhorEnvioTestConnection", identifier);

    logMelhorEnvio("TESTE", `INICIO lojaId=${storeId} uid=${uid}`);
    const sb = parseSandbox(sandbox);
    const me = await callMelhorEnvioMe(t, sb, storeId, fetchWithTimeout);

    return {
      ok: true,
      provider: "melhor_envio",
      displayName: me.firstname ?? me.name ?? "Usuário",
      sandbox: sb,
    };
  }

  async function melhorEnvioSaveConfig() {
    const { lojaId, token, cepOrigem, sandbox } = request.data ?? {};
    const { uid, lojaId: storeId } = await requireStoreAdmin(lojaId);
    const t = String(token ?? "").trim();
    if (!t) {
      throw new HttpsError("invalid-argument", "Informe o token do Melhor Envio.");
    }
    if (!isValidCep(cepOrigem)) {
      throw new HttpsError("invalid-argument", "Informe um CEP de origem válido.");
    }

    const identifier = getCallableIdentifier(request);
    await checkRateLimit("melhorEnvioSaveConfig", identifier);

    const sb = parseSandbox(sandbox);
    logMelhorEnvio("SAVE", `INICIO lojaId=${storeId} uid=${uid}`);
    await callMelhorEnvioMe(t, sb, storeId, fetchWithTimeout);

    const lojaRef = db.collection(collectionLojas).doc(storeId);
    const publicRef = lojaRef.collection("config").doc(FRETES_PUBLIC_DOC);
    const secretsRef = lojaRef.collection("config").doc(FRETES_SECRETS_DOC);
    const draftRef = lojaRef.collection("draft_config").doc("config");
    const now = FieldValue.serverTimestamp();

    try {
      await db.runTransaction(async (tx) => {
        const pubSnap = await tx.get(publicRef);
        const draftSnap = await tx.get(draftRef);

        const pubBase = pubSnap.exists ? pubSnap.data() ?? {} : {};
        const cleaned = stripMelhorEnvioLegacyFromPublic(pubBase);

        const publicPatch = {
          ...cleaned,
          cepOrigem: normalizeCep(cepOrigem),
          integrations: {
            ...(cleaned.integrations ?? {}),
            melhor_envio: {
              configured: true,
              enabled: true,
              sandbox: sb,
            },
          },
          updatedAt: now,
        };

        const legacyDeletes = {
          melhorEnvio: FieldValue.delete(),
          melhor_envio_token: FieldValue.delete(),
          melhorEnvioToken: FieldValue.delete(),
        };

        tx.set(
          secretsRef,
          {
            schemaVersion: 1,
            melhor_envio: {
              token: t,
              sandbox: sb,
              updatedAt: now,
              updatedByUid: uid,
              lastValidatedAt: now,
              lastValidationStatus: "ok",
            },
          },
          { merge: true },
        );

        tx.set(publicRef, { ...publicPatch, ...legacyDeletes }, { merge: true });

        if (draftSnap.exists) {
          const draft = draftSnap.data() ?? {};
          const fc = { ...(draft.frete_config ?? {}) };
          delete fc.melhor_envio_token;
          tx.set(
            draftRef,
            {
              frete_config: {
                ...fc,
                cep_origem: normalizeCep(cepOrigem),
                melhor_envio_configured: true,
                melhor_envio_sandbox: sb,
                melhor_envio_token: FieldValue.delete(),
              },
              updatedAt: now,
            },
            { merge: true },
          );
        }
      });
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      logMelhorEnvioFail(
        "SAVE",
        `lojaId=${storeId} code=ERRO_AO_SALVAR_CONFIG type=${err?.name ?? "Error"}`,
      );
      throw new HttpsError(
        "internal",
        "Não foi possível salvar a configuração. Tente novamente.",
        { code: "ERRO_AO_SALVAR_CONFIG" },
      );
    }

    return {
      ok: true,
      configured: true,
      maskedToken: maskToken(t),
      sandbox: sb,
    };
  }

  async function melhorEnvioGetConfigStatus() {
    const { lojaId } = request.data ?? {};
    const { lojaId: storeId } = await requireStoreAdmin(lojaId);

    const identifier = getCallableIdentifier(request);
    await checkRateLimit("melhorEnvioGetConfigStatus", identifier);

    const [publicFretes, draftFc, secrets] = await Promise.all([
      readPublicFretes(storeId),
      readDraftFreteConfig(storeId),
      readSecrets(storeId),
    ]);

    const legacy = detectLegacyMelhorEnvioToken(publicFretes, { frete_config: draftFc });
    const integrations = publicFretes.integrations?.melhor_envio ?? {};
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

  return {
    melhorEnvioTestConnection,
    melhorEnvioSaveConfig,
    melhorEnvioGetConfigStatus,
  };
}

/** Lê token seguro do Melhor Envio (somente Admin SDK). */
export async function readMelhorEnvioSecrets(db, collectionLojas, lojaId) {
  const snap = await db
    .collection(collectionLojas)
    .doc(lojaId)
    .collection("config")
    .doc(FRETES_SECRETS_DOC)
    .get();
  if (!snap.exists) return null;
  const me = snap.data()?.melhor_envio;
  const token = String(me?.token ?? "").trim();
  if (!token) return null;
  return {
    token,
    sandbox: me?.sandbox === true,
  };
}
