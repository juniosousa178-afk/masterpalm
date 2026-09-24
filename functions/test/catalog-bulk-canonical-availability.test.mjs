import test from 'node:test';
import assert from 'node:assert/strict';
import {
  normalizeStock,
  projectCatalog,
  projectPositiveAvailabilityMaps,
} from '../src/catalogStockProjection.js';
import {classifyCatalogPublishPreflight} from '../src/stockCatalogCommands.js';

test('INFINITO_BRILHO_PROJECTION: only 14 positive after project', () => {
  const canonical = {
    stockKind: 'variation',
    stockRevision: 2,
    quantidade: 1,
    variacoes: {'14': {prata: 1}},
    estoquePorTamanho: {'14': 1},
    tamanhos: ['14', '16', '18'],
  };
  const editorial = {
    nome: 'Anel Infinito Brilho',
    publicadoNoCatalogo: true,
    tamanhos: ['14', '16', '18'],
  };
  const p = projectCatalog(canonical, editorial, 'nathy-infinito');
  assert.equal(p.live.quantidade, 1);
  assert.deepEqual(Object.keys(p.live.variacoes), ['14']);
  assert.equal(p.live.variacoes['14'].prata, 1);
  assert.equal(p.live.estoquePorTamanho['14'], 1);
  assert.equal(p.live.estoquePorTamanho['16'], undefined);
  assert.equal(p.live.estoquePorTamanho['18'], undefined);
  assert.deepEqual(p.live.tamanhos, ['14', '16', '18']);
});

test('STALE_LIVE_CELL_REMOVED / CONTROLLED_POSITIVE_CELLS_ONLY', () => {
  const stock = normalizeStock({
    stockKind: 'variation',
    stockRevision: 1,
    quantidade: 99,
    variacoes: {'14': {prata: 1}, '16': {prata: 0}},
    tamanhos: ['14', '16', '18'],
  });
  const avail = projectPositiveAvailabilityMaps(stock);
  assert.deepEqual(Object.keys(avail.variacoes), ['14']);
  assert.equal(avail.estoquePorTamanho['14'], 1);
  assert.equal(avail.estoquePorTamanho['16'], undefined);
});

test('TAMANHOS_METADATA_NOT_STOCK / ZERO_STOCK_NO_INFERENCE', () => {
  const p = projectCatalog({
    stockKind: 'variation',
    stockRevision: 1,
    quantidade: 0,
    variacoes: {},
    tamanhos: ['15', '18'],
    estoquePorTamanho: {},
  }, {publicadoNoCatalogo: true}, 'verde');
  assert.equal(p.live, null);
  assert.equal(p.draft.quantidade, 0);
  assert.equal(Object.keys(p.draft.variacoes || {}).length, 0);
});

test('BULK_PREFLIGHT_NO_WRITE classify blockers', () => {
  const blocked = classifyCatalogPublishPreflight(
    {quantidade: 2, tamanhos: ['45cm']},
    {productId: 'legacy-1', name: 'Legacy'},
  );
  assert.equal(blocked.status, 'BLOCKED_STOCK_MIGRATION');
  assert.match(blocked.reason, /Stock migration required/i);

  const ok = classifyCatalogPublishPreflight({
    stockKind: 'simple',
    stockRevision: 1,
    quantidade: 3,
  }, {productId: 'ok-1', name: 'OK'});
  assert.equal(ok.status, 'PUBLISHABLE');
});

test('ONE_BLOCKER_DOES_NOT_ABORT — publishable class independent of blocked peer', () => {
  const a = classifyCatalogPublishPreflight(
    {quantidade: 0, tamanhos: ['único']},
    {productId: 'blocked', name: 'Blocked'},
  );
  const b = classifyCatalogPublishPreflight({
    stockKind: 'variation',
    stockRevision: 2,
    quantidade: 1,
    variacoes: {'14': {prata: 1}},
    tamanhos: ['14', '16', '18'],
  }, {productId: 'infinito', name: 'Infinito'});
  assert.equal(a.status, 'BLOCKED_STOCK_MIGRATION');
  assert.equal(b.status, 'PUBLISHABLE');
});

test('NO_CONTROL_REGRESSION simple projects', () => {
  const p = projectCatalog({
    stockKind: 'simple',
    stockRevision: 0,
    quantidade: 5,
  }, {publicadoNoCatalogo: true, nome: 'Simples'}, 's1');
  assert.equal(p.live.quantidade, 5);
  assert.equal(p.live.stockKind, 'simple');
});

test('COMBO_REGRESSION smoke', () => {
  const p = projectCatalog({
    stockKind: 'combo',
    stockRevision: 1,
    quantidade: 2,
    tipoProduto: 'combo',
    itensCombo: [{productId: 'x', quantidade: 1}],
  }, {publicadoNoCatalogo: true}, 'combo-1');
  assert.equal(p.live.quantidade, 2);
  assert.equal(p.live.stockKind, 'combo');
});

test('TENANT productId stamped on projection', () => {
  const p = projectCatalog({
    stockKind: 'simple',
    stockRevision: 1,
    quantidade: 1,
  }, {publicadoNoCatalogo: true}, 'loja-a-product-1');
  assert.equal(p.live.id, 'loja-a-product-1');
});

test('BLOCKER_IDS_RETURNED / TENANT_ISOLATION shape', () => {
  const a = classifyCatalogPublishPreflight(
    {quantidade: 1, tamanhos: ['14']},
    {productId: 'tenant-a-legacy', name: 'Legacy A'},
  );
  const b = classifyCatalogPublishPreflight(
    {quantidade: 0, tipoProduto: 'combo', stockKind: 'combo', itensCombo: [{}]},
    {productId: 'tenant-b-combo', name: 'Combo B'},
  );
  assert.equal(a.productId, 'tenant-a-legacy');
  assert.equal(b.productId, 'tenant-b-combo');
  assert.notEqual(a.productId, b.productId);
  assert.ok(a.status.startsWith('BLOCKED_'));
  assert.ok(['BLOCKED_COMBO', 'BLOCKED_OTHER', 'BLOCKED_STOCK_MIGRATION'].includes(b.status));
});

test('STOCK_IMMUTABILITY projectCatalog does not mutate canonical input', () => {
  const canonical = {
    stockKind: 'variation',
    stockRevision: 1,
    quantidade: 1,
    variacoes: {'14': {prata: 1}, '16': {prata: 0}},
    tamanhos: ['14', '16', '18'],
  };
  const before = JSON.stringify(canonical);
  projectCatalog(canonical, {publicadoNoCatalogo: true}, 'imut');
  assert.equal(JSON.stringify(canonical), before);
});

test('INFINITO_BRILHO_PUBLIC_SELECTOR positive cells only', () => {
  const p = projectCatalog({
    stockKind: 'variation',
    stockRevision: 2,
    quantidade: 1,
    variacoes: {'14': {prata: 1}},
    estoquePorTamanho: {'14': 1, '16': 1, '18': 1},
    tamanhos: ['14', '16', '18'],
  }, {
    publicadoNoCatalogo: true,
    tamanhos: ['14', '16', '18'],
  }, 'infinito');
  const ept = p.live.estoquePorTamanho || {};
  const sellable = Object.entries(ept).filter(([, q]) => Number(q) > 0).map(([k]) => k);
  assert.deepEqual(sellable, ['14']);
  assert.equal(ept['16'], undefined);
  assert.equal(ept['18'], undefined);
  // Metadata tamanhos remain editorial on live but do not create stock cells.
  assert.deepEqual(p.live.tamanhos, ['14', '16', '18']);
});
