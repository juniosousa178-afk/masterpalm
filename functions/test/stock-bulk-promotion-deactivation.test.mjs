/**
 * Bulk "Desativar promoções": the client sends one existing `editorial` command per product with
 * exactly the patch the product form sends when the promotion switch is off. Proves on the real
 * command path that only the promotion fields change. In-memory only (no production writes).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {executeStockCommand} from '../src/stockCatalogCommands.js';
import {createConsignmentTestDb} from './consignment-test-db.mjs';

const owner = {uid: 'owner'};
/** Mirrors ProdutoPromocao.camposDesativacao (lib/services/produto_promocao.dart). */
const PATCH = {emPromocao: false, percentualPromo: null, valorPromo: null};
const PROMO_KEYS = Object.keys(PATCH);
const STOCK_KEYS = ['quantidade', 'variacoes', 'estoquePorTamanho', 'estoquePorCor', 'tamanhos', 'cores',
  'variacoesExtraTipo', 'stockKind', 'stockRevision', 'stockOperationId', 'historicalStockCells', 'itensCombo', 'comboConfig'];
let seq = 0;

const promo = {
  emPromocao: true, percentualPromo: 20, valorPromo: null,
  dataInicioPromo: '2026-10-01T00:00:00.000', dataFimPromo: '2026-12-31T00:00:00.000',
};
const FIXTURE = {
  simples: {price: 100, extra: {...promo, codigoBarras: '7891', imagens: ['https://img/s.jpg'], categoria: 'Religiosos'}},
  fixo: {price: 80, extra: {...promo, percentualPromo: null, valorPromo: 10}},
  variacao: {
    price: 120, extra: promo,
    stock: {stockKind: 'variation', quantidade: 5, variacoes: {P: {Azul: 2, Rosa: 1}, M: {Azul: 2}},
      estoquePorTamanho: {P: 3, M: 2}, estoquePorCor: {}, tamanhos: ['P', 'M'], cores: ['Azul', 'Rosa']},
  },
  naoPublicado: {price: 30, extra: {...promo, publicadoNoCatalogo: false}, noLive: true},
};

function seedStore(db, lojaId, {active = false} = {}) {
  const base = db.collection('lojas').doc(lojaId);
  db.seed(base, {ownerUid: 'owner', lojaId});
  if (active) {
    db.seed(base.collection('stock_catalog_control').doc('state'), {protocolVersion: 1, mode: 'active', migrationComplete: true});
    db.seed(base.collection('stock_catalog_access').doc('owner'), {enabled: true, permissions: {editorial: true, adjust: true, publish: true}});
  }
  for (const [id, p] of Object.entries(FIXTURE)) {
    const editorial = {nome: id, preco: p.price, preco_venda: p.price, precoFinal: p.price, publicadoNoCatalogo: true, ...p.extra};
    // Server-normalized shape (what normalizeStock writes back on any command).
    const stockShape = p.stock ?? {stockKind: 'simple', quantidade: 4, variacoes: {}, estoquePorTamanho: {}, estoquePorCor: {}};
    db.seed(base.collection('estoque_produtos').doc(id), {
      lojaId, custoReal: 31.5, stockRevision: 7, stockOperationId: `prev_${id}`, ...stockShape, ...editorial,
    });
    db.seed(base.collection('draft_produtos').doc(id), {...editorial, catalogStockRevision: 7});
    if (!p.noLive) db.seed(base.collection('produtos').doc(id), {...editorial, quantidade: stockShape.quantidade, catalogStockRevision: 7});
    db.seed(base.collection('stock_catalog_dependencies').doc(id), {comboIds: []});
  }
  return base;
}

const read = (db, base, col, id) => db.getData(base.collection(col).doc(id));
const pick = (doc, keys) => Object.fromEntries(keys.filter(k => k in (doc ?? {})).map(k => [k, doc[k]]));
/** Same derivation as BulkPromocaoService.operationId. */
const opId = (lojaId, bulkId, docId) => `promooff_${createHash('sha256').update(`${lojaId}|${bulkId}|${docId}`).digest('hex')}`;
const cmd = (lojaId, id, bulkId = 'promobulk_t') => ({
  protocolVersion: 1, lojaId, operationId: opId(lojaId, bulkId, id), kind: 'editorial',
  items: [{productId: id}], editorial: {...PATCH},
});

