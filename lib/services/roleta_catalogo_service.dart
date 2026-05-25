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
