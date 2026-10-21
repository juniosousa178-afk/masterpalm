// Hierarchical product categories (lojas/{lojaId}/categorias). Pure helpers shared by categoryCommand and
// stockCatalogCommand. A product may be filed under several paths (categoryAssignments); products saved before
// that keep a single categoryId/categoryPathIds/categoryPathNames triple, and products without either are placed
// in the tree by their legacy text fields (categoria/subcategoria/extras), so no migration writes are needed.
import {createHash} from 'node:crypto';

export const MAX_CATEGORY_DEPTH = 6;
export const MAX_CATEGORY_NAME_LENGTH = 60;
/** Rename rewrites the node and every descendant in one transaction; keep it far below the 500-write cap. */
export const MAX_RENAME_DESCENDANTS = 400;
export const CATEGORY_DEPTH_LIMIT_MESSAGE = 'Você pode criar categorias em até 6 níveis.';
export const CATEGORY_HAS_CHILDREN_MESSAGE = 'Esta categoria possui subcategorias.';
export const CATEGORY_HAS_PRODUCTS_MESSAGE = 'Esta categoria possui produtos. Mova os produtos para outra categoria antes de excluir.';
/**
 * Paths per product. Worst case per doc: 20 x 6 ids/names (~25 KB) plus <=120 categoryMembershipIds entries,
 * far below the 1 MiB doc and 40k index-entry limits; the merchant UI stays a short list of cards.
 */
export const MAX_CATEGORY_ASSIGNMENTS = 20;
export const CATEGORY_ASSIGNMENTS_LIMIT_MESSAGE = `Um produto pode estar em até ${MAX_CATEGORY_ASSIGNMENTS} categorias.`;
export const LEGACY_PRODUCT_CATEGORY_KEYS = Object.freeze(['categoryId', 'categoryPathIds', 'categoryPathNames']);
export const PRODUCT_CATEGORY_KEYS = Object.freeze([...LEGACY_PRODUCT_CATEGORY_KEYS, 'categoryAssignments']);

export const CATEGORY_CODES = Object.freeze({
  INVALID_ARGUMENT: 'CATEGORY_INVALID_ARGUMENT',
  NOT_FOUND: 'CATEGORY_NOT_FOUND',
  DEPTH_LIMIT: 'CATEGORY_DEPTH_LIMIT',
  CYCLE: 'CATEGORY_CYCLE',
  CROSS_TENANT: 'CATEGORY_CROSS_TENANT',
  NAME_TAKEN: 'CATEGORY_NAME_TAKEN',
  HAS_CHILDREN: 'CATEGORY_HAS_CHILDREN',
  HAS_PRODUCTS: 'CATEGORY_HAS_PRODUCTS',
  REPARENT_DISABLED: 'CATEGORY_REPARENT_DISABLED',
  TOO_MANY_DESCENDANTS: 'CATEGORY_TOO_MANY_DESCENDANTS',
  TOO_MANY_ASSIGNMENTS: 'CATEGORY_TOO_MANY_ASSIGNMENTS',
  STALE: 'CATEGORY_TREE_STALE',
  PERMISSION_DENIED: 'CATEGORY_PERMISSION_DENIED',
});

export class CategoryError extends Error {
  constructor(code, message, http = 'failed-precondition') {
    super(message);
    this.categoryCode = code;
    this.http = http;
  }
}
const fail = (code, message, http) => { throw new CategoryError(code, message, http); };
const invalid = message => fail(CATEGORY_CODES.INVALID_ARGUMENT, message, 'invalid-argument');

const DIACRITICS = /[\u0300-\u036f]/g;
/** Comparison key: trimmed, single-spaced, lower-case, without accents ("Anéis" == "aneis"). */
export function normalizeCategoryName(value) {
  return String(value ?? '').normalize('NFD').replace(DIACRITICS, '').trim().replace(/\s+/g, ' ').toLowerCase();
}

/** Display name as stored: trimmed and single-spaced. */
export function cleanCategoryName(value) {
  if (typeof value !== 'string') invalid('Nome da categoria é obrigatório.');
  const name = value.trim().replace(/\s+/g, ' ');
  if (!name) invalid('Nome da categoria é obrigatório.');
  if (name.length > MAX_CATEGORY_NAME_LENGTH) invalid(`Use até ${MAX_CATEGORY_NAME_LENGTH} caracteres.`);
  if (/[\u0000-\u001f\u007f]/.test(name)) invalid('Nome da categoria inválido.');
  return name;
}

