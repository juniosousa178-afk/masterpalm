/**
 * Private variation cost (`__custoUnitario`) survives payloads that merely omit it.
 * Clients <= 1.0.152 could lose the cost locally and send the whole `variacoes` map without it;
 * omission is never a removal. A removal is explicit only through `variationCostRemovals`.
 * Costs never move between cells: identity is the same canonical `tamanho|cor` of the same document.
 */
import {createHash} from 'node:crypto';
import {isMap, normKey, stockError, META_COST, NO_EXTRA} from './catalogStockProjection.js';

export const VARIATION_COST_REMOVALS = 'variationCostRemovals';
const MAX_REMOVALS = 500;
const MAX_REMOVAL_LENGTH = 200;

export function validVariationCost(raw) {
  return typeof raw === 'number' && Number.isFinite(raw) && raw > 0 ? raw : null;
}

export function variationCellCost(cell) {
  return isMap(cell) ? validVariationCost(cell[META_COST]) : null;
}

/** Same identity as the client `variacaoId`, folded like the server `resolveKey`. */
export function variationCellId(size, color) {
  const s = normKey(size ?? ''), c = normKey(color ?? '');
  return `${s || 'sem-tamanho'}|${c || 'sem-cor'}`;
}

/** Canonical id -> {size, color, cell}; two cells with one identity are ambiguous. */
function cellsById(variacoes) {
  const out = new Map();
  if (!isMap(variacoes)) return out;
  for (const [size, colors] of Object.entries(variacoes)) {
    if (!isMap(colors)) continue;
    for (const [color, cell] of Object.entries(colors)) {
      if (color.trim() === META_COST) continue;
      const id = variationCellId(size, color);
      out.set(id, out.has(id) ? {ambiguous: true} : {size, color, cell});
    }
  }
  return out;
}

function uniqueCost(cells, id) {
  const entry = cells.get(id);
  return entry && !entry.ambiguous ? variationCellCost(entry.cell) : null;
}

/** Client ids (`tamanho|cor`, case preserved) -> sorted canonical ids. */
export function parseVariationCostRemovals(raw) {
  if (!Array.isArray(raw) || raw.length > MAX_REMOVALS) {
    throw stockError('invalid-argument', 'Invalid variationCostRemovals');
  }
  const ids = new Set();
  for (const value of raw) {
    const separator = typeof value === 'string' ? value.indexOf('|') : -1;
    if (separator < 0 || !value.trim() || value.length > MAX_REMOVAL_LENGTH) {
      throw stockError('invalid-argument', 'Invalid variation cost removal');
    }
    ids.add(variationCellId(value.slice(0, separator), value.slice(separator + 1)));
  }
  return [...ids].sort();
}

/** A cell cannot carry a cost and ask for its removal in the same payload. */
export function assertRemovalsMatchPayload(variacoes, removals) {
  const removed = new Set(removals);
  for (const [id, entry] of cellsById(variacoes)) {
    if (removed.has(id) && !entry.ambiguous && variationCellCost(entry.cell) !== null) {
      throw stockError('invalid-argument', 'Conflicting variation cost removal');
    }
  }
}

function withCost(cell, cost) {
  if (isMap(cell)) return {...cell, [META_COST]: cost};
  if (Number.isSafeInteger(cell) && cell >= 0) return {[NO_EXTRA]: cell, [META_COST]: cost};
  return null;
}

/**
 * Incoming cells without a valid cost keep the valid cost of the same canonical cell in [before],
 * unless the id is in [removals]. Quantities and cells absent from [incoming] are untouched;
 * ambiguous identities (either side) are left as sent.
 */
