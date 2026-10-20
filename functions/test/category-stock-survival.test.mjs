/**
 * Hierarchical category fields (categoryId/categoryPathIds/categoryPathNames) survive every server path that
 * re-projects a product: editorial, sale, restock, adjust, replace, catalog publish and consignment projection.
 * In-memory only (no production access).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import {executeStockCommand, publishStockProduct} from '../src/stockCatalogCommands.js';
import {projectCatalog} from '../src/catalogStockProjection.js';
import {createConsignmentTestDb} from './consignment-test-db.mjs';

const owner = {uid: 'owner'};
const TRIPLE = Object.freeze({
  categoryId: 'cat_aneis',
  categoryPathIds: ['cat_fem', 'cat_rel', 'cat_aneis'],
  categoryPathNames: ['Feminino', 'Religioso', 'Anéis'],
});
const KEYS = Object.keys(TRIPLE);
let seq = 0;

function seed({active = false} = {}) {
  const db = createConsignmentTestDb();
  const lojaId = `cat_srv_${++seq}`;
  const productId = 'anel';
  const base = db.collection('lojas').doc(lojaId);
  db.seed(base, {ownerUid: 'owner', lojaId});
  if (active) {
    db.seed(base.collection('stock_catalog_control').doc('state'), {protocolVersion: 1, mode: 'active', migrationComplete: true});
    db.seed(base.collection('stock_catalog_access').doc('owner'), {enabled: true,
      permissions: {sale: true, restock: true, adjust: true, editorial: true, publish: true, create: true}});
  }
  db.seed(base.collection('estoque_produtos').doc(productId), {
    lojaId, nome: 'Anel Nossa Senhora', categoria: 'Feminino', subcategoria: 'Religioso',
    quantidade: 5, stockKind: 'simple', stockRevision: 1, variacoes: {},
  });
  db.seed(base.collection('draft_produtos').doc(productId), {
    nome: 'Anel Nossa Senhora', categoria: 'Feminino', subcategoria: 'Religioso', publicadoNoCatalogo: true, preco: 90,
  });
  db.seed(base.collection('stock_catalog_dependencies').doc(productId), {comboIds: []});
  return {db, base, lojaId, productId};
}

const read = (db, base, col, id) => db.getData(base.collection(col).doc(id));
const cmd = (lojaId, productId, kind, operationId, extra = {}) =>
  ({protocolVersion: 1, lojaId, kind, operationId, items: [{productId, quantity: 1}], ...extra});

function assertTriple(db, base, productId, label) {
  for (const col of ['estoque_produtos', 'draft_produtos', 'produtos']) {
    const doc = read(db, base, col, productId);
    assert.ok(doc, `${label}: ${col} exists`);
    for (const k of KEYS) assert.deepEqual(doc[k], TRIPLE[k], `${label}: ${col}.${k}`);
  }
}

for (const active of [false, true]) {
  const mode = active ? 'ACTIVE' : 'NO_CONTROL';

  test(`category fields survive editorial, sale, restock, adjust, other edits and publish (${mode})`, async () => {
    const {db, base, lojaId, productId} = seed({active});
    await executeStockCommand(db, {protocolVersion: 1, lojaId, kind: 'editorial', operationId: 'ed1',
      items: [{productId}], editorial: {...TRIPLE}}, owner);
    assertTriple(db, base, productId, 'editorial');

    await executeStockCommand(db, cmd(lojaId, productId, 'sale', 's1'), owner);
    assertTriple(db, base, productId, 'sale');
    assert.equal(read(db, base, 'estoque_produtos', productId).quantidade, 4);

    if (active) {
      await executeStockCommand(db, cmd(lojaId, productId, 'restock', 'r1'), owner);
      assertTriple(db, base, productId, 'restock');
    }

    await executeStockCommand(db, {protocolVersion: 1, lojaId, kind: 'editorial', operationId: 'ed2',
      items: [{productId}], editorial: {nome: 'Anel N. Senhora', preco: 95}}, owner);
    assertTriple(db, base, productId, 'unrelated editorial');

    await publishStockProduct(db, lojaId, productId, owner);
    assertTriple(db, base, productId, 'catalog publish');
  });

  test(`replace keeps category fields sent with the definition (${mode})`, async () => {
    const {db, base, lojaId, productId} = seed({active});
    await executeStockCommand(db, {protocolVersion: 1, lojaId, kind: 'replace', operationId: 'rep1',
      items: [{productId, expectedRevision: 1}], editorial: {nome: 'Anel', publicadoNoCatalogo: true, ...TRIPLE},
      definition: {quantidade: 3, tipoProduto: 'simples'}}, owner);
    assertTriple(db, base, productId, 'replace');
  });
}

test('a draft that lost the fields (older projection) is restored from canonical stock on the next projection', async () => {
  const {db, base, lojaId, productId} = seed();
  await executeStockCommand(db, {protocolVersion: 1, lojaId, kind: 'editorial', operationId: 'ed1',
    items: [{productId}], editorial: {...TRIPLE}}, owner);
  const draftRef = base.collection('draft_produtos').doc(productId);
  const stripped = {...read(db, base, 'draft_produtos', productId)};
  for (const k of KEYS) delete stripped[k];
  db.seed(draftRef, stripped);
  await publishStockProduct(db, lojaId, productId, owner);
  assertTriple(db, base, productId, 'restored by publish');
});

test('consignment-style projection (stock + draft) keeps the fields on draft and live', () => {
  const stock = {stockKind: 'simple', quantidade: 2, stockRevision: 3, variacoes: {}, ...TRIPLE};
  const draft = {nome: 'Anel', publicadoNoCatalogo: true, ...TRIPLE};
  const p = projectCatalog(stock, draft, 'anel');
  for (const k of KEYS) {
    assert.deepEqual(p.draft[k], TRIPLE[k]);
    assert.deepEqual(p.live[k], TRIPLE[k]);
    assert.deepEqual(p.stock[k], TRIPLE[k]);
  }
});

test('incoherent category fields are refused before any write', async () => {
  const {db, lojaId, productId} = seed();
  const before = db.snapshot();
  for (const bad of [
    {...TRIPLE, categoryId: 'cat_other'},
    {...TRIPLE, categoryPathNames: ['Feminino', 'Religioso']},
    {...TRIPLE, categoryPathIds: ['a', 'b', 'c', 'd', 'e', 'f', 'cat_aneis'],
      categoryPathNames: ['a', 'b', 'c', 'd', 'e', 'f', 'g']},
  ]) {
    await assert.rejects(executeStockCommand(db, {protocolVersion: 1, lojaId, kind: 'editorial',
      operationId: `bad_${++seq}`, items: [{productId}], editorial: bad}, owner), e => e.code === 'invalid-argument');
  }
  assert.deepEqual(db.snapshot(), before);
});
