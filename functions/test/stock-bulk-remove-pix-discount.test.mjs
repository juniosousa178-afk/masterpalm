/**
 * Bulk "Remover desconto no Pix": server-authoritative, narrow (percentualDescontoPix + updatedAt only),
 * idempotent, tenant-scoped. In-memory only (no production writes).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import {executeStockCommand, executeStockCommandInTransaction, publishStockProduct} from '../src/stockCatalogCommands.js';
import {
  BULK_PIX_KIND, MAX_PRODUCTS_PER_BULK_PIX_OPERATION, hasPixDiscount, parseBulkPixCommand,
} from '../src/stockCatalogBulkPix.js';
import {projectCatalog} from '../src/catalogStockProjection.js';
import {executeConsignmentCommand} from '../src/consignmentCommand.js';
import {createConsignmentTestDb, commitUnits} from './consignment-test-db.mjs';

const owner = {uid: 'owner'};
const PIX = 'percentualDescontoPix';
const STOCK_KEYS = ['quantidade', 'variacoes', 'estoquePorTamanho', 'estoquePorCor', 'tamanhos', 'cores',
  'variacoesExtraTipo', 'stockKind', 'stockRevision', 'stockOperationId', 'historicalStockCells', 'itensCombo', 'comboConfig'];
let seq = 0;

const multiCategory = {
  categoryAssignments: [
    {categoryId: 'rel_cruz', pathIds: ['rel', 'rel_cruz'], pathNames: ['Religioso', 'Cruz']},
    {categoryId: 'fem_prata', pathIds: ['fem', 'fem_prata'], pathNames: ['Feminino', 'Prata']},
  ],
  categoryMembershipIds: ['rel', 'rel_cruz', 'fem', 'fem_prata'],
  categoryId: 'rel_cruz', categoryPathIds: ['rel', 'rel_cruz'], categoryPathNames: ['Religioso', 'Cruz'],
};
const promo = {
  emPromocao: true, percentualPromo: 20, valorPromo: 0, precoComPromocao: 79.9, promocaoAtiva: true,
  divideSemJuros: true, maxParcelasSemJuros: 6, descontoComboPercentual: 3,
};

/** Products: {id: {stock, draft, live}} — each doc gets the same commercial/editorial fields unless overridden. */
const FIXTURE = {
  // §21 fixture
  A: {price: 100, pix: 10},
  B: {price: 200, pix: 5},
  C: {price: 150, pix: 0},
  // §22 mixed
  simples: {price: 50, pix: 7, extra: {codigoBarras: 'SKU-1', imagens: ['https://img/simples.jpg']}},
  variacao: {
    price: 120, pix: 8,
    stock: {stockKind: 'variation', quantidade: 5, variacoes: {P: {Azul: 2, Rosa: 1}, M: {Azul: 2}},
      estoquePorTamanho: {P: 3, M: 2}, tamanhos: ['P', 'M'], cores: ['Azul', 'Rosa'],
      historicalStockCells: {'G|Verde': {removedAt: 'x'}}},
  },
  multicat: {price: 90, pix: 12, extra: multiCategory},
  legado: {price: 70, pix: 7, extra: {categoria: 'Religiosos', subcategoria: 'Terço'}, legacyStock: true},
  promo: {price: 100, pix: 15, extra: promo},
  semPix: {price: 80, pix: null},
  liveStale: {price: 60, pix: 0, livePix: 10},
  textoPix: {price: 40, pix: 0, livePix: '5'},
  naoPublicado: {price: 30, pix: 9, noLive: true},
};

