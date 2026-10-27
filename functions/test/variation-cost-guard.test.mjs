/**
 * Legacy clients (<= 1.0.152) may send `variacoes` without `__custoUnitario`. Omission never erases
 * the remote cost; only `definition.variationCostRemovals` does. In-memory only (no production).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {executeStockCommand} from '../src/stockCatalogCommands.js';
import {
  handleVariationCostGuardEvent,
  parseVariationCostRemovals,
  preserveVariationCosts,
  variationCellId,
} from '../src/variationCostGuard.js';
import {createConsignmentTestDb} from './consignment-test-db.mjs';

const owner = {uid: 'owner'};
const COST = '__custoUnitario';
let seq = 0;

const REMOTE_VARIACOES = {
  P: {Azul: {_sem_extra: 4, [COST]: 2.99}, Rosa: {_sem_extra: 2, [COST]: 3.5}},
  M: {Azul: 3},
};

function seedStore(db, lojaId, {active = true, variacoes = REMOTE_VARIACOES, extra = {}} = {}) {
  const base = db.collection('lojas').doc(lojaId);
  db.seed(base, {ownerUid: 'owner', lojaId});
  if (active) {
    db.seed(base.collection('stock_catalog_control').doc('state'), {protocolVersion: 1, mode: 'active', migrationComplete: true});
    db.seed(base.collection('stock_catalog_access').doc('owner'), {enabled: true, permissions: {editorial: true, adjust: true, publish: true}});
  }
  const sizes = Object.fromEntries(Object.entries(variacoes).map(([s, cells]) =>
    [s, Object.values(cells).reduce((n, c) => n + (typeof c === 'number' ? c : c._sem_extra ?? 0), 0)]));
  const quantidade = Object.values(sizes).reduce((n, q) => n + q, 0);
  db.seed(base.collection('estoque_produtos').doc('A'), {
    lojaId, nome: 'A', stockKind: 'variation', tipoProduto: 'variacao', quantidade, variacoes,
    estoquePorTamanho: sizes, estoquePorCor: {}, tamanhos: Object.keys(variacoes), cores: ['Azul', 'Rosa'],
    variacoesExtraTipo: {}, itensCombo: [], comboConfig: null,
    stockRevision: 7, stockOperationId: 'prev_A', custoReal: 2.99, ...extra,
  });
  db.seed(base.collection('draft_produtos').doc('A'), {nome: 'A', publicadoNoCatalogo: true});
  db.seed(base.collection('stock_catalog_dependencies').doc('A'), {comboIds: []});
  return base;
}

const stockRef = (base, id = 'A') => base.collection('estoque_produtos').doc(id);
const read = (db, base, col, id) => db.getData(base.collection(col).doc(id));
const cost = (variacoes, size, color) => variacoes?.[size]?.[color]?.[COST];

/** Definition shape sent by ProdutoStockCatalogCadastroSync.buildDefinition. */
function replace(lojaId, operationId, variacoes, {expectedRevision = 7, removals} = {}) {
  const sizes = Object.fromEntries(Object.entries(variacoes).map(([s, cells]) =>
    [s, Object.values(cells).reduce((n, c) => n + (typeof c === 'number' ? c : c._sem_extra ?? 0), 0)]));
  return {
    protocolVersion: 1, lojaId, operationId, kind: 'replace',
    items: [{productId: 'A', expectedRevision}],
    editorial: {nome: 'A', publicadoNoCatalogo: true},
    definition: {
      quantidade: Object.values(sizes).reduce((n, q) => n + q, 0), tipoProduto: 'variacao', variacoes,
      estoquePorTamanho: sizes, tamanhos: Object.keys(variacoes), cores: ['Azul', 'Rosa'],
      variacoesExtraTipo: {}, itensCombo: [], comboConfig: null, custoReal: 2.99,
      ...(removals ? {variationCostRemovals: removals} : {}),
    },
  };
}

const LEGACY_SAME_QTY = {P: {Azul: 4, Rosa: 2}, M: {Azul: 3}};

