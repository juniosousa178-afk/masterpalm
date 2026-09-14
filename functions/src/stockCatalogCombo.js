import {documentId} from './stockCatalogAccess.js';
import {isMap, quantity, stockError, normKey, resolveKey, resolveExtraKey} from './catalogStockProjection.js';
const positive = n => {quantity(n); if (!n) throw stockError('failed-precondition', 'Invalid recipe quantity'); return n;};
export function configurable(stock) {return Array.isArray(stock.comboConfig?.grupos) && stock.comboConfig.grupos.length > 0;}
export function recipe(stock) {
  if (stock.stockKind !== 'combo') return [];
  if (configurable(stock)) return stock.comboConfig.grupos.flatMap(g => g.opcoes ?? []).map(o => ({productId: documentId(o.productId), quantity: 1}));
  if (!Array.isArray(stock.itensCombo)) return [];
  return stock.itensCombo.map(i => ({productId: documentId(i.productId ?? i.id), quantity: positive(i.quantidade ?? 1),
    size: i.tamanho ?? '', color: i.cor ?? '', extra: i.variacaoExtra ?? i.extraValor ?? ''}));
}
export function componentIntents(stock, item) {
  if (stock.stockKind !== 'combo') {
    if (item.selection?.length) throw stockError('invalid-argument', 'Selection requires combo');
    return [];
  }
  if (!configurable(stock)) {
    if (item.selection?.length) throw stockError('invalid-argument', 'Fixed recipe cannot be replaced by client');
    return recipe(stock).map(r => ({...r, quantity: positive(r.quantity * item.quantity)}));
  }
  const selected = item.selection ?? [];
  if (!Array.isArray(selected)) throw stockError('invalid-argument', 'Combo selection required');
  const groups = stock.comboConfig.grupos;
  if (selected.some(s => !groups.some(g => g.id === s.groupId))) throw stockError('invalid-argument', 'Unknown combo group');
  const result = [];
  for (const group of groups) {
    const choices = selected.filter(s => s.groupId === group.id);
    const min = group.selecaoMin ?? (group.obrigatorio ? 1 : 0), max = group.selecaoMax ?? 1;
    quantity(min); quantity(max);
    if (choices.length < min || choices.length > max) throw stockError('invalid-argument', 'Combo group selection bounds');
    const seen = new Set();
    for (const choice of choices) {
      if (!isMap(choice) || Object.keys(choice).some(k => !['groupId','productId','quantity','size','color','extra'].includes(k))) throw stockError('invalid-argument', 'Invalid selection');
      const option = (group.opcoes ?? []).find(o => o.productId === choice.productId);
      if (!option) throw stockError('invalid-argument', 'Selected product not in canonical recipe');
      const n = positive(choice.quantity);
      const lower = option.qtdMin ?? group.qtdMinPorOpcao ?? 1;
      const upper = option.qtdMax || group.qtdMaxPorOpcao || 9999;
      if (n < lower || n > upper || ((option.permiteRepetir === false || group.permiteRepetirOpcao === false) && (n > 1 || seen.has(choice.productId)))) throw stockError('invalid-argument', 'Combo option quantity bounds');
      seen.add(choice.productId);
      result.push({productId: choice.productId, quantity: positive(n * item.quantity), size: choice.size ?? '', color: choice.color ?? '', extra: choice.extra ?? ''});
    }
  }
  return result;
}
export function comboOrder(records) {
  const visiting = new Set(), done = new Set(), order = [];
  function visit(id) {
    if (visiting.has(id)) throw stockError('failed-precondition', 'Cyclic combo recipe');
    if (done.has(id)) return;
    visiting.add(id);
    const stock = records.get(id)?.data;
    if (!stock) throw stockError('failed-precondition', 'Missing recipe component');
    for (const item of recipe(stock)) visit(item.productId);
    visiting.delete(id); done.add(id); order.push(id);
  }
  for (const id of records.keys()) visit(id);
  return order;
}
export function recalculateFixedCombos(records, direction) {
  for (const id of comboOrder(records)) {
    const p = records.get(id).data;
    if (p.stockKind !== 'combo' || configurable(p) || Object.keys(p.variacoes ?? {}).length || Object.keys(p.estoquePorTamanho ?? {}).length) continue;
    const items = recipe(p);
    if (!items.length) continue;
    // Repeated recipe lines consume the same cell together, not independent units.
    const cells = new Map();
    for (const item of items) {
      const key = JSON.stringify([item.productId, normKey(item.size), normKey(item.color), normKey(item.extra)]);
      const prior = cells.get(key);
      cells.set(key, {...item, quantity: quantity((prior?.quantity ?? 0) + item.quantity)});
    }
    const cap = Math.min(...[...cells.values()].map(i => Math.floor(componentAvailable(records.get(i.productId).data, i) / i.quantity)));
    p.quantidade = direction < 0 ? Math.min(p.quantidade, cap) : cap;
  }
}

function componentAvailable(p, item) {
  if (p.pendingSoftDelete) return 0;
  if (p.stockKind === 'simple' || (p.stockKind === 'combo' && !Object.keys(p.variacoes ?? {}).length && !Object.keys(p.estoquePorTamanho ?? {}).length && !Object.keys(p.estoquePorCor ?? {}).length)) {
    return item.size || item.color || item.extra ? 0 : p.quantidade;
  }
  let value;
  if (Object.keys(p.variacoes ?? {}).length) {
    const size = resolveKey(p.variacoes, item.size) ?? (!item.size ? resolveKey(p.variacoes, 'sem-tamanho') : undefined);
    if (size !== undefined) value = p.variacoes[size][resolveKey(p.variacoes[size], item.color) ?? (!item.color ? resolveKey(p.variacoes[size], 'sem-cor') : undefined)];
    if (value === undefined && !item.size && !Object.values(p.variacoes).some(c => resolveKey(c, item.color) !== undefined)) value = p.estoquePorCor[resolveKey(p.estoquePorCor, item.color)];
  } else if (item.size && !item.color) value = p.estoquePorTamanho[resolveKey(p.estoquePorTamanho, item.size)];
  else if (!item.size) value = p.estoquePorCor[resolveKey(p.estoquePorCor, item.color)];
  if (isMap(value)) value = value[resolveExtraKey(value, item.extra)];
  else if (item.extra) value = undefined;
  return value === undefined ? 0 : quantity(value);
}
