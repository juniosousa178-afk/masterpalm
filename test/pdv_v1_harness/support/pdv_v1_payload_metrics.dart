// Métricas sintéticas de payload — harness Fase 6.3.
// JSON UTF-8 NÃO é tamanho wire exato do commit Firestore.

import 'dart:convert';

import 'pdv_v1_contract.dart';

class PdvV1PayloadReport {
  PdvV1PayloadReport({
    required this.label,
    required this.mergedItemCount,
    required this.preparedSnapshotBytes,
    required this.txItemsCanonicalBytes,
    required this.markerV1EstimatedBytes,
    required this.updateMapsEstimatedBytes,
    required this.plannedReads,
    required this.plannedWrites,
    required this.distinctStockDocs,
  });

  final String label;
  final int mergedItemCount;
  final int preparedSnapshotBytes;
  final int txItemsCanonicalBytes;
  final int markerV1EstimatedBytes;
  final int updateMapsEstimatedBytes;
  final int plannedReads;
  final int plannedWrites;
  final int distinctStockDocs;

  Map<String, dynamic> toMap() => {
        'label': label,
        'mergedItemCount': mergedItemCount,
        'preparedSnapshotBytes': preparedSnapshotBytes,
        'txItemsCanonicalBytes': txItemsCanonicalBytes,
        'markerV1EstimatedBytes': markerV1EstimatedBytes,
        'updateMapsEstimatedBytes': updateMapsEstimatedBytes,
        'plannedReads': plannedReads,
        'plannedWrites': plannedWrites,
        'distinctStockDocs': distinctStockDocs,
      };
}

Map<String, dynamic> pdvV1SyntheticPreparedSnapshot({
  required int itemCount,
  bool withVariacoes = false,
  bool withCombo = false,
  bool withFiado = false,
}) {
  final itens = <Map<String, dynamic>>[];
  for (var i = 0; i < itemCount; i++) {
    itens.add({
      'produtoNome': 'SKU-SINTETICO-$i',
      'quantidade': 1 + (i % 3),
      'precoUnitario': 19.90 + i,
      'tamanho': withVariacoes ? 'M' : '',
      'cor': withVariacoes ? 'azul-$i' : '',
      'productId': 'prod-sint-$i',
      'custoUnitario': 8.0,
    });
  }
  return {
    'protocolVersion': pdvV1ProtocolVersion,
    'operationId':
        '00000000-0000-4000-8000-${itemCount.toString().padLeft(12, '0')}',
    'saleId':
        '00000000-0000-4000-8000-${itemCount.toString().padLeft(12, '0')}',
    'lojaId': pdvV1HarnessLojaFicticia,
    'origem': pdvV1Origem,
    'itens': itens,
    'subtotal': itemCount * 25.0,
    'total': itemCount * 25.0,
    'frete': 0.0,
    'descontoPct': 0.0,
    'pagamentoDinheiro': itemCount * 25.0,
    'pagamentoPix': 0.0,
    'pagamentoCartao': 0.0,
    'custoProdutos': itemCount * 8.0,
    'taxas': itemCount * 3.5,
    'formasPagamentoTexto': 'Dinheiro',
    'produtosDescricao': 'Venda sintética harness',
    if (withCombo) 'itensComboSelecaoJson': '{"0":[{"nome":"comp"}]}',
    if (withFiado)
      'fiado': {
        'isFiado': true,
        'saldoFiado': 50.0,
        'parcelas': 2,
      },
  };
}

List<Map<String, dynamic>> pdvV1SyntheticTxItems(int mergedCount) {
  return List.generate(
    mergedCount,
    (i) => {
      'productId': 'prod-sint-$i',
      'nome': 'SKU-SINTETICO-$i',
      'quantidade': 1,
      'tamanho': '',
      'cor': '',
      'extraValor': '',
    },
  );
}

Map<String, dynamic> pdvV1SyntheticLargeVariationProduct() {
  final variacoes = <String, dynamic>{};
  for (var t = 0; t < 40; t++) {
    final cores = <String, dynamic>{};
    for (var c = 0; c < 20; c++) {
      cores['cor-$c'] = {'qtd': 5, 'extra': 'x$c'};
    }
    variacoes['tam-$t'] = cores;
  }
  return {
    'nome': 'Produto-Var-Grande',
    'quantidade': 800,
    'variacoes': variacoes,
    'estoquePorTamanho': <String, int>{},
  };
}

PdvV1PayloadReport pdvV1MeasurePayload({
  required String label,
  required Map<String, dynamic> preparedSnapshot,
  required List<Map<String, dynamic>> txItems,
  Map<String, dynamic>? largeUpdateMap,
}) {
  final snapBytes = utf8.encode(jsonEncode(preparedSnapshot)).length;
  final txBytes = utf8
      .encode(jsonEncode(pdvV1CanonicalJsonHash({'items': txItems})))
      .length;
  final marker = {
    'protocolVersion': 1,
    'operationId': preparedSnapshot['operationId'],
    'origem': 'pdv',
    'baixaAplicada': true,
    'txItemsHash': pdvV1CanonicalJsonHash({'items': txItems}),
    'lojaId': pdvV1HarnessLojaFicticia,
  };
  final markerBytes = utf8.encode(jsonEncode(marker)).length;
  final updateBytes = largeUpdateMap != null
      ? utf8.encode(jsonEncode(largeUpdateMap)).length
      : txItems.length * 512;

  final docIds = txItems.map((t) => t['productId'] as String).toList();
  final reads = 1 + docIds.length;
  final writes = docIds.isEmpty ? 0 : (docIds.length * 3 + 1);

  return PdvV1PayloadReport(
    label: label,
    mergedItemCount: txItems.length,
    preparedSnapshotBytes: snapBytes,
    txItemsCanonicalBytes: txBytes,
    markerV1EstimatedBytes: markerBytes,
    updateMapsEstimatedBytes: updateBytes,
    plannedReads: reads,
    plannedWrites: writes,
    distinctStockDocs: docIds.length,
  );
}