for (const active of [true, false]) {
  const route = active ? 'ACTIVE' : 'NO_CONTROL';

  test(`legacy omission preserves cost: A qty=4 cost=2.99, payload qty=4 without cost (${route})`, async () => {
    const db = createConsignmentTestDb();
    const lojaId = `vcg_${++seq}`;
    const base = seedStore(db, lojaId, {active});
    await executeStockCommand(db, replace(lojaId, 'legacy-same', LEGACY_SAME_QTY), owner);
    const stock = read(db, base, 'estoque_produtos', 'A');
    assert.equal(cost(stock.variacoes, 'P', 'Azul'), 2.99, 'LEGACY_ACCIDENTAL_DELETE_BLOCKED');
    assert.equal(cost(stock.variacoes, 'P', 'Rosa'), 3.5);
    assert.equal(stock.variacoes.P.Azul._sem_extra, 4);
    assert.equal(stock.quantidade, 9);
    assert.equal(stock.stockRevision, 7, 'metadata-only replay does not bump the revision');
    const op = read(db, base, 'stock_catalog_operations', 'legacy-same');
    assert.deepEqual(op.variationCostPreserved, ['p|azul', 'p|rosa']);
    assert.equal('variationCostRemovals' in op, false);
    for (const col of ['draft_produtos', 'produtos']) {
      assert.equal(JSON.stringify(read(db, base, col, 'A') ?? {}).includes(COST), false, `${col} never exposes cost`);
    }
  });

  test(`legacy omission with a quantity change keeps cost and applies the new quantity (${route})`, async () => {
    const db = createConsignmentTestDb();
    const lojaId = `vcg_${++seq}`;
    const base = seedStore(db, lojaId, {active});
    await executeStockCommand(db, replace(lojaId, 'legacy-qty', {P: {Azul: 3, Rosa: 2}, M: {Azul: 3}}), owner);
    const stock = read(db, base, 'estoque_produtos', 'A');
    assert.deepEqual({...stock.variacoes.P.Azul}, {_sem_extra: 3, [COST]: 2.99});
    assert.equal(stock.quantidade, 8);
    assert.equal(stock.stockRevision, 8);
    assert.equal(stock.stockOperationId, 'legacy-qty');
  });

  test(`current explicit clear removes only the listed cell (${route})`, async () => {
    const db = createConsignmentTestDb();
    const lojaId = `vcg_${++seq}`;
    const base = seedStore(db, lojaId, {active});
    await executeStockCommand(db, replace(lojaId, 'clear-azul', LEGACY_SAME_QTY, {removals: ['P|Azul']}), owner);
    const stock = read(db, base, 'estoque_produtos', 'A');
    assert.equal(cost(stock.variacoes, 'P', 'Azul'), undefined, 'CURRENT_EXPLICIT_DELETE_ALLOWED');
    assert.equal(cost(stock.variacoes, 'P', 'Rosa'), 3.5, 'omitted cost of another cell survives');
    assert.equal(stock.quantidade, 9);
    const op = read(db, base, 'stock_catalog_operations', 'clear-azul');
    assert.deepEqual(op.variationCostRemovals, ['p|azul']);
    assert.deepEqual(op.variationCostPreserved, ['p|rosa']);
  });
}

test('a different variation never inherits a cost (new size, new color, renamed size)', async () => {
  const db = createConsignmentTestDb();
  const lojaId = `vcg_${++seq}`;
  const base = seedStore(db, lojaId);
  await executeStockCommand(db, replace(lojaId, 'other-cells', {
    PP: {Azul: 4}, P: {Verde: 1, Rosa: 2}, M: {Azul: 3},
  }), owner);
  const stock = read(db, base, 'estoque_produtos', 'A');
  assert.equal(stock.variacoes.PP.Azul, 4, 'renamed size P->PP is another cell');
  assert.equal(stock.variacoes.P.Verde, 1);
  assert.equal(stock.variacoes.M.Azul, 3, 'M|Azul had no cost and gets none from P|Azul');
  assert.equal(cost(stock.variacoes, 'P', 'Rosa'), 3.5);
  assert.equal(stock.variacoes.P.Azul, undefined);
});

