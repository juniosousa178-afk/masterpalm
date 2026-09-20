import test from 'node:test';
import assert from 'node:assert/strict';
import {executeConsignmentCommand} from '../src/consignmentCommand.js';
import {executeStockCommand, publishStockProduct} from '../src/stockCatalogCommands.js';
import {CODES} from '../src/consignmentProtocol.js';
import {classifyConsignmentProduct} from '../src/consignmentStock.js';
import {createConsignmentTestDb} from './consignment-test-db.mjs';

const owner = {uid: 'owner'};
let seq = 0;

function denied(promise, code) {
  return assert.rejects(promise, e => e.consignmentCode === code || e.code === code);
}

async function seed({
  moduleEnabled = true,
  simpleQty = 5,
  variation = null,
  extraProducts = [],
  grant = true,
  protocol = true,
  protocolMode = 'active',
} = {}) {
  const db = createConsignmentTestDb();
  const lojaId = `csgn_${Date.now().toString(36)}_${++seq}`;
  const base = db.collection('lojas').doc(lojaId);
  db.seed(base, {ownerUid: 'owner', lojaId, nome: 'Master'});
  if (protocol) {
    db.seed(base.collection('stock_catalog_control').doc('state'), {
      protocolVersion: 1, mode: protocolMode, migrationComplete: protocolMode === 'active',
    });
  }
  if (grant) {
    db.seed(base.collection('stock_catalog_access').doc('owner'), {
      enabled: true,
      permissions: {sale: true, restock: true, adjust: true, restore: true, editorial: true, publish: true, create: true, delete: true, undo: true},
    });
  }
  db.seed(base.collection('consignment_control').doc('state'), {
    protocolVersion: 1, moduleEnabled,
  });
  db.seed(base.collection('estoque_produtos').doc('simple'), {
    quantidade: simpleQty, stockKind: 'simple', stockRevision: 0, variacoes: {},
  });
  db.seed(base.collection('draft_produtos').doc('simple'), {nome: 'Anel', publicadoNoCatalogo: true, preco: 100});
  db.seed(base.collection('stock_catalog_dependencies').doc('simple'), {comboIds: []});
  if (variation) {
    db.seed(base.collection('estoque_produtos').doc('varp'), {
      stockKind: 'variation', stockRevision: 0, quantidade: 0, ...variation,
    });
    db.seed(base.collection('draft_produtos').doc('varp'), {nome: 'Pulseira', publicadoNoCatalogo: true, preco: 80});
    db.seed(base.collection('stock_catalog_dependencies').doc('varp'), {comboIds: []});
  }
  for (const p of extraProducts) {
    db.seed(base.collection('estoque_produtos').doc(p.id), p.stock);
    db.seed(base.collection('draft_produtos').doc(p.id), p.draft || {nome: p.id, publicadoNoCatalogo: true});
    if (p.dependency !== false) {
      db.seed(
        base.collection('stock_catalog_dependencies').doc(p.id),
        p.dependency || {comboIds: p.comboIds || []},
      );
    }
  }
  db.seed(base.collection('consignment_resellers').doc('rev1'), {
    storeId: lojaId, resellerId: 'rev1', displayName: 'Maria', active: true, notes: '',
  });
  return {db, base, lojaId};
}

function cmd(lojaId, operation, operationId, payload = {}, consignmentId = null) {
  return {
    protocolVersion: 1, lojaId, operation, operationId,
    ...(consignmentId ? {consignmentId} : {}),
    payload,
  };
}

function simpleLine(qty = 2, price = 50) {
  return {
    productId: 'simple', qtySent: qty, unitSalePrice: price,
    commissionType: 'PERCENTUAL', commissionValue: 10,
  };
}

async function draftAnd(db, lojaId, lines, extras = {}) {
  const consignmentId = extras.consignmentId || `c_${++seq}`;
  await executeConsignmentCommand(db, cmd(lojaId, 'createDraft', `op_draft_${consignmentId}`, {
    resellerId: extras.resellerId || 'rev1',
    notes: extras.notes || '',
    lines,
  }, consignmentId), owner);
  return consignmentId;
}

function stockQty(db, base, id = 'simple') {
  return db.getData(base.collection('estoque_produtos').doc(id))?.quantidade;
}
function stockRev(db, base, id = 'simple') {
  return db.getData(base.collection('estoque_produtos').doc(id))?.stockRevision;
}
function consignment(db, base, id) {
  return db.getData(base.collection('consignments').doc(id));
}
function saleExists(db, base, consignmentId) {
  return db.exists(base.collection('estoque_vendas').doc(`csgn_${consignmentId}`));
}
function financeExists(db, base, consignmentId) {
  return db.exists(base.collection('lancamentos_financeiros').doc(`csgn_fin_${consignmentId}`));
}

