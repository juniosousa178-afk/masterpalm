/**
 * saleEdit restore into a variation removed from the commercial grade after the sale consumed it.
 * In-memory Firestore only — no production access.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {executeStockCommand} from '../src/stockCatalogCommands.js';
import {
  saleLinesHash,
  storedSaleLines,
  applyRemovedVariation,
  originalSaleCellQuantity,
  historicalStockCells,
  REMOVED_VARIATION_DEBIT,
} from '../src/stockCatalogSaleEdit.js';
import {normalizeStock, projectCatalog} from '../src/catalogStockProjection.js';
import {createConsignmentTestDb} from './consignment-test-db.mjs';

const owner = {uid: 'owner'};
const MODES = ['NO_CONTROL', 'ACTIVE'];
const PID = 'berloque';
const NOME = 'Berloque Placa Mãe De Menino/menina Prata 925';
const REMOVED_MESSAGE = 'Esta venda possui uma variação antiga que não existe mais no cadastro do produto: MENINO. ' +
  'Nenhuma alteração foi feita.';
let seq = 0;

/** Mirrors the Mir product: MENINO removed from `variacoes`, metadata still lists it. */
function berloque(meninaQty = 0, extra = {}) {
  return {
    nome: NOME, stockKind: 'variation', stockRevision: 7, quantidade: meninaQty,
    variacoes: {MENINA: {'sem-cor': meninaQty}}, estoquePorTamanho: {MENINA: meninaQty}, estoquePorCor: {},
    tamanhos: ['MENINO', 'MENINA'], cores: [],
    variacoesExtraTipo: {MENINA: {'sem-cor': {_sem_extra: 'Modelo'}}, MENINO: {'sem-cor': {_sem_extra: 'Modelo'}}},
    publicadoNoCatalogo: true, ...extra,
  };
}
const simples = {nome: 'Corrente Simples', stockKind: 'simple', stockRevision: 1, quantidade: 5, variacoes: {}};

function line(productId, quantidade, {tamanho = '', cor = '', preco = 67, nome} = {}) {
  return {
    produtoNome: nome ?? (productId === PID ? NOME : productId), quantidade, tamanho, cor,
    precoUnitario: preco, precoTotal: preco * quantidade, productId, custoUnitario: 0, origemCustoItem: 'desconhecido',
  };
}
const menino = (q = 1) => line(PID, q, {tamanho: 'MENINO', cor: 'sem-cor'});
const menina = (q = 1) => line(PID, q, {tamanho: 'MENINA', cor: 'sem-cor'});

function seedStore(mode, {products = {[PID]: berloque(), simples}, saleLines = [menino(1), line('simples', 1, {preco: 10})],
  grantPerms = {sale: true}} = {}) {
  const db = createConsignmentTestDb();
  const lojaId = `loja_${mode.toLowerCase()}_${++seq}`;
  const base = db.collection('lojas').doc(lojaId);
  db.seed(base, {ownerUid: 'owner', lojaId});
  if (mode === 'ACTIVE') {
    db.seed(base.collection('stock_catalog_control').doc('state'), {protocolVersion: 1, mode: 'active', migrationComplete: true});
    db.seed(base.collection('stock_catalog_access').doc('owner'), {enabled: true, permissions: grantPerms});
  }
  for (const [id, data] of Object.entries(products)) {
    db.seed(base.collection('estoque_produtos').doc(id), data);
    // Like Mir (NO_CONTROL with an editorial draft), every product carries a draft.
    db.seed(base.collection('draft_produtos').doc(id), {nome: data.nome, publicadoNoCatalogo: true});
    if (mode === 'ACTIVE') db.seed(base.collection('stock_catalog_dependencies').doc(id), {comboIds: []});
  }
  db.seed(base.collection('estoque_vendas').doc('sale-1'), {
    id: 'sale-1', lojaId, total: 77, clienteNome: 'Cliente Teste', itens: saleLines, cancelada: false,
    estornada: false, status: 'concluida',
  });
  return {db, base, lojaId};
}