test('remote quantity stays authoritative: stale revision is refused and nothing changes', async () => {
  const db = createConsignmentTestDb();
  const lojaId = `vcg_${++seq}`;
  const base = seedStore(db, lojaId);
  const before = db.snapshot();
  await assert.rejects(
    executeStockCommand(db, replace(lojaId, 'stale', {P: {Azul: 9, Rosa: 9}, M: {Azul: 9}}, {expectedRevision: 6}), owner),
    e => e.code === 'aborted');
  assert.deepEqual(db.snapshot(), before);
});

test('missing cost on both sides adds nothing', async () => {
  const db = createConsignmentTestDb();
  const lojaId = `vcg_${++seq}`;
  const base = seedStore(db, lojaId, {variacoes: {P: {Azul: 4}, M: {Azul: 3}}});
  await executeStockCommand(db, replace(lojaId, 'no-cost', {P: {Azul: 4}, M: {Azul: 2}}), owner);
  const stock = read(db, base, 'estoque_produtos', 'A');
  assert.deepEqual({...stock.variacoes.P}, {Azul: 4});
  assert.deepEqual({...stock.variacoes.M}, {Azul: 2});
  assert.equal('variationCostPreserved' in read(db, base, 'stock_catalog_operations', 'no-cost'), false);
});

test('invalid remote cost (zero) is not preserved', async () => {
  const db = createConsignmentTestDb();
  const lojaId = `vcg_${++seq}`;
  const base = seedStore(db, lojaId, {variacoes: {P: {Azul: {_sem_extra: 4, [COST]: 0}}}});
  await executeStockCommand(db, replace(lojaId, 'zero', {P: {Azul: 4}}), owner);
  assert.equal(read(db, base, 'estoque_produtos', 'A').variacoes.P.Azul, 4);
});

test('tenant mismatch: another store with the same product id never receives the cost', async () => {
  const db = createConsignmentTestDb();
  const lojaA = `vcgA_${++seq}`, lojaB = `vcgB_${seq}`;
  const baseA = seedStore(db, lojaA);
  const baseB = seedStore(db, lojaB, {variacoes: {P: {Azul: 4, Rosa: 2}, M: {Azul: 3}}});
  const priorA = read(db, baseA, 'estoque_produtos', 'A');
  await executeStockCommand(db, replace(lojaB, 'tenant-b', LEGACY_SAME_QTY), owner);
  const stockB = read(db, baseB, 'estoque_produtos', 'A');
  assert.equal(stockB.variacoes.P.Azul, 4);
  assert.equal(stockB.variacoes.P.Rosa, 2);
  assert.deepEqual(read(db, baseA, 'estoque_produtos', 'A'), priorA);
});

test('retry/idempotency: same command replays; changed removals conflict; legacy hash shape unchanged', async () => {
  const db = createConsignmentTestDb();
  const lojaId = `vcg_${++seq}`;
  const base = seedStore(db, lojaId);
  const cmd = replace(lojaId, 'retry-op', LEGACY_SAME_QTY, {removals: ['P|Azul']});
  await executeStockCommand(db, cmd, owner);
  const snapshot = db.snapshot();
  const again = await executeStockCommand(db, structuredClone(cmd), owner);
  assert.equal(again.alreadyApplied, true);
  assert.deepEqual(db.snapshot(), snapshot, 'replay writes nothing');
  await assert.rejects(executeStockCommand(db, replace(lojaId, 'retry-op', LEGACY_SAME_QTY, {removals: ['P|Rosa']}), owner),
    e => e.code === 'already-exists');
  await assert.rejects(executeStockCommand(db, replace(lojaId, 'retry-op', LEGACY_SAME_QTY), owner),
    e => e.code === 'already-exists');

  // Commands without the new field hash exactly like before this protocol addition.
  const legacy = replace(lojaId, 'legacy-hash', {P: {Azul: 4, Rosa: 2}, M: {Azul: 3}},
    {expectedRevision: read(db, base, 'estoque_produtos', 'A').stockRevision});
  await executeStockCommand(db, legacy, owner);
  const ordered = v => Array.isArray(v) ? v.map(ordered) : v && typeof v === 'object'
    ? Object.fromEntries(Object.keys(v).sort().map(k => [k, ordered(v[k])])) : v;
  const parsed = {...legacy, items: legacy.items.map(i => ({...i, size: '', color: '', extra: ''})),
    tombstoneKeys: null, atomicPdvSale: false, atomicSale: null, reconciliation: null};
  const expected = createHash('sha256').update(JSON.stringify(ordered(parsed))).digest('hex');
  assert.equal(read(db, base, 'stock_catalog_operations', 'legacy-hash').requestHash, expected);
});

