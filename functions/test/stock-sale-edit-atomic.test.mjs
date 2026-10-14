/**
 * saleEdit: server-authoritative, single-transaction sale edit (stock + sale document).
 * In-memory Firestore only — no production access.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {executeStockCommand} from '../src/stockCatalogCommands.js';
import {
  saleLinesHash,
  storedSaleLines,
  computeSaleEditDelta,
  stockCommandRejectionLog,
  nextSaleOperationItems,
  buildSaleEditPatch,
  MAX_SALE_EDIT_LINES,
} from '../src/stockCatalogSaleEdit.js';
import {createConsignmentTestDb, commitUnits} from './consignment-test-db.mjs';

const owner = {uid: 'owner'};
const MODES = ['NO_CONTROL', 'ACTIVE'];
let seq = 0;

const PRODUCTS = {
  anel: {
    nome: 'Anel Solitario', stockKind: 'variation', stockRevision: 4, quantidade: 6,
    variacoes: {'20': {Rubelita: 3, Esmeralda: 2}, '14': {'sem-cor': 1}},
    estoquePorTamanho: {'20': 5, '14': 1}, tamanhos: ['20', '14'],
  },
  letra: {
    nome: 'Pingente Letra', stockKind: 'variation', stockRevision: 2, quantidade: 3,
    variacoes: {'sem-tamanho': {Gold: {J: 2, K: 1}}}, estoquePorTamanho: {'sem-tamanho': 3},
  },
  brinco: {
    nome: 'Brinco Bolinha', stockKind: 'variation', stockRevision: 6, quantidade: 4,
    variacoes: {P: {'sem-cor': 2}, M: {'sem-cor': 1}, G: {'sem-cor': 1}},
    estoquePorTamanho: {P: 2, M: 1, G: 1}, tamanhos: ['P', 'M', 'G'],
  },
  simples: {nome: 'Corrente Simples', stockKind: 'simple', stockRevision: 1, quantidade: 5, variacoes: {}},
  outro: {nome: 'Pulseira', stockKind: 'simple', stockRevision: 1, quantidade: 1, variacoes: {}},
  combo: {
    nome: 'Kit', stockKind: 'combo', tipoProduto: 'combo', stockRevision: 1, quantidade: 1,
    itensCombo: [{productId: 'outro', quantidade: 1}],
  },
};

function line(productId, quantidade, {tamanho = '', cor = '', extraValor, preco = 10} = {}) {
  return {
    produtoNome: PRODUCTS[productId]?.nome ?? productId,
    quantidade, tamanho, cor, precoUnitario: preco, precoTotal: preco * quantidade,
    productId, ...(extraValor ? {extraValor} : {}), custoUnitario: 0, origemCustoItem: 'desconhecido',
  };
}

function seedStore(mode, {products = PRODUCTS, saleLines, saleOpItems, saleExtra = {}, grantPerms = {sale: true}} = {}) {
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
    if (mode === 'ACTIVE') {
      db.seed(base.collection('draft_produtos').doc(id), {nome: data.nome, publicadoNoCatalogo: true});
      db.seed(base.collection('stock_catalog_dependencies').doc(id), {comboIds: id === 'outro' ? ['combo'] : []});
    }
  }
  const lines = saleLines ?? [
    line('anel', 1, {tamanho: '20', cor: 'Rubelita'}),
    line('brinco', 1, {tamanho: 'P', cor: 'sem-cor'}),
  ];
  db.seed(base.collection('estoque_vendas').doc('sale-1'), {
    id: 'sale-1', lojaId, total: 20, clienteNome: 'Cliente Teste', itens: lines, cancelada: false,
    estornada: false, status: 'concluida', stockOperationId: 'sale-1', ...saleExtra,
  });
  if (saleOpItems) {
    db.seed(base.collection('stock_catalog_operations').doc('sale-1'), {
      kind: 'sale', status: 'applied', actorUid: 'owner', items: saleOpItems, saleId: 'sale-1', legacyCompat: mode === 'NO_CONTROL',
    });
  }
  return {db, base, lojaId};
}

function opIdFor(...parts) {
  return `saleedit_${createHash('sha256').update(parts.join('|')).digest('hex')}`;
}

function editCommand(lojaId, newLines, {saleId = 'sale-1', expected, opId, sale = {}, stored} = {}) {
  return {
    protocolVersion: 1, lojaId, kind: 'saleEdit',
    operationId: opId ?? opIdFor(lojaId, saleId, JSON.stringify(newLines), ++seq),
    saleEdit: {
      saleId,
      expectedOriginalLinesHash: expected ?? saleLinesHash(storedSaleLines(stored)),
      sale: {clienteNome: 'Cliente Teste', total: 20, itens: newLines, ...sale},
    },
  };
}

function stored(db, base, saleId = 'sale-1') {
  return db.getData(base.collection('estoque_vendas').doc(saleId)).itens;
}
const stock = (db, base, id) => db.getData(base.collection('estoque_produtos').doc(id));
const stockWritesSince = (db, from) => db.commits.slice(from)
  .flatMap(c => c.ops).filter(o => o.path.includes('/estoque_produtos/')).length;
const writesSince = (db, from) => db.commits.slice(from).flatMap(c => c.ops).length;

async function edit(db, base, lojaId, newLines, opts = {}, auth = owner) {
  return executeStockCommand(db, editCommand(lojaId, newLines, {...opts, stored: stored(db, base, opts.saleId)}), auth);
}

function rejectsWith(promise, {code, detail, reason, issueReason}) {
  return assert.rejects(promise, e => {
    if (code && e.code !== code) return false;
    if (detail && e.details?.code !== detail) return false;
    if (reason && e.details?.reason !== reason) return false;
    if (issueReason && !(e.issues ?? []).some(i => i.reasonCode === issueReason)) return false;
    return true;
  });
}

for (const mode of MODES) {
  test(`[${mode}] A no change: sale doc committed, zero stock writes`, async () => {
    const {db, base, lojaId} = seedStore(mode);
    const from = db.commits.length;
    const r = await edit(db, base, lojaId, stored(db, base), {sale: {observacao: 'só observação'}});
    assert.equal(r.stockChanged, false);
    assert.equal(stockWritesSince(db, from), 0);
    const sale = db.getData(base.collection('estoque_vendas').doc('sale-1'));
    assert.equal(sale.observacao, 'só observação');
    assert.equal(sale.saleEditRevision, 1);
  });

  test(`[${mode}] B increase debits exact cell only`, async () => {
    const {db, base, lojaId} = seedStore(mode);
    await edit(db, base, lojaId, [line('anel', 2, {tamanho: '20', cor: 'Rubelita'}), line('brinco', 1, {tamanho: 'P', cor: 'sem-cor'})]);
    const a = stock(db, base, 'anel');
    assert.equal(a.variacoes['20'].Rubelita, 2);
    assert.equal(a.variacoes['20'].Esmeralda, 2);
    assert.equal(a.variacoes['14']['sem-cor'], 1);
    assert.equal(stock(db, base, 'brinco').variacoes.P['sem-cor'], 2);
  });

  test(`[${mode}] C decrease restores exact cell`, async () => {
    const {db, base, lojaId} = seedStore(mode, {saleLines: [line('anel', 2, {tamanho: '20', cor: 'Rubelita'})]});
    await edit(db, base, lojaId, [line('anel', 1, {tamanho: '20', cor: 'Rubelita'})]);
    assert.equal(stock(db, base, 'anel').variacoes['20'].Rubelita, 4);
    assert.equal(stock(db, base, 'anel').variacoes['20'].Esmeralda, 2);
  });

  test(`[${mode}] D remove line restores full quantity`, async () => {
    const {db, base, lojaId} = seedStore(mode);
    await edit(db, base, lojaId, [line('anel', 1, {tamanho: '20', cor: 'Rubelita'})]);
    assert.equal(stock(db, base, 'brinco').variacoes.P['sem-cor'], 3);
    assert.equal(stock(db, base, 'brinco').variacoes.M['sem-cor'], 1);
  });

  test(`[${mode}] E add simple product line`, async () => {
    const {db, base, lojaId} = seedStore(mode);
    await edit(db, base, lojaId, [...stored(db, base), line('simples', 2)]);
    assert.equal(stock(db, base, 'simples').quantidade, 3);
  });

  test(`[${mode}] F mixed edit A 1→2, B 1→0 commits once; failure commits nothing`, async () => {
    const {db, base, lojaId} = seedStore(mode);
    const from = db.commits.length;
    await edit(db, base, lojaId, [line('anel', 2, {tamanho: '20', cor: 'Rubelita'})]);
    const commits = db.commits.slice(from).filter(c => c.ops.length);
    assert.equal(commits.length, 1, 'single atomic commit');
    const paths = commits[0].ops.map(o => o.path);
    assert.ok(paths.some(p => p.endsWith('/estoque_produtos/anel')));
    assert.ok(paths.some(p => p.endsWith('/estoque_produtos/brinco')));
    assert.ok(paths.some(p => p.endsWith('/estoque_vendas/sale-1')));
    assert.ok(paths.some(p => p.includes('/stock_catalog_operations/saleedit_')));
    assert.equal(stock(db, base, 'anel').variacoes['20'].Rubelita, 2);
    assert.equal(stock(db, base, 'brinco').variacoes.P['sem-cor'], 3);

    const fail = seedStore(mode);
    const before = fail.db.snapshot();
    await rejectsWith(edit(fail.db, fail.base, fail.lojaId, [line('anel', 9, {tamanho: '20', cor: 'Rubelita'})]),
      {issueReason: 'INSUFFICIENT_STOCK'});
    assert.deepEqual(fail.db.snapshot(), before, 'no stock, sale or op mutation');
  });

  test(`[${mode}] G variation change restores A once and debits B once`, async () => {
    const {db, base, lojaId} = seedStore(mode);
    await edit(db, base, lojaId, [line('anel', 1, {tamanho: '20', cor: 'Esmeralda'}), line('brinco', 1, {tamanho: 'P', cor: 'sem-cor'})]);
    const a = stock(db, base, 'anel');
    assert.equal(a.variacoes['20'].Rubelita, 4);
    assert.equal(a.variacoes['20'].Esmeralda, 1);
    assert.equal(a.quantidade, 6);
  });

  test(`[${mode}] H multiple increases and decreases`, async () => {
    const {db, base, lojaId} = seedStore(mode, {saleLines: [
      line('anel', 2, {tamanho: '20', cor: 'Rubelita'}), line('brinco', 1, {tamanho: 'P', cor: 'sem-cor'}),
      line('letra', 1, {cor: 'Gold', extraValor: 'J'}), line('simples', 1),
    ]});
    await edit(db, base, lojaId, [
      line('anel', 1, {tamanho: '20', cor: 'Rubelita'}), line('brinco', 1, {tamanho: 'M', cor: 'sem-cor'}),
      line('letra', 2, {cor: 'Gold', extraValor: 'J'}), line('simples', 3),
    ]);
    assert.equal(stock(db, base, 'anel').variacoes['20'].Rubelita, 4);
    assert.equal(stock(db, base, 'brinco').variacoes.P['sem-cor'], 3);
    assert.equal(stock(db, base, 'brinco').variacoes.M['sem-cor'], 0);
    assert.equal(stock(db, base, 'letra').variacoes['sem-tamanho'].Gold.J, 1);
    assert.equal(stock(db, base, 'letra').variacoes['sem-tamanho'].Gold.K, 1);
    assert.equal(stock(db, base, 'simples').quantidade, 3);
  });

  test(`[${mode}] I insufficient stock: structured INSUFFICIENT_STOCK, zero writes`, async () => {
    const {db, base, lojaId} = seedStore(mode);
    const from = db.commits.length;
    await rejectsWith(edit(db, base, lojaId, [...stored(db, base), line('simples', 6)]),
      {code: 'failed-precondition', issueReason: 'INSUFFICIENT_STOCK'});
    assert.equal(writesSince(db, from), 0);
  });

  test(`[${mode}] J concurrent stock change is re-read inside the transaction`, async () => {
    const {db, base, lojaId} = seedStore(mode);
    const anelRef = base.collection('estoque_produtos').doc('anel');
    let injected = false;
    db.onRead = (path, attempt) => {
      if (!injected && attempt === 1 && path === anelRef.path) {
        injected = true;
        db.concurrentWrite(anelRef, {...PRODUCTS.anel, stockRevision: 5, quantidade: 3,
          variacoes: {'20': {Rubelita: 0, Esmeralda: 2}, '14': {'sem-cor': 1}}, estoquePorTamanho: {'20': 2, '14': 1}});
      }
    };
    const before = db.getData(base.collection('estoque_vendas').doc('sale-1'));
    await rejectsWith(edit(db, base, lojaId, [line('anel', 2, {tamanho: '20', cor: 'Rubelita'}), line('brinco', 1, {tamanho: 'P', cor: 'sem-cor'})]),
      {issueReason: 'INSUFFICIENT_STOCK'});
    db.onRead = null;
    assert.ok(injected);
    assert.equal(stock(db, base, 'anel').variacoes['20'].Rubelita, 0, 'never over-debits');
    assert.equal(stock(db, base, 'brinco').variacoes.P['sem-cor'], 2, 'other side untouched');
    assert.deepEqual(db.getData(base.collection('estoque_vendas').doc('sale-1')), before);
  });

  test(`[${mode}] J concurrent sale edit: stale original lines → SALE_EDIT_CONFLICT`, async () => {
    const {db, base, lojaId} = seedStore(mode);
    const staleLines = stored(db, base);
    await edit(db, base, lojaId, [line('anel', 1, {tamanho: '20', cor: 'Rubelita'})]);
    const anelAfterFirst = stock(db, base, 'anel');
    await rejectsWith(executeStockCommand(db, editCommand(lojaId, [line('anel', 1, {tamanho: '20', cor: 'Rubelita'})], {stored: staleLines}), owner),
      {code: 'aborted', detail: 'SALE_EDIT_CONFLICT'});
    assert.deepEqual(stock(db, base, 'anel'), anelAfterFirst);
    assert.equal(stock(db, base, 'brinco').variacoes.P['sem-cor'], 3, 'restored exactly once');
  });

  test(`[${mode}] K exact replay is idempotent`, async () => {
    const {db, base, lojaId} = seedStore(mode);
    const cmd = editCommand(lojaId, [line('anel', 2, {tamanho: '20', cor: 'Rubelita'})], {stored: stored(db, base)});
    const r1 = await executeStockCommand(db, cmd, owner);
    const from = db.commits.length;
    const r2 = await executeStockCommand(db, cmd, owner);
    assert.equal(r1.alreadyApplied, false);
    assert.equal(r2.alreadyApplied, true);
    assert.equal(r2.saleEditRevision, 1);
    assert.equal(writesSince(db, from), 0);
    assert.equal(stock(db, base, 'anel').variacoes['20'].Rubelita, 2);
    assert.equal(stock(db, base, 'brinco').variacoes.P['sem-cor'], 3);
  });

  test(`[${mode}] L same operationId with different payload fails closed`, async () => {
    const {db, base, lojaId} = seedStore(mode);
    const original = stored(db, base);
    const opId = opIdFor('fixed', mode);
    await executeStockCommand(db, editCommand(lojaId, [line('anel', 2, {tamanho: '20', cor: 'Rubelita'})], {stored: original, opId}), owner);
    const snap = db.snapshot();
    await rejectsWith(executeStockCommand(db, editCommand(lojaId, [line('anel', 3, {tamanho: '20', cor: 'Rubelita'})], {stored: original, opId}), owner),
      {code: 'already-exists', detail: 'OPERATION_PAYLOAD_CONFLICT'});
    assert.deepEqual(db.snapshot(), snap);
  });

  test(`[${mode}] M deleted, cancelled or restored sales are not editable`, async () => {
    const {db, base, lojaId} = seedStore(mode);
    await rejectsWith(executeStockCommand(db, editCommand(lojaId, [line('simples', 1)], {saleId: 'missing', expected: 'a'.repeat(64)}), owner),
      {detail: 'INVALID_SALE_EDIT', reason: 'SALE_NOT_FOUND'});
    const cancelled = seedStore(mode, {saleExtra: {cancelada: true}});
    await rejectsWith(edit(cancelled.db, cancelled.base, cancelled.lojaId, [line('simples', 1)]),
      {detail: 'INVALID_SALE_EDIT', reason: 'SALE_NOT_EDITABLE'});
    const restored = seedStore(mode, {saleOpItems: [{productId: 'anel', quantity: 1, size: '20', color: 'Rubelita', extra: ''}]});
    restored.db.seed(restored.base.collection('stock_catalog_operations').doc('sale-1'), {
      ...restored.db.getData(restored.base.collection('stock_catalog_operations').doc('sale-1')), restoredBy: 'restore_x',
    });
    const snap = restored.db.snapshot();
    await rejectsWith(edit(restored.db, restored.base, restored.lojaId, [line('anel', 2, {tamanho: '20', cor: 'Rubelita'})]),
      {detail: 'INVALID_SALE_EDIT', reason: 'SALE_ALREADY_RESTORED'});
    assert.deepEqual(restored.db.snapshot(), snap);
  });

  test(`[${mode}] N cross-tenant: foreign store, foreign sale and foreign product are blocked`, async () => {
    const mine = seedStore(mode);
    const other = seedStore(mode);
    const outsider = {uid: 'intruder'};
    await rejectsWith(edit(other.db, other.base, other.lojaId, [line('anel', 0 + 2, {tamanho: '20', cor: 'Rubelita'})], {}, outsider),
      {code: 'permission-denied'});
    await rejectsWith(executeStockCommand(mine.db, editCommand(mine.lojaId, [line('simples', 1)], {saleId: 'sale-of-other-store', expected: 'b'.repeat(64)}), owner),
      {reason: 'SALE_NOT_FOUND'});
    const snap = mine.db.snapshot();
    await rejectsWith(edit(mine.db, mine.base, mine.lojaId, [...stored(mine.db, mine.base), line('produto-de-outra-loja', 1)]),
      {issueReason: 'PRODUCT_NOT_FOUND'});
    assert.deepEqual(mine.db.snapshot(), snap);
  });

  test(`[${mode}] exact cells: size 20/Rubelita, letter J Gold, size P, simple`, async () => {
    const {db, base, lojaId} = seedStore(mode, {saleLines: [
      line('anel', 1, {tamanho: '20', cor: 'Rubelita'}), line('letra', 1, {cor: 'Gold', extraValor: 'J'}),
      line('brinco', 1, {tamanho: 'P', cor: 'sem-cor'}), line('simples', 1),
    ]});
    await edit(db, base, lojaId, [line('letra', 1, {cor: 'Gold', extraValor: 'K'})]);
    assert.deepEqual(stock(db, base, 'anel').variacoes['20'], {Rubelita: 4, Esmeralda: 2});
    assert.deepEqual(stock(db, base, 'letra').variacoes['sem-tamanho'].Gold, {J: 3, K: 0});
    assert.equal(stock(db, base, 'brinco').variacoes.P['sem-cor'], 3);
    assert.equal(stock(db, base, 'simples').quantidade, 6);
  });

  test(`[${mode}] combo line change fails closed; unchanged combo line is allowed`, async () => {
    const {db, base, lojaId} = seedStore(mode, {saleLines: [line('combo', 1), line('simples', 1)]});
    const snap = db.snapshot();
    await rejectsWith(edit(db, base, lojaId, [line('combo', 2), line('simples', 1)]),
      {detail: 'INVALID_SALE_EDIT', reason: 'COMBO_EDIT_NOT_SUPPORTED'});
    assert.deepEqual(db.snapshot(), snap);
    await edit(db, base, lojaId, [line('combo', 1), line('simples', 2)]);
    assert.equal(stock(db, base, 'simples').quantidade, 4);
  });

  test(`[${mode}] combo component selection change with identical lines fails closed`, async () => {
    const comboJson = JSON.stringify({0: [{productId: 'outro', quantidade: 1}]});
    const {db, base, lojaId} = seedStore(mode, {saleLines: [line('combo', 1)], saleExtra: {itensComboSelecaoJson: comboJson}});
    const snap = db.snapshot();
    await rejectsWith(edit(db, base, lojaId, [line('combo', 1)], {sale: {itensComboSelecaoJson: JSON.stringify({0: [{productId: 'simples', quantidade: 1}]})}}),
      {detail: 'INVALID_SALE_EDIT', reason: 'COMBO_EDIT_NOT_SUPPORTED'});
    await rejectsWith(edit(db, base, lojaId, [line('combo', 1)]),
      {detail: 'INVALID_SALE_EDIT', reason: 'COMBO_EDIT_NOT_SUPPORTED'});
    assert.deepEqual(db.snapshot(), snap);
    await edit(db, base, lojaId, [line('combo', 1)], {sale: {itensComboSelecaoJson: comboJson, observacao: 'ok'}});
    assert.equal(db.getData(base.collection('estoque_vendas').doc('sale-1')).itensComboSelecaoJson, comboJson);
  });

  test(`[${mode}] saleEdit is not a generic restock`, async () => {
    const {db, base, lojaId} = seedStore(mode);
    // Restore is bounded by the saved sale: removing everything but one line restores only what the sale holds.
    await edit(db, base, lojaId, [line('simples', 1)]);
    assert.equal(stock(db, base, 'anel').variacoes['20'].Rubelita, 4);
    assert.equal(stock(db, base, 'brinco').variacoes.P['sem-cor'], 3);
    // A second "restore" attempt from the stale view is refused; nothing is restored twice.
    const snap = db.snapshot();
    await rejectsWith(executeStockCommand(db, editCommand(lojaId, [line('simples', 1)], {
      stored: [line('anel', 5, {tamanho: '20', cor: 'Rubelita'}), line('simples', 1)],
    }), owner), {detail: 'SALE_EDIT_CONFLICT'});
    assert.deepEqual(db.snapshot(), snap);
    // Restore never targets a cell the sale did not hold: unknown cells can only be debited.
    const delta = computeSaleEditDelta(storedSaleLines([line('simples', 1)]), storedSaleLines([line('simples', 1), line('outro', 1)]));
    assert.deepEqual(delta.map(d => d.direction), ['debit']);
  });

  test(`[${mode}] restore after saleEdit returns edited quantities`, async () => {
    const {db, base, lojaId} = seedStore(mode, {
      saleLines: [line('anel', 1, {tamanho: '20', cor: 'Rubelita'})],
      saleOpItems: [{productId: 'anel', quantity: 1, size: '20', color: 'Rubelita', extra: ''}],
    });
    if (mode === 'ACTIVE') db.seed(base.collection('stock_catalog_access').doc('owner'), {enabled: true, permissions: {sale: true, restore: true}});
    await edit(db, base, lojaId, [line('anel', 2, {tamanho: '20', cor: 'Rubelita'})]);
    assert.equal(stock(db, base, 'anel').variacoes['20'].Rubelita, 2);
    const op = db.getData(base.collection('stock_catalog_operations').doc('sale-1'));
    assert.deepEqual(op.currentItems, [{productId: 'anel', size: '20', color: 'Rubelita', extra: '', quantity: 2}]);
    await executeStockCommand(db, {protocolVersion: 1, lojaId, kind: 'restore', operationId: 'restore_sale-1',
      sourceOperationId: 'sale-1', items: [{productId: 'anel', quantity: 1}]}, owner);
    assert.equal(stock(db, base, 'anel').variacoes['20'].Rubelita, 4);
  });
}

test('NO_CONTROL: generic restock still blocked with LEGACY_PROTOCOL_BLOCKED', async () => {
  const {db, base, lojaId} = seedStore('NO_CONTROL');
  const snap = db.snapshot();
  await rejectsWith(executeStockCommand(db, {protocolVersion: 1, lojaId, kind: 'restock', operationId: 'r1',
    items: [{productId: 'simples', quantity: 1}]}, owner), {code: 'failed-precondition', detail: 'LEGACY_PROTOCOL_BLOCKED'});
  assert.deepEqual(db.snapshot(), snap);
});

test('ACTIVE: saleEdit needs only the sale grant; no grant → denied', async () => {
  const ok = seedStore('ACTIVE', {grantPerms: {sale: true}});
  await edit(ok.db, ok.base, ok.lojaId, [line('anel', 1, {tamanho: '20', cor: 'Rubelita'})]);
  assert.equal(ok.db.getData(ok.base.collection('estoque_produtos').doc('brinco')).variacoes.P['sem-cor'], 3);
  const denied = seedStore('ACTIVE', {grantPerms: {restock: true}});
  await rejectsWith(edit(denied.db, denied.base, denied.lojaId, [line('anel', 1, {tamanho: '20', cor: 'Rubelita'})]),
    {code: 'permission-denied'});
});

test('old client mixed edit against new server: zero partial writes (NO_CONTROL)', async () => {
  const {db, base, lojaId} = seedStore('NO_CONTROL');
  const hash = 'd2bb677f80077766ae488a05602eec60dafe09d83e1b22c21ae06050dbb7892b';
  const snap = db.snapshot();
  const from = db.commits.length;
  await rejectsWith(executeStockCommand(db, {protocolVersion: 1, lojaId, kind: 'sale',
    operationId: `editstock_sale-1_${hash}_sale`, items: [{productId: 'anel', quantity: 1, size: '20', color: 'Rubelita'}]}, owner),
  {code: 'failed-precondition', detail: 'LEGACY_PROTOCOL_BLOCKED', reason: 'LEGACY_SPLIT_EDIT_SALE_HALF'});
  await rejectsWith(executeStockCommand(db, {protocolVersion: 1, lojaId, kind: 'restock',
    operationId: `editstock_sale-1_${hash}_restock`, items: [{productId: 'brinco', quantity: 1, size: 'P', color: 'sem-cor'}]}, owner),
  {code: 'failed-precondition', detail: 'LEGACY_PROTOCOL_BLOCKED'});
  assert.equal(writesSince(db, from), 0, 'OLD_CLIENT_MIXED_EDIT_PARTIAL_WRITE_COUNT');
  assert.deepEqual(db.snapshot(), snap);
});

test('normal new sales and single-command legacy increases still work (NO_CONTROL)', async () => {
  const {db, base, lojaId} = seedStore('NO_CONTROL');
  await executeStockCommand(db, {protocolVersion: 1, lojaId, kind: 'sale', operationId: '7b0c8a52-1d4e-4f7e-9a51-0c2f2b6a9e11',
    items: [{productId: 'simples', quantity: 1}]}, owner);
  await executeStockCommand(db, {protocolVersion: 1, lojaId, kind: 'sale',
    operationId: `editstock_sale-1_${'c'.repeat(64)}`, items: [{productId: 'simples', quantity: 1}]}, owner);
  assert.equal(stock(db, base, 'simples').quantidade, 3);
});

test('simple product insufficient stock reports INSUFFICIENT_STOCK; missing grade selection keeps GRADE_SELECTION_REQUIRED', async () => {
  const {db, lojaId} = seedStore('NO_CONTROL');
  await rejectsWith(executeStockCommand(db, {protocolVersion: 1, lojaId, kind: 'sale', operationId: 'sale-simple-short',
    items: [{productId: 'simples', quantity: 6}]}, owner), {issueReason: 'INSUFFICIENT_STOCK'});
  await assert.rejects(executeStockCommand(db, {protocolVersion: 1, lojaId, kind: 'sale', operationId: 'sale-var-noselect',
    items: [{productId: 'anel', quantity: 1}]}, owner), e => e.issues?.[0]?.reasonCode === 'GRADE_SELECTION_REQUIRED');
});

test('clientBuild is observability only: replay with or without it is identical', async () => {
  const {db, base, lojaId} = seedStore('NO_CONTROL');
  const cmd = editCommand(lojaId, [line('anel', 2, {tamanho: '20', cor: 'Rubelita'})], {stored: stored(db, base)});
  await executeStockCommand(db, {...cmd, clientBuild: '1.0.136+150'}, owner);
  const replay = await executeStockCommand(db, cmd, owner);
  assert.equal(replay.alreadyApplied, true);
});

function bigStore(changedProducts, totalLines) {
  const products = {};
  for (let i = 0; i < changedProducts; i++) {
    products[`p${i}`] = {nome: `P${i}`, stockKind: 'simple', stockRevision: 1, quantidade: 10, variacoes: {}};
  }
  const saleLines = [];
  for (let i = 0; i < totalLines; i++) {
    saleLines.push(line(i < changedProducts ? `p${i}` : `untouched-${i}`, 1));
  }
  return {products, saleLines};
}

for (const totalLines of [50, 100, 150]) {
  test(`write budget: ${totalLines}-line sale with 25 changed products fits; 26 fails before writes`, async () => {
    for (const mode of MODES) {
      const ok = bigStore(25, totalLines);
      const s = seedStore(mode, {products: ok.products, saleLines: ok.saleLines});
      const newLines = ok.saleLines.map((l, i) => (i < 25 ? {...l, quantidade: 2, precoTotal: 20} : l));
      const from = s.db.commits.length;
      const r = await edit(s.db, s.base, s.lojaId, newLines);
      const commit = s.db.commits.slice(from).find(c => c.ops.length);
      console.log(`SALE_EDIT_${totalLines}_LINE_25_CHANGED_${mode}: writes=${commit.writes} transforms=${commit.transforms} units=${commitUnits(commit)} reported=${r.writeUnits}`);
      assert.ok(commit.writes <= 100);
      assert.ok(commitUnits(commit) <= 500);

      const tooMany = bigStore(26, totalLines);
      const t = seedStore(mode, {products: tooMany.products, saleLines: tooMany.saleLines});
      const snap = t.db.snapshot();
      await rejectsWith(edit(t.db, t.base, t.lojaId, tooMany.saleLines.map((l, i) => (i < 26 ? {...l, quantidade: 2} : l))),
        {code: 'resource-exhausted', reason: 'SALE_EDIT_TOO_LARGE'});
      assert.deepEqual(t.db.snapshot(), snap);
    }
  });
}

test(`more than ${MAX_SALE_EDIT_LINES} lines is rejected before any read or write`, async () => {
  const {saleLines} = bigStore(0, MAX_SALE_EDIT_LINES + 1);
  const s = seedStore('NO_CONTROL', {saleLines});
  const snap = s.db.snapshot();
  await rejectsWith(edit(s.db, s.base, s.lojaId, saleLines), {reason: 'SALE_EDIT_TOO_LARGE'});
  assert.deepEqual(s.db.snapshot(), snap);
});

test('lines hash is order-insensitive, aggregates duplicates and ignores names when productId exists', () => {
  const a = storedSaleLines([line('anel', 1, {tamanho: '20', cor: 'Rubelita'}), line('simples', 2)]);
  const b = storedSaleLines([{...line('simples', 1), produtoNome: 'Outro nome'}, line('simples', 1), line('anel', 1, {tamanho: ' 20 ', cor: 'rubelita'})]);
  assert.equal(saleLinesHash(a), saleLinesHash(b));
  assert.notEqual(saleLinesHash(a), saleLinesHash(storedSaleLines([line('simples', 2)])));
});

test('lines hash parity vectors (mirrored in Dart)', () => {
  const v1 = saleLinesHash(storedSaleLines([
    {produtoNome: 'Anel', quantidade: 1, tamanho: '20', cor: 'Rubelita', productId: 'anel'},
    {produtoNome: 'Letra', quantidade: 2, tamanho: '', cor: 'Gold', extraValor: 'J', productId: 'letra'},
    {produtoNome: 'Sem ID  Antigo', quantidade: 1, tamanho: '', cor: ''},
    {produtoNome: 'Lilás', quantidade: 3, tamanho: 'P', cor: 'LILÁS', productId: 'brinco-ç'},
  ]));
  const v2 = saleLinesHash([]);
  assert.equal(v1, 'a6f28cf0fe70d104f1264fc12d4b90caa3cf410cbdfcb871c1f99328f8ed986a');
  assert.equal(v2, '4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945');
});

test('sale operation currentItems: exact merge, unreliable when the record cannot absorb a restore', () => {
  const base = {items: [{productId: 'a', quantity: 1, size: '20', color: 'Rubelita', extra: ''}]};
  assert.deepEqual(nextSaleOperationItems(base, [
    {productId: 'a', quantity: 1, size: '20', color: 'Rubelita', extra: '', direction: 'restore'},
    {productId: 'a', quantity: 1, size: '20', color: 'Esmeralda', extra: '', direction: 'debit'},
  ]).items, [{productId: 'a', size: '20', color: 'Esmeralda', extra: '', quantity: 1}]);
  assert.equal(nextSaleOperationItems(base, [
    {productId: 'b', quantity: 1, size: '', color: '', extra: '', direction: 'restore'},
  ]).unreliable, true);
});

test('fiado fields are removed when the edited sale has no open balance', () => {
  const patch = buildSaleEditPatch({operationId: 'saleedit_x', saleEdit: {sale: {
    clienteNome: 'C', total: 10, itens: [], saldoFiado: 0, quantidadeParcelasFiado: null,
    intervaloParcelasDias: null, dataVencimentoFiado: null, data: null,
  }}}, {revision: 2}, {actorUid: 'owner'});
  for (const key of ['saldoFiado', 'quantidadeParcelasFiado', 'intervaloParcelasDias', 'dataVencimentoFiado']) {
    assert.equal(patch[key]?.constructor?.name, 'DeleteTransform', key);
  }
  assert.equal(patch.saleEditRevision, 2);
  assert.ok(!('stockOperationId' in patch) && !('createdAt' in patch) && !('id' in patch));
});

test('rejection log carries no customer data', () => {
  const raw = editCommand('loja-x', [line('anel', 1)], {stored: [line('anel', 2)], sale: {clienteNome: 'Maria Cliente Secreta', observacao: 'tel 99999'}});
  raw.clientBuild = '1.0.136+150';
  const err = new Error('Sale lines changed since the edit started');
  err.code = 'aborted';
  err.details = {code: 'SALE_EDIT_CONFLICT', reason: 'ORIGINAL_LINES_CHANGED'};
  const entry = stockCommandRejectionLog(raw, err);
  const text = JSON.stringify(entry);
  assert.ok(!text.includes('Maria') && !text.includes('99999') && !text.includes('sale-1'));
  assert.equal(entry.reasonCode, 'SALE_EDIT_CONFLICT');
  assert.equal(entry.operationType, 'saleEdit');
  assert.equal(entry.clientBuild, '1.0.136+150');
  assert.match(entry.saleRef, /^[0-9a-f]{16}$/);
  const legacy = stockCommandRejectionLog({lojaId: 'l', kind: 'sale', operationId: `editstock_abc_${'d'.repeat(64)}_sale`}, {code: 'failed-precondition', details: {code: 'LEGACY_PROTOCOL_BLOCKED'}});
  assert.equal(legacy.operationType, 'legacyEditSplitSale');
});
