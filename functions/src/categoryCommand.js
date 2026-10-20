// categoryCommand: the only writer of lojas/{lojaId}/categorias. Every operation validates first and writes in
// one transaction, so a refused command (depth, cycle, other store, name, children, products) commits nothing.
import {randomUUID} from 'node:crypto';
import {FieldValue} from 'firebase-admin/firestore';
import {authorizeNoControlEditorial, storeRef} from './stockCatalogAccess.js';
import {
  CATEGORY_CODES, CATEGORY_HAS_CHILDREN_MESSAGE, CATEGORY_HAS_PRODUCTS_MESSAGE, CategoryError, MAX_RENAME_DESCENDANTS,
  assertCanHaveChild, buildCategoryIndex, cleanCategoryName, deterministicCategoryId, findActiveChildByName,
  normalizeCategoryName, productCategoryIds, resolveCategoryRef, validateCategoryMove,
} from './categoryTree.js';

export const CATEGORY_PROTOCOL_VERSION = 1;
export const CATEGORY_OPERATIONS = Object.freeze(['create', 'rename', 'archive', 'reorder', 'move']);
const PRODUCT_COLLECTIONS = ['estoque_produtos', 'draft_produtos', 'produtos'];
const PRODUCT_CATEGORY_FIELDS = ['categoria', 'subcategoria', 'categoriasExtras', 'subcategoriasExtras',
  'categoriasAssociadas', 'subcategoriasAssociadas', 'categoryPathIds'];
const MAX_REORDER = 200;

const invalid = message => { throw new CategoryError(CATEGORY_CODES.INVALID_ARGUMENT, message, 'invalid-argument'); };
const isMap = v => v !== null && typeof v === 'object' && !Array.isArray(v);

function parseCommand(raw) {
  if (!isMap(raw)) invalid('Comando inválido.');
  if (raw.protocolVersion !== CATEGORY_PROTOCOL_VERSION) invalid('Versão de protocolo não suportada.');
  if (!CATEGORY_OPERATIONS.includes(raw.operation)) invalid('Operação inválida.');
  const operationId = typeof raw.operationId === 'string' ? raw.operationId.trim() : '';
  if (!/^[A-Za-z0-9_.:-]{1,128}$/.test(operationId)) invalid('operationId inválido.');
  if (raw.payload !== undefined && !isMap(raw.payload)) invalid('Payload inválido.');
  return {lojaId: raw.lojaId, operation: raw.operation, operationId, payload: raw.payload ?? {}};
}

export function publicCategory(node) {
  return node ? {
    id: node.id, nome: node.nome, parentId: node.parentId, depth: node.depth, pathIds: node.pathIds,
    pathNames: node.pathNames, sortOrder: node.sortOrder, isDeleted: node.isDeleted, legacyNames: node.legacyNames,
  } : null;
}

async function loadIndex(tx, base, lojaId) {
  const snap = await tx.get(base.collection('categorias'));
  const docs = snap.docs.map(d => ({id: d.id, data: d.data()}));
  const index = buildCategoryIndex(docs, lojaId);
  index.allIds = new Set(docs.map(d => d.id));
  return index;
}

/** Product category fields across the store; read outside the transaction so stock writes are never locked. */
async function loadProductCategoryRefs(base) {
  const out = [];
  for (const col of PRODUCT_COLLECTIONS) {
    let q = base.collection(col);
    if (typeof q.select === 'function') q = q.select(...PRODUCT_CATEGORY_FIELDS);
    const snap = await q.get();
    for (const d of snap.docs) out.push(d.data() || {});
  }
  return out;
}

function nextSortOrder(index, parentId) {
  const orders = index.childrenOf(parentId).map(n => n.sortOrder).filter(Number.isSafeInteger);
  return orders.length ? Math.max(...orders) + 1 : 0;
}

function pickNewId(index, parentId, nome) {
  const id = deterministicCategoryId(index.lojaId, parentId, nome);
  return index.allIds.has(id) ? deterministicCategoryId(index.lojaId, parentId, nome, randomUUID()) : id;
}

function createNode(ctx, parent, nome, extra = {}) {
  const {tx, base, index, cmd, writes} = ctx;
  assertCanHaveChild(parent?.depth ?? 0);
  const parentId = parent?.id ?? null;
  const id = pickNewId(index, parentId, nome);
  const node = {
    id, nome, parentId,
    depth: (parent?.depth ?? 0) + 1,
    pathIds: [...(parent?.pathIds ?? []), id],
    pathNames: [...(parent?.pathNames ?? []), nome],
    isDeleted: false,
    sortOrder: extra.sortOrder ?? nextSortOrder(index, parentId),
    legacyNames: extra.legacyNames ?? [],
  };
  // categorias is publicly readable (public catalog): never store actor identifiers here.
  tx.create(base.collection('categorias').doc(id), {
    id, lojaId: index.lojaId, nome, parentId, depth: node.depth, pathIds: node.pathIds, pathNames: node.pathNames,
    isDeleted: false, deletedAt: null, sortOrder: node.sortOrder, legacyNames: node.legacyNames, schemaVersion: 1,
    createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
    operationId: cmd.operationId,
  });
  index.nodes.set(id, node);
  index.allIds.add(id);
  writes.push(id);
  return node;
}

