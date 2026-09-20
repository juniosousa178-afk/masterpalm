import test from 'node:test';
import assert from 'node:assert/strict';
import {
  CLASSES,
  classifyLegacyConsignmentProduct,
  applyLegacyBootstrapPlan,
  evaluateAfterBootstrap,
  assertQtyUnchanged,
  snapshotQty,
} from '../src/consignmentLegacyBootstrap.js';

const lojaId = 'store-a';

function classify(partial) {
  return classifyLegacyConsignmentProduct({lojaId, ...partial});
}

test('1 valid legacy simple -> safe bootstrappable', () => {
  const stock = {quantidade: 3, nome: 'Anel'};
  const draft = {nome: 'Anel', preco: 10};
  const plan = classify({productId: 's1', stock, draft, dependency: null});
  assert.equal(plan.classification, CLASSES.LEGACY_SIMPLE_BOOTSTRAPPABLE);
  assert.equal(plan.bootstrappable, true);
  assert.equal(plan.writes.stockPatch.stockKind, 'simple');
  assert.equal(plan.writes.stockPatch.stockRevision, 0);
  assert.deepEqual(plan.writes.dependency, {comboIds: []});
  const applied = applyLegacyBootstrapPlan(stock, null, plan);
  assertQtyUnchanged(plan.qtyBefore, applied.stock);
  const elig = evaluateAfterBootstrap({
    lojaId, productId: 's1', stock: applied.stock, draft, dependency: applied.dependency,
  });
  assert.equal(elig.eligible, true);
});

test('2 simple qty unchanged after bootstrap', () => {
  const stock = {quantidade: 7};
  const draft = {nome: 'X'};
  const plan = classify({productId: 's2', stock, draft});
  const before = snapshotQty(stock);
  const applied = applyLegacyBootstrapPlan(stock, null, plan);
  assert.equal(applied.stock.quantidade, 7);
  assertQtyUnchanged(before, applied.stock);
});

test('3 legacy simple conflicting stock -> skipped', () => {
  const stock = {quantidade: 2, stockConflict: true};
  const draft = {nome: 'X'};
  const plan = classify({productId: 's3', stock, draft});
  assert.equal(plan.classification, CLASSES.CONFLICT);
  assert.equal(plan.bootstrappable, false);
});

test('4 valid legacy variation -> safe bootstrappable', () => {
  // Single-axis size map with technical color "sem-cor" (official normal variation shape).
  const stockVar = {
    quantidade: 4,
    stockKind: 'variation',
    variacoes: {P: {'sem-cor': 4}},
  };
  const plan2 = classify({productId: 'v2', stock: stockVar, draft: {nome: 'Var'}, dependency: null});
  assert.equal(plan2.classification, CLASSES.LEGACY_VARIATION_BOOTSTRAPPABLE);
  assert.equal(plan2.writes.stockPatch.stockRevision, 0);
  assert.deepEqual(plan2.writes.dependency, {comboIds: []});
  const applied = applyLegacyBootstrapPlan(stockVar, null, plan2);
  const elig = evaluateAfterBootstrap({
    lojaId, productId: 'v2', stock: applied.stock, draft: {nome: 'Var'}, dependency: applied.dependency,
  });
  assert.equal(elig.eligible, true);
});

test('5 variation quantities unchanged', () => {
  const stock = {
    quantidade: 4,
    stockKind: 'variation',
    variacoes: {P: {'sem-cor': 4}},
  };
  const draft = {nome: 'Var'};
  const plan = classify({productId: 'v3', stock, draft});
  assert.equal(plan.bootstrappable, true);
  const applied = applyLegacyBootstrapPlan(stock, null, plan);
  assert.deepEqual(applied.stock.variacoes, stock.variacoes);
  assert.equal(applied.stock.quantidade, 4);
});

test('6 ambiguous variation -> skipped', () => {
  const stock = {
    quantidade: 3,
    tamanhos: ['P'],
    cores: ['Azul', 'Vermelho'],
    // missing variacoes matrix
  };
  const plan = classify({productId: 'a1', stock, draft: {nome: 'A'}});
  assert.ok([CLASSES.UNSAFE_AMBIGUOUS, CLASSES.GRADE, CLASSES.INVALID_STOCK].includes(plan.classification));
  assert.equal(plan.bootstrappable, false);
});

test('7 grade -> skipped', () => {
  const stock = {
    quantidade: 3,
    stockKind: 'variation',
    stockRevision: 0,
    variacoes: {P: {Azul: 1, Vermelho: 2}},
    tamanhos: ['P'],
    cores: ['Azul', 'Vermelho'],
  };
  const plan = classify({productId: 'gr1', stock, draft: {nome: 'G'}, dependency: {comboIds: []}});
  assert.equal(plan.classification, CLASSES.GRADE);
  assert.equal(plan.bootstrappable, false);
});

test('8 combo -> skipped', () => {
  const stock = {
    quantidade: 1,
    stockKind: 'combo',
    stockRevision: 0,
    tipoProduto: 'combo',
    itensCombo: [{productId: 'x', quantidade: 1}],
  };
  const plan = classify({productId: 'c1', stock, draft: {nome: 'Kit'}, dependency: {comboIds: []}});
  assert.equal(plan.classification, CLASSES.COMBO);
  assert.equal(plan.bootstrappable, false);
});

