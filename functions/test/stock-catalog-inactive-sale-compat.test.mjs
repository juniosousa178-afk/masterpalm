import test, {after} from 'node:test';
import assert from 'node:assert/strict';
import {Firestore} from 'firebase-admin/firestore';
import {executeStockCommand} from '../src/stockCatalogCommands.js';
import {classifyStockControlState, INACTIVE_COMPAT_ALLOWED_KINDS} from '../src/stockCatalogAccess.js';

if (process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:8187') {
  throw new Error('Local emulator required; refusing any other endpoint');
}
const db = new Firestore({projectId: 'demo-stock-catalog'});
after(() => db.terminate());

const runId = Date.now().toString(36);
let sequence = 0;
const owner = {uid: 'owner'};

async function seedLegacy({control = null, product = {}, withOwner = true, withDraft = false, withDep = false} = {}) {
  const lojaId = `inactive_${runId}_${++sequence}`;
  const base = db.collection('lojas').doc(lojaId);
  const batch = db.batch();
  batch.set(base, withOwner ? {ownerUid: 'owner', name: 'Fixture'} : {name: 'Fixture'});
  const stock = {quantidade: 5, stockKind: 'simple', stockRevision: 1, ...product};
  batch.set(base.collection('estoque_produtos').doc('p'), stock);
  if (withDraft) batch.set(base.collection('draft_produtos').doc('p'), {nome: 'Peça', publicadoNoCatalogo: true});
  if (withDep) batch.set(base.collection('stock_catalog_dependencies').doc('p'), {comboIds: []});
  if (control) batch.set(base.collection('stock_catalog_control').doc('state'), control);
  await batch.commit();
  return {base, lojaId};
}

function intent(lojaId, kind, operationId, item = {}, extra = {}) {
  return {protocolVersion: 1, lojaId, kind, operationId, items: [{productId: 'p', quantity: 1, ...item}], ...extra};
}
async function denied(promise, code) {
  await assert.rejects(promise, e => e.code === code);
}

test('classify: no control / inactive / active / invalid', () => {
  assert.equal(classifyStockControlState({exists: false}), 'NO_CONTROL');
  assert.equal(classifyStockControlState({exists: true, data: () => ({mode: 'inactive', protocolVersion: 1})}), 'INACTIVE');
  assert.equal(classifyStockControlState({
    exists: true,
    data: () => ({mode: 'active', protocolVersion: 1, migrationComplete: true}),
  }), 'ACTIVE');
  assert.equal(classifyStockControlState({
    exists: true,
    data: () => ({mode: 'active', protocolVersion: 1, migrationComplete: false}),
  }), 'INVALID');
  assert.equal(classifyStockControlState({
    exists: true,
    data: () => ({mode: 'maintenance', protocolVersion: 1, migrationComplete: true}),
  }), 'INVALID');
  assert.equal(classifyStockControlState({
    exists: true,
    data: () => ({protocolVersion: 2, mode: 'active', migrationComplete: true}),
  }), 'INVALID');
  assert.deepEqual([...INACTIVE_COMPAT_ALLOWED_KINDS], ['sale', 'restore']);
});

test('no-control store authenticated owner simple sale succeeds without draft/dep', async () => {
  const {base, lojaId} = await seedLegacy();
  const result = await executeStockCommand(db, intent(lojaId, 'sale', 's1'), owner);
  assert.equal(result.alreadyApplied, false);
  assert.equal((await base.collection('estoque_produtos').doc('p').get()).data().quantidade, 4);
  assert.equal((await base.collection('stock_catalog_control').doc('state').get()).exists, false);
  assert.equal((await base.collection('stock_catalog_access').doc('owner').get()).exists, false);
  assert.equal((await base.collection('draft_produtos').doc('p').get()).exists, false);
});

test('inactive control store sale succeeds', async () => {
  const {base, lojaId} = await seedLegacy({
    control: {protocolVersion: 1, mode: 'inactive', migrationComplete: false},
  });
  await executeStockCommand(db, intent(lojaId, 'sale', 's1'), owner);
  assert.equal((await base.collection('estoque_produtos').doc('p').get()).data().quantidade, 4);
});

test('migrated-inactive (migrationComplete true, mode inactive) sale succeeds', async () => {
  const {base, lojaId} = await seedLegacy({
    control: {protocolVersion: 1, mode: 'inactive', migrationComplete: true},
    withDraft: true,
    withDep: true,
  });
  await executeStockCommand(db, intent(lojaId, 'sale', 's1'), owner);
  assert.equal((await base.collection('estoque_produtos').doc('p').get()).data().quantidade, 4);
});

test('other-store caller denied; unauthenticated denied', async () => {
  const {lojaId} = await seedLegacy();
  await denied(executeStockCommand(db, intent(lojaId, 'sale', 's1'), null), 'unauthenticated');
  await denied(executeStockCommand(db, intent(lojaId, 'sale', 's1'), {uid: 'intruder'}), 'permission-denied');
});