function seedStore(db, lojaId, {active = false, ownerUid = 'owner', products = FIXTURE} = {}) {
  const base = db.collection('lojas').doc(lojaId);
  db.seed(base, {ownerUid, lojaId});
  if (active) {
    db.seed(base.collection('stock_catalog_control').doc('state'), {protocolVersion: 1, mode: 'active', migrationComplete: true});
    db.seed(base.collection('stock_catalog_access').doc(ownerUid), {enabled: true, permissions: {editorial: true, adjust: true, publish: true}});
  }
  for (const [id, p] of Object.entries(products)) {
    const pixField = p.pix === null ? {} : {[PIX]: p.pix};
    const editorial = {nome: id, preco: p.price, precoFinal: p.price, publicadoNoCatalogo: true, ...pixField, ...(p.extra ?? {})};
    const stockShape = p.legacyStock
      ? {quantidade: 4}
      : (p.stock ?? {stockKind: 'simple', quantidade: 4, variacoes: {}});
    db.seed(base.collection('estoque_produtos').doc(id), {
      lojaId, custoReal: 31.5, stockRevision: 7, stockOperationId: `prev_${id}`, ...stockShape, ...editorial,
    });
    db.seed(base.collection('draft_produtos').doc(id), {...editorial, catalogStockRevision: 7});
    if (!p.noLive) {
      const live = {...editorial, quantidade: stockShape.quantidade, catalogStockRevision: 7};
      if ('livePix' in p) live[PIX] = p.livePix;
      db.seed(base.collection('produtos').doc(id), live);
    }
    db.seed(base.collection('stock_catalog_dependencies').doc(id), {comboIds: []});
  }
  return base;
}

function setup(options = {}) {
  const db = createConsignmentTestDb();
  const lojaId = `pix_${++seq}`;
  const base = seedStore(db, lojaId, options);
  return {db, lojaId, base};
}

const bulk = (lojaId, operationId, productIds, extra = {}) =>
  ({protocolVersion: 1, lojaId, operationId, kind: BULK_PIX_KIND, productIds, ...extra});
const read = (db, base, col, id) => db.getData(base.collection(col).doc(id));
const without = (doc, keys) => Object.fromEntries(Object.entries(doc ?? {}).filter(([k]) => !keys.includes(k)));
const opId = n => `pixrm_test_${String(n).padStart(4, '0')}`;
const docPaths = (base, id) => ['estoque_produtos', 'draft_produtos', 'produtos'].map(c => `${base.path}/${c}/${id}`);

for (const active of [false, true]) {
  const route = active ? 'ACTIVE' : 'NO_CONTROL';

  test(`§21 fixture A/B/C: UPDATED=2 NOOP=1, prices kept (${route})`, async () => {
    const {db, lojaId, base} = setup({active});
    const before = db.snapshot();
    const result = await executeStockCommand(db, bulk(lojaId, opId(1), ['A', 'B', 'C']), owner);
    assert.equal(result.alreadyApplied, false);
    assert.equal(result.updatedCount, 2);
    assert.equal(result.noopCount, 1);
    assert.equal(result.failedCount, 0);
    assert.deepEqual(result.updatedProductIds, ['A', 'B']);
    assert.deepEqual(result.noopProductIds, ['C']);
    for (const [id, price] of [['A', 100], ['B', 200]]) {
      for (const col of ['estoque_produtos', 'draft_produtos', 'produtos']) {
        const doc = read(db, base, col, id);
        assert.equal(doc[PIX], 0, `${col}/${id}`);
        assert.equal(doc.preco, price, 'NORMAL_PRICE_PRESERVED');
        assert.equal(doc.precoFinal, price);
        const prior = before.get(`${base.path}/${col}/${id}`);
        assert.deepEqual(without(doc, [PIX, 'updatedAt']), without(prior, [PIX, 'updatedAt']), 'only Pix field changed');
      }
    }
    for (const path of docPaths(base, 'C')) assert.deepEqual(db.getData({path}), before.get(path), 'C unchanged');
  });

  test(`§22 mixed selection: only Pix changes; stock/variations/categories/promo intact (${route})`, async () => {
    const {db, lojaId, base} = setup({active});
    const ids = ['simples', 'variacao', 'multicat', 'legado', 'promo', 'semPix', 'liveStale', 'textoPix', 'naoPublicado'];
    const before = db.snapshot();
    const commitsBefore = db.commits.length;
    const result = await executeStockCommand(db, bulk(lojaId, opId(2), ids), owner);
    assert.deepEqual(result.noopProductIds, ['semPix']);
    assert.equal(result.updatedCount, 8);
    for (const id of ids) {
      for (const path of docPaths(base, id)) {
        const prior = before.get(path);
        const after = db.getData({path});
        if (!prior) { assert.equal(after, undefined, `${path} not created`); continue; }
        assert.deepEqual(without(after, [PIX, 'updatedAt']), without(prior, [PIX, 'updatedAt']), path);
        assert.equal(hasPixDiscount(after[PIX]), false, `${path} has no Pix discount`);
      }
      const stockBefore = before.get(`${base.path}/estoque_produtos/${id}`);
      const stockAfter = read(db, base, 'estoque_produtos', id);
      for (const k of STOCK_KEYS) assert.deepEqual(stockAfter[k], stockBefore[k], `STOCK ${id}.${k}`);
    }
    // Only docs that carried a positive Pix discount were written; noop product never written.
    const commit = db.commits[commitsBefore];
    const written = commit.ops.map(o => o.path);
    for (const path of docPaths(base, 'semPix')) assert.equal(written.includes(path), false, 'NOOP_PRODUCT_WRITES=0');
    assert.equal(written.includes(`${base.path}/estoque_produtos/liveStale`), false, 'clean stock doc not rewritten');
    assert.equal(written.includes(`${base.path}/produtos/liveStale`), true, 'stale live Pix fixed');
    assert.equal(written.includes(`${base.path}/produtos/textoPix`), true, 'numeric string treated as discount');
    assert.ok(commit.ops.every(o => o.type === 'update' || o.path.endsWith(`/stock_catalog_operations/${opId(2)}`)));
    assert.equal(read(db, base, 'produtos', 'naoPublicado'), undefined, 'unpublished product not published');
  });
}

