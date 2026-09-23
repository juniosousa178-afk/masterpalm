/**
 * Commercial fields projection (Pix / sem juros) — presence-based false/0 preserve.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  projectCatalog,
  validateEditorial,
  mergeCommercialEditorialFields,
  EDITORIAL_FIELDS,
  COMMERCIAL_EDITORIAL_FIELDS,
} from '../src/catalogStockProjection.js';

const baseStock = {quantidade: 2, stockKind: 'simple', stockRevision: 1};
const published = {nome: 'Peça', publicadoNoCatalogo: true};

test('allowlist includes commercial fields', () => {
  for (const k of COMMERCIAL_EDITORIAL_FIELDS) {
    assert.equal(EDITORIAL_FIELDS.includes(k), true);
  }
});

test('Fixture A: editorial true/10/3 projects to live', () => {
  const editorial = {
    ...published,
    divideSemJuros: true,
    percentualDescontoPix: 10,
    maxParcelasSemJuros: 3,
  };
  const p = projectCatalog(baseStock, editorial, 'p-a');
  assert.equal(p.live.divideSemJuros, true);
  assert.equal(p.live.percentualDescontoPix, 10);
  assert.equal(p.live.maxParcelasSemJuros, 3);
  assert.equal(p.draft.divideSemJuros, true);
  assert.equal(p.draft.percentualDescontoPix, 10);
  assert.equal(p.draft.maxParcelasSemJuros, 3);
});

test('Fixture B: false/0/0 preserved (not truthy-filtered)', () => {
  const editorial = {
    ...published,
    divideSemJuros: false,
    percentualDescontoPix: 0,
    maxParcelasSemJuros: 0,
  };
  const p = projectCatalog(baseStock, editorial, 'p-b');
  assert.equal(p.live.divideSemJuros, false);
  assert.equal(p.live.percentualDescontoPix, 0);
  assert.equal(p.live.maxParcelasSemJuros, 0);
  assert.equal('divideSemJuros' in p.live, true);
  assert.equal('percentualDescontoPix' in p.live, true);
  assert.equal('maxParcelasSemJuros' in p.live, true);
});

test('Fixture C: absent commercial fields invent no defaults', () => {
  const p = projectCatalog(baseStock, published, 'p-c');
  assert.equal('divideSemJuros' in p.live, false);
  assert.equal('percentualDescontoPix' in p.live, false);
  assert.equal('maxParcelasSemJuros' in p.live, false);
});

test('Fixture D: stock qty/revision unchanged by commercial projection', () => {
  const stock = {
    ...baseStock,
    quantidade: 7,
    stockRevision: 4,
    divideSemJuros: true,
    percentualDescontoPix: 5,
    maxParcelasSemJuros: 2,
  };
  const p = projectCatalog(stock, published, 'p-d');
  assert.equal(p.stock.quantidade, 7);
  assert.equal(p.stock.stockRevision, 4);
  assert.equal(p.live.quantidade, 7);
  assert.equal(p.live.catalogStockRevision, 4);
  // Fallback from estoque when draft omits commercial keys
  assert.equal(p.live.divideSemJuros, true);
  assert.equal(p.live.percentualDescontoPix, 5);
  assert.equal(p.live.maxParcelasSemJuros, 2);
});

test('Fixture E/F: editorial wins over estoque when both present', () => {
  const stock = {
    ...baseStock,
    divideSemJuros: true,
    percentualDescontoPix: 10,
    maxParcelasSemJuros: 3,
  };
  const editorial = {
    ...published,
    divideSemJuros: false,
    percentualDescontoPix: 0,
    maxParcelasSemJuros: 1,
  };
  const p = projectCatalog(stock, editorial, 'p-ef');
  assert.equal(p.live.divideSemJuros, false);
  assert.equal(p.live.percentualDescontoPix, 0);
  assert.equal(p.live.maxParcelasSemJuros, 1);
});

test('validateEditorial accepts commercial fields incl. false/0', () => {
  assert.deepEqual(
    validateEditorial({
      divideSemJuros: false,
      percentualDescontoPix: 0,
      maxParcelasSemJuros: 0,
    }),
    {divideSemJuros: false, percentualDescontoPix: 0, maxParcelasSemJuros: 0},
  );
});

test('mergeCommercialEditorialFields uses presence not truthiness', () => {
  const m = mergeCommercialEditorialFields(
    {divideSemJuros: false, percentualDescontoPix: 0},
    {divideSemJuros: true, percentualDescontoPix: 10, maxParcelasSemJuros: 3},
  );
  assert.equal(m.divideSemJuros, false);
  assert.equal(m.percentualDescontoPix, 0);
  assert.equal(m.maxParcelasSemJuros, 3); // only from stock
});
