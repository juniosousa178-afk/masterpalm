import test, {before, after} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {initializeTestEnvironment, assertFails, assertSucceeds} from '@firebase/rules-unit-testing';
import {disableNetwork, enableNetwork, setDoc, doc} from 'firebase/firestore';
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
      await db.doc(`lojas/rules_a/${col}/p`).set({quantidade: 0, stockRevision: 1, ativo: false});
    }
  });
});
after(async () => { await env?.cleanup(); });
const root = () => env.authenticatedContext('old-admin', {email: 'root@example.test'}).firestore();
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
  const db = env.unauthenticatedContext().firestore();
  await assertFails(db.doc('lojas/rules_a/produtos/p').set({ativo: true}));
  await assertSucceeds(db.doc('lojas/rules_a/produtos/p').get());
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
