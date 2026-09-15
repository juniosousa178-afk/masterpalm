// Payload de venda canônica para stockCatalogCommand atomicPdvSale.
// Espelha o schema de VendasFirestoreService.syncVenda (sem timestamps/server fields).

Map<String, dynamic> buildAtomicPdvSalePayload({
  required String clienteNome,
  String? clienteId,
  required String produtosDescricao,
  required int quantidade,
  required double preco,
  required double total,
  required String formasPagamento,
  required double frete,
  required double desconto,
  required double descontoValor,
  required String observacao,
  required double pagamentoDinheiro,
  required double pagamentoPix,
  required double pagamentoCartao,
  required double taxas,
  required double custoProdutos,
  required String tamanho,
  required String vendedor,
  String? vendedorUid,
  String? vendedorNome,
  String? vendedorEmail,
  required List<Map<String, dynamic>> itens,
  String? origemCusto,
  String? itensComboSelecaoJson,
  double saldoFiado = 0,
  int? quantidadeParcelasFiado,
  int? intervaloParcelasDias,
  String? dataVencimentoFiado,
}) {
  return <String, dynamic>{
    'clienteNome': clienteNome,
    if (clienteId != null && clienteId.trim().isNotEmpty) 'clienteId': clienteId.trim(),
    'produtosDescricao': produtosDescricao,
    'quantidade': quantidade,
    'preco': preco,
    'total': total,
    'formasPagamento': formasPagamento,
    'frete': frete,
    'desconto': desconto,
    'descontoValor': descontoValor,
    'observacao': observacao,
    'pagamentoDinheiro': pagamentoDinheiro,
    'pagamentoPix': pagamentoPix,
    'pagamentoCartao': pagamentoCartao,
    'taxas': taxas,
    'custoProdutos': custoProdutos,
    'tamanho': tamanho,
    'vendedor': vendedor,
    if (vendedorUid != null && vendedorUid.trim().isNotEmpty)
      'vendedorUid': vendedorUid.trim(),
    if (vendedorNome != null && vendedorNome.trim().isNotEmpty)
      'vendedorNome': vendedorNome.trim(),
    if (vendedorEmail != null && vendedorEmail.trim().isNotEmpty)
      'vendedorEmail': vendedorEmail.trim().toLowerCase(),
    'itens': itens,
    if (origemCusto != null && origemCusto.trim().isNotEmpty)
      'origemCusto': origemCusto.trim(),
    if (itensComboSelecaoJson != null && itensComboSelecaoJson.trim().isNotEmpty)
      'itensComboSelecaoJson': itensComboSelecaoJson.trim(),
    if (saldoFiado > 0.01) 'saldoFiado': saldoFiado,
    if (saldoFiado > 0.01 &&
        quantidadeParcelasFiado != null &&
        quantidadeParcelasFiado > 1)
      'quantidadeParcelasFiado': quantidadeParcelasFiado,
    if (saldoFiado > 0.01 &&
        quantidadeParcelasFiado != null &&
        quantidadeParcelasFiado > 1 &&
        intervaloParcelasDias != null)
      'intervaloParcelasDias': intervaloParcelasDias,
    if (saldoFiado > 0.01 &&
        dataVencimentoFiado != null &&
        dataVencimentoFiado.trim().isNotEmpty)
      'dataVencimentoFiado': dataVencimentoFiado.trim(),
  };
}
