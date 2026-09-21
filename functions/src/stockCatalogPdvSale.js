import {FieldValue} from 'firebase-admin/firestore';
import {documentId} from './stockCatalogAccess.js';
import {isMap, quantity, stockError} from './catalogStockProjection.js';

/** Opt-in marker: old Web omits this and keeps stock-only + client syncVenda. */
export const ATOMIC_PDV_SALE_FLAG = 'atomicPdvSale';

const SALE_INPUT_KEYS = Object.freeze([
  'clienteNome', 'clienteId', 'produtosDescricao', 'quantidade', 'preco', 'total',
  'formasPagamento', 'frete', 'desconto', 'descontoValor', 'observacao',
  'pagamentoDinheiro', 'pagamentoPix', 'pagamentoCartao', 'taxas', 'custoProdutos',
  'tamanho', 'vendedor', 'vendedorUid', 'vendedorNome', 'vendedorEmail',
  'itens', 'origemCusto', 'itensComboSelecaoJson', 'saldoFiado',
  'quantidadeParcelasFiado', 'intervaloParcelasDias', 'dataVencimentoFiado',
]);

function nonNegNumber(value, label) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) {
    throw stockError('invalid-argument', `Invalid ${label}`);
  }
  return value;
}

function optionalString(value, label, max = 2000) {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'string') throw stockError('invalid-argument', `Invalid ${label}`);
  const trimmed = value.trim();
  if (trimmed.length > max) throw stockError('invalid-argument', `${label} too long`);
  return trimmed;
}

/**
 * Parse client sale envelope for atomic PDV sale. Stock items remain authoritative
 * for productId/qty/size/color/extra; sale.itens is display/history structure.
 */
export function parseAtomicPdvSale(rawSale, {operationId, lojaId, stockItems}) {
  if (!isMap(rawSale)) throw stockError('invalid-argument', 'atomicPdvSale requires sale object');
  if (Object.keys(rawSale).some(k => !SALE_INPUT_KEYS.includes(k))) {
    throw stockError('invalid-argument', 'Unknown or protected sale field');
  }
  const clienteNome = optionalString(rawSale.clienteNome, 'clienteNome', 200);
  if (!clienteNome) throw stockError('invalid-argument', 'clienteNome required');
  const total = nonNegNumber(rawSale.total, 'total');
  const preco = nonNegNumber(rawSale.preco ?? total, 'preco');
  const frete = nonNegNumber(rawSale.frete ?? 0, 'frete');
  const desconto = nonNegNumber(rawSale.desconto ?? 0, 'desconto');
  const descontoValor = nonNegNumber(rawSale.descontoValor ?? 0, 'descontoValor');
  const pagamentoDinheiro = nonNegNumber(rawSale.pagamentoDinheiro ?? 0, 'pagamentoDinheiro');
  const pagamentoPix = nonNegNumber(rawSale.pagamentoPix ?? 0, 'pagamentoPix');
  const pagamentoCartao = nonNegNumber(rawSale.pagamentoCartao ?? 0, 'pagamentoCartao');
  const taxas = nonNegNumber(rawSale.taxas ?? 0, 'taxas');
  const custoProdutos = nonNegNumber(rawSale.custoProdutos ?? 0, 'custoProdutos');
  const quantidade = quantity(rawSale.quantidade ?? stockItems.length);
  if (quantidade <= 0) throw stockError('invalid-argument', 'quantidade must be positive');
  if (!Array.isArray(rawSale.itens) || rawSale.itens.length === 0 || rawSale.itens.length > 100) {
    throw stockError('invalid-argument', 'sale.itens required');
  }
  const itens = rawSale.itens.map((item, index) => {
    if (!isMap(item)) throw stockError('invalid-argument', 'Invalid sale item');
    const allowed = ['produtoNome', 'quantidade', 'tamanho', 'cor', 'precoUnitario', 'precoTotal',
      'productId', 'variacaoExtraResumo', 'extraValor', 'custoUnitario', 'origemCustoItem'];
    if (Object.keys(item).some(k => !allowed.includes(k))) {
      throw stockError('invalid-argument', 'Unknown sale item field');
    }
    const productId = item.productId !== undefined
      ? documentId(item.productId, `sale.itens[${index}].productId`)
      : null;
    // productId is historical/display; combo roots may differ from expanded stock items.
    const q = quantity(item.quantidade);
    if (q <= 0) throw stockError('invalid-argument', 'sale item quantity must be positive');
    const precoUnitario = nonNegNumber(item.precoUnitario ?? 0, 'precoUnitario');
    return {
      produtoNome: optionalString(item.produtoNome, 'produtoNome', 300) ?? '',
      quantidade: q,
      tamanho: optionalString(item.tamanho, 'tamanho', 80) ?? '',
      cor: optionalString(item.cor, 'cor', 80) ?? '',
      precoUnitario,
      precoTotal: nonNegNumber(item.precoTotal ?? precoUnitario * q, 'precoTotal'),
      ...(productId ? {productId} : {}),
      ...(optionalString(item.variacaoExtraResumo, 'variacaoExtraResumo', 200)
        ? {variacaoExtraResumo: optionalString(item.variacaoExtraResumo, 'variacaoExtraResumo', 200)}
        : {}),
      ...(optionalString(item.extraValor, 'extraValor', 80)
        ? {extraValor: optionalString(item.extraValor, 'extraValor', 80)}
        : {}),
      custoUnitario: nonNegNumber(item.custoUnitario ?? 0, 'custoUnitario'),
      origemCustoItem: optionalString(item.origemCustoItem, 'origemCustoItem', 40) ?? 'desconhecido',
    };
  });
  const paid = pagamentoDinheiro + pagamentoPix + pagamentoCartao;
  let saldoFiado = 0;
  if (rawSale.saldoFiado !== undefined) {
    saldoFiado = nonNegNumber(rawSale.saldoFiado, 'saldoFiado');
    if (Math.abs(paid + saldoFiado - total) > 0.05) {
      throw stockError('invalid-argument', 'Payment + fiado must equal total');
    }
  } else if (Math.abs(paid - total) > 0.05) {
    throw stockError('invalid-argument', 'Payment total mismatch');
  }
  if (saldoFiado > 0.01 && paid - total > 0.01) {
    throw stockError('invalid-argument', 'Payment exceeds total');
  }
  return {
    operationId,
    lojaId,
    clienteNome,
    clienteId: optionalString(rawSale.clienteId, 'clienteId', 128),
    produtosDescricao: optionalString(rawSale.produtosDescricao, 'produtosDescricao', 8000) ?? '',
    quantidade,
    preco,
    total,
    formasPagamento: optionalString(rawSale.formasPagamento, 'formasPagamento', 2000) ?? '',
    frete,
    desconto,
    descontoValor,
    observacao: optionalString(rawSale.observacao, 'observacao', 2000) ?? '',
    pagamentoDinheiro,
    pagamentoPix,
    pagamentoCartao,
    taxas,
    custoProdutos,
    tamanho: optionalString(rawSale.tamanho, 'tamanho', 80) ?? '',
    vendedor: optionalString(rawSale.vendedor, 'vendedor', 200) ?? 'App',
    vendedorUid: optionalString(rawSale.vendedorUid, 'vendedorUid', 128),
    vendedorNome: optionalString(rawSale.vendedorNome, 'vendedorNome', 200),
    vendedorEmail: optionalString(rawSale.vendedorEmail, 'vendedorEmail', 200),
    itens,
    origemCusto: optionalString(rawSale.origemCusto, 'origemCusto', 40),
    itensComboSelecaoJson: optionalString(rawSale.itensComboSelecaoJson, 'itensComboSelecaoJson', 20000),
    saldoFiado,
    quantidadeParcelasFiado: rawSale.quantidadeParcelasFiado !== undefined
      ? quantity(rawSale.quantidadeParcelasFiado) : null,
    intervaloParcelasDias: rawSale.intervaloParcelasDias !== undefined
      ? quantity(rawSale.intervaloParcelasDias) : null,
    dataVencimentoFiado: rawSale.dataVencimentoFiado !== undefined
      ? optionalString(String(rawSale.dataVencimentoFiado), 'dataVencimentoFiado', 40)
      : null,
  };
}