export function isValidCategoryId(id) {
  return typeof id === 'string' && id.length > 0 && id.length <= 128 && id === id.trim() &&
    !id.includes('/') && id !== '.' && id !== '..' && !/^__.*__$/.test(id);
}

/** Deterministic per store, so concurrent creates of one name under one parent converge on one doc. */
export function deterministicCategoryId(lojaId, parentId, name, salt = '') {
  const key = `${lojaId}\u0000${parentId ?? ''}\u0000${normalizeCategoryName(name)}${salt ? `\u0000${salt}` : ''}`;
  return `cat_${createHash('sha256').update(key).digest('hex').slice(0, 20)}`;
}

const sortKey = node => [Number.isSafeInteger(node.sortOrder) ? node.sortOrder : Number.MAX_SAFE_INTEGER,
  normalizeCategoryName(node.nome)];
export function compareCategoryNodes(a, b) {
  const [ao, an] = sortKey(a);
  const [bo, bn] = sortKey(b);
  if (ao !== bo) return ao - bo;
  if (an !== bn) return an < bn ? -1 : 1;
  return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
}

const stringList = raw => Array.isArray(raw) ? raw.filter(v => typeof v === 'string' && v.trim()).map(v => v.trim()) : [];

/**
 * Canonical index of a store's category docs. Structure comes from the parentId chain, not from the stored
 * pathIds/depth, so a damaged doc cannot claim a different place. Docs of another store and docs whose chain
 * loops or exceeds MAX_CATEGORY_DEPTH are quarantined (never resolved, never used as parents).
 */
export function buildCategoryIndex(docs, lojaId) {
  const raw = new Map();
  const quarantined = new Map();
  for (const {id, data} of docs) {
    const d = data && typeof data === 'object' ? data : {};
    if (!isValidCategoryId(id)) continue;
    if (d.lojaId !== undefined && d.lojaId !== null && d.lojaId !== lojaId) {
      quarantined.set(id, CATEGORY_CODES.CROSS_TENANT);
      continue;
    }
    const nome = typeof d.nome === 'string' && d.nome.trim() ? d.nome.trim().replace(/\s+/g, ' ') : id;
    const parentId = typeof d.parentId === 'string' && d.parentId.trim() ? d.parentId.trim() : null;
    raw.set(id, {
      id, nome, parentId,
      isDeleted: d.isDeleted === true || (d.deletedAt !== undefined && d.deletedAt !== null),
      sortOrder: Number.isSafeInteger(d.sortOrder) ? d.sortOrder : null,
      legacyNames: stringList(d.legacyNames),
    });
  }
  const nodes = new Map();
  const resolve = (id, trail) => {
    if (nodes.has(id)) return nodes.get(id);
    if (quarantined.has(id)) return null;
    const n = raw.get(id);
    if (!n) return null;
    if (trail.includes(id)) {
      for (const t of trail.slice(trail.indexOf(id))) quarantined.set(t, CATEGORY_CODES.CYCLE);
      return null;
    }
    let pathIds = [id];
    let pathNames = [n.nome];
    if (n.parentId) {
      const parent = resolve(n.parentId, [...trail, id]);
      if (quarantined.has(id)) return null;
      if (!parent) {
        quarantined.set(id, quarantined.get(n.parentId) === CATEGORY_CODES.CROSS_TENANT
          ? CATEGORY_CODES.CROSS_TENANT : CATEGORY_CODES.NOT_FOUND);
        return null;
      }
      pathIds = [...parent.pathIds, id];
      pathNames = [...parent.pathNames, n.nome];
    }
    if (pathIds.length > MAX_CATEGORY_DEPTH) {
      quarantined.set(id, CATEGORY_CODES.DEPTH_LIMIT);
      return null;
    }
    const node = {...n, depth: pathIds.length, pathIds, pathNames};
    nodes.set(id, node);
    return node;
  };
  for (const id of raw.keys()) resolve(id, []);
  const childrenOf = parentId => [...nodes.values()].filter(n => n.parentId === parentId).sort(compareCategoryNodes);
  const activeChildrenOf = parentId => childrenOf(parentId).filter(n => !n.isDeleted);
  const descendantsOf = id => [...nodes.values()].filter(n => n.id !== id && n.pathIds.includes(id));
  return {lojaId, nodes, quarantined, childrenOf, activeChildrenOf, descendantsOf};
}

