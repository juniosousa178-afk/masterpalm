/**
 * saleEdit ↔ contas_receber reconciliation (same transaction as the sale document).
 * In-memory Firestore only — no production access.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {executeStockCommand} from '../src/stockCatalogCommands.js';
import {saleLinesHash, storedSaleLines} from '../src/stockCatalogSaleEdit.js';
import {
  saleEditAppliedLog,
  splitParcels,
  stableReceivableId,
  SALE_EDIT_REMOVED_FIADO,
} from '../src/stockCatalogSaleEditReceivable.js';
import {createConsignmentTestDb} from './consignment-test-db.mjs';

const owner = {uid: 'owner'};
const MODES = ['NO_CONTROL', 'ACTIVE'];
const SALE = 'sale-1';
const CR1 = stableReceivableId(SALE, 1);
const DUE = '2026-10-10T03:00:00.000Z';
let seq = 0;

const line = (productId, quantidade, preco = 10) => ({
  produtoNome: productId.toUpperCase(), quantidade, tamanho: '', cor: '', precoUnitario: preco,
  precoTotal: preco * quantidade, productId, custoUnitario: 0, origemCustoItem: 'desconhecido',
});
const simple = (q = 10) => ({nome: 'P', stockKind: 'simple', stockRevision: 1, quantidade: q, variacoes: {}});

function receivable(lojaId, {id = CR1, parcela = 1, total = 1, valor = 100, valorPago = 0, historico = [], extra = {}} = {}) {
  const saldo = valor;
  return {
    lojaId, contaReceberId: id, vendaIdFirebase: SALE, vendaKey: 40, clienteId: '', clienteNome: 'Cliente Teste',
    valorOriginal: saldo + valorPago, valorPago, saldoAtual: saldo, valor: saldo,
    status: valorPago > 0.01 ? 'parcial' : 'pendente', pago: false, parcelaNumero: parcela, parcelaTotal: total,
    observacao: 'Venda fiada', historicoPagamentos: historico, lembrete2DiasEnviado: false,
    cancelada: false, deletedAt: null, schemaVersion: 1, lastWriteOrigin: 'republicar_pos_venda', ...extra,
  };
}

/** Sale stored as fiado (open balance = total) unless `fiado: false`. */
function seedStore(mode, {saleLines = [line('a', 1)], total = 100, fiado = true, receivables = null,
  products = {a: simple(), b: simple()}, saleExtra = {}} = {}) {
  const db = createConsignmentTestDb();
  const lojaId = `loja_${mode.toLowerCase()}_${++seq}`;
  const base = db.collection('lojas').doc(lojaId);
  db.seed(base, {ownerUid: 'owner', lojaId});
  if (mode === 'ACTIVE') {
    db.seed(base.collection('stock_catalog_control').doc('state'), {protocolVersion: 1, mode: 'active', migrationComplete: true});
    db.seed(base.collection('stock_catalog_access').doc('owner'), {enabled: true, permissions: {sale: true}});
  }
  for (const [id, data] of Object.entries(products)) {
    db.seed(base.collection('estoque_produtos').doc(id), data);
    db.seed(base.collection('draft_produtos').doc(id), {nome: data.nome, publicadoNoCatalogo: true});
    if (mode === 'ACTIVE') db.seed(base.collection('stock_catalog_dependencies').doc(id), {comboIds: []});
  }
  db.seed(base.collection('estoque_vendas').doc(SALE), {
    id: SALE, lojaId, total, clienteNome: 'Cliente Teste', itens: saleLines, cancelada: false, estornada: false,
    ...(fiado ? {saldoFiado: total, dataVencimentoFiado: DUE} : {pagamentoPix: total}), ...saleExtra,
  });
  const crs = receivables ?? (fiado ? [{valor: total}] : []);
  for (const r of crs) {
    db.seed(base.collection('contas_receber').doc(r.id ?? CR1), receivable(lojaId, r));
  }
  return {db, base, lojaId};
}

