import test, {after} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {Firestore} from 'firebase-admin/firestore';
import {executeStockCommand} from '../src/stockCatalogCommands.js';
import {
  GRADE_SALE_NOT_AUTHORIZED,
  VARIATION_PRODUCT_STATE_UNSAFE,
  VARIATION_IDENTITY_NOT_RESOLVED,
  VARIATION_NOT_FOUND,
  VARIATION_STOCK_INVALID,
  VARIATION_SALE_PRODUCT_GRANTS_COLLECTION,
  evaluateSafeVariationSaleEligibility,
} from '../src/stockCatalogAccess.js';

const __emuHost = process.env.FIRESTORE_EMULATOR_HOST || '';
if (!/^127\.0\.0\.1:\d+$/.test(__emuHost)) {
  throw new Error('Local emulator required; refusing any other endpoint: ' + __emuHost);
}
const db = new Firestore({projectId: 'demo-safe-variation-runtime'});
after(() => db.terminate());

const runId = Date.now().toString(36);
let sequence = 0;
const owner = {uid: 'owner'};
const stranger = {uid: 'stranger'};

const PRODUCT2 = 'mirjoias-anel-cora-o-color-t-22-prata-925-3';
const PRODUCT3 = 'mirjoias-anel-cora-o-placa-t-15-t-18-prata-925-3';
const PRODUCT4 = 'mirjoias-brinco-cora-o-p-prata-925-3';
const PRODUCT1 = 'mirjoias-brinco-argola-bolinha-cravejado-p-m-g-semijoia';

function accessSrc() {
  return readFileSync(new URL('../src/stockCatalogAccess.js', import.meta.url), 'utf8');
}
function commandsSrc() {
  return readFileSync(new URL('../src/stockCatalogCommands.js', import.meta.url), 'utf8');
}

async function seed(opts = {}) {
  const lojaId = opts.lojaId ?? `svr_${runId}_${++sequence}`;
  const base = db.collection('lojas').doc(lojaId);
  const productId = opts.productId ?? 'safe';
  const batch = db.batch();
  batch.set(base, {ownerUid: opts.ownerUid ?? 'owner', name: opts.storeName ?? 'Safe Runtime Fixture'});
  const stock = {
    quantidade: opts.quantidade ?? 2,
    stockKind: opts.stockKind ?? 'variation',
    stockRevision: opts.stockRevision ?? 1,
    ...(opts.stock || {}),
  };
  if ((opts.stockKind ?? 'variation') !== 'simple') {
    if (!('variacoes' in stock)) stock.variacoes = opts.variacoes ?? {P: {'sem-cor': 2}};
    if (!('estoquePorTamanho' in stock)) stock.estoquePorTamanho = opts.estoquePorTamanho ?? {P: 2};
  }
  batch.set(base.collection('estoque_produtos').doc(productId), stock);
  batch.set(base.collection('draft_produtos').doc(productId), {nome: opts.nome ?? 'Peca', publicadoNoCatalogo: true});
  batch.set(base.collection('stock_catalog_dependencies').doc(productId), {comboIds: []});
  if (opts.simpleProductId) {
    batch.set(base.collection('estoque_produtos').doc(opts.simpleProductId), {
      quantidade: 3, stockKind: 'simple', stockRevision: 1,
    });
    batch.set(base.collection('draft_produtos').doc(opts.simpleProductId), {nome: 'Simples'});
    batch.set(base.collection('stock_catalog_dependencies').doc(opts.simpleProductId), {comboIds: []});
  }
  if (opts.grant === true) {
    batch.set(base.collection(VARIATION_SALE_PRODUCT_GRANTS_COLLECTION).doc(productId), {enabled: true});
  }
  if (opts.tombstone) {
    batch.set(base.collection('exclusao_produto').doc(productId), opts.tombstone);
  }
  if (opts.protocol === 'active') {
    batch.set(base.collection('stock_catalog_control').doc('state'), {
      protocolVersion: 1, mode: 'active', migrationComplete: true,
    });
    batch.set(base.collection('stock_catalog_access').doc('owner'), {
      enabled: true, permissions: {sale: true, restock: true, adjust: true, restore: true},
    });
  }
  await batch.commit();
  return {base, lojaId, productId};
}