/** Turns a legacy (product-text only) path into docs; `lastExtra` customizes the innermost created doc. */
function materialize(ctx, resolved, lastExtra = {}) {
  if (resolved.node) return resolved.node;
  let parent = resolved.anchor ? ctx.index.nodes.get(resolved.anchor) : null;
  resolved.virtual.forEach((nome, i) => {
    const last = i === resolved.virtual.length - 1;
    parent = createNode(ctx, parent, last && lastExtra.nome ? lastExtra.nome : nome,
      last ? {legacyNames: lastExtra.legacyNames} : {});
  });
  return parent;
}

const depthAfter = (index, resolved) => resolved.node
  ? resolved.node.depth
  : (resolved.anchor ? index.nodes.get(resolved.anchor).depth : 0) + resolved.virtual.length;

function assertNameFree(index, parentId, nome, exceptId = null) {
  const clash = findActiveChildByName(index, parentId, nome);
  if (clash && clash.id !== exceptId) {
    throw new CategoryError(CATEGORY_CODES.NAME_TAKEN,
      normalizeCategoryName(clash.nome) === normalizeCategoryName(nome)
        ? 'Já existe uma categoria com este nome neste nível.'
        : `Este nome já foi usado pela categoria “${clash.nome}”.`);
  }
}

function opCreate(ctx) {
  const {index, cmd} = ctx;
  const nome = cleanCategoryName(cmd.payload.nome);
  const parentRef = cmd.payload.parent ?? null;
  const resolved = parentRef === null ? {node: null} : resolveCategoryRef(index, parentRef);
  assertCanHaveChild(parentRef === null ? 0 : depthAfter(index, resolved));
  if (!resolved.virtual) assertNameFree(index, resolved.node?.id ?? null, nome);
  const parent = parentRef === null ? null : materialize(ctx, resolved);
  return createNode(ctx, parent, nome);
}

function opRename(ctx) {
  const {tx, base, index, cmd, writes} = ctx;
  const nome = cleanCategoryName(cmd.payload.nome);
  const resolved = resolveCategoryRef(index, cmd.payload.target);
  if (resolved.virtual) {
    const oldName = resolved.virtual[resolved.virtual.length - 1];
    if (oldName === nome) return null;
    // Only the innermost name changes; its siblings exist only when its parent is already a doc.
    if (resolved.virtual.length === 1) assertNameFree(index, resolved.anchor, nome);
    return materialize(ctx, resolved, {
      nome,
      legacyNames: normalizeCategoryName(oldName) === normalizeCategoryName(nome) ? [] : [oldName],
    });
  }
  const node = resolved.node;
  if (node.nome === nome) return node;
  assertNameFree(index, node.parentId, nome, node.id);
  const descendants = index.descendantsOf(node.id);
  if (descendants.length > MAX_RENAME_DESCENDANTS) {
    throw new CategoryError(CATEGORY_CODES.TOO_MANY_DESCENDANTS,
      'Esta categoria tem subcategorias demais para renomear de uma vez.');
  }
  const legacyNames = normalizeCategoryName(node.nome) === normalizeCategoryName(nome)
    ? node.legacyNames
    : [...node.legacyNames.filter(l => normalizeCategoryName(l) !== normalizeCategoryName(nome)), node.nome];
  const at = node.depth - 1;
  const coll = base.collection('categorias');
  tx.update(coll.doc(node.id), {
    nome, pathNames: node.pathNames.map((n, i) => (i === at ? nome : n)), pathIds: node.pathIds, depth: node.depth,
    legacyNames, updatedAt: FieldValue.serverTimestamp(),
  });
  writes.push(node.id);
  for (const d of descendants) {
    tx.update(coll.doc(d.id), {
      pathNames: d.pathNames.map((n, i) => (i === at ? nome : n)), pathIds: d.pathIds, depth: d.depth,
      updatedAt: FieldValue.serverTimestamp(),
    });
    writes.push(d.id);
  }
  const renamed = {...node, nome, legacyNames, pathNames: node.pathNames.map((n, i) => (i === at ? nome : n))};
  index.nodes.set(node.id, renamed);
  return renamed;
}

function opArchive(ctx) {
  const {tx, base, index, cmd, writes, products} = ctx;
  const resolved = resolveCategoryRef(index, cmd.payload.target);
  if (resolved.virtual) throw new CategoryError(CATEGORY_CODES.HAS_PRODUCTS, CATEGORY_HAS_PRODUCTS_MESSAGE);
  const node = resolved.node;
  if (index.activeChildrenOf(node.id).length) {
    throw new CategoryError(CATEGORY_CODES.HAS_CHILDREN, CATEGORY_HAS_CHILDREN_MESSAGE);
  }
  if (products.some(p => productCategoryIds(index, p).has(node.id))) {
    throw new CategoryError(CATEGORY_CODES.HAS_PRODUCTS, CATEGORY_HAS_PRODUCTS_MESSAGE);
  }
  tx.update(base.collection('categorias').doc(node.id), {
    isDeleted: true, deletedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
  });
  writes.push(node.id);
  return {...node, isDeleted: true};
}

