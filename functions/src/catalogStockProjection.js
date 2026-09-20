/** Server stock projection. No Firestore access and no client availability authority. */
export const PROJECTION_VERSION = 1;
export const META_COST = '__custoUnitario';
export const NO_EXTRA = '_sem_extra';
export const isMap = v => v !== null && typeof v === 'object' && !Array.isArray(v);
export const normKey = v => String(v).trim().toLowerCase().replace(/\s+/gu, ' ');
export function stockError(code, message) {
  const error = new Error(message); error.code = code; return error;
}
export function quantity(value) {
  if (!Number.isSafeInteger(value) || value < 0) throw stockError('failed-precondition', 'Invalid canonical stock quantity');
  return value;
}
export function cellTotal(value) {
  if (!isMap(value)) return quantity(value);
  return Object.entries(value).filter(([key]) => key.trim() !== META_COST).reduce((sum, [, q]) => quantity(sum + quantity(q)), 0);
}
// Preserve first display spelling. Duplicate semantic keys are not independent stock.
export function canonicalMap(raw = {}) {
  if (!isMap(raw)) throw stockError('failed-precondition', 'Invalid stock map');
  const out = Object.create(null), displays = new Map();
  for (const [display, value] of Object.entries(raw)) {
    const key = normKey(display);
    const previous = displays.get(key);
    cellTotal(value);
    const canonicalValue = isMap(value) ? normalizeExtraCell(value) : value;
    if (previous === undefined) { displays.set(key, display); out[display] = canonicalValue; }
    else out[previous] = conservativeAliasCell(out[previous], canonicalValue);
  }
  return out;
}
function conservativeAliasCell(a, b) {
  if (!isMap(a) && !isMap(b)) return Math.min(a, b);
  if (isMap(a) !== isMap(b)) throw stockError('failed-precondition', 'Conflicting variation alias schemas');
  const out = Object.create(null), keys = new Map();
  for (const display of [...Object.keys(a), ...Object.keys(b)]) if (display !== META_COST && !keys.has(normKey(display))) keys.set(normKey(display), display);
  if (META_COST in a || META_COST in b) out[META_COST] = a[META_COST] ?? b[META_COST];
  for (const display of keys.values()) {
    const ak = resolveKey(a, display), bk = resolveKey(b, display);
    // Missing extra in one alias is not positive evidence of availability.
    out[display] = Math.min(ak === undefined ? 0 : quantity(a[ak]), bk === undefined ? 0 : quantity(b[bk]));
  }
  return out;
}
export function normalizeExtraCell(raw) {
  const out = Object.create(null), displays = new Map();
  for (const [rawKey, value] of Object.entries(raw)) {
    if (rawKey.trim() === META_COST) {
      if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) throw stockError('failed-precondition', 'Invalid variation cost');
      out[META_COST] = value; continue;
    }
    const display = !rawKey.trim() || rawKey.trim() === '__sem_extra__' ? NO_EXTRA : rawKey;
    quantity(value);
    const normalized = normKey(display), previous = displays.get(normalized);
    if (previous === undefined) {displays.set(normalized, display); out[display] = value;}
    else out[previous] = Math.min(out[previous], value);
  }
  return out;
}
export function resolveExtraKey(map, input) {
  if (String(input).trim() === META_COST) return undefined;
  const key = !String(input).trim() || String(input).trim() === '__sem_extra__' ? NO_EXTRA : input;
  return resolveKey(map, key);
}
function withoutPrivateVariationCost(value) {
  if (!isMap(value)) return value;
  return Object.fromEntries(Object.entries(value).filter(([key]) => key !== META_COST)
    .map(([key, cell]) => [key, withoutPrivateVariationCost(cell)]));
}
export function resolveKey(map, input) {
  return Object.keys(map).find(k => normKey(k) === normKey(input));
}
const nonempty = v => isMap(v) && Object.keys(v).length > 0;
export function hasVariationAttributes(p) {
  return ['tamanhos', 'cores'].some(k => Array.isArray(p[k]) && p[k].some(v => String(v).trim())) ||
    ['estoquePorTamanho', 'estoquePorCor', 'variacoesExtraTipo'].some(k => nonempty(p[k]));
}
export function inferStockKind(p) {
  if (p.tipoProduto === 'combo' || (Array.isArray(p.itensCombo) && p.itensCombo.length)) return 'combo';
  return nonempty(p.variacoes) || hasVariationAttributes(p) ? 'variation' : 'simple';
}
export function normalizeStock(p) {
  if (!['simple', 'variation', 'combo'].includes(p.stockKind)) throw stockError('failed-precondition', 'Stock migration required');
  const out = {...p};
  if (p.stockKind === 'simple' && (nonempty(p.variacoes) || hasVariationAttributes(p))) {
    throw stockError('failed-precondition', 'Simple product has variation data');
  }
  const hasGrade = isMap(p.variacoes) && (nonempty(p.variacoes) || hasVariationAttributes(p));
  if (isMap(p.variacoes)) {
    out.variacoes = Object.create(null);
    for (const [size, colors] of Object.entries(p.variacoes)) out.variacoes[size] = canonicalMap(colors);
  }
  out.estoquePorCor = canonicalMap(p.estoquePorCor ?? {});
  out.estoquePorTamanho = canonicalMap(p.estoquePorTamanho ?? {});
  let total = 0;
  if (hasGrade) {
    const colors = new Set();
    for (const cells of Object.values(out.variacoes)) {
      for (const [color, value] of Object.entries(cells)) { colors.add(normKey(color)); total = quantity(total + cellTotal(value)); }
    }
    if (nonempty(out.variacoes)) for (const [color, value] of Object.entries(out.estoquePorCor)) {
      if (!colors.has(normKey(color))) total = quantity(total + quantity(value));
    }
    // Rebuild size aggregates: they never resurrect an exhausted grade.
    out.estoquePorTamanho = Object.fromEntries(Object.entries(out.variacoes).map(([s, cells]) =>
      [s, Object.values(cells).reduce((sum, value) => quantity(sum + cellTotal(value)), 0)]));
  } else if (nonempty(out.estoquePorTamanho)) {
    total = Object.values(out.estoquePorTamanho).reduce((sum, value) => quantity(sum + quantity(value)), 0);
  } else if (nonempty(out.estoquePorCor)) {
    total = Object.values(out.estoquePorCor).reduce((sum, value) => quantity(sum + quantity(value)), 0);
  } else if (p.stockKind === 'variation') {
    // Missing variable grade cannot use an old total.
    total = 0;
  } else total = quantity(p.quantidade);
  out.quantidade = total;
  return out;
}
export const EDITORIAL_FIELDS = Object.freeze([
  'nome','descricao','descricao_curta','preco','preco_venda','precoFinal','precoPorTamanho',
  'imagens','imagem_principal','imagemUrl','imageUrl','fotoThumbUrl','fotoOriginalUrl','slug',
  'categoria','categoriaId','subcategoria','subcategoriaId','categoriasExtras','subcategoriasExtras',
  'categoriasAssociadas','subcategoriasAssociadas','peso','emPromocao','percentualPromo','valorPromo',
  'publicadoNoCatalogo','exibir_no_catalogo','ocultar_catalogo','catalog_ativo',
  'priceMin','priceMax','images','imgs','fotos','dataInicioPromo','dataFimPromo',
  'precoComPromocao','promocaoAtiva','descontoComboValor','descontoComboPercentual',
]);
export function validateEditorial(patch) {
  if (!isMap(patch) || Object.keys(patch).some(k => !EDITORIAL_FIELDS.includes(k))) {
    throw stockError('invalid-argument', 'Protected or unknown editorial field');
  }
  for (const key of ['publicadoNoCatalogo','exibir_no_catalogo','ocultar_catalogo','catalog_ativo']) {
    if (key in patch && typeof patch[key] !== 'boolean') throw stockError('invalid-argument', 'Invalid publication flag');
  }
  return structuredClone(patch);
}
export function projectCatalog(canonical, editorial, productId) {
  const stock = normalizeStock(canonical);
  quantity(stock.stockRevision);
  const meta = Object.fromEntries(EDITORIAL_FIELDS.filter(k => k in editorial).map(k => [k, editorial[k]]));
  const stockFields = ['quantidade','variacoes','estoquePorTamanho','estoquePorCor','tamanhos','cores',
    'variacoesExtraTipo','tipoProduto','stockKind','itensCombo','comboConfig'];
  const fields = Object.fromEntries(stockFields.filter(k => k in stock).map(k => [k,
    k === 'variacoes' ? withoutPrivateVariationCost(stock[k]) : stock[k]]));
  const available = stock.quantidade > 0 && editorial.publicadoNoCatalogo === true &&
    editorial.exibir_no_catalogo !== false && editorial.ocultar_catalogo !== true &&
    editorial.catalog_ativo !== false && !stock.pendingSoftDelete;
  const projected = {...meta, ...fields, id: productId,
    ativo: editorial.catalog_ativo !== false, publicar: editorial.publicadoNoCatalogo === true,
    vendasCatalogoTotal: quantity(stock.vendasCatalogoTotal ?? 0),
    estoque: stock.quantidade,
    estoque_atual: stock.quantidade, qtdEstoque: stock.quantidade,
    catalogStockRevision: stock.stockRevision, catalogProjectionVersion: PROJECTION_VERSION};
  return {stock, draft: projected, live: available ? {...projected, ativo: true, publicar: true, publicado: true} : null};
}