test('full variation replace: removed cells vanish, kept cell keeps cost, new cells stay without cost', async () => {
  const db = createConsignmentTestDb();
  const lojaId = `vcg_${++seq}`;
  const base = seedStore(db, lojaId);
  await executeStockCommand(db, replace(lojaId, 'full', {P: {Azul: 1}, G: {Preto: 5}}), owner);
  const stock = read(db, base, 'estoque_produtos', 'A');
  assert.deepEqual(Object.keys(stock.variacoes).sort(), ['G', 'P']);
  assert.deepEqual({...stock.variacoes.P.Azul}, {_sem_extra: 1, [COST]: 2.99});
  assert.equal(stock.variacoes.P.Rosa, undefined);
  assert.equal(stock.variacoes.G.Preto, 5);
  assert.equal(stock.quantidade, 6);
});

test('extra-dimension cell keeps its letters and the cost', async () => {
  const db = createConsignmentTestDb();
  const lojaId = `vcg_${++seq}`;
  const base = seedStore(db, lojaId, {variacoes: {P: {Azul: {A: 1, B: 2, [COST]: 4.1}}}});
  await executeStockCommand(db, replace(lojaId, 'extras', {P: {Azul: {A: 1, B: 1}}}), owner);
  assert.deepEqual({...read(db, base, 'estoque_produtos', 'A').variacoes.P.Azul}, {A: 1, B: 1, [COST]: 4.1});
});

test('physical reconciliation keeps the cost and audits real cells', async () => {
  const db = createConsignmentTestDb();
  const lojaId = `vcg_${++seq}`;
  const base = seedStore(db, lojaId);
  await executeStockCommand(db, {
    protocolVersion: 1, lojaId, operationId: 'count-1', kind: 'physicalReconciliation',
    items: [{productId: 'A', expectedRevision: 7}],
    reconciliation: {physicalCountConfirmed: true, reason: 'contagem', cells: [
      {size: 'P', color: 'Azul', quantity: 5}, {size: 'P', color: 'Rosa', quantity: 2}, {size: 'M', color: 'Azul', quantity: 3},
    ]},
  }, owner);
  const stock = read(db, base, 'estoque_produtos', 'A');
  assert.deepEqual({...stock.variacoes.P.Azul}, {_sem_extra: 5, [COST]: 2.99});
  assert.equal(cost(stock.variacoes, 'P', 'Rosa'), 3.5);
  assert.equal(stock.quantidade, 10);
  const op = read(db, base, 'stock_catalog_operations', 'count-1');
  assert.deepEqual(op.variationCostPreserved, ['p|azul', 'p|rosa']);
  assert.equal(op.beforeQty, 9);
  assert.equal(op.afterQty, 10);
  assert.ok(op.beforeCells.length > 0, 'cost key no longer empties the before audit');
  assert.equal(op.beforeCells.some(c => c.extra === COST), false);
  assert.equal(op.afterCells.some(c => c.extra === COST), false);
});

test('protocol validation for variationCostRemovals', async () => {
  const db = createConsignmentTestDb();
  const lojaId = `vcg_${++seq}`;
  seedStore(db, lojaId);
  const invalid = async (cmd, message) => assert.rejects(executeStockCommand(db, cmd, owner),
    e => e.code === 'invalid-argument' && (!message || message.test(e.message)));
  await invalid(replace(lojaId, 'v1', LEGACY_SAME_QTY, {removals: 'P|Azul'}));
  await invalid(replace(lojaId, 'v2', LEGACY_SAME_QTY, {removals: ['sem-separador']}));
  await invalid(replace(lojaId, 'v3', LEGACY_SAME_QTY, {removals: [7]}));
  await invalid(replace(lojaId, 'v4', LEGACY_SAME_QTY, {removals: Array.from({length: 501}, (_, i) => `T${i}|Azul`)}));
  await invalid(replace(lojaId, 'v5', {P: {Azul: {_sem_extra: 4, [COST]: 2.5}}}, {removals: ['P|Azul']}),
    /Conflicting variation cost removal/);
  const create = replace(lojaId, 'v6', LEGACY_SAME_QTY, {removals: ['P|Azul']});
  create.kind = 'create';
  create.items = [{productId: 'novo'}];
  await invalid(create, /only for replace/);
});