function editCommand(lojaId, newLines, {saleId = 'sale-1', expected, opId, stored} = {}) {
  return {
    protocolVersion: 1, lojaId, kind: 'saleEdit',
    operationId: opId ?? `saleedit_${createHash('sha256').update(`${lojaId}|${saleId}|${++seq}`).digest('hex')}`,
    saleEdit: {
      saleId,
      expectedOriginalLinesHash: expected ?? saleLinesHash(storedSaleLines(stored)),
      sale: {clienteNome: 'Cliente Teste', total: 10, itens: newLines},
    },
  };
}
const storedLines = (db, base) => db.getData(base.collection('estoque_vendas').doc('sale-1')).itens;
const stock = (db, base, id = PID) => db.getData(base.collection('estoque_produtos').doc(id));
const draft = (db, base, id = PID) => db.getData(base.collection('draft_produtos').doc(id));
const live = (db, base, id = PID) => db.getData(base.collection('produtos').doc(id));
const writesSince = (db, from) => db.commits.slice(from).flatMap(c => c.ops).length;
const historical = (db, base) => stock(db, base)?.historicalStockCells ?? [];
const edit = (db, base, lojaId, newLines, opts = {}, auth = owner) =>
  executeStockCommand(db, editCommand(lojaId, newLines, {...opts, stored: storedLines(db, base)}), auth);

function rejectsWith(promise, {code, detail, reason, issueReason, issueMessage}) {
  return assert.rejects(promise, e => {
    if (code && e.code !== code) return false;
    if (detail && e.details?.code !== detail) return false;
    if (reason && e.details?.reason !== reason) return false;
    const issues = e.issues ?? [];
    if (issueReason && !issues.some(i => i.reasonCode === issueReason)) return false;
    if (issueMessage && !issues.some(i => i.userMessage === issueMessage)) return false;
    return true;
  });
}

function assertCommercialGradeUnchanged(db, base, meninaQty = 0) {
  const s = stock(db, base);
  assert.deepEqual(s.variacoes, {MENINA: {'sem-cor': meninaQty}}, 'MENINO never re-enters the sellable grade');
  assert.deepEqual(s.estoquePorTamanho, {MENINA: meninaQty});
  assert.equal(s.quantidade, meninaQty, 'historical units never count as stock');
  assert.deepEqual(s.tamanhos, ['MENINO', 'MENINA'], 'grade metadata untouched');
  const d = draft(db, base);
  assert.equal('historicalStockCells' in d, false, 'never projected to the editorial draft');
  if (d.variacoes) assert.equal('MENINO' in d.variacoes, false);
  const l = live(db, base);
  if (l) {
    assert.equal('historicalStockCells' in l, false, 'never published');
    assert.equal('MENINO' in (l.variacoes ?? {}), false);
  }
}