test('NOOP-only selection writes only the operation marker', async () => {
  const {db, lojaId, base} = setup();
  const commitsBefore = db.commits.length;
  const result = await executeStockCommand(db, bulk(lojaId, opId(3), ['C', 'semPix']), owner);
  assert.equal(result.updatedCount, 0);
  assert.equal(result.noopCount, 2);
  const ops = db.commits[commitsBefore].ops;
  assert.deepEqual(ops.map(o => o.path), [`${base.path}/stock_catalog_operations/${opId(3)}`]);
});

test('audit: one operation document with counts and initiating user', async () => {
  const {db, lojaId, base} = setup();
  await executeStockCommand(db, bulk(lojaId, opId(4), ['A', 'C'], {bulkId: 'bulk_1', clientBuild: '1.0.145+159'}), owner);
  const op = read(db, base, 'stock_catalog_operations', opId(4));
  assert.equal(op.kind, BULK_PIX_KIND);
  assert.equal(op.actorUid, 'owner');
  assert.equal(op.lojaId, lojaId);
  assert.equal(op.bulkId, 'bulk_1');
  assert.equal(op.requestedCount, 2);
  assert.equal(op.updatedCount, 1);
  assert.equal(op.noopCount, 1);
  assert.equal(op.failedCount, 0);
  assert.ok(op.createdAt);
  assert.equal(op.clientBuild, '1.0.145+159');
  assert.deepEqual(op.items, []);
});

test('replay with same operationId + payload: same result, no new writes', async () => {
  const {db, lojaId} = setup();
  const cmd = bulk(lojaId, opId(5), ['B', 'A', 'C']);
  const first = await executeStockCommand(db, cmd, owner);
  const snapshot = db.snapshot();
  // Order and clientBuild are not part of the identity.
  const replay = await executeStockCommand(db, {...cmd, productIds: ['C', 'A', 'B'], clientBuild: 'x.y'}, owner);
  assert.equal(replay.alreadyApplied, true);
  for (const key of ['updatedCount', 'noopCount', 'failedCount', 'requestedCount', 'updatedProductIds', 'noopProductIds']) {
    assert.deepEqual(replay[key], first[key], key);
  }
  assert.deepEqual(db.snapshot(), snapshot);
});

