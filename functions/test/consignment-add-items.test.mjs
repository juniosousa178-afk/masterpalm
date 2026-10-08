import test from 'node:test';
import assert from 'node:assert/strict';
import {executeConsignmentCommand} from '../src/consignmentCommand.js';
import {CODES} from '../src/consignmentProtocol.js';
import {createConsignmentTestDb} from './consignment-test-db.mjs';

const owner = {uid: 'owner'};
let seq = 0;

function denied(promise, code) {
  return assert.rejects(promise, e => e.consignmentCode === code || e.code === code);
}

async function seedJoao({
  prices = {A: 100, B: 100, C: 100, F: 50, G: 60},
  qtys = {A: 10, B: 10, C: 10, F: 10, G: 10},
} = {}) {
  const db = createConsignmentTestDb();
  const lojaId = `add_${Date.now().toString(36)}_${++seq}`;
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
  db.seed(base.collection('consignment_resellers').doc('joao'), {
    storeId: lojaId, resellerId: 'joao', displayName: 'João', active: true, notes: '',
  });
  for (const id of Object.keys(qtys)) {
    db.seed(base.collection('estoque_produtos').doc(id), {
      quantidade: qtys[id], stockKind: 'simple', stockRevision: 0, variacoes: {},
    });
    db.seed(base.collection('draft_produtos').doc(id), {
      nome: `Produto ${id}`, publicadoNoCatalogo: true, preco: prices[id] ?? 100,
    });
    db.seed(base.collection('stock_catalog_dependencies').doc(id), {comboIds: []});
  }
  return {db, base, lojaId};
}

function cmd(lojaId, operation, operationId, payload = {}, consignmentId = null) {
  return {
    protocolVersion: 1, lojaId, operation, operationId,
    ...(consignmentId ? {consignmentId} : {}),
    payload,
  };
}

function line(productId, qty, price = 100, commissionValue = 10) {
  return {
    productId, qtySent: qty, unitSalePrice: price,
    commissionType: 'PERCENTUAL', commissionValue,
  };
}

function stockQty(db, base, id) {
  return db.getData(base.collection('estoque_produtos').doc(id))?.quantidade;
}
function stockRev(db, base, id) {
  return db.getData(base.collection('estoque_produtos').doc(id))?.stockRevision;
}
function consignment(db, base, id) {
  return db.getData(base.collection('consignments').doc(id));
}

async function issueInitial(db, lojaId, lines, resellerId = 'joao') {
  const consignmentId = `c_joao_${++seq}`;
  await executeConsignmentCommand(db, cmd(lojaId, 'createDraft', `op_draft_${consignmentId}`, {
    resellerId, notes: '', lines,
  }, consignmentId), owner);
  await executeConsignmentCommand(db, cmd(lojaId, 'issue', `issue_${consignmentId}`, {}, consignmentId), owner);
  return consignmentId;
}

test('addItems: ISSUED receives new product and more qty of existing', async () => {
  const {db, base, lojaId} = await seedJoao();
  const id = await issueInitial(db, lojaId, [
    line('A', 1, 100), line('B', 2, 100), line('C', 1, 100),
  ]);
  assert.equal(stockQty(db, base, 'B'), 8);
  const doc0 = consignment(db, base, id);
  assert.equal(doc0.status, 'ISSUED');
  assert.equal(doc0.totalItemsSent, 4);
  assert.equal((doc0.additions || []).length, 1);
  assert.equal(doc0.additions[0].kind, 'INITIAL');

  const add = await executeConsignmentCommand(db, cmd(lojaId, 'addItems', `add1_${id}`, {
    expectedRevision: doc0.revision,
    lines: [line('B', 3, 110), line('F', 1, 50), line('G', 2, 60)],
  }, id), owner);

  assert.equal(add.additionId, `add1_${id}`);
  assert.equal(add.revision, doc0.revision + 1);
  assert.equal(add.updatedTotals.totalItemsSent, 10);

  const doc = consignment(db, base, id);
  assert.equal(doc.totalItemsSent, 10);
  assert.equal(doc.revision, doc0.revision + 1);
  assert.equal((doc.additions || []).length, 2);
  assert.equal(doc.additions[1].kind, 'ADDITION');

  const byProduct = {};
  for (const l of doc.lines) {
    byProduct[l.productId] = (byProduct[l.productId] || 0) + l.qtySent;
  }
  assert.deepEqual(byProduct, {A: 1, B: 5, C: 1, F: 1, G: 2});

  const bLots = doc.lines.filter(l => l.productId === 'B');
  assert.equal(bLots.length, 2);
  assert.equal(bLots[0].qtySent, 2);
  assert.equal(bLots[0].unitSalePriceSnapshot, 100);
  assert.equal(bLots[1].qtySent, 3);
  assert.equal(bLots[1].unitSalePriceSnapshot, 110);
  assert.equal(bLots[0].commissionValueSnapshot, 10);
  assert.equal(bLots[1].commissionValueSnapshot, 10);

  const hist = doc.additions[1].lines;
  assert.equal(hist.find(l => l.productId === 'B').qtyAdded, 3);
  assert.equal(hist.find(l => l.productId === 'F').qtyAdded, 1);
  assert.equal(hist.find(l => l.productId === 'G').qtyAdded, 2);

  assert.equal(stockQty(db, base, 'A'), 9);
  assert.equal(stockQty(db, base, 'B'), 5);
  assert.equal(stockQty(db, base, 'C'), 9);
  assert.equal(stockQty(db, base, 'F'), 9);
  assert.equal(stockQty(db, base, 'G'), 8);
});