for (const mode of MODES) {
  test(`[${mode}] A removing the MENINO line restores +1 into a restore-only historical cell`, async () => {
    const {db, base, lojaId} = seedStore(mode);
    const before = stock(db, base);
    const from = db.commits.length;
    const r = await edit(db, base, lojaId, [line('simples', 1, {preco: 10})]);
    assert.equal(r.stockChanged, true);
    assert.deepEqual(historical(db, base), [{size: 'MENINO', color: 'sem-cor', extra: '', quantidade: 1}]);
    assertCommercialGradeUnchanged(db, base);
    assert.equal(stock(db, base).stockRevision, before.stockRevision + 1, 'historical stock is a canonical stock effect');
    assert.equal(live(db, base), undefined, 'nothing published');
    const sale = db.getData(base.collection('estoque_vendas').doc('sale-1'));
    assert.deepEqual(sale.itens.map(l => l.productId), ['simples']);
    const op = db.getData(base.collection('stock_catalog_operations').doc(r.operationId));
    assert.deepEqual(op.items, [{productId: PID, quantity: 1, size: 'MENINO', color: 'sem-cor', extra: '',
      direction: 'restore', historicalCell: true}]);
    const commits = db.commits.slice(from).filter(c => c.ops.length);
    assert.equal(commits.length, 1, 'historical cell, stock and sale doc commit together');
    const paths = commits[0].ops.map(o => o.path);
    assert.ok(paths.some(p => p.endsWith(`/estoque_produtos/${PID}`)));
    assert.ok(paths.some(p => p.endsWith('/estoque_vendas/sale-1')));
    assert.ok(paths.some(p => p.includes('/stock_catalog_operations/')));
  });

  test(`[${mode}] B restore above the original consumption is impossible; forged original fails closed`, async () => {
    const {db, base, lojaId} = seedStore(mode);
    const snap = db.snapshot();
    const forged = storedSaleLines([menino(2), line('simples', 1, {preco: 10})]);
    await rejectsWith(edit(db, base, lojaId, [line('simples', 1, {preco: 10})], {expected: saleLinesHash(forged)}),
      {code: 'aborted', detail: 'SALE_EDIT_CONFLICT'});
    assert.deepEqual(db.snapshot(), snap);
    assert.equal(historical(db, base).length, 0);
  });

  test(`[${mode}] C sale never had MENINO: adding it fails with VARIATION_NOT_FOUND, 0 writes`, async () => {
    const {db, base, lojaId} = seedStore(mode, {saleLines: [line('simples', 1, {preco: 10})]});
    const snap = db.snapshot();
    await rejectsWith(edit(db, base, lojaId, [line('simples', 1, {preco: 10}), menino(1)]),
      {detail: 'PRODUCT_VALIDATION_FAILED', issueReason: 'VARIATION_NOT_FOUND'});
    assert.deepEqual(db.snapshot(), snap);
  });

  test(`[${mode}] D MENINO 1→2 while removed is blocked with the removed-variation message, 0 writes`, async () => {
    const {db, base, lojaId} = seedStore(mode);
    const snap = db.snapshot();
    await rejectsWith(edit(db, base, lojaId, [menino(2), line('simples', 1, {preco: 10})]),
      {detail: 'PRODUCT_VALIDATION_FAILED', issueReason: 'HISTORICAL_VARIATION_REMOVED', issueMessage: REMOVED_MESSAGE});
    assert.deepEqual(db.snapshot(), snap);
  });

  test(`[${mode}] E MENINO→MENINA: historical MENINO +1 and MENINA −1 in one commit`, async () => {
    const {db, base, lojaId} = seedStore(mode, {products: {[PID]: berloque(1), simples}});
    const from = db.commits.length;
    await edit(db, base, lojaId, [menina(1), line('simples', 1, {preco: 10})]);
    assert.deepEqual(historical(db, base), [{size: 'MENINO', color: 'sem-cor', extra: '', quantidade: 1}]);
    assertCommercialGradeUnchanged(db, base, 0);
    assert.equal(db.commits.slice(from).filter(c => c.ops.length).length, 1);
  });

  test(`[${mode}] F MENINO→MENINA without MENINA stock: INSUFFICIENT_STOCK, 0 writes`, async () => {
    const {db, base, lojaId} = seedStore(mode);
    const snap = db.snapshot();
    await rejectsWith(edit(db, base, lojaId, [menina(1), line('simples', 1, {preco: 10})]),
      {detail: 'PRODUCT_VALIDATION_FAILED', issueReason: 'INSUFFICIENT_STOCK'});
    assert.deepEqual(db.snapshot(), snap);
  });

  test(`[${mode}] G replay never duplicates the historical restore`, async () => {
    const {db, base, lojaId} = seedStore(mode);
    const cmd = editCommand(lojaId, [line('simples', 1, {preco: 10})], {stored: storedLines(db, base)});
    await executeStockCommand(db, cmd, owner);
    const from = db.commits.length;
    const replay = await executeStockCommand(db, cmd, owner);
    assert.equal(replay.alreadyApplied, true);
    assert.equal(writesSince(db, from), 0);
    // A fresh edit of the already-edited sale has no MENINO left to restore.
    await edit(db, base, lojaId, [line('simples', 1, {preco: 10})]);
    assert.deepEqual(historical(db, base), [{size: 'MENINO', color: 'sem-cor', extra: '', quantidade: 1}]);
  });

  test(`[${mode}] H same operationId with altered payload fails closed`, async () => {
    const {db, base, lojaId} = seedStore(mode);
    const original = storedLines(db, base);
    const opId = `saleedit_${'c'.repeat(64)}`;
    await executeStockCommand(db, editCommand(lojaId, [line('simples', 1, {preco: 10})], {stored: original, opId}), owner);
    const snap = db.snapshot();
    await rejectsWith(executeStockCommand(db, editCommand(lojaId, [line('simples', 2, {preco: 10})], {stored: original, opId}), owner),
      {code: 'already-exists', detail: 'OPERATION_PAYLOAD_CONFLICT'});
    assert.deepEqual(db.snapshot(), snap);
    assert.equal(historical(db, base)[0].quantidade, 1);
  });

  test(`[${mode}] I cross-tenant: foreign actor and foreign sale cannot restore historical stock`, async () => {
    const mine = seedStore(mode);
    const other = seedStore(mode);
    const snapMine = mine.db.snapshot();
    await rejectsWith(edit(mine.db, mine.base, mine.lojaId, [line('simples', 1, {preco: 10})], {}, {uid: 'intruder'}),
      {code: 'permission-denied'});
    assert.deepEqual(mine.db.snapshot(), snapMine);
    // The other store's sale id does not exist here; the product id collision grants nothing.
    await rejectsWith(executeStockCommand(mine.db, editCommand(mine.lojaId, [line('simples', 1, {preco: 10})],
      {saleId: 'sale-of-other-store', stored: storedLines(other.db, other.base)}), owner), {reason: 'SALE_NOT_FOUND'});
    // A sale document carrying a foreign lojaId is rejected before any stock is read.
    mine.db.seed(mine.base.collection('estoque_vendas').doc('sale-1'), {
      ...mine.db.getData(mine.base.collection('estoque_vendas').doc('sale-1')), lojaId: other.lojaId,
    });
    const snap = mine.db.snapshot();
    await rejectsWith(edit(mine.db, mine.base, mine.lojaId, [line('simples', 1, {preco: 10})]), {reason: 'SALE_STORE_MISMATCH'});
    assert.deepEqual(mine.db.snapshot(), snap);
    assert.equal(historical(mine.db, mine.base).length, 0);
  });

  test(`[${mode}] historical units are never debited back by a later edit`, async () => {
    const {db, base, lojaId} = seedStore(mode);
    await edit(db, base, lojaId, [line('simples', 1, {preco: 10})]);
    const snap = db.snapshot();
    await rejectsWith(edit(db, base, lojaId, [line('simples', 1, {preco: 10}), menino(1)]),
      {issueReason: 'VARIATION_NOT_FOUND'});
    assert.deepEqual(db.snapshot(), snap);
  });

  test(`[${mode}] new sales cannot select the historical cell`, async () => {
    const {db, base, lojaId} = seedStore(mode, {products: {[PID]: berloque(0, {
      historicalStockCells: [{size: 'MENINO', color: 'sem-cor', extra: '', quantidade: 3}],
    }), simples}});
    const snap = db.snapshot();
    await rejectsWith(executeStockCommand(db, {protocolVersion: 1, lojaId, operationId: `sale_hist_${mode}`, kind: 'sale',
      items: [{productId: PID, quantity: 1, size: 'MENINO', color: 'sem-cor'}]}, owner),
    {issueReason: 'VARIATION_NOT_FOUND'});
    assert.deepEqual(db.snapshot(), snap);
  });

  test(`[${mode}] tampered historicalStockCells cannot create sellable stock`, async () => {
    const tampered = [
      {size: 'MENINO', color: 'sem-cor', extra: '', quantidade: 9999},
      {size: 'MENINA', color: 'sem-cor', extra: '', quantidade: 9999},
      {size: 'GAROTO', color: 'sem-cor', extra: '', quantidade: 9999},
    ];
    const grants = {sale: true, restock: true};
    const {db, base, lojaId} = seedStore(mode, {products: {[PID]: berloque(0, {historicalStockCells: tampered}), simples},
      grantPerms: grants});
    const snap = db.snapshot();
    const sale = (size, q = 1) => executeStockCommand(db, {protocolVersion: 1, lojaId, operationId: `sale_${size}_${mode}_${++seq}`,
      kind: 'sale', items: [{productId: PID, quantity: q, size, color: 'sem-cor'}]}, owner);
    await rejectsWith(sale('MENINO'), {issueReason: 'VARIATION_NOT_FOUND'});
    await rejectsWith(sale('GAROTO'), {issueReason: 'VARIATION_NOT_FOUND'});
    await rejectsWith(sale('MENINA'), {issueReason: 'INSUFFICIENT_STOCK'});
    await rejectsWith(edit(db, base, lojaId, [menino(2), line('simples', 1, {preco: 10})]),
      {issueReason: 'HISTORICAL_VARIATION_REMOVED'});
    await rejectsWith(edit(db, base, lojaId, [menino(1), menina(1), line('simples', 1, {preco: 10})]),
      {issueReason: 'INSUFFICIENT_STOCK'});
    await rejectsWith(edit(db, base, lojaId, [menino(1), line(PID, 1, {tamanho: 'GAROTO', cor: 'sem-cor'}),
      line('simples', 1, {preco: 10})]), {issueReason: 'VARIATION_NOT_FOUND'});
    await rejectsWith(executeStockCommand(db, {protocolVersion: 1, lojaId, operationId: `restock_tamper_${mode}`, kind: 'restock',
      items: [{productId: PID, quantity: 1, size: 'MENINO', color: 'sem-cor'}]}, owner),
    mode === 'NO_CONTROL' ? {detail: 'LEGACY_PROTOCOL_BLOCKED'} : {issueReason: 'VARIATION_NOT_FOUND'});
    assert.deepEqual(db.snapshot(), snap, 'no tampered value reached stock, sale, draft or catalog');
    const p = projectCatalog(normalizeStock(stock(db, base)), {nome: NOME, publicadoNoCatalogo: true}, PID);
    assert.equal(p.stock.quantidade, 0, 'commercial availability ignores historical cells');
    assert.equal(p.live, null, 'nothing to publish');
    assert.equal('historicalStockCells' in p.draft, false);
    assert.deepEqual(p.draft.variacoes, {MENINA: {'sem-cor': 0}});
    // Restore allowance comes from the saved sale only: +1, regardless of the tampered counter.
    await edit(db, base, lojaId, [line('simples', 1, {preco: 10})]);
    assert.equal(historical(db, base).find(c => c.size === 'MENINO').quantidade, 10000);
    assert.equal(stock(db, base).quantidade, 0);
  });

  test(`[${mode}] malformed historicalStockCells fails closed on restore`, async () => {
    const {db, base, lojaId} = seedStore(mode, {products: {[PID]: berloque(0, {historicalStockCells: {MENINO: 50}}), simples}});
    const snap = db.snapshot();
    await rejectsWith(edit(db, base, lojaId, [line('simples', 1, {preco: 10})]), {detail: 'PRODUCT_VALIDATION_FAILED'});
    assert.deepEqual(db.snapshot(), snap);
  });

  test(`[${mode}] deleted product: no historical restore`, async () => {
    const {db, base, lojaId} = seedStore(mode, {products: {[PID]: berloque(0, {pendingSoftDelete: true}), simples}});
    const snap = db.snapshot();
    await rejectsWith(edit(db, base, lojaId, [line('simples', 1, {preco: 10})]), {issueReason: 'PRODUCT_INACTIVE'});
    assert.deepEqual(db.snapshot(), snap);
  });
}

