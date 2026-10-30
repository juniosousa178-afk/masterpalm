/**
 * Exportação automática de envio (Melhor Envio / SuperFrete) após pedido confirmado.
 *
 * - Gatilho: transição do pré-pedido para `paid` (webhook MP, verificado pelo marcador
 *   `_mp_webhook_processed`) ou para `confirmado` com `vendaId` (lojista; update só admin nas rules).
 * - Serviço, preço, prazo e pacote vêm do recibo de cotação do servidor (`shipping_quotes`);
 *   nada do navegador define o que é enviado ao provedor.
 * - Idempotente: operationId `shipping:{provider}:{storeId}:{orderId}`, reserva transacional com lease.
 *   O Melhor Envio não documenta chave de idempotência nem busca por referência externa: um POST
 *   com resultado incerto vira `unknown` e só o lojista decide (verificou o carrinho) se reenvia.
 * - Sem compra de etiqueta; sem escrita de estoque, venda, pagamento ou total.
 * - Credenciais só da própria loja (`config/fretes_secrets`); nunca da plataforma.
 */

import { createHash } from "node:crypto";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import {
  FRETES_PUBLIC_DOC,
  FRETES_SECRETS_DOC,
  normalizeCep,
  isValidCep,
  detectLegacySuperFreteToken,
  buildCartPayload,
} from "./superFreteIntegration.js";
import {
  detectLegacyMelhorEnvioToken,
  getMelhorEnvioApiBase,
  buildMelhorEnvioHeaders,
} from "./melhorEnvioIntegration.js";
import {
  SHIPPING_PREORDER_COL,
  SHIPPING_PROVIDER,
  resolveShippingProviderFromOrder,
  executeSuperFreteCartPost,
  buildShippingPreOrderDocId,
} from "./shippingPreOrder.js";
import {
  SHIPPING_QUOTE_ERROR,
  SHIPPING_MODEL,
  SHIPPING_MODEL_VERSION,
  classifyShippingModel,
  loadCanonicalShippingQuote,
} from "./shippingQuoteReceipt.js";

export const SHIPPING_EXPORT_SCHEMA = 2;
export const SHIPPING_EXPORT_LEASE_MS = 5 * 60 * 1000;
export const SHIPPING_AUTO_EXPORT_CUTOVER_ENV = "SHIPPING_AUTO_EXPORT_CUTOVER_UTC";
/** Só UTC explícito (sufixo Z); sem fuso local implícito. */
export const SHIPPING_CUTOVER_UTC_PATTERN = "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(\\.\\d{1,3})?Z$";
const SHIPPING_CUTOVER_UTC_RE = new RegExp(SHIPPING_CUTOVER_UTC_PATTERN);
const WEBHOOK_PROCESSED_COL = "_mp_webhook_processed";
/** Contrato de exportação SuperFrete ainda não homologado para o MasterPalm. */
export const SUPERFRETE_MASTERPALM_EXPORT_CONTRACT_VERIFIED = false;

export const SHIPPING_EXPORT_STATUS = {
  PENDING: "pending",
  EXPORTING: "exporting",
  EXPORTED: "exported",
  FAILED: "failed",
  UNKNOWN: "unknown",
  NOT_REQUIRED: "not_required",
};

export const SHIPPING_EXPORT_ERROR = {
  PROVIDER_ACCOUNT_NOT_CONNECTED: "PROVIDER_ACCOUNT_NOT_CONNECTED",
  LEGACY_TOKEN_NEEDS_ROTATION: "LEGACY_TOKEN_NEEDS_ROTATION",
  PROVIDER_EXPORT_CONTRACT_NOT_VERIFIED: "PROVIDER_EXPORT_CONTRACT_NOT_VERIFIED",
  SHIPPING_DOCUMENT_DATA_REQUIRED: "SHIPPING_DOCUMENT_DATA_REQUIRED",
  SENDER_DATA_REQUIRED: "SENDER_DATA_REQUIRED",
  RECIPIENT_DATA_INCOMPLETE: "RECIPIENT_DATA_INCOMPLETE",
  PROVIDER_AUTH_FAILED: "PROVIDER_AUTH_FAILED",
  PROVIDER_VALIDATION_FAILED: "PROVIDER_VALIDATION_FAILED",
  PROVIDER_RATE_LIMITED: "PROVIDER_RATE_LIMITED",
  PROVIDER_UNAVAILABLE: "PROVIDER_UNAVAILABLE",
  PROVIDER_UNREACHABLE: "PROVIDER_UNREACHABLE",
  PROVIDER_RESPONSE_INVALID: "PROVIDER_RESPONSE_INVALID",
  EXPORT_FAILED: "EXPORT_FAILED",
  ...SHIPPING_QUOTE_ERROR,
};

export const SHIPPING_EXPORT_TRIGGER = {
  PAYMENT_APPROVED: "payment_approved",
  MERCHANT_CONFIRMED: "merchant_confirmed",
  MERCHANT_RETRY: "merchant_retry",
};

/** Decisão do lojista após conferir o carrinho do provedor (resultado incerto). */
export const SHIPPING_EXPORT_RESOLUTION = {
  NOT_IN_CART: "not_in_cart",
  ALREADY_IN_CART: "already_in_cart",
};

export const SHIPPING_AUTO_EXPORT_FLAG = {
  [SHIPPING_PROVIDER.MELHOR_ENVIO]: "shippingAutoExportMelhorEnvio",
  [SHIPPING_PROVIDER.SUPERFRETE]: "shippingAutoExportSuperFrete",
};

/** Status do pedido que já representam pedido confirmado (não disparam nova exportação). */
const CONFIRMED_ORDER_STATUSES = new Set([
  "confirmado",
  "paid",
  "pago",
  "aprovado",
  "embalando",
  "em_preparacao",
  "enviado",
  "entregue",
  "finalizado",
]);
const CANCELLED_ORDER_STATUSES = new Set(["cancelado", "cancelled", "canceled"]);
const NO_SHIPMENT_TIPOS = new Set(["retirada", "local", "combinar", "manual"]);
/** Erros de conexão em que a requisição não chegou ao provedor (nada pode ter sido criado). */
const PRE_CONNECT_ERROR_CODES = new Set(["ENOTFOUND", "EAI_AGAIN", "ECONNREFUSED", "UND_ERR_CONNECT_TIMEOUT"]);