test('invalid command on inactive denied; restock not allowed on compat bridge', async () => {
  const {base, lojaId} = await seedLegacy();
  await denied(executeStockCommand(db, intent(lojaId, 'restock', 'r1'), owner), 'failed-precondition');
  assert.equal((await base.collection('estoque_produtos').doc('p').get()).data().quantidade, 5);
});

test('duplicate retry does not double decrement', async () => {
  const {base, lojaId} = await seedLegacy({product: {quantidade: 3}});
  const cmd = intent(lojaId, 'sale', 'once');
  const a = await executeStockCommand(db, cmd, owner);
  const b = await executeStockCommand(db, cmd, owner);
  assert.equal(a.alreadyApplied, false);
  assert.equal(b.alreadyApplied, true);
  assert.equal((await base.collection('estoque_produtos').doc('p').get()).data().quantidade, 2);
});

test('insufficient stock fails safely without mutation marker', async () => {
  const {base, lojaId} = await seedLegacy({product: {quantidade: 0}});
  await denied(executeStockCommand(db, intent(lojaId, 'sale', 's1'), owner), 'failed-precondition');
  assert.equal((await base.collection('estoque_produtos').doc('p').get()).data().quantidade, 0);
  assert.equal((await base.collection('stock_catalog_operations').doc('s1').get()).exists, false);
});

test('grade sizes 34-39: sale size 37 decrements only 37', async () => {
  const grade = {
    stockKind: 'variation',
    quantidade: 12,
    stockRevision: 2,
    estoquePorTamanho: {34: 2, 35: 2, 36: 2, 37: 2, 38: 2, 39: 2},
    variacoes: {
      34: {amendoa: 2}, 35: {amendoa: 2}, 36: {amendoa: 2},
      37: {amendoa: 2}, 38: {amendoa: 2}, 39: {amendoa: 2},
    },
    tamanhos: ['34', '35', '36', '37', '38', '39'],
  };
  const {base, lojaId} = await seedLegacy({product: grade});
  await executeStockCommand(db, intent(lojaId, 'sale', 'g37', {size: '37', color: 'amendoa'}), owner);
  const stock = (await base.collection('estoque_produtos').doc('p').get()).data();
  assert.equal(stock.variacoes['37'].amendoa, 1);
  assert.equal(stock.variacoes['34'].amendoa, 2);
  assert.equal(stock.variacoes['35'].amendoa, 2);
  assert.equal(stock.variacoes['36'].amendoa, 2);
  assert.equal(stock.variacoes['38'].amendoa, 2);
  assert.equal(stock.variacoes['39'].amendoa, 2);
  assert.equal(stock.estoquePorTamanho['37'], 1);
});

test('missing selected size fails structured', async () => {
  const {lojaId} = await seedLegacy({
    product: {
      stockKind: 'variation',
      quantidade: 2,
      estoquePorTamanho: {37: 2},
      variacoes: {37: {amendoa: 2}},
    },
  });
  await denied(
    executeStockCommand(db, intent(lojaId, 'sale', 'bad', {size: '99', color: 'amendoa'}), owner),
    'failed-precondition',
  );
});

test('corrupt/incomplete control fails closed', async () => {
  for (const control of [
    {protocolVersion: 2, mode: 'active', migrationComplete: true},
    {protocolVersion: 1, mode: 'active', migrationComplete: false},
    {protocolVersion: 1, mode: 'maintenance', migrationComplete: true},
  ]) {
    const {base, lojaId} = await seedLegacy({control});
    await denied(executeStockCommand(db, intent(lojaId, 'sale', 's1'), owner), 'failed-precondition');
    assert.equal((await base.collection('estoque_produtos').doc('p').get()).data().quantidade, 5);
  }
});

test('active store still requires grant protocol (regression)', async () => {
  const lojaId = `active_${runId}_${++sequence}`;
  const base = db.collection('lojas').doc(lojaId);
  await base.set({ownerUid: 'owner'});
  await base.collection('estoque_produtos').doc('p').set({quantidade: 2, stockKind: 'simple', stockRevision: 0});
  await base.collection('draft_produtos').doc('p').set({nome: 'A', publicadoNoCatalogo: true});
  await base.collection('stock_catalog_dependencies').doc('p').set({comboIds: []});
  await base.collection('stock_catalog_control').doc('state').set({
    protocolVersion: 1, mode: 'active', migrationComplete: true,
  });
  // owner membership alone is not enough on ACTIVE — grant required
  await denied(executeStockCommand(db, intent(lojaId, 'sale', 's1'), owner), 'permission-denied');
  await base.collection('stock_catalog_access').doc('owner').set({
    enabled: true, permissions: {sale: true},
  });
  await executeStockCommand(db, intent(lojaId, 'sale', 's1'), owner);
  assert.equal((await base.collection('estoque_produtos').doc('p').get()).data().quantidade, 1);
});