test('NO_CONTROL: generic restock of a removed variation is still LEGACY_PROTOCOL_BLOCKED', async () => {
  const {db, base, lojaId} = seedStore('NO_CONTROL');
  const snap = db.snapshot();
  await rejectsWith(executeStockCommand(db, {protocolVersion: 1, lojaId, operationId: 'restock_menino', kind: 'restock',
    items: [{productId: PID, quantity: 1, size: 'MENINO', color: 'sem-cor'}]}, owner),
  {detail: 'LEGACY_PROTOCOL_BLOCKED'});
  assert.deepEqual(db.snapshot(), snap);
});

test('ACTIVE: generic restock with grant still cannot reach a removed variation', async () => {
  const {db, base, lojaId} = seedStore('ACTIVE', {grantPerms: {sale: true, restock: true}});
  const snap = db.snapshot();
  await rejectsWith(executeStockCommand(db, {protocolVersion: 1, lojaId, operationId: 'restock_menino', kind: 'restock',
    items: [{productId: PID, quantity: 1, size: 'MENINO', color: 'sem-cor'}]}, owner),
  {issueReason: 'VARIATION_NOT_FOUND'});
  assert.deepEqual(db.snapshot(), snap);
  assert.equal(historical(db, base).length, 0);
});

test('old 1.0.135 client: split sale/restock edit of a removed variation writes nothing', async () => {
  const {db, base, lojaId} = seedStore('NO_CONTROL');
  const snap = db.snapshot();
  const hash = 'a'.repeat(64);
  await rejectsWith(executeStockCommand(db, {protocolVersion: 1, lojaId, operationId: `editstock_sale-1_${hash}_sale`,
    kind: 'sale', items: [{productId: 'simples', quantity: 1}]}, owner), {detail: 'LEGACY_PROTOCOL_BLOCKED'});
  await rejectsWith(executeStockCommand(db, {protocolVersion: 1, lojaId, operationId: `editstock_sale-1_${hash}_restock`,
    kind: 'restock', items: [{productId: PID, quantity: 1, size: 'MENINO', color: 'sem-cor'}]}, owner),
  {detail: 'LEGACY_PROTOCOL_BLOCKED'});
  assert.deepEqual(db.snapshot(), snap);
});

