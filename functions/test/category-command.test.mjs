/** Hierarchical categories (up to 6 levels). In-memory Firestore, no production access. */
import test from 'node:test';
import assert from 'node:assert/strict';
import {executeCategoryCommand} from '../src/categoryCommand.js';
import {
  CATEGORY_CODES, CATEGORY_DEPTH_LIMIT_MESSAGE, CATEGORY_HAS_CHILDREN_MESSAGE, MAX_CATEGORY_DEPTH,
  buildCategoryIndex, normalizeCategoryName, productCategoryIds, validateCategoryMove,
} from '../src/categoryTree.js';
import {EDITORIAL_FIELDS, validateEditorial} from '../src/catalogStockProjection.js';
import {createConsignmentTestDb} from './consignment-test-db.mjs';

const owner = {uid: 'owner'};
const LEVELS = ['Feminino', 'Religioso', 'Anéis', 'Nossa Senhora', 'Prata 925', 'Cravejados'];
let seq = 0;

function seedStore(db = createConsignmentTestDb(), lojaId = `loja_${++seq}`, ownerUid = 'owner') {
  const base = db.collection('lojas').doc(lojaId);
  db.seed(base, {ownerUid, lojaId});
  return {db, base, lojaId};
}
const run = (db, lojaId, operation, payload, auth = owner) =>
  executeCategoryCommand(db, {protocolVersion: 1, lojaId, operation, operationId: `op_${++seq}`, payload}, auth);
const cats = (db, base) => [...db.snapshot()].filter(([p]) => p.startsWith(`${base.path}/categorias/`))
  .map(([p, data]) => ({id: p.split('/').pop(), data}));
const indexOf = (db, base, lojaId) => buildCategoryIndex(cats(db, base), lojaId);

async function chain(db, lojaId, names = LEVELS) {
  const out = [];
  let parent = null;
  for (const nome of names) {
    const res = await run(db, lojaId, 'create', {parent, nome});
    out.push(res.category);
    parent = {id: res.category.id};
  }
  return out;
}

async function rejects(promise, code) {
  await assert.rejects(promise, e => {
    assert.equal(e.categoryCode, code, e.message);
    return true;
  });
}

test('six levels are created with canonical depth, pathIds and pathNames', async () => {
  const {db, base, lojaId} = seedStore();
  const nodes = await chain(db, lojaId);
  assert.equal(nodes.length, MAX_CATEGORY_DEPTH);
  nodes.forEach((n, i) => {
    assert.equal(n.depth, i + 1);
    assert.equal(n.parentId, i ? nodes[i - 1].id : null);
    assert.deepEqual(n.pathNames, LEVELS.slice(0, i + 1));
    assert.deepEqual(n.pathIds, nodes.slice(0, i + 1).map(x => x.id));
    const stored = db.getData(base.collection('categorias').doc(n.id));
    assert.equal(stored.lojaId, lojaId);
    assert.equal(stored.isDeleted, false);
    assert.equal(stored.depth, i + 1);
    assert.deepEqual(stored.pathIds, n.pathIds);
    assert.ok(stored.createdAt && stored.updatedAt);
  });
});

test('a 7th level is refused before any write with the depth message', async () => {
  const {db, base, lojaId} = seedStore();
  const nodes = await chain(db, lojaId);
  const before = db.snapshot();
  const commits = db.commits.length;
  await assert.rejects(run(db, lojaId, 'create', {parent: {id: nodes[5].id}, nome: 'Teste'}), e => {
    assert.equal(e.categoryCode, CATEGORY_CODES.DEPTH_LIMIT);
    assert.equal(e.message, CATEGORY_DEPTH_LIMIT_MESSAGE);
    return true;
  });
  assert.equal(db.commits.length, commits);
  assert.deepEqual(db.snapshot(), before);
  assert.equal(cats(db, base).length, 6);
});

