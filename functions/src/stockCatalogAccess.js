import {stockError} from './catalogStockProjection.js';
export const STOCK_PROTOCOL_VERSION = 1;
export const SERVER_PAYMENT_AUTH = Object.freeze({uid: 'stock-catalog-payment'});
export const SERVER_PUBLISH_AUTH = Object.freeze({uid: 'stock-catalog-publisher'});

/** Commands allowed on the inactive/legacy sale compatibility bridge.
 * restock is required to remove/decrease items on an already-saved PDV sale.
 * It does not authorize new variation sales (grant still applies only to kind=sale).
 */
export const INACTIVE_COMPAT_ALLOWED_KINDS = Object.freeze(['sale', 'restore', 'restock']);

/** Product mutation kinds allowed on the inactive/NO_CONTROL compatibility bridge. */
export const INACTIVE_PRODUCT_COMPAT_ALLOWED_KINDS = Object.freeze([
  'create', 'replace', 'editorial', 'delete',
]);

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
 * ACTIVE → current protocol; NO_CONTROL/INACTIVE → sale compat; anything else → fail closed.
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
  if (mode === 'inactive' && (version === STOCK_PROTOCOL_VERSION || version === undefined)) {
    return 'INACTIVE';
  }
  if (mode === 'maintenance') return 'INVALID';
  if (version !== undefined && version !== STOCK_PROTOCOL_VERSION) return 'INVALID';
  if (mode === 'active' && !migrationComplete) return 'INVALID';
  if (mode !== undefined && mode !== 'inactive' && mode !== 'active') return 'INVALID';
  // Partial/unknown shapes fail closed (do not treat as ordinary inactive).
  return 'INVALID';
}

export function isInactiveCompatRoute(route) {
  return route === 'NO_CONTROL' || route === 'INACTIVE';
}

function rejectReservedServerIdentity(auth, uid) {
  if ([SERVER_PUBLISH_AUTH, SERVER_PAYMENT_AUTH].some(identity => uid === identity.uid && auth !== identity)) {
    throw stockError('permission-denied', 'Reserved server identity');
  }
}

/** Dedicated store-scoped capability: authorize operation=reconcile only. */
export const STOCK_RECONCILIATION_GRANT = 'stockReconciliationGrant';
export const RECONCILIATION_CONTROL_COLLECTION = 'stock_reconciliation_control';
export const RECONCILIATION_OPERATORS_COLLECTION = 'stock_reconciliation_operators';

/** Store+product capability: authorize kind=sale for a normal variation product only. */
export const VARIATION_SALE_PRODUCT_GRANT = 'variationSaleProductGrant';
export const VARIATION_SALE_PRODUCT_GRANTS_COLLECTION = 'variation_sale_product_grants';
export const VARIATION_SALE_PRODUCT_NOT_AUTHORIZED = 'VARIATION_SALE_PRODUCT_NOT_AUTHORIZED';
export const GRADE_SALE_NOT_AUTHORIZED = 'GRADE_SALE_NOT_AUTHORIZED';

function isStrictEnabledFlag(value) {
  return value === true;
}

function failClosedGrantData(snap) {
  if (!snap?.exists) return null;
  const data = snap.data();
  if (!data || typeof data !== 'object' || Array.isArray(data)) return null;
  return data;
}

/**
 * Store-scoped reconciliation capability + technical operator.
 * Independent from stock protocol ACTIVE, membership, and stock_catalog_access.
 * Missing/false/malformed grant → RECONCILIATION_GRANT_REQUIRED (fail closed).
 * Missing/false operator → RECONCILIATION_OPERATOR_REQUIRED.
 */
export async function authorizeDedicatedReconciliation(tx, base, auth) {
  const uid = requireAuthenticated(auth);
  rejectReservedServerIdentity(auth, uid);
  const [grantSnap, operatorSnap] = await tx.getAll(
    base.collection(RECONCILIATION_CONTROL_COLLECTION).doc('state'),
    base.collection(RECONCILIATION_OPERATORS_COLLECTION).doc(uid),
  );
  const grant = failClosedGrantData(grantSnap);
  if (!grant || !isStrictEnabledFlag(grant.reconciliationEnabled)) {
    throw stockError('failed-precondition', 'RECONCILIATION_GRANT_REQUIRED');
  }
  const operator = failClosedGrantData(operatorSnap);
  if (!operator || !isStrictEnabledFlag(operator.enabled)) {
    throw stockError('permission-denied', 'RECONCILIATION_OPERATOR_REQUIRED');
  }
  return uid;
}

export function isWildcardProductId(productId) {
  return typeof productId !== 'string' || productId.includes('*');
}

/**
 * Fail-closed product grant for variation sales.
 * Missing / enabled!==true / malformed / wildcard → VARIATION_SALE_PRODUCT_NOT_AUTHORIZED.
 * Does not write. Clients cannot enable this (Admin SDK / catch-all rules deny).
 */
export function variationSaleProductGrantEnabled(snap) {
  const data = failClosedGrantData(snap);
  return !!(data && isStrictEnabledFlag(data.enabled));
}