test('classify: simple / size-only variation / grade denied', () => {
  assert.equal(classifyConsignmentProduct({stockKind: 'simple', quantidade: 3, variacoes: {}}).kind, 'simple');
  assert.equal(classifyConsignmentProduct({
    stockKind: 'variation', variacoes: {P: {'sem-cor': 4}, M: {'sem-cor': 1}}, quantidade: 5,
  }).kind, 'variation');
  assert.throws(() => classifyConsignmentProduct({
    stockKind: 'variation', variacoes: {P: {Azul: 1, Vermelho: 2}}, tamanhos: ['P'], cores: ['Azul', 'Vermelho'], quantidade: 3,
  }), e => e.consignmentCode === CODES.CONSIGNMENT_GRADE_NOT_SUPPORTED);
  assert.throws(() => classifyConsignmentProduct({
    stockKind: 'combo', tipoProduto: 'combo', itensCombo: [{productId: 'x', quantidade: 1}], quantidade: 1,
  }), e => e.consignmentCode === CODES.PRODUCT_STATE_UNSAFE);
});

test('1 simple issue success: stock down, no sale, no finance', async () => {
  const {db, base, lojaId} = await seed();
  const id = await draftAnd(db, lojaId, [simpleLine(2)]);
  const before = db.snapshot();
  await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
  assert.equal(stockQty(db, base), 3);
  assert.equal(stockRev(db, base), 1);
  assert.equal(consignment(db, base, id).status, 'ISSUED');
  assert.equal(saleExists(db, base, id), false);
  assert.equal(financeExists(db, base, id), false);
  assert.equal(db.exists(base.collection('contas_receber').doc(`csgn_${id}`)), false);
  assert.ok(db.exists(base.collection('consignment_audit').doc(`issue_${id}`)));
  assert.notEqual(before.get(base.collection('estoque_produtos').doc('simple').path).quantidade, 3);
});

test('2 variation issue success uses canonical variacoes and regenerates EPT', async () => {
  const {db, base, lojaId} = await seed({
    variation: {variacoes: {P: {'sem-cor': 5}, M: {'sem-cor': 3}}},
  });
  const id = await draftAnd(db, lojaId, [{
    productId: 'varp', qtySent: 2, unitSalePrice: 40, commissionType: 'SEM_COMISSAO', commissionValue: 0,
    variationKey: {size: 'P', color: 'sem-cor', extra: ''},
  }]);
  await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
  const stock = db.getData(base.collection('estoque_produtos').doc('varp'));
  assert.equal(stock.variacoes.P['sem-cor'], 3);
  assert.equal(stock.variacoes.M['sem-cor'], 3);
  assert.equal(stock.estoquePorTamanho.P, 3);
  assert.equal(stock.quantidade, 6);
  assert.equal(stock.stockRevision, 1);
  assert.equal(saleExists(db, base, id), false);
});

test('3 insufficient stock -> zero writes', async () => {
  const {db, base, lojaId} = await seed({simpleQty: 1});
  const id = await draftAnd(db, lojaId, [simpleLine(2)]);
  const before = db.snapshot();
  await denied(executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner), CODES.INSUFFICIENT_STOCK);
  assert.deepEqual(db.snapshot(), before);
  assert.equal(consignment(db, base, id).status, 'DRAFT');
});

test('4 variation missing -> zero writes', async () => {
  const {db, base, lojaId} = await seed({
    variation: {variacoes: {P: {'sem-cor': 5}}},
  });
  const id = await draftAnd(db, lojaId, [{
    productId: 'varp', qtySent: 1, unitSalePrice: 10, commissionType: 'SEM_COMISSAO', commissionValue: 0,
    variationKey: {size: 'G', color: 'sem-cor', extra: ''},
  }]);
  const before = db.snapshot();
  await denied(executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner), CODES.VARIATION_NOT_FOUND);
  assert.deepEqual(db.snapshot(), before);
});

test('5 unsafe product -> zero writes', async () => {
  const {db, base, lojaId} = await seed();
  const id = await draftAnd(db, lojaId, [simpleLine(1)]);
  db.seed(base.collection('exclusao_produto').doc('simple'), {p: true});
  const before = db.snapshot();
  await denied(executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner), CODES.PRODUCT_STATE_UNSAFE);
  assert.deepEqual(db.snapshot(), before);
});

test('6 grade -> denied', async () => {
  const {db, base, lojaId} = await seed({
    extraProducts: [{
      id: 'grade',
      stock: {
        stockKind: 'variation', stockRevision: 0, quantidade: 3,
        variacoes: {P: {Azul: 1, Vermelho: 2}}, tamanhos: ['P'], cores: ['Azul', 'Vermelho'],
      },
    }],
  });
  await denied(draftAnd(db, lojaId, [{
    productId: 'grade', qtySent: 1, unitSalePrice: 10, commissionType: 'SEM_COMISSAO', commissionValue: 0,
    variationKey: {size: 'P', color: 'Azul', extra: ''},
  }]), CODES.CONSIGNMENT_GRADE_NOT_SUPPORTED);
  assert.equal(stockQty(db, base, 'grade'), 3);
});

test('7 multiple product issue atomic', async () => {
  const {db, base, lojaId} = await seed({
    variation: {variacoes: {P: {'sem-cor': 4}}},
  });
  const id = await draftAnd(db, lojaId, [
    simpleLine(2),
    {
      productId: 'varp', qtySent: 1, unitSalePrice: 20, commissionType: 'SEM_COMISSAO', commissionValue: 0,
      variationKey: {size: 'P', color: 'sem-cor', extra: ''},
    },
  ]);
  await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
  assert.equal(stockQty(db, base, 'simple'), 3);
  assert.equal(db.getData(base.collection('estoque_produtos').doc('varp')).variacoes.P['sem-cor'], 3);
});