const str = (v) => String(v ?? "").trim();
const digits = (v) => str(v).replace(/\D/g, "");
const normStatus = (v) => str(v).toLowerCase();

export function shippingExportOperationId(provider, storeId, orderId) {
  const p = str(provider);
  const s = str(storeId);
  const o = str(orderId);
  if (!p || !s || !o) return "";
  return `shipping:${p}:${s}:${o}`;
}

/** Documento do ledger (coleção `shipping_preorders`, escrita só via Admin SDK). */
export function shippingExportDocId(provider, orderId) {
  const p = str(provider);
  const o = str(orderId);
  if (!p || !o) return "";
  return `export_${p}_${o}`.slice(0, 150);
}

export function shortHash(value) {
  const v = str(value);
  if (!v) return null;
  return createHash("sha256").update(v).digest("hex").slice(0, 12);
}

export function emitShippingExportLog(fields) {
  const entry = {
    event: "SHIPPING_EXPORT",
    provider: fields.provider ?? null,
    storeHash: shortHash(fields.storeId),
    orderHash: shortHash(fields.orderId),
    operationHash: shortHash(fields.operationId),
    status: fields.status ?? null,
    providerStatus: fields.providerStatus ?? null,
    durationMs: fields.durationMs ?? null,
    errorCode: fields.errorCode ?? null,
    trigger: fields.trigger ?? null,
    reason: fields.reason ?? null,
  };
  console.log(JSON.stringify(entry));
}

export function parseShippingCutoverUtc(raw) {
  const s = str(raw);
  if (!s || !SHIPPING_CUTOVER_UTC_RE.test(s)) return null;
  const ms = Date.parse(s);
  return Number.isFinite(ms) ? ms : null;
}

/**
 * Só pedidos do modelo com recibo (`createTime >= corte`) exportam. Legado, corte ausente ou
 * `createTime` desconhecido nunca exportam (mesma classificação do pagamento).
 */
export function evaluateShippingCutover({ createTimeMs, cutoverMs }) {
  const { model, reason } = classifyShippingModel({ createTimeMs, cutoverMs });
  if (model === SHIPPING_MODEL.LEGACY) return { ok: false, reason: "historical_order" };
  if (reason !== "created_at_or_after_cutover") return { ok: false, reason };
  return { ok: true };
}

/**
 * Transição que confirma o pedido. Não confia em campos gravados na criação (create público):
 * só transições em update (rules: admin da loja ou Admin SDK).
 */
export function detectShippingExportTrigger(before = {}, after = {}) {
  const b = before && typeof before === "object" ? before : {};
  const a = after && typeof after === "object" ? after : {};
  const afterStatus = normStatus(a.status);
  const beforeStatus = normStatus(b.status);
  if (CANCELLED_ORDER_STATUSES.has(afterStatus)) return null;

  if (beforeStatus !== "paid" && afterStatus === "paid" && str(a.paymentId)) {
    return { trigger: SHIPPING_EXPORT_TRIGGER.PAYMENT_APPROVED, paymentId: str(a.paymentId) };
  }
  if (
    !CONFIRMED_ORDER_STATUSES.has(beforeStatus)
    && afterStatus === "confirmado"
    && str(a.vendaId)
  ) {
    return { trigger: SHIPPING_EXPORT_TRIGGER.MERCHANT_CONFIRMED };
  }
  return null;
}

/** Retirada / combinar / frete manual / sem provedor integrado → nada a exportar. */
export function classifyShippingRequirement(order = {}) {
  const status = normStatus(order.status);
  if (CANCELLED_ORDER_STATUSES.has(status)) {
    return { required: false, reason: "order_cancelled" };
  }
  const frete = order.frete && typeof order.frete === "object" ? order.frete : {};
  const tipo = normStatus(frete.tipo);
  if (NO_SHIPMENT_TIPOS.has(tipo)) return { required: false, reason: "no_shipment" };
  const provider = resolveShippingProviderFromOrder(order);
  if (!provider) return { required: false, reason: "provider_not_integrated" };
  return { required: true, provider };
}

function money(v) {
  const n = typeof v === "string" ? Number(v.replace(",", ".")) : Number(v);
  return Number.isFinite(n) && n >= 0 ? Math.round(n * 100) / 100 : null;
}

/** Remetente cadastrado pela loja (`fretes_secrets.sender`); nenhum valor padrão inventado. */
export function validateSender(raw) {
  const s = raw && typeof raw === "object" ? raw : {};
  const sender = {
    name: str(s.name),
    document: digits(s.document),
    companyDocument: digits(s.companyDocument),
    stateRegister: str(s.stateRegister).toUpperCase(),
    phone: digits(s.phone),
    postalCode: normalizeCep(s.postalCode),
    address: str(s.address),
    number: str(s.number),
    complement: str(s.complement),
    district: str(s.district),
    city: str(s.city),
    state: str(s.state).toUpperCase(),
    shippingDocument: str(s.shippingDocument) === "nota_fiscal" ? "nota_fiscal" : "declaracao_conteudo",
  };
  const hasDoc = sender.document.length === 11 || sender.companyDocument.length === 14;
  if (
    !sender.name
    || !hasDoc
    || !isValidCep(sender.postalCode)
    || !sender.address
    || !sender.number
    || !sender.district
    || !sender.city
    || sender.state.length !== 2
  ) {
    return { ok: false, code: SHIPPING_EXPORT_ERROR.SENDER_DATA_REQUIRED };
  }
  return { ok: true, sender };
}

