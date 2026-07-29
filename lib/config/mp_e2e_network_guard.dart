// Guard de rede QA — bloqueia produção em runtime Web E2E (R8.4.38).

import 'package:flutter/foundation.dart';

import 'package:master_palm/config/mp_environment_config.dart';

const List<String> kMpE2eBlockedProductionHosts = [
  'masterpalm-58c46',
  'app.mastepalm.com.br',
  'masterpalm-58c46.firebaseio.com',
  'southamerica-east1-masterpalm-58c46.cloudfunctions.net',
];

/// Valida URL antes de fetch HTTP em ambiente QA (chamado por hooks de teste).
void mpE2eAssertProductionNetworkBlocked(Uri uri) {
  if (!MpEnvironmentConfig.isQa) return;
  final host = uri.host.toLowerCase();
  final full = uri.toString().toLowerCase();
  for (final blocked in kMpE2eBlockedProductionHosts) {
    final b = blocked.toLowerCase();
    if (host.contains(b) || full.contains(b)) {
      throw StateError('WEB_UI_E2E_PRODUCTION_NETWORK_BLOCKED: $uri');
    }
  }
}

/// Log diagnóstico (sem dados sensíveis).
void mpE2eLogQaGuardStatus() {
  if (!MpEnvironmentConfig.isQa || !kDebugMode) return;
  debugPrint(
    '[MpE2E] QA guard ativo projectId=${MpEnvironmentConfig.qaProjectId} '
    'emulators=${MpEnvironmentConfig.useFirebaseEmulators}',
  );
}
