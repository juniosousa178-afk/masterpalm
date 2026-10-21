// Bulk "Remover desconto no Pix" through real Firestore transactions; every assertion reads the stored documents.
// Runs only against the local emulator: FIRESTORE_EMULATOR_HOST=127.0.0.1:8187 (project demo-stock-catalog).
import test, {after} from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {Firestore} from 'firebase-admin/firestore';
import {executeStockCommand, publishStockProduct} from '../src/stockCatalogCommands.js';
import {BULK_PIX_KIND, MAX_PRODUCTS_PER_BULK_PIX_OPERATION} from '../src/stockCatalogBulkPix.js';

const enabled = process.env.FIRESTORE_EMULATOR_HOST === '127.0.0.1:8187';
const skip = enabled ? false : 'Firestore emulator (127.0.0.1:8187) not running';
const db = enabled ? new Firestore({projectId: 'demo-stock-catalog'}) : null;
after(() => db?.terminate());

const owner = {uid: 'owner'};
const PIX = 'percentualDescontoPix';
const COLS = ['estoque_produtos', 'draft_produtos', 'produtos'];
const runId = Date.now().toString(36);
let seq = 0;

const multiCategory = {
  categoryAssignments: [
    {categoryId: 'rel_cruz', pathIds: ['rel', 'rel_cruz'], pathNames: ['Religioso', 'Cruz']},
    {categoryId: 'fem_prata', pathIds: ['fem', 'fem_prata'], pathNames: ['Feminino', 'Prata']},
  ],
  categoryMembershipIds: ['rel', 'rel_cruz', 'fem', 'fem_prata'],
  categoryId: 'rel_cruz', categoryPathIds: ['rel', 'rel_cruz'], categoryPathNames: ['Religioso', 'Cruz'],
};
const commercial = (id, price) => ({
  nome: `Produto ${id}`, preco: price, precoFinal: price, precoUnitario: price, custoReal: 31.5,
  sku: `SKU-${id}`, codigoBarras: `789${id}`, imagens: [`https://img.example/${id}.jpg`], descricao: `Descrição ${id}`,
  emPromocao: true, percentualPromo: 20, valorPromo: 0, divideSemJuros: true, maxParcelasSemJuros: 6,
  publicadoNoCatalogo: true, categoria: 'Religiosos', subcategoria: 'Cruz',
});

/** spec: {id: {price, pix, kind?, extra?}} */
async function seedStore(lojaId, products, {ownerUid = 'owner'} = {}) {
  const base = db.collection('lojas').doc(lojaId);
  const batch = db.batch();
  batch.set(base, {ownerUid, lojaId});
  batch.set(base.collection('stock_catalog_control').doc('state'), {protocolVersion: 1, mode: 'active', migrationComplete: true});
  batch.set(base.collection('stock_catalog_access').doc(ownerUid), {enabled: true,
    permissions: {sale: true, restock: true, adjust: true, editorial: true, publish: true, create: true}});
  for (const [id, p] of Object.entries(products)) {
    const editorial = {...commercial(id, p.price), [PIX]: p.pix, ...(p.extra ?? {})};
    const stock = p.kind === 'variation'
      ? {stockKind: 'variation', quantidade: 5, variacoes: {P: {Azul: 2, Rosa: 1}, M: {Azul: 2}},
        estoquePorTamanho: {P: 3, M: 2}, tamanhos: ['P', 'M'], cores: ['Azul', 'Rosa'],
        historicalStockCells: {'G|Verde': {removedAt: 'x'}}}
      : {stockKind: 'simple', quantidade: 4, variacoes: {}};
    batch.set(base.collection('estoque_produtos').doc(id), {lojaId, stockRevision: 7, stockOperationId: `prev_${id}`,
      ...stock, ...editorial, ...(p.stockExtra ?? {})});
    batch.set(base.collection('draft_produtos').doc(id), {...editorial, catalogStockRevision: 7});
    batch.set(base.collection('produtos').doc(id), {...editorial, quantidade: stock.quantidade, catalogStockRevision: 7});
    batch.set(base.collection('stock_catalog_dependencies').doc(id), {comboIds: []});
  }
  await batch.commit();
  return base;
}

async function newStore(products, options) {
  const lojaId = `pixemu_${runId}_${++seq}`;
  return {lojaId, base: await seedStore(lojaId, products, options)};
}

/** Every product document (data + updateTime) plus every operation doc of a store. */
async function capture(base) {
  const out = new Map();
  for (const col of [...COLS, 'stock_catalog_operations']) {
    for (const snap of (await base.collection(col).get()).docs) {
      out.set(`${col}/${snap.id}`, {data: snap.data(), updateTime: snap.updateTime.toMillis()});
    }
  }
  return out;
}

