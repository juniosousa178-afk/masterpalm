/**
 * Pré-pedido de envio (carrinho) — SuperFrete e Melhor Envio.
 * Idempotente; token somente no backend; sem compra de etiqueta.
 */

import { FieldValue } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import {
  buildCartPayload,
  buildSuperFreteHeaders,
  getSuperFreteApiBase,
  mapSuperFreteHttpError,
  parseSuperFreteResponseText,
  SUPERFRETE_CART_PATH,
  FRETES_PUBLIC_DOC,
  FRETES_SECRETS_DOC,
  normalizeCep,
  isValidCep,
  detectLegacySuperFreteToken,
} from "./superFreteIntegration.js";
import {
  detectLegacyMelhorEnvioToken,
  getMelhorEnvioApiBase,
  buildMelhorEnvioHeaders,
  readMelhorEnvioSecrets,
  MELHOR_ENVIO_USER_AGENT,
} from "./melhorEnvioIntegration.js";
import { Timestamp } from "firebase-admin/firestore";

export const SHIPPING_PREORDER_COL = "shipping_preorders";
export const SHIPPING_PREORDER_SCHEMA = 1;

export const SHIPPING_PROVIDER = {
  SUPERFRETE: "superfrete",
  MELHOR_ENVIO: "melhor_envio",
};

export const SHIPPING_PREORDER_STATUS = {
  PENDING: "pending",
  PROCESSING: "processing",
  CREATED: "created",
  FAILED: "failed",
  NEEDS_PRODUCT_DATA: "needs_product_data",
  EXTERNAL_STATE_UNKNOWN: "external_state_unknown",
};

export const SHIPPING_ERROR_CODE = {
  PRE_ORDER_CREATED: "PRE_ORDER_CREATED",
  PRODUCT_SHIPPING_DATA_MISSING: "PRODUCT_SHIPPING_DATA_MISSING",
  ADDRESS_INCOMPLETE: "ADDRESS_INCOMPLETE",
  PROVIDER_NOT_CONFIGURED: "PROVIDER_NOT_CONFIGURED",
  API_INDISPONIVEL: "API_INDISPONIVEL",
  RATE_LIMIT: "RATE_LIMIT",
  PRE_ORDER_FAILED: "PRE_ORDER_FAILED",
  PROVIDER_NOT_APPLICABLE: "PROVIDER_NOT_APPLICABLE",
  ORDER_CANCELLED: "ORDER_CANCELLED",
  LEGACY_TOKEN_NEEDS_ROTATION: "LEGACY_TOKEN_NEEDS_ROTATION",
  EXTERNAL_RECONCILIATION_UNAVAILABLE: "EXTERNAL_RECONCILIATION_UNAVAILABLE",
  SUPERFRETE_PREORDER_SANDBOX_ONLY: "SUPERFRETE_PREORDER_SANDBOX_ONLY",
};

/** Lease de processamento — evita POST paralelo (5 min). */
export const PROCESSING_LEASE_MS = 5 * 60 * 1000;

export function buildProviderReference(lojaId, orderId, provider) {
  const l = String(lojaId ?? "").trim();
  const o = String(orderId ?? "").trim();
  const p = String(provider ?? "").trim();
  if (!l || !o || !p) return "";
  return `masterpalm:${l}:${o}:${p}`;
}

export function isProcessingLeaseActive(record, nowMs = Date.now()) {
  if (!record || record.status !== SHIPPING_PREORDER_STATUS.PROCESSING) {
    return false;
  }
  const until = record.processingLeaseUntil;
  if (!until) return false;
  let ms = 0;
  if (typeof until.toMillis === "function") {
    ms = until.toMillis();
  } else if (typeof until._seconds === "number") {
    ms = until._seconds * 1000;
  } else if (typeof until === "number") {
    ms = until;
  }
  return ms > nowMs;
}

export const MELHOR_ENVIO_API_BASE = "https://melhorenvio.com.br/api/v2";

function logShipping(phase, detail) {
  console.info(`[SHIPPING_PREORDER][${phase}] ${detail}`);
}

function logShippingFail(phase, detail) {
  console.warn(`[SHIPPING_PREORDER][${phase}][FALHA] ${detail}`);
}

export function buildShippingPreOrderDocId(provider, orderId) {
  const p = String(provider ?? "").trim();
  const o = String(orderId ?? "").trim();
  if (!p || !o) return "";
  return `${p}_${o}`.slice(0, 150);
}

export function resolveShippingProviderFromOrder(orderData = {}) {
  const frete = orderData.frete && typeof orderData.frete === "object"
    ? orderData.frete
    : {};
  const plataforma = String(
    frete.plataforma ?? orderData.plataformaFrete?.plataforma ?? "",
  )
    .trim()
    .toLowerCase();

  if (plataforma === SHIPPING_PROVIDER.SUPERFRETE || plataforma === "superfrete") {
    return SHIPPING_PROVIDER.SUPERFRETE;
  }
  if (
    plataforma === SHIPPING_PROVIDER.MELHOR_ENVIO
    || plataforma === "melhor_envio"
    || plataforma === "melhorenvio"
  ) {
    return SHIPPING_PROVIDER.MELHOR_ENVIO;
  }
  return null;
}

export function shouldCreateExternalShippingPreOrder(orderData = {}) {
  const provider = resolveShippingProviderFromOrder(orderData);
  if (!provider) return false;

  const frete = orderData.frete ?? {};
  const tipo = String(frete.tipo ?? "").trim().toLowerCase();
  if (tipo === "retirada" || tipo === "local" || tipo === "manual") return false;

  const status = String(orderData.status ?? "").trim().toLowerCase();
  if (status === "cancelado" || status === "cancelled") return false;

  return true;
}

function safeStr(v, fallback = "") {
  const s = String(v ?? "").trim();
  return s || fallback;
}