test('8 one invalid line -> whole issue rollback', async () => {
  const {db, base, lojaId} = await seed({simpleQty: 5, variation: {variacoes: {P: {'sem-cor': 1}}}});
  const id = await draftAnd(db, lojaId, [
    simpleLine(2),
    {
      productId: 'varp', qtySent: 5, unitSalePrice: 20, commissionType: 'SEM_COMISSAO', commissionValue: 0,
      variationKey: {size: 'P', color: 'sem-cor', extra: ''},
    },
  ]);
  const before = db.snapshot();
  await denied(executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner), CODES.INSUFFICIENT_STOCK);
  assert.equal(stockQty(db, base, 'simple'), 5);
  assert.equal(consignment(db, base, id).status, 'DRAFT');
  assert.deepEqual(
    db.getData(base.collection('estoque_produtos').doc('simple')),
    before.get(base.collection('estoque_produtos').doc('simple').path),
  );
});

test('9-12 stockRevision advances, EPT regenerate, no sale, no finance on issue', async () => {
  const {db, base, lojaId} = await seed({
    variation: {variacoes: {P: {'sem-cor': 8}}},
  });
  const id = await draftAnd(db, lojaId, [{
    productId: 'varp', qtySent: 3, unitSalePrice: 10, commissionType: 'VALOR_FIXO_POR_UNIDADE', commissionValue: 2,
    variationKey: {size: 'P', color: 'sem-cor', extra: ''},
  }]);
  assert.equal(stockRev(db, base, 'varp'), 0);
  await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
  const stock = db.getData(base.collection('estoque_produtos').doc('varp'));
  assert.equal(stock.stockRevision, 1);
  assert.equal(stock.estoquePorTamanho.P, 5);
  assert.equal(saleExists(db, base, id), false);
  assert.equal(financeExists(db, base, id), false);
});

test('13 retry same issue operation is idempotent', async () => {
  const {db, base, lojaId} = await seed();
  const id = await draftAnd(db, lojaId, [simpleLine(2)]);
  const first = await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
  const second = await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
  assert.equal(first.alreadyApplied, false);
  assert.equal(second.alreadyApplied, true);
  assert.equal(stockQty(db, base), 3);
});

test('14 conflicting retry denied', async () => {
  const {db, lojaId} = await seed();
  const id = await draftAnd(db, lojaId, [simpleLine(2)]);
  await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
  await denied(executeConsignmentCommand(db, cmd(lojaId, 'settle', `issue_${id}`, {
    lines: [{productId: 'simple', qtySold: 2, qtyReturned: 0}],
  }, id), owner), CODES.IDEMPOTENCY_CONFLICT);
});

test('15 cross-store denied', async () => {
  const {db, lojaId} = await seed();
  const otherId = `other_${++seq}`;
  const other = db.collection('lojas').doc(otherId);
  db.seed(other.collection('stock_catalog_control').doc('state'), {
    protocolVersion: 1, mode: 'active', migrationComplete: true,
  });
  db.seed(other.collection('consignment_control').doc('state'), {protocolVersion: 1, moduleEnabled: true});
  await denied(executeConsignmentCommand(db, cmd(otherId, 'createReseller', 'x', {
    resellerId: 'intruder', displayName: 'X',
  }), owner), CODES.RESELLER_PERMISSION);
  await denied(executeConsignmentCommand(db, cmd(lojaId, 'createReseller', 'y', {
    resellerId: 'rev_other', displayName: 'Y',
  }, null), {uid: 'intruder'}), CODES.RESELLER_PERMISSION);
});

