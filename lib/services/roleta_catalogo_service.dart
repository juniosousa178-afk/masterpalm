import 'dart:math' as math;

import 'package:cloud_functions/cloud_functions.dart';

class RoletaCatalogoSpinResult {
  const RoletaCatalogoSpinResult({
    required this.ok,
    required this.status,
    this.message,
    this.ganhou = false,
    this.premioIndex,
    this.premio,
    this.premios = const [],
    this.totalVendas,
    this.vendasDesdePremio,
    this.codigoCupomTemporario,
  });

  final bool ok;
  final String status;
  final String? message;
  final bool ganhou;
  final int? premioIndex;
  final Map<String, dynamic>? premio;
  final List<Map<String, dynamic>> premios;
  final int? totalVendas;
  final int? vendasDesdePremio;
  final String? codigoCupomTemporario;

  factory RoletaCatalogoSpinResult.fromData(dynamic raw) {
    final data = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final premiosRaw = data['premios'] as List?;

    return RoletaCatalogoSpinResult(
      ok: data['ok'] == true,
      status: data['status']?.toString() ?? 'invalid_response',
      message: data['message']?.toString(),
      ganhou: data['ganhou'] == true,
      premioIndex: (data['premioIndex'] as num?)?.toInt(),
      premio: data['premio'] is Map
          ? Map<String, dynamic>.from(data['premio'] as Map)
          : null,
      premios: premiosRaw == null
          ? const []
          : premiosRaw
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(),
      totalVendas: (data['totalVendas'] as num?)?.toInt(),
      vendasDesdePremio: (data['vendasDesdePremio'] as num?)?.toInt(),
      codigoCupomTemporario: data['codigoCupomTemporario']?.toString(),
    );
  }
}

class RoletaCatalogoService {
  RoletaCatalogoService._();

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'southamerica-east1');

  static Future<RoletaCatalogoSpinResult> girarRoleta({
    required String lojaId,
    required double totalCarrinho,
    String? spinRequestId,
  }) async {
    final callable = _functions.httpsCallable('girarRoletaCatalogo');
    final result = await callable.call(<String, dynamic>{
      'lojaId': lojaId.trim(),
      'totalCarrinho': totalCarrinho,
      if (spinRequestId != null && spinRequestId.trim().isNotEmpty)
        'spinRequestId': spinRequestId.trim(),
    });
    return RoletaCatalogoSpinResult.fromData(result.data);
  }

  static String messageFromFunctionsException(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'invalid-argument':
        return e.message ?? 'Dados inválidos para girar a roleta.';
      case 'failed-precondition':
        return e.message ?? 'A roleta não está disponível no momento.';
      case 'resource-exhausted':
        return 'Muitas tentativas seguidas. Aguarde um pouco e tente novamente.';
      case 'permission-denied':
        return 'A roleta não pôde ser validada no momento.';
      default:
        return e.message ?? 'Não foi possível girar a roleta. Tente novamente.';
    }
  }
}

String? _normalizedPremioId(Map<String, dynamic>? premio) {
  final raw = premio?['id']?.toString().trim();
  if (raw == null || raw.isEmpty) return null;
  return raw;
}

String _normalizedPremioLabel(Map<String, dynamic>? premio) {
  return premio?['label']?.toString().trim() ?? '';
}

String _normalizedPremioTipo(Map<String, dynamic>? premio) {
  final tipo = premio?['tipo']?.toString().trim().toLowerCase() ?? '';
  if (tipo == 'desconto_percentual') return 'desconto';
  return tipo;
}

double _normalizedPremioValor(Map<String, dynamic>? premio) {
  final raw = premio?['valor'];
  if (raw is num) return raw.toDouble();
  return double.tryParse(raw?.toString() ?? '') ?? 0.0;
}

bool _samePremioIdentity(
  Map<String, dynamic> segmento,
  Map<String, dynamic> premio,
) {
  final segmentoId = _normalizedPremioId(segmento);
  final premioId = _normalizedPremioId(premio);
  if (segmentoId != null && premioId != null) {
    return segmentoId == premioId;
  }

  return _normalizedPremioTipo(segmento) == _normalizedPremioTipo(premio) &&
      _normalizedPremioValor(segmento) == _normalizedPremioValor(premio) &&
      _normalizedPremioLabel(segmento) == _normalizedPremioLabel(premio);
}

int? resolvePremioVisualIndex({
  required List<Map<String, dynamic>> segmentos,
  int? premioIndex,
  Map<String, dynamic>? premio,
}) {
  if (segmentos.isEmpty) return null;

  if (premioIndex != null && premioIndex >= 0 && premioIndex < segmentos.length) {
    if (premio == null || _samePremioIdentity(segmentos[premioIndex], premio)) {
      return premioIndex;
    }
  }

  if (premio == null) return null;

  final matches = <int>[];
  for (var i = 0; i < segmentos.length; i++) {
    if (_samePremioIdentity(segmentos[i], premio)) {
      matches.add(i);
    }
  }

  if (matches.length == 1) {
    return matches.single;
  }

  if (premioIndex != null && matches.contains(premioIndex)) {
    return premioIndex;
  }

  return null;
}

double roletaSegmentCenterAngle({
  required int segmentoIndex,
  required int totalSegmentos,
}) {
  if (totalSegmentos <= 0) {
    throw ArgumentError.value(totalSegmentos, 'totalSegmentos');
  }
  final anguloPorFatia = 2 * math.pi / totalSegmentos;
  return -math.pi / 2 + ((segmentoIndex + 0.5) * anguloPorFatia);
}

double normalizeRoletaAngle(double angle) {
  final normalized = angle % (2 * math.pi);
  return normalized < 0 ? normalized + (2 * math.pi) : normalized;
}

double calculateRoletaFinalAngle({
  required int premioIndex,
  required int totalSegmentos,
  int voltasCompletas = 4,
}) {
  if (totalSegmentos <= 0) {
    throw ArgumentError.value(totalSegmentos, 'totalSegmentos');
  }
  if (premioIndex < 0 || premioIndex >= totalSegmentos) {
    throw RangeError.range(premioIndex, 0, totalSegmentos - 1, 'premioIndex');
  }

  final centerAngle = roletaSegmentCenterAngle(
    segmentoIndex: premioIndex,
    totalSegmentos: totalSegmentos,
  );
  final targetOffset = normalizeRoletaAngle((-math.pi / 2) - centerAngle);
  return (voltasCompletas * 2 * math.pi) + targetOffset;
}
