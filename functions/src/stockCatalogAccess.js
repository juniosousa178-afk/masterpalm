import {stockError} from './catalogStockProjection.js';
export const STOCK_PROTOCOL_VERSION = 1;
export const SERVER_PAYMENT_AUTH = Object.freeze({uid: 'stock-catalog-payment'});
export const SERVER_PUBLISH_AUTH = Object.freeze({uid: 'stock-catalog-publisher'});
export function documentId(value, label = 'id') {
  if (typeof value !== 'string' || !value.trim() || value !== value.trim() || value.includes('/') ||
      value === '.' || value === '..' || /^__.*__$/.test(value) || Buffer.byteLength(value) > 256) {
    throw stockError('invalid-argument', `Invalid ${label}`);
  }
  return value;
}
export function requireAuthenticated(auth) {
  if (!auth?.uid) throw stockError('unauthenticated', 'Login required');
  return documentId(auth.uid, 'uid');
}
export function storeRef(db, lojaId) { return db.collection('lojas').doc(documentId(lojaId, 'lojaId')); }
export async function authorizeStockTransaction(tx, base, auth, permission) {
  const uid = requireAuthenticated(auth);
  if ([SERVER_PUBLISH_AUTH, SERVER_PAYMENT_AUTH].some(identity => uid === identity.uid && auth !== identity)) throw stockError('permission-denied', 'Reserved server identity');
  const [control, access] = await tx.getAll(
    base.collection('stock_catalog_control').doc('state'),
    base.collection('stock_catalog_access').doc(uid),
  );
  const state = control.data(), grant = access.data();
  if (!control.exists || state.protocolVersion !== STOCK_PROTOCOL_VERSION ||
      state.mode !== 'active' || state.migrationComplete !== true) {
    throw stockError('failed-precondition', 'Stock protocol unavailable or migration incomplete');
  }
  // Never consult role/email/storeId in user profiles or legacy membership.
  if (!access.exists || grant.enabled !== true || grant.permissions?.[permission] !== true) {
    throw stockError('permission-denied', 'Stock operation not authorized for this store');
  }
  return uid;
}