/** Sale payload as sent by `saleEditSalePayload`: fiado fields only while an open balance remains. */
function salePayload(lines, {total, pix = 0, saldoFiado = 0, parcelas, intervalo, due = DUE, observacao = ''} = {}) {
  const t = total ?? lines.reduce((s, l) => s + l.precoTotal, 0);
  return {
    clienteNome: 'Cliente Teste', total: t, pagamentoPix: pix, observacao, itens: lines,
    data: '2026-09-09T12:00:00.000Z',
    ...(saldoFiado > 0.01 ? {
      saldoFiado,
      ...(parcelas > 1 ? {quantidadeParcelasFiado: parcelas, intervaloParcelasDias: intervalo ?? 30} : {}),
      ...(due ? {dataVencimentoFiado: due} : {}),
    } : {}),
  };
}
const pixSale = (lines, total) => salePayload(lines, {total, pix: total ?? lines.reduce((s, l) => s + l.precoTotal, 0)});
const fiadoSale = (lines, total, opts = {}) => salePayload(lines, {total, saldoFiado: total, ...opts});

const storedLines = (db, base) => db.getData(base.collection('estoque_vendas').doc(SALE)).itens;
const opIdFor = key => `saleedit_${createHash('sha256').update(key).digest('hex')}`;
function edit(db, base, lojaId, sale, {opId, expected} = {}) {
  return executeStockCommand(db, {
    protocolVersion: 1, lojaId, kind: 'saleEdit',
    operationId: opId ?? opIdFor(`${lojaId}|${++seq}`),
    saleEdit: {saleId: SALE, expectedOriginalLinesHash: expected ?? saleLinesHash(storedSaleLines(storedLines(db, base))), sale},
  }, owner);
}
const cr = (db, base, id = CR1) => db.getData(base.collection('contas_receber').doc(id));
const crDocs = (db, base) => [...db.snapshot().entries()]
  .filter(([p]) => p.startsWith(`${base.path}/contas_receber/`))
  .map(([p, d]) => ({id: p.split('/').pop(), ...d}));
const saleDoc = (db, base) => db.getData(base.collection('estoque_vendas').doc(SALE));
const stockQty = (db, base, id = 'a') => db.getData(base.collection('estoque_produtos').doc(id)).quantidade;
const lastOps = db => db.commits.at(-1).ops.map(o => o.path);
const crWrites = (db, from) => db.commits.slice(from).flatMap(c => c.ops).filter(o => o.path.includes('/contas_receber/'));

function rejectsWith(promise, {code, detail, reason}) {
  return assert.rejects(promise, e => (!code || e.code === code) &&
    (!detail || e.details?.code === detail) && (!reason || e.details?.reason === reason));
}

function assertSoftDeleted(doc, saldoAntes) {
  assert.equal(doc.cancelada, true);
  assert.ok(doc.deletedAt instanceof Date, 'deletedAt server timestamp');
  assert.equal(doc.status, 'cancelada');
  assert.equal(doc.saldoAtual, 0);
  assert.equal(doc.valor, 0);
  assert.equal(doc.pago, false, 'never marked as paid');
  assert.equal(doc.motivoCancelamento, SALE_EDIT_REMOVED_FIADO);
  assert.equal(doc.saldoAntesCancelamento, saldoAntes);
  assert.equal(doc.lastWriteOrigin, 'sale_edit_server');
  assert.match(doc.saleEditOperationId, /^saleedit_[0-9a-f]{64}$/);
}