test('same operationId with altered payload or another user is blocked', async () => {
  const {db, lojaId, base} = setup();
  await executeStockCommand(db, bulk(lojaId, opId(6), ['A']), owner);
  const snapshot = db.snapshot();
  await assert.rejects(executeStockCommand(db, bulk(lojaId, opId(6), ['A', 'B']), owner),
    e => e.code === 'already-exists' && e.details?.code === 'OPERATION_PAYLOAD_CONFLICT');
  db.seed(base.collection('members').doc('admin2'), {role: 'admin'});
  await assert.rejects(executeStockCommand(db, bulk(lojaId, opId(6), ['A']), {uid: 'admin2'}),
    e => e.code === 'already-exists');
  assert.deepEqual(db.snapshot().get(`${base.path}/estoque_produtos/B`), snapshot.get(`${base.path}/estoque_produtos/B`));
  assert.equal(read(db, base, 'estoque_produtos', 'B')[PIX], 5);
});

test('network retry after an uncertain commit replays instead of re-applying', async () => {
  const {db, lojaId} = setup();
  const cmd = bulk(lojaId, opId(7), ['A', 'B']);
  await executeStockCommand(db, cmd, owner); // committed, but the client never saw the answer
  const replay = await executeStockCommand(db, cmd, owner);
  assert.equal(replay.alreadyApplied, true);
  assert.equal(replay.updatedCount, 2);
});

for (const [label, ids, expected] of [
  ['duplicate product ID', ['A', 'A'], e => e.code === 'invalid-argument' && e.details?.code === 'BULK_PIX_DUPLICATE_PRODUCT'],
  ['invalid product ID (slash)', ['A', 'x/y'], e => e.code === 'invalid-argument'],
  ['invalid product ID (empty)', ['A', ''], e => e.code === 'invalid-argument'],
  ['invalid product ID (reserved)', ['A', '__x__'], e => e.code === 'invalid-argument'],
  ['missing product', ['A', 'nao-existe'], e => e.code === 'failed-precondition' &&
    e.details?.code === 'BULK_PIX_PRODUCT_UNAVAILABLE' && e.details.reason === 'NOT_FOUND' && e.details.productId === 'nao-existe'],
  ['empty selection', [], e => e.code === 'invalid-argument'],
  ['over the safe limit', Array.from({length: MAX_PRODUCTS_PER_BULK_PIX_OPERATION + 1}, (_, i) => `p${i}`),
    e => e.code === 'resource-exhausted' && e.details?.code === 'BULK_PIX_TOO_MANY_PRODUCTS'],
]) {
  test(`fail-safe, zero writes: ${label}`, async () => {
    const {db, lojaId} = setup();
    const before = db.snapshot();
    await assert.rejects(executeStockCommand(db, bulk(lojaId, opId(8), ids), owner), expected);
    assert.deepEqual(db.snapshot(), before);
  });
}

for (const [label, mark] of [
  ['pendingSoftDelete', (db, base) => db.seed(base.collection('estoque_produtos').doc('B'),
    {...db.getData(base.collection('estoque_produtos').doc('B')), pendingSoftDelete: true})],
  ['full-product tombstone', (db, base) => db.seed(base.collection('exclusao_produto').doc('B'), {p: true, productId: 'B'})],
]) {
  test(`deleted/archived product (${label}) rejects the whole operation`, async () => {
    const {db, lojaId, base} = setup();
    mark(db, base);
    const before = db.snapshot();
    await assert.rejects(executeStockCommand(db, bulk(lojaId, opId(9), ['A', 'B']), owner),
      e => e.details?.code === 'BULK_PIX_PRODUCT_UNAVAILABLE' && e.details.reason === 'DELETED' && e.details.productId === 'B');
    assert.deepEqual(db.snapshot(), before);
  });
}

test('partial variation tombstone (p:false) does not block the product', async () => {
  const {db, lojaId, base} = setup();
  db.seed(base.collection('exclusao_produto').doc('variacao'), {p: false, v: {'G|Verde': true}});
  const result = await executeStockCommand(db, bulk(lojaId, opId(10), ['variacao']), owner);
  assert.equal(result.updatedCount, 1);
});

