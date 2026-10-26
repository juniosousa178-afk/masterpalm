/** READ-ONLY diagnostic for consignment lines priced before per-variation snapshots.
 * Pure functions: callers fetch documents of the consignment's own store. Never writes.
 */
import {consignmentSizePrices} from './consignmentStock.js';

const cents = v => Math.round(Number(v) * 100);

export function normalizeSizePriceKey(size) {
  const raw = String(size ?? '').trim();
  if (!raw) return 'sem-tamanho';
  const lower = raw.toLowerCase();
  if (lower === 'sem-tamanho') return lower;
  return lower.replace(/\s+/g, '');
}

function validMoney(raw) {
  const n = typeof raw === 'number' ? raw : Number(raw);
  return Number.isFinite(n) && n > 0 ? Math.round(n * 100) / 100 : null;
}

/** Same rule as the client `resolveConsignmentUnitPrice` for variation products. */
export function expectedVariationPrice({table, size, basePrice}) {
  const inherit = () => {
    const base = validMoney(basePrice);
    return base == null ? {price: null, source: 'UNRESOLVED'} : {price: base, source: 'INHERITED'};
  };
  if (!table || !Object.keys(table).length) return inherit();
  const s = String(size ?? '').trim();
  const exact = s || 'sem-tamanho';
  if (Object.prototype.hasOwnProperty.call(table, exact)) {
    const v = table[exact];
    return v == null ? {price: null, source: 'UNRESOLVED'} : {price: v, source: 'VARIATION'};
  }
  const wanted = normalizeSizePriceKey(s);
  const matches = Object.entries(table).filter(([k]) => normalizeSizePriceKey(k) === wanted).map(([, v]) => v);
  if (!matches.length) return inherit();
  if (matches.some(v => v == null)) return {price: null, source: 'UNRESOLVED'};
  const distinct = new Set(matches.map(cents));
  if (distinct.size !== 1) return {price: null, source: 'UNRESOLVED'};
  return {price: [...distinct][0] / 100, source: 'VARIATION'};
}

function productBasePrice(draft, stock) {
  return draft?.preco ?? draft?.precoVenda ?? stock?.preco ?? stock?.precoVenda;
}

function isVariationLine(line) {
  const vk = line?.variationKey;
  return !!vk && ['size', 'color', 'extra'].some(k => String(vk[k] ?? '').trim());
}

/**
 * @param consignment consignment document data
 * @param productsById Map(productId -> {draft, stock}) read from the SAME store
 */
export function diagnoseConsignment(consignment, productsById) {
  const lines = Array.isArray(consignment?.lines) ? consignment.lines : [];
  const out = {
    hasVariationProducts: false,
    mismatchedLines: 0,
    unresolvedLines: 0,
    sameSnapshotGroups: 0,
    divergenceCents: 0,
    absoluteDivergenceCents: 0,
    affected: false,
  };
  const groups = new Map();
  for (const line of lines) {
    if (!isVariationLine(line)) continue;
    out.hasVariationProducts = true;
    const product = productsById.get(String(line.productId ?? ''));
    if (!product) { out.unresolvedLines += 1; continue; }
    const table = consignmentSizePrices(product.draft, product.stock);
    if (!table) continue;
    const size = String(line.variationKey.size ?? '');
    const expected = expectedVariationPrice({table, size, basePrice: productBasePrice(product.draft, product.stock)});
    if (expected.price == null) { out.unresolvedLines += 1; continue; }
    const snap = cents(line.unitSalePriceSnapshot);
    const exp = cents(expected.price);
    const qty = Math.max(0, Math.trunc(Number(line.qtySent) || 0));
    if (snap !== exp) {
      out.mismatchedLines += 1;
      out.divergenceCents += qty * (exp - snap);
      out.absoluteDivergenceCents += qty * Math.abs(exp - snap);
    }
    const g = groups.get(line.productId) || [];
    g.push({size: normalizeSizePriceKey(size), exp, snap});
    groups.set(line.productId, g);
  }
  for (const g of groups.values()) {
    const sizes = new Set(g.map(e => e.size));
    if (sizes.size < 2) continue;
    if (new Set(g.map(e => e.exp)).size > 1 && new Set(g.map(e => e.snap)).size === 1) {
      out.sameSnapshotGroups += 1;
    }
  }
  out.affected = out.mismatchedLines > 0 || out.sameSnapshotGroups > 0;
  return out;
}

export function summarizeConsignmentDiagnostics(results) {
  const total = {
    consignmentsScanned: 0,
    consignmentsWithVariationProducts: 0,
    potentiallyAffectedConsignments: 0,
    mismatchedLines: 0,
    unresolvedLines: 0,
    sameSnapshotGroups: 0,
    divergenceCents: 0,
    absoluteDivergenceCents: 0,
    affectedByStatus: {},
  };
  for (const {status, result} of results) {
    total.consignmentsScanned += 1;
    if (result.hasVariationProducts) total.consignmentsWithVariationProducts += 1;
    total.mismatchedLines += result.mismatchedLines;
    total.unresolvedLines += result.unresolvedLines;
    total.sameSnapshotGroups += result.sameSnapshotGroups;
    total.divergenceCents += result.divergenceCents;
    total.absoluteDivergenceCents += result.absoluteDivergenceCents;
    if (result.affected) {
      total.potentiallyAffectedConsignments += 1;
      const key = String(status || 'UNKNOWN');
      total.affectedByStatus[key] = (total.affectedByStatus[key] || 0) + 1;
    }
  }
  return total;
}
