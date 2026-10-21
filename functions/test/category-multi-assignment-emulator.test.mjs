// Multi-category paths through real Firestore transactions (category tree read before any write).
// Runs only against the local emulator: FIRESTORE_EMULATOR_HOST=127.0.0.1:8187 (project demo-stock-catalog).
import test, {after} from 'node:test';
import assert from 'node:assert/strict';
import {Firestore} from 'firebase-admin/firestore';
import {executeStockCommand, publishStockProduct} from '../src/stockCatalogCommands.js';

const enabled = process.env.FIRESTORE_EMULATOR_HOST === '127.0.0.1:8187';
const skip = enabled ? false : 'Firestore emulator (127.0.0.1:8187) not running';
const db = enabled ? new Firestore({projectId: 'demo-stock-catalog'}) : null;
after(() => db?.terminate());

const owner = {uid: 'owner'};
const runId = Date.now().toString(36);
let seq = 0;
const TREE = [
  ['cat_fem', 'Feminino', null], ['cat_fcol', 'Colar', 'cat_fem'], ['cat_fp925', 'Colar Prata 925', 'cat_fcol'],
  ['cat_rel', 'Religioso', null], ['cat_rcol', 'Colar', 'cat_rel'], ['cat_rp925', 'Colar Prata 925', 'cat_rcol'],
  ['cat_cruz', 'Cruz', 'cat_rp925'],
];
const SEVEN = TREE.map(([id]) => id);

async function seed() {
  const lojaId = `multicat_${runId}_${++seq}`;
  const base = db.collection('lojas').doc(lojaId);
  const batch = db.batch();
  batch.set(base.collection('stock_catalog_control').doc('state'), {protocolVersion: 1, mode: 'active', migrationComplete: true});
  batch.set(base.collection('stock_catalog_access').doc('owner'), {enabled: true,
    permissions: {sale: true, restock: true, adjust: true, editorial: true, publish: true, create: true}});
  for (const [id, nome, parentId] of TREE) {
    batch.set(base.collection('categorias').doc(id), {id, lojaId, nome, parentId, isDeleted: false});
  }
  batch.set(base.collection('estoque_produtos').doc('p'), {
    lojaId, nome: 'Colar Cruz', categoria: 'Feminino', subcategoria: 'Colar',
    quantidade: 5, stockKind: 'simple', stockRevision: 1, variacoes: {},
  });
  batch.set(base.collection('draft_produtos').doc('p'), {nome: 'Colar Cruz', publicadoNoCatalogo: true, preco: 90});
  batch.set(base.collection('stock_catalog_dependencies').doc('p'), {comboIds: []});
  await batch.commit();
  return {base, lojaId};
}

const data = async (base, col) => (await base.collection(col).doc('p').get()).data();

test('emulator: two paths derived in the transaction, survive sale and publish, forged path rejected', {skip}, async () => {
  const {base, lojaId} = await seed();
  await executeStockCommand(db, {protocolVersion: 1, lojaId, kind: 'editorial', operationId: 'ed1', items: [{productId: 'p'}],
    editorial: {categoryAssignments: [
      {categoryId: 'cat_fp925', pathIds: ['forged'], pathNames: ['Forjado']},
      {categoryId: 'cat_cruz'},
    ]}}, owner);
  const after1 = await data(base, 'estoque_produtos');
  assert.deepEqual(after1.categoryAssignments.map(a => a.pathIds), [
    ['cat_fem', 'cat_fcol', 'cat_fp925'],
    ['cat_rel', 'cat_rcol', 'cat_rp925', 'cat_cruz'],
  ]);
  assert.deepEqual([...after1.categoryMembershipIds].sort(), [...SEVEN].sort());
  assert.equal(after1.categoryId, 'cat_fp925');

  await executeStockCommand(db, {protocolVersion: 1, lojaId, kind: 'sale', operationId: 's1', items: [{productId: 'p', quantity: 1}]}, owner);
  await publishStockProduct(db, lojaId, 'p', owner);
  for (const col of ['estoque_produtos', 'draft_produtos', 'produtos']) {
    const doc = await data(base, col);
    assert.equal(doc.categoryAssignments.length, 2, col);
    assert.equal(doc.categoryMembershipIds.length, 7, col);
  }
  assert.equal((await data(base, 'estoque_produtos')).quantidade, 4);

  await assert.rejects(executeStockCommand(db, {protocolVersion: 1, lojaId, kind: 'editorial', operationId: 'ed2',
    items: [{productId: 'p'}], editorial: {categoryAssignments: [{categoryId: 'cat_inexistente'}]}}, owner),
  e => e.code === 'not-found' || /not-found/.test(String(e.code)));
  assert.equal((await data(base, 'estoque_produtos')).categoryAssignments.length, 2);
});