test('exactly the safe limit fits in one transaction within the write budget', async () => {
  const products = Object.fromEntries(Array.from({length: MAX_PRODUCTS_PER_BULK_PIX_OPERATION}, (_, i) =>
    [`p${String(i).padStart(2, '0')}`, {price: 10 + i, pix: 5}]));
  const {db, lojaId} = setup({products});
  const before = db.commits.length;
  const result = await executeStockCommand(db, bulk(lojaId, opId(11), Object.keys(products)), owner);
  assert.equal(result.updatedCount, MAX_PRODUCTS_PER_BULK_PIX_OPERATION);
  const commit = db.commits[before];
  assert.equal(commit.writes, MAX_PRODUCTS_PER_BULK_PIX_OPERATION * 3 + 1);
  assert.ok(commitUnits(commit) <= 500, 'Firestore commit limit');
  assert.ok(commit.writes <= 100, 'stock command write budget');
});

test('cross-tenant: foreign lojaId denied; foreign product id never edited', async () => {
  const db = createConsignmentTestDb();
  const baseA = seedStore(db, 'loja_a', {ownerUid: 'owner'});
  const baseB = seedStore(db, 'loja_b', {ownerUid: 'other', products: {'so-na-b': {price: 10, pix: 10}, A: {price: 999, pix: 50}}});
  const before = db.snapshot();
  // Owner of A cannot address store B.
  await assert.rejects(executeStockCommand(db, bulk('loja_b', opId(12), ['A']), owner), e => e.code === 'permission-denied');
  // A product that only exists in B is not found inside A.
  await assert.rejects(executeStockCommand(db, bulk('loja_a', opId(13), ['A', 'so-na-b']), owner),
    e => e.details?.reason === 'NOT_FOUND');
  assert.deepEqual(db.snapshot(), before);
  // Same id in both stores: only the caller's store is touched.
  await executeStockCommand(db, bulk('loja_a', opId(14), ['A']), owner);
  assert.equal(read(db, baseA, 'estoque_produtos', 'A')[PIX], 0);
  for (const col of ['estoque_produtos', 'draft_produtos', 'produtos']) {
    assert.deepEqual(read(db, baseB, col, 'A'), before.get(`${baseB.path}/${col}/A`), `loja_b ${col} untouched`);
  }
});

test('authorization: seller without catalog permission and ACTIVE grant without editorial are denied', async () => {
  const {db, lojaId, base} = setup();
  db.seed(base.collection('vendedores').doc('seller'), {ativo: true, permissoes: {vendas: true}});
  await assert.rejects(executeStockCommand(db, bulk(lojaId, opId(15), ['A']), {uid: 'seller'}), e => e.code === 'permission-denied');
  db.seed(base.collection('vendedores').doc('editor'), {ativo: true, permissoes: {produtos: true}});
  const ok = await executeStockCommand(db, bulk(lojaId, opId(16), ['A']), {uid: 'editor'});
  assert.equal(ok.updatedCount, 1);

  const active = setup({active: true});
  active.db.seed(active.base.collection('stock_catalog_access').doc('owner'), {enabled: true, permissions: {sale: true}});
  await assert.rejects(executeStockCommand(active.db, bulk(active.lojaId, opId(17), ['A']), owner), e => e.code === 'permission-denied');
  await assert.rejects(executeStockCommand(active.db, bulk(active.lojaId, opId(18), ['A']), {}), e => e.code === 'unauthenticated');
});

