import test, {after} from 'node:test';
import assert from 'node:assert/strict';
import {initializeApp, deleteApp} from 'firebase-admin/app';
import {getFirestore} from 'firebase-admin/firestore';
import {executeStockCommand, publishStockProduct} from '../src/stockCatalogCommands.js';

if (process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:8187') throw new Error('Exact local emulator required');
const projectId = 'demo-stock-catalog';
const app = initializeApp({projectId}, `rollout-${Date.now()}`), db = getFirestore(app);
after(() => deleteApp(app));
let sequence = 0;
const auth = {uid: 'owner'};
async function fixture() {
  const lojaId = `rollout-${Date.now()}-${++sequence}`, base = db.collection('lojas').doc(lojaId);
  // Artificial fixtures only, not the migration executor or production data.
  await base.collection('estoque_produtos').doc('p').set({quantidade: 1, stockKind: 'simple', stockRevision: 0});
  await base.collection('draft_produtos').doc('p').set({nome: 'Fixture', publicadoNoCatalogo: true});
  await base.collection('stock_catalog_dependencies').doc('p').set({comboIds: []});
  await base.collection('stock_catalog_access').doc('owner').set({enabled: true, permissions: {sale: true, publish: true, restock: true}});
  return {lojaId, base, control: base.collection('stock_catalog_control').doc('state')};
}
const active = {protocolVersion: 1, mode: 'active', migrationComplete: true};
const intent = (lojaId, kind = 'sale', operationId = 's') => ({lojaId, protocolVersion: 1, kind, operationId,
  items: [{productId: 'p', quantity: kind === 'restock' ? 5 : 1}]});
async function publicRead(lojaId) {
  return fetch(`http://127.0.0.1:8187/v1/projects/${projectId}/databases/(default)/documents/lojas/${lojaId}/produtos/p`);
}
test('absent, unknown-version, incomplete and maintenance controls deny backend without mutation', async () => {
  // Absent control without store membership → inactive route then permission-denied.
  // Corrupt/incomplete/maintenance → fail-closed failed-precondition (unchanged).
  for (const control of [null, {...active, protocolVersion: 2}, {...active, migrationComplete: false}, {...active, mode: 'maintenance'}]) {
    const f = await fixture(); if (control) await f.control.set(control);
    const expected = control === null ? 'permission-denied' : 'failed-precondition';
    await assert.rejects(executeStockCommand(db, intent(f.lojaId), auth), e => e.code === expected);
    await assert.rejects(publishStockProduct(db, f.lojaId, 'p', auth), e => e.code === 'failed-precondition' || e.code === 'permission-denied');
    assert.equal((await f.base.collection('estoque_produtos').doc('p').get()).data().quantidade, 1);
    assert.equal((await f.base.collection('stock_catalog_operations').doc('s').get()).exists, false);
  }
});
test('absent control with ownerUid allows sale via inactive compatibility bridge', async () => {
  const f = await fixture();
  await f.base.set({ownerUid: 'owner'}, {merge: true});
  // No draft/dep required for inactive sale after bridge.
  await f.base.collection('draft_produtos').doc('p').delete();
  await f.base.collection('stock_catalog_dependencies').doc('p').delete();
  await executeStockCommand(db, intent(f.lojaId), auth);
  assert.equal((await f.base.collection('estoque_produtos').doc('p').get()).data().quantidade, 0);
});
test('maintenance rejects backend sale; activation serves only current projection', async () => {
  const f = await fixture(); await f.control.set({...active, mode: 'maintenance'});
  await f.base.collection('produtos').doc('p').set({quantidade: 99});
  // Emergency public catalog Rules allow resource!=null reads regardless of mode;
  // backend maintenance still fail-closes stock commands.
  await assert.rejects(executeStockCommand(db, intent(f.lojaId), auth), e => e.code === 'failed-precondition');
  // Fixtures simulate independently verified migration. Actual activation and
  // document verification remain future authorized deployment operations.
  await f.base.collection('produtos').doc('p').delete();
  await f.control.set(active); await publishStockProduct(db, f.lojaId, 'p', auth);
  const response = await publicRead(f.lojaId); assert.equal(response.status, 200);
  assert.equal((await response.json()).fields.quantidade.integerValue, '1');
  await executeStockCommand(db, intent(f.lojaId), auth);
  assert.equal((await f.base.collection('produtos').doc('p').get()).exists, false);
  await executeStockCommand(db, intent(f.lojaId, 'restock', 'r'), auth);
  assert.equal((await f.base.collection('produtos').doc('p').get()).data().quantidade, 5);
});
test('rollback to maintenance rejects a delayed sale retry; reactivation replays once', async () => {
  const f = await fixture(); await f.control.set(active);
  await executeStockCommand(db, intent(f.lojaId), auth);
  await executeStockCommand(db, intent(f.lojaId, 'restock', 'r'), auth);
  await f.control.set({...active, mode: 'maintenance'});
  await assert.rejects(executeStockCommand(db, intent(f.lojaId), auth), e => e.code === 'failed-precondition');
  await f.control.set(active);
  assert.equal((await executeStockCommand(db, intent(f.lojaId), auth)).alreadyApplied, true);
  assert.equal((await f.base.collection('estoque_produtos').doc('p').get()).data().quantidade, 5);
  assert.equal((await f.base.collection('produtos').doc('p').get()).data().quantidade, 5);
});
test('revoking trusted grant blocks both new intent and replay despite self-edited profile', async () => {
  const f = await fixture(); await f.control.set(active);
  await executeStockCommand(db, intent(f.lojaId), auth);
  await f.base.collection('stock_catalog_access').doc('owner').update({enabled: false});
  await db.collection('users').doc('owner').set({admin: true, role: 'admin', lojaId: f.lojaId});
  for (const command of [intent(f.lojaId), intent(f.lojaId, 'restock', 'r')]) {
    await assert.rejects(executeStockCommand(db, command, auth), e => e.code === 'permission-denied');
  }
  assert.equal((await f.base.collection('estoque_produtos').doc('p').get()).data().quantidade, 0);
});
