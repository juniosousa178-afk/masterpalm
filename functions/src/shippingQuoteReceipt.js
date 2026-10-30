/**
 * Recibo de cotação de frete emitido pelo servidor (Melhor Envio / SuperFrete).
 *
 * - O pacote cotado é calculado aqui a partir de `produtos/{id}` (peso, tipoEmbalagem) e
 *   `config/fretes.embalagens`; peso/dimensões/preço vindos do navegador são ignorados.
 * - Cada opção devolvida pelo provedor recebe um `shippingQuoteId` opaco (`{recibo}.{índice}`),
 *   gravado em `lojas/{storeId}/shipping_quotes/{recibo}` (rules: sem acesso de cliente).
 * - Pagamento e exportação só aceitam o pedido se serviço, destino, itens, preço e validade
 *   baterem com o recibo; nunca substituem o serviço escolhido.
 */

import { randomBytes } from "node:crypto";
import { Timestamp } from "firebase-admin/firestore";

export const SHIPPING_QUOTES_COL = "shipping_quotes";
export const SHIPPING_QUOTE_SCHEMA = 1;
/** Pedido precisa ser criado até 1 h após a cotação. */
export const SHIPPING_QUOTE_VALIDITY_MS = 60 * 60 * 1000;
/**
 * Recibo vale para pagamento/exportação até `retainUntilMs` (checagem lógica).
 * A TTL em `deleteAt` só faz a limpeza física e pode atrasar sem afetar a validação.
 */
export const SHIPPING_QUOTE_RETENTION_MS = 30 * 24 * 60 * 60 * 1000;
export const SHIPPING_QUOTE_MAX_ITEMS = 50;
export const SHIPPING_QUOTE_MAX_QTY = 999;
/** Um volume por pedido; acima disso o carrinho fica só com as opções manuais. */
export const SUPPORTED_PACKAGE_COUNT = 1;
/** Limites de um volume nos serviços dos Correios (os mais restritivos cotados). */
export const SINGLE_VOLUME_MAX_WEIGHT_GRAMS = 30000;
export const SINGLE_VOLUME_MAX_SIDE_CM = 100;
export const SINGLE_VOLUME_MAX_SUM_CM = 200;
/** Marcador do modelo com recibo do servidor (gravado só via Admin SDK). */
export const SHIPPING_MODEL_VERSION = 2;
export const SHIPPING_MODEL = Object.freeze({ LEGACY: "legacy", QUOTE_RECEIPT: "quote_receipt" });
const MIN_WEIGHT_GRAMS = 300;
const MONEY_TOLERANCE = 0.01;
const QUOTE_ID_RE = /^([a-f0-9]{32})\.(\d{1,2})$/;
const PRODUCT_ID_RE = /^[^/]{1,200}$/;

export const SHIPPING_QUOTE_PROVIDER = {
  MELHOR_ENVIO: "melhor_envio",
  SUPERFRETE: "superfrete",
};

export const SHIPPING_QUOTE_ERROR = {
  MISSING: "SHIPPING_QUOTE_MISSING",
  NOT_FOUND: "SHIPPING_QUOTE_NOT_FOUND",
  STORE_MISMATCH: "SHIPPING_QUOTE_STORE_MISMATCH",
  SERVICE_MISMATCH: "SHIPPING_QUOTE_SERVICE_MISMATCH",
  DESTINATION_MISMATCH: "SHIPPING_QUOTE_DESTINATION_MISMATCH",
  EXPIRED: "SHIPPING_QUOTE_EXPIRED",
  ITEMS_MISMATCH: "SHIPPING_QUOTE_ITEMS_MISMATCH",
  PRICE_MISMATCH: "SHIPPING_QUOTE_PRICE_MISMATCH",
  INSURANCE_MISMATCH: "SHIPPING_QUOTE_INSURANCE_MISMATCH",
  TOTAL_INCONSISTENT: "SHIPPING_ORDER_TOTAL_INCONSISTENT",
  PRODUCT_SHIPPING_DATA_MISSING: "PRODUCT_SHIPPING_DATA_MISSING",
  ITEMS_INVALID: "SHIPPING_QUOTE_ITEMS_INVALID",
  MULTI_VOLUME_REQUIRED: "SHIPPING_MULTI_VOLUME_REQUIRED",
};