/** Active node whose name (or a former name) matches, preferring the current name. */
export function findActiveChildByName(index, parentId, name) {
  const key = normalizeCategoryName(name);
  if (!key) return null;
  const siblings = index.activeChildrenOf(parentId);
  return siblings.find(n => normalizeCategoryName(n.nome) === key) ??
    siblings.find(n => n.legacyNames.some(l => normalizeCategoryName(l) === key)) ?? null;
}

/**
 * Ref = {id} for a category doc, or {legacyPath: [categoria, subcategoria?]} for a node that so far only
 * exists as product text. Returns {node} for an existing active node, or {virtual: [nome...], anchor} with the
 * names still to be created (outermost first) under the deepest existing node `anchor` (null = root level).
 */
export function resolveCategoryRef(index, ref, {allowLegacy = true} = {}) {
  if (!ref || typeof ref !== 'object' || Array.isArray(ref)) invalid('Categoria inválida.');
  if (ref.lojaId !== undefined && ref.lojaId !== index.lojaId) {
    fail(CATEGORY_CODES.CROSS_TENANT, 'Categoria de outra loja.', 'permission-denied');
  }
  if ('id' in ref) {
    if (!isValidCategoryId(ref.id)) invalid('Categoria inválida.');
    const q = index.quarantined.get(ref.id);
    if (q === CATEGORY_CODES.CROSS_TENANT) fail(q, 'Categoria de outra loja.', 'permission-denied');
    if (q === CATEGORY_CODES.CYCLE) fail(q, 'Estrutura de categorias inválida (ciclo).');
    const node = index.nodes.get(ref.id);
    if (!node || node.isDeleted) fail(CATEGORY_CODES.NOT_FOUND, 'Categoria não encontrada.', 'not-found');
    return {node};
  }
  if (!allowLegacy || !Array.isArray(ref.legacyPath)) invalid('Categoria inválida.');
  const names = ref.legacyPath.map(cleanCategoryName);
  if (names.length < 1 || names.length > 2) invalid('Categoria inválida.');
  let anchor = null;
  let node = null;
  const virtual = [];
  for (const nome of names) {
    if (!virtual.length) {
      const found = findActiveChildByName(index, anchor, nome);
      if (found) {
        anchor = found.id;
        node = found;
        continue;
      }
    }
    virtual.push(nome);
  }
  return virtual.length ? {virtual, anchor} : {node};
}

/** Node visible as the parent of a new/moved child; enforces the depth cap before any write. */
export function assertCanHaveChild(parentDepth) {
  if (parentDepth >= MAX_CATEGORY_DEPTH) fail(CATEGORY_CODES.DEPTH_LIMIT, CATEGORY_DEPTH_LIMIT_MESSAGE);
}

/** Reparent validation (self, descendant, depth). The move itself is disabled in this version. */
export function validateCategoryMove(index, nodeId, newParentId) {
  const node = index.nodes.get(nodeId);
  if (!node || node.isDeleted) fail(CATEGORY_CODES.NOT_FOUND, 'Categoria não encontrada.', 'not-found');
  if (newParentId !== null) {
    if (newParentId === nodeId) fail(CATEGORY_CODES.CYCLE, 'Uma categoria não pode ser pai dela mesma.');
    const parent = index.nodes.get(newParentId);
    if (!parent || parent.isDeleted) fail(CATEGORY_CODES.NOT_FOUND, 'Categoria não encontrada.', 'not-found');
    if (parent.pathIds.includes(nodeId)) {
      fail(CATEGORY_CODES.CYCLE, 'Uma categoria não pode ser movida para dentro de uma subcategoria dela.');
    }
  }
  const parentDepth = newParentId === null ? 0 : index.nodes.get(newParentId).depth;
  const subtreeHeight = Math.max(1, ...index.descendantsOf(nodeId).map(d => d.depth - node.depth + 1));
  if (parentDepth + subtreeHeight > MAX_CATEGORY_DEPTH) {
    fail(CATEGORY_CODES.DEPTH_LIMIT, CATEGORY_DEPTH_LIMIT_MESSAGE);
  }
  return true;
}

/** Legacy names a product is filed under (categoria + extras, subcategoria + extras). */
export function legacyProductNames(product) {
  const p = product && typeof product === 'object' ? product : {};
  const uniq = values => {
    const seen = new Set();
    return values.filter(v => {
      const k = normalizeCategoryName(v);
      if (!k || seen.has(k)) return false;
      seen.add(k);
      return true;
    });
  };
  const one = v => typeof v === 'string' && v.trim() ? [v.trim()] : [];
  return {
    categorias: uniq([...one(p.categoria), ...stringList(p.categoriasExtras), ...stringList(p.categoriasAssociadas)]),
    subcategorias: uniq([...one(p.subcategoria), ...stringList(p.subcategoriasExtras), ...stringList(p.subcategoriasAssociadas)]),
  };
}