/** Destinatário: o carrinho do Melhor Envio exige documento e bairro. */
export function buildRecipient(order = {}) {
  const cliente = order.cliente && typeof order.cliente === "object" ? order.cliente : {};
  const e = cliente.endereco && typeof cliente.endereco === "object" ? cliente.endereco : {};
  const recipient = {
    name: str(cliente.nome),
    document: digits(cliente.cpf),
    phone: digits(cliente.telefone),
    postalCode: normalizeCep(e.cep),
    address: str(e.rua ?? e.logradouro),
    number: str(e.numero),
    complement: str(e.complemento),
    district: str(e.bairro),
    city: str(e.cidade),
    state: str(e.estado ?? e.uf).toUpperCase(),
  };
  if (
    !recipient.name
    || (recipient.document.length !== 11 && recipient.document.length !== 14)
    || !isValidCep(recipient.postalCode)
    || !recipient.address
    || !recipient.number
    || !recipient.district
    || !recipient.city
    || recipient.state.length !== 2
  ) {
    return { ok: false, code: SHIPPING_EXPORT_ERROR.RECIPIENT_DATA_INCOMPLETE };
  }
  return { ok: true, recipient };
}

export function sanitizeProductName(raw) {
  const cleaned = String(raw ?? "")
    .replace(/[\u0000-\u001f\u007f]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 80);
  return cleaned || "Produto";
}

export function buildShipmentItems(order = {}) {
  const itens = Array.isArray(order.itens) ? order.itens : [];
  return itens
    .map((raw) => {
      const it = raw && typeof raw === "object" ? raw : {};
      const quantity = Math.max(1, Math.round(Number(it.quantidade ?? it.qty ?? 1) || 1));
      const unit = money(it.precoUnitario ?? it.preco)
        ?? (money(it.total) != null ? Math.round((money(it.total) / quantity) * 100) / 100 : 0);
      return { name: sanitizeProductName(it.nome ?? it.name), quantity, unitValue: unit };
    })
    .filter((it) => it.quantity > 0);
}

function validProviderPackage(pp) {
  if (!pp || typeof pp !== "object") return null;
  const pkg = {
    weight: Number(pp.weight),
    height: Number(pp.height),
    width: Number(pp.width),
    length: Number(pp.length),
  };
  return Object.values(pkg).every((v) => Number.isFinite(v) && v > 0) ? pkg : null;
}

/**
 * Modelo canônico independente do provedor. `quote` = recibo validado
 * (`loadCanonicalShippingQuote`); pacote e seguro são exatamente os cotados.
 */
export function buildShippingOrder({ order, storeId, orderId, provider, sender, quote }) {
  if (!quote || quote.provider !== provider) return { ok: false, code: SHIPPING_EXPORT_ERROR.MISSING };
  const pkg = validProviderPackage(quote.providerPackage);
  if (!pkg) return { ok: false, code: SHIPPING_EXPORT_ERROR.MISSING };
  const rec = buildRecipient(order);
  if (!rec.ok) return rec;
  const snd = validateSender(sender);
  if (!snd.ok) return snd;
  const nf = order.notaFiscal && typeof order.notaFiscal === "object" ? order.notaFiscal : {};
  const isInvoice = snd.sender.shippingDocument === "nota_fiscal";
  if (isInvoice && (digits(nf.chave).length !== 44 || !snd.sender.stateRegister
    || snd.sender.stateRegister === "ISENTO")) {
    return { ok: false, code: SHIPPING_EXPORT_ERROR.SHIPPING_DOCUMENT_DATA_REQUIRED };
  }
  const items = buildShipmentItems(order);
  if (items.length === 0) {
    return { ok: false, code: SHIPPING_EXPORT_ERROR.SHIPPING_DOCUMENT_DATA_REQUIRED };
  }
  return {
    ok: true,
    shippingOrder: {
      provider,
      storeId,
      orderId,
      operationId: shippingExportOperationId(provider, storeId, orderId),
      shippingQuoteId: quote.shippingQuoteId,
      serviceId: quote.serviceId,
      serviceName: quote.serviceName,
      carrierName: quote.carrierName,
      quotedPrice: quote.quotedPrice,
      quotedDeadlineDays: quote.deadlineDays,
      chargedPrice: quote.chargedPrice,
      package: pkg,
      recipient: rec.recipient,
      sender: snd.sender,
      items,
      insuranceValue: quote.insuranceValue,
      shippingDocument: snd.sender.shippingDocument,
      invoiceKey: isInvoice ? digits(nf.chave) : null,
    },
  };
}

/** Resumo exibido ao lojista (sem PII). Com recibo válido, dados vêm só do recibo. */
export function shippingSummaryFromOrder(order, provider, quote = null) {
  const frete = order.frete && typeof order.frete === "object" ? order.frete : {};
  if (quote) {
    return {
      provider,
      serviceId: quote.serviceId,
      serviceName: quote.serviceName ?? null,
      carrierName: quote.carrierName ?? null,
      price: quote.chargedPrice,
      quotedPrice: quote.quotedPrice,
      deadline: quote.deadlineDays ?? null,
      shippingQuoteId: quote.shippingQuoteId,
    };
  }
  return {
    provider,
    serviceId: str(frete.service_id ?? frete.servico_id) || null,
    serviceName: str(frete.nome) || null,
    carrierName: null,
    price: money(frete.valor),
    quotedPrice: null,
    deadline: null,
    shippingQuoteId: null,
  };
}

// ---------------------------------------------------------------------------
// Provedores
// ---------------------------------------------------------------------------

/**
 * `POST /api/v2/me/cart` (doc. "Inserir fretes no carrinho"): products com quantity/unitary_value
 * em string; volumes = pacote cotado; NF exige `options.invoice.key` + `from.state_register`.
 * `options.tags` é só identificação visível no painel (a API não busca por tag).
 */