test('cycles are refused: self parent, move into a descendant, corrupt looping docs', async () => {
  const {db, base, lojaId} = seedStore();
  const [a, b, c] = await chain(db, lojaId, ['A', 'B', 'C']);
  const index = indexOf(db, base, lojaId);
  assert.throws(() => validateCategoryMove(index, a.id, a.id), e => e.categoryCode === CATEGORY_CODES.CYCLE);
  assert.throws(() => validateCategoryMove(index, a.id, c.id), e => e.categoryCode === CATEGORY_CODES.CYCLE);
  const commits = db.commits.length;
  await rejects(run(db, lojaId, 'move', {target: {id: a.id}, newParent: {id: b.id}}), CATEGORY_CODES.CYCLE);
  await rejects(run(db, lojaId, 'move', {target: {id: c.id}, newParent: null}), CATEGORY_CODES.REPARENT_DISABLED);
  assert.equal(db.commits.length, commits);

  const coll = base.collection('categorias');
  db.seed(coll.doc('x'), {lojaId, nome: 'X', parentId: 'y'});
  db.seed(coll.doc('y'), {lojaId, nome: 'Y', parentId: 'x'});
  const idx = indexOf(db, base, lojaId);
  assert.equal(idx.quarantined.get('x'), CATEGORY_CODES.CYCLE);
  assert.equal(idx.nodes.has('x'), false);
  await rejects(run(db, lojaId, 'create', {parent: {id: 'x'}, nome: 'Z'}), CATEGORY_CODES.CYCLE);
});

test('moves that would exceed 6 levels are refused as depth errors', async () => {
  const {db, base, lojaId} = seedStore();
  const deep = await chain(db, lojaId, ['R1', 'R2', 'R3', 'R4']);
  const [other] = await chain(db, lojaId, ['Outra', 'O2', 'O3']);
  const index = indexOf(db, base, lojaId);
  assert.throws(() => validateCategoryMove(index, other.id, deep[3].id), e => e.categoryCode === CATEGORY_CODES.DEPTH_LIMIT);
});

test('parents of another store are never reachable', async () => {
  const db = createConsignmentTestDb();
  const a = seedStore(db, 'mirjoias');
  const b = seedStore(db, 'nathy-pratas-e-folheados', 'ownerB');
  const [rootA] = await chain(db, a.lojaId, ['Feminino']);
  const [rootB] = await run(db, b.lojaId, 'create', {parent: null, nome: 'Feminino'}, {uid: 'ownerB'}).then(r => [r.category]);
  assert.notEqual(rootA.id, rootB.id);
  const commits = db.commits.length;
  await rejects(run(db, a.lojaId, 'create', {parent: {id: rootB.id}, nome: 'Religioso'}), CATEGORY_CODES.NOT_FOUND);
  await rejects(run(db, a.lojaId, 'create', {parent: {id: rootA.id, lojaId: b.lojaId}, nome: 'Religioso'}),
    CATEGORY_CODES.CROSS_TENANT);
  db.seed(a.base.collection('categorias').doc('intruso'), {lojaId: b.lojaId, nome: 'Intruso', parentId: null});
  await rejects(run(db, a.lojaId, 'create', {parent: {id: 'intruso'}, nome: 'Religioso'}), CATEGORY_CODES.CROSS_TENANT);
  await assert.rejects(run(db, a.lojaId, 'create', {parent: null, nome: 'Masculino'}, {uid: 'ownerB'}),
    e => e.code === 'permission-denied');
  assert.equal(db.commits.length, commits);
});

test('identical trees in two stores keep separate ids and never resolve across stores', async () => {
  const db = createConsignmentTestDb();
  const mir = seedStore(db, 'mirjoias');
  const nathy = seedStore(db, 'nathy-pratas-e-folheados', 'ownerB');
  const mirNodes = await chain(db, mir.lojaId);
  let parent = null;
  const nathyNodes = [];
  for (const nome of LEVELS) {
    const r = await run(db, nathy.lojaId, 'create', {parent, nome}, {uid: 'ownerB'});
    nathyNodes.push(r.category);
    parent = {id: r.category.id};
  }
  const mirIds = new Set(mirNodes.map(n => n.id));
  assert.ok(nathyNodes.every(n => !mirIds.has(n.id)));
  const mirIndex = indexOf(db, mir.base, mir.lojaId);
  const product = {categoryPathIds: nathyNodes.slice(0, 3).map(n => n.id), categoria: '', subcategoria: ''};
  assert.equal(productCategoryIds(mirIndex, product).size, 0);
});

