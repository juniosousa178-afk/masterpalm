/// Snapshot da cotação de frete escolhida no checkout do catálogo.
///
/// Gravado no pedido em `frete.cotacao` e lido pelo backend
/// (`functions/src/shippingExport.js` → `readQuoteSnapshot`) para exportar o
/// envio ao provedor depois do pagamento aprovado / confirmação do lojista.
/// Escolher uma opção de frete nunca chama o provedor.
library;

const Set<String> kShippingQuoteProviders = {'melhor_envio', 'superfrete'};

/// Pacote usado na cotação (mesmos valores enviados a `FreteService.calcularFrete`).
Map<String, dynamic> buildShippingQuotePackage({
  required num pesoGramas,
  required num alturaCm,
  required num larguraCm,
  required num comprimentoCm,
}) {
  return {
    'pesoGramas': pesoGramas,
    'alturaCm': alturaCm,
    'larguraCm': larguraCm,
    'comprimentoCm': comprimentoCm,
  };
}

int? _asPositiveInt(dynamic raw) {
  if (raw is num) {
    final v = raw.toInt();
    return v > 0 ? v : null;
  }
  if (raw is String) {
    final match = RegExp(r'\d+').firstMatch(raw);
    if (match == null) return null;
    final v = int.tryParse(match.group(0)!);
    return v != null && v > 0 ? v : null;
  }
  return null;
}

double? _asPositiveDouble(dynamic raw) {
  double? v;
  if (raw is num) v = raw.toDouble();
  if (raw is String) v = double.tryParse(raw.replaceAll(',', '.'));
  if (v == null || !v.isFinite || v <= 0) return null;
  return v;
}

String? _asText(dynamic raw, {int maxLength = 80}) {
  if (raw == null) return null;
  final s = raw.toString().trim();
  if (s.isEmpty) return null;
  return s.length > maxLength ? s.substring(0, maxLength) : s;
}

Map<String, dynamic>? _sanitizePackage(dynamic raw) {
  if (raw is! Map) return null;
  final peso = _asPositiveDouble(raw['pesoGramas']);
  final altura = _asPositiveDouble(raw['alturaCm']);
  final largura = _asPositiveDouble(raw['larguraCm']);
  final comprimento = _asPositiveDouble(raw['comprimentoCm']);
  if (peso == null || altura == null || largura == null || comprimento == null) {
    return null;
  }
  return buildShippingQuotePackage(
    pesoGramas: peso,
    alturaCm: altura,
    larguraCm: largura,
    comprimentoCm: comprimento,
  );
}

/// Monta o snapshot a partir da opção de frete selecionada no carrinho.
/// Retorna `null` para fretes manuais/retirada ou quando falta pacote/serviço.
Map<String, dynamic>? buildShippingQuoteSnapshot({
  required Map<String, dynamic> freteSelecionado,
  required Map<String, dynamic>? pacote,
}) {
  final provider = _asText(freteSelecionado['plataforma']);
  if (provider == null || !kShippingQuoteProviders.contains(provider)) {
    return null;
  }
  return sanitizeShippingQuoteSnapshot({
    'provider': provider,
    'serviceId': provider == 'superfrete'
        ? (freteSelecionado['servico_id'] ?? freteSelecionado['service_id'])
        : (freteSelecionado['service_id'] ?? freteSelecionado['servico_id']),
    'serviceName': freteSelecionado['nome'] ?? freteSelecionado['label'],
    'carrierName': freteSelecionado['empresa'],
    'companyId': freteSelecionado['company_id'],
    'quoteId': freteSelecionado['quote_id'],
    'quotedPrice': freteSelecionado['valor'],
    'quotedDeadlineDays':
        freteSelecionado['prazo_dias'] ?? freteSelecionado['prazo'],
    'pacote': pacote,
  });
}

/// Normaliza um snapshot vindo do cliente antes de gravar no pedido.
/// Só mantém chaves conhecidas; descarta o snapshot inteiro se incompleto.
Map<String, dynamic>? sanitizeShippingQuoteSnapshot(dynamic raw) {
  if (raw is! Map) return null;
  final provider = _asText(raw['provider']);
  if (provider == null || !kShippingQuoteProviders.contains(provider)) {
    return null;
  }
  final serviceId = _asPositiveInt(raw['serviceId']);
  final quotedPrice = _asPositiveDouble(raw['quotedPrice']);
  final pacote = _sanitizePackage(raw['pacote']);
  if (serviceId == null || quotedPrice == null || pacote == null) return null;

  final serviceName = _asText(raw['serviceName']);
  final carrierName = _asText(raw['carrierName']);
  final companyId = _asPositiveInt(raw['companyId']);
  final quoteId = _asText(raw['quoteId']);
  final deadline = _asPositiveInt(raw['quotedDeadlineDays']);

  return {
    'provider': provider,
    'serviceId': serviceId,
    if (serviceName != null) 'serviceName': serviceName,
    if (carrierName != null) 'carrierName': carrierName,
    if (companyId != null) 'companyId': companyId,
    if (quoteId != null) 'quoteId': quoteId,
    'quotedPrice': quotedPrice,
    if (deadline != null) 'quotedDeadlineDays': deadline,
    'pacote': pacote,
  };
}

/// Mapa `entrega` enviado pelos três fluxos de checkout do carrinho.
Map<String, dynamic> buildCatalogCheckoutEntrega({
  required Map<String, dynamic> freteSelecionado,
  required String nome,
  required double valorFinal,
  required bool freteGratis,
  required Map<String, dynamic>? pacoteCotacao,
}) {
  final cotacao = buildShippingQuoteSnapshot(
    freteSelecionado: freteSelecionado,
    pacote: pacoteCotacao,
  );
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
    if (cotacao != null) 'cotacao': cotacao,
  };
}