export function validateOrderShippingEligibility(orderData = {}) {
  if (!shouldCreateExternalShippingPreOrder(orderData)) {
    return { ok: false, code: SHIPPING_ERROR_CODE.PROVIDER_NOT_APPLICABLE };
  }

  const status = String(orderData.status ?? "").trim().toLowerCase();
  if (status === "cancelado" || status === "cancelled") {
    return { ok: false, code: SHIPPING_ERROR_CODE.ORDER_CANCELLED };
  }

  const cliente = orderData.cliente && typeof orderData.cliente === "object"
    ? orderData.cliente
    : {};
  const endereco = cliente.endereco && typeof cliente.endereco === "object"
    ? cliente.endereco
    : {};

  const cep = normalizeCep(endereco.cep);
  if (!isValidCep(cep)) {
    return { ok: false, code: SHIPPING_ERROR_CODE.ADDRESS_INCOMPLETE };
  }

  const nome = safeStr(cliente.nome);
  if (!nome) {
    return { ok: false, code: SHIPPING_ERROR_CODE.ADDRESS_INCOMPLETE };
  }

  const rua = safeStr(endereco.rua, safeStr(endereco.logradouro));
  const cidade = safeStr(endereco.cidade);
  const estado = safeStr(endereco.estado, safeStr(endereco.uf, "SP"));
  if (!rua || !cidade || !estado) {
    return { ok: false, code: SHIPPING_ERROR_CODE.ADDRESS_INCOMPLETE };
  }

  const frete = orderData.frete ?? {};
  const provider = resolveShippingProviderFromOrder(orderData);
  const serviceId =
    frete.servico_id
    ?? frete.service_id
    ?? frete.servicoId
    ?? frete.serviceId;

  if (provider === SHIPPING_PROVIDER.SUPERFRETE && serviceId == null) {
    return { ok: false, code: SHIPPING_ERROR_CODE.PRE_ORDER_FAILED };
  }
  if (provider === SHIPPING_PROVIDER.MELHOR_ENVIO && serviceId == null) {
    return { ok: false, code: SHIPPING_ERROR_CODE.PRE_ORDER_FAILED };
  }

  return { ok: true, provider, cep, cliente, endereco, frete, serviceId };
}

export async function loadProductShippingMetrics(db, collectionLojas, lojaId, items = []) {
  const list = Array.isArray(items) ? items : [];
  let pesoTotalGrams = 0;
  let missingWeight = false;
  let maxEmbalagemSize = 0;
  let maxTipoEmbalagem = "padrao";

  for (const raw of list) {
    const item = raw && typeof raw === "object" ? raw : {};
    const qty = Math.max(1, Number(item.quantidade ?? item.qty ?? 1) || 1);
    let peso = Number(item.peso ?? item.pesoGrams ?? 0);

    if (peso <= 0) {
      const productId = safeStr(
        item.productId ?? item.id ?? item.produtosId,
      );
      if (productId) {
        try {
          const snap = await db
            .collection(collectionLojas)
            .doc(lojaId)
            .collection("produtos")
            .doc(productId)
            .get();
          if (snap.exists) {
            const p = snap.data() ?? {};
            peso = Number(p.peso ?? p.pesoGramas ?? 0);
            const tipoEmb = safeStr(p.tipoEmbalagem, "padrao");
            const embSize = Number(p.embalagemTamanho ?? 0);
            if (embSize > maxEmbalagemSize) {
              maxEmbalagemSize = embSize;
              maxTipoEmbalagem = tipoEmb;
            } else if (tipoEmb && tipoEmb !== "padrao") {
              maxTipoEmbalagem = tipoEmb;
            }
          }
        } catch {
          /* ignora leitura individual */
        }
      }
    }

    if (peso <= 0) {
      missingWeight = true;
    } else {
      pesoTotalGrams += peso * qty;
    }
  }

  return {
    pesoTotalGrams,
    missingWeight,
    maxTipoEmbalagem,
  };
}

export function pickEmbalagemFromConfig(fretesConfig = {}, tipoEmbalagem = "padrao") {
  const embalagens = Array.isArray(fretesConfig.embalagens)
    ? fretesConfig.embalagens
    : [];
  if (embalagens.length === 0) {
    return {
      altura: 10,
      largura: 20,
      comprimento: 30,
      pesoEmbalagem: 50,
    };
  }
  const found = embalagens.find(
    (e) => safeStr(e?.id) === safeStr(tipoEmbalagem),
  ) ?? embalagens[0];
  return {
    altura: Math.max(1, Number(found?.altura) || 10),
    largura: Math.max(1, Number(found?.largura) || 20),
    comprimento: Math.max(1, Number(found?.comprimento) || 30),
    pesoEmbalagem: Math.max(0, Number(found?.peso) || 50),
  };
}

export function computeShippingPackage(orderData, fretesConfig, productMetrics) {
  const envio = orderData.envio && typeof orderData.envio === "object"
    ? orderData.envio
    : {};

  if (
    Number(envio.pesoTotalGrams) > 0
    && Number(envio.altura) > 0
    && Number(envio.largura) > 0
    && Number(envio.comprimento) > 0
  ) {
    return {
      ok: true,
      pesoGrams: Number(envio.pesoTotalGrams),
      altura: Number(envio.altura),
      largura: Number(envio.largura),
      comprimento: Number(envio.comprimento),
      valorDeclarado: Number(orderData.total) > 0 ? Number(orderData.total) : 10,
    };
  }

  if (productMetrics.missingWeight || productMetrics.pesoTotalGrams <= 0) {
    return { ok: false, code: SHIPPING_ERROR_CODE.PRODUCT_SHIPPING_DATA_MISSING };
  }

  const emb = pickEmbalagemFromConfig(
    fretesConfig,
    productMetrics.maxTipoEmbalagem,
  );
  const pesoGrams = productMetrics.pesoTotalGrams + emb.pesoEmbalagem;

  return {
    ok: true,
    pesoGrams: Math.max(300, pesoGrams),
    altura: emb.altura,
    largura: emb.largura,
    comprimento: emb.comprimento,
    valorDeclarado: Number(orderData.total) > 0 ? Number(orderData.total) : 10,
  };
}

async function readPublicFretes(db, collectionLojas, lojaId) {
  const ref = db
    .collection(collectionLojas)
    .doc(lojaId)
    .collection("config")
    .doc(FRETES_PUBLIC_DOC);
  const snap = await ref.get();
  return snap.exists ? snap.data() ?? {} : {};
}

function readMelhorEnvioTokenFromPublic(fretesConfig = {}) {
  const direct = safeStr(fretesConfig?.melhorEnvio?.token);
  if (direct) return direct;
  return safeStr(
    fretesConfig.melhor_envio_token
    ?? fretesConfig.melhorEnvioToken,
  );
}

async function resolveMelhorEnvioAuth(db, collectionLojas, lojaId, fretesConfig) {
  const legacy = detectLegacyMelhorEnvioToken(fretesConfig, {});
  if (legacy) {
    throw Object.assign(new Error("Token legado Melhor Envio"), {
      safeCode: SHIPPING_ERROR_CODE.LEGACY_TOKEN_NEEDS_ROTATION,
    });
  }
  const secrets = await readMelhorEnvioSecrets(db, collectionLojas, lojaId);
  if (!secrets?.token) {
    throw Object.assign(new Error("Melhor Envio não configurado"), {
      safeCode: SHIPPING_ERROR_CODE.PROVIDER_NOT_CONFIGURED,
    });
  }
  return secrets;
}