/**
 * Modelo de frete do pedido, decidido só por timestamps do servidor:
 * `createTime` do documento (metadado do Firestore) contra o corte `SHIPPING_AUTO_EXPORT_CUTOVER`.
 * Campos do pedido (`createdAt`, `legacy`, `shippingModelVersion`…) nunca entram aqui.
 * `createTime < corte` → legado; `createTime >= corte` → recibo obrigatório.
 * Sem corte ou sem `createTime` → recibo obrigatório (falha fechado).
 */
export function classifyShippingModel({ createTimeMs, cutoverMs }) {
  if (!Number.isFinite(cutoverMs)) {
    return { model: SHIPPING_MODEL.QUOTE_RECEIPT, reason: "cutover_not_configured" };
  }
  if (!Number.isFinite(createTimeMs)) {
    return { model: SHIPPING_MODEL.QUOTE_RECEIPT, reason: "order_create_time_unknown" };
  }
  return createTimeMs < cutoverMs
    ? { model: SHIPPING_MODEL.LEGACY, reason: "created_before_cutover" }
    : { model: SHIPPING_MODEL.QUOTE_RECEIPT, reason: "created_at_or_after_cutover" };
}

/** Mesmo padrão do carrinho (`_embalagensPadrao`). */
export const DEFAULT_EMBALAGENS = Object.freeze([
  { id: "padrao", peso: 50, tamanho: 1, altura: 10, largura: 20, comprimento: 30 },
  { id: "pequena", peso: 100, tamanho: 2, altura: 15, largura: 25, comprimento: 35 },
  { id: "media", peso: 200, tamanho: 3, altura: 20, largura: 30, comprimento: 40 },
  { id: "grande", peso: 350, tamanho: 4, altura: 25, largura: 35, comprimento: 45 },
]);

const str = (v) => String(v ?? "").trim();
const cep = (v) => str(v).replace(/\D/g, "").slice(0, 8);
const round2 = (n) => Math.round(n * 100) / 100;

function num(v, fallback) {
  if (typeof v === "number") return Number.isFinite(v) ? v : fallback;
  const n = Number.parseFloat(String(v ?? ""));
  return Number.isFinite(n) ? n : fallback;
}

function money(v) {
  const n = typeof v === "string" ? Number(v.replace(",", ".")) : Number(v);
  return Number.isFinite(n) && n >= 0 ? round2(n) : null;
}

/** Espelha `_parseMoneyMelhorEnvio` do cliente (número ou string pt-BR). */
export function parseProviderMoney(raw) {
  if (raw == null) return null;
  if (typeof raw === "number") return Number.isFinite(raw) ? raw : null;
  let s = String(raw).trim();
  if (!s) return null;
  if (s.includes(",") && !s.includes(".")) s = s.replace(/\./g, "").replace(",", ".");
  const n = Number(s);
  return Number.isFinite(n) ? n : null;
}

export function parseEmbalagens(raw) {
  if (!Array.isArray(raw) || raw.length === 0) return [];
  return raw.map((e) => {
    const m = e && typeof e === "object" ? e : {};
    return {
      id: m.id == null ? "" : String(m.id),
      peso: num(m.peso, 0),
      tamanho: Math.trunc(num(m.tamanho, 0)),
      altura: num(m.altura, 10),
      largura: num(m.largura, 20),
      comprimento: num(m.comprimento, 30),
    };
  });
}

