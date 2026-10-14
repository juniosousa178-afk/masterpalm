/**
 * Post-commit catalog projection for consignment stock operations.
 * estoque_produtos is the only stock authority; draft_produtos/produtos are re-derived from it here.
 * Idempotent: every run re-reads canonical stock, skips documents already projected at that stockRevision,
 * never recreates editorial drafts, and can be repeated by the callable replay or the retry trigger.
 */
import {FieldValue} from 'firebase-admin/firestore';
import {storeRef, documentId} from './stockCatalogAccess.js';
import {projectCatalog, PROJECTION_VERSION} from './catalogStockProjection.js';

export const PROJECTION_STATUS = Object.freeze({PENDING: 'PENDING', DONE: 'DONE', INVALID: 'INVALID'});
export const PROJECTION_PRODUCTS_PER_TRANSACTION = 25;

// stockRevision only grows; a derived doc already at a newer revision must never be rewritten backwards.
function projectedNewer(stock, doc) {
  return Number.isFinite(doc?.catalogStockRevision) && Number.isFinite(stock.stockRevision) &&
    doc.catalogStockRevision > stock.stockRevision;
}

function projectionCurrent(stock, draft, live, projectedLive) {
  if (draft.catalogStockRevision !== stock.stockRevision) return false;
  if (draft.catalogProjectionVersion !== PROJECTION_VERSION) return false;
  if (!projectedLive) return !live.exists;
  return live.exists && live.data()?.catalogStockRevision === stock.stockRevision;
}

async function projectChunk(db, base, ids) {
  return db.runTransaction(async tx => {
    const refs = ids.flatMap(id => [
      base.collection('estoque_produtos').doc(id),
      base.collection('draft_produtos').doc(id),
      base.collection('produtos').doc(id),
    ]);
    const snaps = await tx.getAll(...refs);
    let written = 0;
    let skipped = 0;
    let stale = 0;
    const invalidIds = [];
    ids.forEach((id, i) => {
      const [stockSnap, draftSnap, liveSnap] = snaps.slice(i * 3, i * 3 + 3);
      if (!stockSnap.exists || !draftSnap.exists) { skipped++; return; }
      const stock = stockSnap.data() || {};
      const draft = draftSnap.data() || {};
      let projected;
      try { projected = projectCatalog(stock, draft, id); }
      catch { invalidIds.push(id); return; }
      if (projectedNewer(projected.stock, draft) || projectedNewer(projected.stock, liveSnap.data())) {
        stale++;
        return;
      }
      if (projectionCurrent(projected.stock, draft, liveSnap, projected.live)) { skipped++; return; }
      tx.set(refs[i * 3 + 1], {...projected.draft, updatedAt: FieldValue.serverTimestamp()});
      const liveRef = refs[i * 3 + 2];
      if (projected.live) tx.set(liveRef, {...projected.live, updatedAt: FieldValue.serverTimestamp()});
      else if (liveSnap.exists) tx.delete(liveRef);
      written++;
    });
    return {written, skipped, stale, invalidIds};
  });
}

/**
 * Projects the products recorded on consignment_operations/{operationId}.projection.
 * Returns {status: 'DONE'|'INVALID'|'SKIPPED'|'STOPPED'}; throws only on transaction failures (callers retry).
 * DONE is recorded only when every product was projected (or already current); unprojectable canonical
 * stock ends as INVALID with the product ids, never as DONE.
 */
export async function projectConsignmentCatalog(db, lojaId, operationId, {shouldStop = () => false} = {}) {
  const base = storeRef(db, lojaId);
  const opDocRef = base.collection('consignment_operations').doc(documentId(operationId, 'operationId'));
  const projection = await db.runTransaction(async tx => (await tx.get(opDocRef)).data()?.projection ?? null);
  if (!projection || projection.status !== PROJECTION_STATUS.PENDING) return {status: 'SKIPPED'};
  const ids = (Array.isArray(projection.productIds) ? projection.productIds : [])
    .map(id => documentId(id, 'productId'));
  const totals = {written: 0, skipped: 0, stale: 0};
  const invalidIds = [];
  for (let i = 0; i < ids.length; i += PROJECTION_PRODUCTS_PER_TRANSACTION) {
    if (shouldStop()) return {status: 'STOPPED', ...totals};
    const r = await projectChunk(db, base, ids.slice(i, i + PROJECTION_PRODUCTS_PER_TRANSACTION));
    totals.written += r.written;
    totals.skipped += r.skipped;
    totals.stale += r.stale;
    invalidIds.push(...r.invalidIds);
  }
  const status = invalidIds.length ? PROJECTION_STATUS.INVALID : PROJECTION_STATUS.DONE;
  await db.runTransaction(async tx => {
    const snap = await tx.get(opDocRef);
    if (snap.data()?.projection?.status !== PROJECTION_STATUS.PENDING) return;
    tx.update(opDocRef, {projection: {
      status,
      productIds: ids,
      ...totals,
      ...(invalidIds.length ? {invalidProductIds: invalidIds} : {}),
      completedAt: FieldValue.serverTimestamp(),
    }});
  });
  if (invalidIds.length) {
    console.warn('[consignmentProjection] invalid_canonical_stock', {lojaId, operationId, count: invalidIds.length});
  }
  return {status, ...totals, invalid: invalidIds.length};
}

/** consignmentProjectionRetry body: only the store and operation named by the event path are touched. */
export async function handleProjectionRetryEvent(db, event) {
  if (event.data?.data()?.projection?.status !== PROJECTION_STATUS.PENDING) return {status: 'SKIPPED'};
  return projectConsignmentCatalog(db, event.params.lojaId, event.params.operationId);
}