test('protocol: unknown fields, client-sent values and foreign operation ids are rejected', async () => {
  const {db, lojaId} = setup();
  const before = db.snapshot();
  for (const extra of [{preco: 90}, {[PIX]: 0}, {items: [{productId: 'A'}]}, {editorial: {}}]) {
    await assert.rejects(executeStockCommand(db, bulk(lojaId, opId(19), ['A'], extra), owner), e => e.code === 'invalid-argument');
  }
  await assert.rejects(executeStockCommand(db, bulk(lojaId, 'sale_123456789', ['A']), owner), e => e.code === 'invalid-argument');
  await assert.rejects(executeStockCommand(db, {...bulk(lojaId, opId(20), ['A']), protocolVersion: 2}, owner),
    e => e.code === 'failed-precondition');
  // Trusted in-transaction callers cannot reach the bulk path.
  await assert.rejects(db.runTransaction(tx => executeStockCommandInTransaction(tx, db, bulk(lojaId, opId(21), ['A']), owner)),
    e => e.code === 'invalid-argument');
  assert.deepEqual(db.snapshot(), before);
  assert.throws(() => parseBulkPixCommand({...bulk(lojaId, opId(22), ['A']), bulkId: 'a/b'}), e => e.code === 'invalid-argument');
});

test('concurrency: a stock change between preview and commit is kept (narrow update)', async () => {
  const {db, lojaId, base} = setup();
  const stockRef = base.collection('estoque_produtos').doc('A');
  let injected = false;
  db.onRead = (path, attempt) => {
    if (!injected && attempt === 1 && path === stockRef.path) {
      injected = true;
      // Another device sells one unit while the bulk transaction is in flight.
      db.concurrentWrite(stockRef, {...db.getData(stockRef), quantidade: 3, stockRevision: 8, stockOperationId: 'sale_x'});
    }
  };
  await executeStockCommand(db, bulk(lojaId, opId(23), ['A']), owner);
  db.onRead = null;
  const stock = db.getData(stockRef);
  assert.equal(stock.quantidade, 3);
  assert.equal(stock.stockRevision, 8);
  assert.equal(stock.stockOperationId, 'sale_x');
  assert.equal(stock[PIX], 0);
});

test('catalog projection and republish never resurrect the removed Pix discount', async () => {
  const {db, lojaId, base} = setup({active: true});
  await executeStockCommand(db, bulk(lojaId, opId(24), ['multicat', 'promo', 'variacao']), owner);
  for (const id of ['multicat', 'promo', 'variacao']) {
    const projected = projectCatalog(read(db, base, 'estoque_produtos', id), read(db, base, 'draft_produtos', id), id);
    assert.equal(projected.live[PIX], 0);
    const liveBefore = read(db, base, 'produtos', id);
    await publishStockProduct(db, lojaId, id, owner);
    const live = read(db, base, 'produtos', id);
    assert.equal(live[PIX], 0, `${id} republished without Pix`);
    for (const k of ['preco', 'categoryAssignments', 'categoryMembershipIds', 'emPromocao', 'percentualPromo',
      'precoComPromocao', 'divideSemJuros', 'maxParcelasSemJuros', 'quantidade']) {
      assert.deepEqual(live[k], liveBefore[k], `${id}.${k}`);
    }
  }
});

test('a later editorial command keeps Pix at zero unless explicitly set', async () => {
  const {db, lojaId, base} = setup({active: true});
  await executeStockCommand(db, bulk(lojaId, opId(25), ['A']), owner);
  await executeStockCommand(db, {protocolVersion: 1, lojaId, kind: 'editorial', operationId: 'ed-after-pix',
    items: [{productId: 'A'}], editorial: {nome: 'A renomeado'}}, owner);
  for (const col of ['estoque_produtos', 'draft_produtos', 'produtos']) assert.equal(read(db, base, col, 'A')[PIX], 0, col);
});

test('old-client compatibility: no-discount value is the numeric 0 every reader already accepts', async () => {
  const {db, lojaId, base} = setup();
  await executeStockCommand(db, bulk(lojaId, opId(26), ['A']), owner);
  for (const col of ['estoque_produtos', 'draft_produtos', 'produtos']) {
    const v = read(db, base, col, 'A')[PIX];
    assert.equal(typeof v, 'number');
    assert.equal(v, 0);
  }
  // The editorial validator (old editor saves) accepts the stored value unchanged.
  await executeStockCommand(db, {protocolVersion: 1, lojaId, kind: 'editorial', operationId: 'ed-old-client',
    items: [{productId: 'A'}], editorial: {[PIX]: 0, preco: 100}}, owner);
  assert.equal(read(db, base, 'produtos', 'A')[PIX], 0);
});

