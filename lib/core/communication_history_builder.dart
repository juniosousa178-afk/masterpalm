// Extrai histórico de comunicação somente leitura do documento do pedido.
// Sem dados fictícios — só canais com evidência no mapa.

enum CommunicationChannel {
  whatsapp,
  email,
  mercadoPago,
  campanha,
  roleta,
  numeroSorte,
}

enum CommunicationStatus { enviado, pendente, falhou, reenviado, desconhecido }

class CommunicationHistoryItem {
  const CommunicationHistoryItem({
    required this.channel,
    required this.label,
    required this.status,
    this.at,
    this.detail,
    this.origem,
  });

  final CommunicationChannel channel;
  final String label;
  final CommunicationStatus status;
  final DateTime? at;
  final String? detail;
  final String? origem;
}

CommunicationStatus _statusFrom(dynamic raw) {
  final s = (raw ?? '').toString().trim().toLowerCase();
  if (s.isEmpty) return CommunicationStatus.desconhecido;
  if (s.contains('reenv')) return CommunicationStatus.reenviado;
  if (s.contains('fail') || s.contains('falh') || s.contains('erro')) {
    return CommunicationStatus.falhou;
  }
  if (s.contains('pend') || s.contains('aguard') || s == 'pending') {
    return CommunicationStatus.pendente;
  }
  if (s.contains('env') ||
      s.contains('ok') ||
      s.contains('sent') ||
      s.contains('aprov') ||
      s == 'paid' ||
      s == 'approved' ||
      s == 'true') {
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
  final origemDoc = (data['origem'] ?? data['source'] ?? '').toString().trim();

  void add(
    CommunicationChannel ch,
    String label,
    dynamic statusRaw, {
    dynamic at,
    String? detail,
    String? origem,
  }) {
    // Exige evidência: status, data ou detalhe concreto.
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
        origem: (origem ?? origemDoc).isEmpty ? null : (origem ?? origemDoc),
      ),
    );
  }

  final waFlag = data['whatsappEnviado'] ??
      data['waEnviado'] ??
      data['mensagemEnviadaWhatsApp'];
  final waAt = data['whatsappEnviadoEm'];
  if (waFlag != null || waAt != null) {
    add(
      CommunicationChannel.whatsapp,
      'WhatsApp',
      data['whatsappStatus'] ?? waFlag,
      at: waAt,
    );
  }

  final emailFlag = data['emailEnviado'] ?? data['mensagemEnviadaEmail'];
  final emailAt = data['emailEnviadoEm'];
  if (emailFlag != null || emailAt != null || data.containsKey('emailStatus')) {
    add(
      CommunicationChannel.email,
      'Email',
      data['emailStatus'] ?? emailFlag,
      at: emailAt,
    );
  }

  final mp = (data['statusPagamento'] ?? data['mpStatus'] ?? '').toString();
  final paymentId = (data['paymentId'] ?? '').toString().trim();
  if (mp.isNotEmpty || paymentId.isNotEmpty) {
    add(
      CommunicationChannel.mercadoPago,
      'Mercado Pago',
      mp.isNotEmpty ? mp : 'pendente',
      at: data['paidAt'] ?? data['paymentStartedAt'],
      detail: paymentId.isEmpty ? null : 'paymentId=$paymentId',
      origem: 'mercado_pago',
    );
  }

  if (data['campanhaAplicada'] == true ||
      data['campanhaAplicadaEm'] != null ||
      ((data['campanhaStatus'] ?? '').toString().trim().isNotEmpty)) {
    add(
      CommunicationChannel.campanha,
      'Campanha',
      data['campanhaStatus'] ??
          (data['campanhaAplicada'] == true ? 'enviado' : 'pendente'),
      at: data['campanhaAplicadaEm'],
      detail: (data['campanhaNome'] ?? '').toString().trim().isEmpty
          ? null
          : data['campanhaNome'].toString(),
      origem: 'campanha',
    );
  }

  if (data['premioRoleta'] != null) {
    final p = data['premioRoleta'];
    final detail = p is Map
        ? (p['descricao'] ?? p['tipo'] ?? '').toString()
        : p.toString();
    if (detail.trim().isNotEmpty || p is Map) {
      add(
        CommunicationChannel.roleta,
        'Roleta',
        data['roletaStatus'] ?? 'enviado',
        at: data['roletaEm'] ?? data['premioRoletaEm'],
        detail: detail.trim().isEmpty ? null : detail,
        origem: 'roleta',
      );
    }
  }

  final numero = (data['numeroSorte'] ?? data['numeroDaSorte'] ?? '').toString();
  if (numero.trim().isNotEmpty) {
    add(
      CommunicationChannel.numeroSorte,
      'Número da sorte',
      data['numeroSorteStatus'] ?? 'enviado',
      at: data['numeroSorteEm'] ?? data['campanhaAplicadaEm'],
      detail: numero.trim(),
      origem: 'campanha',
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
                      : canal.contains('sorte') || canal.contains('numero')
                          ? CommunicationChannel.numeroSorte
                          : CommunicationChannel.roleta;
      items.add(
        CommunicationHistoryItem(
          channel: ch,
          label: (e['label'] ?? canal).toString(),
          status: _statusFrom(e['status']),
          at: _asDate(e['at'] ?? e['data'] ?? e['hora']),
          detail: (e['detail'] ?? e['detalhe'])?.toString(),
          origem: (e['origem'] ?? e['source'])?.toString(),
        ),
      );
    }
  }

  return items;
}