function sale(lojaId, operationId, item = {}) {
  const row = {
    productId: item.productId ?? 'safe',
    quantity: item.quantity ?? 1,
  };
  if (item.size !== undefined) row.size = item.size;
  else if (!item.omitSize) row.size = 'P';
  if (item.color !== undefined) row.color = item.color;
  else if (!item.omitColor) row.color = 'sem-cor';
  if (item.extra) row.extra = item.extra;
  return {protocolVersion: 1, lojaId, kind: 'sale', operationId, items: [row], ...(item.extraCommand || {})};
}

async function denied(promise, code, messageIncludes) {
  await assert.rejects(promise, e => {
    if (e.code !== code) return false;
    if (messageIncludes && !String(e.message).includes(messageIncludes)) return false;
    return true;
  });
}

test('1 healthy variation product allowed', async () => {
  const {base, lojaId} = await seed();
  await executeStockCommand(db, sale(lojaId, 't1'), owner);
  const stock = (await base.collection('estoque_produtos').doc('safe').get()).data();
  assert.equal(stock.variacoes.P['sem-cor'], 1);
  assert.equal(stock.quantidade, 1);
});

test('2 healthy product without manual product grant allowed', async () => {
  const {base, lojaId} = await seed({grant: false});
  await executeStockCommand(db, sale(lojaId, 't2'), owner);
  assert.equal((await base.collection('estoque_produtos').doc('safe').get()).data().quantidade, 1);
});

test('3 existing granted healthy product allowed', async () => {
  const {base, lojaId} = await seed({grant: true});
  await executeStockCommand(db, sale(lojaId, 't3'), owner);
  assert.equal((await base.collection('estoque_produtos').doc('safe').get()).data().quantidade, 1);
});

test('4 requested variation missing denied', async () => {
  const {base, lojaId} = await seed();
  await denied(executeStockCommand(db, sale(lojaId, 't4', {size: 'G'}), owner),
    'failed-precondition', 'Variation not found');
  assert.equal((await base.collection('estoque_produtos').doc('safe').get()).data().variacoes.P['sem-cor'], 2);
});

test('5 malformed canonical variations denied', async () => {
  const {base, lojaId} = await seed({stock: {variacoes: {P: 'bad'}, estoquePorTamanho: {P: 2}, quantidade: 2}});
  await denied(executeStockCommand(db, sale(lojaId, 't5'), owner), 'failed-precondition');
  assert.equal((await base.collection('estoque_produtos').doc('safe').get()).data().quantidade, 2);
});

test('6 ambiguous product identity denied', async () => {
  const {base, lojaId} = await seed({
    variacoes: {P: {'sem-cor': 2}, p: {'sem-cor': 2}},
    estoquePorTamanho: {P: 2, p: 2},
    quantidade: 4,
  });
  await denied(executeStockCommand(db, sale(lojaId, 't6'), owner),
    'permission-denied', VARIATION_IDENTITY_NOT_RESOLVED);
  assert.equal((await base.collection('estoque_produtos').doc('safe').get()).data().quantidade, 4);
});

test('7 invalid qty denied', async () => {
  const {lojaId} = await seed();
  await denied(executeStockCommand(db, sale(lojaId, 't7', {quantity: 1.5}), owner), 'failed-precondition');
  await denied(executeStockCommand(db, sale(lojaId, 't7b', {quantity: -1}), owner), 'failed-precondition');
  await denied(executeStockCommand(db, sale(lojaId, 't7c', {quantity: 0}), owner), 'invalid-argument');
});