test('hasPixDiscount classification', () => {
  for (const v of [10, 0.5, '5', ' 7 ', Infinity]) assert.equal(hasPixDiscount(v), true, String(v));
  for (const v of [0, -1, '0', '', 'abc', null, undefined, NaN, false, {}]) assert.equal(hasPixDiscount(v), false, String(v));
});

// §17 consignment compatibility: same consignment run with and without a bulk Pix removal in the middle.
async function consignmentRun({removePix}) {
  const db = createConsignmentTestDb();
  const lojaId = 'cons_store';
  const base = seedStore(db, lojaId, {products: {colar: {price: 100, pix: 10, extra: multiCategory}, anel: {price: 80, pix: 5}}});
  db.seed(base.collection('consignment_control').doc('state'), {protocolVersion: 1, moduleEnabled: true});
  db.seed(base.collection('consignment_resellers').doc('r1'), {storeId: lojaId, resellerId: 'r1', displayName: 'R', active: true, notes: ''});
  const run = (operation, operationId, payload = {}, consignmentId = 'c1') => executeConsignmentCommand(db,
    {protocolVersion: 1, lojaId, operation, operationId, consignmentId, payload}, owner);
  const line = productId => ({productId, qtySent: 2, unitSalePrice: 100, commissionType: 'PERCENTUAL', commissionValue: 10});
  await run('createDraft', 'draft_c1', {resellerId: 'r1', notes: '', lines: [line('colar'), line('anel')]});
  await run('issue', 'issue_c1');
  let consignmentBefore = null;
  if (removePix) {
    consignmentBefore = new Map([...db.snapshot()].filter(([p]) => /\/consignment/.test(p)));
    await executeStockCommand(db, bulk(lojaId, opId(27), ['colar', 'anel']), owner);
    const consignmentAfter = new Map([...db.snapshot()].filter(([p]) => /\/consignment/.test(p)));
    assert.deepEqual(consignmentAfter, consignmentBefore, 'CONSIGNMENT_DATA_UNCHANGED by the bulk command');
  }
  const doc = db.getData(base.collection('consignments').doc('c1'));
  await run('settle', 'settle_c1', {lines: doc.lines.map(l => ({lineId: l.lineId, productId: l.productId,
    variationKey: l.variationKey, qtySold: 1, qtyReturned: 1}))});
  return {db, base};
}

test('§17 consignment issue/settle unaffected; projection after settlement keeps Pix removed', async () => {
  const control = await consignmentRun({removePix: false});
  const treated = await consignmentRun({removePix: true});
  const mask = v => v instanceof Date || typeof v?.toMillis === 'function' ? '<ts>' : Array.isArray(v) ? v.map(mask)
    : v && typeof v === 'object' ? Object.fromEntries(Object.keys(v).sort().map(k => [k, mask(v[k])])) : v;
  const view = ({db}) => new Map([...db.snapshot()]
    .filter(([p]) => !p.includes('/stock_catalog_operations/pixrm_'))
    .map(([p, d]) => [p, mask(without(d, [PIX, 'updatedAt']))]));
  assert.deepEqual(view(treated), view(control), 'business output identical except the Pix field');
  for (const id of ['colar', 'anel']) {
    for (const col of ['estoque_produtos', 'draft_produtos', 'produtos']) {
      const doc = treated.db.getData(treated.base.collection(col).doc(id));
      if (doc) assert.equal(hasPixDiscount(doc[PIX]), false, `${col}/${id}`);
    }
    const live = treated.db.getData(treated.base.collection('produtos').doc(id));
    const controlLive = control.db.getData(control.base.collection('produtos').doc(id));
    assert.equal(controlLive[PIX] > 0, true, 'control run keeps its discount');
    assert.deepEqual(live?.categoryAssignments, controlLive?.categoryAssignments);
  }
});
