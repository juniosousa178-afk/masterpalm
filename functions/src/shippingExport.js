/**
 * Exportação automática de envio (Melhor Envio / SuperFrete) após pedido confirmado.
 *
 * - Gatilho: transição do pré-pedido para `paid` (webhook MP, verificado pelo marcador
 *   `_mp_webhook_processed`) ou para `confirmado` com `vendaId` (lojista; update só admin nas rules).
 * - A seleção do frete no catálogo só grava o snapshot `frete.cotacao`; nunca chama o provedor.
 * - Idempotente: operationId `shipping:{provider}:{storeId}:{orderId}`, reserva transacional com lease,
 *   reconciliação no Melhor Envio (tag no carrinho) antes de qualquer novo POST.
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
} from "./shippingPreOrder.js";

export const SHIPPING_EXPORT_SCHEMA = 1;
export const SHIPPING_EXPORT_LEASE_MS = 5 * 60 * 1000;
export const SHIPPING_AUTO_EXPORT_CUTOVER_ENV = "SHIPPING_AUTO_EXPORT_CUTOVER_UTC";
const WEBHOOK_PROCESSED_COL = "_mp_webhook_processed";
const MELHOR_ENVIO_CART_MAX_PAGES = 20;

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
  UNSUPPORTED_BY_CURRENT_API: "UNSUPPORTED_BY_CURRENT_API",
  SHIPPING_DOCUMENT_DATA_REQUIRED: "SHIPPING_DOCUMENT_DATA_REQUIRED",
  SENDER_DATA_REQUIRED: "SENDER_DATA_REQUIRED",
  RECIPIENT_DATA_INCOMPLETE: "RECIPIENT_DATA_INCOMPLETE",
  QUOTE_SNAPSHOT_MISSING: "QUOTE_SNAPSHOT_MISSING",
  PROVIDER_AUTH_FAILED: "PROVIDER_AUTH_FAILED",
  PROVIDER_VALIDATION_FAILED: "PROVIDER_VALIDATION_FAILED",
  PROVIDER_RATE_LIMITED: "PROVIDER_RATE_LIMITED",
  PROVIDER_UNAVAILABLE: "PROVIDER_UNAVAILABLE",
  PROVIDER_RESPONSE_INVALID: "PROVIDER_RESPONSE_INVALID",
  EXPORT_FAILED: "EXPORT_FAILED",
};

export const SHIPPING_EXPORT_TRIGGER = {
  PAYMENT_APPROVED: "payment_approved",
  MERCHANT_CONFIRMED: "merchant_confirmed",
  MERCHANT_RETRY: "merchant_retry",
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
  if (!s) return null;
  const ms = Date.parse(s);
  return Number.isFinite(ms) ? ms : null;
}

/** Pedidos criados antes do corte (ou sem corte configurado) nunca exportam automaticamente. */
export function evaluateShippingCutover({ createTimeMs, cutoverMs }) {
  if (!Number.isFinite(cutoverMs)) return { ok: false, reason: "cutover_not_configured" };
  if (!Number.isFinite(createTimeMs)) return { ok: false, reason: "order_create_time_unknown" };
  if (createTimeMs < cutoverMs) return { ok: false, reason: "historical_order" };
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

function positiveNumber(v) {
  const n = typeof v === "string" ? Number(v.replace(",", ".")) : Number(v);
  return Number.isFinite(n) && n > 0 ? n : null;
}

function money(v) {
  const n = typeof v === "string" ? Number(v.replace(",", ".")) : Number(v);
  return Number.isFinite(n) && n >= 0 ? Math.round(n * 100) / 100 : null;
}

/** Snapshot gravado pelo checkout no momento da escolha do frete (não recalculado). */
export function readQuoteSnapshot(order = {}, provider) {
  const frete = order.frete && typeof order.frete === "object" ? order.frete : {};
  const c = frete.cotacao && typeof frete.cotacao === "object" ? frete.cotacao : null;
  if (!c) return { ok: false, code: SHIPPING_EXPORT_ERROR.QUOTE_SNAPSHOT_MISSING };
  const snapProvider = resolveShippingProviderFromOrder({ frete: { plataforma: c.provider } });
  if (snapProvider !== provider) {
    return { ok: false, code: SHIPPING_EXPORT_ERROR.QUOTE_SNAPSHOT_MISSING };
  }
  const serviceId = str(c.serviceId);
  const orderServiceId = str(frete.service_id ?? frete.servico_id ?? frete.serviceId);
  if (!serviceId || (orderServiceId && orderServiceId !== serviceId)) {
    return { ok: false, code: SHIPPING_EXPORT_ERROR.QUOTE_SNAPSHOT_MISSING };
  }
  const pacote = c.pacote && typeof c.pacote === "object" ? c.pacote : {};
  const pesoGramas = positiveNumber(pacote.pesoGramas);
  const altura = positiveNumber(pacote.alturaCm);
  const largura = positiveNumber(pacote.larguraCm);
  const comprimento = positiveNumber(pacote.comprimentoCm);
  if (!pesoGramas || !altura || !largura || !comprimento) {
    return { ok: false, code: SHIPPING_EXPORT_ERROR.QUOTE_SNAPSHOT_MISSING };
  }
  const quotedPrice = money(c.quotedPrice);
  if (quotedPrice == null) return { ok: false, code: SHIPPING_EXPORT_ERROR.QUOTE_SNAPSHOT_MISSING };
  const deadline = Number(c.quotedDeadlineDays);
  return {
    ok: true,
    snapshot: {
      provider,
      serviceId,
      serviceName: str(c.serviceName) || null,
      carrierName: str(c.carrierName) || null,
      companyId: str(c.companyId) || null,
      quoteId: str(c.quoteId) || null,
      quotedPrice,
      quotedDeadlineDays: Number.isFinite(deadline) && deadline > 0 ? Math.round(deadline) : null,
      chargedPrice: money(frete.valor),
      package: {
        weightGrams: pesoGramas,
        heightCm: altura,
        widthCm: largura,
        lengthCm: comprimento,
      },
    },
  };
}

/** Remetente cadastrado pela loja (`fretes_secrets.sender`); nenhum valor padrão inventado. */
export function validateSender(raw) {
  const s = raw && typeof raw === "object" ? raw : {};
  const sender = {
    name: str(s.name),
    document: digits(s.document),
    companyDocument: digits(s.companyDocument),
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
    || !isValidCep(recipient.postalCode)
    || !recipient.address
    || !recipient.number
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

/** Modelo canônico independente do provedor. */
export function buildShippingOrder({ order, storeId, orderId, provider, sender }) {
  const quote = readQuoteSnapshot(order, provider);
  if (!quote.ok) return quote;
  const rec = buildRecipient(order);
  if (!rec.ok) return rec;
  const snd = validateSender(sender);
  if (!snd.ok) return snd;
  if (snd.sender.shippingDocument === "nota_fiscal") {
    const nf = order.notaFiscal && typeof order.notaFiscal === "object" ? order.notaFiscal : {};
    if (digits(nf.chave).length !== 44) {
      return { ok: false, code: SHIPPING_EXPORT_ERROR.SHIPPING_DOCUMENT_DATA_REQUIRED };
    }
  }
  const items = buildShipmentItems(order);
  if (items.length === 0) {
    return { ok: false, code: SHIPPING_EXPORT_ERROR.SHIPPING_DOCUMENT_DATA_REQUIRED };
  }
  const itemsValue = Math.round(items.reduce((acc, it) => acc + it.unitValue * it.quantity, 0) * 100) / 100;
  const nf = order.notaFiscal && typeof order.notaFiscal === "object" ? order.notaFiscal : {};
  return {
    ok: true,
    shippingOrder: {
      provider,
      storeId,
      orderId,
      operationId: shippingExportOperationId(provider, storeId, orderId),
      serviceId: quote.snapshot.serviceId,
      serviceName: quote.snapshot.serviceName,
      carrierName: quote.snapshot.carrierName,
      quoteId: quote.snapshot.quoteId,
      quotedPrice: quote.snapshot.quotedPrice,
      quotedDeadlineDays: quote.snapshot.quotedDeadlineDays,
      chargedPrice: quote.snapshot.chargedPrice,
      package: quote.snapshot.package,
      recipient: rec.recipient,
      sender: snd.sender,
      items,
      insuranceValue: itemsValue,
      shippingDocument: snd.sender.shippingDocument,
      invoiceKey: snd.sender.shippingDocument === "nota_fiscal" ? digits(nf.chave) : null,
    },
  };
}

/** Resumo exibido ao lojista (sem PII). */
export function shippingSummaryFromOrder(order, provider) {
  const frete = order.frete && typeof order.frete === "object" ? order.frete : {};
  const c = frete.cotacao && typeof frete.cotacao === "object" ? frete.cotacao : {};
  const deadline = Number(c.quotedDeadlineDays);
  return {
    provider,
    serviceId: str(c.serviceId ?? frete.service_id ?? frete.servico_id) || null,
    serviceName: str(c.serviceName ?? frete.nome) || null,
    carrierName: str(c.carrierName) || null,
    price: money(frete.valor),
    deadline: Number.isFinite(deadline) && deadline > 0 ? Math.round(deadline) : null,
  };
}

// ---------------------------------------------------------------------------
// Provedores
// ---------------------------------------------------------------------------

export function buildMelhorEnvioCartRequest(so) {
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
  };
  if (so.sender.companyDocument) from.company_document = so.sender.companyDocument;
  else from.document = so.sender.document;

  const to = {
    name: so.recipient.name,
    phone: so.recipient.phone || undefined,
    document: so.recipient.document || undefined,
    address: so.recipient.address,
    complement: so.recipient.complement || undefined,
    number: so.recipient.number,
    district: so.recipient.district || undefined,
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
    non_commercial: so.shippingDocument !== "nota_fiscal",
    platform: "MasterPalm",
    tags: [{ tag: so.operationId }],
  };
  if (so.invoiceKey) options.invoice = { key: so.invoiceKey };

  return JSON.parse(JSON.stringify({
    service: Number(so.serviceId),
    from,
    to,
    products: so.items.map((it) => ({
      name: it.name,
      quantity: it.quantity,
      unitary_value: it.unitValue,
    })),
    volumes: [{
      height: Math.max(1, Math.round(so.package.heightCm)),
      width: Math.max(1, Math.round(so.package.widthCm)),
      length: Math.max(1, Math.round(so.package.lengthCm)),
      weight: Math.max(0.01, Math.round(so.package.weightGrams) / 1000),
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
      district: so.recipient.district || undefined,
      city: so.recipient.city,
      state_abbr: so.recipient.state,
      postal_code: so.recipient.postalCode,
      document: so.recipient.document || undefined,
    },
    package: {
      height: so.package.heightCm,
      width: so.package.widthCm,
      length: so.package.lengthCm,
      weight: Math.round(so.package.weightGrams) / 1000,
    },
    products: so.items.map((it) => ({
      name: it.name,
      quantity: it.quantity,
      unitary_value: it.unitValue,
    })),
    valorDeclarado: so.insuranceValue,
    pedidoRef: so.operationId,
  });
}

function cartItemHasTag(item, tag) {
  const tags = Array.isArray(item?.tags) ? item.tags : [];
  return tags.some((t) => (typeof t === "string" ? t : str(t?.tag)) === tag);
}

/**
 * Procura no carrinho Melhor Envio da loja um item com a tag da operação.
 * @returns {{found: true, providerShipmentId: string} | {found: false} | {error: string}}
 */
export async function findMelhorEnvioCartItemByTag({ token, sandbox, tag, fetchImpl }) {
  const base = getMelhorEnvioApiBase(sandbox);
  let page = 1;
  let lastPage = 1;
  try {
    while (page <= lastPage && page <= MELHOR_ENVIO_CART_MAX_PAGES) {
      const resp = await fetchImpl(`${base}/me/cart?page=${page}`, {
        method: "GET",
        headers: buildMelhorEnvioHeaders(token),
      });
      const text = await resp.text();
      if (!resp.ok) return { error: classifyProviderHttpStatus(resp.status).code };
      let parsed;
      try {
        parsed = JSON.parse(text);
      } catch {
        return { error: SHIPPING_EXPORT_ERROR.PROVIDER_RESPONSE_INVALID };
      }
      const items = Array.isArray(parsed?.data) ? parsed.data : Array.isArray(parsed) ? parsed : [];
      const hit = items.find((it) => cartItemHasTag(it, tag));
      if (hit && str(hit.id)) return { found: true, providerShipmentId: str(hit.id) };
      lastPage = Number(parsed?.last_page ?? 1) || 1;
      page += 1;
    }
    if (lastPage > MELHOR_ENVIO_CART_MAX_PAGES) {
      return { error: SHIPPING_EXPORT_ERROR.PROVIDER_RESPONSE_INVALID };
    }
    return { found: false };
  } catch {
    return { error: SHIPPING_EXPORT_ERROR.PROVIDER_UNAVAILABLE };
  }
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
    text = await resp.text();
  } catch {
    return { outcome: "unknown", code: SHIPPING_EXPORT_ERROR.PROVIDER_UNAVAILABLE, providerStatus: null };
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

/**
 * Melhor Envio: reconcilia pela tag antes de POST; POST cria item no carrinho da loja (sem compra).
 * `priorAttempt`: houve tentativa anterior com resultado incerto → reconciliação obrigatória.
 */
export async function exportMelhorEnvio({ shippingOrder, credentials, priorAttempt, fetchImpl }) {
  const lookup = await findMelhorEnvioCartItemByTag({
    token: credentials.token,
    sandbox: credentials.sandbox,
    tag: shippingOrder.operationId,
    fetchImpl,
  });
  if (lookup.found) {
    return { outcome: "exported", providerShipmentId: lookup.providerShipmentId, reconciled: true };
  }
  if (lookup.error) {
    if (lookup.error === SHIPPING_EXPORT_ERROR.PROVIDER_AUTH_FAILED) {
      return { outcome: "failed", code: lookup.error };
    }
    if (priorAttempt) return { outcome: "unknown", code: lookup.error };
  }
  return postMelhorEnvioCart({
    token: credentials.token,
    sandbox: credentials.sandbox,
    body: buildMelhorEnvioCartRequest(shippingOrder),
    fetchImpl,
  });
}

/**
 * SuperFrete: `POST /api/v0/cart` existe (documentado), mas não há consulta por tag/referência
 * (só `GET /api/v0/order/info/{id}`). Sem reconciliação, produção permanece bloqueada.
 */
export async function exportSuperFrete({ shippingOrder, credentials, fetchImpl }) {
  if (credentials.sandbox !== true) {
    return { outcome: "failed", code: SHIPPING_EXPORT_ERROR.UNSUPPORTED_BY_CURRENT_API };
  }
  const res = await executeSuperFreteCartPost({
    token: credentials.token,
    sandbox: true,
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

/**
 * Reserva at-most-once. Gatilhos automáticos só criam a primeira tentativa;
 * novas tentativas só por ação explícita do lojista.
 */
export async function reserveShippingExport({
  db, collectionLojas, storeId, orderId, provider, trigger, summary, nowMs,
}) {
  const ref = lojaRef(db, collectionLojas, storeId);
  const exportRef = ref.collection(SHIPPING_PREORDER_COL).doc(shippingExportDocId(provider, orderId));
  const orderRef = ref.collection("pre_pedidos").doc(orderId);
  const operationId = shippingExportOperationId(provider, storeId, orderId);
  const isRetry = trigger === SHIPPING_EXPORT_TRIGGER.MERCHANT_RETRY;

  return db.runTransaction(async (tx) => {
    const exportSnap = await tx.get(exportRef);
    const orderSnap = await tx.get(orderRef);
    if (!orderSnap.exists) return { action: "skip", reason: "order_not_found" };
    const order = orderSnap.data() || {};
    if (CANCELLED_ORDER_STATUSES.has(normStatus(order.status))) {
      return { action: "skip", reason: "order_cancelled" };
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
    if (status === SHIPPING_EXPORT_STATUS.UNKNOWN && provider !== SHIPPING_PROVIDER.MELHOR_ENVIO) {
      return { action: "skip", reason: "unknown_requires_manual_review", record: existing, operationId };
    }

    const priorAttempt = status === SHIPPING_EXPORT_STATUS.UNKNOWN
      || status === SHIPPING_EXPORT_STATUS.EXPORTING;
    const now = FieldValue.serverTimestamp();
    const attempts = Number(existing?.attempts ?? 0) + 1;
    tx.set(exportRef, {
      schemaVersion: SHIPPING_EXPORT_SCHEMA,
      kind: "shipping_export",
      operationId,
      provider,
      orderId,
      storeId,
      status: SHIPPING_EXPORT_STATUS.EXPORTING,
      trigger,
      attempts,
      leaseUntil: Timestamp.fromMillis(nowMs + SHIPPING_EXPORT_LEASE_MS),
      lastAttemptAt: now,
      updatedAt: now,
      lastErrorCode: null,
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
    return { action: "reserved", operationId, priorAttempt, attempts };
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
    ...(exported ? { exportedAt: now } : {}),
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
 */
export async function exportShippingOrder({
  db, collectionLojas, storeId, orderId, order, trigger, fetchImpl, now = () => Date.now(),
}) {
  const started = now();
  const req = classifyShippingRequirement(order);
  if (!req.required) return { skipped: true, reason: req.reason };
  const provider = req.provider;

  const { secrets, publicFretes } = await readStoreShippingConfig(db, collectionLojas, storeId);
  if (!isAutoExportEnabled(secrets, provider)) {
    emitShippingExportLog({ provider, storeId, orderId, trigger, status: "skipped", reason: "feature_disabled" });
    return { skipped: true, reason: "feature_disabled" };
  }

  const reserve = await reserveShippingExport({
    db,
    collectionLojas,
    storeId,
    orderId,
    provider,
    trigger,
    summary: shippingSummaryFromOrder(order, provider),
    nowMs: now(),
  });
  if (reserve.action === "noop") {
    return { ok: true, idempotent: true, status: SHIPPING_EXPORT_STATUS.EXPORTED, record: reserve.record };
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

  const built = buildShippingOrder({ order, storeId, orderId, provider, sender: secrets.sender });
  if (!built.ok) {
    return finish({ status: SHIPPING_EXPORT_STATUS.FAILED, errorCode: built.code });
  }

  let res;
  try {
    res = provider === SHIPPING_PROVIDER.MELHOR_ENVIO
      ? await exportMelhorEnvio({
        shippingOrder: built.shippingOrder,
        credentials,
        priorAttempt: reserve.priorAttempt,
        fetchImpl,
      })
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

/** Trigger `onDocumentUpdated` de `pre_pedidos`. */
export async function handlePrePedidoShippingExportUpdate({
  db, collectionLojas, storeId, orderId, before, after, createTimeMs, cutoverMs, fetchImpl, now,
}) {
  const detected = detectShippingExportTrigger(before, after);
  if (!detected) return { skipped: true, reason: "no_confirmation_transition" };
  const req = classifyShippingRequirement(after);
  if (!req.required) return { skipped: true, reason: req.reason };

  const cut = evaluateShippingCutover({ createTimeMs, cutoverMs });
  if (!cut.ok) {
    emitShippingExportLog({
      provider: req.provider, storeId, orderId, trigger: detected.trigger, status: "skipped", reason: cut.reason,
    });
    return { skipped: true, reason: cut.reason };
  }

  if (detected.trigger === SHIPPING_EXPORT_TRIGGER.PAYMENT_APPROVED) {
    const verified = await verifyPaymentApprovedMarker(db, { paymentId: detected.paymentId, storeId, orderId });
    if (!verified) {
      emitShippingExportLog({
        provider: req.provider, storeId, orderId, trigger: detected.trigger, status: "skipped",
        reason: "payment_marker_not_verified",
      });
      return { skipped: true, reason: "payment_marker_not_verified" };
    }
  }

  return exportShippingOrder({
    db, collectionLojas, storeId, orderId, order: after, trigger: detected.trigger, fetchImpl, now,
  });
}

// ---------------------------------------------------------------------------
// Callables (lojista)
// ---------------------------------------------------------------------------

const SENDER_FIELDS = [
  "name", "document", "companyDocument", "phone", "postalCode", "address",
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

  async function retryShippingExport() {
    const { lojaId, orderId } = request.data ?? {};
    const { lojaId: storeId } = await requireStoreAdmin(lojaId);
    const oid = str(orderId);
    if (!oid || oid.includes("/")) throw new HttpsError("invalid-argument", "Informe o pedido.");
    await checkRateLimit("retryShippingExport", getCallableIdentifier(request));

    const storeRef = lojaRef(db, collectionLojas, storeId);
    const snap = await storeRef.collection("pre_pedidos").doc(oid).get();
    if (!snap.exists) throw new HttpsError("not-found", "Pedido não encontrado.");
    const order = snap.data() || {};
    const provider = resolveShippingProviderFromOrder(order);
    // Estado lido do ledger (só Admin SDK escreve); `order.shipping` pode vir do cliente na criação.
    const ledgerSnap = provider
      ? await storeRef.collection(SHIPPING_PREORDER_COL).doc(shippingExportDocId(provider, oid)).get()
      : null;
    const current = ledgerSnap?.exists ? (ledgerSnap.data() || {}).status : null;
    if (current !== SHIPPING_EXPORT_STATUS.FAILED && current !== SHIPPING_EXPORT_STATUS.UNKNOWN
      && current !== SHIPPING_EXPORT_STATUS.EXPORTING) {
      throw new HttpsError("failed-precondition", "Este frete não está aguardando nova tentativa.", {
        code: "SHIPPING_EXPORT_NOT_RETRYABLE",
      });
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
      trigger: SHIPPING_EXPORT_TRIGGER.MERCHANT_RETRY,
      fetchImpl: fetchWithTimeout,
      now,
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
      sender: {
        name: str(s.name),
        documentMasked: maskDigits(s.document),
        companyDocumentMasked: maskDigits(s.companyDocument),
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
        if (typeof flags.superFrete === "boolean") automation.shippingAutoExportSuperFrete = flags.superFrete;
        patch.automation = { ...automation, updatedAt: FieldValue.serverTimestamp(), updatedByUid: uid };
      }
      tx.set(secretsRef, patch, { merge: true });
    });
    return { ok: true };
  }

  return { retryShippingExport, shippingGetAutomationConfig, shippingSaveAutomationConfig };
}