test('addItems: João settlement includes all additions (TOTAL_ENVIADO=10)', async () => {
  const {db, base, lojaId} = await seedJoao();
  const id = await issueInitial(db, lojaId, [
    line('A', 1), line('B', 2), line('C', 1),
  ]);
  const rev = consignment(db, base, id).revision;
  await executeConsignmentCommand(db, cmd(lojaId, 'addItems', `add2_${id}`, {
    expectedRevision: rev,
    lines: [line('B', 3, 110), line('F', 1), line('G', 2)],
  }, id), owner);
  const doc = consignment(db, base, id);
  assert.equal(doc.totalItemsSent, 10);
  const settleLines = doc.lines.map(l => ({
    lineId: l.lineId,
    productId: l.productId,
    variationKey: l.variationKey,
    qtySold: l.qtySent,
    qtyReturned: 0,
  }));
  await executeConsignmentCommand(db, cmd(lojaId, 'settle', `settle_${id}`, {
    lines: settleLines,
  }, id), owner);
  const settled = consignment(db, base, id);
  assert.equal(settled.status, 'SETTLED');
  assert.equal(settled.totalItemsSold, 10);
  assert.equal(settled.totalItemsReturned, 0);
  // B lots: 2@100 + 3@110 => gross 200+330=530 from B alone; full sold all lines
  assert.ok(settled.grossSoldAmount > 0);
});

test('addItems: history preserves separate lots (2 then 3)', async () => {
  const {db, base, lojaId} = await seedJoao();
  const id = await issueInitial(db, lojaId, [line('B', 2, 100)]);
  const rev = consignment(db, base, id).revision;
  await executeConsignmentCommand(db, cmd(lojaId, 'addItems', `addB_${id}`, {
    expectedRevision: rev,
    lines: [line('B', 3, 110)],
  }, id), owner);
  const doc = consignment(db, base, id);
  assert.equal(doc.additions.length, 2);
  assert.equal(doc.additions[0].lines[0].qtyAdded, 2);
  assert.equal(doc.additions[0].lines[0].unitSalePriceSnapshot, 100);
  assert.equal(doc.additions[1].lines[0].qtyAdded, 3);
  assert.equal(doc.additions[1].lines[0].unitSalePriceSnapshot, 110);
  assert.equal(doc.lines.reduce((s, l) => s + (l.productId === 'B' ? l.qtySent : 0), 0), 5);
});

test('addItems: DRAFT appends without stock decrement until issue', async () => {
  const {db, base, lojaId} = await seedJoao();
  const id = `c_draft_${++seq}`;
  await executeConsignmentCommand(db, cmd(lojaId, 'createDraft', `op_draft_${id}`, {
    resellerId: 'joao', notes: '', lines: [line('A', 1)],
  }, id), owner);
  const before = stockQty(db, base, 'A');
  const rev = consignment(db, base, id).revision;
  await executeConsignmentCommand(db, cmd(lojaId, 'addItems', `add_draft_${id}`, {
    expectedRevision: rev,
    lines: [line('B', 2)],
  }, id), owner);
  assert.equal(stockQty(db, base, 'A'), before);
  assert.equal(stockQty(db, base, 'B'), 10);
  const doc = consignment(db, base, id);
  assert.equal(doc.status, 'DRAFT');
  assert.equal(doc.totalItemsSent, 3);
  assert.equal(doc.additions.at(-1).kind, 'DRAFT_ADD');
});

