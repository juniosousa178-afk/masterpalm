/**
 * Consignment operations and the projection retry republish draft_produtos/produtos from canonical stock: every
 * category field (multi-path, the single-path triple, legacy text) must survive each step, sanitized and once.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {executeConsignmentCommand} from '../src/consignmentCommand.js';
import {handleProjectionRetryEvent} from '../src/consignmentCatalogProjection.js';
import {MAX_DISTINCT_PRODUCTS_PER_CONSIGNMENT, MAX_LINES, CODES} from '../src/consignmentProtocol.js';
import {createConsignmentTestDb} from './consignment-test-db.mjs';
import {
  A, CATEGORY_KEYS, EXPECTED_CATEGORY_FIELDS, LOJA_ID, PRODUCT_IDS, loadConsignmentSource, runConsignmentLifecycle,
} from './consignment-category-lifecycle.mjs';

const SRC = fileURLToPath(new URL('../src/', import.meta.url));
const docAt = (snapshot, col, id) => snapshot.get(`lojas/${LOJA_ID}/${col}/${id}`);
const lifecycle = loadConsignmentSource(SRC).then(runConsignmentLifecycle);
const stepOf = async name => (await lifecycle).steps.find(s => s.name === name);

function assertCategoryFields(snapshot, label) {
  for (const id of PRODUCT_IDS) {
    for (const col of ['draft_produtos', 'produtos']) {
      const doc = docAt(snapshot, col, id);
      assert.ok(doc, `${label}: ${col}/${id} exists`);
      const expected = EXPECTED_CATEGORY_FIELDS[id] ?? {};
      const actual = Object.fromEntries(CATEGORY_KEYS.filter(k => k in doc).map(k => [k, doc[k]]));
      assert.deepEqual(actual, expected, `${label}: ${col}/${id}`);
    }
  }
}

for (const [name, field] of [
  ['issue', 'CATEGORY_FIELDS_AFTER_ISSUE'], ['withdrawal', 'CATEGORY_FIELDS_AFTER_WITHDRAWAL'],
  ['retry', 'CATEGORY_FIELDS_AFTER_RETRY'], ['partialSale', 'CATEGORY_FIELDS_AFTER_PARTIAL_SALE'],
  ['staleRetry', 'CATEGORY_FIELDS_AFTER_STALE_RETRY'], ['settlement', 'CATEGORY_FIELDS_AFTER_SETTLEMENT'],
  ['commandReplay', 'CATEGORY_FIELDS_AFTER_REPLAY'],
]) {
  test(`${name}: every category field survives on draft and live`, async () => {
    assertCategoryFields((await stepOf(name)).snapshot, name);
    console.log(`${field}=true`);
  });
}

test('the projections actually ran: draft/live at the canonical stockRevision with the new quantity', async () => {
  for (const name of ['issue', 'withdrawal', 'retry', 'partialSale']) {
    const {snapshot} = await stepOf(name);
    const stock = docAt(snapshot, 'estoque_produtos', 'colar-cruz');
    for (const col of ['draft_produtos', 'produtos']) {
      assert.equal(docAt(snapshot, col, 'colar-cruz').catalogStockRevision, stock.stockRevision, `${name}: ${col}`);
    }
    assert.equal(docAt(snapshot, 'produtos', 'colar-cruz').quantidade, stock.quantidade, name);
  }
});

test('Colar Cruz: both paths, full membership, each id once, one product doc per collection', async () => {
  const {snapshot} = await stepOf('settlement');
  for (const col of ['draft_produtos', 'produtos']) {
    const doc = docAt(snapshot, col, 'colar-cruz');
    assert.deepEqual(doc.categoryAssignments, [A('fem_prata'), A('rel_cruz')]);
    assert.deepEqual(doc.categoryMembershipIds, ['fem', 'fem_colar', 'fem_prata', 'rel', 'rel_colar', 'rel_prata', 'rel_cruz']);
    assert.equal(new Set(doc.categoryMembershipIds).size, doc.categoryMembershipIds.length);
    assert.equal(new Set(doc.categoryAssignments.map(a => a.categoryId)).size, 2);
    assert.equal(doc.categoryId, 'fem_prata');
  }
  console.log('CONSIGNMENT_COLAR_CRUZ_FIXTURE_PASS=true');
});

test('dedup: projection never creates extra product docs', async () => {
  for (const {name, snapshot} of (await lifecycle).steps) {
    for (const col of ['estoque_produtos', 'draft_produtos', 'produtos']) {
      const ids = [...snapshot.keys()].filter(p => p.startsWith(`lojas/${LOJA_ID}/${col}/`)).map(p => p.split('/').pop());
      assert.deepEqual(ids.sort(), [...PRODUCT_IDS].sort(), `${name}: ${col}`);
    }
  }
  console.log('CONSIGNMENT_PROJECTED_PRODUCT_DEDUP_PASS=true');
});

test('public sanitization: forged stored paths dropped, internal keys stripped, membership re-derived', async () => {
  const {snapshot} = await stepOf('settlement');
  const live = docAt(snapshot, 'produtos', 'forjado');
  assert.deepEqual(live.categoryAssignments, [A('fem_prata')]);
  assert.deepEqual(live.categoryMembershipIds, ['fem', 'fem_colar', 'fem_prata']);
  const json = JSON.stringify(live.categoryAssignments);
  for (const leak of ['leak', 'ownerUid', 'custo', 'Forjado', 'outra-loja-cat']) assert.equal(json.includes(leak), false, leak);
  assert.equal(live.categoryMembershipIds.includes('outra-loja-cat'), false);
  console.log('CONSIGNMENT_CATEGORY_PUBLIC_SANITIZATION_MATCHES_1_0_144=true CONSIGNMENT_MEMBERSHIP_REDERIVED=true');
});

test('legacy products: triple-only, text-only and uncategorized keep exactly what they had', async () => {
  const {snapshot} = await stepOf('settlement');
  for (const col of ['draft_produtos', 'produtos']) {
    const tripleOnly = docAt(snapshot, col, 'triple-only');
    assert.equal(tripleOnly.categoryId, 'rel_cruz');
    assert.equal('categoryAssignments' in tripleOnly, false, 'no assignments invented');
    assert.equal(docAt(snapshot, col, 'text-only').categoria, 'Brincos');
    assert.equal(docAt(snapshot, col, 'text-only').subcategoria, 'Argola');
    assert.equal(docAt(snapshot, col, 'sem-categoria').publicadoNoCatalogo, true);
  }
  console.log('CONSIGNMENT_LEGACY_CATEGORY_COMPAT=true CONSIGNMENT_SINGLE_CATEGORY_PRESERVATION=true');
});

test('retry: projection-only, idempotent and stale-safe (zero canonical stock writes)', async () => {
  const {steps, db} = await lifecycle;
  const at = name => steps.findIndex(s => s.name === name);
  const opsBetween = (from, to) => db.commits.slice(steps[from].commitsSoFar, steps[to].commitsSoFar).flatMap(c => c.ops);
  for (const name of ['retry', 'replayRetry', 'staleRetry']) {
    const ops = opsBetween(at(name) - 1, at(name));
    assert.equal(ops.filter(o => o.path.includes('/estoque_produtos/')).length, 0, `${name} stock writes`);
    for (const o of ops) assert.match(o.path, /\/(draft_produtos|produtos|consignment_operations)\//, `${name}: ${o.path}`);
  }
  assert.equal(steps[at('retry')].result.written, 2);
  assert.equal(steps[at('replayRetry')].result.status, 'SKIPPED');
  assert.deepEqual(steps[at('replayRetry')].snapshot, steps[at('retry')].snapshot);
  assert.equal(steps[at('staleRetry')].result.written, 0);
  assert.deepEqual(steps[at('staleRetry')].snapshot.get(`lojas/${LOJA_ID}/produtos/colar-cruz`),
    steps[at('partialSale')].snapshot.get(`lojas/${LOJA_ID}/produtos/colar-cruz`), 'catalog not regressed');
  console.log('CONSIGNMENT_RETRY_IDEMPOTENT=true CONSIGNMENT_RETRY_STALE_SAFE=true CANONICAL_STOCK_WRITES=0');
});

test('150 categorized products (300 lines) issue and project with every path; 151st product still refused', async () => {
  assert.equal(MAX_DISTINCT_PRODUCTS_PER_CONSIGNMENT, 150);
  assert.equal(MAX_LINES, 300);
  const db = createConsignmentTestDb();
  const lojaId = 'cat150';
  const base = db.collection('lojas').doc(lojaId);
  db.seed(base, {ownerUid: 'owner', lojaId});
  db.seed(base.collection('consignment_control').doc('state'), {protocolVersion: 1, moduleEnabled: true});
  db.seed(base.collection('consignment_resellers').doc('r1'), {storeId: lojaId, resellerId: 'r1', displayName: 'R', active: true, notes: ''});
  const ids = Array.from({length: 151}, (_, i) => `colar-${String(i + 1).padStart(3, '0')}`);
  const cats = {categoryAssignments: [A('fem_prata'), A('rel_cruz')],
    categoryMembershipIds: ['fem', 'fem_colar', 'fem_prata', 'rel', 'rel_colar', 'rel_prata', 'rel_cruz']};
  for (const id of ids) {
    db.seed(base.collection('estoque_produtos').doc(id), {lojaId, stockRevision: 1, stockKind: 'variation', quantidade: 3,
      variacoes: {P: {'sem-cor': 2}, M: {'sem-cor': 1}}});
    db.seed(base.collection('draft_produtos').doc(id), {nome: id, publicadoNoCatalogo: true, preco: 50, ...cats});
    db.seed(base.collection('stock_catalog_dependencies').doc(id), {comboIds: []});
  }
  const owner = {uid: 'owner'};
  const line = (productId, size) => ({productId, qtySent: 1, unitSalePrice: 50, commissionType: 'PERCENTUAL',
    commissionValue: 10, variationKey: {size, color: 'sem-cor', extra: ''}});
  const lines = ids.slice(0, 150).flatMap(id => [line(id, 'P'), line(id, 'M')]);
  const cmd = (operation, operationId, payload) => ({protocolVersion: 1, lojaId, operation, operationId, consignmentId: 'big', payload});
  await executeConsignmentCommand(db, cmd('createDraft', 'draft_big', {resellerId: 'r1', notes: '', lines}), owner);
  const res = await executeConsignmentCommand(db, cmd('issue', 'issue_big', {}), owner);
  assert.equal(res.status, 'ISSUED');
  for (const id of ids.slice(0, 150)) {
    assert.equal(db.getData(base.collection('produtos').doc(id))?.quantidade, 1, id);
    for (const col of ['draft_produtos', 'produtos']) {
      const doc = db.getData(base.collection(col).doc(id));
      assert.deepEqual(doc.categoryAssignments, cats.categoryAssignments, `${col}/${id}`);
      assert.deepEqual(doc.categoryMembershipIds, cats.categoryMembershipIds, `${col}/${id}`);
    }
  }
  const op = db.getData(base.collection('consignment_operations').doc('issue_big'));
  assert.equal((await handleProjectionRetryEvent(db, {data: {data: () => op}, params: {lojaId, operationId: 'issue_big'}})).status, 'SKIPPED');
  const before = db.snapshot();
  await assert.rejects(executeConsignmentCommand(db, {protocolVersion: 1, lojaId, operation: 'createDraft', operationId: 'draft_over',
    consignmentId: 'over', payload: {resellerId: 'r1', notes: '', lines: ids.map(id => line(id, 'P'))}}, owner),
  e => e.consignmentCode === CODES.CONSIGNMENT_PRODUCT_LIMIT);
  assert.deepEqual(db.snapshot(), before);
  console.log('CONSIGNMENT_150_PRODUCT_BOUNDARY_UNCHANGED=true');
});
