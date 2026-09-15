import test, {after} from 'node:test';
import assert from 'node:assert/strict';
import {Firestore} from 'firebase-admin/firestore';
import {executeStockCommand} from '../src/stockCatalogCommands.js';
import {resolveLegacyCompatStockKind} from '../src/catalogStockProjection.js';

const __emu = process.env.FIRESTORE_EMULATOR_HOST || '';
if (!/^127\.0\.0\.1:\d+$/.test(__emu)) {
  throw new Error('Local emulator required; refusing any other endpoint: ' + __emu);
}
const db = new Firestore({projectId: 'demo-stock-catalog'});
after(() => db.terminate());

const runId = Date.now().toString(36);
let sequence = 0;
const owner = {uid: 'owner'};

function salePayload(overrides = {}) {
  return {
    clienteNome: 'Cliente Teste',
    produtosDescricao: '1 x Peça',
    quantidade: 1,
    preco: 10,
    total: 10,
    formasPagamento: 'Pagamento Dinheiro: R$ 10.00',
    frete: 0,
    desconto: 0,
    descontoValor: 0,
    observacao: '',
    pagamentoDinheiro: 10,
    pagamentoPix: 0,
    pagamentoCartao: 0,
    taxas: 0,
    custoProdutos: 0,
    tamanho: '',
    vendedor: 'App',
    itens: [{
      produtoNome: 'Peça', quantidade: 1, tamanho: '', cor: '',
      precoUnitario: 10, precoTotal: 10, productId: 'p', custoUnitario: 0,
      origemCustoItem: 'desconhecido',
    }],
    ...overrides,
  };
}

async function seedLegacy({
  product = {}, control = null, omitStockKind = false, withOwner = true,
  withDraft = false, withDep = false, grant = false,
} = {}) {
  const lojaId = `atomic_${runId}_${++sequence}`;
  const base = db.collection('lojas').doc(lojaId);
  const batch = db.batch();
  batch.set(base, withOwner ? {ownerUid: 'owner', name: 'Fixture'} : {name: 'Fixture'});
  const stock = {quantidade: 1, stockRevision: 1, ...product};
  if (!omitStockKind && !('stockKind' in product)) stock.stockKind = 'simple';
  if (omitStockKind) delete stock.stockKind;
  batch.set(base.collection('estoque_produtos').doc('p'), stock);
  if (withDraft) batch.set(base.collection('draft_produtos').doc('p'), {nome: 'Peça', publicadoNoCatalogo: true});
  if (withDep) batch.set(base.collection('stock_catalog_dependencies').doc('p'), {comboIds: []});
  if (control) batch.set(base.collection('stock_catalog_control').doc('state'), control);
  if (grant) {
    batch.set(base.collection('stock_catalog_access').doc('owner'), {
      enabled: true,
      permissions: {sale: true, restock: true, adjust: true, restore: true, editorial: true, publish: true, create: true, delete: true, undo: true},
    });
  }
  await batch.commit();
  return {base, lojaId};
}

async function seedActive(product = {}) {
  return seedLegacy({
    product: {quantidade: 1, stockKind: 'simple', stockRevision: 0, ...product},
    control: {protocolVersion: 1, mode: 'active', migrationComplete: true},
    withDraft: true,
    withDep: true,
    grant: true,
    withOwner: true,
  });
}

function intent(lojaId, operationId, {atomic = false, item = {}, sale = null, extra = {}} = {}) {
  const cmd = {
    protocolVersion: 1,
    lojaId,
    kind: 'sale',
    operationId,
    items: [{productId: 'p', quantity: 1, ...item}],
    ...extra,
  };
  if (atomic) {
    cmd.atomicPdvSale = true;
    cmd.sale = sale ?? salePayload();
  }
  return cmd;
}

async function denied(promise, code, messageIncludes) {
  await assert.rejects(promise, e => {
    if (e.code !== code) return false;
    if (messageIncludes && !String(e.message).includes(messageIncludes)) return false;
    return true;
  });
}

const grade = {
  quantidade: 6,
  stockRevision: 2,
  estoquePorTamanho: {36: 2, 37: 2, 38: 2},
  variacoes: {36: {preto: 2}, 37: {preto: 2}, 38: {preto: 2}},
  tamanhos: ['36', '37', '38'],
};