test('addItems: SETTLED rejects', async () => {
  const {db, base, lojaId} = await seedJoao();
  const id = await issueInitial(db, lojaId, [line('A', 1)]);
  const doc = consignment(db, base, id);
  await executeConsignmentCommand(db, cmd(lojaId, 'settle', `settle_${id}`, {
    lines: doc.lines.map(l => ({
      lineId: l.lineId, productId: l.productId, variationKey: l.variationKey,
      qtySold: l.qtySent, qtyReturned: 0,
    })),
  }, id), owner);
  await denied(executeConsignmentCommand(db, cmd(lojaId, 'addItems', `add_settled_${id}`, {
    expectedRevision: consignment(db, base, id).revision,
    lines: [line('B', 1)],
  }, id), owner), CODES.CONSIGNMENT_ALREADY_SETTLED);
});

test('addItems: CANCELLED rejects', async () => {
  const {db, base, lojaId} = await seedJoao();
  const id = `c_cancel_${++seq}`;
  await executeConsignmentCommand(db, cmd(lojaId, 'createDraft', `op_draft_${id}`, {
    resellerId: 'joao', notes: '', lines: [line('A', 1)],
  }, id), owner);
  await executeConsignmentCommand(db, cmd(lojaId, 'cancelDraft', `cancel_${id}`, {}, id), owner);
  await denied(executeConsignmentCommand(db, cmd(lojaId, 'addItems', `add_cancel_${id}`, {
    expectedRevision: consignment(db, base, id).revision,
    lines: [line('B', 1)],
  }, id), owner), CODES.CONSIGNMENT_CANCELLED);
});

test('addItems: stale consignmentRevision rejects', async () => {
  const {db, base, lojaId} = await seedJoao();
  const id = await issueInitial(db, lojaId, [line('A', 1)]);
  await denied(executeConsignmentCommand(db, cmd(lojaId, 'addItems', `add_stale_${id}`, {
    expectedRevision: 0,
    lines: [line('B', 1)],
  }, id), owner), CODES.CONSIGNMENT_REVISION_CONFLICT);
});

test('addItems: insufficient stock rejects', async () => {
  const {db, base, lojaId} = await seedJoao({qtys: {A: 10, B: 1, C: 10, F: 10, G: 10}});
  const id = await issueInitial(db, lojaId, [line('A', 1)]);
  const rev = consignment(db, base, id).revision;
  await denied(executeConsignmentCommand(db, cmd(lojaId, 'addItems', `add_insuf_${id}`, {
    expectedRevision: rev,
    lines: [line('B', 5)],
  }, id), owner), CODES.PRODUCT_VALIDATION_FAILED);
});

test('addItems: stale stockRevision rejects', async () => {
  const {db, base, lojaId} = await seedJoao();
  const id = await issueInitial(db, lojaId, [line('A', 1)]);
  const rev = consignment(db, base, id).revision;
  await denied(executeConsignmentCommand(db, cmd(lojaId, 'addItems', `add_stockrev_${id}`, {
    expectedRevision: rev,
    lines: [{...line('B', 1), expectedStockRevision: 99}],
  }, id), owner), CODES.PRODUCT_VALIDATION_FAILED);
});

test('addItems: retry idempotent', async () => {
  const {db, base, lojaId} = await seedJoao();
  const id = await issueInitial(db, lojaId, [line('A', 1)]);
  const rev = consignment(db, base, id).revision;
  const payload = {expectedRevision: rev, lines: [line('B', 2)]};
  const op = `add_idem_${id}`;
  const r1 = await executeConsignmentCommand(db, cmd(lojaId, 'addItems', op, payload, id), owner);
  const stockAfter = stockQty(db, base, 'B');
  const r2 = await executeConsignmentCommand(db, cmd(lojaId, 'addItems', op, payload, id), owner);
  assert.equal(r2.alreadyApplied, true);
  assert.equal(stockQty(db, base, 'B'), stockAfter);
  assert.equal(consignment(db, base, id).lines.filter(l => l.productId === 'B').length, 1);
  assert.equal(r1.additionId, op);
});