const assignmentLeafId = a => {
  if (!a || typeof a !== 'object' || Array.isArray(a)) return '';
  if (typeof a.categoryId === 'string' && a.categoryId.trim()) return a.categoryId.trim();
  return stringList(a.pathIds).at(-1) ?? '';
};

/**
 * Leaf ids a stored product is filed under: categoryAssignments when non-empty, else the legacy
 * categoryPathIds leaf (products saved before multi-category, read without any migration write).
 */
export function productAssignmentLeafIds(product) {
  const leaves = [];
  for (const a of Array.isArray(product?.categoryAssignments) ? product.categoryAssignments : []) {
    const id = assignmentLeafId(a);
    if (id && !leaves.includes(id)) leaves.push(id);
  }
  if (leaves.length) return leaves;
  const pathIds = stringList(product?.categoryPathIds);
  return pathIds.length ? [pathIds[pathIds.length - 1]] : [];
}

/** Category node ids a product belongs to (all its paths, with ancestors), resolved against the index. */
export function productCategoryIds(index, product) {
  const ids = new Set();
  for (const leafId of productAssignmentLeafIds(product)) {
    const leaf = index.nodes.get(leafId);
    if (leaf && !leaf.isDeleted) leaf.pathIds.forEach(id => ids.add(id));
  }
  const {categorias, subcategorias} = legacyProductNames(product);
  for (const c of categorias) {
    const root = findActiveChildByName(index, null, c);
    if (!root) continue;
    ids.add(root.id);
    for (const s of subcategorias) {
      const child = findActiveChildByName(index, root.id, s);
      if (child) ids.add(child.id);
    }
  }
  return ids;
}

/** Shape check for the product editorial fields; tenant scoping comes from the store-relative doc path. */
export function validateProductCategoryFields(patch, onError) {
  const err = message => onError(message);
  if ('categoryId' in patch) {
    const v = patch.categoryId;
    if (typeof v !== 'string' || (v !== '' && !isValidCategoryId(v))) err('Invalid categoryId');
  }
  for (const key of ['categoryPathIds', 'categoryPathNames']) {
    if (!(key in patch)) continue;
    const v = patch[key];
    if (!Array.isArray(v) || v.length > MAX_CATEGORY_DEPTH || v.some(s => typeof s !== 'string')) err(`Invalid ${key}`);
  }
  if ('categoryPathIds' in patch) {
    const ids = patch.categoryPathIds;
    if (ids.some(id => !isValidCategoryId(id)) || new Set(ids).size !== ids.length) err('Invalid categoryPathIds');
    if ('categoryId' in patch) {
      const leaf = ids.length ? ids[ids.length - 1] : '';
      if (leaf !== patch.categoryId) err('categoryId must be the last categoryPathIds entry');
    }
    if ('categoryPathNames' in patch && patch.categoryPathNames.length !== ids.length) {
      err('categoryPathNames must match categoryPathIds');
    }
  }
  if ('categoryPathNames' in patch) {
    if (patch.categoryPathNames.some(n => !n.trim() || n.length > MAX_CATEGORY_NAME_LENGTH)) err('Invalid categoryPathNames');
  }
  if ('categoryAssignments' in patch) {
    const list = patch.categoryAssignments;
    if (!Array.isArray(list)) err('Invalid categoryAssignments');
    // Refused, never truncated: the merchant must remove paths explicitly.
    if (list.length > MAX_CATEGORY_ASSIGNMENTS) err(CATEGORY_ASSIGNMENTS_LIMIT_MESSAGE);
    for (const a of list) {
      if (!a || typeof a !== 'object' || Array.isArray(a)) err('Invalid categoryAssignments');
      if (!isValidCategoryId(assignmentLeafId(a))) err('Invalid categoryAssignments');
      for (const key of ['pathIds', 'pathNames']) {
        if (key in a && (!Array.isArray(a[key]) || a[key].length > MAX_CATEGORY_DEPTH ||
          a[key].some(s => typeof s !== 'string' || s.length > 128))) err('Invalid categoryAssignments');
      }
      if ('lojaId' in a && typeof a.lojaId !== 'string') err('Invalid categoryAssignments');
    }
  }
}

