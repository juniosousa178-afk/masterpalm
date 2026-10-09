/**
 * codigoBarras travels in the editorial payload and lands on estoque_produtos only.
 * In-memory only (no production writes).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import {executeStockCommand} from '../src/stockCatalogCommands.js';
import {splitEditorialPayload, MAX_PRODUCT_CODE_LENGTH} from '../src/catalogStockProjection.js';
import {createConsignmentTestDb} from './consignment-test-db.mjs';

const owner = {uid: 'owner'};
let seq = 0;

function seed({active = false} = {}) {
  const db = createConsignmentTestDb();
  const lojaId = `idf_${++seq}`;
  const productId = `${lojaId}-anel-gota-verde-agua-t-20`;
  const base = db.collection('lojas').doc(lojaId);
  db.seed(base, {ownerUid: 'owner', lojaId});
  if (active) {
    db.seed(base.collection('stock_catalog_control').doc('state'), {protocolVersion: 1, mode: 'active', migrationComplete: true});
    db.seed(base.collection('stock_catalog_access').doc('owner'), {enabled: true, permissions: {editorial: true, adjust: true}});
  }
  db.seed(base.collection('estoque_produtos').doc(productId), {
    lojaId, nome: 'Anel Gota Verde Água T.20 Semijoia', codigoBarras: 'AN32SM',
    quantidade: 1, stockKind: 'simple', stockRevision: 6, stockOperationId: 'issue_prev', variacoes: {},
  });
  db.seed(base.collection('draft_produtos').doc(productId), {nome: 'Anel Gota Verde Água T.20 Semijoia', publicadoNoCatalogo: true, preco: 89});
  db.seed(base.collection('produtos').doc(productId), {nome: 'Anel Gota Verde Água T.20 Semijoia', quantidade: 1, preco: 89});
  db.seed(base.collection('stock_catalog_dependencies').doc(productId), {comboIds: []});
  return {db, base, lojaId, productId};
}

const editorial = (lojaId, productId, operationId, patch) => ({
  protocolVersion: 1, lojaId, kind: 'editorial', operationId, items: [{productId}], editorial: patch,
});
const read = (db, base, col, id) => db.getData(base.collection(col).doc(id));

for (const active of [false, true]) {
  test(`editorial codigoBarras updates canonical stock only (${active ? 'ACTIVE' : 'NO_CONTROL'})`, async () => {
    const {db, base, lojaId, productId} = seed({active});
    await executeStockCommand(db, editorial(lojaId, productId, 'ed1', {nome: 'Anel Gota Verde Água T.20 Semijoia', codigoBarras: '  AN45SM - 103 '}), owner);
    const stock = read(db, base, 'estoque_produtos', productId);
    assert.equal(stock.codigoBarras, 'AN45SM - 103');
    assert.equal(stock.quantidade, 1);
    assert.equal(stock.stockRevision, 6, 'identity change is not a stock effect');
    assert.equal(stock.stockOperationId, 'issue_prev', 'editorial keeps stock lineage');
    assert.equal('codigoBarras' in read(db, base, 'draft_produtos', productId), false);
    const live = read(db, base, 'produtos', productId);
    assert.ok(live);
    assert.equal('codigoBarras' in live, false);
  });
}

test('replay of the same editorial operation is idempotent', async () => {
  const {db, base, lojaId, productId} = seed();
  const cmd = editorial(lojaId, productId, 'ed-replay', {codigoBarras: 'AN45SM-103'});
  await executeStockCommand(db, cmd, owner);
  const before = db.snapshot();
  const replay = await executeStockCommand(db, cmd, owner);
  assert.equal(replay.alreadyApplied, true);
  assert.deepEqual(db.snapshot(), before);
  assert.equal(read(db, base, 'estoque_produtos', productId).codigoBarras, 'AN45SM-103');
});

test('editorial without codigoBarras keeps the existing code', async () => {
  const {db, base, lojaId, productId} = seed();
  await executeStockCommand(db, editorial(lojaId, productId, 'ed-name', {nome: 'Outro nome'}), owner);
  assert.equal(read(db, base, 'estoque_produtos', productId).codigoBarras, 'AN32SM');
});

for (const [label, value] of [
  ['empty', '   '],
  ['non-string', 103],
  ['too long', 'X'.repeat(MAX_PRODUCT_CODE_LENGTH + 1)],
  ['control char', 'AN45\nSM'],
]) {
  test(`invalid codigoBarras rejected before any write: ${label}`, async () => {
    const {db, lojaId, productId} = seed();
    const before = db.snapshot();
    await assert.rejects(
      executeStockCommand(db, editorial(lojaId, productId, `bad-${seq}`, {codigoBarras: value}), owner),
      e => e.code === 'invalid-argument',
    );
    assert.deepEqual(db.snapshot(), before);
  });
}

test('other protected fields are still rejected', async () => {
  const {db, lojaId, productId} = seed();
  await assert.rejects(
    executeStockCommand(db, editorial(lojaId, productId, 'ed-qty', {quantidade: 99}), owner),
    e => e.code === 'invalid-argument',
  );
  assert.throws(() => splitEditorialPayload({stockRevision: 1}), e => e.code === 'invalid-argument');
});

test('replace and create persist codigoBarras on estoque_produtos', async () => {
  const {db, base, lojaId, productId} = seed();
  await executeStockCommand(db, {
    protocolVersion: 1, lojaId, kind: 'replace', operationId: 'rep1',
    items: [{productId, expectedRevision: 6}],
    editorial: {nome: 'Anel', codigoBarras: 'AN45SM'},
    definition: {quantidade: 2, tipoProduto: 'simples'},
  }, owner);
  const replaced = read(db, base, 'estoque_produtos', productId);
  assert.equal(replaced.codigoBarras, 'AN45SM');
  assert.equal(replaced.quantidade, 2);

  const newId = `${lojaId}-novo`;
  await executeStockCommand(db, {
    protocolVersion: 1, lojaId, kind: 'create', operationId: 'cre1',
    items: [{productId: newId}],
    editorial: {nome: 'Novo', publicadoNoCatalogo: false, codigoBarras: 'NV01SM'},
    definition: {quantidade: 1, tipoProduto: 'simples'},
  }, owner);
  assert.equal(read(db, base, 'estoque_produtos', newId).codigoBarras, 'NV01SM');
});

test('editorial on another store product is denied (tenant isolation)', async () => {
  const a = seed();
  const b = seed();
  const db = a.db;
  db.seed(db.collection('lojas').doc(b.lojaId), {ownerUid: 'someone-else', lojaId: b.lojaId});
  await assert.rejects(
    executeStockCommand(db, editorial(b.lojaId, a.productId, 'x-tenant', {codigoBarras: 'AN45SM'}), owner),
    e => e.code === 'permission-denied',
  );
  assert.equal(read(db, a.base, 'estoque_produtos', a.productId).codigoBarras, 'AN32SM');
});