test('MIR fixture: 91-line sale, historical MENINO/sem-cor qty 1 restored once', async () => {
  const products = {[PID]: berloque(0)};
  const saleLines = [];
  for (let i = 0; i < 90; i++) {
    const id = `mir-p${i}`;
    products[id] = {nome: `Peca ${i}`, stockKind: 'simple', stockRevision: 3, quantidade: 4, variacoes: {}};
    saleLines.push(line(id, 1, {preco: 89}));
  }
  saleLines.splice(37, 0, menino(1));
  assert.equal(saleLines.length, 91);
  const {db, base, lojaId} = seedStore('NO_CONTROL', {products, saleLines});
  const before = stock(db, base);
  const draftBefore = draft(db, base);

  // Positive delta on the removed cell: blocked, nothing written.
  const snap = db.snapshot();
  await rejectsWith(edit(db, base, lojaId, saleLines.map(l => (l.tamanho === 'MENINO' ? menino(2) : l))),
    {issueReason: 'HISTORICAL_VARIATION_REMOVED', issueMessage: REMOVED_MESSAGE});
  assert.deepEqual(db.snapshot(), snap);

  // Owner removes the MENINO line and one other piece in the same edit.
  const newLines = saleLines.filter(l => l.tamanho !== 'MENINO' && l.productId !== 'mir-p5');
  const cmd = editCommand(lojaId, newLines, {stored: storedLines(db, base)});
  const from = db.commits.length;
  const r = await executeStockCommand(db, cmd, owner);
  assert.equal(r.alreadyApplied, false);
  assert.equal(db.commits.slice(from).filter(c => c.ops.length).length, 1, 'single atomic commit');
  const replay = await executeStockCommand(db, cmd, owner);
  assert.equal(replay.alreadyApplied, true);
  const replayAgain = await executeStockCommand(db, cmd, owner);
  assert.equal(replayAgain.alreadyApplied, true);

  const after = stock(db, base);
  const restored = historical(db, base).reduce((sum, c) => sum + c.quantidade, 0);
  const commercialDelta = after.quantidade - before.quantidade;
  assert.equal(restored, 1);
  assert.equal(commercialDelta, 0);
  assert.equal(after.stockRevision, before.stockRevision + 1);
  assert.deepEqual(after.variacoes, before.variacoes);
  assert.deepEqual(after.tamanhos, before.tamanhos);
  assert.deepEqual(draft(db, base).variacoes ?? draftBefore.variacoes, before.variacoes);
  assert.equal(live(db, base), undefined);
  assert.equal(stock(db, base, 'mir-p5').quantidade, 5);
  assertCommercialGradeUnchanged(db, base);
  const saleDoc = db.getData(base.collection('estoque_vendas').doc('sale-1'));
  assert.equal(saleDoc.itens.length, 89);
  assert.equal(saleDoc.saleEditRevision, 1, 'sale document updated once');
  assert.equal(saleDoc.lastSaleEditOperationId, cmd.operationId);
  const op = db.getData(base.collection('stock_catalog_operations').doc(cmd.operationId));
  assert.equal(op.kind, 'saleEdit');
  assert.equal(op.saleId, 'sale-1');
  assert.deepEqual(op.items.filter(i => i.historicalCell), [{productId: PID, quantity: 1, size: 'MENINO', color: 'sem-cor',
    extra: '', direction: 'restore', historicalCell: true}]);
  console.log(`MIR_HISTORICAL_RESTORE_FIXTURE_PASS=true MIR_HISTORICAL_RESTORE_QTY=${restored} ` +
    `MIR_COMMERCIAL_QTY_DELTA=${commercialDelta} MIR_DUPLICATE_RESTORE=${restored - 1} MIR_HISTORICAL_RESTORE_IDEMPOTENT=true`);
});

