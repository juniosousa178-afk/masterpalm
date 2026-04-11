// Política única de contexto de loja no Web (espelha AppStartRouter).
// Extraída para testes de regressão sem depender de Firebase/Hive.

import '../services/public_store_link_helper.dart';

/// Resultado da checagem (motivo curto para testes e logs).
class WebStoreContextPolicyResult {
  final bool allowed;
  final String? rejectionMotivo;

  const WebStoreContextPolicyResult._(this.allowed, this.rejectionMotivo);

  const WebStoreContextPolicyResult.ok()
      : allowed = true,
        rejectionMotivo = null;

  factory WebStoreContextPolicyResult.rejected(String motivo) {
    return WebStoreContextPolicyResult._(false, motivo);
  }

  /// Mesma lógica de [_AppStartRouterState._webEvaluateStoreContextSafe].
  static WebStoreContextPolicyResult evaluate({
    required bool resolveThrew,
    String? resolvedStoreId,
    required String sessionStoreId,
  }) {
    final sid = sessionStoreId.trim();
    if (resolveThrew) {
      final sessionOk = sid.isNotEmpty && isValidForPublicLink(sid);
      if (!sessionOk) {
        return WebStoreContextPolicyResult.rejected(
          'resolve_exception_sem_sessao_segura',
        );
      }
      return const WebStoreContextPolicyResult.ok();
    }

    final trimmed = resolvedStoreId?.trim() ?? '';
    final resolveOk = trimmed.isNotEmpty && isValidForPublicLink(trimmed);
    final sessionOk = sid.isNotEmpty && isValidForPublicLink(sid);

    if (!resolveOk && !sessionOk) {
      return WebStoreContextPolicyResult.rejected('no_safe_store');
    }
    if (resolveOk && sessionOk && trimmed != sid) {
      return WebStoreContextPolicyResult.rejected('resolve_session_mismatch');
    }
    return const WebStoreContextPolicyResult.ok();
  }
}