/** Classifies writes between two captures: product doc writes vs operation (audit) writes. */
function writesBetween(before, afterSnap) {
  const product = [];
  const audit = [];
  for (const [key, value] of afterSnap) {
    const prev = before.get(key);
    if (prev && prev.updateTime === value.updateTime) continue;
    (key.startsWith('stock_catalog_operations/') ? audit : product).push(key);
  }
  return {product: product.sort(), audit: audit.sort()};
}

const strip = (doc, keys = [PIX, 'updatedAt']) => Object.fromEntries(Object.entries(doc).filter(([k]) => !keys.includes(k)));
const bulk = (lojaId, operationId, productIds) => ({protocolVersion: 1, lojaId, operationId, kind: BULK_PIX_KIND, productIds});
const opId = n => `pixrm_emu_${runId}_${String(n).padStart(4, '0')}`;
const range = (n, prefix = 'p') => Array.from({length: n}, (_, i) => `${prefix}${String(i).padStart(2, '0')}`);

/** Same algorithm as lib/services/bulk_pix_discount_service.dart (lotes + operationId). */
const clientBatches = (ids, size = MAX_PRODUCTS_PER_BULK_PIX_OPERATION) => {
  const sorted = [...new Set(ids)].sort();
  const out = [];
  for (let i = 0; i < sorted.length; i += size) out.push(sorted.slice(i, i + size));
  return out;
};
const clientOperationId = (lojaId, bulkId, productIds) =>
  `pixrm_${createHash('sha256').update(`${lojaId}|${bulkId}|${[...productIds].sort().join(',')}`).digest('hex')}`;

function assertNarrow(before, afterSnap, updatedIds) {
  for (const id of updatedIds) {
    for (const col of COLS) {
      const a = before.get(`${col}/${id}`).data;
      const b = afterSnap.get(`${col}/${id}`).data;
      assert.equal(b[PIX], 0, `${col}/${id} Pix`);
      assert.deepEqual(strip(b), strip(a), `${col}/${id} other fields`);
    }
  }
}

async function rejectsWithoutWrites(base, command, predicate) {
  const before = await capture(base);
  await assert.rejects(executeStockCommand(db, command, owner), predicate);
  const w = writesBetween(before, await capture(base));
  assert.deepEqual(w, {product: [], audit: []});
}

test('emulator §6 1 product: preco=100 Pix=10 -> preco=100 Pix=0, only Pix+updatedAt written', {skip}, async () => {
  const {lojaId, base} = await newStore({A: {price: 100, pix: 10}});
  const before = await capture(base);
  const r = await executeStockCommand(db, bulk(lojaId, opId(1), ['A']), owner);
  const afterSnap = await capture(base);
  assert.deepEqual([r.updatedCount, r.noopCount, r.failedCount], [1, 0, 0]);
  assertNarrow(before, afterSnap, ['A']);
  const stock = afterSnap.get('estoque_produtos/A').data;
  assert.equal(stock.preco, 100);
  assert.equal(stock.precoFinal, 100);
  assert.equal(stock.quantidade, 4);
  assert.equal(stock.stockRevision, 7, 'STOCK_REVISION_CHANGE=0');
  const w = writesBetween(before, afterSnap);
  assert.deepEqual(w.product, COLS.map(c => `${c}/A`).sort());
  assert.deepEqual(w.audit, [`stock_catalog_operations/${opId(1)}`]);
  const op = afterSnap.get(`stock_catalog_operations/${opId(1)}`).data;
  assert.equal(op.kind, BULK_PIX_KIND);
  assert.equal(op.actorUid, 'owner');
  assert.equal(op.lojaId, lojaId);
  assert.deepEqual([op.requestedCount, op.updatedCount, op.noopCount, op.failedCount], [1, 1, 0, 0]);
  assert.ok(op.createdAt);
});

test('emulator §7/§21 30 products mixed: 15 updated, 15 already-zero not written (NOOP_PRODUCT_WRITES=0)', {skip}, async () => {
  const ids = range(30);
  const spec = Object.fromEntries(ids.map((id, i) => [id, {price: 100 + i, pix: i % 2 === 0 ? 10 : 0}]));
  const {lojaId, base} = await newStore(spec);
  const before = await capture(base);
  const r = await executeStockCommand(db, bulk(lojaId, opId(2), [...ids].reverse()), owner);
  const afterSnap = await capture(base);
  const withPix = ids.filter((_, i) => i % 2 === 0);
  const zero = ids.filter((_, i) => i % 2 === 1);
  assert.deepEqual(r.updatedProductIds, withPix);
  assert.deepEqual(r.noopProductIds, zero);
  const w = writesBetween(before, afterSnap);
  assert.equal(w.product.filter(k => zero.some(id => k.endsWith(`/${id}`))).length, 0, 'NOOP_PRODUCT_WRITES');
  assert.equal(w.product.length, withPix.length * 3);
  assert.equal(w.audit.length, 1, 'AUDIT_OPERATION_WRITES');
  assertNarrow(before, afterSnap, withPix);
  for (const id of ids) assert.equal(afterSnap.get(`estoque_produtos/${id}`).data.quantidade, 4);
});

