// Fase 1A — regressão dos comandos existentes. Não altera consignmentCommand
// nem stockCatalogCommand. Não faz deploy.

import test from 'node:test';
import assert from 'node:assert/strict';
import {executeConsignmentCommand} from '../src/consignmentCommand.js';
import {executeStockCommand} from '../src/stockCatalogCommands.js';
import {CODES} from '../src/consignmentProtocol.js';
import {createConsignmentTestDb} from './consignment-test-db.mjs';

const owner = {uid: 'owner'};
let seq = 0;

function denied(promise, code) {
  return assert.rejects(promise, (e) => e.consignmentCode === code || e.code === code);
}

async function seed() {
  const db = createConsignmentTestDb();
  const lojaId = `finv2_${Date.now().toString(36)}_${++seq}`;
  const base = db.collection('lojas').doc(lojaId);
  db.seed(base, {ownerUid: 'owner', lojaId, nome: 'Master'});
  db.seed(base.collection('stock_catalog_control').doc('state'), {
    protocolVersion: 1, mode: 'active', migrationComplete: true,
  });
  db.seed(base.collection('stock_catalog_access').doc('owner'), {
    enabled: true,
    permissions: {
      sale: true, restock: true, adjust: true, restore: true,
      editorial: true, publish: true, create: true, delete: true, undo: true,
    },
  });
  db.seed(base.collection('consignment_control').doc('state'), {
    protocolVersion: 1, moduleEnabled: true,
  });
  db.seed(base.collection('estoque_produtos').doc('simple'), {
    quantidade: 5, stockKind: 'simple', stockRevision: 0, variacoes: {},
  });
  db.seed(base.collection('draft_produtos').doc('simple'), {
    nome: 'Anel', publicadoNoCatalogo: true, preco: 100,
  });
  db.seed(base.collection('stock_catalog_dependencies').doc('simple'), {comboIds: []});
  db.seed(base.collection('estoque_produtos').doc('second'), {
    quantidade: 4, stockKind: 'simple', stockRevision: 7, variacoes: {},
  });
  db.seed(base.collection('draft_produtos').doc('second'), {
    nome: 'Brinco', publicadoNoCatalogo: true, preco: 40,
  });
  db.seed(base.collection('stock_catalog_dependencies').doc('second'), {comboIds: []});
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

function line(productId, qty, price = 50) {
  return {
    productId, qtySent: qty, unitSalePrice: price,
    commissionType: 'PERCENTUAL', commissionValue: 10,
  };
}

test('CONSIGNMENT_DRAFT_NO_STOCK_WRITE', async () => {
  const {db, base, lojaId} = await seed();
  const beforeSimple = db.getData(base.collection('estoque_produtos').doc('simple'));
  const beforeSecond = db.getData(base.collection('estoque_produtos').doc('second'));
  await executeConsignmentCommand(db, cmd(lojaId, 'createDraft', 'op_draft_multi', {
    resellerId: 'rev1',
    notes: '',
    lines: [line('simple', 2), line('second', 1, 40)],
  }, 'c_multi'), owner);
  const afterSimple = db.getData(base.collection('estoque_produtos').doc('simple'));
  const afterSecond = db.getData(base.collection('estoque_produtos').doc('second'));
  assert.equal(afterSimple.quantidade, beforeSimple.quantidade);
  assert.equal(afterSimple.stockRevision, beforeSimple.stockRevision);
  assert.equal(afterSecond.quantidade, beforeSecond.quantidade);
  assert.equal(afterSecond.stockRevision, beforeSecond.stockRevision);
  assert.equal(db.exists(base.collection('estoque_vendas').doc('csgn_c_multi')), false);
  assert.equal(db.exists(base.collection('lancamentos_financeiros').doc('csgn_fin_c_multi')), false);
});

test('CONSIGNMENT_MULTI_ITEM_PRESERVED', async () => {
  const {db, base, lojaId} = await seed();
  await executeConsignmentCommand(db, cmd(lojaId, 'createDraft', 'op_draft_keep', {
    resellerId: 'rev1',
    lines: [line('simple', 2, 50), line('second', 1, 40)],
  }, 'c_keep'), owner);
  const doc = db.getData(base.collection('consignments').doc('c_keep'));
  assert.equal(doc.lines.length, 2);
  assert.equal(doc.lines[0].productId, 'simple');
  assert.equal(doc.lines[0].qtySent, 2);
  assert.equal(doc.lines[1].productId, 'second');
  assert.equal(doc.lines[1].qtySent, 1);
  assert.equal(doc.status, 'DRAFT');
});

test('CONSIGNMENT_ISSUE_NOT_REVENUE', async () => {
  const {db, base, lojaId} = await seed();
  await executeConsignmentCommand(db, cmd(lojaId, 'createDraft', 'op_draft_issue', {
    resellerId: 'rev1',
    lines: [line('simple', 2)],
  }, 'c_issue'), owner);
  await executeConsignmentCommand(db, cmd(lojaId, 'issue', 'op_issue', {}, 'c_issue'), owner);
  const stock = db.getData(base.collection('estoque_produtos').doc('simple'));
  assert.equal(stock.quantidade, 3);
  assert.equal(db.exists(base.collection('estoque_vendas').doc('csgn_c_issue')), false);
  assert.equal(db.exists(base.collection('lancamentos_financeiros').doc('csgn_fin_c_issue')), false);
  const doc = db.getData(base.collection('consignments').doc('c_issue'));
  assert.equal(doc.status, 'ISSUED');
  assert.equal(doc.saleId, null);
  assert.equal(doc.financeId, null);
});

test('CONSIGNMENT_SETTLEMENT_NOT_DOUBLE_COUNTED', async () => {
  const {db, base, lojaId} = await seed();
  await executeConsignmentCommand(db, cmd(lojaId, 'createDraft', 'op_draft_set', {
    resellerId: 'rev1',
    lines: [line('simple', 2, 50)],
  }, 'c_set'), owner);
  await executeConsignmentCommand(db, cmd(lojaId, 'issue', 'op_issue_set', {}, 'c_set'), owner);
  await executeConsignmentCommand(db, cmd(lojaId, 'settle', 'op_settle_set', {
    lines: [{productId: 'simple', qtySold: 2, qtyReturned: 0}],
  }, 'c_set'), owner);
  assert.equal(db.exists(base.collection('estoque_vendas').doc('csgn_c_set')), true);
  assert.equal(db.exists(base.collection('lancamentos_financeiros').doc('csgn_fin_c_set')), true);
  const sale = db.getData(base.collection('estoque_vendas').doc('csgn_c_set'));
  const fin = db.getData(base.collection('lancamentos_financeiros').doc('csgn_fin_c_set'));
  assert.equal(sale.formasPagamento, 'consignacao');
  assert.equal(sale.pagamentoDinheiro, 0);
  assert.equal(sale.pagamentoPix, 0);
  assert.equal(sale.pagamentoCartao, 0);
  assert.equal(fin.origem, 'consignment');
  assert.equal(fin.referenciaExterna, 'c_set');
  await denied(executeConsignmentCommand(db, cmd(lojaId, 'settle', 'op_settle_again', {
    lines: [{productId: 'simple', qtySold: 2, qtyReturned: 0}],
  }, 'c_set'), owner), CODES.CONSIGNMENT_ALREADY_SETTLED);
  assert.equal(db.exists(base.collection('estoque_vendas').doc('csgn_c_set')), true);
  assert.equal(db.exists(base.collection('lancamentos_financeiros').doc('csgn_fin_c_set')), true);
});

test('SALE_STOCK_DECREMENT_UNCHANGED', async () => {
  const {db, base, lojaId} = await seed();
  await executeStockCommand(db, {
    protocolVersion: 1, lojaId, kind: 'sale', operationId: 'sale_once',
    items: [{productId: 'simple', quantity: 2}],
  }, owner);
  assert.equal(db.getData(base.collection('estoque_produtos').doc('simple')).quantidade, 3);
});

test('SALE_RETRY_IDEMPOTENT', async () => {
  const {db, base, lojaId} = await seed();
  const first = await executeStockCommand(db, {
    protocolVersion: 1, lojaId, kind: 'sale', operationId: 'sale_retry',
    items: [{productId: 'simple', quantity: 1}],
  }, owner);
  const second = await executeStockCommand(db, {
    protocolVersion: 1, lojaId, kind: 'sale', operationId: 'sale_retry',
    items: [{productId: 'simple', quantity: 1}],
  }, owner);
  assert.equal(first.alreadyApplied, false);
  assert.equal(second.alreadyApplied, true);
  assert.equal(db.getData(base.collection('estoque_produtos').doc('simple')).quantidade, 4);
});

test('PRODUCT_STOCK_CAS_UNCHANGED', async () => {
  const {db, base, lojaId} = await seed();
  const before = db.getData(base.collection('estoque_produtos').doc('second'));
  await denied(executeStockCommand(db, {
    protocolVersion: 1, lojaId, kind: 'adjust', operationId: 'cas_stale',
    items: [{productId: 'second', quantity: 1, expectedRevision: 0}],
  }, owner), 'aborted');
  const after = db.getData(base.collection('estoque_produtos').doc('second'));
  assert.equal(after.quantidade, before.quantidade);
  assert.equal(after.stockRevision, before.stockRevision);
  assert.equal(after.stockRevision, 7);
});