export function buildMelhorEnvioCartRequest(so) {
  const isInvoice = so.shippingDocument === "nota_fiscal";
  const from = {
    name: so.sender.name,
    phone: so.sender.phone || undefined,
    address: so.sender.address,
    complement: so.sender.complement || undefined,
    number: so.sender.number,
    district: so.sender.district,
    city: so.sender.city,
    state_abbr: so.sender.state,
    country_id: "BR",
    postal_code: so.sender.postalCode,
    document: so.sender.document || undefined,
    company_document: so.sender.companyDocument || undefined,
    state_register: isInvoice ? so.sender.stateRegister : undefined,
  };

  const to = {
    name: so.recipient.name,
    phone: so.recipient.phone || undefined,
    document: so.recipient.document.length === 11 ? so.recipient.document : undefined,
    company_document: so.recipient.document.length === 14 ? so.recipient.document : undefined,
    address: so.recipient.address,
    complement: so.recipient.complement || undefined,
    number: so.recipient.number,
    district: so.recipient.district,
    city: so.recipient.city,
    state_abbr: so.recipient.state,
    country_id: "BR",
    postal_code: so.recipient.postalCode,
  };

  const options = {
    insurance_value: so.insuranceValue,
    receipt: false,
    own_hand: false,
    reverse: false,
    non_commercial: !isInvoice,
    platform: "MasterPalm",
    tags: [{ tag: so.operationId }],
  };
  if (isInvoice) options.invoice = { key: so.invoiceKey };

  return JSON.parse(JSON.stringify({
    service: Number(so.serviceId),
    from,
    to,
    products: so.items.map((it) => ({
      name: it.name,
      quantity: String(it.quantity),
      unitary_value: it.unitValue.toFixed(2),
    })),
    volumes: [{
      height: so.package.height,
      width: so.package.width,
      length: so.package.length,
      weight: so.package.weight,
    }],
    options,
  }));
}

export function buildSuperFreteCartRequest(so) {
  return buildCartPayload({
    servicoId: Number(so.serviceId),
    from: {
      name: so.sender.name,
      address: so.sender.address,
      number: so.sender.number,
      complement: so.sender.complement || undefined,
      district: so.sender.district,
      city: so.sender.city,
      state_abbr: so.sender.state,
      postal_code: so.sender.postalCode,
      document: so.sender.companyDocument || so.sender.document,
    },
    to: {
      name: so.recipient.name,
      address: so.recipient.address,
      number: so.recipient.number,
      complement: so.recipient.complement || undefined,
      district: so.recipient.district,
      city: so.recipient.city,
      state_abbr: so.recipient.state,
      postal_code: so.recipient.postalCode,
      document: so.recipient.document,
    },
    package: so.package,
    products: so.items.map((it) => ({
      name: it.name,
      quantity: it.quantity,
      unitary_value: it.unitValue,
    })),
    valorDeclarado: so.insuranceValue,
    pedidoRef: so.operationId,
  });
}

/** 4xx determinístico → falha (nada criado); 408/5xx/rede → resultado incerto. */
export function classifyProviderHttpStatus(status) {
  const s = Number(status) || 0;
  if (s === 401 || s === 403) return { outcome: "failed", code: SHIPPING_EXPORT_ERROR.PROVIDER_AUTH_FAILED };
  if (s === 429) return { outcome: "failed", code: SHIPPING_EXPORT_ERROR.PROVIDER_RATE_LIMITED };
  if (s === 408 || s >= 500 || s === 0) {
    return { outcome: "unknown", code: SHIPPING_EXPORT_ERROR.PROVIDER_UNAVAILABLE };
  }
  if (s >= 400) return { outcome: "failed", code: SHIPPING_EXPORT_ERROR.PROVIDER_VALIDATION_FAILED };
  return { outcome: "unknown", code: SHIPPING_EXPORT_ERROR.PROVIDER_RESPONSE_INVALID };
}

/** Exceção de rede: só erros de conexão comprovadamente anteriores ao envio são falha definitiva. */
export function classifyProviderNetworkError(err) {
  const code = str(err?.cause?.code ?? err?.code);
  if (PRE_CONNECT_ERROR_CODES.has(code)) {
    return { outcome: "failed", code: SHIPPING_EXPORT_ERROR.PROVIDER_UNREACHABLE };
  }
  return { outcome: "unknown", code: SHIPPING_EXPORT_ERROR.PROVIDER_UNAVAILABLE };
}

export async function postMelhorEnvioCart({ token, sandbox, body, fetchImpl }) {
  const base = getMelhorEnvioApiBase(sandbox);
  let resp;
  let text;
  try {
    resp = await fetchImpl(`${base}/me/cart`, {
      method: "POST",
      headers: buildMelhorEnvioHeaders(token),
      body: JSON.stringify(body),
    });
  } catch (err) {
    return { ...classifyProviderNetworkError(err), providerStatus: null };
  }
  try {
    text = await resp.text();
  } catch {
    return { outcome: "unknown", code: SHIPPING_EXPORT_ERROR.PROVIDER_UNAVAILABLE, providerStatus: resp.status };
  }
  if (!resp.ok) return { ...classifyProviderHttpStatus(resp.status), providerStatus: resp.status };
  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch {
    return { outcome: "unknown", code: SHIPPING_EXPORT_ERROR.PROVIDER_RESPONSE_INVALID, providerStatus: resp.status };
  }
  const id = str(parsed?.id);
  if (!id) {
    return { outcome: "unknown", code: SHIPPING_EXPORT_ERROR.PROVIDER_RESPONSE_INVALID, providerStatus: resp.status };
  }
  return { outcome: "exported", providerShipmentId: id, providerStatus: resp.status };
}

function readProviderCredentials(secretsDoc, provider) {
  const key = provider === SHIPPING_PROVIDER.MELHOR_ENVIO ? "melhor_envio" : "superfrete";
  const node = secretsDoc?.[key];
  const token = str(node?.token);
  if (!token) return null;
  return { token, sandbox: node?.sandbox === true };
}

/** Melhor Envio: um único POST por tentativa autorizada (sem consulta prévia por referência). */
export async function exportMelhorEnvio({ shippingOrder, credentials, fetchImpl }) {
  return postMelhorEnvioCart({
    token: credentials.token,
    sandbox: credentials.sandbox,
    body: buildMelhorEnvioCartRequest(shippingOrder),
    fetchImpl,
  });
}

/**
 * SuperFrete: contrato de exportação ainda não homologado para o MasterPalm.
 * Produção falha fechado; sandbox permite validar o payload.
 */
