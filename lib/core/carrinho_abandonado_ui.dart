// Status canônicos M3.8 (UI) — mapeia status legado do catálogo.
// Não altera engines de checkout/venda.

const String kCarrinhoUiAbandonado = 'abandonado';
const String kCarrinhoUiRecuperado = 'recuperado';
const String kCarrinhoUiVirouPedido = 'virou_pedido';
const String kCarrinhoUiVirouVenda = 'virou_venda';

String normalizarStatusCarrinhoAbandonado(String raw) {
  final s = raw.trim().toLowerCase();
  if (s.isEmpty || s == 'ativo') return kCarrinhoUiAbandonado;
  if (s == 'recuperado' || s == 'recovered') return kCarrinhoUiRecuperado;
  if (s.contains('pedido') || s == 'virou_pedido') return kCarrinhoUiVirouPedido;
  if (s.contains('venda') || s == 'virou_venda') return kCarrinhoUiVirouVenda;
  if (s == 'abandonado' || s == 'abandoned') return kCarrinhoUiAbandonado;
  return s;
}

String labelStatusCarrinhoAbandonado(String raw) {
  switch (normalizarStatusCarrinhoAbandonado(raw)) {
    case kCarrinhoUiRecuperado:
      return 'Recuperado';
    case kCarrinhoUiVirouPedido:
      return 'Virou Pedido';
    case kCarrinhoUiVirouVenda:
      return 'Virou Venda';
    default:
      return 'Abandonado';
  }
}

double totalCarrinhoProdutos(List<Map<String, dynamic>> produtos) {
  double t = 0;
  for (final p in produtos) {
    final q = (p['quantidade'] as num?)?.toDouble() ?? 1;
    final preco = (p['preco'] as num?)?.toDouble() ??
        (p['precoUnitario'] as num?)?.toDouble() ??
        (p['price'] as num?)?.toDouble() ??
        0;
    final line = (p['total'] as num?)?.toDouble();
    t += line ?? (preco * q);
  }
  return t;
}

String formatarTempoAbandonado(Duration d) {
  if (d.inDays >= 1) return '${d.inDays}d ${d.inHours % 24}h';
  if (d.inHours >= 1) return '${d.inHours}h ${d.inMinutes % 60}min';
  return '${d.inMinutes}min';
}