function buildFromAddress(fretesConfig = {}) {
  const cepOrigem = normalizeCep(
    fretesConfig.cepOrigem ?? fretesConfig.cep_origem ?? "01310100",
  );
  return {
    postal_code: cepOrigem,
    address: safeStr(fretesConfig.enderecoOrigem, "Centro"),
    city: safeStr(fretesConfig.cidadeOrigem, "São Paulo"),
    state: safeStr(fretesConfig.estadoOrigem, "SP"),
    district: safeStr(fretesConfig.bairroOrigem, "Centro"),
    number: safeStr(fretesConfig.numeroOrigem, "S/N"),
  };
}

function buildSuperFreteCartRequest(orderData, eligibility, pkg, providerReference) {
  const { cliente, endereco } = eligibility;
  const frete = orderData.frete ?? {};
  const cepOrigem = normalizeCep(
    orderData.cepOrigem ?? frete.cepOrigem,
  );

  return buildCartPayload({
    servicoId: eligibility.serviceId,
    from: buildFromAddress({ cepOrigem }),
    to: {
      name: safeStr(cliente.nome, "Cliente"),
      phone: safeStr(cliente.telefone).replace(/\D/g, ""),
      email: safeStr(cliente.email),
      document: safeStr(cliente.cpf).replace(/\D/g, ""),
      postal_code: eligibility.cep,
      address: safeStr(endereco.rua, safeStr(endereco.logradouro, "S/N")),
      number: safeStr(endereco.numero, "S/N"),
      complement: safeStr(endereco.complemento),
      district: safeStr(endereco.bairro),
      city: safeStr(endereco.cidade),
      state: safeStr(endereco.estado, safeStr(endereco.uf, "SP")),
    },
    package: {
      height: pkg.altura,
      width: pkg.largura,
      length: pkg.comprimento,
      weight: Math.max(0.3, pkg.pesoGrams / 1000),
    },
    valorDeclarado: pkg.valorDeclarado,
    pedidoRef: providerReference,
  });
}

function buildMelhorEnvioCartBody(orderData, eligibility, pkg, providerReference, fretesConfig) {
  const { cliente, endereco } = eligibility;
  const orderLabel = String(providerReference ?? "").split(":")[2] || "pedido";
  const cepOrigem = normalizeCep(
    fretesConfig.cepOrigem ?? fretesConfig.cep_origem ?? "01310100",
  );
  const fromName = safeStr(fretesConfig.nomeLoja, "Loja");
  const fromCnpj = safeStr(fretesConfig.cnpjLoja).replace(/\D/g, "");

  const fromObj = {
    name: fromName,
    address: safeStr(fretesConfig.enderecoOrigem, "Centro"),
    number: safeStr(fretesConfig.numeroOrigem, "S/N"),
    district: safeStr(fretesConfig.bairroOrigem, "Centro"),
    city: safeStr(fretesConfig.cidadeOrigem, "São Paulo"),
    postal_code: cepOrigem,
    state_abbr: safeStr(fretesConfig.estadoOrigem, "SP"),
    state_register: fromCnpj ? "" : "",
    country_id: "BR",
    company_document: fromCnpj || "",
    document: "",
  };

  return {
    service: Number(eligibility.serviceId) || 1,
    from: fromObj,
    to: {
      name: safeStr(cliente.nome, "Cliente"),
      phone: safeStr(cliente.telefone).replace(/\D/g, ""),
      email: safeStr(cliente.email),
      document: safeStr(cliente.cpf).replace(/\D/g, ""),
      company_document: "",
      state_register: "ISENTO",
      postal_code: eligibility.cep,
      address: safeStr(endereco.rua, safeStr(endereco.logradouro, "S/N")),
      number: safeStr(endereco.numero, "S/N"),
      complement: safeStr(endereco.complemento),
      district: safeStr(endereco.bairro),
      city: safeStr(endereco.cidade),
      state_abbr: safeStr(endereco.estado, safeStr(endereco.uf, "SP")),
      country_id: "BR",
    },
    products: [
      {
        name: `Pedido ${orderLabel}`,
        quantity: 1,
        unitary_value: pkg.valorDeclarado,
      },
    ],
    volumes: [
      {
        height: Math.round(pkg.altura),
        width: Math.round(pkg.largura),
        length: Math.round(pkg.comprimento),
        weight: Math.max(0.1, pkg.pesoGrams / 1000),
      },
    ],
    options: {
      insurance_value: pkg.valorDeclarado,
      receipt: false,
      own_hand: false,
      collect: false,
      reverse: false,
      non_commercial: true,
      platform: "MasterPalm",
      tags: [{ tag: providerReference }],
    },
  };
}

function cartItemHasProviderReference(item, providerReference) {
  const tags = item?.tags;
  if (!Array.isArray(tags)) return false;
  return tags.some((t) => {
    if (typeof t === "string") return t === providerReference;
    if (t && typeof t === "object") {
      return String(t.tag ?? "") === providerReference;
    }
    return false;
  });
}

async function reconcileMelhorEnvioCartByReference({
  token,
  sandbox,
  providerReference,
  fetchImpl,
}) {
  const base = getMelhorEnvioApiBase(sandbox);
  let page = 1;
  let lastPage = 1;

  while (page <= lastPage && page <= 20) {
    const url = `${base}/me/cart?page=${page}`;
    const resp = await fetchImpl(url, {
      method: "GET",
      headers: buildMelhorEnvioHeaders(token),
    });
    const text = await resp.text();
    if (!resp.ok) {
      return null;
    }
    let parsed;
    try {
      parsed = JSON.parse(text);
    } catch {
      return null;
    }
    const items = Array.isArray(parsed?.data) ? parsed.data : [];
    for (const item of items) {
      if (cartItemHasProviderReference(item, providerReference)) {
        return {
          providerCartId: String(item.id ?? ""),
          providerReference: String(item.protocol ?? item.id ?? providerReference),
        };
      }
    }
    lastPage = Number(parsed?.last_page ?? 1) || 1;
    page += 1;
  }
  return null;
}

