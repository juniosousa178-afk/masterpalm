// lib/screens/public_catalog/checkout_total_helper.dart
// Total do checkout do catálogo público — mesma regra do carrinho (PIX por item, cupom, frete).

import 'catalog_estoque_helper.dart';

/// True quando a forma de pagamento é cartão (rótulo “Subtotal (cartão)” só nesse caso).
bool catalogCheckoutPagamentoEhCartao(String pagamento) {
  final p = pagamento.toUpperCase().trim();
  if (p.contains('CARTAO') || p.contains('CARTÃO') || p == 'CARD') return true;
  return false;
}

/// Rótulo da linha de subtotal “cheio” antes do desconto PIX por produto (breakdown no carrinho).
/// Altera apenas o texto exibido; os valores numéricos não mudam.
String catalogSubtotalBeforePixItemDiscountLabel(String pagamento) {
  final p = pagamento.toUpperCase().trim();
  if (p == 'PIX') return 'Subtotal';
  if (catalogCheckoutPagamentoEhCartao(pagamento)) return 'Subtotal (cartão)';
  return 'Subtotal';
}

/// Totais alinhados ao cálculo exibido em [CarrinhoSheetWeb].
class CatalogCheckoutTotals {
  const CatalogCheckoutTotals({
    required this.subtotalBruto,
    required this.subtotalPix,
    required this.subtotalConformePagamento,
    required this.descontoCupom,
    required this.valorFreteOriginal,
    required this.valorFreteFinal,
    required this.freteGratis,
    required this.total,
  });

  final double subtotalBruto;
  final double subtotalPix;
  final double subtotalConformePagamento;
  final double descontoCupom;
  final double valorFreteOriginal;
  final double valorFreteFinal;
  final bool freteGratis;
  final double total;
}

/// Frete grátis: roleta, cupom frete grátis, ou opção de frete marcada como grátis.
bool catalogFreteGratisEfetivo({
  required bool freteGratisRoleta,
  required Map<String, dynamic>? cupomAplicado,
  required List<Map<String, dynamic>> fretesParaCalculo,
  required int freteIndex,
}) {
  if (freteGratisRoleta) return true;
  if (cupomAplicado != null &&
      (cupomAplicado['tipo'] == 'frete_gratis' ||
          cupomAplicado['freteGratis'] == true)) {
    return true;
  }
  if (fretesParaCalculo.isNotEmpty) {
    final idx = freteIndex.clamp(0, fretesParaCalculo.length - 1);
    if (fretesParaCalculo[idx]['freteGratis'] == true) return true;
  }
  return false;
}

double _subtotalBruto(List<Map<String, dynamic>> items) {
  return items.fold<double>(0.0, (s, e) {
    final price = (e['preco'] as num?)?.toDouble() ?? 0.0;
    final qty = CatalogEstoqueHelper.parseCartItemQuantidade(e['quantidade']);
    return s + price * qty;
  });
}

double _subtotalPix(List<Map<String, dynamic>> items) {
  return items.fold<double>(0.0, (s, e) {
    final price = (e['preco'] as num?)?.toDouble() ?? 0.0;
    final qty = CatalogEstoqueHelper.parseCartItemQuantidade(e['quantidade']);
    final pctPix = (e['percentualDescontoPix'] as num?)?.toDouble() ?? 0.0;
    final precoEfetivo = pctPix > 0 ? price * (1 - pctPix / 100) : price;
    return s + precoEfetivo * qty;
  });
}

/// IDs de produto aos quais o cupom se aplica (lista vazia = qualquer item do pedido).
List<String> catalogCupomProdutoIds(Map<String, dynamic>? cupom) {
  if (cupom == null) return [];
  final a = cupom['produtoIds'];
  if (a is List) {
    return a.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
  }
  final single = cupom['produtoId'] ?? cupom['produto_id'];
  if (single != null && single.toString().trim().isNotEmpty) {
    return [single.toString().trim()];
  }
  return [];
}

String catalogItemIdProduto(Map<String, dynamic> e) {
  return (e['id'] ?? e['produtoId'] ?? e['produtosId'] ?? '').toString().trim();
}

