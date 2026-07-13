// Constrói timeline somente leitura a partir do mapa do pré-pedido / pedido.
// Fail-closed: só marca eventos com evidência real no documento.

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

bool _statusPago(String statusPag) {
  return statusPag.contains('aprov') ||
      statusPag == 'paid' ||
      statusPag == 'approved' ||
      statusPag == 'pago';
}

/// Extrai eventos conhecidos do documento sem mutar engines.
/// Eventos sem evidência ficam com [PedidoTimelineEvent.occurred] = false.
List<PedidoTimelineEvent> buildPedidoTimeline(Map<String, dynamic> data) {
  final created = _asDate(
    data['createdAt'] ?? data['criadoEm'] ?? data['data'] ?? data['created_at'],
  );
  final checkout = _asDate(data['checkoutAt'] ?? data['checkoutEm']);
  final payStart =
      _asDate(data['paymentStartedAt'] ?? data['pagamentoIniciadoEm']);
  final paid = _asDate(data['paidAt'] ?? data['pagoEm']);
  final venda = _asDate(data['vendaCriadaEm'] ?? data['confirmedAt']);
  final estoque = _asDate(data['estoqueBaixadoEm'] ?? data['stockAppliedAt']);
  final campanha = _asDate(data['campanhaAplicadaEm']);
  final numero = (data['numeroSorte'] ?? data['numeroDaSorte'] ?? '').toString();
  final wa = _truthy(
        data['whatsappEnviado'] ??
            data['waEnviado'] ??
            data['mensagemEnviadaWhatsApp'],
      ) ||
      _asDate(data['whatsappEnviadoEm']) != null;
  final email = _truthy(data['emailEnviado'] ?? data['mensagemEnviadaEmail']) ||
      _asDate(data['emailEnviadoEm']) != null;
  final statusPag = (data['statusPagamento'] ?? '').toString().toLowerCase();
  final paymentId = (data['paymentId'] ?? '').toString().trim();
  final statusPedido = (data['status'] ?? '').toString().toLowerCase();

  final pago = paid != null || _statusPago(statusPag);
  final temVenda = venda != null ||
      _truthy(data['vendaRegistrada']) ||
      (data['vendaId'] ?? data['vendaKey'] ?? '').toString().trim().isNotEmpty;
  final temEstoque = estoque != null ||
      _truthy(data['estoqueBaixado']) ||
      (data['stockStatus'] ?? '').toString().toLowerCase() == 'applied';
  final temCampanha = campanha != null || _truthy(data['campanhaAplicada']);
  final temNumero = numero.trim().isNotEmpty;
  final premio = data['premioRoleta'];
  final temPremio = premio != null &&
      (premio is! Map ||
          premio.values.any((v) => v != null && v.toString().trim().isNotEmpty));

  final temCheckout = checkout != null ||
      statusPedido == 'confirmado' ||
      statusPedido == 'pago' ||
      statusPedido.contains('checkout') ||
      (data['frete'] is Map &&
          (data['cliente'] is Map) &&
          (data['itens'] is List && (data['itens'] as List).isNotEmpty));

  final pagamentoIniciado =
      payStart != null || paymentId.isNotEmpty || pago;

  // Pedido criado: precisa de timestamp ou id explícito — não "data.isNotEmpty".
  final temCriado = created != null ||
      (data['id'] ?? data['prePedidoId'] ?? data['pedidoId'] ?? '')
          .toString()
          .trim()
          .isNotEmpty;

  return [
    PedidoTimelineEvent(
      id: 'criado',
      label: 'Pedido criado',
      occurred: temCriado,
      at: created,
    ),
    PedidoTimelineEvent(
      id: 'checkout',
      label: 'Checkout',
      occurred: temCheckout,
      at: checkout ?? created,
    ),
    PedidoTimelineEvent(
      id: 'pay_start',
      label: 'Pagamento iniciado',
      occurred: pagamentoIniciado || pago,
      at: payStart,
      detail: paymentId.isEmpty ? null : 'paymentId=$paymentId',
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
      label: 'Roleta',
      occurred: temPremio,
      detail: premio is Map
          ? (premio['descricao'] ?? premio['tipo'] ?? '').toString()
          : premio?.toString(),
    ),
    PedidoTimelineEvent(
      id: 'whatsapp',
      label: 'WhatsApp enviado',
      occurred: wa,
      at: _asDate(data['whatsappEnviadoEm']),
    ),
    PedidoTimelineEvent(
      id: 'email',
      label: 'Email enviado',
      occurred: email,
      at: _asDate(data['emailEnviadoEm']),
    ),
  ];
}

/// Apenas eventos que realmente ocorreram (UI fail-closed).
List<PedidoTimelineEvent> buildPedidoTimelineOcorridos(Map<String, dynamic> data) {
  return buildPedidoTimeline(data).where((e) => e.occurred).toList();
}