async function requestSuperFreteCart({ token, sandbox, body, lojaId, fetchImpl }) {
  const base = getSuperFreteApiBase(sandbox);
  const url = `${base}${SUPERFRETE_CART_PATH}`;
  const headers = buildSuperFreteHeaders(token);
  const resp = await fetchImpl(url, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
  const text = await resp.text();
  let parsed;
  try {
    parsed = parseSuperFreteResponseText("CHECKOUT", resp.status, text);
  } catch (err) {
    const mapped = mapSuperFreteHttpError(resp.status, err?.code);
    throw Object.assign(new Error(mapped.message), { safeCode: mapped.code });
  }
  if (!resp.ok) {
    const mapped = mapSuperFreteHttpError(resp.status);
    throw Object.assign(new Error(mapped.message), { safeCode: mapped.code });
  }
  return parsed;
}

async function requestMelhorEnvioCart({ token, sandbox, body, fetchImpl }) {
  const base = getMelhorEnvioApiBase(sandbox);
  const url = `${base}/me/cart`;
  const resp = await fetchImpl(url, {
    method: "POST",
    headers: buildMelhorEnvioHeaders(token),
    body: JSON.stringify(body),
  });
  const text = await resp.text();
  if (resp.status === 429) {
    throw Object.assign(new Error("Rate limit"), { safeCode: SHIPPING_ERROR_CODE.RATE_LIMIT });
  }
  if (resp.status >= 500) {
    throw Object.assign(new Error("API indisponível"), { safeCode: SHIPPING_ERROR_CODE.API_INDISPONIVEL });
  }
  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw Object.assign(new Error("Resposta inválida"), { safeCode: SHIPPING_ERROR_CODE.PRE_ORDER_FAILED });
  }
  if (!resp.ok) {
    throw Object.assign(new Error("Falha ao criar carrinho"), { safeCode: SHIPPING_ERROR_CODE.PRE_ORDER_FAILED });
  }
  return parsed;
}

export async function createSuperFretePreOrder({
  db,
  collectionLojas,
  lojaId,
  orderId,
  orderData,
  eligibility,
  pkg,
  providerReference,
  fetchImpl,
}) {
  const publicFretes = await readPublicFretes(db, collectionLojas, lojaId);
  if (detectLegacySuperFreteToken(publicFretes, {})) {
    throw Object.assign(new Error("Token legado SuperFrete"), {
      safeCode: SHIPPING_ERROR_CODE.LEGACY_TOKEN_NEEDS_ROTATION,
    });
  }
  const secrets = await readSuperFreteSecrets(db, collectionLojas, lojaId);
  if (!secrets?.token) {
    throw Object.assign(new Error("SuperFrete não configurada"), {
      safeCode: SHIPPING_ERROR_CODE.PROVIDER_NOT_CONFIGURED,
    });
  }
  const body = buildSuperFreteCartRequest(
    orderData,
    eligibility,
    pkg,
    providerReference,
  );
  const parsed = await requestSuperFreteCart({
    token: secrets.token,
    sandbox: secrets.sandbox,
    body,
    lojaId,
    fetchImpl,
  });
  return {
    providerCartId: String(parsed.id ?? ""),
    providerReference: providerReference || String(parsed.protocol ?? parsed.id ?? ""),
  };
}

export async function createMelhorEnvioPreOrder({
  db,
  collectionLojas,
  lojaId,
  orderId,
  orderData,
  eligibility,
  pkg,
  fretesConfig,
  providerReference,
  fetchImpl,
}) {
  const auth = await resolveMelhorEnvioAuth(db, collectionLojas, lojaId, fretesConfig);
  const body = buildMelhorEnvioCartBody(
    orderData,
    eligibility,
    pkg,
    providerReference,
    fretesConfig,
  );
  const parsed = await requestMelhorEnvioCart({
    token: auth.token,
    sandbox: auth.sandbox,
    body,
    fetchImpl,
  });
  return {
    providerCartId: String(parsed.id ?? ""),
    providerReference: String(parsed.protocol ?? parsed.id ?? providerReference),
  };
}

export async function reconcileMelhorEnvioPreOrder({
  db,
  collectionLojas,
  lojaId,
  fretesConfig,
  providerReference,
  fetchImpl,
}) {
  const auth = await resolveMelhorEnvioAuth(db, collectionLojas, lojaId, fretesConfig);
  return reconcileMelhorEnvioCartByReference({
    token: auth.token,
    sandbox: auth.sandbox,
    providerReference,
    fetchImpl,
  });
}

async function readSuperFreteSecrets(db, collectionLojas, lojaId) {
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
    sandbox: sf?.sandbox === true,
  };
}

function safeStatusMessage(code) {
  switch (code) {
    case SHIPPING_ERROR_CODE.PRE_ORDER_CREATED:
      return "Pré-pedido criado com sucesso.";
    case SHIPPING_ERROR_CODE.PRODUCT_SHIPPING_DATA_MISSING:
      return "Alguns produtos ainda não possuem peso ou medidas para gerar o envio.";
    case SHIPPING_ERROR_CODE.ADDRESS_INCOMPLETE:
      return "O endereço de entrega está incompleto.";
    case SHIPPING_ERROR_CODE.PROVIDER_NOT_CONFIGURED:
      return "Configure a integração de frete antes de criar o pré-pedido.";
    case SHIPPING_ERROR_CODE.API_INDISPONIVEL:
      return "A transportadora está temporariamente indisponível. Tente novamente mais tarde.";
    case SHIPPING_ERROR_CODE.RATE_LIMIT:
      return "Muitas tentativas em pouco tempo. Aguarde alguns minutos.";
    case SHIPPING_ERROR_CODE.PRE_ORDER_FAILED:
      return "Não foi possível criar o pré-pedido de envio.";
    case SHIPPING_ERROR_CODE.LEGACY_TOKEN_NEEDS_ROTATION:
      return "Configure um novo token de frete na tela de fretes antes de criar o pré-pedido.";
    case SHIPPING_ERROR_CODE.EXTERNAL_RECONCILIATION_UNAVAILABLE:
      return "Não foi possível confirmar automaticamente se o carrinho foi criado na SuperFrete. Confira o painel da SuperFrete antes de tentar qualquer novo envio.";
    case SHIPPING_ERROR_CODE.SUPERFRETE_PREORDER_SANDBOX_ONLY:
      return "Pré-pedido automático da SuperFrete está em homologação. O carrinho não foi criado automaticamente.";
    default:
      return "Não foi possível criar o pré-pedido de envio.";
  }
}

function isHtmlLikeResponse(text) {
  const trim = String(text ?? "").trim().toLowerCase();
  return trim.startsWith("<!") || trim.startsWith("<html");
}

function isSafeSuperFretePreOrderClientError(status) {
  const s = Number(status) || 0;
  return s >= 400 && s < 500 && s !== 408;
}

/**
 * POST carrinho SuperFrete — classifica resultado para at-most-once.
 * Nunca expõe token; não compra etiqueta.
 */
