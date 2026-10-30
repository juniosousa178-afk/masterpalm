/// Referência da cotação de frete escolhida no checkout do catálogo.
///
/// A cotação (Melhor Envio / SuperFrete) é feita no servidor a partir dos itens
/// do carrinho; cada opção volta com um `shippingQuoteId` opaco. O pedido grava
/// só esse ID em `frete.shippingQuoteId`: preço, prazo, serviço e pacote usados
/// no pagamento e na exportação vêm do recibo do servidor
/// (`functions/src/shippingQuoteReceipt.js`), nunca do navegador.
/// Escolher uma opção de frete nunca chama o provedor.
library;

import 'catalog_cart_item_snapshot.dart';

const Set<String> kShippingQuoteProviders = {'melhor_envio', 'superfrete'};

final RegExp _quoteIdPattern = RegExp(r'^[a-f0-9]{32}\.\d{1,2}$');

int _quantidade(dynamic raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse('$raw') ?? 1;
}

/// Itens enviados à cotação (`[{productId, quantidade}]`), um por linha do carrinho.
List<Map<String, dynamic>> buildShippingQuoteItems(
  List<Map<String, dynamic>> cartItems,
) {
  return [
    for (final item in cartItems)
      if (catalogCartLineCanonicalProductId(item).isNotEmpty)
        {
          'productId': catalogCartLineCanonicalProductId(item),
          'quantidade': _quantidade(item['quantidade'] ?? item['qty']),
        },
  ];
}

/// Assinatura estável do conteúdo do carrinho (produto × quantidade agregada).
String shippingQuoteItemsSignature(List<Map<String, dynamic>> cartItems) {
  final agg = <String, int>{};
  for (final it in buildShippingQuoteItems(cartItems)) {
    final id = it['productId'] as String;
    agg[id] = (agg[id] ?? 0) + (it['quantidade'] as int);
  }
  final keys = agg.keys.toList()..sort();
  return keys.map((k) => '$k:${agg[k]}').join('|');
}

/// ID emitido pelo servidor; qualquer outro formato é descartado.
String? sanitizeShippingQuoteId(dynamic raw) {
  if (raw == null) return null;
  final s = raw.toString().trim();
  return _quoteIdPattern.hasMatch(s) ? s : null;
}

bool isShippingQuoteProvider(dynamic plataforma) =>
    kShippingQuoteProviders.contains((plataforma ?? '').toString());

/// Mapa `entrega` enviado pelos três fluxos de checkout do carrinho.
Map<String, dynamic> buildCatalogCheckoutEntrega({
  required Map<String, dynamic> freteSelecionado,
  required String nome,
  required double valorFinal,
  required bool freteGratis,
}) {
  final quoteId = isShippingQuoteProvider(freteSelecionado['plataforma'])
      ? sanitizeShippingQuoteId(freteSelecionado['shipping_quote_id'])
      : null;
  return {
    'nome': nome,
    'valor': valorFinal,
    'freteGratis': freteGratis,
    'tipo': freteSelecionado['tipo'] ?? 'padrao',
    if (freteSelecionado['plataforma'] != null)
      'plataforma': freteSelecionado['plataforma'],
    if (freteSelecionado['service_id'] != null)
      'service_id': freteSelecionado['service_id'],
    if (freteSelecionado['servico_id'] != null)
      'servico_id': freteSelecionado['servico_id'],
    if (quoteId != null) 'shippingQuoteId': quoteId,
  };
}