/** Sem contrato verificado não há POST, nem com token de sandbox. */
export async function exportSuperFrete({
  shippingOrder, credentials, fetchImpl, contractVerified = SUPERFRETE_MASTERPALM_EXPORT_CONTRACT_VERIFIED,
}) {
  if (contractVerified !== true) {
    return { outcome: "failed", code: SHIPPING_EXPORT_ERROR.PROVIDER_EXPORT_CONTRACT_NOT_VERIFIED };
  }
  const res = await executeSuperFreteCartPost({
    token: credentials.token,
    sandbox: credentials.sandbox,
    body: buildSuperFreteCartRequest(shippingOrder),
    fetchImpl,
  });
  if (res.outcome === "created") {
    return { outcome: "exported", providerShipmentId: res.providerCartId };
  }
  if (res.outcome === "failed") {
    const code = res.errorCode === "PROVIDER_NOT_CONFIGURED"
      ? SHIPPING_EXPORT_ERROR.PROVIDER_AUTH_FAILED
      : SHIPPING_EXPORT_ERROR.PROVIDER_VALIDATION_FAILED;
    return { outcome: "failed", code };
  }
  return { outcome: "unknown", code: SHIPPING_EXPORT_ERROR.PROVIDER_UNAVAILABLE };
}

// ---------------------------------------------------------------------------
// Estado / transações
// ---------------------------------------------------------------------------

function lojaRef(db, collectionLojas, storeId) {
  return db.collection(collectionLojas).doc(storeId);
}

function leaseActive(record, nowMs) {
  const until = record?.leaseUntil;
  if (!until) return false;
  const ms = typeof until.toMillis === "function" ? until.toMillis() : Number(until);
  return Number.isFinite(ms) && ms > nowMs;
}

/** `unknown`, ou `exporting` com lease vencido (processo caiu após o POST): resultado incerto. */
export function isUncertainExportRecord(record, nowMs) {
  const status = record?.status ?? null;
  if (status === SHIPPING_EXPORT_STATUS.UNKNOWN) return true;
  return status === SHIPPING_EXPORT_STATUS.EXPORTING && !leaseActive(record, nowMs);
}

/**
 * Reserva at-most-once. Gatilhos automáticos só criam a primeira tentativa.
 * Nova tentativa: só ação do lojista; após resultado incerto exige `resolution` explícita.
 */
export async function reserveShippingExport({
  db, collectionLojas, storeId, orderId, provider, trigger, summary, nowMs, resolution = null, actorUid = null,
}) {
  const ref = lojaRef(db, collectionLojas, storeId);
  const exportRef = ref.collection(SHIPPING_PREORDER_COL).doc(shippingExportDocId(provider, orderId));
  const legacyRef = ref.collection(SHIPPING_PREORDER_COL).doc(buildShippingPreOrderDocId(provider, orderId));
  const orderRef = ref.collection("pre_pedidos").doc(orderId);
  const operationId = shippingExportOperationId(provider, storeId, orderId);
  const isRetry = trigger === SHIPPING_EXPORT_TRIGGER.MERCHANT_RETRY;

  return db.runTransaction(async (tx) => {
    const exportSnap = await tx.get(exportRef);
    const legacySnap = await tx.get(legacyRef);
    const orderSnap = await tx.get(orderRef);
    if (!orderSnap.exists) return { action: "skip", reason: "order_not_found" };
    const order = orderSnap.data() || {};
    if (CANCELLED_ORDER_STATUSES.has(normStatus(order.status))) {
      return { action: "skip", reason: "order_cancelled" };
    }
    // Pedido do fluxo antigo (carrinho criado na criação do pré-pedido): nunca exporta de novo.
    if (legacySnap.exists || (order.shippingPreOrder && typeof order.shippingPreOrder === "object")) {
      return { action: "skip", reason: "legacy_preorder_exists" };
    }
    const existing = exportSnap.exists ? exportSnap.data() || {} : null;
    const status = existing?.status ?? null;

    if (status === SHIPPING_EXPORT_STATUS.EXPORTED) {
      return { action: "noop", record: existing, operationId };
    }
    if (status === SHIPPING_EXPORT_STATUS.EXPORTING && leaseActive(existing, nowMs)) {
      return { action: "skip", reason: "export_in_progress", record: existing, operationId };
    }
    if (existing && !isRetry) {
      return { action: "skip", reason: "already_attempted", record: existing, operationId };
    }
    const now = FieldValue.serverTimestamp();
    if (existing && isUncertainExportRecord(existing, nowMs)) {
      if (resolution === SHIPPING_EXPORT_RESOLUTION.ALREADY_IN_CART) {
        const state = {
          status: SHIPPING_EXPORT_STATUS.EXPORTED,
          operationId,
          providerShipmentId: null,
          reconciledManually: true,
          lastErrorCode: null,
          updatedAt: now,
          exportedAt: now,
        };
        tx.set(exportRef, {
          ...state,
          leaseUntil: null,
          resolution,
          resolvedByUid: actorUid,
        }, { merge: true });
        tx.set(orderRef, { shipping: { export: state } }, { merge: true });
        return { action: "resolved_manually", operationId };
      }
      if (resolution !== SHIPPING_EXPORT_RESOLUTION.NOT_IN_CART) {
        return { action: "skip", reason: "uncertain_requires_merchant_resolution", record: existing, operationId };
      }
    }

    const attempts = Number(existing?.attempts ?? 0) + 1;
    tx.set(exportRef, {
      schemaVersion: SHIPPING_EXPORT_SCHEMA,
      shippingModelVersion: SHIPPING_MODEL_VERSION,
      kind: "shipping_export",
      operationId,
      provider,
      orderId,
      storeId,
      status: SHIPPING_EXPORT_STATUS.EXPORTING,
      trigger,
      attempts,
      shippingQuoteId: summary?.shippingQuoteId ?? null,
      leaseUntil: Timestamp.fromMillis(nowMs + SHIPPING_EXPORT_LEASE_MS),
      lastAttemptAt: now,
      updatedAt: now,
      lastErrorCode: null,
      ...(resolution ? { resolution, resolvedByUid: actorUid } : {}),
      ...(existing ? {} : { createdAt: now }),
    }, { merge: true });
    tx.set(orderRef, {
      shipping: {
        ...summary,
        export: {
          status: SHIPPING_EXPORT_STATUS.EXPORTING,
          operationId,
          trigger,
          updatedAt: now,
          lastErrorCode: null,
        },
      },
    }, { merge: true });
    return { action: "reserved", operationId, attempts };
  });
}

