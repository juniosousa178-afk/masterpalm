import test from 'node:test';
import assert from 'node:assert/strict';
import {classifyConsignmentProduct} from '../src/consignmentStock.js';
import {quantity} from '../src/catalogStockProjection.js';
import {CODES} from '../src/consignmentProtocol.js';

function eligible(stock, dep) {
  if (!dep || !Array.isArray(dep.comboIds)) return false;
  const classified = classifyConsignmentProduct(stock);
  quantity(classified.stock.stockRevision ?? stock.stockRevision);
  return classified.kind === 'simple' || classified.kind === 'variation';
}

test('1 safe simple with revision and comboIds is eligible', () => {
  const stock = {stockKind: 'simple', tipoProduto: 'simples', quantidade: 1, stockRevision: 0, variacoes: {}};
  assert.equal(classifyConsignmentProduct(stock).kind, 'simple');
  assert.equal(eligible(stock, {comboIds: []}), true);
});

test('2 safe normal variation with canonical variacoes is eligible', () => {
  const stock = {
    stockKind: 'variation', quantidade: 4, stockRevision: 0,
    variacoes: {P: {'sem-cor': 4}}, tamanhos: ['P'],
  };
  assert.equal(classifyConsignmentProduct(stock).kind, 'variation');
  assert.equal(eligible(stock, {comboIds: []}), true);
});

test('3 already migrated no-op: second comboIds write not required', () => {
  const stock = {stockKind: 'simple', quantidade: 2, stockRevision: 0};
  assert.equal(eligible(stock, {comboIds: []}), true);
  assert.equal(eligible(stock, {comboIds: []}), true);
});

test('4 missing stockRevision is not eligible even with dependency', () => {
  const stock = {tipoProduto: 'simples', quantidade: 1};
  assert.throws(() => classifyConsignmentProduct(stock), e => e.consignmentCode === CODES.PRODUCT_STATE_UNSAFE);
  assert.throws(() => eligible(stock, {comboIds: []}));
});

test('5 grade denied', () => {
  assert.throws(() => classifyConsignmentProduct({
    stockKind: 'variation',
    variacoes: {P: {Azul: 1, Vermelho: 2}},
    tamanhos: ['P'], cores: ['Azul', 'Vermelho'], quantidade: 3, stockRevision: 0,
  }), e => e.consignmentCode === CODES.CONSIGNMENT_GRADE_NOT_SUPPORTED);
});

test('6 combo denied', () => {
  assert.throws(() => classifyConsignmentProduct({
    stockKind: 'combo', tipoProduto: 'combo', itensCombo: [{productId: 'x', quantidade: 1}],
    quantidade: 1, stockRevision: 0,
  }), e => e.consignmentCode === CODES.PRODUCT_STATE_UNSAFE);
});

test('operator-like jewelry SKU without revision remains blocked', () => {
  const stock = {tipoProduto: 'simples', quantidade: 1, nome: 'Anel 2 Folhas T.18 Prata 925'};
  assert.throws(() => quantity(stock.stockRevision));
  assert.throws(() => eligible(stock, {comboIds: []}));
});
