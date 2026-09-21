/** P0: atomicPdvSale allowlist + grade/multi-error + zero writes on protected field. */
import test from 'node:test';
import assert from 'node:assert/strict';
import {executeStockCommand} from '../src/stockCatalogCommands.js';
import {PRODUCT_VALIDATION_FAILED} from '../src/productValidationErrors.js';
import {createConsignmentTestDb} from './consignment-test-db.mjs';

const owner = {uid: 'owner'};
let seq = 0;

function saleEnvelope({pix = 10, cash = 0, card = 0, fiado = 0, itens} = {}) {
  const total = pix + cash + card + fiado;
  return {
    clienteNome: 'Cliente Teste',
    produtosDescricao: 'teste',
    quantidade: 1,
    preco: total,
    total,
    formasPagamento: fiado > 0 ? 'Fiado' : pix > 0 ? 'Pix' : cash > 0 ? 'Dinheiro' : 'Cartão',
    frete: 0,
    desconto: 0,
    descontoValor: 0,
    observacao: '',
    pagamentoDinheiro: cash,
    pagamentoPix: pix,
    pagamentoCartao: card,
    taxas: 0,
    custoProdutos: 0,
    tamanho: '',
    vendedor: 'App',
    itens: itens || [{produtoNome: 'Item', quantidade: 1, tamanho: '', cor: '', precoUnitario: total, precoTotal: total, productId: 'simple'}],
    ...(fiado > 0 ? {saldoFiado: fiado} : {}),
  };
}

async function seedStore({extraProducts = []} = {}) {
  const db = createConsignmentTestDb();
  const lojaId = `p0_${Date.now().toString(36)}_${++seq}`;
  const base = db.collection('lojas').doc(lojaId);
  db.seed(base, {ownerUid: 'owner', lojaId, nome: 'Master'});
  db.seed(base.collection('stock_catalog_control').doc('state'), {
    protocolVersion: 1, mode: 'active', migrationComplete: true,
  });
  db.seed(base.collection('stock_catalog_access').doc('owner'), {
    enabled: true,
    permissions: {sale: true, restock: true, adjust: true, restore: true, editorial: true, publish: true, create: true, delete: true, undo: true},
  });
  const products = [
    {
      id: 'simple',
      stock: {quantidade: 10, stockKind: 'simple', stockRevision: 0, variacoes: {}},
      draft: {nome: 'Simples', publicadoNoCatalogo: true, preco: 10},
    },
    {
      id: 'variation',
      stock: {
        stockKind: 'variation', stockRevision: 0, quantidade: 5,
        variacoes: {M: {'sem-cor': 5}}, tamanhos: ['M'], cores: ['sem-cor'],
      },
      draft: {nome: 'Variacao', publicadoNoCatalogo: true, preco: 20},
    },
    {
      id: 'grade',
      stock: {
        stockKind: 'variation', stockRevision: 0, quantidade: 4,
        variacoes: {P: {Azul: {A: 2, B: 2}}}, tamanhos: ['P'], cores: ['Azul'],
        variacoesExtraTipo: {A: true, B: true},
      },
      draft: {nome: 'Grade', publicadoNoCatalogo: true, preco: 30},
    },
    ...extraProducts,
  ];
  for (const p of products) {
    db.seed(base.collection('estoque_produtos').doc(p.id), p.stock);
    db.seed(base.collection('draft_produtos').doc(p.id), p.draft);
    db.seed(base.collection('stock_catalog_dependencies').doc(p.id), {comboIds: []});
  }
  return {db, base, lojaId};
}

function atomicSale(lojaId, operationId, items, sale) {
  return {
    protocolVersion: 1,
    lojaId,
    kind: 'sale',
    operationId,
    items,
    atomicPdvSale: true,
    sale: sale || saleEnvelope({
      itens: items.map(i => ({
        produtoNome: i.productId,
        quantidade: i.quantity,
        tamanho: i.size || '',
        cor: i.color || '',
        precoUnitario: 10,
        precoTotal: 10 * i.quantity,
        productId: i.productId,
        ...(i.extra ? {extraValor: i.extra} : {}),
      })),
      pix: items.reduce((s, i) => s + 10 * i.quantity, 0),
    }),
  };
}

test('1. simple atomic sale accepted once', async () => {
  const {db, base, lojaId} = await seedStore();
  const op = `op_simple_${++seq}`;
  const res = await executeStockCommand(db, atomicSale(lojaId, op, [
    {productId: 'simple', quantity: 1},
  ]), owner);
  assert.equal(res.alreadyApplied, false);
  assert.equal(res.saleCommitted, true);
  assert.equal(res.saleId, op);
  assert.equal(db.getData(base.collection('estoque_produtos').doc('simple')).quantidade, 9);
  assert.ok(db.getData(base.collection('estoque_vendas').doc(op)));
});

test('2. normal variation atomic sale decrements exact cell', async () => {
  const {db, base, lojaId} = await seedStore();
  const op = `op_var_${++seq}`;
  await executeStockCommand(db, atomicSale(lojaId, op, [
    {productId: 'variation', quantity: 1, size: 'M', color: 'sem-cor'},
  ]), owner);
  assert.equal(db.getData(base.collection('estoque_produtos').doc('variation')).variacoes.M['sem-cor'], 4);
});

test('3. grade atomic sale decrements exact cell', async () => {
  const {db, base, lojaId} = await seedStore();
  const op = `op_grade_${++seq}`;
  await executeStockCommand(db, atomicSale(lojaId, op, [
    {productId: 'grade', quantity: 1, size: 'P', color: 'Azul', extra: 'A'},
  ]), owner);
  const stock = db.getData(base.collection('estoque_produtos').doc('grade'));
  assert.equal(stock.variacoes.P.Azul.A, 1);
  assert.equal(stock.variacoes.P.Azul.B, 2);
});