export async function executeSuperFreteCartPost({
  token,
  sandbox,
  body,
  fetchImpl,
}) {
  const base = getSuperFreteApiBase(sandbox);
  const url = `${base}${SUPERFRETE_CART_PATH}`;
  try {
    const resp = await fetchImpl(url, {
      method: "POST",
      headers: buildSuperFreteHeaders(token),
      body: JSON.stringify(body),
    });
    const text = await resp.text();

    if (isHtmlLikeResponse(text)) {
      return {
        outcome: "ambiguous",
        errorCode: SHIPPING_ERROR_CODE.API_INDISPONIVEL,
      };
    }

    let parsed;
    try {
      parsed = JSON.parse(text);
    } catch {
      if (resp.ok) {
        return {
          outcome: "ambiguous",
          errorCode: SHIPPING_ERROR_CODE.PRE_ORDER_FAILED,
        };
      }
      if (isSafeSuperFretePreOrderClientError(resp.status)) {
        const code = resp.status === 401 || resp.status === 403
          ? SHIPPING_ERROR_CODE.PROVIDER_NOT_CONFIGURED
          : SHIPPING_ERROR_CODE.PRE_ORDER_FAILED;
        return { outcome: "failed", errorCode: code };
      }
      return {
        outcome: "ambiguous",
        errorCode: SHIPPING_ERROR_CODE.API_INDISPONIVEL,
      };
    }

    if (resp.ok) {
      const cartId = String(parsed?.id ?? "").trim();
      if (!cartId) {
        return {
          outcome: "ambiguous",
          errorCode: SHIPPING_ERROR_CODE.PRE_ORDER_FAILED,
        };
      }
      return { outcome: "created", providerCartId: cartId };
    }

    if (isSafeSuperFretePreOrderClientError(resp.status)) {
      const code = resp.status === 401 || resp.status === 403
        ? SHIPPING_ERROR_CODE.PROVIDER_NOT_CONFIGURED
        : SHIPPING_ERROR_CODE.PRE_ORDER_FAILED;
      return { outcome: "failed", errorCode: code };
    }

    return {
      outcome: "ambiguous",
      errorCode: SHIPPING_ERROR_CODE.API_INDISPONIVEL,
    };
  } catch {
    return {
      outcome: "ambiguous",
      errorCode: SHIPPING_ERROR_CODE.API_INDISPONIVEL,
    };
  }
}

export function isSuperFreteAutomaticPostBlocked(record) {
  if (!record) return false;
  if (record.status === SHIPPING_PREORDER_STATUS.CREATED) return true;
  if (record.status === SHIPPING_PREORDER_STATUS.EXTERNAL_STATE_UNKNOWN) {
    return true;
  }
  if (
    record.status === SHIPPING_PREORDER_STATUS.PROCESSING
    && isProcessingLeaseActive(record)
  ) {
    return true;
  }
  return false;
}

export function isAdminShippingPreOrderRetryAllowed({
  provider,
  orderStatus,
  preRecord,
  leaseExpiredProcessing = false,
}) {
  if (orderStatus === SHIPPING_PREORDER_STATUS.EXTERNAL_STATE_UNKNOWN) {
    return false;
  }
  if (preRecord?.status === SHIPPING_PREORDER_STATUS.EXTERNAL_STATE_UNKNOWN) {
    return false;
  }
  if (provider === SHIPPING_PROVIDER.SUPERFRETE) {
    return (
      orderStatus === SHIPPING_PREORDER_STATUS.FAILED
      || orderStatus === SHIPPING_PREORDER_STATUS.NEEDS_PRODUCT_DATA
      || preRecord?.status === SHIPPING_PREORDER_STATUS.FAILED
      || preRecord?.status === SHIPPING_PREORDER_STATUS.NEEDS_PRODUCT_DATA
    );
  }
  return (
    orderStatus === SHIPPING_PREORDER_STATUS.FAILED
    || orderStatus === SHIPPING_PREORDER_STATUS.NEEDS_PRODUCT_DATA
    || (orderStatus === SHIPPING_PREORDER_STATUS.PROCESSING && leaseExpiredProcessing)
    || preRecord?.status === SHIPPING_PREORDER_STATUS.FAILED
    || preRecord?.status === SHIPPING_PREORDER_STATUS.NEEDS_PRODUCT_DATA
    || (preRecord?.status === SHIPPING_PREORDER_STATUS.PROCESSING && leaseExpiredProcessing)
  );
}

async function markShippingPreOrderDispatched({
  db,
  collectionLojas,
  lojaId,
  orderId,
  provider,
}) {
  const docId = buildShippingPreOrderDocId(provider, orderId);
  const ref = db
    .collection(collectionLojas)
    .doc(lojaId)
    .collection(SHIPPING_PREORDER_COL)
    .doc(docId);
  await ref.set(
    { dispatchedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() },
    { merge: true },
  );
}

