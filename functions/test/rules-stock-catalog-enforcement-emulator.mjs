import test, {before, after} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {initializeTestEnvironment, assertFails, assertSucceeds} from '@firebase/rules-unit-testing';
import {disableNetwork, enableNetwork, setDoc, doc, collection, getDocs, query, where, limit} from 'firebase/firestore';
if (process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:8187') throw new Error('Only the local emulator is authorized');
const projectId = 'demo-stock-catalog';
const rules = readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8');
const options = {projectId, firestore: {host: '127.0.0.1', port: 8187, rules}};
let env;
before(async () => {
  env = await initializeTestEnvironment(options);
  await env.withSecurityRulesDisabled(async ctx => {
    const db = ctx.firestore();
    await db.doc('usuarios/root@example.test').set({tipo: 'admin'});
    await db.doc('lojas/rules_a/stock_catalog_control/state').set({protocolVersion: 1, mode: 'active', migrationComplete: true});
    await db.doc('lojas/rules_a/stock_catalog_access/owner').set({enabled: true, permissions: {sale: true}});
    for (const col of ['estoque_produtos','produtos','draft_produtos','produtos_publicos']) {
      await db.doc(`lojas/rules_a/${col}/p`).set({quantidade: 0, stockRevision: 1, ativo: true});
    }
    // Emergency public-read matrix fixtures (recovery plan A–D).
    await db.doc('lojas/rules_nocontrol/produtos/p').set({ativo: true, nome: 'nocontrol'});
    await db.doc('lojas/rules_nocontrol/estoque_produtos/p').set({quantidade: 1, stockRevision: 0});
    await db.doc('lojas/rules_inactive/stock_catalog_control/state').set({protocolVersion: 1, mode: 'inactive', migrationComplete: false});
    await db.doc('lojas/rules_inactive/produtos/p').set({ativo: true, nome: 'inactive'});
    await db.doc('lojas/rules_inactive/estoque_produtos/p').set({quantidade: 1, stockRevision: 0});
    await db.doc('lojas/rules_inactive').set({ownerUid: 'inactive-owner'});
    await db.doc('lojas/rules_nocontrol').set({ownerUid: 'nocontrol-owner'});
    await db.doc('lojas/rules_migrated_inactive/stock_catalog_control/state').set({protocolVersion: 1, mode: 'inactive', migrationComplete: true});
    await db.doc('lojas/rules_migrated_inactive/produtos/p').set({ativo: true, nome: 'migrated-inactive'});
    await db.doc('lojas/rules_migrated_inactive/estoque_produtos/p').set({quantidade: 1, stockRevision: 0});
    await db.doc('lojas/rules_migrated_inactive').set({ownerUid: 'migrated-owner'});
  });
});
after(async () => { await env?.cleanup(); });
const root = () => env.authenticatedContext('old-admin', {email: 'root@example.test'}).firestore();
const unauth = () => env.unauthenticatedContext().firestore();
async function listAtivoProdutos(lojaId) {
  const db = unauth();
  const modular = db._delegate ?? db;
  return getDocs(query(collection(modular, `lojas/${lojaId}/produtos`), where('ativo', '==', true), limit(10)));
}
for (const col of ['estoque_produtos','produtos','draft_produtos','produtos_publicos','produtos_rascunho','products','produtos_draft']) {
  test(`legacy admin direct protected CRUD denied: ${col}`, async () => {
    const ref = root().doc(`lojas/rules_a/${col}/p`);
    await assertFails(ref.set({quantidade: 1, ativo: true, stockRevision: 999}));
    await assertFails(ref.set({quantidade: 0}, {merge: true}));
    await assertFails(ref.delete());
  });
}
test('revision-only and availability-only spoof denied', async () => {
  await assertFails(root().doc('lojas/rules_a/estoque_produtos/p').update({stockRevision: 999}));
  await assertFails(root().doc('lojas/rules_a/produtos/p').update({ativo: true}));
});
test('self-promoted profile cannot create own stock grant or mutate stock', async () => {
  const ctx = env.authenticatedContext('self', {email: 'self@example.test'}), db = ctx.firestore();
  // Reproduce the existing profile weakness without changing unrelated auth rules.
  await assertSucceeds(db.doc('usuarios/self@example.test').set({tipo: 'admin'}));
  await assertFails(db.doc('lojas/rules_a/stock_catalog_access/self').set({enabled: true, permissions: {sale: true}}));
  await assertFails(db.doc('lojas/rules_a/estoque_produtos/p').set({quantidade: 50, stockRevision: 2}));
});
test('authorized owner still cannot use direct write; cross-store grant denied', async () => {
  const db = env.authenticatedContext('owner').firestore();
  await assertSucceeds(db.doc('lojas/rules_a/estoque_produtos/p').get());
  await assertFails(db.doc('lojas/rules_a/estoque_produtos/p').update({quantidade: 9}));
  await assertFails(db.doc('lojas/rules_b/stock_catalog_access/owner').set({enabled: true}));
});
test('unauthenticated mutation denied; final active public read allowed', async () => {
  const db = unauth();
  await assertFails(db.doc('lojas/rules_a/produtos/p').set({ativo: true}));
  await assertSucceeds(db.doc('lojas/rules_a/produtos/p').get());
});
// --- Emergency public-read regression tests (recovery plan EXPECTED_NEW_TEST_COUNT=6) ---
test('emergency public GET no-control ALLOW', async () => {
  await assertSucceeds(unauth().doc('lojas/rules_nocontrol/produtos/p').get());
  // Baseline resource!=null: nonexistent remains denied.
  await assertFails(unauth().doc('lojas/rules_nocontrol/produtos/missing').get());
});
test('emergency public LIST no-control ALLOW', async () => {
  const snap = await assertSucceeds(listAtivoProdutos('rules_nocontrol'));
  assert.ok(snap.size >= 1);
});
test('emergency public LIST migrated-inactive ALLOW', async () => {
  const snap = await assertSucceeds(listAtivoProdutos('rules_migrated_inactive'));
  assert.ok(snap.size >= 1);
});
test('emergency public LIST ACTIVE ALLOW', async () => {
  const snap = await assertSucceeds(listAtivoProdutos('rules_a'));
  assert.ok(snap.size >= 1);
});
test('emergency public GET inactive-with-control ALLOW', async () => {
  await assertSucceeds(unauth().doc('lojas/rules_inactive/produtos/p').get());
  // Protected stock write remains DENY on inactive stores.
  await assertFails(root().doc('lojas/rules_inactive/estoque_produtos/p').set({quantidade: 9, stockRevision: 1}));
});
test('emergency public GET ACTIVE ALLOW', async () => {
  await assertSucceeds(unauth().doc('lojas/rules_a/produtos/p').get());
});
test('inactive same-store member can READ estoque_produtos; write still DENY', async () => {
  const db = env.authenticatedContext('inactive-owner').firestore();
  await assertSucceeds(db.doc('lojas/rules_inactive/estoque_produtos/p').get());
  await assertFails(db.doc('lojas/rules_inactive/estoque_produtos/p').update({quantidade: 9}));
});
test('no-control same-store member can READ estoque_produtos', async () => {
  const db = env.authenticatedContext('nocontrol-owner').firestore();
  await assertSucceeds(db.doc('lojas/rules_nocontrol/estoque_produtos/p').get());
});
test('other-store cannot READ inactive estoque_produtos; unauth DENY', async () => {
  const other = env.authenticatedContext('stranger').firestore();
  await assertFails(other.doc('lojas/rules_inactive/estoque_produtos/p').get());
  await assertFails(unauth().doc('lojas/rules_inactive/estoque_produtos/p').get());
});
test('ACTIVE store private stock read still requires grant (owner without grant DENY)', async () => {
  // rules_a has grant for 'owner' only — stranger denied; granted owner allowed.
  const stranger = env.authenticatedContext('stranger').firestore();
  await assertFails(stranger.doc('lojas/rules_a/estoque_produtos/p').get());
  const granted = env.authenticatedContext('owner').firestore();
  await assertSucceeds(granted.doc('lojas/rules_a/estoque_produtos/p').get());
});
test('control, operation marker, dependency and tombstone cannot be spoofed', async () => {
  for (const path of ['stock_catalog_control/state','stock_catalog_operations/fake','stock_catalog_dependencies/p','exclusao_produto/p','estoque_baixa_pagamento/fake']) {
    await assertFails(root().doc(`lojas/rules_a/${path}`).set({enabled: true, status: 'applied'}));
  }
});
test('queued legacy offline write is denied after new Rules become effective', async () => {
  const old = await initializeTestEnvironment({...options, firestore: {...options.firestore, rules: 'rules_version = "2"; service cloud.firestore { match /databases/{database}/documents { match /{doc=**} { allow read, write: if true; } } }'}});
  const client = old.authenticatedContext('queued-old').firestore();
  const modular = client._delegate ?? client;
  await disableNetwork(modular);
  const pending = setDoc(doc(modular, 'lojas/rules_a/produtos/p'), {quantidade: 100, ativo: true});
  const outcome = pending.then(() => ({ok: true}), error => ({ok: false, code: error.code}));
  const upgraded = await initializeTestEnvironment(options);
  await enableNetwork(modular);
  const result = await outcome;
  assert.equal(result.ok, false); assert.equal(result.code, 'permission-denied');
  await old.cleanup(); await upgraded.cleanup();
});
