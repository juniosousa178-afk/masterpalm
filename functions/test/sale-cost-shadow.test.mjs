/**
 * Sale cost shadow: compares the cost a sale line carries with the canonical cost of the same
 * store/product/variation and only logs it. In-memory Firestore only — no production access.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {executeStockCommand, executeStockCommandInTransaction, runStockTransaction} from '../src/stockCatalogCommands.js';
import {saleLinesHash, storedSaleLines} from '../src/stockCatalogSaleEdit.js';
import {
  SHADOW_CLASS,
  SHADOW_KIND,
  SALE_COST_SHADOW,
  resolveCanonicalCost,
  classifySaleLine,
  buildSaleCostShadowReport,
  emitSaleCostShadow,
} from '../src/saleCostShadow.js';
import {createConsignmentTestDb} from './consignment-test-db.mjs';

const COST = '__custoUnitario';
const owner = {uid: 'owner'};
const MODES = ['NO_CONTROL', 'ACTIVE'];
let seq = 0;

const GRADE = {
  nome: 'Brinco Gota', stockKind: 'variation', stockRevision: 1, quantidade: 10, custoReal: 1.99,
  variacoes: {A: {'sem-cor': {_sem_extra: 5, [COST]: 2.99}}, B: {'sem-cor': {_sem_extra: 5, [COST]: 3.99}}},
  estoquePorTamanho: {A: 5, B: 5}, tamanhos: ['A', 'B'],
};
const SIMPLE = {nome: 'Corrente', stockKind: 'simple', stockRevision: 1, quantidade: 5, variacoes: {}, custoReal: 10};
const COMBO = {
  nome: 'Kit', stockKind: 'combo', tipoProduto: 'combo', stockRevision: 1, quantidade: 1, custoReal: 7,
  itensCombo: [{productId: 'simples', quantidade: 1}],
};
const PRODUCTS = {grade: GRADE, simples: SIMPLE, combo: COMBO};

const loaded = entries => new Map(Object.entries(entries));
const line = (productId, custoUnitario, {tamanho = '', cor = '', origemCustoItem = 'item', quantidade = 1} = {}) => ({
  produtoNome: PRODUCTS[productId]?.nome ?? productId, quantidade, tamanho, cor,
  precoUnitario: 20, precoTotal: 20 * quantidade, productId, custoUnitario, origemCustoItem,
});
const classify = (l, products = loaded(PRODUCTS), opts = {}) => classifySaleLine(l, {products, ...opts});

// ---------------------------------------------------------------- canonical resolution / classification

test('§14 simple product: custoReal 10, app sends 10 -> MATCH', () => {
  const r = classify(line('simples', 10));
  assert.equal(r.classification, SHADOW_CLASS.MATCH);
  assert.equal(r.canonicalCost, 10);
  assert.equal(r.canonicalSource, 'product');
  assert.equal(r.delta, 0);
});

test('§15 variation cost wins over custoReal: Tam A 2.99 sent 2.99 -> MATCH', () => {
  const r = classify(line('grade', 2.99, {tamanho: 'A', cor: 'sem-cor'}));
  assert.equal(r.classification, SHADOW_CLASS.MATCH);
  assert.equal(r.canonicalCost, 2.99);
  assert.equal(r.canonicalSource, 'variation');
  assert.equal(r.cellId, 'a|sem-cor');
});

test('§16 old client bug: Tam A 2.99, custoReal 1.99, sent 1.99 -> SUSPECT_CLIENT_FALLBACK delta -1.00', () => {
  const r = classify(line('grade', 1.99, {tamanho: 'A', cor: 'sem-cor', origemCustoItem: 'item'}));
  assert.equal(r.classification, SHADOW_CLASS.SUSPECT_CLIENT_FALLBACK);
  assert.equal(r.reason, 'SENT_EQUALS_PRODUCT_COST');
  assert.equal(r.delta, -1);
  assert.equal(r.sentCost, 1.99);
  assert.equal(r.canonicalCost, 2.99);
});

test('§17 other variation: Tam B 3.99 sent 2.99 -> MISMATCH against 3.99, never Tam A', () => {
  const r = classify(line('grade', 2.99, {tamanho: 'B', cor: 'sem-cor'}));
  assert.equal(r.classification, SHADOW_CLASS.MISMATCH);
  assert.equal(r.canonicalCost, 3.99);
  assert.equal(r.cellId, 'b|sem-cor');
  assert.equal(r.delta, -1);
  // Empty color is the technical 'sem-cor' cell of the same size, not another cell.
  assert.equal(classify(line('grade', 3.99, {tamanho: 'B'})).classification, SHADOW_CLASS.MATCH);
});

test('§18 two cells with one canonical identity -> AMBIGUOUS, no cost chosen', () => {
  const dup = {...GRADE, variacoes: {A: {Azul: {_sem_extra: 1, [COST]: 2.99}}, ' a ': {azul: {_sem_extra: 1, [COST]: 9.99}}}};
  for (const sent of [2.99, 9.99, 1.99]) {
    const r = classify(line('grade', sent, {tamanho: 'A', cor: 'Azul'}), loaded({grade: dup}));
    assert.equal(r.classification, SHADOW_CLASS.AMBIGUOUS);
    assert.equal(r.reason, 'DUPLICATE_CELL_IDENTITY');
    assert.equal(r.canonicalCost, null);
    assert.equal(r.delta, null);
  }
  const dupColor = {...GRADE, variacoes: {A: {Azul: {_sem_extra: 1, [COST]: 2.99}, AZUL: {_sem_extra: 1, [COST]: 3.5}}}};
  assert.equal(classify(line('grade', 2.99, {tamanho: 'A', cor: 'azul'}), loaded({grade: dupColor})).classification,
    SHADOW_CLASS.AMBIGUOUS);
});

test('§4 unresolved cell of a variation product -> AMBIGUOUS, never falls back to custoReal or another cell', () => {
  const r = classify(line('grade', 1.99, {tamanho: 'C', cor: 'sem-cor'}));
  assert.equal(r.classification, SHADOW_CLASS.AMBIGUOUS);
  assert.equal(r.reason, 'CELL_NOT_FOUND');
  assert.equal(r.canonicalCost, null);
});

test('§3 cell without valid cost falls back to the product custoReal only (rule B)', () => {
  const noCellCost = {...GRADE, variacoes: {A: {'sem-cor': 5}, B: {'sem-cor': {_sem_extra: 5, [COST]: 3.99}}}};
  const r = classify(line('grade', 1.99, {tamanho: 'A', cor: 'sem-cor'}), loaded({grade: noCellCost}));
  assert.equal(r.classification, SHADOW_CLASS.MATCH);
  assert.equal(r.canonicalSource, 'product');
  assert.equal(r.canonicalCost, 1.99);
});

test('§19 invalid canonical costs (0, negative, NaN, text, missing) never compare', () => {
  for (const bad of [0, -2.99, NaN, '2.99', undefined, Infinity, null]) {
    const cell = bad === undefined ? {_sem_extra: 5} : {_sem_extra: 5, [COST]: bad};
    const withProduct = {...GRADE, variacoes: {A: {'sem-cor': cell}}};
    const fallback = classify(line('grade', 1.99, {tamanho: 'A'}), loaded({grade: withProduct}));
    assert.equal(fallback.canonicalSource, 'product', `cell ${String(bad)} falls back to custoReal`);
    assert.equal(fallback.classification, SHADOW_CLASS.MATCH);
    const {custoReal: _drop, ...noProductCost} = withProduct;
    for (const productCost of [undefined, 0, -1, NaN, '1.99', null]) {
      const product = productCost === undefined ? noProductCost : {...noProductCost, custoReal: productCost};
      const r = classify(line('grade', 2.99, {tamanho: 'A'}), loaded({grade: product}));
      assert.equal(r.classification, SHADOW_CLASS.NO_CANONICAL_COST, `cell ${String(bad)} / product ${String(productCost)}`);
      assert.equal(r.canonicalCost, null);
      assert.equal(r.delta, null);
    }
  }
  for (const productCost of [undefined, 0, -10, NaN, '10']) {
    const product = {...SIMPLE, custoReal: productCost};
    assert.equal(classify(line('simples', 10), loaded({simples: product})).classification, SHADOW_CLASS.NO_CANONICAL_COST);
  }
});

test('§19 invalid sent costs (0, negative, NaN, text, missing) never MATCH or MISMATCH', () => {
  for (const sent of [0, -1.99, NaN, '2.99', undefined, null, Infinity]) {
    const r = classify(line('grade', sent, {tamanho: 'A', origemCustoItem: 'produto'}));
    assert.equal(r.classification, SHADOW_CLASS.NO_SENT_COST, `sent ${String(sent)}`);
    assert.equal(r.delta, null);
    assert.equal(r.canonicalCost, 2.99);
  }
  assert.equal(classify(line('grade', 0, {tamanho: 'A', origemCustoItem: 'zero_intencional'})).classification,
    SHADOW_CLASS.EXPECTED_MANUAL_ORIGIN);
});

test('§8 threshold in cents: <= R$0.01 is MATCH, float noise never mismatches', () => {
  assert.equal(classify(line('simples', 10.01)).classification, SHADOW_CLASS.MATCH);
  assert.equal(classify(line('simples', 9.99)).classification, SHADOW_CLASS.MATCH);
  assert.equal(classify(line('simples', 10.02)).classification, SHADOW_CLASS.MISMATCH);
  assert.equal(classify(line('simples', 9.98)).delta, -0.02);
  const floaty = {...SIMPLE, custoReal: 0.3};
  assert.equal(classify(line('simples', 0.1 + 0.2), loaded({simples: floaty})).classification, SHADOW_CLASS.MATCH);
});

test('§6 manual origins are not reported as bugs; other origins compare normally', () => {
  for (const origin of ['fallback', 'zero_intencional']) {
    const r = classify(line('grade', 1.99, {tamanho: 'A', origemCustoItem: origin}));
    assert.equal(r.classification, SHADOW_CLASS.EXPECTED_MANUAL_ORIGIN, origin);
    assert.equal(r.delta, -1);
  }
  for (const origin of ['item', 'produto', 'desconhecido', undefined, 'valor-novo']) {
    const r = classify(line('grade', 1.99, {tamanho: 'A', origemCustoItem: origin}));
    assert.equal(r.classification, SHADOW_CLASS.SUSPECT_CLIENT_FALLBACK, String(origin));
  }
  assert.equal(classify(line('grade', 1.99, {tamanho: 'A', origemCustoItem: 'valor-novo'})).origemCustoItem, 'other');
  // A divergence on a simple product cannot be the variation fallback bug.
  assert.equal(classify(line('simples', 1.99, {origemCustoItem: 'produto'})).classification, SHADOW_CLASS.MISMATCH);
});

test('§5 combos are skipped: root productId never resolves component cost', () => {
  for (const combo of [COMBO, {...SIMPLE, tipoProduto: 'combo'}, {...SIMPLE, itensCombo: [{productId: 'x', quantidade: 1}]}]) {
    const r = classify(line('combo', 3), loaded({combo}));
    assert.equal(r.classification, SHADOW_CLASS.COMBO_SKIPPED);
    assert.equal(r.canonicalCost, null);
  }
});

test('§13 consignment-origin sale keeps its snapshot: classified separately, never compared', () => {
  const r = classify(line('grade', 0, {tamanho: 'A'}), loaded(PRODUCTS), {consignmentOrigin: true});
  assert.equal(r.classification, SHADOW_CLASS.CONSIGNMENT_SNAPSHOT);
  assert.equal(r.canonicalCost, null);
});

test('line without productId, product not read, product missing', () => {
  const {productId: _p, ...noId} = line('simples', 10);
  assert.equal(classify(noId).classification, SHADOW_CLASS.NO_CANONICAL_COST);
  assert.equal(classify(line('outro', 10)).classification, SHADOW_CLASS.NOT_LOADED);
  const missing = classify(line('gone', 10), loaded({gone: null}));
  assert.equal(missing.classification, SHADOW_CLASS.NO_CANONICAL_COST);
  assert.equal(missing.reason, 'PRODUCT_NOT_FOUND');
  assert.equal(resolveCanonicalCost(undefined).status, 'unavailable');
});

test('§9/§20 report: counters, safe identifiers, only non-MATCH lines, no customer/payment data', () => {
  const report = buildSaleCostShadowReport({
    shadowKind: SHADOW_KIND.PDV_SALE, commandKind: 'sale', lojaId: 'loja_secret_uid', operationId: 'op-123',
    saleId: 'op-123', clientBuild: null, products: loaded(PRODUCTS), now: new Date('2026-10-28T00:00:00Z'),
    lines: [
      line('simples', 10), line('grade', 1.99, {tamanho: 'A'}), line('grade', 2.99, {tamanho: 'B'}),
      line('combo', 1), line('grade', 1, {tamanho: 'A', origemCustoItem: 'fallback'}),
      line('grade', 1, {tamanho: 'Z'}), line('grade', 0, {tamanho: 'A', origemCustoItem: 'produto'}),
      line('missing', 1),
    ],
  });
  assert.equal(report.message, SALE_COST_SHADOW);
  assert.equal(report.severity, 'WARNING');
  assert.deepEqual(report.counters, {
    TOTAL_CHECKED: 8, MATCH: 1, MISMATCH: 1, SUSPECT_CLIENT_FALLBACK: 1, EXPECTED_MANUAL_ORIGIN: 1,
    AMBIGUOUS: 1, NO_CANONICAL_COST: 0, NO_SENT_COST: 1, COMBO_SKIPPED: 1, CONSIGNMENT_SNAPSHOT: 0, NOT_LOADED: 1,
  });
  assert.equal(report.lines.length, 7);
  assert.equal(report.storeHash, createHash('sha256').update('loja_secret_uid').digest('hex').slice(0, 12));
  assert.equal(report.operationRef.length, 16);
  assert.equal(report.clientBuild, null);
  assert.equal(report.at, '2026-10-28T00:00:00.000Z');
  assert.equal(report.comparedWithCurrentCostOnly, false);
  const text = JSON.stringify(report);
  assert.ok(!text.includes('loja_secret_uid'), 'raw store id never logged');
  assert.ok(!text.includes('op-123'), 'raw operation id never logged');
  for (const banned of ['clienteNome', 'clienteId', 'email', 'telefone', 'cpf', 'endereco', 'pagamento',
    'formasPagamento', 'token', 'produtoNome', 'precoUnitario', 'precoTotal']) {
    assert.ok(!text.toLowerCase().includes(banned.toLowerCase()), `no ${banned}`);
  }
  const quiet = buildSaleCostShadowReport({shadowKind: SHADOW_KIND.SALE_EDIT, commandKind: 'saleEdit', lojaId: 'l',
    operationId: 'o', clientBuild: '1.0.157+172', products: loaded(PRODUCTS), lines: [line('simples', 10)]});
  assert.equal(quiet.severity, 'INFO');
  assert.deepEqual(quiet.lines, []);
  assert.equal(quiet.clientBuild, '1.0.157+172');
  assert.equal(quiet.comparedWithCurrentCostOnly, true);
});

test('emit never throws, even when the logger does', () => {
  const calls = [];
  emitSaleCostShadow({severity: 'WARNING', a: 1}, {warn: l => calls.push(['warn', l]), info: l => calls.push(['info', l])});
  emitSaleCostShadow({severity: 'INFO'}, {warn: l => calls.push(['warn', l]), info: l => calls.push(['info', l])});
  assert.deepEqual(calls.map(c => c[0]), ['warn', 'info']);
  assert.doesNotThrow(() => emitSaleCostShadow({severity: 'WARNING'}, {warn: () => { throw new Error('boom'); }}));
  const cyclic = {}; cyclic.self = cyclic;
  assert.doesNotThrow(() => emitSaleCostShadow(cyclic));
});

// ---------------------------------------------------------------- stockCatalogCommand integration

function seedStore(db, mode, lojaId, products = PRODUCTS) {
  const base = db.collection('lojas').doc(lojaId);
  db.seed(base, {ownerUid: 'owner', lojaId});
  if (mode === 'ACTIVE') {
    db.seed(base.collection('stock_catalog_control').doc('state'), {protocolVersion: 1, mode: 'active', migrationComplete: true});
    db.seed(base.collection('stock_catalog_access').doc('owner'), {enabled: true, permissions: {sale: true}});
  }
  for (const [id, data] of Object.entries(products)) {
    db.seed(base.collection('estoque_produtos').doc(id), data);
    if (mode === 'ACTIVE') {
      db.seed(base.collection('draft_produtos').doc(id), {nome: data.nome, publicadoNoCatalogo: true});
      db.seed(base.collection('stock_catalog_dependencies').doc(id), {comboIds: id === 'simples' ? ['combo'] : []});
    }
  }
  return base;
}

function pdvSale(lojaId, operationId, {size = 'A', color = 'sem-cor', sent = 1.99, origin = 'item'} = {}) {
  return {
    protocolVersion: 1, lojaId, operationId, kind: 'sale', atomicPdvSale: true,
    items: [{productId: 'grade', quantity: 1, size, color}],
    sale: {
      clienteNome: 'Maria Cliente', total: 20, preco: 20, pagamentoPix: 20, formasPagamento: 'PIX',
      custoProdutos: sent, quantidade: 1,
      itens: [line('grade', sent, {tamanho: size, cor: color, origemCustoItem: origin})],
    },
  };
}

async function captureLogs(fn) {
  const logs = [];
  const original = {info: console.info, warn: console.warn};
  console.info = l => logs.push(l);
  console.warn = l => logs.push(l);
  try { return {value: await fn(), logs}; } finally { Object.assign(console, original); }
}
const shadowLogs = logs => logs.filter(l => typeof l === 'string' && l.includes(SALE_COST_SHADOW)).map(l => JSON.parse(l));

for (const mode of MODES) {
  test(`[${mode}] §7/§16 PDV old-bug sale: shadow flags it, sale/stock/response identical to no-shadow run`, async () => {
    const lojaId = `shadow_${mode}_${++seq}`;
    const plainDb = createConsignmentTestDb(), shadowDb = createConsignmentTestDb();
    seedStore(plainDb, mode, lojaId); const base = seedStore(shadowDb, mode, lojaId);
    const reads = {plain: 0, shadow: 0};
    plainDb.onRead = () => reads.plain++;
    shadowDb.onRead = () => reads.shadow++;
    const plain = await runStockTransaction(plainDb, tx => executeStockCommandInTransaction(tx, plainDb, pdvSale(lojaId, 'op-bug'), owner));
    const {value: shadowed, logs} = await captureLogs(() => executeStockCommand(shadowDb, pdvSale(lojaId, 'op-bug'), owner));

    assert.deepEqual(shadowed, plain, 'response unchanged');
    assert.deepEqual(shadowDb.snapshot(), plainDb.snapshot(), 'every document unchanged');
    assert.equal(reads.shadow, reads.plain, 'ADDITIONAL_FIRESTORE_READS_PER_SALE=0');
    assert.deepEqual(shadowDb.commits.map(c => c.ops), plainDb.commits.map(c => c.ops), 'same writes');
    const sale = shadowDb.getData(base.collection('estoque_vendas').doc('op-bug'));
    assert.equal(sale.itens[0].custoUnitario, 1.99, 'sale keeps the cost the app sent');
    assert.equal(sale.custoProdutos, 1.99);
    assert.equal(sale.total, 20);

    const [entry, ...rest] = shadowLogs(logs);
    assert.equal(rest.length, 0);
    assert.equal(entry.severity, 'WARNING');
    assert.equal(entry.shadowKind, SHADOW_KIND.PDV_SALE);
    assert.equal(entry.commandKind, 'sale');
    assert.equal(entry.counters.SUSPECT_CLIENT_FALLBACK, 1);
    assert.deepEqual(entry.lines.map(l => [l.classification, l.sentCost, l.canonicalCost, l.delta, l.variation]),
      [[SHADOW_CLASS.SUSPECT_CLIENT_FALLBACK, 1.99, 2.99, -1, 'a|sem-cor']]);
    assert.equal(entry.clientBuild, null, 'PDV sale commands carry no clientBuild today');
    assert.ok(!JSON.stringify(entry).includes('Maria'), 'no customer name');
    assert.ok(!JSON.stringify(entry).includes(lojaId), 'store id hashed');
  });

  test(`[${mode}] §15/§17 PDV: correct variation cost is MATCH; Tam B compared only with Tam B`, async () => {
    const db = createConsignmentTestDb();
    const lojaId = `shadow_${mode}_${++seq}`;
    seedStore(db, mode, lojaId);
    const ok = await captureLogs(() => executeStockCommand(db, pdvSale(lojaId, 'op-ok', {sent: 2.99}), owner));
    const [match] = shadowLogs(ok.logs);
    assert.equal(match.severity, 'INFO');
    assert.equal(match.counters.MATCH, 1);
    assert.deepEqual(match.lines, []);
    const other = await captureLogs(() => executeStockCommand(db, pdvSale(lojaId, 'op-b', {size: 'B', sent: 2.99}), owner));
    const [mismatch] = shadowLogs(other.logs);
    assert.deepEqual(mismatch.lines.map(l => [l.classification, l.canonicalCost, l.delta]),
      [[SHADOW_CLASS.MISMATCH, 3.99, -1]]);
  });

  test(`[${mode}] replay of an applied sale logs nothing and writes nothing`, async () => {
    const db = createConsignmentTestDb();
    const lojaId = `shadow_${mode}_${++seq}`;
    seedStore(db, mode, lojaId);
    await captureLogs(() => executeStockCommand(db, pdvSale(lojaId, 'op-replay'), owner));
    const before = db.snapshot();
    const again = await captureLogs(() => executeStockCommand(db, pdvSale(lojaId, 'op-replay'), owner));
    assert.equal(again.value.alreadyApplied, true);
    assert.deepEqual(shadowLogs(again.logs), []);
    assert.deepEqual(db.snapshot(), before);
  });

  test(`[${mode}] rejected sale emits no shadow; non-atomic stock sale is not shadowed`, async () => {
    const db = createConsignmentTestDb();
    const lojaId = `shadow_${mode}_${++seq}`;
    seedStore(db, mode, lojaId, {...PRODUCTS, grade: {...GRADE, variacoes: {A: {'sem-cor': {_sem_extra: 0, [COST]: 2.99}}}, quantidade: 0}});
    const rejected = await captureLogs(() => assert.rejects(executeStockCommand(db, pdvSale(lojaId, 'op-none'), owner)));
    assert.deepEqual(shadowLogs(rejected.logs), []);
    const stockOnly = await captureLogs(() => executeStockCommand(db, {
      protocolVersion: 1, lojaId, operationId: 'op-stock', kind: 'sale', items: [{productId: 'simples', quantity: 1}],
    }, owner));
    assert.equal(stockOnly.value.alreadyApplied, false);
    assert.deepEqual(shadowLogs(stockOnly.logs), []);
  });
}

test('shadow callback failure never affects the sale commit or response', async () => {
  const lojaId = `shadow_fail_${++seq}`;
  const plainDb = createConsignmentTestDb(), failDb = createConsignmentTestDb();
  seedStore(plainDb, 'ACTIVE', lojaId); seedStore(failDb, 'ACTIVE', lojaId);
  const plain = await runStockTransaction(plainDb, tx => executeStockCommandInTransaction(tx, plainDb, pdvSale(lojaId, 'op-f'), owner));
  const failing = await runStockTransaction(failDb, tx => executeStockCommandInTransaction(tx, failDb, pdvSale(lojaId, 'op-f'), owner, 0,
    {onSaleCostShadow: () => { throw new Error('shadow exploded'); }}));
  assert.deepEqual(failing, plain);
  assert.deepEqual(failDb.snapshot(), plainDb.snapshot());
});

test('tenant isolation: canonical cost comes only from the command store', async () => {
  const db = createConsignmentTestDb();
  const lojaA = `shadow_tenant_a_${++seq}`, lojaB = `shadow_tenant_b_${seq}`;
  seedStore(db, 'ACTIVE', lojaA);
  seedStore(db, 'ACTIVE', lojaB, {...PRODUCTS, grade: {...GRADE, variacoes: {
    A: {'sem-cor': {_sem_extra: 5, [COST]: 1.99}}, B: {'sem-cor': {_sem_extra: 5, [COST]: 3.99}}}}});
  const {logs} = await captureLogs(() => executeStockCommand(db, pdvSale(lojaB, 'op-t', {sent: 1.99}), owner));
  const [entry] = shadowLogs(logs);
  assert.equal(entry.counters.MATCH, 1, 'store B cell cost 1.99, not store A 2.99');
  assert.equal(entry.counters.SUSPECT_CLIENT_FALLBACK, 0);
});

// ---------------------------------------------------------------- saleEdit

function seedSale(db, base, lojaId, lines, extra = {}) {
  db.seed(base.collection('estoque_vendas').doc('sale-1'), {
    id: 'sale-1', lojaId, total: 40, clienteNome: 'Cliente Teste', itens: lines, cancelada: false,
    estornada: false, status: 'concluida', stockOperationId: 'sale-1', ...extra,
  });
}
function editCommand(lojaId, oldLines, newLines, {clientBuild} = {}) {
  return {
    protocolVersion: 1, lojaId, kind: 'saleEdit',
    operationId: `saleedit_${createHash('sha256').update(`${lojaId}|${++seq}`).digest('hex')}`,
    saleEdit: {
      saleId: 'sale-1',
      expectedOriginalLinesHash: saleLinesHash(storedSaleLines(oldLines)),
      sale: {clienteNome: 'Cliente Teste', total: 40, itens: newLines},
    },
    ...(clientBuild ? {clientBuild} : {}),
  };
}

for (const mode of MODES) {
  test(`[${mode}] §12 SALE_EDIT_SHADOW: changed line compared with current cost, unchanged line not read, sale keeps sent cost`, async () => {
    const db = createConsignmentTestDb();
    const lojaId = `shadow_edit_${mode}_${++seq}`;
    const base = seedStore(db, mode, lojaId);
    const oldLines = [line('simples', 10), line('grade', 1.99, {tamanho: 'A', cor: 'sem-cor'})];
    seedSale(db, base, lojaId, oldLines);
    const newLines = [line('simples', 10), line('grade', 1.99, {tamanho: 'A', cor: 'sem-cor', quantidade: 2})];
    const {value, logs} = await captureLogs(() =>
      executeStockCommand(db, editCommand(lojaId, oldLines, newLines, {clientBuild: '1.0.157+172'}), owner));
    assert.equal(value.saleCommitted, true);
    const sale = db.getData(base.collection('estoque_vendas').doc('sale-1'));
    assert.deepEqual(sale.itens.map(i => i.custoUnitario), [10, 1.99], 'edited sale keeps the costs the app sent');
    const [entry] = shadowLogs(logs);
    assert.equal(entry.shadowKind, SHADOW_KIND.SALE_EDIT);
    assert.equal(entry.commandKind, 'saleEdit');
    assert.equal(entry.comparedWithCurrentCostOnly, true);
    assert.equal(entry.clientBuild, '1.0.157+172');
    assert.ok(entry.saleRef && !JSON.stringify(entry).includes('sale-1'));
    assert.equal(entry.counters.NOT_LOADED, 1, 'unchanged line product is not read for the shadow');
    assert.equal(entry.counters.SUSPECT_CLIENT_FALLBACK, 1);
  });

  test(`[${mode}] §13 edit of a consignment-origin sale is classified separately`, async () => {
    const db = createConsignmentTestDb();
    const lojaId = `shadow_csgn_${mode}_${++seq}`;
    const base = seedStore(db, mode, lojaId);
    const oldLines = [line('grade', 0, {tamanho: 'A', cor: 'sem-cor'})];
    seedSale(db, base, lojaId, oldLines, {origemVenda: 'consignment', saleOrigin: 'consignment'});
    const newLines = [line('grade', 0, {tamanho: 'A', cor: 'sem-cor', quantidade: 2})];
    const {logs} = await captureLogs(() => executeStockCommand(db, editCommand(lojaId, oldLines, newLines), owner));
    const [entry] = shadowLogs(logs);
    assert.equal(entry.counters.CONSIGNMENT_SNAPSHOT, 1);
    assert.equal(entry.counters.NO_SENT_COST, 0);
    assert.equal(db.getData(base.collection('estoque_vendas').doc('sale-1')).itens[0].custoUnitario, 0);
  });
}
