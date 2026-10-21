/**
 * Bulk removal of the per-product Pix discount (`percentualDescontoPix`).
 * Server reads the canonical documents and writes only that field (plus updatedAt);
 * stock, revision, price, promotions, categories and variations are never part of the write.
 */
import {createHash} from 'node:crypto';
import {FieldValue} from 'firebase-admin/firestore';
import {documentId, storeRef, requireAuthenticated, authorizeStockCommand} from './stockCatalogAccess.js';
import {isMap, stockError} from './catalogStockProjection.js';
import {parseClientBuild} from './stockCatalogSaleEdit.js';

export const BULK_PIX_KIND = 'removePixDiscount';
export const PIX_DISCOUNT_FIELD = 'percentualDescontoPix';
/** Value every client already reads as "no Pix discount" (all readers test `> 0`). */
export const NO_PIX_DISCOUNT = 0;
/** Up to 3 narrow updates per product (stock, draft, live) + 1 operation marker within the 100-write budget. */
export const MAX_PRODUCTS_PER_BULK_PIX_OPERATION = 30;
const WRITE_BUDGET = 100;
export const BULK_PIX_OPERATION_ID = /^pixrm_[A-Za-z0-9_-]{8,120}$/;
const ALLOWED_KEYS = ['protocolVersion', 'lojaId', 'operationId', 'kind', 'productIds', 'bulkId', 'clientBuild'];

const ordered = value => Array.isArray(value) ? value.map(ordered) : isMap(value)
  ? Object.fromEntries(Object.keys(value).sort().map(k => [k, ordered(value[k])])) : value;
const fingerprint = value => createHash('sha256').update(JSON.stringify(ordered(value))).digest('hex');

function bulkError(code, message, details) {
  const error = stockError(code, message);
  error.details = details;
  return error;
}

/** True when a stored value would show a Pix discount to any reader (numbers or numeric strings > 0). */
export function hasPixDiscount(value) {
  if (typeof value === 'number') return value > 0;
  if (typeof value === 'string') return Number(value.trim()) > 0;
  return false;
}

export function parseBulkPixCommand(raw) {
  if (!isMap(raw) || Object.keys(raw).some(k => !ALLOWED_KEYS.includes(k))) {
    throw stockError('invalid-argument', 'Unknown or protected command field');
  }
  if (raw.protocolVersion !== 1) throw stockError('failed-precondition', 'Unsupported stock protocol');
  if (raw.kind !== BULK_PIX_KIND) throw stockError('invalid-argument', 'Unsupported command');
  documentId(raw.lojaId, 'lojaId');
  documentId(raw.operationId, 'operationId');
  if (!BULK_PIX_OPERATION_ID.test(raw.operationId)) throw stockError('invalid-argument', 'Invalid operationId');
  if (!Array.isArray(raw.productIds) || raw.productIds.length === 0) {
    throw stockError('invalid-argument', 'productIds required');
  }
  // Never truncate: the client chunks explicitly.
  if (raw.productIds.length > MAX_PRODUCTS_PER_BULK_PIX_OPERATION) {
    throw bulkError('resource-exhausted', 'Too many products', {
      code: 'BULK_PIX_TOO_MANY_PRODUCTS', reason: `MAX_${MAX_PRODUCTS_PER_BULK_PIX_OPERATION}`,
    });
  }
  const seen = new Set();
  for (const id of raw.productIds) {
    documentId(id, 'productId');
    if (seen.has(id)) {
      throw bulkError('invalid-argument', 'Duplicate productId', {code: 'BULK_PIX_DUPLICATE_PRODUCT', productId: id});
    }
    seen.add(id);
  }
  if ('bulkId' in raw) documentId(raw.bulkId, 'bulkId');
  return {
    protocolVersion: 1,
    lojaId: raw.lojaId,
    operationId: raw.operationId,
    kind: BULK_PIX_KIND,
    productIds: [...seen].sort(),
    bulkId: raw.bulkId ?? null,
    clientBuild: parseClientBuild(raw.clientBuild),
  };
}