test('canonical identity matches the client variacaoId folding', () => {
  assert.equal(variationCellId(' P ', 'Azul  Claro'), 'p|azul claro');
  assert.equal(variationCellId('', ''), 'sem-tamanho|sem-cor');
  assert.deepEqual(parseVariationCostRemovals(['P|Azul', 'p|azul', '|Azul', 'P/M|Rosa']),
    ['p/m|rosa', 'p|azul', 'sem-tamanho|azul']);
  // Two cells with one identity are ambiguous: nothing is copied.
  const ambiguous = preserveVariationCosts({
    before: {'': {Azul: {_sem_extra: 1, [COST]: 2}}, 'sem-tamanho': {Azul: {_sem_extra: 1, [COST]: 3}}},
    incoming: {'sem-tamanho': {Azul: 1}},
  });
  assert.deepEqual(ambiguous.preserved, []);
});

// --- estoque_produtos trigger (direct client writes) ---

const snap = data => data === undefined ? {exists: false, data: () => undefined} : {exists: true, data: () => structuredClone(data)};
const writeEvent = (lojaId, before, after, productId = 'A') =>
  ({params: {lojaId, productId}, data: {before: snap(before), after: snap(after)}});

function legacyDirectWrite(db, base, patch) {
  const before = read(db, base, 'estoque_produtos', 'A');
  const after = {...before, ...patch};
  db.concurrentWrite(stockRef(base), after);
  return {before, after};
}

test('trigger: legacy direct write without cost is restored; quantity, revision and operation id untouched', async () => {
  const db = createConsignmentTestDb();
  const lojaId = `vcgT_${++seq}`;
  const base = seedStore(db, lojaId);
  const {before, after} = legacyDirectWrite(db, base, {
    variacoes: {P: {Azul: 3, Rosa: 2}, M: {Azul: 3}}, estoquePorTamanho: {P: 5, M: 3}, quantidade: 8,
    stockRevision: 8, stockOperationId: 'client-op-1',
  });
  const out = await handleVariationCostGuardEvent(db, writeEvent(lojaId, before, after));
  assert.equal(out.action, 'restored');
  const stock = read(db, base, 'estoque_produtos', 'A');
  assert.deepEqual({...stock.variacoes.P.Azul}, {_sem_extra: 3, [COST]: 2.99});
  assert.deepEqual({...stock.variacoes.P.Rosa}, {_sem_extra: 2, [COST]: 3.5});
  assert.equal(stock.variacoes.M.Azul, 3);
  for (const key of ['quantidade', 'estoquePorTamanho', 'stockRevision', 'stockOperationId', 'custoReal']) {
    assert.deepEqual(stock[key], after[key], `REMOTE_STOCK_AUTHORITY_PRESERVED ${key}`);
  }

  // Redelivery and the trigger's own write are no-ops.
  const commits = db.commits.length;
  assert.equal((await handleVariationCostGuardEvent(db, writeEvent(lojaId, before, after))).action, 'noop');
  assert.equal((await handleVariationCostGuardEvent(db, writeEvent(lojaId, after, stock))).action, 'noop');
  assert.equal(db.commits.slice(commits).some(c => c.ops.length > 0), false, 'no write on redelivery');
  assert.deepEqual(read(db, base, 'estoque_produtos', 'A'), stock);
});

