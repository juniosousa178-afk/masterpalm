import 'package:cloud_functions/cloud_functions.dart';

/// Chamada ao callable [getMpCatalogPaymentSupportSnapshot] (somente root no backend).
class CatalogPaymentSupportService {
  CatalogPaymentSupportService({FirebaseFunctions? functions})
      : _functions = functions ??
            FirebaseFunctions.instanceFor(region: 'southamerica-east1');

  final FirebaseFunctions _functions;

  /// Monta o payload como o backend espera (apenas chaves não vazias).
  static Map<String, dynamic> buildPayload({
    String? lojaId,
    String? orderId,
    String? externalReference,
    String? paymentId,
  }) {
    String? t(String? s) {
      final x = s?.trim();
      return (x == null || x.isEmpty) ? null : x;
    }

    return <String, dynamic>{
      if (t(lojaId) != null) 'lojaId': t(lojaId),
      if (t(orderId) != null) 'orderId': t(orderId),
      if (t(externalReference) != null) 'externalReference': t(externalReference),
      if (t(paymentId) != null) 'paymentId': t(paymentId),
    };
  }

  /// Retorna o mapa JSON do callable (status ok | not_found | insufficient_data ou erro).
  Future<Map<String, dynamic>> fetchSnapshot(Map<String, dynamic> payload) async {
    final callable = _functions.httpsCallable('getMpCatalogPaymentSupportSnapshot');
    final result = await callable.call(payload);
    final data = result.data;
    if (data is! Map) {
      throw Exception('Resposta inválida do servidor.');
    }
    return Map<String, dynamic>.from(data);
  }
}

/// Mensagens objetivas para a UI (sem expor detalhes internos demais).
String? userFacingMessageForSnapshot(Map<String, dynamic> response) {
  final status = response['status']?.toString();
  if (status == 'not_found') {
    return 'Pagamento não encontrado ou pedido ausente.';
  }
  if (status == 'insufficient_data') {
    return 'Dados insuficientes para localizar o caso.';
  }
  return null;
}

/// Mensagem para exceções do callable.
String messageForFunctionsException(FirebaseFunctionsException e) {
  switch (e.code) {
    case 'permission-denied':
      return 'Consulta permitida apenas para conta root/admin.';
    case 'unauthenticated':
      return 'Faça login para consultar.';
    case 'invalid-argument':
      return e.message ?? 'Informe paymentId ou pedido (orderId / externalReference).';
    default:
      return e.message ?? e.code;
  }
}