/** Itens do carrinho → `[{productId, quantity}]` agregados por produto, ordenados. */
export function normalizeQuoteItems(raw) {
  if (!Array.isArray(raw) || raw.length === 0 || raw.length > SHIPPING_QUOTE_MAX_ITEMS) {
    return { ok: false, code: SHIPPING_QUOTE_ERROR.ITEMS_INVALID };
  }
  const agg = new Map();
  for (const r of raw) {
    const it = r && typeof r === "object" ? r : {};
    const productId = str(it.productId ?? it.id ?? it.produtosId);
    const quantity = Number(it.quantity ?? it.quantidade);
    if (!PRODUCT_ID_RE.test(productId) || !Number.isInteger(quantity) || quantity < 1
      || quantity > SHIPPING_QUOTE_MAX_QTY) {
      return { ok: false, code: SHIPPING_QUOTE_ERROR.ITEMS_INVALID };
    }
    agg.set(productId, (agg.get(productId) ?? 0) + quantity);
  }
  const items = [...agg.entries()]
    .map(([productId, quantity]) => ({ productId, quantity }))
    .sort((a, b) => (a.productId < b.productId ? -1 : a.productId > b.productId ? 1 : 0));
  return { ok: true, items };
}

/** Itens gravados no pedido, no mesmo formato de `normalizeQuoteItems`. */
export function orderItemsForQuote(order = {}) {
  const itens = Array.isArray(order.itens) ? order.itens : [];
  return normalizeQuoteItems(itens.map((it) => {
    const m = it && typeof it === "object" ? it : {};
    return {
      productId: m.productId ?? m.id ?? m.produtosId,
      quantity: Number(m.quantidade ?? m.qty ?? 1),
    };
  }));
}

/**
 * Pacote canônico (gramas / cm) a partir dos produtos e embalagens da loja.
 * Mesma regra do carrinho: soma `peso × qtd` + peso da embalagem de maior `tamanho`.
 */
export async function computeCanonicalPackage({ db, collectionLojas, storeId, items }) {
  const storeRef = db.collection(collectionLojas).doc(storeId);
  const [fretesSnap, ...productSnaps] = await Promise.all([
    storeRef.collection("config").doc("fretes").get(),
    ...items.map((it) => storeRef.collection("produtos").doc(it.productId).get()),
  ]);
  const fretes = fretesSnap.exists ? fretesSnap.data() || {} : {};
  const parsed = parseEmbalagens(fretes.embalagens);
  const embalagens = parsed.length > 0 ? parsed : DEFAULT_EMBALAGENS;
  const originCep = cep(fretes.cepOrigem ?? fretes.cep_origem);

  let productsGrams = 0;
  let biggest = null;
  let biggestSize = 0;
  items.forEach((it, i) => {
    const p = productSnaps[i]?.exists ? productSnaps[i].data() || {} : {};
    const peso = typeof p.peso === "number" && Number.isFinite(p.peso) ? p.peso : 0;
    const tipo = typeof p.tipoEmbalagem === "string" ? p.tipoEmbalagem : "padrao";
    productsGrams += peso * it.quantity;
    const emb = embalagens.find((e) => e.id === tipo) ?? embalagens[0];
    if (emb.tamanho > biggestSize) {
      biggestSize = emb.tamanho;
      biggest = emb;
    }
  });
  if (!(productsGrams > 0)) {
    return { ok: false, code: SHIPPING_QUOTE_ERROR.PRODUCT_SHIPPING_DATA_MISSING };
  }
  const emb = biggest ?? embalagens[0];
  const pkg = {
    weightGrams: Math.max(MIN_WEIGHT_GRAMS, productsGrams + emb.peso),
    heightCm: emb.altura,
    widthCm: emb.largura,
    lengthCm: emb.comprimento,
  };
  if (!fitsSingleVolume(pkg)) {
    return { ok: false, code: SHIPPING_QUOTE_ERROR.MULTI_VOLUME_REQUIRED };
  }
  return {
    ok: true,
    originCep: originCep.length === 8 ? originCep : null,
    package: pkg,
  };
}

/** Pedido que não cabe em um volume não é cotado (nunca soma em um pacote inválido). */
export function fitsSingleVolume(pkg) {
  const sides = [pkg.heightCm, pkg.widthCm, pkg.lengthCm];
  return pkg.weightGrams <= SINGLE_VOLUME_MAX_WEIGHT_GRAMS
    && sides.every((s) => s <= SINGLE_VOLUME_MAX_SIDE_CM)
    && sides.reduce((a, b) => a + b, 0) <= SINGLE_VOLUME_MAX_SUM_CM;
}