test('16-24 settlement 100% sold / returned / mixed + freeze + sale/finance once', async () => {
  const {db, base, lojaId} = await seed({simpleQty: 10});
  const soldId = await draftAnd(db, lojaId, [simpleLine(3, 50)]);
  await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${soldId}`, {}, soldId), owner);
  assert.equal(stockQty(db, base), 7);
  const sold = await executeConsignmentCommand(db, cmd(lojaId, 'settle', `settle_${soldId}`, {
    lines: [{productId: 'simple', qtySold: 3, qtyReturned: 0}],
  }, soldId), owner);
  assert.equal(stockQty(db, base), 7);
  assert.equal(sold.saleCreated, true);
  assert.equal(sold.financeCreated, true);
  assert.equal(sold.grossSoldAmount, 150);
  assert.equal(sold.commissionAmount, 15);
  assert.equal(sold.netAmount, 135);
  const sale = db.getData(base.collection('estoque_vendas').doc(`csgn_${soldId}`));
  assert.equal(sale.origemVenda, 'consignment');
  assert.equal(sale.stockAlreadyReservedByConsignment, true);
  assert.equal(sale.total, 150);

  const retId = await draftAnd(db, lojaId, [simpleLine(2, 40)], {consignmentId: `ret_${seq}`});
  await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${retId}`, {}, retId), owner);
  const afterIssue = stockQty(db, base);
  await executeConsignmentCommand(db, cmd(lojaId, 'settle', `settle_${retId}`, {
    lines: [{productId: 'simple', qtySold: 0, qtyReturned: 2}],
  }, retId), owner);
  assert.equal(stockQty(db, base), afterIssue + 2);
  assert.equal(saleExists(db, base, retId), false);
  assert.equal(financeExists(db, base, retId), false);

  const mixId = await draftAnd(db, lojaId, [simpleLine(3, 100)], {consignmentId: `mix_${seq}`});
  await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${mixId}`, {}, mixId), owner);
  const beforeMixSettle = stockQty(db, base);
  const mix = await executeConsignmentCommand(db, cmd(lojaId, 'settle', `settle_${mixId}`, {
    lines: [{productId: 'simple', qtySold: 2, qtyReturned: 1}],
  }, mixId), owner);
  assert.equal(stockQty(db, base), beforeMixSettle + 1);
  assert.equal(mix.totalItemsSold, 2);
  assert.equal(mix.totalItemsReturned, 1);
  assert.equal(mix.grossSoldAmount, 200);
  assert.equal(mix.commissionAmount, 20);
  const frozen = consignment(db, base, mixId).lines[0];
  assert.equal(frozen.unitSalePriceSnapshot, 100);
  assert.equal(frozen.commissionValueSnapshot, 10);
});

test('25 invalid sold+returned -> zero writes', async () => {
  const {db, base, lojaId} = await seed();
  const id = await draftAnd(db, lojaId, [simpleLine(2)]);
  await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
  const before = db.snapshot();
  await denied(executeConsignmentCommand(db, cmd(lojaId, 'settle', `settle_${id}`, {
    lines: [{productId: 'simple', qtySold: 2, qtyReturned: 1}],
  }, id), owner), CODES.INVALID_SETTLEMENT_TOTAL);
  assert.equal(consignment(db, base, id).status, 'ISSUED');
  assert.equal(saleExists(db, base, id), false);
  assert.equal(db.snapshot().get(base.collection('estoque_produtos').doc('simple').path).quantidade,
    before.get(base.collection('estoque_produtos').doc('simple').path).quantidade);
});

test('26-28 settlement retry idempotent, conflict denied, already settled denied', async () => {
  const {db, base, lojaId} = await seed();
  const id = await draftAnd(db, lojaId, [simpleLine(2)]);
  await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
  const first = await executeConsignmentCommand(db, cmd(lojaId, 'settle', `settle_${id}`, {
    lines: [{productId: 'simple', qtySold: 2, qtyReturned: 0}],
  }, id), owner);
  const second = await executeConsignmentCommand(db, cmd(lojaId, 'settle', `settle_${id}`, {
    lines: [{productId: 'simple', qtySold: 2, qtyReturned: 0}],
  }, id), owner);
  assert.equal(first.alreadyApplied, false);
  assert.equal(second.alreadyApplied, true);
  assert.equal(saleExists(db, base, id), true);
  await denied(executeConsignmentCommand(db, cmd(lojaId, 'settle', `settle_${id}_b`, {
    lines: [{productId: 'simple', qtySold: 1, qtyReturned: 1}],
  }, id), owner), CODES.CONSIGNMENT_ALREADY_SETTLED);
  await denied(executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_other`, {
  }, id), owner), CODES.CONSIGNMENT_ALREADY_SETTLED);
});

test('29-30 stockRevision on returns and aggregate/EPT convergence', async () => {
  const {db, base, lojaId} = await seed({
    variation: {variacoes: {P: {'sem-cor': 6}}},
  });
  const id = await draftAnd(db, lojaId, [{
    productId: 'varp', qtySent: 4, unitSalePrice: 10, commissionType: 'SEM_COMISSAO', commissionValue: 0,
    variationKey: {size: 'P', color: 'sem-cor', extra: ''},
  }]);
  await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
  const afterIssue = db.getData(base.collection('estoque_produtos').doc('varp'));
  assert.equal(afterIssue.variacoes.P['sem-cor'], 2);
  assert.equal(afterIssue.estoquePorTamanho.P, 2);
  assert.equal(afterIssue.stockRevision, 1);
  await executeConsignmentCommand(db, cmd(lojaId, 'settle', `settle_${id}`, {
    lines: [{productId: 'varp', variationKey: {size: 'P', color: 'sem-cor', extra: ''}, qtySold: 1, qtyReturned: 3}],
  }, id), owner);
  const after = db.getData(base.collection('estoque_produtos').doc('varp'));
  assert.equal(after.variacoes.P['sem-cor'], 5);
  assert.equal(after.estoquePorTamanho.P, 5);
  assert.equal(after.quantidade, 5);
  assert.equal(after.stockRevision, 2);
});

test('31-33 normal simple/variation sale unaffected by consignment module', async () => {
  const {db, base, lojaId} = await seed({
    variation: {variacoes: {P: {'sem-cor': 4}}},
  });
  await executeStockCommand(db, {
    protocolVersion: 1, lojaId, kind: 'sale', operationId: 'pdv_simple',
    items: [{productId: 'simple', quantity: 1}],
  }, owner);
  assert.equal(stockQty(db, base, 'simple'), 4);
  await executeStockCommand(db, {
    protocolVersion: 1, lojaId, kind: 'sale', operationId: 'pdv_var',
    items: [{productId: 'varp', quantity: 1, size: 'P', color: 'sem-cor'}],
  }, owner);
  assert.equal(db.getData(base.collection('estoque_produtos').doc('varp')).variacoes.P['sem-cor'], 3);
  assert.equal(db.exists(base.collection('variation_sale_product_grants').doc('varp')), false);
});