test('addItems: variation cell exact', async () => {
  const {db, base, lojaId} = await seedJoao();
  db.seed(base.collection('estoque_produtos').doc('varB'), {
    stockKind: 'variation', stockRevision: 0, quantidade: 4,
    variacoes: {P: {'sem-cor': 1}, M: {'sem-cor': 2}, G: {'sem-cor': 1}},
  });
  db.seed(base.collection('draft_produtos').doc('varB'), {
    nome: 'Brinco B', publicadoNoCatalogo: true, preco: 40,
  });
  db.seed(base.collection('stock_catalog_dependencies').doc('varB'), {comboIds: []});
  const id = await issueInitial(db, lojaId, [line('A', 1)]);
  const rev = consignment(db, base, id).revision;
  await executeConsignmentCommand(db, cmd(lojaId, 'addItems', `add_var_${id}`, {
    expectedRevision: rev,
    lines: [{
      productId: 'varB', qtySent: 1, unitSalePrice: 40,
      commissionType: 'SEM_COMISSAO', commissionValue: 0,
      variationKey: {size: 'M', color: 'sem-cor', extra: ''},
    }],
  }, id), owner);
  const stock = db.getData(base.collection('estoque_produtos').doc('varB'));
  assert.equal(stock.variacoes.M['sem-cor'], 1);
  assert.equal(stock.quantidade, 3);
  const added = consignment(db, base, id).lines.find(l => l.productId === 'varB');
  assert.equal(added.variationKey.size, 'M');
  assert.equal(added.qtySent, 1);
});

test('addItems: grade cell exact', async () => {
  const {db, base, lojaId} = await seedJoao();
  db.seed(base.collection('estoque_produtos').doc('gradeX'), {
    stockKind: 'variation', stockRevision: 0, quantidade: 3,
    variacoes: {P: {Dourado: 1, Prata: 1}, M: {Dourado: 1}},
    tamanhos: ['P', 'M'], cores: ['Dourado', 'Prata'],
  });
  db.seed(base.collection('draft_produtos').doc('gradeX'), {
    nome: 'Grade X', publicadoNoCatalogo: true, preco: 70,
  });
  db.seed(base.collection('stock_catalog_dependencies').doc('gradeX'), {comboIds: []});
  const id = await issueInitial(db, lojaId, [line('A', 1)]);
  const rev = consignment(db, base, id).revision;
  await executeConsignmentCommand(db, cmd(lojaId, 'addItems', `add_grade_${id}`, {
    expectedRevision: rev,
    lines: [{
      productId: 'gradeX', qtySent: 1, unitSalePrice: 70,
      commissionType: 'SEM_COMISSAO', commissionValue: 0,
      variationKey: {size: 'P', color: 'Dourado', extra: ''},
    }],
  }, id), owner);
  const stock = db.getData(base.collection('estoque_produtos').doc('gradeX'));
  assert.equal(stock.variacoes.P.Dourado, 0);
  assert.equal(stock.variacoes.P.Prata, 1);
  assert.equal(stock.quantidade, 2);
});

test('addItems: cross-store blocked', async () => {
  const {db, lojaId} = await seedJoao();
  const foreignId = `foreign_${++seq}`;
  const foreignBase = db.collection('lojas').doc(foreignId);
  db.seed(foreignBase, {ownerUid: 'owner', lojaId: foreignId, nome: 'Other'});
  db.seed(foreignBase.collection('consignment_control').doc('state'), {
    protocolVersion: 1, moduleEnabled: true,
  });
  const stolenId = `stolen_${++seq}`;
  db.seed(foreignBase.collection('consignments').doc(stolenId), {
    id: stolenId,
    storeId: lojaId,
    resellerId: 'joao',
    status: 'ISSUED',
    revision: 1,
    lines: [],
    additions: [],
    totalItemsSent: 0,
  });
  await denied(executeConsignmentCommand(db, cmd(foreignId, 'addItems', `add_xs_${stolenId}`, {
    expectedRevision: 1,
    lines: [line('B', 1)],
  }, stolenId), owner), CODES.AUTH);
});