test('sibling names are unique ignoring case and accents; same name under another parent is fine', async () => {
  const {db, lojaId} = seedStore();
  const [fem] = await chain(db, lojaId, ['Feminino']);
  const [mas] = await chain(db, lojaId, ['Masculino']);
  await run(db, lojaId, 'create', {parent: {id: fem.id}, nome: 'Anéis'});
  await rejects(run(db, lojaId, 'create', {parent: {id: fem.id}, nome: '  aneis '}), CATEGORY_CODES.NAME_TAKEN);
  const r = await run(db, lojaId, 'create', {parent: {id: mas.id}, nome: 'Anéis'});
  assert.equal(r.category.depth, 2);
});

test('rename keeps ids, updates descendant pathNames atomically and remembers the old name', async () => {
  const {db, base, lojaId} = seedStore();
  const nodes = await chain(db, lojaId, ['Feminino', 'Religioso', 'Anéis', 'Nossa Senhora']);
  const product = {categoria: 'Feminino', subcategoria: 'Religioso'};
  const before = productCategoryIds(indexOf(db, base, lojaId), product);
  const commits = db.commits.length;
  const r = await run(db, lojaId, 'rename', {target: {id: nodes[1].id}, nome: 'Religiosos'});
  assert.equal(db.commits.length, commits + 1);
  assert.equal(r.writes, 3);
  assert.equal(r.category.id, nodes[1].id);
  const idx = indexOf(db, base, lojaId);
  assert.deepEqual(idx.nodes.get(nodes[3].id).pathNames, ['Feminino', 'Religiosos', 'Anéis', 'Nossa Senhora']);
  const stored = db.getData(base.collection('categorias').doc(nodes[3].id));
  assert.deepEqual(stored.pathNames, ['Feminino', 'Religiosos', 'Anéis', 'Nossa Senhora']);
  assert.deepEqual(db.getData(base.collection('categorias').doc(nodes[1].id)).legacyNames, ['Religioso']);
  assert.deepEqual(productCategoryIds(idx, product), before);
  assert.equal([...db.snapshot().keys()].some(k => k.includes('/estoque_produtos/')), false);
});

test('archive refuses categories with active subcategories, with no write', async () => {
  const {db, lojaId} = seedStore();
  const [rel, aneis] = await chain(db, lojaId, ['Religioso', 'Anéis']);
  const commits = db.commits.length;
  await assert.rejects(run(db, lojaId, 'archive', {target: {id: rel.id}}), e => {
    assert.equal(e.categoryCode, CATEGORY_CODES.HAS_CHILDREN);
    assert.equal(e.message, CATEGORY_HAS_CHILDREN_MESSAGE);
    return true;
  });
  assert.equal(db.commits.filter(c => c.writes).length, commits);
  await run(db, lojaId, 'archive', {target: {id: aneis.id}});
  await run(db, lojaId, 'archive', {target: {id: rel.id}});
});