export async function finalizeShippingExport({
  db, collectionLojas, storeId, orderId, provider, operationId, result,
}) {
  const ref = lojaRef(db, collectionLojas, storeId);
  const exportRef = ref.collection(SHIPPING_PREORDER_COL).doc(shippingExportDocId(provider, orderId));
  const orderRef = ref.collection("pre_pedidos").doc(orderId);
  const now = FieldValue.serverTimestamp();
  const exported = result.status === SHIPPING_EXPORT_STATUS.EXPORTED;
  const exportState = {
    status: result.status,
    operationId,
    providerShipmentId: result.providerShipmentId ?? null,
    lastErrorCode: exported ? null : result.errorCode ?? SHIPPING_EXPORT_ERROR.EXPORT_FAILED,
    updatedAt: now,
    ...(exported ? { exportedAt: now, reconciledManually: false } : {}),
  };
  await db.runTransaction(async (tx) => {
    tx.set(exportRef, { ...exportState, leaseUntil: null }, { merge: true });
    tx.set(orderRef, { shipping: { export: exportState } }, { merge: true });
  });
  return exportState;
}

async function readStoreShippingConfig(db, collectionLojas, storeId) {
  const ref = lojaRef(db, collectionLojas, storeId).collection("config");
  const [secretsSnap, publicSnap] = await Promise.all([
    ref.doc(FRETES_SECRETS_DOC).get(),
    ref.doc(FRETES_PUBLIC_DOC).get(),
  ]);
  return {
    secrets: secretsSnap.exists ? secretsSnap.data() || {} : {},
    publicFretes: publicSnap.exists ? publicSnap.data() || {} : {},
  };
}

export function isAutoExportEnabled(secretsDoc, provider) {
  const flag = SHIPPING_AUTO_EXPORT_FLAG[provider];
  return !!flag && secretsDoc?.automation?.[flag] === true;
}

/**
 * Exporta um pedido já confirmado. Nunca escreve estoque, venda, pagamento ou total.
 * `orderCreateTimeMs`: `createTime` do documento (servidor), usado na validade do recibo.
 */
export async function exportShippingOrder({
  db, collectionLojas, storeId, orderId, order, orderCreateTimeMs, trigger, fetchImpl,
  now = () => Date.now(), resolution = null, actorUid = null,
}) {
  const started = now();
  const req = classifyShippingRequirement(order);
  if (!req.required) return { skipped: true, reason: req.reason };
  const provider = req.provider;

  const { secrets, publicFretes } = await readStoreShippingConfig(db, collectionLojas, storeId);
  const manualResolution = resolution === SHIPPING_EXPORT_RESOLUTION.ALREADY_IN_CART;
  if (!manualResolution && !isAutoExportEnabled(secrets, provider)) {
    emitShippingExportLog({ provider, storeId, orderId, trigger, status: "skipped", reason: "feature_disabled" });
    return { skipped: true, reason: "feature_disabled" };
  }

  const quote = await loadCanonicalShippingQuote({
    db, collectionLojas, storeId, provider, order, orderCreateTimeMs, nowMs: now(),
  });

  const reserve = await reserveShippingExport({
    db,
    collectionLojas,
    storeId,
    orderId,
    provider,
    trigger,
    summary: shippingSummaryFromOrder(order, provider, quote.ok ? quote.quote : null),
    nowMs: now(),
    resolution,
    actorUid,
  });
  if (reserve.action === "noop") {
    return { ok: true, idempotent: true, status: SHIPPING_EXPORT_STATUS.EXPORTED, record: reserve.record };
  }
  if (reserve.action === "resolved_manually") {
    emitShippingExportLog({
      provider, storeId, orderId, operationId: reserve.operationId, trigger,
      status: SHIPPING_EXPORT_STATUS.EXPORTED, reason: "merchant_confirmed_in_cart",
    });
    return { ok: true, status: SHIPPING_EXPORT_STATUS.EXPORTED, reconciledManually: true };
  }
  if (reserve.action !== "reserved") return { skipped: true, reason: reserve.reason };

  const operationId = reserve.operationId;
  const finish = async (result, providerStatus = null) => {
    const state = await finalizeShippingExport({
      db, collectionLojas, storeId, orderId, provider, operationId, result,
    });
    emitShippingExportLog({
      provider,
      storeId,
      orderId,
      operationId,
      trigger,
      status: result.status,
      providerStatus,
      errorCode: state.lastErrorCode,
      durationMs: now() - started,
    });
    return { ok: result.status === SHIPPING_EXPORT_STATUS.EXPORTED, ...state };
  };

  const legacy = provider === SHIPPING_PROVIDER.MELHOR_ENVIO
    ? detectLegacyMelhorEnvioToken(publicFretes, {})
    : detectLegacySuperFreteToken(publicFretes, {});
  if (legacy) {
    return finish({ status: SHIPPING_EXPORT_STATUS.FAILED, errorCode: SHIPPING_EXPORT_ERROR.LEGACY_TOKEN_NEEDS_ROTATION });
  }
  const credentials = readProviderCredentials(secrets, provider);
  if (!credentials) {
    return finish({ status: SHIPPING_EXPORT_STATUS.FAILED, errorCode: SHIPPING_EXPORT_ERROR.PROVIDER_ACCOUNT_NOT_CONNECTED });
  }
  if (!quote.ok) {
    return finish({ status: SHIPPING_EXPORT_STATUS.FAILED, errorCode: quote.code });
  }

  const built = buildShippingOrder({
    order, storeId, orderId, provider, sender: secrets.sender, quote: quote.quote,
  });
  if (!built.ok) {
    return finish({ status: SHIPPING_EXPORT_STATUS.FAILED, errorCode: built.code });
  }

  let res;
  try {
    res = provider === SHIPPING_PROVIDER.MELHOR_ENVIO
      ? await exportMelhorEnvio({ shippingOrder: built.shippingOrder, credentials, fetchImpl })
      : await exportSuperFrete({ shippingOrder: built.shippingOrder, credentials, fetchImpl });
  } catch {
    res = { outcome: "unknown", code: SHIPPING_EXPORT_ERROR.PROVIDER_UNAVAILABLE };
  }

  if (res.outcome === "exported") {
    return finish(
      { status: SHIPPING_EXPORT_STATUS.EXPORTED, providerShipmentId: res.providerShipmentId },
      res.providerStatus ?? null,
    );
  }
  if (res.outcome === "failed") {
    return finish({ status: SHIPPING_EXPORT_STATUS.FAILED, errorCode: res.code }, res.providerStatus ?? null);
  }
  return finish({ status: SHIPPING_EXPORT_STATUS.UNKNOWN, errorCode: res.code }, res.providerStatus ?? null);
}