test('emulator §8 31 products in one request rejected; client chunking 30+1 completes all 31', {skip}, async () => {
  const ids = range(31);
  const {lojaId, base} = await newStore(Object.fromEntries(ids.map(id => [id, {price: 50, pix: 5}])));
  await rejectsWithoutWrites(base, bulk(lojaId, opId(3), ids),
    e => e.code === 'resource-exhausted' && e.details?.code === 'BULK_PIX_TOO_MANY_PRODUCTS');
  const before = await capture(base);
  const batches = clientBatches([...ids].reverse());
  assert.deepEqual(batches.map(b => b.length), [30, 1]);
  const results = [];
  for (const b of batches) {
    results.push(await executeStockCommand(db, bulk(lojaId, clientOperationId(lojaId, 'pixbulk_emu31', b), b), owner));
  }
  assert.equal(results.reduce((n, r) => n + r.updatedCount, 0), 31);
  const afterSnap = await capture(base);
  assertNarrow(before, afterSnap, ids);
  assert.equal(writesBetween(before, afterSnap).audit.length, 2);
});

test('emulator §7 only already-zero products: no product write, one audit record', {skip}, async () => {
  const {lojaId, base} = await newStore({Z1: {price: 10, pix: 0}, Z2: {price: 20, pix: 0}});
  const before = await capture(base);
  const r = await executeStockCommand(db, bulk(lojaId, opId(4), ['Z1', 'Z2']), owner);
  assert.deepEqual([r.updatedCount, r.noopCount], [0, 2]);
  const w = writesBetween(before, await capture(base));
  assert.deepEqual(w.product, []);
  assert.deepEqual(w.audit, [`stock_catalog_operations/${opId(4)}`]);
});

test('emulator §8 duplicate / missing / deleted / invalid ID: whole request rejected, zero writes', {skip}, async () => {
  const {lojaId, base} = await newStore({
    A: {price: 100, pix: 10}, B: {price: 200, pix: 5},
    D: {price: 90, pix: 10, stockExtra: {pendingSoftDelete: true}},
    T: {price: 90, pix: 10},
  });
  await base.collection('exclusao_produto').doc('T').set({p: true});
  await rejectsWithoutWrites(base, bulk(lojaId, opId(5), ['A', 'B', 'A']),
    e => e.code === 'invalid-argument' && e.details?.code === 'BULK_PIX_DUPLICATE_PRODUCT');
  await rejectsWithoutWrites(base, bulk(lojaId, opId(6), ['A', 'B', 'nao_existe']),
    e => e.code === 'failed-precondition' && e.details?.reason === 'NOT_FOUND' && e.details?.productId === 'nao_existe');
  await rejectsWithoutWrites(base, bulk(lojaId, opId(7), ['A', 'D']),
    e => e.details?.reason === 'DELETED' && e.details?.productId === 'D');
  await rejectsWithoutWrites(base, bulk(lojaId, opId(8), ['A', 'T']),
    e => e.details?.reason === 'DELETED' && e.details?.productId === 'T');
  await rejectsWithoutWrites(base, bulk(lojaId, opId(9), ['A', 'a/b']), e => e.code === 'invalid-argument');
  await rejectsWithoutWrites(base, {...bulk(lojaId, opId(10), ['A']), preco: 1}, e => e.code === 'invalid-argument');
});

test('emulator §12 cross-tenant: foreign ID or foreign store fails closed, neither store written', {skip}, async () => {
  const a = await newStore({A: {price: 100, pix: 10}});
  const b = await newStore({X: {price: 300, pix: 20}}, {ownerUid: 'ownerB'});
  const beforeB = await capture(b.base);
  await rejectsWithoutWrites(a.base, bulk(a.lojaId, opId(11), ['A', 'X']),
    e => e.details?.reason === 'NOT_FOUND' && e.details?.productId === 'X');
  await rejectsWithoutWrites(b.base, bulk(b.lojaId, opId(12), ['X']), e => e.code === 'permission-denied');
  assert.deepEqual(writesBetween(beforeB, await capture(b.base)), {product: [], audit: []});
  assert.equal((await b.base.collection('estoque_produtos').doc('X').get()).data()[PIX], 20);
});