test('34 saved-sale removal/restock unaffected', async () => {
  const {db, base, lojaId} = await seed();
  await executeStockCommand(db, {
    protocolVersion: 1, lojaId, kind: 'sale', operationId: 'pdv_sale',
    items: [{productId: 'simple', quantity: 1}],
  }, owner);
  await executeStockCommand(db, {
    protocolVersion: 1, lojaId, kind: 'restore', operationId: 'pdv_restore',
    sourceOperationId: 'pdv_sale', items: [{productId: 'simple', quantity: 1}],
  }, owner);
  assert.equal(stockQty(db, base), 5);
});

test('35-37 stockCatalogCommand, catalog publish and finance of normal sale unaffected', async () => {
  const {db, base, lojaId} = await seed();
  await publishStockProduct(db, lojaId, 'simple', owner);
  assert.equal(db.getData(base.collection('produtos').doc('simple')).quantidade, 5);
  await executeStockCommand(db, {
    protocolVersion: 1, lojaId, kind: 'sale', operationId: 'pdv_pub',
    items: [{productId: 'simple', quantity: 1}],
  }, owner);
  assert.equal(db.exists(base.collection('produtos').doc('simple')), true);
  db.seed(base.collection('lancamentos_financeiros').doc('manual_pdv'), {
    lojaId, origem: 'manual', valor: 10, tipo: 'entrada_extra',
  });
  const id = await draftAnd(db, lojaId, [simpleLine(1)]);
  await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
  assert.equal(db.getData(base.collection('lancamentos_financeiros').doc('manual_pdv')).valor, 10);
  assert.equal(financeExists(db, base, id), false);
});

test('38 customer accounts receivable unaffected', async () => {
  const {db, base, lojaId} = await seed();
  const id = await draftAnd(db, lojaId, [simpleLine(1)]);
  await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
  await executeConsignmentCommand(db, cmd(lojaId, 'settle', `settle_${id}`, {
    lines: [{productId: 'simple', qtySold: 1, qtyReturned: 0}],
  }, id), owner);
  const cr = [...db._store.keys()].filter(k => k.includes('/contas_receber/'));
  assert.equal(cr.length, 0);
});

test('39 no queue replay documents', async () => {
  const {db, lojaId} = await seed();
  const id = await draftAnd(db, lojaId, [simpleLine(1)]);
  await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
  const queue = [...db._store.keys()].filter(k => /sync_queue|offline_queue|hive/i.test(k));
  assert.equal(queue.length, 0);
});

test('40 grade restriction unchanged: stock sale of size×color still uses catalog command, consignment denies', async () => {
  const {db, base, lojaId} = await seed({
    extraProducts: [{
      id: 'grade',
      stock: {
        stockKind: 'variation', stockRevision: 0, quantidade: 2,
        variacoes: {P: {Azul: 2}}, tamanhos: ['P'], cores: ['Azul'],
      },
    }],
  });
  await executeStockCommand(db, {
    protocolVersion: 1, lojaId, kind: 'sale', operationId: 'grade_pdv',
    items: [{productId: 'grade', quantity: 1, size: 'P', color: 'Azul'}],
  }, owner);
  assert.equal(db.getData(base.collection('estoque_produtos').doc('grade')).variacoes.P.Azul, 1);
  await denied(draftAnd(db, lojaId, [{
    productId: 'grade', qtySent: 1, unitSalePrice: 10, commissionType: 'SEM_COMISSAO', commissionValue: 0,
    variationKey: {size: 'P', color: 'Azul', extra: ''},
  }]), CODES.CONSIGNMENT_GRADE_NOT_SUPPORTED);
});

