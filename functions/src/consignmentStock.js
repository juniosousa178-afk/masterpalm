/** Isolated consignment stock mutations. Canonical variacoes only. No PDV sale path. */
import {createHash} from 'node:crypto';
import {FieldValue} from 'firebase-admin/firestore';
import {recipe, comboOrder, recalculateFixedCombos} from './stockCatalogCombo.js';
import {documentId} from './stockCatalogAccess.js';
import {
  isMap, stockError, normalizeStock, projectCatalog, quantity, resolveKey, resolveExtraKey,
  META_COST,
} from './catalogStockProjection.js';
import {consignmentError, CODES} from './consignmentProtocol.js';

const MAX_PRODUCTS = 25;
const nonempty = v => isMap(v) && Object.keys(v).length > 0;
const ordered = value => Array.isArray(value) ? value.map(ordered) : isMap(value)
  ? Object.fromEntries(Object.keys(value).sort().map(k => [k, ordered(value[k])])) : value;
export const fingerprint = value => createHash('sha256').update(JSON.stringify(ordered(value))).digest('hex');
const stockEffect = p => Object.fromEntries(['quantidade','variacoes','estoquePorTamanho','estoquePorCor',
  'tamanhos','cores','variacoesExtraTipo','tipoProduto','stockKind','itensCombo','comboConfig','pendingSoftDelete']
  .filter(key => key in p).map(key => [key, p[key]]));

function technicalKey(value) {
  const n = String(value ?? '').trim().toLowerCase().replace(/\s+/gu, '');
  return !n || n === 'sem-tamanho' || n === 'semtamanho' || n === 'sem-cor' || n === 'semcor'
    || n === 'unico' || n === 'unique' || n === 'u';
}

/** Grade = size×color matrix or extra dimension. Normal variation is single-axis canonical variacoes. */
export function classifyConsignmentProduct(raw) {
  if (!raw || !['simple', 'variation', 'combo'].includes(raw.stockKind)) {
    throw consignmentError(CODES.PRODUCT_STATE_UNSAFE, 'Stock identity is ambiguous');
  }
  const data = {...raw};
  if (data.pendingSoftDelete) throw consignmentError(CODES.PRODUCT_STATE_UNSAFE, 'Product deleted');
  if (data.stockKind === 'combo' || data.tipoProduto === 'combo' || (Array.isArray(data.itensCombo) && data.itensCombo.length)) {
    throw consignmentError(CODES.PRODUCT_STATE_UNSAFE, 'Combo products are not supported in consignment MVP');
  }
  if (data.stockKind === 'simple') {
    if (nonempty(data.variacoes) || hasGradeAttrs(data)) {
      throw consignmentError(CODES.PRODUCT_STATE_UNSAFE, 'Simple product has variation data');
    }
    return {kind: 'simple', stock: safeNormalize(data)};
  }
  if (data.stockKind !== 'variation') {
    throw consignmentError(CODES.PRODUCT_STATE_UNSAFE, 'Unsupported stock kind');
  }
  if (nonempty(data.variacoesExtraTipo)) {
    throw consignmentError(CODES.CONSIGNMENT_GRADE_NOT_SUPPORTED, 'Grade extra dimension is not supported');
  }
  const stock = safeNormalize(data);
  if (!nonempty(stock.variacoes)) {
    throw consignmentError(CODES.PRODUCT_STATE_UNSAFE, 'Canonical variacoes required for variation products');
  }
  if (isGradeMatrix(stock) || hasBothSizeAndColorLists(data)) {
    throw consignmentError(CODES.CONSIGNMENT_GRADE_NOT_SUPPORTED, 'Grade products are not supported');
  }
  return {kind: 'variation', stock};
}