for (const mode of MODES) {
  test(`[${mode}] ROOT CAUSE (Mir shape): fiado 8179 → Pix 312 soft-deletes the pending receivable in the same commit`, async () => {
    const oldLines = [line('a', 1, 4000), line('b', 1, 4179)];
    const {db, base, lojaId} = seedStore(mode, {saleLines: oldLines, total: 8179});
    const from = db.commits.length;
    const r = await edit(db, base, lojaId, pixSale([line('a', 1, 416)], 312));
    assert.equal(r.receivable.action, 'SOFT_DELETE');
    assert.equal(r.receivable.oldPaymentMode, 'FIADO');
    assert.equal(r.receivable.newPaymentMode, 'PAID');
    const doc = cr(db, base);
    assertSoftDeleted(doc, 8179);
    assert.equal(doc.valorOriginal, 8179, 'audit: original amount preserved');
    assert.deepEqual(doc.historicoPagamentos, [], 'payment history untouched');
    assert.equal(doc.vendaIdFirebase, SALE);
    assert.equal(crDocs(db, base).length, 1, 'no hard delete, no new doc');
    const sale = saleDoc(db, base);
    assert.equal(sale.total, 312);
    assert.equal(sale.saldoFiado, undefined);
    assert.equal(db.commits.length - from, 1, 'one commit');
    const paths = lastOps(db);
    assert.ok(paths.some(p => p.endsWith(`/estoque_vendas/${SALE}`)));
    assert.ok(paths.some(p => p.endsWith(`/contas_receber/${CR1}`)));
    assert.ok(paths.some(p => p.endsWith('/estoque_produtos/b')), 'stock restore in the same commit');
    assert.equal(stockQty(db, base, 'b'), 11);
  });

  test(`[${mode}] fiado → Pix without line changes: no stock write, receivable soft-deleted`, async () => {
    const {db, base, lojaId} = seedStore(mode);
    const r = await edit(db, base, lojaId, pixSale([line('a', 1)], 100));
    assert.equal(r.stockChanged, false);
    assert.equal(r.receivable.action, 'SOFT_DELETE');
    assertSoftDeleted(cr(db, base), 100);
    assert.equal(lastOps(db).some(p => p.includes('/estoque_produtos/')), false, 'stock untouched');
    assert.equal(stockQty(db, base), 10);
  });

  test(`[${mode}] A non-fiado → non-fiado: no receivable read effect, no receivable write`, async () => {
    const {db, base, lojaId} = seedStore(mode, {fiado: false});
    const from = db.commits.length;
    const r = await edit(db, base, lojaId, pixSale([line('a', 2)]));
    assert.equal(r.receivable.action, 'NONE');
    assert.deepEqual(crWrites(db, from), []);
    assert.deepEqual(crDocs(db, base), []);
  });

  test(`[${mode}] B non-fiado → fiado creates exactly the linked parcels at stable ids; replay never duplicates`, async () => {
    const {db, base, lojaId} = seedStore(mode, {fiado: false});
    const opId = opIdFor(`b-${mode}`);
    const sale = fiadoSale([line('a', 1)], 100, {parcelas: 3, intervalo: 15, observacao: 'obs'});
    const r = await edit(db, base, lojaId, sale, {opId});
    assert.equal(r.receivable.action, 'CREATE');
    assert.equal(r.receivable.count, 3);
    const docs = crDocs(db, base).sort((a, b) => a.parcelaNumero - b.parcelaNumero);
    assert.deepEqual(docs.map(d => d.id), [1, 2, 3].map(p => stableReceivableId(SALE, p)));
    assert.deepEqual(docs.map(d => d.valor), [33.34, 33.33, 33.33]);
    assert.deepEqual(docs.map(d => d.saldoAtual), [33.34, 33.33, 33.33]);
    assert.deepEqual(docs.map(d => d.dataVencimento.toMillis() - Date.parse(DUE)), [0, 15, 30].map(d => d * 86_400_000));
    assert.deepEqual(docs.map(d => d.observacao), ['Parcela 1/3 - obs', 'Parcela 2/3 - obs', 'Parcela 3/3 - obs']);
    for (const d of docs) {
      assert.equal(d.status, 'pendente');
      assert.equal(d.pago, false);
      assert.equal(d.cancelada, false);
      assert.equal(d.deletedAt, null);
      assert.equal(d.vendaIdFirebase, SALE);
      assert.equal(d.vendaKey, -1, 'never collides with a device Hive key');
      assert.equal(d.parcelaTotal, 3);
      assert.equal(d.lojaId, lojaId);
    }
    const before = db.snapshot();
    const replay = await edit(db, base, lojaId, sale, {opId, expected: saleLinesHash(storedSaleLines([line('a', 1)]))});
    assert.equal(replay.alreadyApplied, true);
    assert.equal(replay.receivable.action, 'CREATE');
    assert.deepEqual(db.snapshot(), before, 'replay writes nothing');
    assert.equal(crDocs(db, base).length, 3);
  });

  test(`[${mode}] C fiado → fiado with the same open amount preserves the receivable`, async () => {
    const {db, base, lojaId} = seedStore(mode);
    const before = cr(db, base);
    const from = db.commits.length;
    const r = await edit(db, base, lojaId, fiadoSale([line('b', 1)], 100));
    assert.equal(r.receivable.action, 'NONE');
    assert.deepEqual(crWrites(db, from), []);
    assert.deepEqual(cr(db, base), before);
  });

  test(`[${mode}] D fiado amount changes: open balance follows, payments and history preserved`, async () => {
    const hist = [{baixaId: 'b1', valor: 30}];
    const {db, base, lojaId} = seedStore(mode, {receivables: [{valor: 70, valorPago: 30, historico: hist}]});
    const r = await edit(db, base, lojaId, fiadoSale([line('a', 1), line('b', 1)], 150));
    assert.equal(r.receivable.action, 'UPDATE');
    const doc = cr(db, base);
    assert.equal(doc.valor, 120);
    assert.equal(doc.saldoAtual, 120);
    assert.equal(doc.valorOriginal, 150);
    assert.equal(doc.valorPago, 30);
    assert.deepEqual(doc.historicoPagamentos, hist);
    assert.equal(doc.status, 'parcial');
    assert.equal(doc.pago, false);
    assert.equal(doc.dataVencimento.toMillis(), Date.parse(DUE));
  });

  test(`[${mode}] D multi-parcel: proportional like the client model`, async () => {
    const p2 = stableReceivableId(SALE, 2);
    const {db, base, lojaId} = seedStore(mode, {receivables: [
      {id: CR1, parcela: 1, total: 2, valor: 50}, {id: p2, parcela: 2, total: 2, valor: 50}]});
    const r = await edit(db, base, lojaId, fiadoSale([line('b', 1)], 80));
    assert.equal(r.receivable.count, 2);
    assert.deepEqual([cr(db, base).valor, cr(db, base, p2).valor], [40, 40]);
  });

  test(`[${mode}] E with payments fails closed: nothing written (stock, sale, receivable)`, async () => {
    const {db, base, lojaId} = seedStore(mode, {receivables: [{valor: 70, valorPago: 30, historico: [{baixaId: 'b1'}]}]});
    const snap = db.snapshot();
    await rejectsWith(edit(db, base, lojaId, pixSale([line('a', 2)], 100)),
      {code: 'failed-precondition', detail: 'INVALID_SALE_EDIT', reason: 'RECEIVABLE_HAS_PAYMENTS'});
    assert.deepEqual(db.snapshot(), snap);
  });

  test(`[${mode}] G paid/terminal receivable is never reopened nor destroyed`, async () => {
    const paid = {valor: 0, valorPago: 100, historico: [{baixaId: 'b1'}], extra: {pago: true, status: 'paga'}};
    for (const sale of [fiadoSale([line('a', 1)], 150), pixSale([line('a', 2)], 100)]) {
      const {db, base, lojaId} = seedStore(mode, {receivables: [paid]});
      const snap = db.snapshot();
      await assert.rejects(edit(db, base, lojaId, sale), e => e.details?.code === 'INVALID_SALE_EDIT' &&
        ['RECEIVABLE_REQUIRES_REVIEW', 'RECEIVABLE_HAS_PAYMENTS'].includes(e.details?.reason));
      assert.deepEqual(db.snapshot(), snap);
    }
  });

  test(`[${mode}] G cancelled receivable stays a tombstone when the sale is non-fiado`, async () => {
    const {db, base, lojaId} = seedStore(mode, {receivables: [{valor: 0,
      extra: {cancelada: true, status: 'cancelada', deletedAt: new Date('2026-09-01'), motivoCancelamento: 'venda_excluida'}}]});
    const before = cr(db, base);
    const r = await edit(db, base, lojaId, pixSale([line('a', 2)], 20));
    assert.equal(r.receivable.action, 'NONE');
    assert.deepEqual(cr(db, base), before);
  });

  test(`[${mode}] G a fiado never revives a tombstone it did not create`, async () => {
    const {db, base, lojaId} = seedStore(mode, {fiado: false, receivables: [{valor: 0,
      extra: {cancelada: true, status: 'cancelada', deletedAt: new Date('2026-09-01'), motivoCancelamento: 'venda_excluida'}}]});
    const snap = db.snapshot();
    await rejectsWith(edit(db, base, lojaId, fiadoSale([line('a', 1)], 100)), {reason: 'RECEIVABLE_REQUIRES_REVIEW'});
    assert.deepEqual(db.snapshot(), snap);
  });

  test(`[${mode}] H replay of the soft-delete is a no-op; I altered payload with the same operationId fails closed`, async () => {
    const {db, base, lojaId} = seedStore(mode);
    const opId = opIdFor(`h-${mode}`);
    const expected = saleLinesHash(storedSaleLines(storedLines(db, base)));
    await edit(db, base, lojaId, pixSale([line('a', 2)], 20), {opId, expected});
    const after = db.snapshot();
    const replay = await edit(db, base, lojaId, pixSale([line('a', 2)], 20), {opId, expected});
    assert.equal(replay.alreadyApplied, true);
    assert.equal(replay.receivable.action, 'SOFT_DELETE');
    assert.deepEqual(db.snapshot(), after, 'at most one effective mutation');
    await rejectsWith(edit(db, base, lojaId, pixSale([line('a', 3)], 30), {opId, expected}),
      {code: 'already-exists', detail: 'OPERATION_PAYLOAD_CONFLICT'});
    assert.deepEqual(db.snapshot(), after);
  });

  test(`[${mode}] F cancelled sale is not editable; receivable untouched`, async () => {
    const {db, base, lojaId} = seedStore(mode, {saleExtra: {cancelada: true}});
    const snap = db.snapshot();
    await rejectsWith(edit(db, base, lojaId, pixSale([line('a', 2)], 20)), {reason: 'SALE_NOT_EDITABLE'});
    assert.deepEqual(db.snapshot(), snap);
  });

  test(`[${mode}] MULTI-EDIT: six sequential edits, final non-fiado wins; fiado removed then restored is one doc`, async () => {
    const {db, base, lojaId} = seedStore(mode);
    const steps = [
      [fiadoSale([line('a', 2)], 120), 'UPDATE', 120],
      [fiadoSale([line('a', 2), line('b', 1)], 120), 'NONE', 120],
      [pixSale([line('b', 1)], 50), 'SOFT_DELETE', 0],
      [fiadoSale([line('b', 2)], 60), 'CREATE', 60],
      [fiadoSale([line('a', 1)], 90), 'UPDATE', 90],
      [pixSale([line('a', 1), line('b', 1)], 312), 'SOFT_DELETE', 0],
    ];
    for (const [sale, action, saldo] of steps) {
      const r = await edit(db, base, lojaId, sale);
      assert.equal(r.receivable.action, action, JSON.stringify(sale.itens));
      assert.equal(cr(db, base).saldoAtual, saldo);
    }
    assert.equal(saleDoc(db, base).saleEditRevision, 6);
    const docs = crDocs(db, base);
    assert.equal(docs.length, 1, 'never duplicated');
    assertSoftDeleted(docs[0], 90);
    assert.equal(docs[0].reabertaAposCancelamento.motivo, SALE_EDIT_REMOVED_FIADO);
    assert.equal(saleDoc(db, base).total, 312);
    assert.equal(saleDoc(db, base).saldoFiado, undefined);
    const r = await edit(db, base, lojaId, pixSale([line('a', 1)], 10));
    assert.equal(r.receivable.action, 'NONE', 'later non-fiado edits keep the tombstone');
  });

  test(`[${mode}] legacy linked doc id (non-stable) is reconciled by vendaIdFirebase`, async () => {
    const {db, base, lojaId} = seedStore(mode, {receivables: [{id: 'cr_legacy_abcd1234', valor: 100}]});
    const r = await edit(db, base, lojaId, pixSale([line('a', 1)], 100));
    assert.equal(r.receivable.action, 'SOFT_DELETE');
    assertSoftDeleted(cr(db, base, 'cr_legacy_abcd1234'), 100);
    assert.equal(cr(db, base, CR1), undefined);
  });

  test(`[${mode}] receivable of another store or missing fiado due date fails closed`, async () => {
    {
      const {db, base, lojaId} = seedStore(mode);
      db.seed(base.collection('contas_receber').doc(CR1), {...cr(db, base), lojaId: 'other'});
      const snap = db.snapshot();
      await rejectsWith(edit(db, base, lojaId, pixSale([line('a', 1)], 100)), {reason: 'RECEIVABLE_REQUIRES_REVIEW'});
      assert.deepEqual(db.snapshot(), snap);
    }
    {
      const {db, base, lojaId} = seedStore(mode);
      const snap = db.snapshot();
      await rejectsWith(edit(db, base, lojaId, fiadoSale([line('a', 1)], 80, {due: null})), {reason: 'FIADO_DUE_DATE_REQUIRED'});
      assert.deepEqual(db.snapshot(), snap);
    }
  });

  test(`[${mode}] atomic: a failing receivable write aborts stock, sale and operation`, async () => {
    const {db, base, lojaId} = seedStore(mode);
    const snap = db.snapshot();
    db.faultInjector = ({path}) => { if (path.includes('/contas_receber/')) throw new Error('injected'); };
    await assert.rejects(edit(db, base, lojaId, pixSale([line('a', 3)], 30)), /injected/);
    db.faultInjector = null;
    assert.deepEqual(db.snapshot(), snap);
  });

  test(`[${mode}] receivable writes count toward the write budget (fail closed, nothing written)`, async () => {
    const products = Object.fromEntries(Array.from({length: 25}, (_, i) => [`p${i}`, simple()]));
    const oldLines = Object.keys(products).map(id => line(id, 1));
    const {db, base, lojaId} = seedStore(mode, {products, saleLines: oldLines, fiado: false});
    const snap = db.snapshot();
    const newLines = Object.keys(products).map(id => line(id, 2));
    await rejectsWith(edit(db, base, lojaId, fiadoSale(newLines, 500, {parcelas: 48})), {reason: 'SALE_EDIT_TOO_LARGE'});
    assert.deepEqual(db.snapshot(), snap);
  });
}