test('trigger: removal recorded by stockCatalogCommand is honored', async () => {
  const db = createConsignmentTestDb();
  const lojaId = `vcgT_${++seq}`;
  const base = seedStore(db, lojaId);
  const before = read(db, base, 'estoque_produtos', 'A');
  await executeStockCommand(db, replace(lojaId, 'clear-op', LEGACY_SAME_QTY, {removals: ['P|Azul']}), owner);
  const after = read(db, base, 'estoque_produtos', 'A');
  const out = await handleVariationCostGuardEvent(db, writeEvent(lojaId, before, after));
  assert.equal(out.action, 'noop');
  assert.equal(cost(read(db, base, 'estoque_produtos', 'A').variacoes, 'P', 'Azul'), undefined);
});

test('trigger: an operation for another product does not authorize a removal', async () => {
  const db = createConsignmentTestDb();
  const lojaId = `vcgT_${++seq}`;
  const base = seedStore(db, lojaId);
  db.seed(base.collection('stock_catalog_operations').doc('foreign-op'), {
    status: 'applied', kind: 'replace', result: {productIds: ['B']}, variationCostRemovals: ['p|azul'],
  });
  const {before, after} = legacyDirectWrite(db, base, {
    variacoes: {P: {Azul: 4, Rosa: 2}, M: {Azul: 3}}, stockRevision: 8, stockOperationId: 'foreign-op',
  });
  assert.equal((await handleVariationCostGuardEvent(db, writeEvent(lojaId, before, after))).action, 'restored');
  assert.equal(cost(read(db, base, 'estoque_produtos', 'A').variacoes, 'P', 'Azul'), 2.99);
});

test('trigger: stale, deleted, created, tenant-mismatched and invalid-cost events change nothing', async () => {
  const db = createConsignmentTestDb();
  const lojaId = `vcgT_${++seq}`;
  const base = seedStore(db, lojaId);
  const {before, after} = legacyDirectWrite(db, base, {
    variacoes: {P: {Azul: 4, Rosa: 2}, M: {Azul: 3}}, stockRevision: 8, stockOperationId: 'client-op-2',
  });
  const newer = {...after, variacoes: {P: {Azul: 1, Rosa: 2}, M: {Azul: 3}}, stockRevision: 9, stockOperationId: 'client-op-3'};
  db.concurrentWrite(stockRef(base), newer);
  assert.equal((await handleVariationCostGuardEvent(db, writeEvent(lojaId, before, after))).reason, 'STALE');
  assert.deepEqual(read(db, base, 'estoque_produtos', 'A'), newer);

  assert.equal((await handleVariationCostGuardEvent(db, writeEvent(lojaId, undefined, after))).reason, 'NOT_UPDATE');
  assert.equal((await handleVariationCostGuardEvent(db, writeEvent(lojaId, before, undefined))).reason, 'NOT_UPDATE');

  const foreign = {...after, lojaId: 'outra_loja'};
  assert.equal((await handleVariationCostGuardEvent(db, writeEvent(lojaId, before, foreign))).reason, 'TENANT_MISMATCH');

  const invalidBefore = {...before, variacoes: {P: {Azul: {_sem_extra: 4, [COST]: '2.99'}, Rosa: {_sem_extra: 2, [COST]: -1}}}};
  assert.equal((await handleVariationCostGuardEvent(db, writeEvent(lojaId, invalidBefore, after))).action, 'noop');

  db.concurrentWrite(stockRef(base), after);
  const removedCell = {...after, variacoes: {M: {Azul: 3}}};
  db.concurrentWrite(stockRef(base), removedCell);
  assert.equal((await handleVariationCostGuardEvent(db, writeEvent(lojaId, before, removedCell))).action, 'noop');
  assert.deepEqual(read(db, base, 'estoque_produtos', 'A'), removedCell);
});

test('trigger deploy manifest: estoque_produtos path, retry, no secrets', async () => {
  process.env.GCLOUD_PROJECT ||= 'masterpalm-58c46';
  const fns = await import('../index.js');
  const endpoint = fns.estoqueProdutoVariationCostGuard.__endpoint;
  assert.deepEqual(endpoint.secretEnvironmentVariables ?? [], []);
  assert.equal(endpoint.eventTrigger.eventFilterPathPatterns.document, 'lojas/{lojaId}/estoque_produtos/{productId}');
  assert.equal(endpoint.eventTrigger.retry, true);
});