test('emulator §10 replay (any order) is idempotent; same operationId with other payload is blocked', {skip}, async () => {
  const {lojaId, base} = await newStore({A: {price: 100, pix: 10}, B: {price: 200, pix: 5}, C: {price: 150, pix: 0}});
  const first = await executeStockCommand(db, bulk(lojaId, opId(13), ['A', 'B', 'C']), owner);
  const before = await capture(base);
  const replay = await executeStockCommand(db, bulk(lojaId, opId(13), ['C', 'A', 'B']), owner);
  assert.equal(replay.alreadyApplied, true);
  assert.deepEqual(replay.updatedProductIds, first.updatedProductIds);
  assert.deepEqual(replay.noopProductIds, first.noopProductIds);
  assert.deepEqual(writesBetween(before, await capture(base)), {product: [], audit: []});
  await rejectsWithoutWrites(base, bulk(lojaId, opId(13), ['A', 'B']),
    e => e.code === 'already-exists' && e.details?.code === 'OPERATION_PAYLOAD_CONFLICT');
  assert.equal(clientOperationId('loja1', 'pixbulk_vec', ['c', 'a', 'b']),
    'pixrm_c864d44979827ec6aeacb0396ad1ee2206bae864632bee82dd6d275a51f31eb7', 'Dart/JS chunk id vector');
});

test('emulator concurrent sale + unrelated editorial: no lost update, Pix removed', {skip}, async () => {
  const {lojaId, base} = await newStore({A: {price: 100, pix: 10}, B: {price: 200, pix: 5}, C: {price: 150, pix: 3}});
  const [r] = await Promise.all([
    executeStockCommand(db, bulk(lojaId, opId(14), ['A', 'B']), owner),
    executeStockCommand(db, {protocolVersion: 1, lojaId, kind: 'sale', operationId: `sale_${runId}`,
      items: [{productId: 'A', quantity: 1}]}, owner),
    executeStockCommand(db, {protocolVersion: 1, lojaId, kind: 'editorial', operationId: `ed_${runId}`,
      items: [{productId: 'C'}], editorial: {nome: 'Produto C renomeado'}}, owner),
  ]);
  assert.equal(r.updatedCount, 2);
  const a = (await base.collection('estoque_produtos').doc('A').get()).data();
  assert.equal(a[PIX], 0);
  assert.equal(a.quantidade, 3, 'sale kept');
  assert.equal(a.stockRevision, 8, 'only the sale bumps stockRevision');
  assert.equal(a.preco, 100);
  const c = (await base.collection('estoque_produtos').doc('C').get()).data();
  assert.equal(c.nome, 'Produto C renomeado');
  assert.equal(c[PIX], 3, 'not selected, untouched');
});

test('emulator multi-category + variation products: categories, variations, historical cells unchanged; publish keeps Pix=0', {skip}, async () => {
  const {lojaId, base} = await newStore({
    M: {price: 90, pix: 12, extra: multiCategory},
    V: {price: 120, pix: 8, kind: 'variation'},
  });
  const before = await capture(base);
  await executeStockCommand(db, bulk(lojaId, opId(15), ['M', 'V']), owner);
  const afterSnap = await capture(base);
  assertNarrow(before, afterSnap, ['M', 'V']);
  for (const col of COLS) {
    const m = afterSnap.get(`${col}/M`).data;
    for (const k of Object.keys(multiCategory)) assert.deepEqual(m[k], multiCategory[k], `${col}/M ${k}`);
  }
  const v = afterSnap.get('estoque_produtos/V').data;
  assert.deepEqual(v.variacoes, {P: {Azul: 2, Rosa: 1}, M: {Azul: 2}});
  assert.deepEqual(v.historicalStockCells, {'G|Verde': {removedAt: 'x'}});
  assert.equal(v.quantidade, 5);

  await publishStockProduct(db, lojaId, 'M', owner);
  const live = (await base.collection('produtos').doc('M').get()).data();
  assert.equal(live[PIX], 0, 'PUBLIC_CATALOG_PIX_DISCOUNT_REMOVED');
  assert.equal(live.preco, 90);
  assert.equal(live.emPromocao, true);
  assert.equal(live.percentualPromo, 20);
  assert.deepEqual(live.categoryAssignments.map(x => x.categoryId), ['rel_cruz', 'fem_prata']);
  assert.deepEqual([...live.categoryMembershipIds].sort(), [...multiCategory.categoryMembershipIds].sort());
});