/** Pagamento aprovado só vale com o marcador transacional do webhook (Admin SDK). */
export async function verifyPaymentApprovedMarker(db, { paymentId, storeId, orderId }) {
  const id = str(paymentId);
  if (!id || id.includes("/")) return false;
  const snap = await db.collection(WEBHOOK_PROCESSED_COL).doc(id).get();
  if (!snap.exists) return false;
  const m = snap.data() || {};
  return m.status === "applied" && str(m.lojaId) === storeId && str(m.orderId) === orderId;
}

/**
 * Quem gravou `status: confirmado` precisa ser dono/admin desta loja (ou backend via Admin SDK).
 * Repete no servidor o que as rules já exigem (`isStoreAdmin(lojaId)`), pelo `authId` do evento.
 */
export async function authorizeMerchantConfirmation({ authType, authId, storeId, isStoreAdminUid }) {
  if (authType === "service_account") return { ok: true };
  if (authType === "unauthenticated") return { ok: false, reason: "merchant_confirmation_unauthenticated" };
  const uid = str(authId);
  if (!uid || typeof isStoreAdminUid !== "function") {
    return { ok: false, reason: "merchant_confirmation_actor_unknown" };
  }
  let allowed = false;
  try {
    allowed = (await isStoreAdminUid(storeId, uid)) === true;
  } catch {
    allowed = false;
  }
  return allowed ? { ok: true } : { ok: false, reason: "merchant_confirmation_not_store_admin" };
}

/**
 * Trigger `onDocumentUpdatedWithAuthContext` de `pre_pedidos`.
 * Confirmação do lojista só vale se o autor do evento for admin da mesma loja.
 */
export async function handlePrePedidoShippingExportUpdate({
  db, collectionLojas, storeId, orderId, before, after, createTimeMs, cutoverMs, fetchImpl, now,
  authType = null, authId = null, isStoreAdminUid = null,
}) {
  const detected = detectShippingExportTrigger(before, after);
  if (!detected) return { skipped: true, reason: "no_confirmation_transition" };
  const req = classifyShippingRequirement(after);
  if (!req.required) return { skipped: true, reason: req.reason };

  const skip = (reason) => {
    emitShippingExportLog({
      provider: req.provider, storeId, orderId, trigger: detected.trigger, status: "skipped", reason,
    });
    return { skipped: true, reason };
  };

  const cut = evaluateShippingCutover({ createTimeMs, cutoverMs });
  if (!cut.ok) return skip(cut.reason);

  if (detected.trigger === SHIPPING_EXPORT_TRIGGER.MERCHANT_CONFIRMED) {
    const auth = await authorizeMerchantConfirmation({ authType, authId, storeId, isStoreAdminUid });
    if (!auth.ok) return skip(auth.reason);
  }

  if (detected.trigger === SHIPPING_EXPORT_TRIGGER.PAYMENT_APPROVED) {
    const verified = await verifyPaymentApprovedMarker(db, { paymentId: detected.paymentId, storeId, orderId });
    if (!verified) return skip("payment_marker_not_verified");
  }

  return exportShippingOrder({
    db,
    collectionLojas,
    storeId,
    orderId,
    order: after,
    orderCreateTimeMs: createTimeMs,
    trigger: detected.trigger,
    fetchImpl,
    now,
  });
}

// ---------------------------------------------------------------------------
// Callables (lojista)
// ---------------------------------------------------------------------------

const SENDER_FIELDS = [
  "name", "document", "companyDocument", "stateRegister", "phone", "postalCode", "address",
  "number", "complement", "district", "city", "state", "shippingDocument",
];

function maskDigits(v) {
  const d = digits(v);
  return d.length >= 4 ? `••••${d.slice(-4)}` : d ? "••••" : "";
}