/** Build canonical estoque_vendas document (Admin SDK FieldValue timestamps). */
export function buildCanonicalEstoqueVendaDoc(parsed, {actorUid}) {
  const doc = {
    id: parsed.operationId,
    lojaId: parsed.lojaId,
    data: FieldValue.serverTimestamp(),
    total: parsed.total,
    desconto: parsed.desconto,
    descontoValor: parsed.descontoValor,
    formasPagamento: parsed.formasPagamento,
    frete: parsed.frete,
    clienteNome: parsed.clienteNome,
    produtosDescricao: parsed.produtosDescricao,
    quantidade: parsed.quantidade,
    preco: parsed.preco,
    tamanho: parsed.tamanho,
    vendedor: parsed.vendedor,
    observacao: parsed.observacao,
    pagamentoDinheiro: parsed.pagamentoDinheiro,
    pagamentoPix: parsed.pagamentoPix,
    pagamentoCartao: parsed.pagamentoCartao,
    taxas: parsed.taxas,
    custoProdutos: parsed.custoProdutos,
    itens: parsed.itens,
    cancelada: false,
    estornada: false,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    status: 'concluida',
    statusVenda: 'concluida',
    stockOperationId: parsed.operationId,
    origemVenda: 'pdv_atomic',
    actorUid,
  };
  if (parsed.clienteId) doc.clienteId = parsed.clienteId;
  if (parsed.vendedorUid) doc.vendedorUid = parsed.vendedorUid;
  if (parsed.vendedorNome) doc.vendedorNome = parsed.vendedorNome;
  if (parsed.vendedorEmail) doc.vendedorEmail = parsed.vendedorEmail;
  if (parsed.origemCusto) doc.origemCusto = parsed.origemCusto;
  if (parsed.itensComboSelecaoJson) doc.itensComboSelecaoJson = parsed.itensComboSelecaoJson;
  if (parsed.saldoFiado > 0.01) {
    doc.saldoFiado = parsed.saldoFiado;
    if (parsed.quantidadeParcelasFiado && parsed.quantidadeParcelasFiado > 1) {
      doc.quantidadeParcelasFiado = parsed.quantidadeParcelasFiado;
      doc.intervaloParcelasDias = parsed.intervaloParcelasDias ?? 30;
    }
    if (parsed.dataVencimentoFiado) doc.dataVencimentoFiado = parsed.dataVencimentoFiado;
  }
  return doc;
}