test('archive refuses categories with products (path ids or legacy names) and soft-deletes otherwise', async () => {
  const {db, base, lojaId} = seedStore();
  const [fem, rel, aneis] = await chain(db, lojaId, ['Feminino', 'Religioso', 'Anéis']);
  const [vazia] = await chain(db, lojaId, ['Vazia']);
  db.seed(base.collection('estoque_produtos').doc('p1'), {nome: 'Anel Nossa Senhora', quantidade: 3,
    categoria: 'Feminino', subcategoria: 'Religioso', categoryId: aneis.id, categoryPathIds: [fem.id, rel.id, aneis.id]});
  const [legacyRoot] = await chain(db, lojaId, ['Pulseiras']);
  db.seed(base.collection('draft_produtos').doc('p2'), {nome: 'Pulseira', categoria: 'pulseiras'});
  const writesBefore = db.commits.filter(c => c.writes).length;
  await rejects(run(db, lojaId, 'archive', {target: {id: aneis.id}}), CATEGORY_CODES.HAS_PRODUCTS);
  await rejects(run(db, lojaId, 'archive', {target: {id: legacyRoot.id}}), CATEGORY_CODES.HAS_PRODUCTS);
  await rejects(run(db, lojaId, 'archive', {target: {legacyPath: ['Brincos']}}), CATEGORY_CODES.HAS_PRODUCTS);
  assert.equal(db.commits.filter(c => c.writes).length, writesBefore);
  const productBefore = db.getData(base.collection('estoque_produtos').doc('p1'));

  await run(db, lojaId, 'archive', {target: {id: vazia.id}});
  const stored = db.getData(base.collection('categorias').doc(vazia.id));
  assert.equal(stored.isDeleted, true);
  assert.ok(stored.deletedAt);
  assert.equal(stored.nome, 'Vazia');
  assert.deepEqual(db.getData(base.collection('estoque_produtos').doc('p1')), productBefore);
  assert.equal(indexOf(db, base, lojaId).activeChildrenOf(null).some(n => n.id === vazia.id), false);
});

test('legacy text categories become docs only when the merchant acts on them, in one commit', async () => {
  const {db, base, lojaId} = seedStore();
  db.seed(base.collection('estoque_produtos').doc('p1'), {nome: 'Anel', categoria: 'Feminino', subcategoria: 'Anéis'});
  assert.equal(cats(db, base).length, 0);
  const commits = db.commits.length;
  const r = await run(db, lojaId, 'create', {parent: {legacyPath: ['Feminino', 'Anéis']}, nome: 'Nossa Senhora'});
  assert.equal(db.commits.length, commits + 1);
  assert.equal(r.writes, 3);
  assert.deepEqual(r.category.pathNames, ['Feminino', 'Anéis', 'Nossa Senhora']);
  const idx = indexOf(db, base, lojaId);
  const ids = productCategoryIds(idx, db.getData(base.collection('estoque_produtos').doc('p1')));
  assert.deepEqual([...ids].sort(), r.category.pathIds.slice(0, 2).sort());
  const again = await run(db, lojaId, 'create', {parent: {legacyPath: ['feminino']}, nome: 'Religioso'});
  assert.equal(again.writes, 1);
  assert.equal(again.category.parentId, r.category.pathIds[0]);
  assert.deepEqual(db.getData(base.collection('estoque_produtos').doc('p1')), {nome: 'Anel', categoria: 'Feminino', subcategoria: 'Anéis'});
});

test('renaming a legacy category keeps old product text resolving to it', async () => {
  const {db, base, lojaId} = seedStore();
  const r = await run(db, lojaId, 'rename', {target: {legacyPath: ['Religioso']}, nome: 'Religiosos'});
  assert.deepEqual(r.category.legacyNames, ['Religioso']);
  const ids = productCategoryIds(indexOf(db, base, lojaId), {categoria: 'Religioso'});
  assert.deepEqual([...ids], [r.category.id]);
});

test('reorder sets sortOrder for every sibling and refuses a stale list', async () => {
  const {db, base, lojaId} = seedStore();
  const [f] = await chain(db, lojaId, ['Feminino']);
  const [m] = await chain(db, lojaId, ['Masculino']);
  const [i] = await chain(db, lojaId, ['Infantil']);
  await run(db, lojaId, 'reorder', {parent: null, orderedChildren: [{id: i.id}, {id: f.id}, {id: m.id}]});
  const idx = indexOf(db, base, lojaId);
  assert.deepEqual(idx.activeChildrenOf(null).map(n => n.nome), ['Infantil', 'Feminino', 'Masculino']);
  const commits = db.commits.length;
  await rejects(run(db, lojaId, 'reorder', {parent: null, orderedChildren: [{id: f.id}, {id: m.id}]}), CATEGORY_CODES.STALE);
  assert.equal(db.commits.length, commits);
});