/// True se o carrinho tem pelo menos uma linha cujo produto está na lista do cupom.
bool catalogCarrinhoCobreProdutosCupom({
  required Map<String, dynamic>? cupomAplicado,
  required List<Map<String, dynamic>> items,
}) {
  final ids = catalogCupomProdutoIds(cupomAplicado);
  if (ids.isEmpty) return true;
  for (final it in items) {
    final pid = catalogItemIdProduto(it);
    if (pid.isNotEmpty && ids.contains(pid)) return true;
  }
  return false;
}

double _descontoCupomProdutos({
  required Map<String, dynamic>? cupomAplicado,
  required double subtotalConformePagamento,
  required List<Map<String, dynamic>> items,
  required String pagamento,
  required List<Map<String, dynamic>> fretesParaCalculo,
  required int freteIndex,
  required bool freteGratis,
}) {
  if (cupomAplicado == null) return 0.0;

  final tipo = (cupomAplicado['tipo'] ?? '').toString();
  final valor = (cupomAplicado['valor'] as num?)?.toDouble() ?? 0.0;
  final aplicarEm = (cupomAplicado['aplicarEm'] ?? 'produtos').toString();
  final restritoIds = catalogCupomProdutoIds(cupomAplicado);

  double base;
  if (restritoIds.isNotEmpty) {
    final filtered = items.where((e) {
      final pid = catalogItemIdProduto(e);
      return pid.isNotEmpty && restritoIds.contains(pid);
    }).toList();
    if (filtered.isEmpty) return 0.0;
    final brutoF = _subtotalBruto(filtered);
    final subPixF = _subtotalPix(filtered);
    base = pagamento.toUpperCase() == 'PIX' ? subPixF : brutoF;
  } else if (aplicarEm == 'total') {
    if (fretesParaCalculo.isEmpty) {
      base = subtotalConformePagamento;
    } else {
      final frete = fretesParaCalculo[freteIndex.clamp(0, fretesParaCalculo.length - 1)];
      final double freteVal = (frete['valor'] as num?)?.toDouble() ?? 0.0;
      base = subtotalConformePagamento + (freteGratis ? 0.0 : freteVal);
    }
  } else {
    base = subtotalConformePagamento;
  }

  if (tipo == 'percent') {
    final d = base * (valor / 100);
    return d.clamp(0.0, base);
  }
  if (tipo == 'valor') {
    return valor.clamp(0.0, base);
  }
  return 0.0;
}

/// Replica a lógica de total do [CarrinhoSheetWeb] para uso no catálogo e pré-pedido.
CatalogCheckoutTotals computeCatalogCheckoutTotals({
  required List<Map<String, dynamic>> items,
  required String pagamento,
  required Map<String, dynamic>? cupomAplicado,
  required List<Map<String, dynamic>> fretesParaCalculo,
  required int freteIndex,
  required bool freteGratisRoleta,
}) {
  final bruto = _subtotalBruto(items);
  final subPix = _subtotalPix(items);
  final subConf =
      pagamento.toUpperCase() == 'PIX' ? subPix : bruto;

  final idx = fretesParaCalculo.isEmpty
      ? 0
      : freteIndex.clamp(0, fretesParaCalculo.length - 1);
  final valorFreteOriginal = fretesParaCalculo.isEmpty
      ? 0.0
      : ((fretesParaCalculo[idx]['valor'] as num?)?.toDouble() ?? 0.0);

  final fg = catalogFreteGratisEfetivo(
    freteGratisRoleta: freteGratisRoleta,
    cupomAplicado: cupomAplicado,
    fretesParaCalculo: fretesParaCalculo,
    freteIndex: freteIndex,
  );
  final valorFreteFinal = fg ? 0.0 : valorFreteOriginal;

  final desconto = _descontoCupomProdutos(
    cupomAplicado: cupomAplicado,
    subtotalConformePagamento: subConf,
    items: items,
    pagamento: pagamento,
    fretesParaCalculo: fretesParaCalculo,
    freteIndex: freteIndex,
    freteGratis: fg,
  );

  final total =
      ((subConf + valorFreteFinal) - desconto).clamp(0.0, double.infinity);

  return CatalogCheckoutTotals(
    subtotalBruto: bruto,
    subtotalPix: subPix,
    subtotalConformePagamento: subConf,
    descontoCupom: desconto,
    valorFreteOriginal: valorFreteOriginal,
    valorFreteFinal: valorFreteFinal,
    freteGratis: fg,
    total: total,
  );
}