/**
 * Canonical category fields for a product patch, derived from the store's current tree. Client paths/names
 * are never trusted: only the leaf ids count. Returns null when the patch carries no category key.
 *
 * - `categoryAssignments` (new clients): every leaf must be an active node of this store.
 * - legacy triple only (APKs before multi-category): its leaf is the primary path; the other stored paths are
 *   kept, so an old client editing an unrelated field never drops paths it cannot see.
 * - A stored leaf that is no longer resolvable is kept as stored instead of failing an unrelated edit.
 * Duplicate leaves collapse; a leaf that is an ancestor of another selected leaf is dropped (the product
 * already appears there through the more specific path). The triple mirrors the first path.
 */
export function canonicalProductCategoryPatch(index, patch, existing = {}) {
  if (!PRODUCT_CATEGORY_KEYS.some(k => k in patch)) return null;
  const storedLeaves = productAssignmentLeafIds(existing);
  let requested;
  if ('categoryAssignments' in patch) {
    for (const a of patch.categoryAssignments) {
      if (typeof a.lojaId === 'string' && a.lojaId !== index.lojaId) {
        fail(CATEGORY_CODES.CROSS_TENANT, 'Categoria de outra loja.', 'permission-denied');
      }
    }
    requested = patch.categoryAssignments.map(assignmentLeafId);
  } else {
    const legacyLeaf = 'categoryPathIds' in patch
      ? (stringList(patch.categoryPathIds).at(-1) ?? '')
      : String(patch.categoryId ?? '').trim();
    if (!legacyLeaf) requested = storedLeaves.slice(1);
    else if (storedLeaves.includes(legacyLeaf)) requested = storedLeaves;
    else requested = [legacyLeaf, ...storedLeaves.slice(1)];
  }
  const stored = storedAssignments(existing);
  const resolved = [];
  for (const id of requested) {
    const q = index.quarantined.get(id);
    const node = index.nodes.get(id);
    if (node && !node.isDeleted) {
      resolved.push({categoryId: id, pathIds: [...node.pathIds], pathNames: [...node.pathNames]});
      continue;
    }
    const keep = stored.get(id);
    if (keep && q !== CATEGORY_CODES.CROSS_TENANT) {
      resolved.push(keep);
      continue;
    }
    if (q === CATEGORY_CODES.CROSS_TENANT) fail(q, 'Categoria de outra loja.', 'permission-denied');
    if (q === CATEGORY_CODES.DEPTH_LIMIT) fail(q, CATEGORY_DEPTH_LIMIT_MESSAGE);
    if (q === CATEGORY_CODES.CYCLE) fail(q, 'Estrutura de categorias inválida (ciclo).');
    fail(CATEGORY_CODES.NOT_FOUND, 'Categoria não encontrada.', 'not-found');
  }
  const assignments = normalizeCategoryAssignments(resolved);
  if (assignments.length > MAX_CATEGORY_ASSIGNMENTS) {
    fail(CATEGORY_CODES.TOO_MANY_ASSIGNMENTS, CATEGORY_ASSIGNMENTS_LIMIT_MESSAGE, 'invalid-argument');
  }
  const primary = assignments[0];
  return {
    categoryAssignments: assignments,
    categoryMembershipIds: [...new Set(assignments.flatMap(a => a.pathIds))],
    categoryId: primary?.categoryId ?? '',
    categoryPathIds: primary ? [...primary.pathIds] : [],
    categoryPathNames: primary ? [...primary.pathNames] : [],
  };
}

/** Dedupe by leaf (first wins) and drop any leaf that is an ancestor of another selected leaf; order kept. */
export function normalizeCategoryAssignments(assignments) {
  const seen = new Set();
  const unique = assignments.filter(a => a.categoryId && !seen.has(a.categoryId) && seen.add(a.categoryId));
  return unique.filter(a => !unique.some(b => b.categoryId !== a.categoryId && b.pathIds.includes(a.categoryId)));
}

function storedAssignments(existing) {
  const out = new Map();
  for (const a of Array.isArray(existing?.categoryAssignments) ? existing.categoryAssignments : []) {
    const id = assignmentLeafId(a);
    const pathIds = stringList(a?.pathIds);
    if (id && pathIds.at(-1) === id) out.set(id, {categoryId: id, pathIds, pathNames: stringList(a?.pathNames)});
  }
  const legacyIds = stringList(existing?.categoryPathIds);
  const legacyLeaf = legacyIds.at(-1);
  if (legacyLeaf && !out.has(legacyLeaf)) {
    out.set(legacyLeaf, {categoryId: legacyLeaf, pathIds: legacyIds, pathNames: stringList(existing?.categoryPathNames)});
  }
  return out;
}
