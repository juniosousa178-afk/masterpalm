import 'package:cloud_functions/cloud_functions.dart';

/// Callables: [catalogDomainSubmitRequest], [catalogDomainVerifyDns] (southamerica-east1).
class CatalogDomainWorkflowService {
  CatalogDomainWorkflowService._();

  static FirebaseFunctions get _fn =>
      FirebaseFunctions.instanceFor(region: 'southamerica-east1');

  static Future<Map<String, dynamic>> submitRequest({
    required String lojaId,
    required String dominioUserInput,
    String? providerId,
  }) async {
    final callable = _fn.httpsCallable('catalogDomainSubmitRequest');
    final res = await callable.call({
      'lojaId': lojaId.trim(),
      'dominioUserInput': dominioUserInput.trim(),
      if (providerId != null && providerId.trim().isNotEmpty)
        'providerId': providerId.trim(),
    });
    final data = res.data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  static Future<Map<String, dynamic>> verifyDns({
    required String lojaId,
    required String hostNormalized,
  }) async {
    final callable = _fn.httpsCallable('catalogDomainVerifyDns');
    final res = await callable.call({
      'lojaId': lojaId.trim(),
      'hostNormalized': hostNormalized.trim(),
    });
    final data = res.data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  static String? messageFromFunctionsException(Object e) {
    if (e is FirebaseFunctionsException) {
      return e.message?.trim().isNotEmpty == true ? e.message : e.code;
    }
    return e.toString();
  }
}