export async function processSuperFreteShippingPreOrder({
  db,
  collectionLojas,
  lojaId,
  orderId,
  orderData,
  eligibility,
  pkg,
  providerReference,
  fetchImpl,
}) {
  const provider = SHIPPING_PROVIDER.SUPERFRETE;

  const publicFretes = await readPublicFretes(db, collectionLojas, lojaId);
  if (detectLegacySuperFreteToken(publicFretes, {})) {
    const summary = await finalizeShippingPreOrder({
      db,
      collectionLojas,
      lojaId,
      orderId,
      provider,
      result: {
        status: SHIPPING_PREORDER_STATUS.FAILED,
        providerReference,
        errorCode: SHIPPING_ERROR_CODE.LEGACY_TOKEN_NEEDS_ROTATION,
        errorMessage: safeStatusMessage(SHIPPING_ERROR_CODE.LEGACY_TOKEN_NEEDS_ROTATION),
      },
    });
    return { ok: false, ...summary };
  }

  const secrets = await readSuperFreteSecrets(db, collectionLojas, lojaId);
  if (!secrets?.token) {
    const summary = await finalizeShippingPreOrder({
      db,
      collectionLojas,
      lojaId,
      orderId,
      provider,
      result: {
        status: SHIPPING_PREORDER_STATUS.FAILED,
        providerReference,
        errorCode: SHIPPING_ERROR_CODE.PROVIDER_NOT_CONFIGURED,
        errorMessage: safeStatusMessage(SHIPPING_ERROR_CODE.PROVIDER_NOT_CONFIGURED),
      },
    });
    return { ok: false, ...summary };
  }

  if (secrets.sandbox !== true) {
    const summary = await finalizeShippingPreOrder({
      db,
      collectionLojas,
      lojaId,
      orderId,
      provider,
      result: {
        status: SHIPPING_PREORDER_STATUS.FAILED,
        providerReference,
        errorCode: SHIPPING_ERROR_CODE.SUPERFRETE_PREORDER_SANDBOX_ONLY,
        errorMessage: safeStatusMessage(
          SHIPPING_ERROR_CODE.SUPERFRETE_PREORDER_SANDBOX_ONLY,
        ),
      },
    });
    logShippingFail(
      "SUPERFRETE_SANDBOX_GATE",
      `lojaId=${lojaId} orderId=${orderId} code=${SHIPPING_ERROR_CODE.SUPERFRETE_PREORDER_SANDBOX_ONLY}`,
    );
    return { ok: false, ...summary };
  }

  const body = buildSuperFreteCartRequest(
    orderData,
    eligibility,
    pkg,
    providerReference,
  );

  await markShippingPreOrderDispatched({
    db,
    collectionLojas,
    lojaId,
    orderId,
    provider,
  });

  const postResult = await executeSuperFreteCartPost({
    token: secrets.token,
    sandbox: secrets.sandbox,
    body,
    fetchImpl,
  });

  if (postResult.outcome === "created") {
    const summary = await finalizeShippingPreOrder({
      db,
      collectionLojas,
      lojaId,
      orderId,
      provider,
      result: {
        status: SHIPPING_PREORDER_STATUS.CREATED,
        providerCartId: postResult.providerCartId,
        providerReference,
        confirmedAt: FieldValue.serverTimestamp(),
        errorCode: SHIPPING_ERROR_CODE.PRE_ORDER_CREATED,
        errorMessage: safeStatusMessage(SHIPPING_ERROR_CODE.PRE_ORDER_CREATED),
      },
    });
    logShipping(
      "OK",
      `lojaId=${lojaId} orderId=${orderId} provider=${provider} cartId=${postResult.providerCartId}`,
    );
    return { ok: true, ...summary };
  }

  if (postResult.outcome === "failed") {
    const summary = await finalizeShippingPreOrder({
      db,
      collectionLojas,
      lojaId,
      orderId,
      provider,
      result: {
        status: SHIPPING_PREORDER_STATUS.FAILED,
        providerReference,
        errorCode: postResult.errorCode ?? SHIPPING_ERROR_CODE.PRE_ORDER_FAILED,
        errorMessage: safeStatusMessage(
          postResult.errorCode ?? SHIPPING_ERROR_CODE.PRE_ORDER_FAILED,
        ),
      },
    });
    logShippingFail(
      "SUPERFRETE_FAIL",
      `lojaId=${lojaId} orderId=${orderId} code=${postResult.errorCode}`,
    );
    return { ok: false, ...summary };
  }

  const summary = await finalizeShippingPreOrder({
    db,
    collectionLojas,
    lojaId,
    orderId,
    provider,
    result: {
      status: SHIPPING_PREORDER_STATUS.EXTERNAL_STATE_UNKNOWN,
      providerReference,
      errorCode: SHIPPING_ERROR_CODE.EXTERNAL_RECONCILIATION_UNAVAILABLE,
      errorMessage: safeStatusMessage(
        SHIPPING_ERROR_CODE.EXTERNAL_RECONCILIATION_UNAVAILABLE,
      ),
    },
  });
  logShippingFail(
    "SUPERFRETE_AMBIGUO",
    `lojaId=${lojaId} orderId=${orderId} code=${SHIPPING_ERROR_CODE.EXTERNAL_RECONCILIATION_UNAVAILABLE}`,
  );
  return { ok: false, ...summary };
}

async function reserveShippingPreOrder({
  db,
  collectionLojas,
  lojaId,
  orderId,
  provider,
  forceRetry,
}) {
  const docId = buildShippingPreOrderDocId(provider, orderId);
  const providerReference = buildProviderReference(lojaId, orderId, provider);
  const preOrderRef = db
    .collection(collectionLojas)
    .doc(lojaId)
    .collection(SHIPPING_PREORDER_COL)
    .doc(docId);
  const orderRef = db
    .collection(collectionLojas)
    .doc(lojaId)
    .collection("pre_pedidos")
    .doc(orderId);

  return db.runTransaction(async (tx) => {
    const preSnap = await tx.get(preOrderRef);
    const orderSnap = await tx.get(orderRef);

    if (!orderSnap.exists) {
      return { action: "skip", reason: "order_not_found" };
    }

    const existing = preSnap.exists ? preSnap.data() ?? {} : null;
    if (existing?.status === SHIPPING_PREORDER_STATUS.CREATED) {
      return {
        action: "noop",
        docId,
        record: existing,
        providerReference: existing.providerReference ?? providerReference,
      };
    }

    if (
      existing?.status === SHIPPING_PREORDER_STATUS.PROCESSING
      && isProcessingLeaseActive(existing)
      && !forceRetry
    ) {
      return {
        action: "skip",
        reason: "already_processing",
        docId,
        record: existing,
        providerReference: existing.providerReference ?? providerReference,
      };
    }

    const leaseExpiredProcessing =
      existing?.status === SHIPPING_PREORDER_STATUS.PROCESSING
      && !isProcessingLeaseActive(existing);

    if (existing?.status === SHIPPING_PREORDER_STATUS.EXTERNAL_STATE_UNKNOWN) {
      return {
        action: "skip",
        reason: "external_state_unknown",
        docId,
        record: existing,
        providerReference: existing.providerReference ?? providerReference,
      };
    }

    const retryable = forceRetry
      || !existing
      || existing.status === SHIPPING_PREORDER_STATUS.FAILED
      || existing.status === SHIPPING_PREORDER_STATUS.NEEDS_PRODUCT_DATA
      || existing.status === SHIPPING_PREORDER_STATUS.PENDING
      || (leaseExpiredProcessing && provider !== SHIPPING_PROVIDER.SUPERFRETE);

    if (!retryable) {
      return {
        action: "skip",
        reason: "not_retryable",
        docId,
        record: existing,
        providerReference: existing?.providerReference ?? providerReference,
      };
    }

    const now = FieldValue.serverTimestamp();
    const leaseUntil = Timestamp.fromMillis(Date.now() + PROCESSING_LEASE_MS);
    const attempts = Number(existing?.attempts ?? 0) + 1;
    const patch = {
      schemaVersion: SHIPPING_PREORDER_SCHEMA,
      orderId,
      provider,
      providerReference: existing?.providerReference ?? providerReference,
      status: SHIPPING_PREORDER_STATUS.PROCESSING,
      processingLeaseUntil: leaseUntil,
      updatedAt: now,
      lastAttemptAt: now,
      attempts,
      errorCode: null,
      errorMessage: null,
    };

    if (!existing) {
      patch.createdAt = now;
    }

    tx.set(preOrderRef, patch, { merge: true });
    tx.set(
      orderRef,
      {
        shippingPreOrder: {
          provider,
          status: SHIPPING_PREORDER_STATUS.PROCESSING,
          providerReference: patch.providerReference,
          updatedAt: now,
        },
        updatedAt: now,
      },
      { merge: true },
    );

    return {
      action: "reserved",
      docId,
      preOrderRef,
      orderRef,
      providerReference: patch.providerReference,
      needsReconcile: leaseExpiredProcessing || forceRetry,
    };
  });
}

