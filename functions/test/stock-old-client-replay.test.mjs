/**
 * Replays the exact stockCatalogCommand payloads serialized by the 1.0.135
 * client (fixtures/old-client-1.0.135-stock-payloads.json, captured from
 * VendasService.registrarVendaMulti / editarVendaMulti through the callable
 * transport) against the current server on a NO_CONTROL store.
 * In-memory Firestore only — no production access.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {executeStockCommand} from '../src/stockCatalogCommands.js';
import {createConsignmentTestDb} from './consignment-test-db.mjs';

const owner = {uid: 'owner'};
const payloads = JSON.parse(readFileSync(new URL('./fixtures/old-client-1.0.135-stock-payloads.json', import.meta.url), 'utf8'));
const LOJA = payloads.CASE3_NEW_SALE[0].lojaId;

function seedNoControlStore() {
  const db = createConsignmentTestDb();
  const base = db.collection('lojas').doc(LOJA);
  db.seed(base, {ownerUid: 'owner', lojaId: LOJA});
  db.seed(base.collection('estoque_produtos').doc('prod-a-simple'), {
    nome: 'Produto A', stockKind: 'simple', stockRevision: 1, quantidade: 10, variacoes: {},
  });
  db.seed(base.collection('estoque_produtos').doc('prod-b-variation'), {
    nome: 'Produto B', stockKind: 'variation', stockRevision: 1, quantidade: 10,
    variacoes: {'12': {'sem-cor': 10}}, estoquePorTamanho: {'12': 10}, tamanhos: ['12'],
  });
  return {db, base};
}

function writesSince(db, from) {
  const ops = db.commits.slice(from).flatMap(c => c.ops);
  return {
    total: ops.length,
    stock: ops.filter(o => o.path.includes('/estoque_produtos/')).length,
    saleDoc: ops.filter(o => o.path.includes('/estoque_vendas/')).length,
  };
}

const qty = (db, base, id) => db.getData(base.collection('estoque_produtos').doc(id)).quantidade;
const cell = (db, base) => db.getData(base.collection('estoque_produtos').doc('prod-b-variation')).variacoes['12']['sem-cor'];

function only(name) {
  assert.equal(payloads[name].length, name === 'CASE2_EDIT_MIXED' ? 2 : 1);
  return payloads[name];
}

test('fixture shape: operationId formats produced by the 1.0.135 client', () => {
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
  assert.match(only('CASE3_NEW_SALE')[0].operationId, uuid);
  assert.match(only('CASE1_EDIT_INCREASE_ONLY')[0].operationId, /^editstock_.+_[0-9a-f]{64}$/);
  const [saleHalf, restockHalf] = only('CASE2_EDIT_MIXED');
  assert.match(saleHalf.operationId, /^editstock_.+_[0-9a-f]{64}_sale$/);
  assert.equal(saleHalf.kind, 'sale');
  assert.match(restockHalf.operationId, /^editstock_.+_[0-9a-f]{64}_restock$/);
  assert.equal(restockHalf.kind, 'restock');
});

test('CASE3 old-client new normal sale succeeds (NO_CONTROL)', async () => {
  const {db, base} = seedNoControlStore();
  const from = db.commits.length;
  const [cmd] = only('CASE3_NEW_SALE');
  const r = await executeStockCommand(db, cmd, owner);
  assert.equal(r.alreadyApplied, false);
  assert.equal(qty(db, base, 'prod-a-simple'), 9);
  assert.equal(cell(db, base), 9);
  const w = writesSince(db, from);
  console.log(`OLD_CLIENT_CASE3 opId=${cmd.operationId} stockWrites=${w.stock} saleDocWrites=${w.saleDoc} totalWrites=${w.total}`);
  assert.equal(w.stock, 2);
  assert.equal(w.saleDoc, 0);
});

test('CASE1 old-client increase-only edit (A 1→2) succeeds and is idempotent (NO_CONTROL)', async () => {
  const {db, base} = seedNoControlStore();
  await executeStockCommand(db, only('CASE1_SETUP_SALE')[0], owner);
  const from = db.commits.length;
  const [cmd] = only('CASE1_EDIT_INCREASE_ONLY');
  const r = await executeStockCommand(db, cmd, owner);
  assert.equal(r.alreadyApplied, false);
  assert.equal(qty(db, base, 'prod-a-simple'), 8);
  assert.equal(cell(db, base), 9);
  const w = writesSince(db, from);
  console.log(`OLD_CLIENT_CASE1 opId=${cmd.operationId} stockWrites=${w.stock} saleDocWrites=${w.saleDoc} totalWrites=${w.total}`);
  assert.equal(w.stock, 1);
  assert.equal(w.saleDoc, 0);
  const replay = await executeStockCommand(db, cmd, owner);
  assert.equal(replay.alreadyApplied, true);
  assert.equal(qty(db, base, 'prod-a-simple'), 8);
});

test('CASE2 old-client mixed edit (A 1→2, B 1→0): both halves rejected before any write (NO_CONTROL)', async () => {
  const {db, base} = seedNoControlStore();
  await executeStockCommand(db, only('CASE2_SETUP_SALE')[0], owner);
  const snap = db.snapshot();
  const from = db.commits.length;
  const [saleHalf, restockHalf] = only('CASE2_EDIT_MIXED');
  await assert.rejects(executeStockCommand(db, saleHalf, owner), e =>
    e.code === 'failed-precondition' &&
    e.details?.code === 'LEGACY_PROTOCOL_BLOCKED' &&
    e.details?.reason === 'LEGACY_SPLIT_EDIT_SALE_HALF');
  // The 1.0.135 client stops after the first rejection; the restock half is
  // replayed anyway to prove it cannot write on its own either.
  await assert.rejects(executeStockCommand(db, restockHalf, owner), e =>
    e.code === 'failed-precondition' && e.details?.code === 'LEGACY_PROTOCOL_BLOCKED');
  const w = writesSince(db, from);
  console.log(`OLD_CLIENT_CASE2 saleHalf=${saleHalf.operationId} restockHalf=${restockHalf.operationId} stockWrites=${w.stock} saleDocWrites=${w.saleDoc} totalWrites=${w.total}`);
  assert.equal(w.total, 0, 'OLD_CLIENT_MIXED_EDIT_PARTIAL_WRITE_COUNT');
  assert.deepEqual(db.snapshot(), snap);
  assert.equal(qty(db, base, 'prod-a-simple'), 9);
  assert.equal(cell(db, base), 9);
});
