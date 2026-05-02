// lib/catalog/catalog_public_order_payment_status.dart
// Heurísticas de “pagamento aprovado” para o catálogo público (sem ler pré-pedido privado).

/// `pedido_status_publico` — espelho mínimo; após MP o [status] costuma ser `paid` (webhook).
bool catalogPedidoStatusPublicoIndicaPago(Map<String, dynamic> m) {
  final st = m['status']?.toString().trim().toLowerCase();
  if (st == 'paid' || st == 'pago' || st == 'aprovado') return true;
  final sp = m['statusPagamento']?.toString().trim().toLowerCase();
  if (sp == 'aprovado' || sp == 'pago') return true;
  if (m['paidAt'] != null) return true;
  final ps = m['paymentStatus']?.toString().trim().toLowerCase();
  if (ps == 'approved' || ps == 'aprovado' || ps == 'authorized') return true;
  return false;
}