test('legacy stockKind fix still present', () => {
  assert.equal(typeof resolveLegacyCompatStockKind, 'function');
  assert.deepEqual(resolveLegacyCompatStockKind({quantidade: 1}), {
    stockKind: 'simple', stockKindSource: 'inferred',
  });
});

test('1 inactive simple atomic success', async () => {
  const {base, lojaId} = await seedLegacy({
    control: {protocolVersion: 1, mode: 'inactive', migrationComplete: false},
    product: {quantidade: 1},
  });
  const result = await executeStockCommand(db, intent(lojaId, 'a1', {atomic: true}), owner);
  assert.equal(result.alreadyApplied, false);
  assert.equal(result.saleCommitted, true);
  assert.equal(result.saleId, 'a1');
  assert.equal((await base.collection('estoque_produtos').doc('p').get()).data().quantidade, 0);
  const sale = (await base.collection('estoque_vendas').doc('a1').get()).data();
  assert.equal(sale.lojaId, lojaId);
  assert.equal(sale.total, 10);
  assert.equal(sale.origemVenda, 'pdv_atomic');
  assert.equal(sale.stockOperationId, 'a1');
});

test('2 no-control simple atomic success', async () => {
  const {base, lojaId} = await seedLegacy({product: {quantidade: 1}});
  const result = await executeStockCommand(db, intent(lojaId, 'a2', {atomic: true}), owner);
  assert.equal(result.saleCommitted, true);
  assert.equal((await base.collection('estoque_produtos').doc('p').get()).data().quantidade, 0);
  assert.equal((await base.collection('estoque_vendas').doc('a2').get()).exists, true);
});

test('3 variation inactive atomic success size 37', async () => {
  const {base, lojaId} = await seedLegacy({
    omitStockKind: true,
    product: grade,
    control: {protocolVersion: 1, mode: 'inactive', migrationComplete: false},
  });
  const sale = salePayload({
    itens: [{
      produtoNome: 'Grade', quantidade: 1, tamanho: '37', cor: 'preto',
      precoUnitario: 10, precoTotal: 10, productId: 'p', custoUnitario: 0,
      origemCustoItem: 'desconhecido',
    }],
    tamanho: '37',
  });
  await executeStockCommand(db, intent(lojaId, 'a3', {
    atomic: true, item: {size: '37', color: 'preto'}, sale,
  }), owner);
  const stock = (await base.collection('estoque_produtos').doc('p').get()).data();
  assert.equal(stock.variacoes['37'].preto, 1);
  assert.equal(stock.variacoes['36'].preto, 2);
  assert.equal(stock.variacoes['38'].preto, 2);
  const doc = (await base.collection('estoque_vendas').doc('a3').get()).data();
  assert.equal(doc.itens[0].tamanho, '37');
});

test('4 ACTIVE atomic success preserves CAS revision', async () => {
  const {base, lojaId} = await seedActive({quantidade: 2, stockRevision: 3});
  const result = await executeStockCommand(db, intent(lojaId, 'a4', {atomic: true}), owner);
  assert.equal(result.saleCommitted, true);
  const stock = (await base.collection('estoque_produtos').doc('p').get()).data();
  assert.equal(stock.quantidade, 1);
  assert.equal(stock.stockRevision, 4);
  assert.equal(stock.stockOperationId, 'a4');
  assert.equal((await base.collection('estoque_vendas').doc('a4').get()).exists, true);
});

test('5 missing stockKind legacy atomic success', async () => {
  const {base, lojaId} = await seedLegacy({omitStockKind: true, product: {quantidade: 1}});
  await executeStockCommand(db, intent(lojaId, 'a5', {atomic: true}), owner);
  const stock = (await base.collection('estoque_produtos').doc('p').get()).data();
  assert.equal(stock.quantidade, 0);
  assert.equal(stock.stockKind, undefined);
  assert.equal((await base.collection('estoque_vendas').doc('a5').get()).exists, true);
});

test('6 valid explicit kind preserved with atomic', async () => {
  const {base, lojaId} = await seedLegacy({product: {stockKind: 'simple', quantidade: 1}});
  await executeStockCommand(db, intent(lojaId, 'a6', {atomic: true}), owner);
  assert.equal((await base.collection('estoque_produtos').doc('p').get()).data().stockKind, 'simple');
});

