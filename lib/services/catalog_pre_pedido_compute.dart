// Cálculo puro de itens normalizados + subtotal + total do pré-pedido do catálogo.
// Espelha a primeira fase de [PrePedidoService.criarPrePedido] (sem Firestore).

import 'catalog_cart_item_snapshot.dart';

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
  double subtotal = 0.0;
  final itensList = <Map<String, dynamic>>[];
  final isPix = pagamento.toUpperCase() == 'PIX';

  for (final raw in items) {
    final item = enrichCatalogCartLineSnapshot(
      line: Map<String, dynamic>.from(raw),
      pagamento: pagamento,
    );
    final qty = (item['quantidade'] as int?) ?? (item['qty'] as int?) ?? 1;
    final price = (item['preco'] as num?)?.toDouble() ??
        (item['price'] as num?)?.toDouble() ??
        0.0;
    final pctPix =
        (item['percentualDescontoPix'] as num?)?.toDouble() ?? 0.0;
    final precoEfetivo =
        (isPix && pctPix > 0) ? price * (1 - pctPix / 100) : price;
    final itemTotal = precoEfetivo * qty;
    subtotal += itemTotal;

    final productId = (item['productId'] ?? item['id'] ?? item['produtosId'] ?? '')
        .toString()
        .trim();
    final nomeSnap =
        (item['nomeSnapshot'] ?? item['nome'] ?? item['name'] ?? '').toString();
    final storedItem = <String, dynamic>{
      'productId': productId,
      'id': productId,
      'firestoreDocId':
          (item['firestoreDocId'] ?? productId).toString().trim(),
      'produtosId': item['produtosId'] ?? productId,
      'nome': nomeSnap,
      'nomeSnapshot': nomeSnap,
      'quantidade': qty,
      'precoUnitario': precoEfetivo,
      'precoUnitarioSnapshot': precoEfetivo,
      'tamanho': item['tamanho'] ?? item['size'] ?? '',
      'cor': item['cor'] ?? item['color'] ?? '',
      'imagem': item['imagemSnapshot'] ??
          item['imageUrl'] ??
          item['url_foto'] ??
          item['image'] ??
          '',
      'imagemSnapshot': item['imagemSnapshot'] ??
          item['imageUrl'] ??
          item['url_foto'] ??
          item['image'] ??
          '',
      'slug': item['slug'] ?? '',
      'total': itemTotal,
      'schemaVersion': item['schemaVersion'] ?? catalogCartItemSchemaVersion,
    };
    if (isPix) {
      storedItem['precoPixSnapshot'] = precoEfetivo;
    }
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