test('draft cancel has no stock effect; issued cannot cancel', async () => {
  const {db, base, lojaId} = await seed();
  const draftId = await draftAnd(db, lojaId, [simpleLine(1)]);
  await executeConsignmentCommand(db, cmd(lojaId, 'cancelDraft', `cancel_${draftId}`, {}, draftId), owner);
  assert.equal(consignment(db, base, draftId).status, 'CANCELLED');
  assert.equal(stockQty(db, base), 5);
  const issuedId = await draftAnd(db, lojaId, [simpleLine(1)], {consignmentId: `iss_${seq}`});
  await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${issuedId}`, {}, issuedId), owner);
  await denied(executeConsignmentCommand(db, cmd(lojaId, 'cancelDraft', `cancel_${issuedId}`, {}, issuedId), owner),
    CODES.CONSIGNMENT_ALREADY_ISSUED);
});

test('module flag default deny', async () => {
  const {db, lojaId} = await seed({moduleEnabled: false});
  await denied(executeConsignmentCommand(db, cmd(lojaId, 'createReseller', 'op', {
    resellerId: 'r2', displayName: 'X',
  }), owner), CODES.MODULE_DISABLED);
});

test('feature flag does not write stock_catalog_operations kind=sale on issue', async () => {
  const {db, base, lojaId} = await seed();
  const id = await draftAnd(db, lojaId, [simpleLine(1)]);
  await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
  const ops = [...db._store.keys()].filter(k => k.includes('/stock_catalog_operations/'));
  assert.equal(ops.length, 0);
});

test('createReseller empty name denied locally-equivalent', async () => {
  const {db, lojaId} = await seed();
  await denied(executeConsignmentCommand(db, cmd(lojaId, 'createReseller', 'op_empty', {
    resellerId: 'r_empty', displayName: '   ',
  }), owner), CODES.INVALID_ARGUMENT);
});

test('createReseller without stock protocol: scoped, no stock/sale/finance/consignment', async () => {
  const db = createConsignmentTestDb();
  const lojaId = `csgn_reseller_${++seq}`;
  const base = db.collection('lojas').doc(lojaId);
  db.seed(base, {ownerUid: 'owner', lojaId, nome: 'Master'});
  db.seed(base.collection('consignment_control').doc('state'), {
    protocolVersion: 1, moduleEnabled: true,
  });
  db.seed(base.collection('estoque_produtos').doc('simple'), {
    quantidade: 5, stockKind: 'simple', stockRevision: 0, variacoes: {},
  });
  const stockBefore = db.getData(base.collection('estoque_produtos').doc('simple'));
  const res = await executeConsignmentCommand(db, cmd(lojaId, 'createReseller', 'op_r1', {
    resellerId: 'rev_new', displayName: 'Revendedor Teste', phone: '11999999999', notes: 'n',
  }), owner);
  assert.equal(res.resellerId, 'rev_new');
  assert.equal(res.displayName, 'Revendedor Teste');
  const doc = db.getData(base.collection('consignment_resellers').doc('rev_new'));
  assert.equal(doc.storeId, lojaId);
  assert.equal(doc.active, true);
  assert.equal(doc.phone, '11999999999');
  assert.deepEqual(db.getData(base.collection('estoque_produtos').doc('simple')), stockBefore);
  assert.equal([...db._store.keys()].filter(k => k.includes('/consignments/')).length, 0);
  assert.equal(saleExists(db, base, 'rev_new'), false);
  assert.equal(financeExists(db, base, 'rev_new'), false);
  assert.equal([...db._store.keys()].filter(k => k.includes('/stock_catalog_operations/')).length, 0);
  assert.equal([...db._store.keys()].filter(k => k.includes('/estoque_vendas/')).length, 0);
  assert.equal([...db._store.keys()].filter(k => k.includes('/lancamentos_financeiros/')).length, 0);
});

test('createReseller succeeds without stock grant; issue of safe product also allowed', async () => {
  const {db, base, lojaId} = await seed({grant: false, protocol: false});
  const created = await executeConsignmentCommand(db, cmd(lojaId, 'createReseller', 'op_r2', {
    resellerId: 'rev_member', displayName: 'Joao',
  }), owner);
  assert.equal(created.resellerId, 'rev_member');
  const id = await draftAnd(db, lojaId, [simpleLine(1)], {resellerId: 'rev_member'});
  await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
  assert.equal(stockQty(db, base), 4);
  assert.equal(db.exists(base.collection('stock_catalog_control').doc('state')), false);
});

test('dedicated gate 1 module disabled -> issue denied', async () => {
  const {db, lojaId} = await seed({moduleEnabled: false, protocol: false, grant: false});
  await denied(executeConsignmentCommand(db, cmd(lojaId, 'issue', 'op_mod', {}, 'c_mod'), owner), CODES.MODULE_DISABLED);
});

test('dedicated gate 2 module enabled + safe simple -> allowed without protocol', async () => {
  const {db, base, lojaId} = await seed({protocol: false, grant: false});
  const id = await draftAnd(db, lojaId, [simpleLine(1)]);
  await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
  assert.equal(stockQty(db, base), 4);
});

test('dedicated gate 3 module enabled + safe variation -> allowed', async () => {
  const {db, base, lojaId} = await seed({
    protocol: false, grant: false,
    variation: {variacoes: {P: {'sem-cor': 4}}},
  });
  const id = await draftAnd(db, lojaId, [{
    productId: 'varp', qtySent: 1, unitSalePrice: 40, commissionType: 'SEM_COMISSAO', commissionValue: 0,
    variationKey: {size: 'P', color: 'sem-cor', extra: ''},
  }]);
  await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
  assert.equal(db.getData(base.collection('estoque_produtos').doc('varp')).variacoes.P['sem-cor'], 3);
});

test('dedicated gate 4 dependency missing -> denied', async () => {
  const {db, base, lojaId} = await seed({
    protocol: false, grant: false,
    extraProducts: [{
      id: 'nodep',
      stock: {quantidade: 3, stockKind: 'simple', stockRevision: 0, variacoes: {}},
      dependency: false,
    }],
  });
  const before = db.snapshot();
  await denied(draftAnd(db, lojaId, [{
    productId: 'nodep', qtySent: 1, unitSalePrice: 10, commissionType: 'SEM_COMISSAO', commissionValue: 0,
  }]), CODES.PRODUCT_STATE_UNSAFE);
  assert.deepEqual(db.snapshot(), before);
});

test('dedicated gate 5 dependency unsafe -> denied', async () => {
  const {db, lojaId} = await seed({
    protocol: false, grant: false,
    extraProducts: [{
      id: 'unsafedep',
      stock: {quantidade: 3, stockKind: 'simple', stockRevision: 0, variacoes: {}},
      dependency: {comboIds: 'legacy'},
    }],
  });
  await denied(draftAnd(db, lojaId, [{
    productId: 'unsafedep', qtySent: 1, unitSalePrice: 10, commissionType: 'SEM_COMISSAO', commissionValue: 0,
  }]), CODES.PRODUCT_STATE_UNSAFE);
});

test('dedicated gate 6 invalid stockRevision -> denied', async () => {
  const {db, lojaId} = await seed({
    protocol: false, grant: false,
    extraProducts: [{
      id: 'badrev',
      stock: {quantidade: 3, stockKind: 'simple', variacoes: {}},
    }],
  });
  await denied(draftAnd(db, lojaId, [{
    productId: 'badrev', qtySent: 1, unitSalePrice: 10, commissionType: 'SEM_COMISSAO', commissionValue: 0,
  }]), CODES.PRODUCT_STATE_UNSAFE);
});

test('dedicated gate 7 ambiguous stock -> denied', async () => {
  const {db, lojaId} = await seed({
    protocol: false, grant: false,
    extraProducts: [{
      id: 'ambig',
      stock: {tipoProduto: 'simples', quantidade: 3},
    }],
  });
  await denied(draftAnd(db, lojaId, [{
    productId: 'ambig', qtySent: 1, unitSalePrice: 10, commissionType: 'SEM_COMISSAO', commissionValue: 0,
  }]), CODES.PRODUCT_STATE_UNSAFE);
});

test('dedicated gate 8 insufficient stock -> denied', async () => {
  const {db, base, lojaId} = await seed({protocol: false, grant: false, simpleQty: 1});
  const id = await draftAnd(db, lojaId, [simpleLine(2)]);
  const before = db.snapshot();
  await denied(executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner), CODES.INSUFFICIENT_STOCK);
  assert.deepEqual(db.snapshot(), before);
});

test('dedicated gate 9 legacy stock protocol absent + safe product -> ALLOWED', async () => {
  const {db, base, lojaId} = await seed({protocol: false, grant: false});
  assert.equal(db.exists(base.collection('stock_catalog_control').doc('state')), false);
  const id = await draftAnd(db, lojaId, [simpleLine(1)]);
  const res = await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
  assert.equal(res.status, 'ISSUED');
  assert.equal(stockQty(db, base), 4);
});

test('dedicated gate 10 broad protocol inactive + safe product -> ALLOWED', async () => {
  const {db, base, lojaId} = await seed({protocol: true, protocolMode: 'off', grant: false});
  const control = db.getData(base.collection('stock_catalog_control').doc('state'));
  assert.notEqual(control.mode, 'active');
  const id = await draftAnd(db, lojaId, [simpleLine(1)]);
  await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
  assert.equal(stockQty(db, base), 4);
});

test('dedicated gate 11 wrong store -> denied', async () => {
  const {db} = await seed({protocol: false, grant: false});
  const otherId = `other_gate_${++seq}`;
  const other = db.collection('lojas').doc(otherId);
  db.seed(other, {ownerUid: 'other-owner', lojaId: otherId});
  db.seed(other.collection('consignment_control').doc('state'), {protocolVersion: 1, moduleEnabled: true});
  await denied(executeConsignmentCommand(db, cmd(otherId, 'createDraft', 'op_ws', {
    resellerId: 'rev1', notes: '', lines: [simpleLine(1)],
  }, `c_ws_${seq}`), owner), CODES.AUTH);
});

test('dedicated gate 12 cross-store product -> denied', async () => {
  const {db, lojaId} = await seed({
    protocol: false, grant: false,
    extraProducts: [{
      id: 'foreign',
      stock: {quantidade: 4, stockKind: 'simple', stockRevision: 0, variacoes: {}, lojaId: 'other'},
    }],
  });
  await denied(draftAnd(db, lojaId, [{
    productId: 'foreign', qtySent: 1, unitSalePrice: 10, commissionType: 'SEM_COMISSAO', commissionValue: 0,
  }]), CODES.AUTH);
});

test('dedicated gate 13 grade -> denied', async () => {
  const {db, lojaId} = await seed({
    protocol: false, grant: false,
    extraProducts: [{
      id: 'grade2',
      stock: {
        stockKind: 'variation', stockRevision: 0, quantidade: 3,
        variacoes: {P: {Azul: 1, Vermelho: 2}}, tamanhos: ['P'], cores: ['Azul', 'Vermelho'],
      },
    }],
  });
  await denied(draftAnd(db, lojaId, [{
    productId: 'grade2', qtySent: 1, unitSalePrice: 10, commissionType: 'SEM_COMISSAO', commissionValue: 0,
    variationKey: {size: 'P', color: 'Azul', extra: ''},
  }]), CODES.CONSIGNMENT_GRADE_NOT_SUPPORTED);
});

test('dedicated gate 14 combo -> denied', async () => {
  const {db, lojaId} = await seed({
    protocol: false, grant: false,
    extraProducts: [{
      id: 'combo',
      stock: {
        stockKind: 'combo', tipoProduto: 'combo', stockRevision: 0, quantidade: 1,
        itensCombo: [{productId: 'simple', quantidade: 1}],
      },
    }],
  });
  await denied(draftAnd(db, lojaId, [{
    productId: 'combo', qtySent: 1, unitSalePrice: 10, commissionType: 'SEM_COMISSAO', commissionValue: 0,
  }]), CODES.PRODUCT_STATE_UNSAFE);
});

test('dedicated gate 15 safe simple issue decrements exactly once', async () => {
  const {db, base, lojaId} = await seed({protocol: false, grant: false});
  const id = await draftAnd(db, lojaId, [simpleLine(2)]);
  await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
  assert.equal(stockQty(db, base), 3);
  assert.equal(stockRev(db, base), 1);
});

test('dedicated gate 16 multi-line issue with one unsafe line -> zero writes', async () => {
  const {db, base, lojaId} = await seed({
    protocol: false, grant: false,
    extraProducts: [{
      id: 'legacy',
      stock: {tipoProduto: 'simples', quantidade: 9},
    }],
  });
  const before = db.snapshot();
  await denied(draftAnd(db, lojaId, [
    simpleLine(1),
    {productId: 'legacy', qtySent: 1, unitSalePrice: 10, commissionType: 'SEM_COMISSAO', commissionValue: 0},
  ]), CODES.PRODUCT_STATE_UNSAFE);
  assert.deepEqual(db.snapshot(), before);
  assert.equal(stockQty(db, base), 5);
  assert.equal(stockQty(db, base, 'legacy'), 9);
});

test('dedicated gate 17 retry same operation -> no duplicate decrement', async () => {
  const {db, base, lojaId} = await seed({protocol: false, grant: false});
  const id = await draftAnd(db, lojaId, [simpleLine(1)]);
  const first = await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
  const second = await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
  assert.equal(first.alreadyApplied, false);
  assert.equal(second.alreadyApplied, true);
  assert.equal(stockQty(db, base), 4);
  assert.equal(stockRev(db, base), 1);
});

test('dedicated gate 18-20 issue creates no sale/finance/receivable', async () => {
  const {db, base, lojaId} = await seed({protocol: false, grant: false});
  const id = await draftAnd(db, lojaId, [simpleLine(1)]);
  await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${id}`, {}, id), owner);
  assert.equal(saleExists(db, base, id), false);
  assert.equal(financeExists(db, base, id), false);
  assert.equal(db.exists(base.collection('contas_receber').doc(`csgn_${id}`)), false);
});

