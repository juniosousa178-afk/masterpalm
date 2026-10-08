import test from 'node:test';
import assert from 'node:assert/strict';
import {
  evaluateConsignmentPickerEligibility,
  sellableConsignmentQty,
} from '../src/consignmentStock.js';

const baseDep = {comboIds: []};
const baseDraft = {nome: 'P', preco: 10};

test('simple qty 1 → picker 1', () => {
  const elig = evaluateConsignmentPickerEligibility({
    productId: 'p1',
    lojaId: 'mirjoias',
    stock: {stockKind: 'simple', stockRevision: 1, quantidade: 1, variacoes: {}},
    draft: baseDraft,
    dependency: baseDep,
  });
  assert.equal(elig.eligible, true);
  assert.equal(elig.availableQty, 1);
});

test('simple qty 3 → picker 3', () => {
  const elig = evaluateConsignmentPickerEligibility({
    productId: 'p1',
    lojaId: 'mirjoias',
    stock: {stockKind: 'simple', stockRevision: 1, quantidade: 3, variacoes: {}},
    draft: baseDraft,
    dependency: baseDep,
  });
  assert.equal(elig.availableQty, 3);
});

test('simple qty 0 → unavailable', () => {
  const elig = evaluateConsignmentPickerEligibility({
    productId: 'p1',
    lojaId: 'mirjoias',
    stock: {stockKind: 'simple', stockRevision: 1, quantidade: 0, variacoes: {}},
    draft: baseDraft,
    dependency: baseDep,
  });
  assert.equal(elig.eligible, false);
  assert.equal(elig.reason, 'ZERO_STOCK');
  assert.equal(elig.availableQty, 0);
});

test('variation P=1 M=0 G=2 sellable = min(aggregate, cellSum)', () => {
  const stock = {
    stockKind: 'variation',
    stockRevision: 1,
    quantidade: 3,
    variacoes: {
      P: {'sem-cor': 1},
      M: {'sem-cor': 0},
      G: {'sem-cor': 2},
    },
  };
  assert.equal(sellableConsignmentQty(stock, 'variation', stock.variacoes), 3);
  const elig = evaluateConsignmentPickerEligibility({
    productId: 'v1',
    lojaId: 'mirjoias',
    stock,
    draft: baseDraft,
    dependency: baseDep,
  });
  assert.equal(elig.eligible, true);
  assert.equal(elig.availableQty, 3);
});

test('overstated aggregate capped to cell sum', () => {
  const stock = {
    stockKind: 'variation',
    stockRevision: 1,
    quantidade: 4,
    variacoes: {
      '14': {'sem-cor': 2},
      '16': {'sem-cor': 1},
    },
  };
  assert.equal(sellableConsignmentQty(stock, 'variation', stock.variacoes), 3);
});

test('nested extra cell counted', () => {
  const stock = {
    stockKind: 'variation',
    stockRevision: 1,
    quantidade: 4,
    variacoes: {
      '14': {
        'sem-cor': 2,
        ESMERALDA: {_sem_extra: 1},
      },
      '16': {'sem-cor': 1},
    },
  };
  assert.equal(sellableConsignmentQty(stock, 'variation', stock.variacoes), 4);
});

test('cross-store denied', () => {
  const elig = evaluateConsignmentPickerEligibility({
    productId: 'p1',
    lojaId: 'mirjoias',
    stock: {
      stockKind: 'simple',
      stockRevision: 1,
      quantidade: 2,
      lojaId: 'nathy',
      variacoes: {},
    },
    draft: baseDraft,
    dependency: baseDep,
  });
  assert.equal(elig.eligible, false);
});
