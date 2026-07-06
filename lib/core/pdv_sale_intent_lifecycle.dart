// Lifecycle mínimo de saleIntentId para PDV manual (M3.2-B).

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

/// Uma tentativa deliberada de finalização recebe um [saleIntentId] estável.
class PdvSaleIntentLifecycle {
  String? _activeId;

  /// ID ativo da tentativa em curso (null se nenhuma).
  @visibleForTesting
  String? get activeId => _activeId;

  /// Garante ID para a tentativa atual; reutiliza em retries da mesma tentativa.
  String ensureForAttempt() => _activeId ??= const Uuid().v4();

  /// Limpa após conclusão bem-sucedida ou abandono explícito da tentativa.
  void clearOnSuccess() => _activeId = null;
}
