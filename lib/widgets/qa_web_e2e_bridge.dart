import 'package:flutter/foundation.dart' show kIsWeb;

import '../config/mp_environment_config.dart';
import 'qa_web_e2e_bridge_stub.dart'
    if (dart.library.html) 'qa_web_e2e_bridge_web.dart' as impl;

/// Regista trigger E2E (somente QA Web) para submit de login headless.
void qaWebRegisterLoginTrigger(Future<void> Function() login) {
  if (!kIsWeb || !MpEnvironmentConfig.isQa) return;
  impl.qaWebRegisterLoginTrigger(login);
}
