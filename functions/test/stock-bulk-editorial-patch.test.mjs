/**
 * Bulk Pix / dividir sem juros / ativar promoção: the client sends one existing `editorial` command
 * per product carrying only the changed fields (BulkEditorialService). Proves on the real command
 * path that estoque, draft and live get the fields and nothing else changes. In-memory only.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {executeStockCommand} from '../src/stockCatalogCommands.js';
import {createConsignmentTestDb} from './consignment-test-db.mjs';

const owner = {uid: 'owner'};
/** Mirrors BulkEditorialPlano (lib/services/bulk_editorial_service.dart). */
const PLANS = {
  pixset: {percentualDescontoPix: 10},
  parcel: {divideSemJuros: true, maxParcelasSemJuros: 6},
  promoon: {emPromocao: true, percentualPromo: 20, valorPromo: null, dataInicioPromo: null, dataFimPromo: null},
};
const STOCK_KEYS = ['quantidade', 'variacoes', 'estoquePorTamanho', 'estoquePorCor', 'tamanhos', 'cores',
  'variacoesExtraTipo', 'stockKind', 'stockRevision', 'stockOperationId', 'historicalStockCells', 'itensCombo', 'comboConfig'];
const KEPT_KEYS = ['preco', 'precoFinal', 'preco_venda', 'categoria', 'subcategoria', 'publicadoNoCatalogo', 'imagens', 'nome'];
let seq = 0;

const FIXTURE = {
  simples: {price: 100, extra: {codigoBarras: '7891', imagens: ['https://img/s.jpg'], categoria: 'Aneis', subcategoria: 'Prata'}},
  variacao: {
    price: 120, extra: {categoria: 'Colares'},
    stock: {stockKind: 'variation', quantidade: 5, variacoes: {P: {Azul: 2, Rosa: 1}, M: {Azul: 2}},
      estoquePorTamanho: {P: 3, M: 2}, estoquePorCor: {}, tamanhos: ['P', 'M'], cores: ['Azul', 'Rosa']},
  },
  naoPublicado: {price: 30, extra: {publicadoNoCatalogo: false}, noLive: true},
};