for (const mode of MODES) {
  test(`[${mode}] worst supported edit: 25 changed products + sale op + receivable parcels stays within budget`, async () => {
    const products = Object.fromEntries(Array.from({length: 25}, (_, i) => [`p${i}`, simple()]));
    const oldLines = Object.keys(products).map(id => line(id, 1));
    const seedWithSaleOp = () => {
      const s = seedStore(mode, {products, saleLines: oldLines, fiado: false});
      s.db.seed(s.base.collection('stock_catalog_operations').doc(SALE), {kind: 'sale', status: 'applied', actorUid: 'owner',
        items: Object.keys(products).map(productId => ({productId, quantity: 1, size: '', color: '', extra: ''}))});
      return s;
    };
    const newLines = Object.keys(products).map(id => line(id, 2));
    const fixed = 25 * 3 + 3;
    const maxParcels = 100 - fixed;
    {
      const {db, base, lojaId} = seedWithSaleOp();
      const r = await edit(db, base, lojaId, fiadoSale(newLines, 500, {parcelas: maxParcels}));
      assert.equal(r.receivable.count, maxParcels);
      const c = db.commits.at(-1);
      assert.equal(c.writes, 100, 'exactly at the preserved internal limit');
      assert.ok(c.writes + c.transforms <= 500, `units ${c.writes + c.transforms}`);
      console.log(`SALE_EDIT_MAX_WRITES=${c.writes} SALE_EDIT_MAX_WRITE_UNITS_WITH_RECEIVABLE=${c.writes + c.transforms} ` +
        `MAX_PARCELS_WITH_25_PRODUCTS=${maxParcels}`);
    }
    {
      const {db, base, lojaId} = seedWithSaleOp();
      const snap = db.snapshot();
      await rejectsWith(edit(db, base, lojaId, fiadoSale(newLines, 500, {parcelas: maxParcels + 1})), {reason: 'SALE_EDIT_TOO_LARGE'});
      assert.deepEqual(db.snapshot(), snap);
    }
    {
      // Payment-only edit with the client maximum of 48 parcels: no stock writes, well inside the limit.
      const {db, base, lojaId} = seedWithSaleOp();
      const r = await edit(db, base, lojaId, fiadoSale(oldLines, 25, {parcelas: 48}));
      assert.equal(r.stockChanged, false);
      assert.equal(db.commits.at(-1).writes, 2 + 48);
    }
  });
}

