// Extrai histórico de comunicação somente leitura do documento do pedido.

enum CommunicationChannel { whatsapp, email, mercadoPago, campanha, roleta }

enum CommunicationStatus { enviado, pendente, falhou, reenviado, desconhecido }

class CommunicationHistoryItem {
  const CommunicationHistoryItem({
    required this.channel,
    required this.label,
    required this.status,
    this.at,
    this.detail,
  });

  final CommunicationChannel channel;
  final String label;
  final CommunicationStatus status;
  final DateTime? at;
  final String? detail;
}

CommunicationStatus _statusFrom(dynamic raw) {
  final s = (raw ?? '').toString().trim().toLowerCase();
  if (s.isEmpty) return CommunicationStatus.desconhecido;
  if (s.contains('reenv')) return CommunicationStatus.reenviado;
  if (s.contains('fail') || s.contains('falh') || s.contains('erro')) {
    return CommunicationStatus.falhou;
  }
  if (s.contains('pend')) return CommunicationStatus.pendente;
  if (s.contains('env') || s.contains('ok') || s.contains('sent') || s == 'true') {
    return CommunicationStatus.enviado;
  }
  return CommunicationStatus.desconhecido;
}

DateTime? _asDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  try {
    return (v as dynamic).toDate() as DateTime;
  } catch (_) {}
  if (v is String) return DateTime.tryParse(v);
  return null;
}

List<CommunicationHistoryItem> buildCommunicationHistory(
  Map<String, dynamic> data,
) {
  final items = <CommunicationHistoryItem>[];

  void add(
    CommunicationChannel ch,
    String label,
    dynamic statusRaw, {
    dynamic at,
    String? detail,
  }) {
    if (statusRaw == null && detail == null && at == null) return;
    items.add(
      CommunicationHistoryItem(
        channel: ch,
        label: label,
        status: statusRaw == true
            ? CommunicationStatus.enviado
            : statusRaw == false
                ? CommunicationStatus.falhou
                : _statusFrom(statusRaw),
        at: _asDate(at),
        detail: detail,
      ),
    );
  }

  if (data.containsKey('whatsappEnviado') ||
      data.containsKey('waEnviado') ||
      data.containsKey('whatsappStatus')) {
    add(
      CommunicationChannel.whatsapp,
      'WhatsApp',
      data['whatsappStatus'] ?? data['whatsappEnviado'] ?? data['waEnviado'],
      at: data['whatsappEnviadoEm'],
    );
  }

  if (data.containsKey('emailEnviado') || data.containsKey('emailStatus')) {
    add(
      CommunicationChannel.email,
      'Email',
      data['emailStatus'] ?? data['emailEnviado'],
      at: data['emailEnviadoEm'],
    );
  }

  final mp = (data['statusPagamento'] ?? data['mpStatus'] ?? '').toString();
  if (mp.isNotEmpty || (data['paymentId'] ?? '').toString().isNotEmpty) {
    add(
      CommunicationChannel.mercadoPago,
      'Mercado Pago',
      mp.isNotEmpty ? mp : 'pendente',
      at: data['paidAt'],
      detail: (data['paymentId'] ?? '').toString().isEmpty
          ? null
          : 'paymentId=${data['paymentId']}',
    );
  }

  if ((data['campanhaId'] ?? data['campanhaNome'] ?? '').toString().isNotEmpty ||
      data['campanhaAplicada'] == true) {
    add(
      CommunicationChannel.campanha,
      'Campanha',
      data['campanhaStatus'] ??
          (data['campanhaAplicada'] == true ? 'enviado' : 'pendente'),
      at: data['campanhaAplicadaEm'],
      detail: (data['campanhaNome'] ?? data['numeroSorte'] ?? '').toString(),
    );
  }

  if (data['premioRoleta'] != null) {
    final p = data['premioRoleta'];
    add(
      CommunicationChannel.roleta,
      'Roleta',
      data['roletaStatus'] ?? 'enviado',
      detail: p is Map
          ? (p['descricao'] ?? p['tipo'] ?? '').toString()
          : p.toString(),
    );
  }

  final hist = data['comunicacoes'];
  if (hist is List) {
    for (final e in hist) {
      if (e is! Map) continue;
      final canal = (e['canal'] ?? e['channel'] ?? '').toString().toLowerCase();
      final ch = canal.contains('whats')
          ? CommunicationChannel.whatsapp
          : canal.contains('mail')
              ? CommunicationChannel.email
              : canal.contains('mp') || canal.contains('mercado')
                  ? CommunicationChannel.mercadoPago
                  : canal.contains('camp')
                      ? CommunicationChannel.campanha
                      : CommunicationChannel.roleta;
      items.add(
        CommunicationHistoryItem(
          channel: ch,
          label: (e['label'] ?? canal).toString(),
          status: _statusFrom(e['status']),
          at: _asDate(e['at'] ?? e['data']),
          detail: (e['detail'] ?? e['detalhe'])?.toString(),
        ),
      );
    }
  }

  return items;
}
