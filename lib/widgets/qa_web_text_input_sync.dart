import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../config/mp_environment_config.dart';
import 'qa_web_text_input_sync_stub.dart'
    if (dart.library.html) 'qa_web_text_input_sync_web.dart' as impl;

/// Copia valores dos inputs HTML para controllers antes do login QA E2E.
void qaWebSyncLoginControllersIfNeeded({
  required TextEditingController login,
  required TextEditingController senha,
}) {
  if (!kIsWeb || !MpEnvironmentConfig.isQa) return;
  impl.qaWebSyncLoginControllersIfNeeded(login: login, senha: senha);
}