test('7 invalid kind fails closed atomic', async () => {
  const {base, lojaId} = await seedLegacy({product: {stockKind: 'legacy-grade', quantidade: 1}});
  await denied(executeStockCommand(db, intent(lojaId, 'a7', {atomic: true}), owner),
    'failed-precondition', 'Invalid stockKind');
  assert.equal((await base.collection('estoque_produtos').doc('p').get()).data().quantidade, 1);
  assert.equal((await base.collection('estoque_vendas').doc('a7').get()).exists, false);
});

test('8 forced sale write failure → no stock', async () => {
  const {base, lojaId} = await seedLegacy({product: {quantidade: 1}});
  await denied(
    executeStockCommand(db, intent(lojaId, 'a8', {
      atomic: true,
      sale: salePayload({observacao: '__FORCE_SALE_WRITE_FAIL__'}),
    }), owner),
    'internal',
    'Forced sale write failure',
  );
  assert.equal((await base.collection('estoque_produtos').doc('p').get()).data().quantidade, 1);
  assert.equal((await base.collection('estoque_vendas').doc('a8').get()).exists, false);
  assert.equal((await base.collection('stock_catalog_operations').doc('a8').get()).exists, false);
});

test('9 stock failure → no sale', async () => {
  const {base, lojaId} = await seedLegacy({product: {quantidade: 0}});
  await assert.rejects(executeStockCommand(db, intent(lojaId, 'a9', {atomic: true}), owner));
  assert.equal((await base.collection('estoque_vendas').doc('a9').get()).exists, false);
  assert.equal((await base.collection('stock_catalog_operations').doc('a9').get()).exists, false);
});

test('10 sale validation abort → neither', async () => {
  const {base, lojaId} = await seedLegacy({product: {quantidade: 1}});
  await denied(
    executeStockCommand(db, intent(lojaId, 'a10', {
      atomic: true,
      sale: salePayload({total: 10, pagamentoDinheiro: 5}),
    }), owner),
    'invalid-argument',
    'Payment total mismatch',
  );
  assert.equal((await base.collection('estoque_produtos').doc('p').get()).data().quantidade, 1);
  assert.equal((await base.collection('estoque_vendas').doc('a10').get()).exists, false);
});

test('11 retry after commit returns existing', async () => {
  const {base, lojaId} = await seedLegacy({product: {quantidade: 2}});
  const cmd = intent(lojaId, 'a11', {atomic: true});
  const first = await executeStockCommand(db, cmd, owner);
  const second = await executeStockCommand(db, cmd, owner);
  assert.equal(first.alreadyApplied, false);
  assert.equal(second.alreadyApplied, true);
  assert.equal(second.saleCommitted, true);
  assert.equal(second.saleId, 'a11');
  assert.equal((await base.collection('estoque_produtos').doc('p').get()).data().quantidade, 1);
  const sales = await base.collection('estoque_vendas').get();
  assert.equal(sales.size, 1);
});

test('12 response timeout + retry same operation', async () => {
  const {base, lojaId} = await seedLegacy({product: {quantidade: 2}});
  const cmd = intent(lojaId, 'a12', {atomic: true});
  await executeStockCommand(db, cmd, owner);
  // Simulate lost response: client retries identical command.
  const retry = await executeStockCommand(db, cmd, owner);
  assert.equal(retry.alreadyApplied, true);
  assert.equal(retry.saleCommitted, true);
  assert.equal((await base.collection('estoque_produtos').doc('p').get()).data().quantidade, 1);
  assert.equal((await base.collection('estoque_vendas').get()).size, 1);
});

test('13 duplicate click / idempotency', async () => {
  const {base, lojaId} = await seedLegacy({product: {quantidade: 3}});
  const cmd = intent(lojaId, 'a13', {atomic: true});
  const results = await Promise.all([
    executeStockCommand(db, cmd, owner),
    executeStockCommand(db, cmd, owner),
  ]);
  assert.equal(results.filter(r => r.alreadyApplied).length, 1);
  assert.equal((await base.collection('estoque_produtos').doc('p').get()).data().quantidade, 2);
  assert.equal((await base.collection('estoque_vendas').get()).size, 1);
});

