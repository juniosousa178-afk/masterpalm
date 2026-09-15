import {readFileSync} from 'node:fs';
import test from 'node:test';
import assert from 'node:assert/strict';
import {normalizeStock, projectCatalog, inferStockKind, resolveLegacyCompatStockKind, normKey, validateEditorial} from '../src/catalogStockProjection.js';
const base = {quantidade: 1, stockKind: 'simple', stockRevision: 3};
const published = {nome: 'Peça', publicadoNoCatalogo: true};
test('resolveLegacyCompatStockKind preserves valid, infers absent, rejects invalid', () => {
  assert.deepEqual(resolveLegacyCompatStockKind({quantidade: 2}), {stockKind: 'simple', stockKindSource: 'inferred'});
  assert.deepEqual(resolveLegacyCompatStockKind({stockKind: 'combo', itensCombo: [{productId: 'a'}]}), {
    stockKind: 'combo', stockKindSource: 'explicit',
  });
  assert.throws(() => resolveLegacyCompatStockKind({stockKind: 'nope'}), e => e.message === 'Invalid stockKind');
});
for (const variations of [undefined, null, {}]) {
  test(`simple with ${JSON.stringify(variations)} remains available`, () => {
    const stock = {...base, ...(variations === undefined ? {} : {variacoes: variations})};
    assert.equal(inferStockKind(stock), 'simple');
    const p = projectCatalog(stock, published, 'p');
    assert.equal(p.live.quantidade, 1); assert.equal(p.live.catalogStockRevision, 3);
  });
}
test('zero removes live but preserves editorial draft', () => {
  const p = projectCatalog({...base, quantidade: 0}, published, 'p');
  assert.equal(p.live, null); assert.equal(p.draft.publicadoNoCatalogo, true);
});
test('restock republishes only when publication intent remains true', () => {
  assert.equal(projectCatalog({...base, quantidade: 5}, published, 'p').live.quantidade, 5);
  assert.equal(projectCatalog({...base, quantidade: 5}, {...published, publicadoNoCatalogo: false}, 'p').live, null);
});
test('empty variable grade with attributes ignores stale aggregates', () => {
  const p = {...base, stockKind: 'variation', variacoes: {}, tamanhos: ['P'], estoquePorTamanho: {P: 8}};
  assert.equal(normalizeStock(p).quantidade, 0);
});
test('explicit zero cell never inherits size or root aggregate of same color', () => {
  const p = {...base, stockKind: 'variation', variacoes: {P: {Azul: 0}}, estoquePorTamanho: {P: 8}, estoquePorCor: {azul: 9}};
  assert.equal(normalizeStock(p).quantidade, 0);
});
test('color aliases preserve display and take conservative stock', () => {
  const p = {...base, stockKind: 'variation', variacoes: {P: {Azul: 2, ' azul ': 0, Vermelho: 2}}};
  const n = normalizeStock(p);
  assert.deepEqual(Object.keys(n.variacoes.P), ['Azul', 'Vermelho']);
  assert.equal(n.variacoes.P.Azul, 0); assert.equal(n.quantidade, 2);
  for (const v of ['Azul', 'azul', 'AZUL', ' Azul ']) assert.equal(normKey(v), 'azul');
});
test('dimension extras and root color outside grade counted once', () => {
  const p = {...base, stockKind: 'variation', variacoes: {P: {Azul: {Fosco: 1, Brilho: 2}}}, estoquePorCor: {azul: 10, Verde: 4}};
  assert.equal(normalizeStock(p).quantidade, 7);
});
for (const field of ['estoquePorTamanho', 'estoquePorCor']) test(`${field} only remains valid`, () => {
  assert.equal(normalizeStock({...base, stockKind: 'variation', [field]: {Azul: 2}}).quantidade, 2);
});
test('kind is not inferred from tipoProduto simples alone', () => {
  assert.equal(inferStockKind({...base, tipoProduto: 'simples', variacoes: {P: {Azul: 0}}}), 'variation');
  assert.throws(() => normalizeStock({...base, variacoes: {P: {Azul: 1}}}));
});
test('unmigrated or invalid stock is rejected', () => {
  assert.throws(() => normalizeStock({quantidade: 1}));
  for (const q of [-1, 1.5, '2', NaN, Infinity]) assert.throws(() => normalizeStock({...base, quantidade: q}));
});
test('editorial API rejects protected fields; live excludes private cost', () => {
  for (const field of ['quantidade', 'stockRevision', 'ativo', 'variacoes', 'id', 'custo']) assert.throws(() => validateEditorial({[field]: 1}));
  assert.deepEqual(validateEditorial({descricao: 'Nova'}), {descricao: 'Nova'});
  const p = projectCatalog({...base, custo: 7}, {...published, custo: 9}, 'p');
  assert.equal('custo' in p.live, false); assert.equal(p.live.id, 'p');
});

test('color aliases merge per extra cell, never by equal aggregate totals', () => {
  const p = normalizeStock({stockKind: 'variation', quantidade: 99, variacoes: {P: {Azul: {A: 1, B: 0}, azul: {A: 0, B: 1}}}});
  assert.equal(p.quantidade, 0);
  assert.deepEqual({...p.variacoes.P.Azul}, {A: 0, B: 0});
});

test('private variation cost is preserved canonically, excluded from stock sum and public projections', () => {
  const p = projectCatalog({stockKind: 'variation', stockRevision: 0, quantidade: 99,
    variacoes: {P: {Azul: {_sem_extra: 1, __custoUnitario: 12.75}}}}, {publicadoNoCatalogo: true}, 'p');
  assert.equal(p.stock.quantidade, 1); assert.equal(p.stock.variacoes.P.Azul.__custoUnitario, 12.75);
  assert.equal(p.live.variacoes.P.Azul.__custoUnitario, undefined);
  assert.equal(p.draft.variacoes.P.Azul.__custoUnitario, undefined);
  assert.equal(p.live.variacoes.P.Azul._sem_extra, 1);
});

const sharedFixtures = JSON.parse(readFileSync(new URL('../../test/fixtures/stock_catalog_projection.json', import.meta.url), 'utf8'));
for (const fixture of sharedFixtures) test(`shared Flutter/server projection: ${fixture.name}`, () => {
  const stock = {...fixture.canonical, stockKind: inferStockKind(fixture.canonical), stockRevision: 1};
  const projected = projectCatalog(stock, published, 'p');
  assert.equal(projected.stock.quantidade, fixture.total);
  assert.equal(projected.live !== null, fixture.total > 0);
  for (const [key, value] of Object.entries(fixture.display)) {
    assert.deepEqual(JSON.parse(JSON.stringify(projected.draft[key])), value);
  }
});
