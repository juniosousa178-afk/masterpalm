import {stockError} from './catalogStockProjection.js';
export const STOCK_PROTOCOL_VERSION = 1;
export const SERVER_PAYMENT_AUTH = Object.freeze({uid: 'stock-catalog-payment'});
export const SERVER_PUBLISH_AUTH = Object.freeze({uid: 'stock-catalog-publisher'});

/** Sale/restore remain on the inactive/legacy sale compatibility bridge. */
export const INACTIVE_COMPAT_ALLOWED_KINDS = Object.freeze(['sale', 'restore']);

/**
 * NO_CONTROL kinds beyond sale/restore — each role-scoped separately.
 * Never implies ACTIVE protocol, grants, or migration.
 */
export const NO_CONTROL_EDITORIAL_KINDS = Object.freeze(['editorial']);
export const NO_CONTROL_STOCK_EDIT_KINDS = Object.freeze(['replace', 'create']);
export const NO_CONTROL_PUBLISH_PERMISSION = 'publish';

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
 * ACTIVE → grant protocol; NO_CONTROL (absent) → legacy sale/restore + narrow editorial/stock-edit/publish;
 * INACTIVE/INVALID/incomplete → fail closed.
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
  if (!access.exists || grant.enabled !== true || grant.permissions?.[permission] !== true) {
    throw stockError('permission-denied', 'Stock operation not authorized for this store');
  }
  return uid;
}

async function loadMembership(tx, db, base, uid) {
  const [loja, seller, member, user] = await tx.getAll(
    base,
    base.collection('vendedores').doc(uid),
    base.collection('members').doc(uid),
    db.collection('users').doc(uid),
  );
  if (!loja.exists) throw stockError('permission-denied', 'Store not found');
  return {loja, seller, member, user, data: loja.data() || {}};
}

function isOwnerOrAdmin({loja, member, user, data, uid, base}) {
  if (data.ownerUid === uid) return true;
  if (data.admins && data.admins[uid] === true) return true;
  if (member.exists) {
    const role = (member.data()?.role ?? '').toString();
    if (role === 'owner' || role === 'admin') return true;
  }
  if (user.exists) {
    const ud = user.data() || {};
    const storeId = (ud.store_id || ud.storeId || '').toString();
    if (storeId && storeId === base.id) {
      if (!data.ownerUid || data.ownerUid === uid) return true;
    }
  }
  return false;
}

function isActiveSellerWithSalePerm({seller}) {
  if (!seller.exists || seller.data()?.ativo !== true) return false;
  const perms = seller.data()?.permissoes || {};
  if (perms.vendas === true || perms.sale === true) return true;
  if (!Object.keys(perms).length) return true;
  return false;
}

function isSellerWithCatalogEditPerm({seller}) {
  if (!seller.exists || seller.data()?.ativo !== true) return false;
  const perms = seller.data()?.permissoes || {};
  return perms.produtos === true ||
    perms.estoque === true ||
    perms.cadastro === true ||
    perms.catalogo === true ||
    perms.editStock === true;
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
  const membership = await loadMembership(tx, db, base, uid);
  if (isOwnerOrAdmin({...membership, uid, base})) return uid;
  if (isActiveSellerWithSalePerm(membership)) return uid;
  throw stockError('permission-denied', 'Stock operation not authorized for this store');
}

/** NO_CONTROL editorial: owner/admin or seller with catalog/product edit permission. */
export async function authorizeNoControlEditorial(tx, db, base, auth) {
  const uid = requireAuthenticated(auth);
  if ([SERVER_PUBLISH_AUTH, SERVER_PAYMENT_AUTH].some(identity => uid === identity.uid && auth !== identity)) {
    throw stockError('permission-denied', 'Reserved server identity');
  }
  const membership = await loadMembership(tx, db, base, uid);
  if (isOwnerOrAdmin({...membership, uid, base})) return uid;
  if (isSellerWithCatalogEditPerm(membership)) return uid;
  throw stockError('permission-denied', 'Editorial not authorized for this store');
}

/**
 * NO_CONTROL stock edit (replace/create): owner/admin only.
 * Sale-only vendedor is never authorized.
 */
export async function authorizeNoControlStockEdit(tx, db, base, auth, kind) {
  const uid = requireAuthenticated(auth);
  if ([SERVER_PUBLISH_AUTH, SERVER_PAYMENT_AUTH].some(identity => uid === identity.uid && auth !== identity)) {
    throw stockError('permission-denied', 'Reserved server identity');
  }
  if (!NO_CONTROL_STOCK_EDIT_KINDS.includes(kind)) {
    throw stockError('failed-precondition', 'Stock protocol unavailable or migration incomplete');
  }
  const membership = await loadMembership(tx, db, base, uid);
  if (isOwnerOrAdmin({...membership, uid, base})) return uid;
  throw stockError('permission-denied', 'Stock edit not authorized for this store');
}

/** NO_CONTROL catalog publish: owner/admin only. Does not mutate canonical stock. */
export async function authorizeNoControlPublish(tx, db, base, auth) {
  const uid = requireAuthenticated(auth);
  if ([SERVER_PUBLISH_AUTH, SERVER_PAYMENT_AUTH].some(identity => uid === identity.uid && auth !== identity)) {
    throw stockError('permission-denied', 'Reserved server identity');
  }
  const membership = await loadMembership(tx, db, base, uid);
  if (isOwnerOrAdmin({...membership, uid, base})) return uid;
  throw stockError('permission-denied', 'Catalog publish not authorized for this store');
}

/**
 * Resolve route + authorize.
 * ACTIVE → grants; NO_CONTROL → kind-scoped membership; anything else → fail closed.
 */
export async function authorizeStockCommand(tx, db, base, auth, permission, kind) {
  const control = await tx.get(base.collection('stock_catalog_control').doc('state'));
  const route = classifyStockControlState(control);
  if (route === 'ACTIVE') {
    const uid = await authorizeStockTransaction(tx, base, auth, permission);
    return {uid, route, legacyCompat: false};
  }
  if (route === 'NO_CONTROL') {
    if (INACTIVE_COMPAT_ALLOWED_KINDS.includes(kind)) {
      const uid = await authorizeInactiveLegacySale(tx, db, base, auth, kind);
      return {uid, route, legacyCompat: true};
    }
    if (NO_CONTROL_EDITORIAL_KINDS.includes(kind)) {
      const uid = await authorizeNoControlEditorial(tx, db, base, auth);
      return {uid, route, legacyCompat: true};
    }
    if (NO_CONTROL_STOCK_EDIT_KINDS.includes(kind)) {
      const uid = await authorizeNoControlStockEdit(tx, db, base, auth, kind);
      return {uid, route, legacyCompat: true};
    }
    throw stockError('failed-precondition', 'Stock protocol unavailable or migration incomplete');
  }
  throw stockError('failed-precondition', 'Stock protocol unavailable or migration incomplete');
}

/**
 * Publish authorization: ACTIVE grant publish, or NO_CONTROL owner/admin.
 */
export async function authorizePublish(tx, db, base, auth) {
  const control = await tx.get(base.collection('stock_catalog_control').doc('state'));
  const route = classifyStockControlState(control);
  if (route === 'ACTIVE') {
    const uid = await authorizeStockTransaction(tx, base, auth, NO_CONTROL_PUBLISH_PERMISSION);
    return {uid, route, legacyCompat: false};
  }
  if (route === 'NO_CONTROL') {
    const uid = await authorizeNoControlPublish(tx, db, base, auth);
    return {uid, route, legacyCompat: true};
  }
  throw stockError('failed-precondition', 'Stock protocol unavailable or migration incomplete');
}