async function finalizeShippingPreOrder({
  db,
  collectionLojas,
  lojaId,
  orderId,
  provider,
  result,
}) {
  const docId = buildShippingPreOrderDocId(provider, orderId);
  const preOrderRef = db
    .collection(collectionLojas)
    .doc(lojaId)
    .collection(SHIPPING_PREORDER_COL)
    .doc(docId);
  const orderRef = db
    .collection(collectionLojas)
    .doc(lojaId)
    .collection("pre_pedidos")
    .doc(orderId);

  const now = FieldValue.serverTimestamp();
  const status = result.status;
  const summary = {
    provider,
    status,
    providerCartId: result.providerCartId ?? null,
    providerReference: result.providerReference ?? null,
    errorCode: result.errorCode ?? null,
    updatedAt: now,
  };

  await db.runTransaction(async (tx) => {
    tx.set(
      preOrderRef,
      {
        status,
        providerCartId: result.providerCartId ?? null,
        providerReference: result.providerReference ?? null,
        processingLeaseUntil: null,
        errorCode: result.errorCode ?? null,
        errorMessage: result.errorMessage ?? null,
        updatedAt: now,
        ...(result.confirmedAt != null ? { confirmedAt: result.confirmedAt } : {}),
        ...(result.manualConfirmationAudit
          ? { manualConfirmationAudit: result.manualConfirmationAudit }
          : {}),
      },
      { merge: true },
    );
    tx.set(
      orderRef,
      {
        shippingPreOrder: summary,
        updatedAt: now,
      },
      { merge: true },
    );
  });

  return summary;
}

/**
 * Processa criação de pré-pedido externo (idempotente).
 */
export async function processShippingPreOrder({
  db,
  collectionLojas,
  lojaId,
  orderId,
  orderData,
  fetchImpl,
  forceRetry = false,
}) {
  if (!shouldCreateExternalShippingPreOrder(orderData)) {
    logShipping("SKIP", `lojaId=${lojaId} orderId=${orderId} motivo=nao_aplicavel`);
    return { skipped: true, reason: SHIPPING_ERROR_CODE.PROVIDER_NOT_APPLICABLE };
  }

  const eligibility = validateOrderShippingEligibility(orderData);
  if (!eligibility.ok) {
    logShippingFail("VALIDACAO", `lojaId=${lojaId} orderId=${orderId} code=${eligibility.code}`);
    return { skipped: true, reason: eligibility.code };
  }

  const provider = eligibility.provider;
  const reserve = await reserveShippingPreOrder({
    db,
    collectionLojas,
    lojaId,
    orderId,
    provider,
    forceRetry,
  });

  if (reserve.action === "noop") {
    return {
      ok: true,
      status: SHIPPING_PREORDER_STATUS.CREATED,
      providerCartId: reserve.record?.providerCartId ?? null,
      idempotent: true,
    };
  }
  if (reserve.action === "skip") {
    return { skipped: true, reason: reserve.reason };
  }

  logShipping("INICIO", `lojaId=${lojaId} orderId=${orderId} provider=${provider}`);

  const providerReference =
    reserve.providerReference
    ?? buildProviderReference(lojaId, orderId, provider);

  try {
    const fretesConfig = await readPublicFretes(db, collectionLojas, lojaId);

    const productMetrics = await loadProductShippingMetrics(
      db,
      collectionLojas,
      lojaId,
      orderData.itens,
    );
    const pkg = computeShippingPackage(orderData, fretesConfig, productMetrics);

    if (!pkg.ok) {
      const summary = await finalizeShippingPreOrder({
        db,
        collectionLojas,
        lojaId,
        orderId,
        provider,
        result: {
          status: SHIPPING_PREORDER_STATUS.NEEDS_PRODUCT_DATA,
          providerReference,
          errorCode: pkg.code,
          errorMessage: safeStatusMessage(pkg.code),
        },
      });
      logShippingFail(
        "PRODUTO",
        `lojaId=${lojaId} orderId=${orderId} code=${pkg.code}`,
      );
      return { ok: false, ...summary };
    }

    if (provider === SHIPPING_PROVIDER.SUPERFRETE) {
      return processSuperFreteShippingPreOrder({
        db,
        collectionLojas,
        lojaId,
        orderId,
        orderData,
        eligibility,
        pkg,
        providerReference,
        fetchImpl,
      });
    }

    // Reconciliação externa Melhor Envio antes de POST.
    const reconciled = await reconcileMelhorEnvioPreOrder({
      db,
      collectionLojas,
      lojaId,
      fretesConfig,
      providerReference,
      fetchImpl,
    });
    if (reconciled?.providerCartId) {
      const summary = await finalizeShippingPreOrder({
        db,
        collectionLojas,
        lojaId,
        orderId,
        provider,
        result: {
          status: SHIPPING_PREORDER_STATUS.CREATED,
          providerCartId: reconciled.providerCartId,
          providerReference: reconciled.providerReference ?? providerReference,
          errorCode: SHIPPING_ERROR_CODE.PRE_ORDER_CREATED,
          errorMessage: safeStatusMessage(SHIPPING_ERROR_CODE.PRE_ORDER_CREATED),
        },
      });
      logShipping(
        "RECONCILE",
        `lojaId=${lojaId} orderId=${orderId} provider=${provider} cartId=${reconciled.providerCartId}`,
      );
      return { ok: true, ...summary, reconciled: true };
    }

    const external = await createMelhorEnvioPreOrder({
      db,
      collectionLojas,
      lojaId,
      orderId,
      orderData,
      eligibility,
      pkg,
      fretesConfig,
      providerReference,
      fetchImpl,
    });

    const summary = await finalizeShippingPreOrder({
      db,
      collectionLojas,
      lojaId,
      orderId,
      provider,
      result: {
        status: SHIPPING_PREORDER_STATUS.CREATED,
        providerCartId: external.providerCartId,
        providerReference: external.providerReference ?? providerReference,
        errorCode: SHIPPING_ERROR_CODE.PRE_ORDER_CREATED,
        errorMessage: safeStatusMessage(SHIPPING_ERROR_CODE.PRE_ORDER_CREATED),
      },
    });

    logShipping(
      "OK",
      `lojaId=${lojaId} orderId=${orderId} provider=${provider} cartId=${external.providerCartId}`,
    );
    return { ok: true, ...summary };
  } catch (err) {
    const safeCode = err?.safeCode ?? SHIPPING_ERROR_CODE.PRE_ORDER_FAILED;
    const summary = await finalizeShippingPreOrder({
      db,
      collectionLojas,
      lojaId,
      orderId,
      provider,
      result: {
        status: safeCode === SHIPPING_ERROR_CODE.LEGACY_TOKEN_NEEDS_ROTATION
          || safeCode === SHIPPING_ERROR_CODE.PROVIDER_NOT_CONFIGURED
          ? SHIPPING_PREORDER_STATUS.FAILED
          : SHIPPING_PREORDER_STATUS.FAILED,
        providerReference,
        errorCode: safeCode,
        errorMessage: safeStatusMessage(safeCode),
      },
    });
    logShippingFail(
      "EXTERNO",
      `lojaId=${lojaId} orderId=${orderId} code=${safeCode} type=${err?.name ?? "Error"}`,
    );
    return { ok: false, ...summary };
  }
}