function hasGradeAttrs(p) {
  return ['tamanhos', 'cores'].some(k => Array.isArray(p[k]) && p[k].some(v => String(v).trim()))
    || ['estoquePorTamanho', 'estoquePorCor', 'variacoesExtraTipo'].some(k => nonempty(p[k]));
}
function hasBothSizeAndColorLists(p) {
  const sizes = Array.isArray(p.tamanhos) && p.tamanhos.some(v => String(v).trim() && !technicalKey(v));
  const colors = Array.isArray(p.cores) && p.cores.some(v => String(v).trim() && !technicalKey(v));
  return sizes && colors;
}
function isGradeMatrix(stock) {
  const sizes = Object.keys(stock.variacoes || {}).filter(s => !technicalKey(s));
  const colors = new Set();
  for (const cells of Object.values(stock.variacoes || {})) {
    if (!isMap(cells)) continue;
    for (const color of Object.keys(cells)) {
      if (color === META_COST || technicalKey(color)) continue;
      colors.add(String(color).trim().toLowerCase());
    }
  }
  return sizes.length > 0 && colors.size > 0;
}
function wrapUnsafe(error) {
  if (error?.consignmentCode) return error;
  return consignmentError(CODES.PRODUCT_STATE_UNSAFE, error?.message || 'Unsafe product state');
}
function safeNormalize(data) {
  try { return normalizeStock(data); }
  catch (error) { throw wrapUnsafe(error); }
}

export function parseVariationSelector(raw) {
  const src = isMap(raw) ? raw : {};
  const size = typeof src.size === 'string' ? src.size : '';
  const color = typeof src.color === 'string' ? src.color : '';
  const extra = typeof src.extra === 'string' ? src.extra : '';
  return {size, color, extra};
}

export function variationIdentity(selector) {
  const s = parseVariationSelector(selector);
  return `${s.size}\u001e${s.color}\u001e${s.extra}`;
}

/** Exact canonical cell only. No sem-tamanho/sem-cor fallback. Never uses estoquePorTamanho as authority. */
export function applyExactConsignmentDelta(stock, kind, selector, delta) {
  if (!Number.isSafeInteger(delta) || delta === 0) throw consignmentError(CODES.INVALID_ARGUMENT, 'Stock delta must be a non-zero integer');
  if (kind === 'simple') {
    if (selector.size || selector.color || selector.extra) {
      throw consignmentError(CODES.INVALID_ARGUMENT, 'Simple product cannot select a variation');
    }
    const next = safeNormalize(stock);
    const qty = quantity(next.quantidade);
    if (qty + delta < 0) throw consignmentError(CODES.INSUFFICIENT_STOCK, 'Insufficient available stock');
    next.quantidade = quantity(qty + delta);
    return next;
  }
  const next = safeNormalize(stock);
  if (!nonempty(next.variacoes)) throw consignmentError(CODES.VARIATION_NOT_FOUND, 'Canonical variation map missing');
  if (!selector.size || !selector.color) {
    throw consignmentError(CODES.VARIATION_NOT_FOUND, 'Exact variationKey required');
  }
  const sizeKey = resolveKey(next.variacoes, selector.size);
  if (sizeKey === undefined) throw consignmentError(CODES.VARIATION_NOT_FOUND, 'Variation size not found');
  const colorMap = next.variacoes[sizeKey];
  if (!isMap(colorMap)) throw consignmentError(CODES.VARIATION_NOT_FOUND, 'Variation color map not found');
  const colorKey = resolveKey(colorMap, selector.color);
  if (colorKey === undefined) throw consignmentError(CODES.VARIATION_NOT_FOUND, 'Variation color not found');
  let map = colorMap;
  let key = colorKey;
  if (isMap(map[key])) {
    const extraKey = resolveExtraKey(map[key], selector.extra);
    if (extraKey === undefined) throw consignmentError(CODES.VARIATION_NOT_FOUND, 'Extra variation not found');
    map = map[key];
    key = extraKey;
  } else if (selector.extra) {
    throw consignmentError(CODES.VARIATION_NOT_FOUND, 'Unexpected extra dimension');
  }
  const current = quantity(map[key]);
  if (current + delta < 0) throw consignmentError(CODES.INSUFFICIENT_STOCK, 'Insufficient variation stock');
  map[key] = quantity(current + delta);
  return safeNormalize(next);
}