test('8 zero stock insufficient stock failure', async () => {
  const {base, lojaId} = await seed({
    quantidade: 0, variacoes: {P: {'sem-cor': 0}}, estoquePorTamanho: {P: 0}, stockRevision: 3,
  });
  await denied(executeStockCommand(db, sale(lojaId, 't8'), owner), 'failed-precondition');
  const stock = (await base.collection('estoque_produtos').doc('safe').get()).data();
  assert.equal(stock.variacoes.P['sem-cor'], 0);
  assert.equal(stock.stockRevision, 3);
});

test('9 exact stock decrement atomic', async () => {
  const {base, lojaId} = await seed({quantidade: 2, variacoes: {P: {'sem-cor': 2}}, stockRevision: 5});
  await executeStockCommand(db, sale(lojaId, 't9'), owner);
  const stock = (await base.collection('estoque_produtos').doc('safe').get()).data();
  assert.equal(stock.variacoes.P['sem-cor'], 1);
  assert.equal(stock.quantidade, 1);
  assert.equal(stock.estoquePorTamanho.P, 1);
});

test('10 sale record once', async () => {
  const {base, lojaId} = await seed();
  await executeStockCommand(db, {
    protocolVersion: 1, lojaId, kind: 'sale', operationId: 't10',
    atomicPdvSale: true,
    items: [{productId: 'safe', quantity: 1, size: 'P', color: 'sem-cor'}],
    sale: {
      clienteNome: 'Cliente Teste', produtosDescricao: '1 x Peca', quantidade: 1, preco: 10, total: 10,
      formasPagamento: 'Pagamento Dinheiro: R$ 10.00', frete: 0, desconto: 0, descontoValor: 0, observacao: '',
      pagamentoDinheiro: 10, pagamentoPix: 0, pagamentoCartao: 0, taxas: 0, custoProdutos: 0,
      tamanho: 'P', vendedor: 'App',
      itens: [{
        produtoNome: 'Peca', quantidade: 1, tamanho: 'P', cor: 'sem-cor',
        precoUnitario: 10, precoTotal: 10, productId: 'safe',
      }],
    },
  }, owner);
  const sales = await base.collection('estoque_vendas').get();
  assert.equal(sales.size, 1);
});

test('11 stock operation once', async () => {
  const {base, lojaId} = await seed();
  await executeStockCommand(db, sale(lojaId, 't11'), owner);
  assert.equal((await base.collection('stock_catalog_operations').doc('t11').get()).exists, true);
  const ops = await base.collection('stock_catalog_operations').get();
  assert.equal(ops.size, 1);
});

test('12 revision advances correctly', async () => {
  const {base, lojaId} = await seed({stockRevision: 7});
  await executeStockCommand(db, sale(lojaId, 't12'), owner);
  assert.equal((await base.collection('estoque_produtos').doc('safe').get()).data().stockRevision, 8);
});

test('13 failed transaction zero partial write', async () => {
  const {base, lojaId} = await seed({quantidade: 0, variacoes: {P: {'sem-cor': 0}}, estoquePorTamanho: {P: 0}, stockRevision: 4});
  await denied(executeStockCommand(db, sale(lojaId, 't13'), owner), 'failed-precondition');
  assert.equal((await base.collection('stock_catalog_operations').doc('t13').get()).exists, false);
  assert.equal((await base.collection('estoque_produtos').doc('safe').get()).data().stockRevision, 4);
});

test('14 stale conflict deterministic failure', async () => {
  const {base, lojaId} = await seed({tombstone: {p: true}});
  await denied(executeStockCommand(db, sale(lojaId, 't14'), owner),
    'failed-precondition', 'Product tombstone requires reconciliation');
  assert.equal((await base.collection('estoque_produtos').doc('safe').get()).data().quantidade, 2);
});

test('15 blocked safety marker denied', async () => {
  const {base, lojaId} = await seed({stock: {variationSaleBlocked: true}});
  await denied(executeStockCommand(db, sale(lojaId, 't15'), owner),
    'permission-denied', VARIATION_PRODUCT_STATE_UNSAFE);
  assert.equal((await base.collection('estoque_produtos').doc('safe').get()).data().quantidade, 2);
});