/** Pacote enviado à cotação do Melhor Envio (mesmos arredondamentos do app). */
export function melhorEnvioQuotePackage(pkg) {
  return {
    weight: Math.max(MIN_WEIGHT_GRAMS, pkg.weightGrams) / 1000,
    height: Math.trunc(pkg.heightCm < 1 ? 2 : pkg.heightCm),
    width: Math.trunc(pkg.widthCm < 1 ? 11 : pkg.widthCm),
    length: Math.trunc(pkg.lengthCm < 1 ? 16 : pkg.lengthCm),
  };
}

/** Opções do Melhor Envio → modelo do recibo (só serviços com preço e sem erro). */
export function parseMelhorEnvioQuoteOptions(raw) {
  const list = Array.isArray(raw) ? raw : [];
  const out = [];
  list.forEach((item, index) => {
    if (!item || typeof item !== "object" || item.error) return;
    const serviceId = str(item.id);
    if (!serviceId) return;
    let price = null;
    for (const k of ["price", "custom_price", "customPrice", "total", "final_price"]) {
      const v = parseProviderMoney(item[k]);
      if (v != null && v > 0) {
        price = v;
        break;
      }
    }
    if (price == null) return;
    const deadline = Number(item.delivery_time ?? item.custom_delivery_time);
    out.push({
      responseIndex: index,
      serviceId,
      serviceName: str(item.name) || null,
      carrierName: str(item.company?.name) || null,
      companyId: str(item.company?.id) || null,
      price: round2(price),
      deadlineDays: Number.isFinite(deadline) && deadline > 0 ? Math.round(deadline) : null,
    });
  });
  return out;
}

/** Opções do SuperFrete (`mapQuoteResponse`) → modelo do recibo. */
export function parseSuperFreteQuoteOptions(opcoes) {
  const list = Array.isArray(opcoes) ? opcoes : [];
  const out = [];
  list.forEach((o, index) => {
    if (!o || typeof o !== "object") return;
    const serviceId = str(o.servico_id);
    const price = Number(o.preco);
    if (!serviceId || !(price > 0)) return;
    const deadline = Number(o.prazo);
    out.push({
      responseIndex: index,
      serviceId,
      serviceName: str(o.nome) || null,
      carrierName: str(o.empresa) || null,
      companyId: null,
      price: round2(price),
      deadlineDays: Number.isFinite(deadline) && deadline > 0 ? Math.round(deadline) : null,
    });
  });
  return out;
}

export function newShippingQuoteReceiptId() {
  return randomBytes(16).toString("hex");
}

export function parseShippingQuoteId(raw) {
  const m = QUOTE_ID_RE.exec(str(raw));
  if (!m) return null;
  return { receiptId: m[1], optionIndex: Number(m[2]) };
}

/**
 * Grava o recibo e devolve `shippingQuoteId` por `responseIndex` da resposta do provedor.
 * Sem credenciais, sem dados pessoais (só CEPs, itens e pacote).
 */
export async function issueShippingQuoteReceipt({
  db, collectionLojas, storeId, provider, originCep, destinationCep, canonicalPackage,
  providerPackage, insuranceValue, items, options, nowMs = Date.now(),
}) {
  if (!options.length) return { receiptId: null, quoteIds: new Map() };
  const receiptId = newShippingQuoteReceiptId();
  const quoteIds = new Map();
  const stored = options.slice(0, 99).map((o, i) => {
    quoteIds.set(o.responseIndex, `${receiptId}.${i}`);
    return {
      serviceId: o.serviceId,
      serviceName: o.serviceName,
      carrierName: o.carrierName,
      companyId: o.companyId,
      price: o.price,
      deadlineDays: o.deadlineDays,
    };
  });
  await db.collection(collectionLojas).doc(storeId).collection(SHIPPING_QUOTES_COL).doc(receiptId).set({
    schemaVersion: SHIPPING_QUOTE_SCHEMA,
    storeId,
    provider,
    originCep: cep(originCep),
    destinationCep: cep(destinationCep),
    items,
    canonicalPackage,
    providerPackage,
    insuranceValue: round2(Number(insuranceValue) || 0),
    options: stored,
    quotedAtMs: nowMs,
    expiresAtMs: nowMs + SHIPPING_QUOTE_VALIDITY_MS,
    retainUntilMs: nowMs + SHIPPING_QUOTE_RETENTION_MS,
    quotedAt: Timestamp.fromMillis(nowMs),
    deleteAt: Timestamp.fromMillis(nowMs + SHIPPING_QUOTE_RETENTION_MS),
  });
  return { receiptId, quoteIds };
}