export async function loadConsignmentStockRecords(tx, base, productIds) {
  const ids = [...new Set(productIds.map(id => documentId(id, 'productId')))];
  if (!ids.length) throw consignmentError(CODES.INVALID_ARGUMENT, 'Products required');
  if (ids.length > MAX_PRODUCTS) throw consignmentError(CODES.RESOURCE_EXHAUSTED, 'Too many affected products');
  const records = new Map();
  for (const id of ids) {
    if (records.has(id)) continue;
    if (records.size >= MAX_PRODUCTS) throw consignmentError(CODES.RESOURCE_EXHAUSTED, 'Combo fan-out exceeds transaction budget');
    const stockRef = base.collection('estoque_produtos').doc(id);
    const draftRef = base.collection('draft_produtos').doc(id);
    const [stock, draft, dependency, tombstone] = await tx.getAll(
      stockRef, draftRef, base.collection('stock_catalog_dependencies').doc(id),
      base.collection('exclusao_produto').doc(id),
    );
    if (!stock.exists || !draft.exists) throw consignmentError(CODES.PRODUCT_NOT_FOUND, 'Canonical product and editorial draft required');
    const raw = stock.data() || {};
    const editorial = draft.data() || {};
    const claimedStore = String(raw.lojaId || raw.storeId || editorial.lojaId || editorial.storeId || '').trim();
    if (claimedStore && claimedStore !== base.id) {
      throw consignmentError(CODES.AUTH, 'Cross-store product access denied');
    }
    if (raw.ativo === false || editorial.ativo === false || editorial.ativoNoRascunho === false) {
      throw consignmentError(CODES.PRODUCT_STATE_UNSAFE, 'Product is inactive');
    }
    if (!['simple', 'variation', 'combo'].includes(raw.stockKind)) {
      throw consignmentError(CODES.PRODUCT_STATE_UNSAFE, 'Stock identity is ambiguous');
    }
    if (tombstone.exists && tombstone.data()?.p === true) {
      throw consignmentError(CODES.PRODUCT_STATE_UNSAFE, 'Product tombstone requires reconciliation');
    }
    if (!dependency.exists || !Array.isArray(dependency.data().comboIds)) {
      throw consignmentError(CODES.PRODUCT_STATE_UNSAFE, 'Dependency migration required');
    }
    for (const related of (dependency.data()?.comboIds ?? [])) {
      if (!ids.includes(documentId(related))) ids.push(related);
    }
    let data;
    try {
      data = normalizeStock(stock.data());
      quantity(data.stockRevision);
    } catch (error) { throw wrapUnsafe(error); }
    for (const component of recipe(data)) if (!ids.includes(component.productId)) ids.push(component.productId);
    records.set(id, {
      stockRef, draftRef, dependency,
      data, editorial,
      beforeHash: fingerprint(stockEffect(data)),
      originalRevision: data.stockRevision,
      beforeStock: structuredClone(stockEffect(data)),
    });
  }
  comboOrder(records);
  return records;
}

export function persistConsignmentStock(tx, base, records, operationId, direction) {
  recalculateFixedCombos(records, direction);
  const products = [];
  const writes = [];
  const set = (ref, data, merge = false) => writes.push(() => merge ? tx.set(ref, data, {merge: true}) : tx.set(ref, data));
  const remove = ref => writes.push(() => tx.delete(ref));
  const affected = [];
  for (const [id, r] of records) {
    const changed = fingerprint(stockEffect(r.data)) !== r.beforeHash;
    r.data.stockRevision = quantity(r.originalRevision + (changed ? 1 : 0));
    r.data.stockOperationId = operationId;
    let projected;
    try { projected = projectCatalog(r.data, r.editorial, id); }
    catch (error) { throw wrapUnsafe(error); }
    products.push({productId: id, revision: projected.stock.stockRevision, quantidade: projected.stock.quantidade});
    if (changed) {
      affected.push({
        productId: id,
        before: r.beforeStock,
        after: stockEffect(projected.stock),
        stockRevision: projected.stock.stockRevision,
      });
    }
    set(r.stockRef, {...projected.stock, stockUpdatedAt: FieldValue.serverTimestamp()});
    set(r.draftRef, {...projected.draft, updatedAt: FieldValue.serverTimestamp()});
    const live = base.collection('produtos').doc(id);
    if (projected.live) set(live, {...projected.live, updatedAt: FieldValue.serverTimestamp()});
    else remove(live);
  }
  return {products, writes, affected};
}

export {stockError};