export function createShippingPreOrderHandlers(deps) {
  const {
    db,
    collectionLojas,
    canManageStoreConfigServerSide,
    checkRateLimit,
    getCallableIdentifier,
    fetchWithTimeout,
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

  async function retryShippingPreOrder() {
    const { lojaId, orderId } = request.data ?? {};
    await requireStoreAdmin(lojaId);
    const oid = String(orderId ?? "").trim();
    if (!oid) {
      throw new HttpsError("invalid-argument", "Informe o pedido.");
    }

    const identifier = getCallableIdentifier(request);
    await checkRateLimit("retryShippingPreOrder", identifier);

    const orderSnap = await db
      .collection(collectionLojas)
      .doc(lojaId)
      .collection("pre_pedidos")
      .doc(oid)
      .get();
    if (!orderSnap.exists) {
      throw new HttpsError("not-found", "Pedido não encontrado.");
    }

    const orderData = orderSnap.data() ?? {};
    const provider = resolveShippingProviderFromOrder(orderData);
    const current = orderData.shippingPreOrder?.status;
    const docId = buildShippingPreOrderDocId(provider ?? "", oid);
    const preSnap = await db
      .collection(collectionLojas)
      .doc(lojaId)
      .collection(SHIPPING_PREORDER_COL)
      .doc(docId)
      .get();
    const preRecord = preSnap.exists ? preSnap.data() ?? {} : {};
    const leaseExpired = isProcessingLeaseActive(preRecord) === false
      && preRecord.status === SHIPPING_PREORDER_STATUS.PROCESSING;

    if (
      preRecord.status === SHIPPING_PREORDER_STATUS.EXTERNAL_STATE_UNKNOWN
      || current === SHIPPING_PREORDER_STATUS.EXTERNAL_STATE_UNKNOWN
    ) {
      throw new HttpsError(
        "failed-precondition",
        "Não foi possível confirmar automaticamente se o carrinho foi criado na SuperFrete. Confira o painel da SuperFrete antes de tentar qualquer novo envio.",
        { code: "EXTERNAL_STATE_UNKNOWN" },
      );
    }

    if (
      !isAdminShippingPreOrderRetryAllowed({
        provider,
        orderStatus: current,
        preRecord,
        leaseExpiredProcessing: leaseExpired,
      })
    ) {
      throw new HttpsError(
        "failed-precondition",
        "Só é possível tentar novamente após falha ou dados pendentes.",
        { code: "PRE_ORDER_NOT_RETRYABLE" },
      );
    }

    const result = await processShippingPreOrder({
      db,
      collectionLojas,
      lojaId,
      orderId: oid,
      orderData,
      fetchImpl: fetchWithTimeout,
      forceRetry: true,
    });

    return {
      ok: result.ok === true,
      status: result.status ?? result.reason ?? null,
      providerCartId: result.providerCartId ?? null,
      errorCode: result.errorCode ?? null,
    };
  }

  async function confirmSuperFreteCartCreated() {
    const { lojaId, orderId, providerCartId } = request.data ?? {};
    const { uid } = await requireStoreAdmin(lojaId);
    const oid = String(orderId ?? "").trim();
    const cartId = String(providerCartId ?? "").trim();
    if (!oid) {
      throw new HttpsError("invalid-argument", "Informe o pedido.");
    }
    if (!cartId) {
      throw new HttpsError(
        "invalid-argument",
        "Informe o identificador do carrinho SuperFrete.",
      );
    }

    const identifier = getCallableIdentifier(request);
    await checkRateLimit("confirmSuperFreteCartCreated", identifier);

    const orderSnap = await db
      .collection(collectionLojas)
      .doc(lojaId)
      .collection("pre_pedidos")
      .doc(oid)
      .get();
    if (!orderSnap.exists) {
      throw new HttpsError("not-found", "Pedido não encontrado.");
    }

    const orderData = orderSnap.data() ?? {};
    const provider = resolveShippingProviderFromOrder(orderData);
    if (provider !== SHIPPING_PROVIDER.SUPERFRETE) {
      throw new HttpsError(
        "failed-precondition",
        "Confirmação manual só se aplica a pedidos SuperFrete.",
        { code: "PROVIDER_NOT_APPLICABLE" },
      );
    }

    const docId = buildShippingPreOrderDocId(SHIPPING_PROVIDER.SUPERFRETE, oid);
    const preSnap = await db
      .collection(collectionLojas)
      .doc(lojaId)
      .collection(SHIPPING_PREORDER_COL)
      .doc(docId)
      .get();
    const preRecord = preSnap.exists ? preSnap.data() ?? {} : {};

    if (preRecord.status === SHIPPING_PREORDER_STATUS.CREATED) {
      return {
        ok: true,
        status: SHIPPING_PREORDER_STATUS.CREATED,
        providerCartId: preRecord.providerCartId ?? cartId,
        idempotent: true,
      };
    }

    const providerReference =
      preRecord.providerReference
      ?? buildProviderReference(lojaId, oid, SHIPPING_PROVIDER.SUPERFRETE);

    const summary = await finalizeShippingPreOrder({
      db,
      collectionLojas,
      lojaId,
      orderId: oid,
      provider: SHIPPING_PROVIDER.SUPERFRETE,
      result: {
        status: SHIPPING_PREORDER_STATUS.CREATED,
        providerCartId: cartId,
        providerReference,
        confirmedAt: FieldValue.serverTimestamp(),
        errorCode: SHIPPING_ERROR_CODE.PRE_ORDER_CREATED,
        errorMessage: safeStatusMessage(SHIPPING_ERROR_CODE.PRE_ORDER_CREATED),
        manualConfirmationAudit: {
          confirmedByUid: uid,
          confirmedAt: FieldValue.serverTimestamp(),
          source: "admin_manual_cart_confirm",
        },
      },
    });

    logShipping(
      "MANUAL_CONFIRM",
      `lojaId=${lojaId} orderId=${oid} provider=superfrete cartId=${cartId}`,
    );

    return {
      ok: true,
      status: summary.status,
      providerCartId: cartId,
    };
  }

  return { retryShippingPreOrder, confirmSuperFreteCartCreated };
}

export async function onPrePedidoShippingPreOrderTrigger({
  db,
  collectionLojas,
  lojaId,
  orderId,
  orderData,
  fetchImpl,
}) {
  return processShippingPreOrder({
    db,
    collectionLojas,
    lojaId,
    orderId,
    orderData,
    fetchImpl,
  });
}