test('14 ACTIVE stale revision → no sale no stock', async () => {
  const {base, lojaId} = await seedActive({quantidade: 2, stockRevision: 5});
  await denied(
    executeStockCommand(db, {
      ...intent(lojaId, 'a14', {atomic: true}),
      kind: 'adjust',
      atomicPdvSale: true,
      sale: salePayload(),
      items: [{productId: 'p', quantity: 1, expectedRevision: 0}],
    }, owner),
    'invalid-argument',
  );
  // adjust + atomic rejected at parse; stock unchanged
  assert.equal((await base.collection('estoque_produtos').doc('p').get()).data().quantidade, 2);
  assert.equal((await base.collection('estoque_vendas').doc('a14').get()).exists, false);
});

test('14b ACTIVE sale with stale adjust semantics via expectedRevision on sale N/A — stock fail path', async () => {
  const {base, lojaId} = await seedActive({quantidade: 0, stockRevision: 2});
  await assert.rejects(executeStockCommand(db, intent(lojaId, 'a14b', {atomic: true}), owner));
  assert.equal((await base.collection('estoque_vendas').doc('a14b').get()).exists, false);
  assert.equal((await base.collection('estoque_produtos').doc('p').get()).data().quantidade, 0);
});

test('15 unauthorized', async () => {
  const {lojaId} = await seedLegacy({product: {quantidade: 1}});
  await denied(executeStockCommand(db, intent(lojaId, 'a15', {atomic: true}), null), 'unauthenticated');
});

test('16 other-store denied', async () => {
  const {lojaId} = await seedLegacy({product: {quantidade: 1}, withOwner: false});
  await denied(
    executeStockCommand(db, intent(lojaId, 'a16', {atomic: true}), {uid: 'stranger'}),
    'permission-denied',
  );
});

test('18 Nathy SALE B regression: missing kind + atomic prevents partial', async () => {
  const {base, lojaId} = await seedLegacy({
    omitStockKind: true,
    product: {quantidade: 1},
    control: {protocolVersion: 1, mode: 'inactive', migrationComplete: false},
  });
  // Pre-fix shaped failure: stock-only would leave qty=0 without sale.
  // Post-fix: forced sale fail leaves stock=1 and sale absent.
  await denied(
    executeStockCommand(db, intent(lojaId, 'nathy_b', {
      atomic: true,
      sale: salePayload({observacao: '__FORCE_SALE_WRITE_FAIL__'}),
    }), owner),
    'internal',
  );
  assert.equal((await base.collection('estoque_produtos').doc('p').get()).data().quantidade, 1);
  assert.equal((await base.collection('estoque_vendas').doc('nathy_b').get()).exists, false);
  // Success path: both together
  await executeStockCommand(db, intent(lojaId, 'nathy_ok', {atomic: true}), owner);
  assert.equal((await base.collection('estoque_produtos').doc('p').get()).data().quantidade, 0);
  assert.equal((await base.collection('estoque_vendas').doc('nathy_ok').get()).exists, true);
});

test('19 old protocol backward compat: no atomic → no estoque_vendas', async () => {
  const {base, lojaId} = await seedLegacy({product: {quantidade: 1}});
  const result = await executeStockCommand(db, intent(lojaId, 'old1', {atomic: false}), owner);
  assert.equal(result.saleCommitted, undefined);
  assert.equal((await base.collection('estoque_produtos').doc('p').get()).data().quantidade, 0);
  assert.equal((await base.collection('estoque_vendas').doc('old1').get()).exists, false);
});

test('20 new atomic protocol marker required for sale field', async () => {
  const {lojaId} = await seedLegacy({product: {quantidade: 1}});
  await denied(
    executeStockCommand(db, {
      ...intent(lojaId, 'bad', {atomic: false}),
      sale: salePayload(),
    }, owner),
    'invalid-argument',
    'sale requires atomicPdvSale',
  );
});

test('ACTIVE valid atomic sale', async () => {
  const {base, lojaId} = await seedActive({quantidade: 1, stockRevision: 1});
  const r = await executeStockCommand(db, intent(lojaId, 'active_ok', {atomic: true}), owner);
  assert.equal(r.authoritativeSalePersisted, true);
  assert.equal(r.authoritativeStockCommitted, true);
  assert.equal((await base.collection('estoque_vendas').doc('active_ok').get()).exists, true);
});