function seedStore(db, lojaId, {active = false} = {}) {
  const base = db.collection('lojas').doc(lojaId);
  db.seed(base, {ownerUid: 'owner', lojaId});
  if (active) {
    db.seed(base.collection('stock_catalog_control').doc('state'), {protocolVersion: 1, mode: 'active', migrationComplete: true});
    db.seed(base.collection('stock_catalog_access').doc('owner'), {enabled: true, permissions: {editorial: true, adjust: true, publish: true}});
  }
  for (const [id, p] of Object.entries(FIXTURE)) {
    const editorial = {
      nome: id, preco: p.price, preco_venda: p.price, precoFinal: p.price, publicadoNoCatalogo: true,
      percentualDescontoPix: 0, divideSemJuros: false, maxParcelasSemJuros: 12,
      emPromocao: false, percentualPromo: null, valorPromo: null, ...p.extra,
    };
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
/** Same derivation as BulkEditorialService.operationId. */
const opId = (prefix, lojaId, bulkId, docId) =>
  `${prefix}_${createHash('sha256').update(`${lojaId}|${bulkId}|${docId}`).digest('hex')}`;
const cmd = (prefix, lojaId, id, bulkId = 'edbulk_t', patch = PLANS[prefix]) => ({
  protocolVersion: 1, lojaId, operationId: opId(prefix, lojaId, bulkId, id), kind: 'editorial',
  items: [{productId: id}], editorial: {...patch},
});

for (const active of [false, true]) {
  const route = active ? 'ACTIVE' : 'NO_CONTROL';

  for (const [prefix, patch] of Object.entries(PLANS)) {
    test(`${prefix}: estoque, draft e live recebem só o patch; estoque, preço e publicação preservados (${route})`, async () => {
      const db = createConsignmentTestDb();
      const lojaId = `ed_${++seq}`;
      const base = seedStore(db, lojaId, {active});
      const before = db.snapshot();
      for (const id of Object.keys(FIXTURE)) {
        const r = await executeStockCommand(db, cmd(prefix, lojaId, id), owner);
        assert.notEqual(r.alreadyApplied, true, id);
      }
      for (const [id, p] of Object.entries(FIXTURE)) {
        const cols = p.noLive ? ['estoque_produtos', 'draft_produtos'] : ['estoque_produtos', 'draft_produtos', 'produtos'];
        for (const col of cols) {
          const doc = read(db, base, col, id);
          const prior = before.get(`${base.path}/${col}/${id}`);
          assert.ok(doc, `${col}/${id} not deleted`);
          assert.deepEqual(pick(doc, Object.keys(patch)), patch, `${col}/${id} patch applied`);
          assert.deepEqual(pick(doc, KEPT_KEYS), pick(prior, KEPT_KEYS), `${col}/${id} untouched fields`);
        }
        const stock = read(db, base, 'estoque_produtos', id);
        const priorStock = before.get(`${base.path}/estoque_produtos/${id}`);
        assert.deepEqual(pick(stock, STOCK_KEYS), pick(priorStock, STOCK_KEYS), `STOCK_PRESERVED ${id}`);
        assert.equal(stock.custoReal, 31.5);
        assert.equal(stock.codigoBarras, priorStock.codigoBarras);
      }
      assert.equal(read(db, base, 'produtos', 'naoPublicado'), undefined, 'unpublished product is not published');
    });
  }

  test(`Pix e promoção em lote coexistem no live (${route})`, async () => {
    const db = createConsignmentTestDb();
    const lojaId = `edPP_${++seq}`;
    const base = seedStore(db, lojaId, {active});
    await executeStockCommand(db, cmd('promoon', lojaId, 'simples'), owner);
    await executeStockCommand(db, cmd('pixset', lojaId, 'simples'), owner);
    const live = read(db, base, 'produtos', 'simples');
    assert.equal(live.emPromocao, true);
    assert.equal(live.percentualPromo, 20);
    assert.equal(live.percentualDescontoPix, 10);
    assert.equal(live.preco, 100);
  });

  test(`reenvio com o mesmo operationId é replay; outro payload com o mesmo id é recusado (${route})`, async () => {
    const db = createConsignmentTestDb();
    const lojaId = `edR_${++seq}`;
    seedStore(db, lojaId, {active});
    await executeStockCommand(db, cmd('pixset', lojaId, 'simples'), owner);
    const snapshot = db.snapshot();
    const again = await executeStockCommand(db, cmd('pixset', lojaId, 'simples'), owner);
    assert.equal(again.alreadyApplied, true);
    assert.deepEqual(db.snapshot(), snapshot, 'replay writes nothing');
    await assert.rejects(
      executeStockCommand(db, cmd('pixset', lojaId, 'simples', 'edbulk_t', {percentualDescontoPix: 15}), owner),
      e => e.code === 'already-exists');
    assert.deepEqual(db.snapshot(), snapshot, 'conflict writes nothing');
  });
}

test('outra loja intacta', async () => {
  const db = createConsignmentTestDb();
  const lojaA = `edA_${++seq}`, lojaB = `edB_${seq}`;
  seedStore(db, lojaA);
  const baseB = seedStore(db, lojaB);
  const before = db.snapshot();
  await executeStockCommand(db, cmd('pixset', lojaA, 'simples'), owner);
  for (const col of ['estoque_produtos', 'draft_produtos', 'produtos']) {
    const path = `${baseB.path}/${col}/simples`;
    assert.deepEqual(read(db, baseB, col, 'simples'), before.get(path), path);
  }
});

test('Pix fora de 0–100 é recusado sem escrever nada (mesma faixa do cliente)', async () => {
  const db = createConsignmentTestDb();
  const lojaId = `edV_${++seq}`;
  seedStore(db, lojaId);
  const before = db.snapshot();
  for (const bad of [-1, 100.5, 'dez']) {
    await assert.rejects(
      executeStockCommand(db, cmd('pixset', lojaId, 'simples', `edbulk_${bad}`, {percentualDescontoPix: bad}), owner));
  }
  assert.deepEqual(db.snapshot(), before);
  for (const ok of [0, 100]) {
    await executeStockCommand(db, cmd('pixset', lojaId, 'simples', `edbulk_${ok}`, {percentualDescontoPix: ok}), owner);
  }
});

test('operationId: vetor fixo compartilhado com o teste Dart (Dart == JS)', () => {
  assert.equal(opId('pixset', 'loja1', 'edbulk_vec', 'abc'),
    'pixset_0c3122196e6cc92cebc19976d5c232c3a5d67a5a2a0fda91fe95098bdcdb359f');
});