test('9 zero-stock safe metadata allowed but hidden from picker', () => {
  const stock = {quantidade: 0};
  const draft = {nome: 'Z'};
  const plan = classify({productId: 'z1', stock, draft});
  assert.equal(plan.classification, CLASSES.LEGACY_SIMPLE_BOOTSTRAPPABLE);
  assert.equal(plan.zeroStock, true);
  const applied = applyLegacyBootstrapPlan(stock, null, plan);
  const elig = evaluateAfterBootstrap({
    lojaId, productId: 'z1', stock: applied.stock, draft, dependency: applied.dependency,
  });
  assert.equal(elig.eligible, false);
  assert.equal(elig.reason, 'INSUFFICIENT_STOCK');
});

test('10 already-safe -> no-op', () => {
  const stock = {quantidade: 2, stockKind: 'simple', stockRevision: 0};
  const draft = {nome: 'S'};
  const dep = {comboIds: []};
  const plan = classify({productId: 'ok1', stock, draft, dependency: dep});
  assert.equal(plan.classification, CLASSES.ALREADY_SAFE);
  assert.equal(plan.bootstrappable, false);
  assert.equal(plan.writes, null);
});

test('11 repeat bootstrap -> idempotent', () => {
  const stock = {quantidade: 2};
  const draft = {nome: 'S'};
  const plan1 = classify({productId: 'id1', stock, draft});
  const once = applyLegacyBootstrapPlan(stock, null, plan1);
  const plan2 = classify({
    productId: 'id1', stock: once.stock, draft, dependency: once.dependency,
  });
  assert.equal(plan2.classification, CLASSES.ALREADY_SAFE);
  assert.equal(plan2.bootstrappable, false);
  assert.equal(once.stock.stockRevision, 0);
  const twice = applyLegacyBootstrapPlan(once.stock, once.dependency, plan2);
  assert.equal(twice.mutated, false);
  assert.equal(twice.stock.stockRevision, 0);
});

test('12 no public catalog dependency', () => {
  const stock = {quantidade: 2, stockKind: 'simple', stockRevision: 0};
  const draft = {nome: 'S', publicadoNoCatalogo: false, catalog_ativo: false};
  const dep = {comboIds: []};
  const elig = evaluateAfterBootstrap({lojaId, productId: 'pc1', stock, draft, dependency: dep});
  assert.equal(elig.eligible, true);
});

test('13 wrong-store isolation', () => {
  const stock = {quantidade: 2, lojaId: 'other'};
  const draft = {nome: 'S', lojaId: 'other'};
  const plan = classify({productId: 'ws1', stock, draft});
  assert.equal(plan.classification, CLASSES.OTHER_UNSUPPORTED);
  assert.equal(plan.reason, 'CROSS_STORE');
  assert.equal(plan.bootstrappable, false);
});

test('14 Mirjoias no writes (classifier refuses foreign store when lojaId=mirjoias claimed elsewhere)', () => {
  const stock = {quantidade: 5, lojaId: 'mirjoias'};
  const draft = {nome: 'M', lojaId: 'mirjoias'};
  const plan = classifyLegacyConsignmentProduct({
    lojaId: 'master', productId: 'm1', stock, draft,
  });
  assert.equal(plan.bootstrappable, false);
  assert.equal(plan.writes, null);
});

test('15 no sale fields in bootstrap plan', () => {
  const plan = classify({productId: 's15', stock: {quantidade: 1}, draft: {nome: 'S'}});
  assert.equal(plan.writes.stockPatch.saleId, undefined);
  assert.ok(!('vendas' in (plan.writes.stockPatch || {})));
});

test('16 no finance fields in bootstrap plan', () => {
  const plan = classify({productId: 's16', stock: {quantidade: 1}, draft: {nome: 'S'}});
  assert.ok(!JSON.stringify(plan.writes).includes('finance'));
});

test('17 no receivable fields in bootstrap plan', () => {
  const plan = classify({productId: 's17', stock: {quantidade: 1}, draft: {nome: 'S'}});
  assert.ok(!JSON.stringify(plan.writes).includes('receivable'));
});

test('18 no consignation fields in bootstrap plan', () => {
  const plan = classify({productId: 's18', stock: {quantidade: 1}, draft: {nome: 'S'}});
  assert.ok(!JSON.stringify(plan.writes).includes('consignment'));
});

test('19 picker eligibility becomes true only for safe product', () => {
  const stock = {quantidade: 2};
  const draft = {nome: 'S'};
  const before = evaluateAfterBootstrap({lojaId, productId: 'e1', stock, draft, dependency: null});
  assert.equal(before.eligible, false);
  const plan = classify({productId: 'e1', stock, draft});
  const applied = applyLegacyBootstrapPlan(stock, null, plan);
  const after = evaluateAfterBootstrap({
    lojaId, productId: 'e1', stock: applied.stock, draft, dependency: applied.dependency,
  });
  assert.equal(after.eligible, true);
});

test('20 unsafe product remains fail-closed', () => {
  const stock = {
    quantidade: 9,
    stockKind: 'variation',
    stockRevision: 0,
    variacoes: {P: {Azul: 4, Vermelho: 5}},
    tamanhos: ['P'],
    cores: ['Azul', 'Vermelho'],
  };
  const draft = {nome: 'Grade'};
  const plan = classify({productId: 'u1', stock, draft, dependency: {comboIds: []}});
  assert.equal(plan.bootstrappable, false);
  const elig = evaluateAfterBootstrap({lojaId, productId: 'u1', stock, draft, dependency: {comboIds: []}});
  assert.equal(elig.eligible, false);
});