test('16 wrong store denied', async () => {
  const {lojaId} = await seed({ownerUid: 'other-owner'});
  await denied(executeStockCommand(db, sale(lojaId, 't16'), owner),
    'permission-denied', 'Stock operation not authorized for this store');
});

test('17 cross-store isolation', async () => {
  const a = await seed({lojaId: `svr_${runId}_isoA`, productId: 'shared-name'});
  const b = await seed({lojaId: `svr_${runId}_isoB`, productId: 'shared-name', ownerUid: 'owner'});
  await executeStockCommand(db, sale(a.lojaId, 't17', {productId: 'shared-name'}), owner);
  assert.equal((await a.base.collection('estoque_produtos').doc('shared-name').get()).data().quantidade, 1);
  assert.equal((await b.base.collection('estoque_produtos').doc('shared-name').get()).data().quantidade, 2);
});

test('18 simple sale regression GREEN', async () => {
  const {base, lojaId} = await seed({
    simpleProductId: 'plain', stockKind: 'variation',
  });
  await executeStockCommand(db, {
    protocolVersion: 1, lojaId, kind: 'sale', operationId: 't18',
    items: [{productId: 'plain', quantity: 1}],
  }, owner);
  assert.equal((await base.collection('estoque_produtos').doc('plain').get()).data().quantidade, 2);
  assert.equal((await base.collection('estoque_produtos').doc('safe').get()).data().quantidade, 2);
});

test('19 current mirjoias 3 safe products allowed without grant', async () => {
  const fixtures = [
    {
      productId: PRODUCT2, size: '22', color: 'ESMERALDA',
      stock: {
        quantidade: 2, stockKind: 'variation', stockRevision: 4,
        variacoes: {22: {ESMERALDA: 1, 'LILÁS': 1}}, estoquePorTamanho: {22: 2},
      },
    },
    {
      productId: PRODUCT3, size: '15', color: 'sem-cor',
      stock: {
        quantidade: 2, stockKind: 'variation', stockRevision: 6,
        variacoes: {15: {'sem-cor': 1}, 18: {'sem-cor': 1}}, estoquePorTamanho: {15: 1, 18: 1},
      },
    },
    {
      productId: PRODUCT4, size: 'RUBI', color: 'sem-cor',
      stock: {
        quantidade: 2, stockKind: 'variation', stockRevision: 3,
        variacoes: {RUBI: {'sem-cor': 1}, TURQUESA: {'sem-cor': 1}},
        estoquePorTamanho: {RUBI: 1, TURQUESA: 1},
      },
    },
  ];
  for (const fx of fixtures) {
    const {base, lojaId} = await seed({productId: fx.productId, stock: fx.stock, grant: false});
    await executeStockCommand(db, sale(lojaId, `t19-${fx.productId}`, {
      productId: fx.productId, size: fx.size, color: fx.color,
    }), owner);
    assert.equal((await base.collection('estoque_produtos').doc(fx.productId).get()).data().quantidade, 1);
  }
});

test('20 current mirjoias Product 1 canonical sale independently eligible; missing variation denied', async () => {
  const stock = {
    quantidade: 3, stockKind: 'variation', stockRevision: 3,
    variacoes: {P: {'sem-cor': 1}, M: {'sem-cor': 1}, G: {'sem-cor': 1}},
    estoquePorTamanho: {P: 1, M: 1, G: 1},
  };
  const allowed = await seed({productId: PRODUCT1, stock, grant: false});
  await executeStockCommand(db, sale(allowed.lojaId, 't20-m', {
    productId: PRODUCT1, size: 'M', color: 'sem-cor',
  }), owner);
  assert.equal((await allowed.base.collection('estoque_produtos').doc(PRODUCT1).get()).data().variacoes.M['sem-cor'], 0);

  const missing = await seed({productId: PRODUCT1, stock, grant: false});
  await denied(executeStockCommand(db, sale(missing.lojaId, 't20-x', {
    productId: PRODUCT1, size: 'XG', color: 'sem-cor',
  }), owner), 'failed-precondition', 'Variation not found');

  const historical = await seed({
    productId: PRODUCT1,
    stock: {
      quantidade: 0, stockKind: 'variation', stockRevision: 2,
      variacoes: {M: {'sem-cor': 0}}, estoquePorTamanho: {M: 0},
    },
  });
  await denied(executeStockCommand(db, sale(historical.lojaId, 't20-hist-p', {
    productId: PRODUCT1, size: 'P', color: 'sem-cor',
  }), owner), 'failed-precondition', 'Variation not found');
});

