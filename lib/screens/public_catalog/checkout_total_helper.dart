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

/// Cupom que só pode alterar frete (grátis ou desconto sobre o valor do frete), nunca subtotal de produtos.
bool catalogCupomSomenteFrete(Map<String, dynamic>? c) {
  if (c == null) return false;
  final t = (c['tipo'] ?? '').toString();
  if (t == 'frete_gratis') return true;
  if (c['freteGratis'] == true) return true;
  final ae = (c['aplicarEm'] ?? '').toString().toLowerCase().trim();
  if (ae == 'frete') return true;
  return false;
}

/// Totais alinhados ao cálculo exibido em [CarrinhoSheetWeb].
class CatalogCheckoutTotals {
  const CatalogCheckoutTotals({
    required this.subtotalBruto,
    required this.subtotalPix,
    required this.subtotalConformePagamento,
    required this.descontoCupomProdutos,
    required this.descontoCupomFrete,
    required this.valorFreteOriginal,
    required this.valorFreteFinal,
    required this.freteGratis,
    required this.total,
  });

  final double subtotalBruto;
  final double subtotalPix;
  final double subtotalConformePagamento;

  /// Desconto de cupom sobre produtos / total (nunca sobre frete).
  final double descontoCupomProdutos;

  /// Desconto de cupom aplicado só sobre o frete (ex.: % ou R$ no frete).
  final double descontoCupomFrete;

  final double valorFreteOriginal;
  final double valorFreteFinal;
  final bool freteGratis;
  final double total;

  /// Compat: soma dos descontos de cupom (admin / pedidos legados).
  double get descontoCupom => descontoCupomProdutos + descontoCupomFrete;
}

/// Frete grátis: roleta, cupom de frete, ou opção de frete marcada como grátis.
bool catalogFreteGratisEfetivo({
  required bool freteGratisRoleta,
  required Map<String, dynamic>? cupomDescontoAplicado,
  required Map<String, dynamic>? cupomFreteAplicado,
  required List<Map<String, dynamic>> fretesParaCalculo,
  required int freteIndex,
}) {
  if (freteGratisRoleta) return true;
  for (final c in [cupomFreteAplicado, cupomDescontoAplicado]) {
    if (c == null) continue;
    if (c['tipo'] == 'frete_gratis' || c['freteGratis'] == true) {
      return true;
    }
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

double _descontoCupomSobreProdutosOuTotal({
  required Map<String, dynamic>? cupom,
  required double subtotalConformePagamento,
  required List<Map<String, dynamic>> items,
  required String pagamento,
  required List<Map<String, dynamic>> fretesParaCalculo,
  required int freteIndex,
  required bool freteGratis,
}) {
  if (cupom == null) return 0.0;
  if (catalogCupomSomenteFrete(cupom)) return 0.0;

  final tipo = (cupom['tipo'] ?? '').toString();
  final valor = (cupom['valor'] as num?)?.toDouble() ?? 0.0;
  final aplicarEm = (cupom['aplicarEm'] ?? 'produtos').toString();
  final restritoIds = catalogCupomProdutoIds(cupom);

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

  if (tipo == 'percent' || tipo == 'percentual') {
    final d = base * (valor / 100);
    return d.clamp(0.0, base);
  }
  if (tipo == 'valor' || tipo == 'fixo') {
    return valor.clamp(0.0, base);
  }
  return 0.0;
}

double _descontoCupomSobreFrete({
  required Map<String, dynamic>? cupomFrete,
  required double valorFreteOriginal,
  required bool freteGratis,
}) {
  if (cupomFrete == null || freteGratis || valorFreteOriginal <= 0) {
    return 0.0;
  }
  final ae = (cupomFrete['aplicarEm'] ?? '').toString().toLowerCase().trim();
  if (ae != 'frete') return 0.0;

  final tipo = (cupomFrete['tipo'] ?? '').toString();
  final valor = (cupomFrete['valor'] as num?)?.toDouble() ?? 0.0;
  if (valor <= 0) return 0.0;

  if (tipo == 'percent' || tipo == 'percentual') {
    return (valorFreteOriginal * valor / 100).clamp(0.0, valorFreteOriginal);
  }
  if (tipo == 'valor' || tipo == 'fixo') {
    return valor.clamp(0.0, valorFreteOriginal);
  }
  return 0.0;
}

/// Replica a lógica de total do [CarrinhoSheetWeb] para uso no catálogo e pré-pedido.
///
/// [cupomDescontoAplicado] — desconto em produtos / total (nunca frete-only).
/// [cupomFreteAplicado] — frete grátis, ou [aplicarEm] == frete com %/fixo.
CatalogCheckoutTotals computeCatalogCheckoutTotals({
  required List<Map<String, dynamic>> items,
  required String pagamento,
  Map<String, dynamic>? cupomDescontoAplicado,
  Map<String, dynamic>? cupomFreteAplicado,
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
    cupomDescontoAplicado: cupomDescontoAplicado,
    cupomFreteAplicado: cupomFreteAplicado,
    fretesParaCalculo: fretesParaCalculo,
    freteIndex: freteIndex,
  );

  final descontoFreteCalc = _descontoCupomSobreFrete(
    cupomFrete: cupomFreteAplicado,
    valorFreteOriginal: valorFreteOriginal,
    freteGratis: fg,
  );

  final valorFreteFinal = fg
      ? 0.0
      : (valorFreteOriginal - descontoFreteCalc).clamp(0.0, double.infinity);

  final descontoProd = _descontoCupomSobreProdutosOuTotal(
    cupom: cupomDescontoAplicado,
    subtotalConformePagamento: subConf,
    items: items,
    pagamento: pagamento,
    fretesParaCalculo: fretesParaCalculo,
    freteIndex: freteIndex,
    freteGratis: fg,
  );

  final total =
      ((subConf + valorFreteFinal) - descontoProd).clamp(0.0, double.infinity);

  return CatalogCheckoutTotals(
    subtotalBruto: bruto,
    subtotalPix: subPix,
    subtotalConformePagamento: subConf,
    descontoCupomProdutos: descontoProd,
    descontoCupomFrete: descontoFreteCalc,
    valorFreteOriginal: valorFreteOriginal,
    valorFreteFinal: valorFreteFinal,
    freteGratis: fg,
    total: total,
  );
}