function resultFromOperation(data, operationId) {
  return {
    operationId,
    kind: BULK_PIX_KIND,
    requestedCount: data.requestedCount,
    updatedCount: data.updatedCount,
    noopCount: data.noopCount,
    failedCount: data.failedCount,
    updatedProductIds: [...(data.result?.updatedProductIds ?? [])],
    noopProductIds: [...(data.result?.noopProductIds ?? [])],
  };
}

/**
 * All-or-nothing per operation: any missing, deleted or foreign product rejects the whole
 * request before writing. Products already without a Pix discount are counted and never written.
 */
export async function executeBulkRemovePixDiscountInTransaction(tx, db, raw, auth) {
  requireAuthenticated(auth);
  const command = parseBulkPixCommand(raw);
  const base = storeRef(db, command.lojaId);
  const {uid, legacyCompat} = await authorizeStockCommand(tx, db, base, auth, 'editorial', 'editorial');
  const {clientBuild: _clientBuild, ...hashable} = command;
  const hash = fingerprint(hashable);
  const opRef = base.collection('stock_catalog_operations').doc(command.operationId);
  const op = await tx.get(opRef);
  if (op.exists) {
    const data = op.data();
    if (data.kind !== BULK_PIX_KIND || data.requestHash !== hash || data.actorUid !== uid) {
      throw bulkError('already-exists', 'Operation identity conflict', {code: 'OPERATION_PAYLOAD_CONFLICT'});
    }
    return {alreadyApplied: true, ...resultFromOperation(data, command.operationId)};
  }

  const rows = [];
  for (const id of command.productIds) {
    const stockRef = base.collection('estoque_produtos').doc(id);
    const draftRef = base.collection('draft_produtos').doc(id);
    const liveRef = base.collection('produtos').doc(id);
    const [stock, draft, live, tombstone] = await tx.getAll(
      stockRef, draftRef, liveRef, base.collection('exclusao_produto').doc(id),
    );
    if (!stock.exists) {
      throw bulkError('failed-precondition', 'Product unavailable', {
        code: 'BULK_PIX_PRODUCT_UNAVAILABLE', reason: 'NOT_FOUND', productId: id,
      });
    }
    if (stock.data()?.pendingSoftDelete === true || (tombstone.exists && tombstone.data()?.p === true)) {
      throw bulkError('failed-precondition', 'Product unavailable', {
        code: 'BULK_PIX_PRODUCT_UNAVAILABLE', reason: 'DELETED', productId: id,
      });
    }
    const targets = [[stockRef, stock], [draftRef, draft], [liveRef, live]]
      .filter(([, snap]) => snap.exists && hasPixDiscount(snap.data()?.[PIX_DISCOUNT_FIELD]))
      .map(([ref]) => ref);
    rows.push({id, targets});
  }

  const updatedProductIds = rows.filter(r => r.targets.length > 0).map(r => r.id);
  const noopProductIds = rows.filter(r => r.targets.length === 0).map(r => r.id);
  const writeCount = rows.reduce((n, r) => n + r.targets.length, 0) + 1;
  if (writeCount > WRITE_BUDGET) throw stockError('resource-exhausted', 'Stock transaction write budget exceeded');

  for (const row of rows) {
    for (const ref of row.targets) {
      tx.update(ref, {[PIX_DISCOUNT_FIELD]: NO_PIX_DISCOUNT, updatedAt: FieldValue.serverTimestamp()});
    }
  }
  const counts = {
    requestedCount: command.productIds.length,
    updatedCount: updatedProductIds.length,
    noopCount: noopProductIds.length,
    failedCount: 0,
  };
  tx.create(opRef, {
    actorUid: uid,
    kind: BULK_PIX_KIND,
    requestHash: hash,
    status: 'applied',
    lojaId: command.lojaId,
    bulkId: command.bulkId,
    items: [],
    ...counts,
    result: {productIds: command.productIds, updatedProductIds, noopProductIds},
    legacyCompat: legacyCompat === true,
    ...(command.clientBuild ? {clientBuild: command.clientBuild} : {}),
    createdAt: FieldValue.serverTimestamp(),
  });
  return {
    alreadyApplied: false,
    operationId: command.operationId,
    kind: BULK_PIX_KIND,
    ...counts,
    updatedProductIds,
    noopProductIds,
  };
}