function orderServiceId(frete) {
  return str(frete.service_id ?? frete.servico_id ?? frete.serviceId);
}

function hasFreightDiscountMarker(order) {
  const cf = order.cupomFrete;
  if (cf && typeof cf === "object" && str(cf.codigo)) return true;
  const pr = order.premioRoleta;
  return !!(pr && typeof pr === "object");
}

function hasProductDiscountMarker(order) {
  const c = order.cupom;
  if (c && typeof c === "object" && str(c.codigo)) return true;
  const pr = order.premioRoleta;
  return !!(pr && typeof pr === "object");
}

function retainUntilMsOf(receipt) {
  const ms = Number(receipt.retainUntilMs);
  if (Number.isFinite(ms)) return ms;
  return typeof receipt.deleteAt?.toMillis === "function" ? receipt.deleteAt.toMillis() : NaN;
}

/**
 * Valida o frete do pedido contra o recibo do servidor.
 * `orderCreateTimeMs`: `createTime` do documento (servidor), nunca relógio do cliente.
 * `nowMs`: relógio do servidor; recibo além de `retainUntilMs` é rejeitado mesmo que a TTL
 * ainda não o tenha apagado.
 */
export async function loadCanonicalShippingQuote({
  db, collectionLojas, storeId, provider, order = {}, orderCreateTimeMs, nowMs = Date.now(),
}) {
  const frete = order.frete && typeof order.frete === "object" ? order.frete : {};
  const ref = parseShippingQuoteId(frete.shippingQuoteId);
  if (!ref) return { ok: false, code: SHIPPING_QUOTE_ERROR.MISSING };

  const snap = await db.collection(collectionLojas).doc(storeId)
    .collection(SHIPPING_QUOTES_COL).doc(ref.receiptId).get();
  if (!snap.exists) return { ok: false, code: SHIPPING_QUOTE_ERROR.NOT_FOUND };
  const receipt = snap.data() || {};
  if (str(receipt.storeId) !== storeId) return { ok: false, code: SHIPPING_QUOTE_ERROR.STORE_MISMATCH };

  const option = Array.isArray(receipt.options) ? receipt.options[ref.optionIndex] : null;
  if (!option || str(receipt.provider) !== provider) {
    return { ok: false, code: SHIPPING_QUOTE_ERROR.SERVICE_MISMATCH };
  }
  const declaredService = orderServiceId(frete);
  if (!declaredService || declaredService !== str(option.serviceId)) {
    return { ok: false, code: SHIPPING_QUOTE_ERROR.SERVICE_MISMATCH };
  }

  const endereco = order.cliente?.endereco && typeof order.cliente.endereco === "object"
    ? order.cliente.endereco
    : {};
  if (cep(endereco.cep) !== str(receipt.destinationCep)) {
    return { ok: false, code: SHIPPING_QUOTE_ERROR.DESTINATION_MISMATCH };
  }

  const created = Number(orderCreateTimeMs);
  const quotedAt = Number(receipt.quotedAtMs);
  const expiresAt = Number(receipt.expiresAtMs);
  const retainUntil = retainUntilMsOf(receipt);
  if (!Number.isFinite(created) || !Number.isFinite(expiresAt) || created > expiresAt
    || (Number.isFinite(quotedAt) && created < quotedAt)
    || !Number.isFinite(retainUntil) || Number(nowMs) > retainUntil) {
    return { ok: false, code: SHIPPING_QUOTE_ERROR.EXPIRED };
  }

  const orderItems = orderItemsForQuote(order);
  if (!orderItems.ok || JSON.stringify(orderItems.items) !== JSON.stringify(receipt.items ?? [])) {
    return { ok: false, code: SHIPPING_QUOTE_ERROR.ITEMS_MISMATCH };
  }

  const subtotal = money(order.subtotal);
  if (subtotal != null && Number(receipt.insuranceValue) + MONEY_TOLERANCE < subtotal) {
    return { ok: false, code: SHIPPING_QUOTE_ERROR.INSURANCE_MISMATCH };
  }

  const quotedPrice = money(option.price);
  const charged = frete.gratis === true ? 0 : money(frete.valor);
  if (quotedPrice == null || charged == null || charged > quotedPrice + MONEY_TOLERANCE) {
    return { ok: false, code: SHIPPING_QUOTE_ERROR.PRICE_MISMATCH };
  }
  const discounted = charged < quotedPrice - MONEY_TOLERANCE;
  if (discounted && frete.gratis !== true && !hasFreightDiscountMarker(order)) {
    return { ok: false, code: SHIPPING_QUOTE_ERROR.PRICE_MISMATCH };
  }

  const total = money(order.total);
  if (total == null || subtotal == null) return { ok: false, code: SHIPPING_QUOTE_ERROR.TOTAL_INCONSISTENT };
  const expected = round2(subtotal + charged);
  if (total > expected + MONEY_TOLERANCE) return { ok: false, code: SHIPPING_QUOTE_ERROR.TOTAL_INCONSISTENT };
  if (total < expected - MONEY_TOLERANCE && !hasProductDiscountMarker(order)) {
    return { ok: false, code: SHIPPING_QUOTE_ERROR.TOTAL_INCONSISTENT };
  }

  return {
    ok: true,
    quote: {
      shippingQuoteId: `${ref.receiptId}.${ref.optionIndex}`,
      provider,
      serviceId: str(option.serviceId),
      serviceName: option.serviceName ?? null,
      carrierName: option.carrierName ?? null,
      companyId: option.companyId ?? null,
      quotedPrice,
      chargedPrice: charged,
      deadlineDays: option.deadlineDays ?? null,
      originCep: str(receipt.originCep),
      destinationCep: str(receipt.destinationCep),
      insuranceValue: Number(receipt.insuranceValue) || 0,
      providerPackage: receipt.providerPackage,
      canonicalPackage: receipt.canonicalPackage,
    },
  };
}