test('a product filed in Feminino > Religioso > Anéis matches each ancestor and not Masculino', async () => {
  const {db, base, lojaId} = seedStore();
  const [fem, rel, aneis] = await chain(db, lojaId, ['Feminino', 'Religioso', 'Anéis']);
  const [mas] = await chain(db, lojaId, ['Masculino']);
  const idx = indexOf(db, base, lojaId);
  const ids = productCategoryIds(idx, {nome: 'Anel Nossa Senhora', categoria: 'Feminino', subcategoria: 'Religioso',
    categoryId: aneis.id, categoryPathIds: [fem.id, rel.id, aneis.id]});
  for (const n of [fem, rel, aneis]) assert.equal(ids.has(n.id), true, n.nome);
  assert.equal(ids.has(mas.id), false);
});

test('existing data without depth/pathIds is read as root categories without writes', () => {
  const idx = buildCategoryIndex([{id: 'aneis', data: {nome: 'Anéis', lojaId: 'l'}}, {id: 'brincos', data: {nome: 'Brincos'}}], 'l');
  const a = idx.nodes.get('aneis');
  assert.equal(a.depth, 1);
  assert.equal(a.parentId, null);
  assert.deepEqual(a.pathIds, ['aneis']);
  assert.deepEqual(a.pathNames, ['Anéis']);
  assert.equal(idx.nodes.get('brincos').depth, 1);
});

test('editorial accepts the hierarchical product fields with strict shape checks', () => {
  for (const k of ['categoryId', 'categoryPathIds', 'categoryPathNames']) assert.ok(EDITORIAL_FIELDS.includes(k));
  const ok = {categoryId: 'c3', categoryPathIds: ['c1', 'c2', 'c3'], categoryPathNames: ['Feminino', 'Religioso', 'Anéis']};
  assert.deepEqual(validateEditorial(ok), ok);
  assert.deepEqual(validateEditorial({categoryId: '', categoryPathIds: [], categoryPathNames: []}).categoryPathIds, []);
  const bad = [
    {categoryId: 'c2', categoryPathIds: ['c1', 'c2', 'c3']},
    {categoryPathIds: ['a', 'b', 'c', 'd', 'e', 'f', 'g']},
    {categoryPathIds: ['a/b']},
    {categoryPathIds: ['a', 'a']},
    {categoryPathIds: ['a'], categoryPathNames: []},
    {categoryId: 3},
    {categoryPathNames: ['']},
  ];
  for (const patch of bad) assert.throws(() => validateEditorial(patch), e => e.code === 'invalid-argument', JSON.stringify(patch));
});

test('names normalize by case, accents and spacing', () => {
  assert.equal(normalizeCategoryName('  Anéis   de  Prata '), 'aneis de prata');
  assert.equal(normalizeCategoryName('ANÉIS'), normalizeCategoryName('aneis'));
});

function assertPathIntegrity(db, base, lojaId) {
  const idx = indexOf(db, base, lojaId);
  for (const {id, data} of cats(db, base)) {
    assert.equal(data.depth, data.pathIds.length, id);
    assert.equal(data.pathNames.length, data.pathIds.length, id);
    assert.equal(data.pathIds.at(-1), id);
    assert.equal(data.pathNames.at(-1), data.nome);
    if (data.parentId) {
      const parent = idx.nodes.get(data.parentId);
      assert.deepEqual(data.pathIds, [...parent.pathIds, id]);
      assert.deepEqual(data.pathNames, [...parent.pathNames, data.nome]);
    } else {
      assert.equal(data.depth, 1);
    }
  }
}

test('paths are server-derived: client depth/pathIds/pathNames are ignored and stay consistent after rename', async () => {
  const {db, base, lojaId} = seedStore();
  const [fem] = await chain(db, lojaId, ['Feminino']);
  const r = await run(db, lojaId, 'create', {parent: {id: fem.id}, nome: 'Religioso',
    depth: 6, pathIds: ['forged'], pathNames: ['Forjado'], id: 'forged'});
  assert.equal(r.category.depth, 2);
  assert.deepEqual(r.category.pathIds, [fem.id, r.category.id]);
  assert.notEqual(r.category.id, 'forged');
  await chain(db, lojaId, ['Masculino']);
  const [, , aneis] = await chain(db, lojaId, ['Infantil', 'Religioso', 'Anéis']);
  assertPathIntegrity(db, base, lojaId);
  await run(db, lojaId, 'rename', {target: {id: aneis.pathIds[1]}, nome: 'Religiosos'});
  assertPathIntegrity(db, base, lojaId);
});