function opReorder(ctx) {
  const {tx, base, index, cmd, writes} = ctx;
  const parentRef = cmd.payload.parent ?? null;
  const refs = cmd.payload.orderedChildren;
  if (!Array.isArray(refs) || !refs.length || refs.length > MAX_REORDER) invalid('Ordem inválida.');
  const parentResolved = parentRef === null ? {node: null} : resolveCategoryRef(index, parentRef);
  const parent = parentRef === null ? null : materialize(ctx, parentResolved);
  const parentId = parent?.id ?? null;
  const ordered = refs.map((ref, i) => {
    if (isMap(ref) && Array.isArray(ref.legacyPath)) {
      const names = ref.legacyPath;
      if (names.length !== (parent?.depth ?? 0) + 1) invalid('Ordem inválida.');
      const found = findActiveChildByName(index, parentId, cleanCategoryName(names[names.length - 1]));
      return found ?? createNode(ctx, parent, cleanCategoryName(names[names.length - 1]), {sortOrder: i});
    }
    const {node} = resolveCategoryRef(index, ref, {allowLegacy: false});
    if (node.parentId !== parentId) invalid('Ordem inválida.');
    return node;
  });
  const ids = ordered.map(n => n.id);
  const expected = index.activeChildrenOf(parentId).map(n => n.id);
  if (new Set(ids).size !== ids.length || ids.length !== expected.length || !expected.every(id => ids.includes(id))) {
    throw new CategoryError(CATEGORY_CODES.STALE, 'A lista de categorias mudou. Atualize e tente novamente.');
  }
  ordered.forEach((n, i) => {
    if (n.sortOrder === i) return;
    if (!writes.includes(n.id)) {
      tx.update(base.collection('categorias').doc(n.id), {sortOrder: i, updatedAt: FieldValue.serverTimestamp()});
      writes.push(n.id);
    }
    index.nodes.set(n.id, {...n, sortOrder: i});
  });
  return parent;
}

function opMove(ctx) {
  const {index, cmd} = ctx;
  const target = resolveCategoryRef(index, cmd.payload.target, {allowLegacy: false}).node;
  const parentRef = cmd.payload.newParent ?? null;
  const newParent = parentRef === null ? null : resolveCategoryRef(index, parentRef, {allowLegacy: false}).node;
  validateCategoryMove(index, target.id, newParent?.id ?? null);
  throw new CategoryError(CATEGORY_CODES.REPARENT_DISABLED,
    'Mover categorias para outro nível ainda não está disponível. Renomeie ou crie uma nova categoria.');
}

const HANDLERS = {create: opCreate, rename: opRename, archive: opArchive, reorder: opReorder, move: opMove};

export async function executeCategoryCommand(db, raw, auth) {
  const cmd = parseCommand(raw);
  let base;
  try {
    base = storeRef(db, cmd.lojaId);
  } catch {
    invalid('Loja inválida.');
  }
  let products = [];
  if (cmd.operation === 'archive') {
    // Authorize before the store-wide product read so an outsider cannot trigger it.
    await db.runTransaction(tx => authorizeNoControlEditorial(tx, db, base, auth));
    products = await loadProductCategoryRefs(base);
  }
  return db.runTransaction(async tx => {
    await authorizeNoControlEditorial(tx, db, base, auth);
    const index = await loadIndex(tx, base, cmd.lojaId);
    const ctx = {tx, base, index, cmd, writes: [], products};
    const node = HANDLERS[cmd.operation](ctx);
    return {
      ok: true,
      operation: cmd.operation,
      operationId: cmd.operationId,
      category: publicCategory(node),
      writes: ctx.writes.length,
      writtenIds: ctx.writes,
    };
  });
}

/** Maps any thrown error to {http, message, details} for the callable wrapper. */
export function mapCategoryError(error) {
  if (error instanceof CategoryError) {
    return {http: error.http, message: error.message, details: {categoryCode: error.categoryCode}};
  }
  const code = typeof error?.code === 'string' ? error.code : '';
  if (code === 'permission-denied' || code === 'unauthenticated') {
    return {http: code, message: 'Sem permissão para alterar categorias desta loja.',
      details: {categoryCode: CATEGORY_CODES.PERMISSION_DENIED}};
  }
  if (code === 'invalid-argument') {
    return {http: code, message: error.message || 'Dados inválidos.', details: {categoryCode: CATEGORY_CODES.INVALID_ARGUMENT}};
  }
  if (error?.code === 6 || /ALREADY_EXISTS/.test(String(error?.message ?? ''))) {
    return {http: 'aborted', message: 'A lista de categorias mudou. Atualize e tente novamente.',
      details: {categoryCode: CATEGORY_CODES.STALE}};
  }
  return {http: 'internal', message: 'Não foi possível salvar a categoria.', details: {categoryCode: 'SERVER'}};
}
