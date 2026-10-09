/**
 * Mir fixture (in-memory only): AN32SM -> "AN45SM - 103" on a zero-stock simple product
 * without a live doc. The same save with and without the code must produce identical
 * state except estoque_produtos.codigoBarras and the operation's own record.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import {executeStockCommand} from '../src/stockCatalogCommands.js';
import {createConsignmentTestDb} from './consignment-test-db.mjs';

const owner = {uid: 'owner'};
const lojaId = 'mirjoias';
const productId = 'mirjoias-anel-gota-verde-gua-t-20-semijoia-3';
const nome = 'Anel Gota Verde Água T.20 Semijoia';

function seed(active) {
  const db = createConsignmentTestDb();
  const base = db.collection('lojas').doc(lojaId);
  db.seed(base, {ownerUid: 'owner', lojaId});
  if (active) {
    db.seed(base.collection('stock_catalog_control').doc('state'), {protocolVersion: 1, mode: 'active', migrationComplete: true});
    db.seed(base.collection('stock_catalog_access').doc('owner'), {enabled: true, permissions: {editorial: true, adjust: true}});
  }
  db.seed(base.collection('estoque_produtos').doc(productId), {
    lojaId, nome, codigoBarras: 'AN32SM', quantidade: 0, stockKind: 'simple', tipoProduto: 'simples',
    stockRevision: 9, stockOperationId: 'consignment_issue_e6542fe1', variacoes: {},
  });
  db.seed(base.collection('draft_produtos').doc(productId), {nome, publicadoNoCatalogo: true, preco: 89, categoria: 'Anéis'});
  db.seed(base.collection('stock_catalog_dependencies').doc(productId), {comboIds: []});
  return {db, base};
}

const save = code => ({
  protocolVersion: 1, lojaId, kind: 'editorial', operationId: 'mir-code-save', items: [{productId}],
  editorial: {nome, preco: 89, categoria: 'Anéis', publicadoNoCatalogo: true, ...(code ? {codigoBarras: code} : {})},
});

const stripOp = snap => new Map([...snap].filter(([p]) => !p.includes('/stock_catalog_operations/')));

for (const active of [false, true]) {
  test(`MIR_CODE_UPDATE_FIXTURE (${active ? 'ACTIVE' : 'NO_CONTROL'}): only the stock code changes`, async () => {
    const withCode = seed(active);
    const without = seed(active);
    const before = withCode.db.snapshot();
    await executeStockCommand(withCode.db, save('AN45SM - 103'), owner);
    await executeStockCommand(without.db, save(null), owner);

    const stockPath = `lojas/${lojaId}/estoque_produtos/${productId}`;
    const a = stripOp(withCode.db.snapshot());
    const b = stripOp(without.db.snapshot());
    const stockA = a.get(stockPath);
    const stockB = b.get(stockPath);
    assert.equal(before.get(stockPath).codigoBarras, 'AN32SM');
    assert.equal(stockA.codigoBarras, 'AN45SM - 103', 'stored exactly as typed (no normalization)');
    assert.equal(stockB.codigoBarras, 'AN32SM');
    assert.deepEqual({...stockA, codigoBarras: null}, {...stockB, codigoBarras: null}, 'nothing else on stock differs');
    assert.equal(stockA.quantidade, 0);
    assert.equal(stockA.stockRevision, 9);
    assert.equal(stockA.stockOperationId, 'consignment_issue_e6542fe1');
    a.delete(stockPath);
    b.delete(stockPath);
    assert.deepEqual(a, b, 'draft, live and every other document identical with or without the code');
    assert.equal(a.has(`lojas/${lojaId}/produtos/${productId}`), b.has(`lojas/${lojaId}/produtos/${productId}`));
  });
}