export function preserveVariationCosts({before, incoming, removals = []}) {
  const result = {variacoes: incoming, preserved: []};
  if (!isMap(incoming) || !isMap(before)) return result;
  const prior = cellsById(before);
  if (![...prior.keys()].some(id => uniqueCost(prior, id) !== null)) return result;
  const sent = cellsById(incoming);
  const removed = new Set(removals);
  const out = {};
  for (const [size, colors] of Object.entries(incoming)) {
    if (!isMap(colors)) { out[size] = colors; continue; }
    const inner = {};
    for (const [color, cell] of Object.entries(colors)) {
      inner[color] = cell;
      if (color.trim() === META_COST || variationCellCost(cell) !== null) continue;
      const id = variationCellId(size, color);
      if (removed.has(id) || sent.get(id)?.ambiguous) continue;
      const cost = uniqueCost(prior, id);
      const restored = cost === null ? null : withCost(cell, cost);
      if (restored === null) continue;
      inner[color] = restored;
      result.preserved.push(id);
    }
    out[size] = inner;
  }
  if (result.preserved.length) {
    result.variacoes = out;
    result.preserved.sort();
  }
  return result;
}

function sameTenant(lojaId, before, after) {
  for (const doc of [before, after]) {
    const owner = doc?.lojaId;
    if (owner !== undefined && owner !== null && String(owner) !== lojaId) return false;
  }
  return true;
}

/** Direct-write plan for one document version change; fails closed on tenant mismatch. */
export function planVariationCostRestore({lojaId, before, after, removals = []}) {
  if (!sameTenant(lojaId, before, after)) return {variacoes: after?.variacoes, preserved: [], skipped: 'TENANT_MISMATCH'};
  return preserveVariationCosts({before: before?.variacoes, incoming: after?.variacoes, removals});
}

const lojaHash = lojaId => createHash('sha256').update(String(lojaId)).digest('hex').slice(0, 12);
const validDocId = id => typeof id === 'string' && id.length > 0 && id.length <= 1500 && !id.includes('/') && id !== '.' && id !== '..';

/**
 * `estoque_produtos` write trigger. Restores only when the document still carries the exact stock
 * lineage of the event (stockRevision + stockOperationId); never changes quantities, revision,
 * operation id or pending fields. Removals recorded by stockCatalogCommand are honored.
 */
export async function handleVariationCostGuardEvent(db, event, {collection = 'lojas'} = {}) {
  const beforeSnap = event?.data?.before, afterSnap = event?.data?.after;
  if (!beforeSnap?.exists || !afterSnap?.exists) return {action: 'skip', reason: 'NOT_UPDATE'};
  const {lojaId, productId} = event.params ?? {};
  if (!validDocId(lojaId) || !validDocId(productId)) return {action: 'skip', reason: 'INVALID_PATH'};
  const before = beforeSnap.data(), after = afterSnap.data();
  const firstPass = planVariationCostRestore({lojaId, before, after});
  if (!firstPass.preserved.length) return {action: 'noop', reason: firstPass.skipped ?? null};
  const base = db.collection(collection).doc(lojaId);
  const ref = base.collection('estoque_produtos').doc(productId);
  const operationId = String(after.stockOperationId ?? '').trim();
  const outcome = await db.runTransaction(async tx => {
    const [current, op] = validDocId(operationId)
      ? await tx.getAll(ref, base.collection('stock_catalog_operations').doc(operationId))
      : [await tx.get(ref), null];
    if (!current.exists) return {action: 'skip', reason: 'DELETED'};
    const now = current.data();
    if ((now.stockRevision ?? null) !== (after.stockRevision ?? null) ||
        String(now.stockOperationId ?? '').trim() !== operationId) {
      return {action: 'skip', reason: 'STALE'};
    }
    const opData = op?.exists ? op.data() : null;
    const removals = opData?.status === 'applied' && Array.isArray(opData.result?.productIds) &&
      opData.result.productIds.includes(productId) && Array.isArray(opData[VARIATION_COST_REMOVALS])
      ? opData[VARIATION_COST_REMOVALS]
      : [];
    const plan = planVariationCostRestore({lojaId, before, after: now, removals});
    if (!plan.preserved.length) return {action: 'noop', reason: plan.skipped ?? null};
    tx.update(ref, {variacoes: plan.variacoes});
    return {action: 'restored', preserved: plan.preserved};
  });
  console.info(JSON.stringify({
    event: 'VARIATION_COST_GUARD', action: outcome.action, reason: outcome.reason ?? null,
    loja: lojaHash(lojaId), productId, cells: outcome.preserved?.length ?? 0,
  }));
  return outcome;
}