test('the receivable query runs inside the transaction', async () => {
  const {db, base, lojaId} = seedStore('ACTIVE');
  await edit(db, base, lojaId, pixSale([line('a', 1)], 100));
  assert.ok(db.queryReads.includes(`${base.path}/contas_receber`));
});

test('splitParcels mirrors the client cents split', () => {
  assert.deepEqual(splitParcels(100, 3), [33.34, 33.33, 33.33]);
  assert.deepEqual(splitParcels(8179, 1), [8179]);
  assert.deepEqual(splitParcels(0.05, 2), [0.03, 0.02]);
  assert.equal(splitParcels(10, 99).length, 48);
});

test('applied log carries no customer data', () => {
  const log = saleEditAppliedLog(
    {lojaId: 'mirjoias', kind: 'saleEdit', saleEdit: {saleId: SALE, sale: {clienteNome: 'Fulana', itens: []}}},
    {operationId: opIdFor('x'), saleEditRevision: 2, alreadyApplied: false,
      receivable: {action: 'SOFT_DELETE', count: 1, oldPaymentMode: 'FIADO', newPaymentMode: 'PAID'}},
  );
  assert.deepEqual(Object.keys(log).sort(), ['message', 'newPaymentMode', 'oldPaymentMode', 'operationId', 'receivableAction',
    'receivableCount', 'result', 'saleEditRevision', 'saleRef', 'severity', 'storeId'].sort());
  assert.equal(JSON.stringify(log).includes('Fulana'), false);
  assert.equal(JSON.stringify(log).includes(SALE), false, 'sale id only as a hash');
  assert.equal(log.receivableAction, 'SOFT_DELETE');
});
