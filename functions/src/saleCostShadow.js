/**
 * Sale cost shadow audit. Compares the unit cost each sale line carries with the current canonical
 * cost of the same store/product/variation and only reports it: never changes the sale, the stock,
 * the response or the transaction outcome, and never reads Firestore (it only sees product
 * documents the stock transaction already read).
 *
 * Canonical cost: the `__custoUnitario` of the exact canonical `tamanho|cor` cell, else the product
 * `custoReal`, else unavailable. Valid cost = finite number > 0. No other cell is ever used.
 */
import {createHash} from 'node:crypto';
import {isMap, META_COST} from './catalogStockProjection.js';
import {validVariationCost, variationCellCost, variationCellId} from './variationCostGuard.js';

export const SALE_COST_SHADOW = 'SALE_COST_SHADOW';
export const SHADOW_KIND = Object.freeze({PDV_SALE: 'PDV_SALE_SHADOW', SALE_EDIT: 'SALE_EDIT_SHADOW'});
export const SHADOW_CLASS = Object.freeze({
  MATCH: 'MATCH',
  MISMATCH: 'MISMATCH',
  SUSPECT_CLIENT_FALLBACK: 'SUSPECT_CLIENT_FALLBACK',
  EXPECTED_MANUAL_ORIGIN: 'EXPECTED_MANUAL_ORIGIN',
  AMBIGUOUS: 'AMBIGUOUS',
  NO_CANONICAL_COST: 'NO_CANONICAL_COST',
  NO_SENT_COST: 'NO_SENT_COST',
  COMBO_SKIPPED: 'COMBO_SKIPPED',
  CONSIGNMENT_SNAPSHOT: 'CONSIGNMENT_SNAPSHOT',
  NOT_LOADED: 'NOT_LOADED',
});
const COUNTER_KEYS = Object.freeze(['TOTAL_CHECKED', ...Object.values(SHADOW_CLASS)]);
const KNOWN_ORIGINS = new Set(['produto', 'item', 'fallback', 'zero_intencional', 'desconhecido']);
/** Origins that declare a cost the client did not take from the product: never reported as a bug. */
const MANUAL_ORIGINS = new Set(['zero_intencional', 'fallback']);
const MAX_LOGGED_LINES = 50;
const MISMATCH_CENTS = 1;

const cents = value => Math.round(value * 100);
const shortHash = (value, length) => createHash('sha256').update(String(value)).digest('hex').slice(0, length);
const clip = (value, max) => String(value ?? '').slice(0, max);

function isComboProduct(product) {
  return product.stockKind === 'combo' || product.tipoProduto === 'combo' ||
    (Array.isArray(product.itensCombo) && product.itensCombo.length > 0);
}

/**
 * Canonical cost of one line, from the raw product document. Duplicate canonical cells are
 * ambiguous; a variation product whose cell is not found is ambiguous too (never falls back).
 * @returns {{status: 'ok', cost: number, source: 'variation'|'product', cellId: string|null}
 *   | {status: 'ambiguous'|'unavailable', reason: string, cellId: string|null}}
 */
export function resolveCanonicalCost(product, {size = '', color = ''} = {}) {
  if (!isMap(product)) return {status: 'unavailable', reason: 'PRODUCT_NOT_FOUND', cellId: null};
  const productCost = validVariationCost(product.custoReal);
  const variacoes = isMap(product.variacoes) ? product.variacoes : null;
  const hasGrade = variacoes !== null && Object.values(variacoes).some(colors => isMap(colors) &&
    Object.keys(colors).some(color => color.trim() !== META_COST));
  if (!hasGrade) {
    return productCost === null
      ? {status: 'unavailable', reason: 'NO_VALID_PRODUCT_COST', cellId: null}
      : {status: 'ok', cost: productCost, source: 'product', cellId: null};
  }
  const cellId = variationCellId(size, color);
  let found = 0, cell;
  for (const [rawSize, colors] of Object.entries(variacoes)) {
    if (!isMap(colors)) continue;
    for (const [rawColor, value] of Object.entries(colors)) {
      if (rawColor.trim() === META_COST || variationCellId(rawSize, rawColor) !== cellId) continue;
      found++;
      cell = value;
    }
  }
  if (found > 1) return {status: 'ambiguous', reason: 'DUPLICATE_CELL_IDENTITY', cellId};
  if (found === 0) return {status: 'ambiguous', reason: 'CELL_NOT_FOUND', cellId};
  const cellCost = variationCellCost(cell);
  if (cellCost !== null) return {status: 'ok', cost: cellCost, source: 'variation', cellId};
  return productCost === null
    ? {status: 'unavailable', reason: 'NO_VALID_CELL_OR_PRODUCT_COST', cellId}
    : {status: 'ok', cost: productCost, source: 'product', cellId};
}