test('21 current mirjoias historical blocked cases remain denied where unsafe', async () => {
  const blocked = ['hive-126', 'hive-132', 'hive-133', 'hive-154', 'hive-172', 'hive-175', 'hive-194', 'hive-227', 'hive-231'];
  const {lojaId} = await seed();
  for (const id of blocked) {
    await denied(executeStockCommand(db, sale(lojaId, `t21-${id}`, {productId: id, size: 'M'}), owner),
      'failed-precondition');
  }
  const eptConflict = await seed({
    stock: {
      quantidade: 2, variacoes: {P: {'sem-cor': 2}}, estoquePorTamanho: {P: 2, G: 1},
    },
  });
  await denied(executeStockCommand(db, sale(eptConflict.lojaId, 't21-ept'), owner),
    'permission-denied', VARIATION_PRODUCT_STATE_UNSAFE);
});

test('22 grade remains denied', async () => {
  const {base, lojaId} = await seed({
    variacoes: {P: {Azul: {A: 2}}},
    estoquePorTamanho: {P: 2},
    quantidade: 2,
  });
  await denied(executeStockCommand(db, sale(lojaId, 't22', {color: 'Azul', extra: 'A'}), owner),
    'permission-denied', GRADE_SALE_NOT_AUTHORIZED);
  assert.equal((await base.collection('estoque_produtos').doc('safe').get()).data().quantidade, 2);
});

test('23 replace auth unchanged', async () => {
  const {base, lojaId} = await seed({grant: false, stockRevision: 1});
  await executeStockCommand(db, {
    protocolVersion: 1, lojaId, kind: 'replace', operationId: 't23',
    items: [{productId: 'safe', expectedRevision: 1}],
    editorial: {},
    definition: {quantidade: 2, variacoes: {P: {'sem-cor': 2}}, estoquePorTamanho: {P: 2}},
  }, owner);
  assert.equal((await base.collection('estoque_produtos').doc('safe').get()).data().variacoes.P['sem-cor'], 2);
});

test('24 restock auth unchanged', async () => {
  const {lojaId} = await seed({stockKind: 'simple', quantidade: 1, variacoes: undefined, estoquePorTamanho: {}});
  await denied(executeStockCommand(db, {
    protocolVersion: 1, lojaId, kind: 'restock', operationId: 't24',
    items: [{productId: 'safe', quantity: 1}],
  }, owner), 'failed-precondition');
});

test('25 reconcile auth unchanged', async () => {
  const {lojaId} = await seed({grant: true, stockRevision: 1});
  await denied(executeStockCommand(db, {
    protocolVersion: 1, lojaId, kind: 'reconcile', operationId: 't25', reconciliationId: 't25',
    countedAt: '2026-09-19T12:00:00.000Z',
    items: [{productId: 'safe', expectedRevision: 1, confirmedPhysicalQty: 1, size: 'P', color: 'sem-cor'}],
  }, owner), 'failed-precondition', 'RECONCILIATION_GRANT_REQUIRED');
});

test('26 queue replay unchanged', async () => {
  const {base, lojaId} = await seed();
  await executeStockCommand(db, sale(lojaId, 't26'), owner);
  const again = await executeStockCommand(db, sale(lojaId, 't26'), owner);
  assert.equal(again.alreadyApplied, true);
  assert.equal((await base.collection('estoque_produtos').doc('safe').get()).data().variacoes.P['sem-cor'], 1);
});

