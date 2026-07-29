// Ordem obrigatória do bootstrap QA Web — fail-closed (R8.4.40).

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../firebase_bootstrap_options.dart';
import 'firebase_emulator_connect.dart';
import 'mp_environment_config.dart';
import 'qa_emulator_guard.dart';

/// Estágios publicados na semântica QA.
enum QaBootstrapStage {
  started,
  environmentValid,
  firebaseInitializing,
  firebaseReady,
  emulatorsConnecting,
  emulatorsReady,
  authReady,
  appMounting,
  ready,
  error,
}

/// Progresso observável do bootstrap QA (timestamps para diagnóstico).
class QaBootstrapProgress {
  QaBootstrapProgress();

  final Map<QaBootstrapStage, DateTime> stageAt = {};
  QaBootstrapStage current = QaBootstrapStage.started;
  String? errorType;
  String? errorMessage;
  String? correlationId;

  void mark(QaBootstrapStage stage) {
    current = stage;
    stageAt[stage] = DateTime.now();
    if (kDebugMode) {
      debugPrint('[QaBootstrap] stage=$stage');
    }
  }

  Duration? durationSince(QaBootstrapStage from, QaBootstrapStage to) {
    final a = stageAt[from];
    final b = stageAt[to];
    if (a == null || b == null) return null;
    return b.difference(a);
  }

  String stageLabel() => 'qa-bootstrap-stage-${current.name}';
}

/// Inicializa Firebase QA + emulators — sem fallback offline.
Future<void> qaBootstrapInitFirebase(QaBootstrapProgress progress) async {
  assertQaBootstrapEnvironment();
  progress.mark(QaBootstrapStage.environmentValid);

  progress.mark(QaBootstrapStage.emulatorsConnecting);
  await assertQaEmulatorReachable(
    MpEnvironmentConfig.firestoreEmulatorHost,
    label: 'firestore',
  );
  await assertQaEmulatorReachable(
    MpEnvironmentConfig.authEmulatorHost,
    label: 'auth',
  );

  progress.mark(QaBootstrapStage.firebaseInitializing);
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: firebaseOptionsForInit(),
    ).timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw StateError('QA_FIREBASE_INIT_TIMEOUT'),
    );
  }

  final projectId = Firebase.app().options.projectId;
  MpEnvironmentConfig.assertQaProjectSafe(projectId);

  await connectFirebaseEmulatorsIfConfigured();
  progress.mark(QaBootstrapStage.firebaseReady);
  progress.mark(QaBootstrapStage.emulatorsReady);

  // Auth state inicial (sem App Check em QA).
  try {
    await FirebaseAuth.instance.authStateChanges().first.timeout(
          const Duration(seconds: 3),
          onTimeout: () => FirebaseAuth.instance.currentUser,
        );
  } catch (_) {
    // Sem sessão — OK para login E2E.
  }
  progress.mark(QaBootstrapStage.authReady);
}

String sanitizeQaBootstrapError(Object error) {
  final text = error.toString();
  const secrets = ['password', 'token', 'secret', 'apikey', 'credential'];
  var out = text;
  for (final s in secrets) {
    if (out.toLowerCase().contains(s)) {
      out = 'erro sanitizado ($s redacted)';
      break;
    }
  }
  if (out.length > 240) {
    out = '${out.substring(0, 240)}…';
  }
  return out;
}