export function createShippingExportHandlers(deps) {
  const {
    db,
    collectionLojas,
    canManageStoreConfigServerSide,
    checkRateLimit,
    getCallableIdentifier,
    fetchWithTimeout,
    request,
    now = () => Date.now(),
    cutoverMs = null,
  } = deps;

  async function requireStoreAdmin(lojaId) {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Faça login para continuar.");
    const id = str(lojaId);
    if (!id) throw new HttpsError("invalid-argument", "Informe a loja.");
    const allowed = await canManageStoreConfigServerSide({
      lojaId: id,
      uid,
      email: request.auth?.token?.email ?? "",
      emailVerified: request.auth?.token?.email_verified === true,
    });
    if (!allowed) {
      throw new HttpsError("permission-denied", "Sem permissão para configurar fretes desta loja.", {
        code: "PERMISSION_DENIED",
      });
    }
    return { uid, lojaId: id };
  }

  /**
   * Nova tentativa pelo lojista. Estado lido só do ledger (Admin SDK); `order.shipping` é ignorado.
   * Resultado incerto exige `resolution`: `not_in_cart` (conferiu e não está → reenvia) ou
   * `already_in_cart` (já está → marca exportado sem novo POST).
   */
  async function retryShippingExport() {
    const { lojaId, orderId, resolution: rawResolution } = request.data ?? {};
    const { uid, lojaId: storeId } = await requireStoreAdmin(lojaId);
    const oid = str(orderId);
    if (!oid || oid.includes("/")) throw new HttpsError("invalid-argument", "Informe o pedido.");
    const resolution = rawResolution == null ? null : str(rawResolution);
    if (resolution && !Object.values(SHIPPING_EXPORT_RESOLUTION).includes(resolution)) {
      throw new HttpsError("invalid-argument", "Ação inválida.");
    }
    await checkRateLimit("retryShippingExport", getCallableIdentifier(request));

    const storeRef = lojaRef(db, collectionLojas, storeId);
    const snap = await storeRef.collection("pre_pedidos").doc(oid).get();
    if (!snap.exists) throw new HttpsError("not-found", "Pedido não encontrado.");
    const order = snap.data() || {};
    const createTimeMs = typeof snap.createTime?.toMillis === "function" ? snap.createTime.toMillis() : NaN;
    const cut = evaluateShippingCutover({ createTimeMs, cutoverMs });
    if (!cut.ok) {
      throw new HttpsError("failed-precondition", "Este pedido não usa o envio automático.", {
        code: "SHIPPING_EXPORT_LEGACY_ORDER",
      });
    }
    const provider = resolveShippingProviderFromOrder(order);
    const ledgerSnap = provider
      ? await storeRef.collection(SHIPPING_PREORDER_COL).doc(shippingExportDocId(provider, oid)).get()
      : null;
    const ledger = ledgerSnap?.exists ? ledgerSnap.data() || {} : null;
    const nowMs = now();
    const uncertain = ledger ? isUncertainExportRecord(ledger, nowMs) : false;
    if (ledger?.status !== SHIPPING_EXPORT_STATUS.FAILED && !uncertain) {
      throw new HttpsError("failed-precondition", "Este frete não está aguardando nova tentativa.", {
        code: "SHIPPING_EXPORT_NOT_RETRYABLE",
      });
    }
    if (uncertain && !resolution) {
      throw new HttpsError(
        "failed-precondition",
        "Verifique o carrinho do provedor e informe se o envio já está lá antes de tentar novamente.",
        { code: "SHIPPING_EXPORT_RESOLUTION_REQUIRED" },
      );
    }
    if (!CONFIRMED_ORDER_STATUSES.has(normStatus(order.status))) {
      throw new HttpsError("failed-precondition", "O pedido ainda não está confirmado.", {
        code: "ORDER_NOT_CONFIRMED",
      });
    }
    const result = await exportShippingOrder({
      db,
      collectionLojas,
      storeId,
      orderId: oid,
      order,
      orderCreateTimeMs: createTimeMs,
      trigger: SHIPPING_EXPORT_TRIGGER.MERCHANT_RETRY,
      fetchImpl: fetchWithTimeout,
      now,
      resolution: uncertain ? resolution : null,
      actorUid: uid,
    });
    return {
      ok: result.ok === true,
      status: result.status ?? null,
      reason: result.reason ?? null,
      errorCode: result.lastErrorCode ?? null,
    };
  }

  async function shippingGetAutomationConfig() {
    const { lojaId } = request.data ?? {};
    const { lojaId: storeId } = await requireStoreAdmin(lojaId);
    await checkRateLimit("shippingGetAutomationConfig", getCallableIdentifier(request));
    const snap = await lojaRef(db, collectionLojas, storeId).collection("config").doc(FRETES_SECRETS_DOC).get();
    const data = snap.exists ? snap.data() || {} : {};
    const s = data.sender && typeof data.sender === "object" ? data.sender : {};
    return {
      flags: {
        melhorEnvio: data.automation?.shippingAutoExportMelhorEnvio === true,
        superFrete: data.automation?.shippingAutoExportSuperFrete === true,
      },
      superFreteExportContractVerified: SUPERFRETE_MASTERPALM_EXPORT_CONTRACT_VERIFIED,
      sender: {
        name: str(s.name),
        documentMasked: maskDigits(s.document),
        companyDocumentMasked: maskDigits(s.companyDocument),
        stateRegister: str(s.stateRegister),
        phone: str(s.phone),
        postalCode: str(s.postalCode),
        address: str(s.address),
        number: str(s.number),
        complement: str(s.complement),
        district: str(s.district),
        city: str(s.city),
        state: str(s.state),
        shippingDocument: str(s.shippingDocument) || "declaracao_conteudo",
      },
      senderComplete: validateSender(s).ok,
    };
  }

  async function shippingSaveAutomationConfig() {
    const { lojaId, sender, flags } = request.data ?? {};
    const { uid, lojaId: storeId } = await requireStoreAdmin(lojaId);
    await checkRateLimit("shippingSaveAutomationConfig", getCallableIdentifier(request));
    if (flags && typeof flags === "object" && flags.superFrete === true
      && !SUPERFRETE_MASTERPALM_EXPORT_CONTRACT_VERIFIED) {
      throw new HttpsError(
        "failed-precondition",
        "Exportação automática para a SuperFrete ainda em homologação.",
        { code: SHIPPING_EXPORT_ERROR.PROVIDER_EXPORT_CONTRACT_NOT_VERIFIED },
      );
    }
    const secretsRef = lojaRef(db, collectionLojas, storeId).collection("config").doc(FRETES_SECRETS_DOC);

    await db.runTransaction(async (tx) => {
      const snap = await tx.get(secretsRef);
      const current = snap.exists ? snap.data() || {} : {};
      const patch = { updatedAt: FieldValue.serverTimestamp() };
      if (sender && typeof sender === "object") {
        const prev = current.sender && typeof current.sender === "object" ? current.sender : {};
        const next = { ...prev };
        for (const k of SENDER_FIELDS) {
          if (!(k in sender)) continue;
          const v = str(sender[k]).slice(0, 120);
          if ((k === "document" || k === "companyDocument") && v.includes("•")) continue;
          next[k] = v;
        }
        const checked = validateSender(next);
        if (!checked.ok) {
          throw new HttpsError("invalid-argument", "Dados do remetente incompletos.", {
            code: SHIPPING_EXPORT_ERROR.SENDER_DATA_REQUIRED,
          });
        }
        patch.sender = { ...checked.sender, updatedAt: FieldValue.serverTimestamp(), updatedByUid: uid };
      }
      if (flags && typeof flags === "object") {
        const automation = { ...(current.automation ?? {}) };
        if (typeof flags.melhorEnvio === "boolean") automation.shippingAutoExportMelhorEnvio = flags.melhorEnvio;
        if (flags.superFrete === false) automation.shippingAutoExportSuperFrete = false;
        patch.automation = { ...automation, updatedAt: FieldValue.serverTimestamp(), updatedByUid: uid };
      }
      tx.set(secretsRef, patch, { merge: true });
    });
    return { ok: true };
  }

  return { retryShippingExport, shippingGetAutomationConfig, shippingSaveAutomationConfig };
}