export async function authorizeVariationSaleProduct(tx, base, productId) {
  if (isWildcardProductId(productId)) {
    throw stockError('permission-denied', VARIATION_SALE_PRODUCT_NOT_AUTHORIZED);
  }
  const id = documentId(productId, 'productId');
  const snap = await tx.get(base.collection(VARIATION_SALE_PRODUCT_GRANTS_COLLECTION).doc(id));
  if (!variationSaleProductGrantEnabled(snap)) {
    throw stockError('permission-denied', VARIATION_SALE_PRODUCT_NOT_AUTHORIZED);
  }
}

/** ACTIVE protocol: control + migrationComplete + dedicated grant. Unchanged semantics. */
export async function authorizeStockTransaction(tx, base, auth, permission) {
  const uid = requireAuthenticated(auth);
  rejectReservedServerIdentity(auth, uid);
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
 * Inactive/legacy sale bridge auth: authenticated store membership only.
 * Does NOT require ACTIVE, migrationComplete, or rollout grants.
 * Does NOT create control/grants/migration markers.
 * Intentionally allows sellers with vendas/sale — MUST NOT be reused for product/publish.
 * restock uses the same membership as sale so existing-sale item removal can restore stock.
 */
export async function authorizeInactiveLegacySale(tx, db, base, auth, kind) {
  const uid = requireAuthenticated(auth);
  rejectReservedServerIdentity(auth, uid);
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

function sellerHasProductCadastroPermission(perms) {
  if (!perms || typeof perms !== 'object' || Array.isArray(perms)) return false;
  return perms.estoque === true || perms.produtos === true || perms.cadastro === true ||
    perms.estoque_produtos === true || perms.product === true || perms.products === true;
}

/**
 * Owner/admin (or seller with explicit estoque/produtos/cadastro) membership.
 * Does NOT allow vendas-only sellers. Shared by product + publish inactive bridges.
 */
async function authorizeInactiveOwnerAdminOrCadastro(tx, db, base, auth) {
  const uid = requireAuthenticated(auth);
  rejectReservedServerIdentity(auth, uid);
  const [loja, seller, member] = await tx.getAll(
    base,
    base.collection('vendedores').doc(uid),
    base.collection('members').doc(uid),
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
    if (sellerHasProductCadastroPermission(perms)) return uid;
  }
  throw stockError('permission-denied', 'Stock operation not authorized for this store');
}

/**
 * Inactive/NO_CONTROL product mutation auth (create/replace/editorial/delete).
 * Separate from sale auth — vendas-only sellers are denied.
 */
export async function authorizeInactiveLegacyProductMutation(tx, db, base, auth, kind) {
  if (!INACTIVE_PRODUCT_COMPAT_ALLOWED_KINDS.includes(kind)) {
    throw stockError('failed-precondition', 'Stock protocol unavailable or migration incomplete');
  }
  return authorizeInactiveOwnerAdminOrCadastro(tx, db, base, auth);
}

/**
 * Inactive/NO_CONTROL catalog publish auth.
 * Separate from sale auth and from ACTIVE publisher grants.
 */
export async function authorizeInactiveLegacyPublish(tx, db, base, auth) {
  return authorizeInactiveOwnerAdminOrCadastro(tx, db, base, auth);
}

/**
 * Resolve route + authorize stockCatalogCommand.
 * reconcile → dedicated store grant + operator (never protocol ACTIVE / adjust / membership).
 * ACTIVE → grants; sale/restore/restock → sale membership; product kinds → product membership.
 */
export async function authorizeStockCommand(tx, db, base, auth, permission, kind) {
  if (kind === 'reconcile') {
    const uid = await authorizeDedicatedReconciliation(tx, base, auth);
    return {uid, route: STOCK_RECONCILIATION_GRANT, legacyCompat: false};
  }
  const control = await tx.get(base.collection('stock_catalog_control').doc('state'));
  const route = classifyStockControlState(control);
  if (route === 'ACTIVE') {
    const uid = await authorizeStockTransaction(tx, base, auth, permission);
    return {uid, route, legacyCompat: false};
  }
  if (route === 'INVALID') {
    throw stockError('failed-precondition', 'Stock protocol unavailable or migration incomplete');
  }
  // NO_CONTROL | INACTIVE
  if (INACTIVE_COMPAT_ALLOWED_KINDS.includes(kind)) {
    const uid = await authorizeInactiveLegacySale(tx, db, base, auth, kind);
    return {uid, route, legacyCompat: true};
  }
  if (INACTIVE_PRODUCT_COMPAT_ALLOWED_KINDS.includes(kind)) {
    const uid = await authorizeInactiveLegacyProductMutation(tx, db, base, auth, kind);
    return {uid, route, legacyCompat: true};
  }
  throw stockError('failed-precondition', 'Stock protocol unavailable or migration incomplete');
}

/**
 * Resolve route + authorize catalogPublishOne/All.
 * ACTIVE → grant publish; NO_CONTROL/INACTIVE → owner/admin publish bridge.
 */
export async function authorizePublishCommand(tx, db, base, auth) {
  const control = await tx.get(base.collection('stock_catalog_control').doc('state'));
  const route = classifyStockControlState(control);
  if (route === 'ACTIVE') {
    const uid = await authorizeStockTransaction(tx, base, auth, 'publish');
    return {uid, route, legacyCompat: false};
  }
  if (route === 'INVALID') {
    throw stockError('failed-precondition', 'Stock protocol unavailable or migration incomplete');
  }
  const uid = await authorizeInactiveLegacyPublish(tx, db, base, auth);
  return {uid, route, legacyCompat: true};
}