for (const active of [false, true]) {
  const route = active ? 'ACTIVE' : 'NO_CONTROL';

  test(`várias: só os campos de promoção mudam; preço, estoque, período e mídia preservados (${route})`, async () => {
    const db = createConsignmentTestDb();
    const lojaId = `promo_${++seq}`;
    const base = seedStore(db, lojaId, {active});
    const before = db.snapshot();
    for (const id of Object.keys(FIXTURE)) {
      const r = await executeStockCommand(db, cmd(lojaId, id), owner);
      assert.notEqual(r.alreadyApplied, true, id);
    }
    for (const [id, p] of Object.entries(FIXTURE)) {
      const cols = p.noLive ? ['estoque_produtos', 'draft_produtos'] : ['estoque_produtos', 'draft_produtos', 'produtos'];
      for (const col of cols) {
        const doc = read(db, base, col, id);
        const prior = before.get(`${base.path}/${col}/${id}`);
        assert.ok(doc, `${col}/${id} not deleted`);
        assert.deepEqual(pick(doc, PROMO_KEYS), PATCH, `${col}/${id} promotion off`);
        assert.equal(doc.preco, p.price, `NORMAL_PRICE_PRESERVED ${col}/${id}`);
        assert.equal(doc.precoFinal, p.price);
        assert.equal(doc.preco_venda, p.price);
        assert.equal(doc.dataInicioPromo, promo.dataInicioPromo, 'period kept, like the form');
        assert.equal(doc.dataFimPromo, promo.dataFimPromo);
        assert.equal(doc.publicadoNoCatalogo, prior.publicadoNoCatalogo, 'publication unchanged');
        assert.deepEqual(doc.imagens, prior.imagens);
        assert.equal(doc.categoria, prior.categoria);
      }
      const stock = read(db, base, 'estoque_produtos', id);
      const priorStock = before.get(`${base.path}/estoque_produtos/${id}`);
      assert.deepEqual(pick(stock, STOCK_KEYS), pick(priorStock, STOCK_KEYS), `STOCK_PRESERVED ${id}`);
      assert.equal(stock.custoReal, 31.5);
      assert.equal(stock.codigoBarras, priorStock.codigoBarras);
    }
    assert.equal(read(db, base, 'produtos', 'naoPublicado'), undefined, 'unpublished product is not published');
    assert.deepEqual(read(db, base, 'estoque_produtos', 'variacao').variacoes, FIXTURE.variacao.stock.variacoes);
  });

  test(`outra loja intacta (${route})`, async () => {
    const db = createConsignmentTestDb();
    const lojaA = `promoA_${++seq}`, lojaB = `promoB_${seq}`;
    seedStore(db, lojaA, {active});
    const baseB = seedStore(db, lojaB, {active});
    const before = db.snapshot();
    await executeStockCommand(db, cmd(lojaA, 'simples'), owner);
    for (const col of ['estoque_produtos', 'draft_produtos', 'produtos']) {
      const path = `${baseB.path}/${col}/simples`;
      assert.deepEqual(read(db, baseB, col, 'simples'), before.get(path), path);
    }
  });

  test(`reenvio com o mesmo operationId é replay, sem segunda escrita (${route})`, async () => {
    const db = createConsignmentTestDb();
    const lojaId = `promoR_${++seq}`;
    seedStore(db, lojaId, {active});
    await executeStockCommand(db, cmd(lojaId, 'simples'), owner);
    const snapshot = db.snapshot();
    const again = await executeStockCommand(db, cmd(lojaId, 'simples'), owner);
    assert.equal(again.alreadyApplied, true);
    assert.deepEqual(db.snapshot(), snapshot, 'replay writes nothing');
  });
}

test('produto inexistente falha sem escrever nada; os demais seguem', async () => {
  const db = createConsignmentTestDb();
  const lojaId = `promoF_${++seq}`;
  const base = seedStore(db, lojaId);
  const before = db.snapshot();
  await assert.rejects(executeStockCommand(db, cmd(lojaId, 'naoExiste'), owner),
    e => e.code === 'failed-precondition' && /^Canonical product/.test(e.message));
  assert.deepEqual(db.snapshot(), before, 'failed product wrote nothing');
  await executeStockCommand(db, cmd(lojaId, 'fixo'), owner);
  assert.deepEqual(pick(read(db, base, 'estoque_produtos', 'fixo'), PROMO_KEYS), PATCH);
});

test('operationId: vetor fixo compartilhado com o teste Dart (Dart == JS) e aceito pelo servidor', async () => {
  assert.equal(opId('loja1', 'promobulk_vec', 'abc'),
    'promooff_271fff0c705c06d8e31e3d2b2760f82f8c3c6cc9bfd32414e33c7f2eed1efad2');
});

test('mais de um produto por comando editorial é recusado (por isso o cliente envia um a um)', async () => {
  const db = createConsignmentTestDb();
  const lojaId = `promoM_${++seq}`;
  seedStore(db, lojaId);
  const c = cmd(lojaId, 'simples');
  c.items = [{productId: 'simples'}, {productId: 'fixo'}];
  await assert.rejects(executeStockCommand(db, c, owner), /Editorial command requires one product/);
});