test('Feminino > Religioso and Masculino > Religioso coexist; same-parent duplicates are refused', async () => {
  const {db, base, lojaId} = seedStore();
  const [fem] = await chain(db, lojaId, ['Feminino']);
  const [mas] = await chain(db, lojaId, ['Masculino']);
  const a = await run(db, lojaId, 'create', {parent: {id: fem.id}, nome: 'Religioso'});
  const b = await run(db, lojaId, 'create', {parent: {id: mas.id}, nome: 'Religioso'});
  assert.notEqual(a.category.id, b.category.id);
  for (const dup of ['religioso', ' RELIGIOSO ', 'Religióso', 'Religioso  ']) {
    await rejects(run(db, lojaId, 'create', {parent: {id: fem.id}, nome: dup}), CATEGORY_CODES.NAME_TAKEN);
  }
  await run(db, lojaId, 'rename', {target: {id: b.category.id}, nome: 'Masculino'});
  const rel2 = await run(db, lojaId, 'create', {parent: {id: mas.id}, nome: 'Crucifixos'});
  await rejects(run(db, lojaId, 'rename', {target: {id: rel2.category.id}, nome: 'masculino'}), CATEGORY_CODES.NAME_TAKEN);
  assert.equal(cats(db, base).filter(c => normalizeCategoryName(c.data.nome) === 'religioso').length, 1);
});

test('reorder writes only sortOrder and updatedAt', async () => {
  const {db, base, lojaId} = seedStore();
  const [f] = await chain(db, lojaId, ['Feminino']);
  const [m] = await chain(db, lojaId, ['Masculino']);
  const before = new Map(cats(db, base).map(c => [c.id, c.data]));
  await run(db, lojaId, 'reorder', {parent: null, orderedChildren: [{id: m.id}, {id: f.id}]});
  for (const {id, data} of cats(db, base)) {
    const changed = Object.keys({...before.get(id), ...data})
      .filter(k => JSON.stringify(before.get(id)[k]) !== JSON.stringify(data[k]));
    for (const k of changed) assert.ok(['sortOrder', 'updatedAt'].includes(k), `${id}.${k}`);
  }
});

test('category docs are publicly readable, so they never carry actor uids', async () => {
  const {db, base, lojaId} = seedStore();
  const [, rel] = await chain(db, lojaId, ['Feminino', 'Religioso']);
  await run(db, lojaId, 'rename', {target: {id: rel.id}, nome: 'Religiosos'});
  await run(db, lojaId, 'archive', {target: {id: rel.id}});
  for (const {data} of cats(db, base)) {
    const json = JSON.stringify(data);
    assert.equal(json.includes('owner'), false, json);
    for (const k of ['createdBy', 'updatedBy', 'deletedBy', 'uid', 'actorUid']) assert.equal(k in data, false, k);
  }
});

test('invalid commands are refused before any read or write', async () => {
  const {db, lojaId} = seedStore();
  await assert.rejects(executeCategoryCommand(db, {protocolVersion: 2, lojaId, operation: 'create', operationId: 'x', payload: {}}, owner),
    e => e.categoryCode === CATEGORY_CODES.INVALID_ARGUMENT);
  await assert.rejects(executeCategoryCommand(db, {protocolVersion: 1, lojaId, operation: 'drop', operationId: 'x'}, owner),
    e => e.categoryCode === CATEGORY_CODES.INVALID_ARGUMENT);
  await rejects(run(db, lojaId, 'create', {parent: null, nome: '   '}), CATEGORY_CODES.INVALID_ARGUMENT);
  await rejects(run(db, lojaId, 'create', {parent: null, nome: 'x'.repeat(61)}), CATEGORY_CODES.INVALID_ARGUMENT);
  assert.equal(db.commits.length, 0);
});