test('4. mixed simple+variation+grade atomic', async () => {
  const {db, base, lojaId} = await seedStore();
  const op = `op_mix_${++seq}`;
  await executeStockCommand(db, atomicSale(lojaId, op, [
    {productId: 'simple', quantity: 1},
    {productId: 'variation', quantity: 1, size: 'M', color: 'sem-cor'},
    {productId: 'grade', quantity: 1, size: 'P', color: 'Azul', extra: 'B'},
  ], saleEnvelope({
    pix: 30,
    itens: [
      {produtoNome: 'Simples', quantidade: 1, tamanho: '', cor: '', precoUnitario: 10, precoTotal: 10, productId: 'simple'},
      {produtoNome: 'Variacao', quantidade: 1, tamanho: 'M', cor: 'sem-cor', precoUnitario: 10, precoTotal: 10, productId: 'variation'},
      {produtoNome: 'Grade', quantidade: 1, tamanho: 'P', cor: 'Azul', precoUnitario: 10, precoTotal: 10, productId: 'grade', extraValor: 'B'},
    ],
  })), owner);
  assert.equal(db.getData(base.collection('estoque_produtos').doc('simple')).quantidade, 9);
  assert.equal(db.getData(base.collection('estoque_produtos').doc('variation')).variacoes.M['sem-cor'], 4);
  assert.equal(db.getData(base.collection('estoque_produtos').doc('grade')).variacoes.P.Azul.B, 1);
});

test('5-8. payment command shapes pix/cash/card/fiado parse', async () => {
  const {db, lojaId} = await seedStore();
  for (const [label, pay] of [
    ['pix', {pix: 10}],
    ['cash', {cash: 10, pix: 0}],
    ['card', {card: 10, pix: 0}],
    ['fiado', {fiado: 10, pix: 0}],
  ]) {
    const op = `op_pay_${label}_${++seq}`;
    const res = await executeStockCommand(db, atomicSale(lojaId, op, [
      {productId: 'simple', quantity: 1},
    ], saleEnvelope({...pay, itens: [
      {produtoNome: 'Simples', quantidade: 1, tamanho: '', cor: '', precoUnitario: 10, precoTotal: 10, productId: 'simple'},
    ]})), owner);
    assert.equal(res.saleCommitted, true, label);
  }
});

test('9. invalid multi-product cart -> PRODUCT_VALIDATION_FAILED zero writes', async () => {
  const {db, base, lojaId} = await seedStore();
  const op = `op_multi_${++seq}`;
  await assert.rejects(
    () => executeStockCommand(db, atomicSale(lojaId, op, [
      {productId: 'simple', quantity: 1},
      {productId: 'missing', quantity: 1},
    ], saleEnvelope({
      pix: 20,
      itens: [
        {produtoNome: 'Simples', quantidade: 1, tamanho: '', cor: '', precoUnitario: 10, precoTotal: 10, productId: 'simple'},
        {produtoNome: 'Missing', quantidade: 1, tamanho: '', cor: '', precoUnitario: 10, precoTotal: 10, productId: 'missing'},
      ],
    })), owner),
    e => e.details?.code === PRODUCT_VALIDATION_FAILED || e.message?.includes('PRODUCT_VALIDATION'),
  );
  assert.equal(db.getData(base.collection('estoque_produtos').doc('simple')).quantidade, 10);
  assert.equal(db.getData(base.collection('estoque_vendas').doc(op)), undefined);
  assert.equal(db.getData(base.collection('stock_catalog_operations').doc(op)), undefined);
});

test('10. unknown top-level field still rejected', async () => {
  const {db, lojaId} = await seedStore();
  await assert.rejects(
    () => executeStockCommand(db, {
      protocolVersion: 1, lojaId, kind: 'sale', operationId: `op_bad_${++seq}`,
      items: [{productId: 'simple', quantity: 1}],
      stockRevisionOverride: 99,
    }, owner),
    e => /Unknown or protected command field/i.test(String(e.message || e)),
  );
});

test('11. atomicPdvSale+sale accepted at command schema', async () => {
  const {db, lojaId} = await seedStore();
  const res = await executeStockCommand(db, atomicSale(lojaId, `op_ok_${++seq}`, [
    {productId: 'simple', quantity: 1},
  ]), owner);
  assert.equal(res.saleCommitted, true);
});

test('12. duplicate operation idempotent', async () => {
  const {db, base, lojaId} = await seedStore();
  const op = `op_idem_${++seq}`;
  const cmd = atomicSale(lojaId, op, [{productId: 'simple', quantity: 1}]);
  const first = await executeStockCommand(db, cmd, owner);
  const second = await executeStockCommand(db, cmd, owner);
  assert.equal(first.alreadyApplied, false);
  assert.equal(second.alreadyApplied, true);
  assert.equal(db.getData(base.collection('estoque_produtos').doc('simple')).quantidade, 9);
  assert.ok(db.getData(base.collection('estoque_vendas').doc(op)));
});

test('15. validation failure before mutation leaves zero writes', async () => {
  const {db, base, lojaId} = await seedStore();
  const op = `op_zero_${++seq}`;
  await assert.rejects(
    () => executeStockCommand(db, {
      protocolVersion: 1, lojaId, kind: 'sale', operationId: op,
      items: [{productId: 'simple', quantity: 1}],
      atomicPdvSale: true,
      sale: saleEnvelope({pix: 10}),
      maliciousQty: 1,
    }, owner),
    e => /Unknown or protected command field/i.test(String(e.message || e)),
  );
  assert.equal(db.getData(base.collection('estoque_produtos').doc('simple')).quantidade, 10);
  assert.equal(db.getData(base.collection('estoque_vendas').doc(op)), undefined);
});
