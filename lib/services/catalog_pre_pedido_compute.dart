// Cálculo puro de itens normalizados + subtotal + total do pré-pedido do catálogo.
// Espelha a primeira fase de [PrePedidoService.criarPrePedido] (sem Firestore).

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

/// Resultado estável para persistência no documento de pré-pedido (itens + valores).
class CatalogPrePedidoMoneySnapshot {
  const CatalogPrePedidoMoneySnapshot({
    required this.itensList,
    required this.subtotal,
    required this.total,
  });

  final List<Map<String, dynamic>> itensList;
  final double subtotal;
  final double total;
}

/// Normaliza linhas do carrinho e calcula subtotal/total como em `criarPrePedido`.
CatalogPrePedidoMoneySnapshot computeCatalogPrePedidoMoneySnapshot({
  required List<Map<String, dynamic>> items,
  required Map<String, dynamic> entrega,
  required String pagamento,
  double desconto = 0.0,
}) {
  int qtyFromItem(Map<String, dynamic> item) {
    final q = item['quantidade'] ?? item['qty'];
    if (q is int) return q;
    if (q is num) return q.round();
    return int.tryParse(q?.toString() ?? '') ?? 1;
  }

  double subtotal = 0.0;
  final itensList = <Map<String, dynamic>>[];
  final isPix = pagamento.toUpperCase() == 'PIX';

  for (final item in items) {
    final qty = qtyFromItem(item);
    final pRaw = item['preco'] ?? item['price'];
    final price = pRaw is num
        ? pRaw.toDouble()
        : (double.tryParse(pRaw?.toString() ?? '') ?? 0.0);
    final pctRaw = item['percentualDescontoPix'];
    final pctPix = pctRaw is num
        ? pctRaw.toDouble()
        : (double.tryParse(pctRaw?.toString() ?? '') ?? 0.0);
    final precoEfetivo =
        (isPix && pctPix > 0) ? price * (1 - pctPix / 100) : price;
    final itemTotal = precoEfetivo * qty;
    subtotal += itemTotal;

    final productId = (item['productId'] ?? item['id'] ?? item['produtosId'] ?? '')
        .toString()
        .trim();
    final nomeRaw = (item['nome'] ?? item['name'] ?? '').toString().trim();
    if (kDebugMode) {
      if (productId.isEmpty) {
        debugPrint(
          '[PRE-PEDIDO-SNAP] item sem productId (nome="$nomeRaw")',
        );
      }
      if (nomeRaw.isEmpty && productId.isNotEmpty) {
        debugPrint(
          '[PRE-PEDIDO-SNAP] item sem nome (productId=$productId)',
        );
      }
    }
    final storedItem = <String, dynamic>{
      'productId': productId,
      'id': productId,
      'produtosId': item['produtosId'] ?? productId,
      'nome': item['nome'] ?? item['name'] ?? '',
      'quantidade': qty,
      'precoUnitario': precoEfetivo,
      'tamanho': item['tamanho'] ?? item['size'] ?? '',
      'cor': item['cor'] ?? item['color'] ?? '',
      'imagem': item['imageUrl'] ?? item['url_foto'] ?? item['image'] ?? '',
      'slug': item['slug'] ?? '',
      'total': itemTotal,
    };
    final resumoExtra =
        (item['variacaoExtraResumo'] ?? '').toString().trim();
    if (resumoExtra.isNotEmpty) {
      storedItem['variacaoExtraResumo'] = resumoExtra;
    }
    final exVal = (item['extraValor'] ?? item['variacaoExtra'] ?? '')
        .toString()
        .trim();
    if (exVal.isNotEmpty) {
      storedItem['extraValor'] = exVal;
    }
    final exTipo = (item['extraTipo'] ?? '').toString().trim();
    if (exTipo.isNotEmpty) {
      storedItem['extraTipo'] = exTipo;
    }
    if (item['itensComboComSelecao'] is List) {
      storedItem['itensComboComSelecao'] = item['itensComboComSelecao'];
    }
    final rComboCfg =
        (item['comboConfiguravelResumo'] ?? '').toString().trim();
    if (rComboCfg.isNotEmpty) {
      storedItem['comboConfiguravelResumo'] = rComboCfg;
    }
    itensList.add(storedItem);
  }

  final freteGratis = entrega['freteGratis'] == true;
  final freteValor = (entrega['valor'] as num?)?.toDouble() ?? 0.0;
  final total = subtotal + (freteGratis ? 0 : freteValor) - desconto;

  return CatalogPrePedidoMoneySnapshot(
    itensList: itensList,
    subtotal: subtotal,
    total: total,
  );
}