/**
 * Antes de cobrar: pedido com frete de provedor integrado só segue se o frete cobrado bater
 * com o recibo do servidor. Frete manual/retirada não passa por aqui.
 * Pedido legado (criado antes do corte) mantém a cobrança anterior, sem exigir recibo.
 */
export async function validateOrderShippingForPayment({
  db, collectionLojas, storeId, order, orderCreateTimeMs, cutoverMs, nowMs = Date.now(),
}) {
  const provider = resolveQuotedShippingProvider(order);
  if (!provider) return { ok: true, required: false };
  const { model, reason } = classifyShippingModel({ createTimeMs: orderCreateTimeMs, cutoverMs });
  if (model === SHIPPING_MODEL.LEGACY) {
    return { ok: true, required: false, shippingModel: model, reason };
  }
  const res = await loadCanonicalShippingQuote({
    db, collectionLojas, storeId, provider, order, orderCreateTimeMs, nowMs,
  });
  return res.ok
    ? { ok: true, required: true, shippingModel: model, quote: res.quote }
    : { ok: false, required: true, shippingModel: model, reason, code: res.code };
}

/** Provedor integrado pelo frete do pedido (`plataforma` ou `tipo`, como grava o checkout). */
export function resolveQuotedShippingProvider(order = {}) {
  const frete = order.frete && typeof order.frete === "object" ? order.frete : {};
  for (const raw of [frete.plataforma, frete.tipo]) {
    const v = str(raw).toLowerCase();
    if (v === "melhor_envio" || v === "melhorenvio") return SHIPPING_QUOTE_PROVIDER.MELHOR_ENVIO;
    if (v === "superfrete") return SHIPPING_QUOTE_PROVIDER.SUPERFRETE;
  }
  return null;
}
