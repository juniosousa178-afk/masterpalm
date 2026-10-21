/**
 * One product in several hierarchical category paths (categoryAssignments): server-derived paths, tenant/depth
 * checks, dedupe and ancestor normalization, legacy-client compatibility, the explicit limit, and survival through
 * stock commands, catalog publish and consignment writes/projection. One product doc, one stock, one price.
 * In-memory only (no production access).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import {executeStockCommand, publishStockProduct} from '../src/stockCatalogCommands.js';
import {executeCategoryCommand} from '../src/categoryCommand.js';
import {
  CATEGORY_ASSIGNMENTS_LIMIT_MESSAGE, CATEGORY_CODES, CATEGORY_DEPTH_LIMIT_MESSAGE, MAX_CATEGORY_ASSIGNMENTS,
  buildCategoryIndex, productCategoryIds,
} from '../src/categoryTree.js';
import {loadConsignmentStockRecords, persistConsignmentStock, applyExactConsignmentDelta} from '../src/consignmentStock.js';
import {projectConsignmentCatalog} from '../src/consignmentCatalogProjection.js';
import {createConsignmentTestDb} from './consignment-test-db.mjs';

const owner = {uid: 'owner'};
const PRODUCT_COLLECTIONS = ['estoque_produtos', 'draft_produtos', 'produtos'];
// Feminino > Colar > Colar Prata 925 | Religioso > Colar > Colar Prata 925 > Cruz | Presentes > Dia das Mães
const TREE = [
  ['fem', null, 'Feminino'], ['fem_colar', 'fem', 'Colar'], ['fem_prata', 'fem_colar', 'Colar Prata 925'],
  ['rel', null, 'Religioso'], ['rel_colar', 'rel', 'Colar'], ['rel_prata', 'rel_colar', 'Colar Prata 925'],
  ['rel_cruz', 'rel_prata', 'Cruz'],
  ['pres', null, 'Presentes'], ['pres_maes', 'pres', 'Dia das Mães'],
  ['mas', null, 'Masculino'],
];
const PATH = {
  fem_prata: [['fem', 'fem_colar', 'fem_prata'], ['Feminino', 'Colar', 'Colar Prata 925']],
  rel_cruz: [['rel', 'rel_colar', 'rel_prata', 'rel_cruz'], ['Religioso', 'Colar', 'Colar Prata 925', 'Cruz']],
  rel_prata: [['rel', 'rel_colar', 'rel_prata'], ['Religioso', 'Colar', 'Colar Prata 925']],
  pres_maes: [['pres', 'pres_maes'], ['Presentes', 'Dia das Mães']],
};
const A = id => ({categoryId: id, pathIds: PATH[id][0], pathNames: PATH[id][1]});
let seq = 0;

function seed({active = false, product = {}} = {}) {
  const db = createConsignmentTestDb();
  const lojaId = `multi_${++seq}`;
  const productId = 'colar-cruz';
  const base = db.collection('lojas').doc(lojaId);
  db.seed(base, {ownerUid: 'owner', lojaId});
  if (active) {
    db.seed(base.collection('stock_catalog_control').doc('state'), {protocolVersion: 1, mode: 'active', migrationComplete: true});
    db.seed(base.collection('stock_catalog_access').doc('owner'), {enabled: true,
      permissions: {sale: true, restock: true, adjust: true, editorial: true, publish: true, create: true}});
  }
  for (const [id, parentId, nome] of TREE) {
    db.seed(base.collection('categorias').doc(id), {id, lojaId, nome, parentId, isDeleted: false});
  }
  db.seed(base.collection('estoque_produtos').doc(productId), {
    lojaId, nome: 'Colar Cruz', categoria: 'Feminino', subcategoria: 'Colar',
    quantidade: 5, stockKind: 'simple', stockRevision: 1, variacoes: {}, preco: 120, ...product,
  });
  db.seed(base.collection('draft_produtos').doc(productId), {
    nome: 'Colar Cruz', categoria: 'Feminino', subcategoria: 'Colar', publicadoNoCatalogo: true, preco: 120, ...product,
  });
  db.seed(base.collection('stock_catalog_dependencies').doc(productId), {comboIds: []});
  return {db, base, lojaId, productId};
}

const read = (db, base, col, id) => db.getData(base.collection(col).doc(id));
const editorial = (lojaId, productId, operationId, patch) =>
  ({protocolVersion: 1, lojaId, kind: 'editorial', operationId, items: [{productId}], editorial: patch});
const assign = (ctx, op, leaves, extra = {}) => executeStockCommand(ctx.db, editorial(ctx.lojaId, ctx.productId, op, {
  categoryAssignments: leaves.map(id => ({categoryId: id})), ...extra}), owner);
const cats = (db, base) => [...db.snapshot()].filter(([p]) => p.startsWith(`${base.path}/categorias/`))
  .map(([p, data]) => ({id: p.split('/').pop(), data}));
const productDocs = (db, base) => [...db.snapshot().keys()].filter(p => p.startsWith(`${base.path}/estoque_produtos/`));

function assertAssignments(ctx, expected, label, cols = PRODUCT_COLLECTIONS) {
  for (const col of cols) {
    const doc = read(ctx.db, ctx.base, col, ctx.productId);
    assert.ok(doc, `${label}: ${col} exists`);
    assert.deepEqual(doc.categoryAssignments, expected, `${label}: ${col}.categoryAssignments`);
    assert.deepEqual(doc.categoryMembershipIds, [...new Set(expected.flatMap(a => a.pathIds))], `${label}: ${col}.membership`);
    const primary = expected[0];
    assert.equal(doc.categoryId, primary?.categoryId ?? '', `${label}: ${col}.categoryId mirrors the first path`);
    assert.deepEqual(doc.categoryPathIds, primary?.pathIds ?? [], `${label}: ${col}.categoryPathIds`);
    assert.deepEqual(doc.categoryPathNames, primary?.pathNames ?? [], `${label}: ${col}.categoryPathNames`);
  }
}

async function rejectsWithoutWrites(ctx, promise, check) {
  const before = ctx.db.snapshot();
  await assert.rejects(promise, check);
  assert.deepEqual(ctx.db.snapshot(), before);
}

test('Colar Cruz in Feminino > Colar > Colar Prata 925 and Religioso > … > Cruz appears in all 7 nodes, one product', async () => {
  const ctx = seed();
  await assign(ctx, 'a1', ['fem_prata', 'rel_cruz']);
  assertAssignments(ctx, [A('fem_prata'), A('rel_cruz')], 'fixture');
  const index = buildCategoryIndex(cats(ctx.db, ctx.base), ctx.lojaId);
  const ids = productCategoryIds(index, read(ctx.db, ctx.base, 'produtos', ctx.productId));
  for (const id of ['fem', 'fem_colar', 'fem_prata', 'rel', 'rel_colar', 'rel_prata', 'rel_cruz']) {
    assert.equal(ids.has(id), true, id);
  }
  assert.equal(ids.size, 7);
  assert.equal(ids.has('mas'), false);
  assert.equal(productDocs(ctx.db, ctx.base).length, 1, 'no duplicated product doc');
  const stock = read(ctx.db, ctx.base, 'estoque_produtos', ctx.productId);
  assert.equal(stock.quantidade, 5);
  assert.equal(stock.stockRevision, 1, 'category change is not a stock effect');
});

test('three independent branches: canonical count 1, membership is the union', async () => {
  const ctx = seed();
  await assign(ctx, 'a1', ['fem_prata', 'rel_cruz', 'pres_maes']);
  assertAssignments(ctx, [A('fem_prata'), A('rel_cruz'), A('pres_maes')], 'three branches');
  assert.equal(read(ctx.db, ctx.base, 'produtos', ctx.productId).categoryMembershipIds.length, 9);
  assert.equal(productDocs(ctx.db, ctx.base).length, 1);
});

test('paths are server-derived: forged client pathIds/pathNames are ignored', async () => {
  const ctx = seed();
  await executeStockCommand(ctx.db, editorial(ctx.lojaId, ctx.productId, 'f1', {categoryAssignments: [
    {categoryId: 'rel_cruz', pathIds: ['fem', 'rel_cruz'], pathNames: ['Forjado', 'Cruz']},
  ]}), owner);
  assertAssignments(ctx, [A('rel_cruz')], 'forged');
});

test('unknown leaf, deleted leaf and fake ids are refused before any write', async () => {
  const ctx = seed();
  ctx.db.seed(ctx.base.collection('categorias').doc('arquivada'), {lojaId: ctx.lojaId, nome: 'X', parentId: null, isDeleted: true});
  for (const leaf of ['nao_existe', 'arquivada']) {
    await rejectsWithoutWrites(ctx, assign(ctx, `u_${leaf}`, ['fem_prata', leaf]), e => {
      assert.equal(e.code, 'not-found');
      assert.equal(e.details?.code, CATEGORY_CODES.NOT_FOUND);
      return true;
    });
  }
  for (const bad of [[{categoryId: 'a/b'}], [{}], ['fem'], {categoryId: 'fem'}]) {
    await rejectsWithoutWrites(ctx, executeStockCommand(ctx.db, editorial(ctx.lojaId, ctx.productId, `b_${++seq}`,
      {categoryAssignments: bad}), owner), e => e.code === 'invalid-argument');
  }
});

test('categories of another store are never assignable', async () => {
  const ctx = seed();
  const other = ctx.db.collection('lojas').doc('outra-loja');
  ctx.db.seed(other.collection('categorias').doc('alheia'), {lojaId: 'outra-loja', nome: 'Alheia', parentId: null});
  await rejectsWithoutWrites(ctx, assign(ctx, 'x1', ['alheia']), e => e.code === 'not-found');
  ctx.db.seed(ctx.base.collection('categorias').doc('intrusa'), {lojaId: 'outra-loja', nome: 'Intrusa', parentId: null});
  await rejectsWithoutWrites(ctx, assign(ctx, 'x2', ['intrusa']), e => {
    assert.equal(e.code, 'permission-denied');
    assert.equal(e.details?.code, CATEGORY_CODES.CROSS_TENANT);
    return true;
  });
  await rejectsWithoutWrites(ctx, executeStockCommand(ctx.db, editorial(ctx.lojaId, ctx.productId, 'x3', {
    categoryAssignments: [{categoryId: 'fem_prata', lojaId: 'outra-loja'}]}), owner), e => e.code === 'permission-denied');
});

test('each path may be 1 to 6 levels; a 7th-level node is never assignable', async () => {
  const ctx = seed();
  const ids = ['d1', 'd2', 'd3', 'd4', 'd5', 'd6', 'd7'];
  ids.forEach((id, i) => ctx.db.seed(ctx.base.collection('categorias').doc(id),
    {lojaId: ctx.lojaId, nome: `N${i + 1}`, parentId: i ? ids[i - 1] : null}));
  await assign(ctx, 'd_ok', ['d6', 'mas']);
  const stored = read(ctx.db, ctx.base, 'produtos', ctx.productId).categoryAssignments;
  assert.deepEqual(stored.map(a => a.pathIds.length), [6, 1]);
  await rejectsWithoutWrites(ctx, assign(ctx, 'd_bad', ['d7']), e => {
    assert.equal(e.details?.code, CATEGORY_CODES.DEPTH_LIMIT);
    assert.equal(e.message, CATEGORY_DEPTH_LIMIT_MESSAGE);
    return true;
  });
});

test('duplicate leaves collapse and a redundant ancestor is replaced by the more specific path', async () => {
  const ctx = seed();
  await assign(ctx, 'n1', ['rel_cruz', 'rel_cruz', 'fem_prata', 'rel_prata', 'rel', 'fem_prata']);
  assertAssignments(ctx, [A('rel_cruz'), A('fem_prata')], 'normalized');
  await assign(ctx, 'n2', ['rel_prata', 'pres_maes']);
  assertAssignments(ctx, [A('rel_prata'), A('pres_maes')], 'independent branches kept');
});

test('edit roundtrip: add, remove and keep paths; removing one only removes that link', async () => {
  const ctx = seed();
  await assign(ctx, 'e1', ['fem_prata']);
  await assign(ctx, 'e2', ['fem_prata', 'rel_cruz', 'pres_maes']);
  assertAssignments(ctx, [A('fem_prata'), A('rel_cruz'), A('pres_maes')], 'added');
  const before = read(ctx.db, ctx.base, 'estoque_produtos', ctx.productId);
  await assign(ctx, 'e3', ['fem_prata', 'pres_maes']);
  assertAssignments(ctx, [A('fem_prata'), A('pres_maes')], 'removed one');
  const after = read(ctx.db, ctx.base, 'estoque_produtos', ctx.productId);
  for (const k of ['quantidade', 'stockRevision', 'variacoes', 'preco', 'nome', 'stockKind']) {
    assert.deepEqual(after[k], before[k], `stock field ${k} unchanged`);
  }
  assert.equal(productDocs(ctx.db, ctx.base).length, 1);
  await assign(ctx, 'e4', []);
  assertAssignments(ctx, [], 'zero categories');
});

test('more than the limit is refused explicitly (never truncated); exactly the limit is accepted', async () => {
  const ctx = seed();
  const many = Array.from({length: MAX_CATEGORY_ASSIGNMENTS + 1}, (_, i) => `r${i}`);
  many.forEach(id => ctx.db.seed(ctx.base.collection('categorias').doc(id), {lojaId: ctx.lojaId, nome: id, parentId: null}));
  await rejectsWithoutWrites(ctx, assign(ctx, 'lim1', many), e => {
    assert.equal(e.code, 'invalid-argument');
    assert.equal(e.message, CATEGORY_ASSIGNMENTS_LIMIT_MESSAGE);
    return true;
  });
  await assign(ctx, 'lim2', many.slice(0, MAX_CATEGORY_ASSIGNMENTS));
  assert.equal(read(ctx.db, ctx.base, 'produtos', ctx.productId).categoryAssignments.length, MAX_CATEGORY_ASSIGNMENTS);
});

test('categoryMembershipIds is server-derived: a client-sent value is refused', async () => {
  const ctx = seed();
  await rejectsWithoutWrites(ctx, executeStockCommand(ctx.db, editorial(ctx.lojaId, ctx.productId, 'm1', {
    categoryAssignments: [{categoryId: 'fem_prata'}], categoryMembershipIds: ['mas']}), owner),
  e => e.code === 'invalid-argument');
});

test('legacy single-category product: read as one path, converted only on its next category save', async () => {
  const legacy = {categoryId: 'fem_prata', categoryPathIds: PATH.fem_prata[0], categoryPathNames: PATH.fem_prata[1]};
  const ctx = seed({product: legacy});
  const index = buildCategoryIndex(cats(ctx.db, ctx.base), ctx.lojaId);
  assert.deepEqual([...productCategoryIds(index, read(ctx.db, ctx.base, 'estoque_produtos', ctx.productId))].sort(),
    ['fem', 'fem_colar', 'fem_prata']);
  await executeStockCommand(ctx.db, {protocolVersion: 1, lojaId: ctx.lojaId, kind: 'sale', operationId: 's1',
    items: [{productId: ctx.productId, quantity: 1}]}, owner);
  await executeStockCommand(ctx.db, editorial(ctx.lojaId, ctx.productId, 'n1', {nome: 'Colar Cruz Prata'}), owner);
  for (const col of PRODUCT_COLLECTIONS) {
    const doc = read(ctx.db, ctx.base, col, ctx.productId);
    assert.equal('categoryAssignments' in doc, false, `${col}: no mass/automatic migration`);
    assert.equal(doc.categoryId, 'fem_prata');
  }
  await executeStockCommand(ctx.db, editorial(ctx.lojaId, ctx.productId, 'n2', {...legacy}), owner);
  assertAssignments(ctx, [A('fem_prata')], 'converted on legitimate save');
});

test('old APK (triple only): same leaf keeps every path; new leaf replaces the first; empty removes only the first', async () => {
  const ctx = seed();
  await assign(ctx, 'o0', ['fem_prata', 'rel_cruz', 'pres_maes']);
  const triple = id => ({categoryId: id, categoryPathIds: PATH[id][0], categoryPathNames: PATH[id][1]});
  await executeStockCommand(ctx.db, editorial(ctx.lojaId, ctx.productId, 'o1', {nome: 'Colar', ...triple('fem_prata')}), owner);
  assertAssignments(ctx, [A('fem_prata'), A('rel_cruz'), A('pres_maes')], 'old client unrelated edit');
  const mas = {categoryId: 'mas', pathIds: ['mas'], pathNames: ['Masculino']};
  await executeStockCommand(ctx.db, editorial(ctx.lojaId, ctx.productId, 'o2',
    {categoryId: 'mas', categoryPathIds: ['mas'], categoryPathNames: ['Masculino']}), owner);
  assertAssignments(ctx, [mas, A('rel_cruz'), A('pres_maes')], 'old client picks a new leaf');
  await executeStockCommand(ctx.db, editorial(ctx.lojaId, ctx.productId, 'o3', triple('rel_prata')), owner);
  assertAssignments(ctx, [A('rel_cruz'), A('pres_maes')],
    'old client picks an ancestor of an existing path: the more specific path stays');
  await executeStockCommand(ctx.db, editorial(ctx.lojaId, ctx.productId, 'o4',
    {categoryId: '', categoryPathIds: [], categoryPathNames: []}), owner);
  assertAssignments(ctx, [A('pres_maes')], 'old client clears its category: only the first path goes');
});

test('a renamed category shows the current name on the next save (ids are stable)', async () => {
  const ctx = seed();
  await assign(ctx, 'r1', ['fem_prata', 'rel_cruz']);
  await executeCategoryCommand(ctx.db, {protocolVersion: 1, lojaId: ctx.lojaId, operation: 'rename',
    operationId: 'ren1', payload: {target: {id: 'rel_colar'}, nome: 'Colares'}}, owner);
  const index = buildCategoryIndex(cats(ctx.db, ctx.base), ctx.lojaId);
  assert.equal(productCategoryIds(index, read(ctx.db, ctx.base, 'produtos', ctx.productId)).has('rel_colar'), true);
  await executeStockCommand(ctx.db, editorial(ctx.lojaId, ctx.productId, 'r2',
    {nome: 'Colar Cruz', categoryAssignments: [{categoryId: 'fem_prata'}, {categoryId: 'rel_cruz'}]}), owner);
  const stored = read(ctx.db, ctx.base, 'produtos', ctx.productId).categoryAssignments;
  assert.deepEqual(stored[1].pathNames, ['Religioso', 'Colares', 'Colar Prata 925', 'Cruz']);
  assert.deepEqual(stored[1].pathIds, PATH.rel_cruz[0]);
});

test('archive checks every path of every product', async () => {
  const ctx = seed();
  await assign(ctx, 'ar1', ['fem_prata', 'rel_cruz']);
  const archive = id => executeCategoryCommand(ctx.db, {protocolVersion: 1, lojaId: ctx.lojaId, operation: 'archive',
    operationId: `arc_${++seq}`, payload: {target: {id}}}, owner);
  await assert.rejects(archive('rel_cruz'), e => e.categoryCode === CATEGORY_CODES.HAS_PRODUCTS);
  await assert.rejects(archive('fem_prata'), e => e.categoryCode === CATEGORY_CODES.HAS_PRODUCTS);
  await assign(ctx, 'ar2', ['fem_prata']);
  await archive('rel_cruz');
  assert.equal(read(ctx.db, ctx.base, 'categorias', 'rel_cruz').isDeleted, true);
});

test('the tree read happens only when the command carries category fields', async () => {
  const ctx = seed();
  ctx.db.queryReads.length = 0;
  await executeStockCommand(ctx.db, editorial(ctx.lojaId, ctx.productId, 'q1', {nome: 'Colar'}), owner);
  await executeStockCommand(ctx.db, {protocolVersion: 1, lojaId: ctx.lojaId, kind: 'sale', operationId: 'q2',
    items: [{productId: ctx.productId, quantity: 1}]}, owner);
  assert.equal(ctx.db.queryReads.some(q => q.endsWith('/categorias')), false);
  await assign(ctx, 'q3', ['fem_prata']);
  assert.equal(ctx.db.queryReads.filter(q => q.endsWith('/categorias')).length, 1);
});

for (const active of [false, true]) {
  const mode = active ? 'ACTIVE' : 'NO_CONTROL';
  test(`three paths survive sale, restock, adjust, unrelated edits, replace and publish (${mode})`, async () => {
    const ctx = seed({active});
    const three = [A('fem_prata'), A('rel_cruz'), A('pres_maes')];
    await assign(ctx, 'p0', ['fem_prata', 'rel_cruz', 'pres_maes']);
    const cmd = (kind, operationId, item = {quantity: 1}) => executeStockCommand(ctx.db,
      {protocolVersion: 1, lojaId: ctx.lojaId, kind, operationId, items: [{productId: ctx.productId, ...item}]}, owner);

    await cmd('sale', 's1');
    assertAssignments(ctx, three, 'sale');
    assert.equal(read(ctx.db, ctx.base, 'estoque_produtos', ctx.productId).quantidade, 4);
    if (active) {
      await cmd('restock', 'r1');
      assertAssignments(ctx, three, 'restock');
      const rev = read(ctx.db, ctx.base, 'estoque_produtos', ctx.productId).stockRevision;
      await cmd('adjust', 'adj1', {quantity: 9, expectedRevision: rev});
      assertAssignments(ctx, three, 'adjust');
    }
    await executeStockCommand(ctx.db, editorial(ctx.lojaId, ctx.productId, 'ed2', {nome: 'Colar Cruz', preco: 130}), owner);
    assertAssignments(ctx, three, 'unrelated editorial');
    const rev = read(ctx.db, ctx.base, 'estoque_produtos', ctx.productId).stockRevision;
    await executeStockCommand(ctx.db, {protocolVersion: 1, lojaId: ctx.lojaId, kind: 'replace', operationId: 'rep1',
      items: [{productId: ctx.productId, expectedRevision: rev}], editorial: {nome: 'Colar Cruz', publicadoNoCatalogo: true},
      definition: {quantidade: 3, tipoProduto: 'simples'}}, owner);
    assertAssignments(ctx, three, 'replace without category fields');
    await publishStockProduct(ctx.db, ctx.lojaId, ctx.productId, owner);
    assertAssignments(ctx, three, 'catalog publish');
    assert.equal(productDocs(ctx.db, ctx.base).length, 1);
  });
}

test('create with several paths stores them canonically', async () => {
  const ctx = seed();
  const newId = 'novo-colar';
  await executeStockCommand(ctx.db, {protocolVersion: 1, lojaId: ctx.lojaId, kind: 'create', operationId: 'c1',
    items: [{productId: newId}], definition: {quantidade: 2, tipoProduto: 'simples'},
    editorial: {nome: 'Novo', publicadoNoCatalogo: true, categoryAssignments: [{categoryId: 'rel_cruz'}, {categoryId: 'fem_prata'}]}}, owner);
  assertAssignments({...ctx, productId: newId}, [A('rel_cruz'), A('fem_prata')], 'create');
});

test('a draft that lost the paths is restored from canonical stock by publish', async () => {
  const ctx = seed();
  await assign(ctx, 'd1', ['fem_prata', 'rel_cruz']);
  const draftRef = ctx.base.collection('draft_produtos').doc(ctx.productId);
  const stripped = {...read(ctx.db, ctx.base, 'draft_produtos', ctx.productId)};
  for (const k of ['categoryAssignments', 'categoryMembershipIds', 'categoryId', 'categoryPathIds', 'categoryPathNames']) {
    delete stripped[k];
  }
  ctx.db.seed(draftRef, stripped);
  await publishStockProduct(ctx.db, ctx.lojaId, ctx.productId, owner);
  assertAssignments(ctx, [A('fem_prata'), A('rel_cruz')], 'restored');
});

test('consignment stock write and post-commit projection keep every path (protected code unchanged)', async () => {
  const ctx = seed({active: true});
  await assign(ctx, 'cs0', ['fem_prata', 'rel_cruz', 'pres_maes']);
  const three = [A('fem_prata'), A('rel_cruz'), A('pres_maes')];
  await ctx.db.runTransaction(async tx => {
    const records = await loadConsignmentStockRecords(tx, ctx.base, [ctx.productId]);
    const r = records.get(ctx.productId);
    r.data = applyExactConsignmentDelta(r.data, 'simple', {size: '', color: '', extra: ''}, -2);
    const persisted = persistConsignmentStock(tx, ctx.base, records, 'cons_op_1', -1);
    for (const write of persisted.writes) write();
  });
  const stock = read(ctx.db, ctx.base, 'estoque_produtos', ctx.productId);
  assert.equal(stock.quantidade, 3);
  assert.deepEqual(stock.categoryAssignments, three);
  ctx.db.seed(ctx.base.collection('consignment_operations').doc('cons_op_1'),
    {projection: {status: 'PENDING', productIds: [ctx.productId]}});
  const result = await projectConsignmentCatalog(ctx.db, ctx.lojaId, 'cons_op_1');
  assert.equal(result.status, 'DONE');
  assertAssignments(ctx, three, 'consignment');
  assert.equal(read(ctx.db, ctx.base, 'produtos', ctx.productId).quantidade, 3);
});

test('public projection carries only category ids/names, never internal data', async () => {
  const ctx = seed();
  await assign(ctx, 'pub1', ['fem_prata', 'rel_cruz']);
  const live = read(ctx.db, ctx.base, 'produtos', ctx.productId);
  for (const a of live.categoryAssignments) assert.deepEqual(Object.keys(a).sort(), ['categoryId', 'pathIds', 'pathNames']);
  assert.ok(live.categoryMembershipIds.every(id => typeof id === 'string'));
  const json = JSON.stringify({a: live.categoryAssignments, m: live.categoryMembershipIds});
  for (const leak of ['owner', 'uid', 'custo', 'lojaId', 'legacyNames', 'sortOrder']) assert.equal(json.includes(leak), false, leak);
});