/** Classifies one sale line. `products` maps productId -> raw doc (null = read but missing). */
export function classifySaleLine(line, {products, consignmentOrigin = false}) {
  const origin = typeof line?.origemCustoItem === 'string' && KNOWN_ORIGINS.has(line.origemCustoItem)
    ? line.origemCustoItem : (line?.origemCustoItem == null ? null : 'other');
  const sentRaw = line?.custoUnitario;
  const sent = validVariationCost(sentRaw);
  const productId = typeof line?.productId === 'string' && line.productId ? line.productId : null;
  const out = {
    productId,
    cellId: null,
    origemCustoItem: origin,
    sentCost: typeof sentRaw === 'number' && Number.isFinite(sentRaw) ? sentRaw : null,
    canonicalCost: null,
    canonicalSource: null,
    delta: null,
    classification: null,
    reason: null,
  };
  const done = (classification, reason = null) => ({...out, classification, reason});
  if (consignmentOrigin) return done(SHADOW_CLASS.CONSIGNMENT_SNAPSHOT, 'CONSIGNMENT_SALE');
  if (!productId) return done(SHADOW_CLASS.NO_CANONICAL_COST, 'NO_PRODUCT_ID');
  if (!products.has(productId)) return done(SHADOW_CLASS.NOT_LOADED, 'PRODUCT_NOT_IN_TRANSACTION');
  const product = products.get(productId);
  if (isMap(product) && isComboProduct(product)) return done(SHADOW_CLASS.COMBO_SKIPPED, 'COMBO_COST_NOT_PROVABLE');
  const canonical = resolveCanonicalCost(product, {size: line?.tamanho ?? '', color: line?.cor ?? ''});
  out.cellId = canonical.cellId;
  if (canonical.status === 'ambiguous') return done(SHADOW_CLASS.AMBIGUOUS, canonical.reason);
  if (canonical.status !== 'ok') return done(SHADOW_CLASS.NO_CANONICAL_COST, canonical.reason);
  out.canonicalCost = canonical.cost;
  out.canonicalSource = canonical.source;
  if (sent === null) {
    return origin === 'zero_intencional'
      ? done(SHADOW_CLASS.EXPECTED_MANUAL_ORIGIN, 'ZERO_INTENCIONAL')
      : done(SHADOW_CLASS.NO_SENT_COST, 'SENT_COST_NOT_POSITIVE');
  }
  const deltaCents = cents(sent) - cents(canonical.cost);
  out.delta = deltaCents / 100;
  if (Math.abs(deltaCents) <= MISMATCH_CENTS) return done(SHADOW_CLASS.MATCH);
  if (MANUAL_ORIGINS.has(origin)) return done(SHADOW_CLASS.EXPECTED_MANUAL_ORIGIN, `ORIGIN_${origin.toUpperCase()}`);
  const productCost = validVariationCost(product.custoReal);
  if (canonical.source === 'variation' && productCost !== null &&
      Math.abs(cents(sent) - cents(productCost)) <= MISMATCH_CENTS) {
    return done(SHADOW_CLASS.SUSPECT_CLIENT_FALLBACK, 'SENT_EQUALS_PRODUCT_COST');
  }
  return done(SHADOW_CLASS.MISMATCH);
}

/**
 * One report per committed sale command. Lines that MATCH are only counted; every other line is
 * listed (bounded). Contains no customer, payment or credential data.
 */
export function buildSaleCostShadowReport({
  shadowKind, commandKind, lojaId, operationId, saleId = null, clientBuild = null,
  lines, products, consignmentOrigin = false, now = new Date(),
}) {
  const counters = Object.fromEntries(COUNTER_KEYS.map(k => [k, 0]));
  const listed = [];
  (Array.isArray(lines) ? lines : []).forEach((line, index) => {
    const result = classifySaleLine(line, {products, consignmentOrigin});
    counters.TOTAL_CHECKED++;
    counters[result.classification]++;
    if (result.classification !== SHADOW_CLASS.MATCH && listed.length < MAX_LOGGED_LINES) {
      listed.push({
        lineIndex: index,
        productId: result.productId ? clip(result.productId, 128) : null,
        variation: result.cellId ? clip(result.cellId, 160) : null,
        sentCost: result.sentCost,
        canonicalCost: result.canonicalCost,
        canonicalSource: result.canonicalSource,
        delta: result.delta,
        classification: result.classification,
        reason: result.reason,
        origemCustoItem: result.origemCustoItem,
      });
    }
  });
  const flagged = counters.MISMATCH + counters.SUSPECT_CLIENT_FALLBACK;
  return {
    severity: flagged > 0 ? 'WARNING' : 'INFO',
    message: SALE_COST_SHADOW,
    shadowKind,
    commandKind,
    storeHash: shortHash(lojaId, 12),
    operationRef: shortHash(operationId, 16),
    saleRef: saleId ? shortHash(saleId, 16) : null,
    clientBuild: typeof clientBuild === 'string' && clientBuild ? clientBuild : null,
    // Edited sales are compared with today's cost: a divergence there is not proof of a historical error.
    comparedWithCurrentCostOnly: shadowKind === SHADOW_KIND.SALE_EDIT,
    counters,
    lines: listed,
    linesTruncated: counters.TOTAL_CHECKED - counters.MATCH > listed.length,
    at: now.toISOString(),
  };
}

/** Logging must never change the command outcome. */
export function emitSaleCostShadow(report, logger = console) {
  try {
    const line = JSON.stringify(report);
    if (report?.severity === 'WARNING') logger.warn(line); else logger.info(line);
  } catch (_) {
    // Observability only.
  }
}