test('applyRemovedVariation bounds: proof, direction, quantity, kind', () => {
  const oldLines = storedSaleLines([menino(1)]);
  const missing = new Error('Variation not found');
  const item = (over = {}) => ({productId: PID, quantity: 1, size: 'MENINO', color: 'sem-cor', extra: '', direction: 'restore', ...over});
  const s = berloque(0);
  assert.equal(originalSaleCellQuantity(oldLines, item()), 1);
  assert.equal(originalSaleCellQuantity(oldLines, item({size: ' menino '})), 1, 'normalized like the grade');
  assert.deepEqual(applyRemovedVariation(s, item(), oldLines, missing).historicalStockCells,
    [{size: 'MENINO', color: 'sem-cor', extra: '', quantidade: 1}]);
  assert.throws(() => applyRemovedVariation(s, item({quantity: 2}), oldLines, missing), e => e === missing);
  assert.throws(() => applyRemovedVariation(s, item(), storedSaleLines([menina(1)]), missing), e => e === missing);
  assert.throws(() => applyRemovedVariation(s, item({productId: 'outro'}), oldLines, missing), e => e === missing);
  assert.throws(() => applyRemovedVariation(s, item({direction: 'debit'}), oldLines, missing),
    e => e.message === REMOVED_VARIATION_DEBIT);
  const insufficient = new Error('Invalid canonical stock quantity');
  assert.throws(() => applyRemovedVariation(s, item(), oldLines, insufficient), e => e === insufficient);
  assert.throws(() => applyRemovedVariation({...s, stockKind: 'simple'}, item(), oldLines, missing), e => e === missing);
  assert.throws(() => applyRemovedVariation({...s, pendingSoftDelete: true}, item(), oldLines, missing), e => e === missing);
  const twice = applyRemovedVariation(applyRemovedVariation(s, item(), oldLines, missing), item(), oldLines, missing);
  assert.deepEqual(twice.historicalStockCells, [{size: 'MENINO', color: 'sem-cor', extra: '', quantidade: 2}],
    'same cell accumulates instead of duplicating rows');
  assert.throws(() => historicalStockCells({historicalStockCells: {MENINO: 1}}), /Invalid historical stock cells/);
  assert.throws(() => historicalStockCells({historicalStockCells: [{size: 'MENINO', color: 'sem-cor', extra: '', quantidade: -1}]}));
});