test('27 no variation synthesis', async () => {
  const {base, lojaId} = await seed({
    quantidade: 1, variacoes: {M: {'sem-cor': 1}}, estoquePorTamanho: {M: 1},
  });
  const before = (await base.collection('estoque_produtos').doc('safe').get()).data();
  await denied(executeStockCommand(db, sale(lojaId, 't27', {size: 'P'}), owner),
    'failed-precondition', 'Variation not found');
  const after = (await base.collection('estoque_produtos').doc('safe').get()).data();
  assert.deepEqual(Object.keys(after.variacoes), Object.keys(before.variacoes));
  assert.equal(after.variacoes.P, undefined);
  assert.equal(after.quantidade, 1);
});

test('28 no global wildcard', async () => {
  const {base, lojaId} = await seed({
    stock: {variationSaleBlocked: true},
  });
  await base.collection(VARIATION_SALE_PRODUCT_GRANTS_COLLECTION).doc('*').set({enabled: true});
  await denied(executeStockCommand(db, sale(lojaId, 't28'), owner),
    'permission-denied', VARIATION_PRODUCT_STATE_UNSAFE);
  assert.doesNotMatch(accessSrc(), /mirjoias/);
  assert.doesNotMatch(commandsSrc(), /mirjoias/);
  assert.match(commandsSrc(), /evaluateSafeVariationSaleEligibility/);
  assert.doesNotMatch(commandsSrc(), /VARIATION_SALE_PRODUCT_GRANTS_COLLECTION/);
});

test('29 no client-supplied safety bypass', async () => {
  const {lojaId} = await seed({stock: {variationSaleBlocked: true}});
  await denied(executeStockCommand(db, sale(lojaId, 't29', {
    extraCommand: {forceVariationSale: true},
  }), owner), 'invalid-argument');
  await denied(executeStockCommand(db, {
    protocolVersion: 1, lojaId, kind: 'sale', operationId: 't29b',
    items: [{productId: 'safe', quantity: 1, size: 'P', color: 'sem-cor', eligible: true}],
  }, owner), 'invalid-argument');
  assert.equal(
    evaluateSafeVariationSaleEligibility(
      {stockKind: 'variation', quantidade: 2, variacoes: {P: {'sem-cor': 2}}, variationSaleBlocked: true},
      {productId: 'safe', quantity: 1, size: 'P', color: 'sem-cor'},
    ),
    VARIATION_PRODUCT_STATE_UNSAFE,
  );
});

test('30 existing product-scoped grant compatibility', async () => {
  const {base, lojaId} = await seed({grant: true, productId: PRODUCT2, stock: {
    quantidade: 2, stockKind: 'variation', stockRevision: 4,
    variacoes: {22: {ESMERALDA: 1, 'LILÁS': 1}}, estoquePorTamanho: {22: 2},
  }});
  await executeStockCommand(db, sale(lojaId, 't30', {
    productId: PRODUCT2, size: '22', color: 'ESMERALDA',
  }), owner);
  assert.equal((await base.collection(VARIATION_SALE_PRODUCT_GRANTS_COLLECTION).doc(PRODUCT2).get()).data().enabled, true);
  assert.equal((await base.collection('estoque_produtos').doc(PRODUCT2).get()).data().quantidade, 1);
  const blockedWithGrant = await seed({
    grant: true,
    stock: {variationSaleBlocked: true, quantidade: 2, variacoes: {P: {'sem-cor': 2}}, estoquePorTamanho: {P: 2}},
  });
  await denied(executeStockCommand(db, sale(blockedWithGrant.lojaId, 't30-block'), owner),
    'permission-denied', VARIATION_PRODUCT_STATE_UNSAFE);
  assert.equal(stranger.uid, 'stranger');
  assert.equal(VARIATION_STOCK_INVALID, 'VARIATION_STOCK_INVALID');
});
