// Constrói timeline somente leitura a partir do mapa do pré-pedido / pedido.

class PedidoTimelineEvent {
  const PedidoTimelineEvent({
    required this.id,
    required this.label,
    required this.occurred,
    this.at,
    this.detail,
  });

  final String id;
  final String label;
  final bool occurred;
  final DateTime? at;
  final String? detail;
}

DateTime? _asDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  try {
    // Firestore Timestamp
    return (v as dynamic).toDate() as DateTime;
  } catch (_) {}
  if (v is String) return DateTime.tryParse(v);
  if (v is int) {
    if (v > 1000000000000) {
      return DateTime.fromMillisecondsSinceEpoch(v);
    }
    return DateTime.fromMillisecondsSinceEpoch(v * 1000);
  }
  return null;
}

bool _truthy(dynamic v) {
  if (v == true) return true;
  if (v is String) {
    final s = v.trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'sim' || s == 'enviado';
  }
  return false;
}

/// Extrai eventos conhecidos do documento sem mutar engines.
List<PedidoTimelineEvent> buildPedidoTimeline(Map<String, dynamic> data) {
  final created = _asDate(data['createdAt'] ?? data['criadoEm'] ?? data['data']);
  final checkout = _asDate(data['checkoutAt'] ?? data['checkoutEm']);
  final payStart = _asDate(data['paymentStartedAt'] ?? data['pagamentoIniciadoEm']);
  final paid = _asDate(data['paidAt'] ?? data['pagoEm']);
  final venda = _asDate(data['vendaCriadaEm'] ?? data['confirmedAt']);
  final estoque = _asDate(data['estoqueBaixadoEm'] ?? data['stockAppliedAt']);
  final campanha = _asDate(data['campanhaAplicadaEm']);
  final numero = (data['numeroSorte'] ?? data['numeroDaSorte'] ?? '').toString();
  final wa = _truthy(data['whatsappEnviado'] ?? data['waEnviado']);
  final email = _truthy(data['emailEnviado']);
  final statusPag = (data['statusPagamento'] ?? '').toString().toLowerCase();
  final pago = paid != null ||
      statusPag.contains('aprov') ||
      statusPag == 'paid' ||
      statusPag == 'approved';
  final temVenda = venda != null ||
      (data['vendaId'] ?? data['vendaKey'] ?? '').toString().isNotEmpty;
  final temEstoque = estoque != null ||
      _truthy(data['estoqueBaixado']) ||
      (data['stockStatus'] ?? '').toString().toLowerCase() == 'applied';
  final temCampanha = campanha != null ||
      _truthy(data['campanhaAplicada']) ||
      (data['campanhaId'] ?? '').toString().isNotEmpty;
  final temNumero = numero.trim().isNotEmpty;
  final carrinho = _asDate(data['carrinhoIniciadoEm']) ?? created;
  final premio = data['premioRoleta'];

  return [
    PedidoTimelineEvent(
      id: 'criado',
      label: 'Pedido criado',
      occurred: created != null || data.isNotEmpty,
      at: created,
    ),
    PedidoTimelineEvent(
      id: 'carrinho',
      label: 'Carrinho iniciado',
      occurred: carrinho != null,
      at: carrinho,
    ),
    PedidoTimelineEvent(
      id: 'checkout',
      label: 'Checkout',
      occurred: checkout != null || data['entrega'] != null || data['pagamento'] != null,
      at: checkout ?? created,
    ),
    PedidoTimelineEvent(
      id: 'pay_start',
      label: 'Pagamento iniciado',
      occurred: payStart != null ||
          (data['paymentId'] ?? '').toString().isNotEmpty ||
          statusPag.isNotEmpty,
      at: payStart,
    ),
    PedidoTimelineEvent(
      id: 'pay_ok',
      label: 'Pagamento aprovado',
      occurred: pago,
      at: paid,
    ),
    PedidoTimelineEvent(
      id: 'venda',
      label: 'Venda criada',
      occurred: temVenda,
      at: venda,
    ),
    PedidoTimelineEvent(
      id: 'estoque',
      label: 'Estoque baixado',
      occurred: temEstoque,
      at: estoque,
    ),
    PedidoTimelineEvent(
      id: 'campanha',
      label: 'Campanha aplicada',
      occurred: temCampanha,
      at: campanha,
      detail: (data['campanhaNome'] ?? '').toString().trim().isEmpty
          ? null
          : data['campanhaNome'].toString(),
    ),
    PedidoTimelineEvent(
      id: 'numero',
      label: 'Número da sorte',
      occurred: temNumero,
      detail: temNumero ? numero : null,
    ),
    PedidoTimelineEvent(
      id: 'roleta',
      label: 'Roleta / prêmio',
      occurred: premio != null,
      detail: premio is Map
          ? (premio['descricao'] ?? premio['tipo'] ?? '').toString()
          : premio?.toString(),
    ),
    PedidoTimelineEvent(
      id: 'whatsapp',
      label: 'WhatsApp enviado',
      occurred: wa,
    ),
    PedidoTimelineEvent(
      id: 'email',
      label: 'Email enviado',
      occurred: email,
    ),
  ];
}
