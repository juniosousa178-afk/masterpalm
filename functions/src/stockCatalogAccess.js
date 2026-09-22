import {stockError} from './catalogStockProjection.js';
export const STOCK_PROTOCOL_VERSION = 1;
export const SERVER_PAYMENT_AUTH = Object.freeze({uid: 'stock-catalog-payment'});
export const SERVER_PUBLISH_AUTH = Object.freeze({uid: 'stock-catalog-publisher'});

/** Commands allowed on the inactive/legacy sale compatibility bridge only. */
export const INACTIVE_COMPAT_ALLOWED_KINDS = Object.freeze(['sale', 'restore']);

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

/**
 * Classify stock_catalog_control/state for routing.
 * ACTIVE → grant protocol; NO_CONTROL (absent) → legacy sale/restore;
 * INACTIVE/INVALID/incomplete → fail closed (ticket preference: present-but-not-ACTIVE
 * must not silently fall through to legacy).
 */
export function classifyStockControlState(controlSnap) {
  if (!controlSnap?.exists) return 'NO_CONTROL';
  const state = controlSnap.data();
  if (!state || typeof state !== 'object' || Array.isArray(state)) return 'INVALID';
  const version = state.protocolVersion;
  const mode = state.mode;
  const migrationComplete = state.migrationComplete === true;
  if (version === STOCK_PROTOCOL_VERSION && mode === 'active' && migrationComplete) {
    return 'ACTIVE';
  }
  // Present but not fully ACTIVE: fail closed (includes mode=inactive, wrong version,
  // migrationComplete=false). Stricter than historical INACTIVE→legacy for security.
  if (mode === 'maintenance') return 'INVALID';
  if (version !== undefined && version !== STOCK_PROTOCOL_VERSION) return 'INVALID';
  if (mode === 'active' && !migrationComplete) return 'INVALID';
  if (mode === 'inactive') return 'INVALID';
  if (mode !== undefined && mode !== 'inactive' && mode !== 'active') return 'INVALID';
  return 'INVALID';
}

export function isInactiveCompatRoute(route) {
  return route === 'NO_CONTROL';
}

/** ACTIVE protocol: control + migrationComplete + dedicated grant. Unchanged semantics. */
export async function authorizeStockTransaction(tx, base, auth, permission) {
  const uid = requireAuthenticated(auth);
  if ([SERVER_PUBLISH_AUTH, SERVER_PAYMENT_AUTH].some(identity => uid === identity.uid && auth !== identity)) {
    throw stockError('permission-denied', 'Reserved server identity');
  }
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

/**
 * Legacy NO_CONTROL sale bridge: authenticated store membership only.
 * Does NOT require ACTIVE, migrationComplete, or rollout grants.
 * Does NOT create control/grants/migration markers.
 */
export async function authorizeInactiveLegacySale(tx, db, base, auth, kind) {
  const uid = requireAuthenticated(auth);
  if ([SERVER_PUBLISH_AUTH, SERVER_PAYMENT_AUTH].some(identity => uid === identity.uid && auth !== identity)) {
    throw stockError('permission-denied', 'Reserved server identity');
  }
  if (!INACTIVE_COMPAT_ALLOWED_KINDS.includes(kind)) {
    throw stockError('failed-precondition', 'Stock protocol unavailable or migration incomplete');
  }
  const [loja, seller, member, user] = await tx.getAll(
    base,
    base.collection('vendedores').doc(uid),
    base.collection('members').doc(uid),
    db.collection('users').doc(uid),
  );
  if (!loja.exists) throw stockError('permission-denied', 'Store not found');
  const data = loja.data() || {};
  if (data.ownerUid === uid) return uid;
  if (data.admins && data.admins[uid] === true) return uid;
  if (member.exists) {
    const role = (member.data()?.role ?? '').toString();
    if (role === 'owner' || role === 'admin') return uid;
  }
  if (seller.exists && seller.data()?.ativo === true) {
    const perms = seller.data()?.permissoes || {};
    if (perms.vendas === true || perms.sale === true) return uid;
    // Active seller without explicit deny may sell in legacy PDV.
    if (!Object.keys(perms).length) return uid;
  }
  if (user.exists) {
    const ud = user.data() || {};
    const storeId = (ud.store_id || ud.storeId || '').toString();
    if (storeId && storeId === base.id) {
      if (!data.ownerUid || data.ownerUid === uid) return uid;
    }
  }
  throw stockError('permission-denied', 'Stock operation not authorized for this store');
}

/**
 * Resolve route + authorize.
 * ACTIVE → grants; NO_CONTROL → membership sale/restore; anything else → fail closed.
 */
export async function authorizeStockCommand(tx, db, base, auth, permission, kind) {
  const control = await tx.get(base.collection('stock_catalog_control').doc('state'));
  const route = classifyStockControlState(control);
  if (route === 'ACTIVE') {
    const uid = await authorizeStockTransaction(tx, base, auth, permission);
    return {uid, route, legacyCompat: false};
  }
  if (route === 'NO_CONTROL') {
    const uid = await authorizeInactiveLegacySale(tx, db, base, auth, kind);
    return {uid, route, legacyCompat: true};
  }
  // INVALID / present-but-incomplete / mode=inactive → fail closed
  throw stockError('failed-precondition', 'Stock protocol unavailable or migration incomplete');
}