test('dedicated gate 21-26 settlement without broad protocol', async () => {
  const {db, base, lojaId} = await seed({protocol: false, grant: false, simpleQty: 10});
  const retId = await draftAnd(db, lojaId, [simpleLine(2, 50)]);
  await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${retId}`, {}, retId), owner);
  assert.equal(stockQty(db, base), 8);
  await executeConsignmentCommand(db, cmd(lojaId, 'settle', `settle_${retId}`, {
    lines: [{productId: 'simple', qtySold: 0, qtyReturned: 2}],
  }, retId), owner);
  assert.equal(stockQty(db, base), 10);
  assert.equal(saleExists(db, base, retId), false);

  const soldId = await draftAnd(db, lojaId, [simpleLine(2, 50)], {consignmentId: `sold_${seq}`});
  await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${soldId}`, {}, soldId), owner);
  const afterIssue = stockQty(db, base);
  const sold = await executeConsignmentCommand(db, cmd(lojaId, 'settle', `settle_${soldId}`, {
    lines: [{productId: 'simple', qtySold: 2, qtyReturned: 0}],
  }, soldId), owner);
  assert.equal(stockQty(db, base), afterIssue);
  assert.equal(sold.saleCreated, true);
  assert.equal(sold.financeCreated, true);
  const soldAgain = await executeConsignmentCommand(db, cmd(lojaId, 'settle', `settle_${soldId}`, {
    lines: [{productId: 'simple', qtySold: 2, qtyReturned: 0}],
  }, soldId), owner);
  assert.equal(soldAgain.alreadyApplied, true);
  assert.equal(stockQty(db, base), afterIssue);
  assert.equal([...db._store.keys()].filter(k => k.endsWith(`/estoque_vendas/csgn_${soldId}`)).length, 1);
  assert.equal([...db._store.keys()].filter(k => k.endsWith(`/lancamentos_financeiros/csgn_fin_${soldId}`)).length, 1);

  const mixId = await draftAnd(db, lojaId, [simpleLine(4, 50)], {consignmentId: `mix_${seq}`});
  await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${mixId}`, {}, mixId), owner);
  const beforeMixSettle = stockQty(db, base);
  await executeConsignmentCommand(db, cmd(lojaId, 'settle', `settle_${mixId}`, {
    lines: [{productId: 'simple', qtySold: 1, qtyReturned: 3}],
  }, mixId), owner);
  assert.equal(stockQty(db, base), beforeMixSettle + 3);
});
