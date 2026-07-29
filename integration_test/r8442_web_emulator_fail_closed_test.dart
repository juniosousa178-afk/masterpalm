// R8.4.42 — fail-closed bootstrap com emuladores indisponíveis.

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:master_palm/config/mp_environment_config.dart';
import 'package:master_palm/main.dart' as app;

import 'support/r8442_pump_helpers.dart';
import 'support/r8442_qa_constants.dart';

/// Modo: --dart-define=R8442_FAIL_CLOSED_MODE=auth|firestore
const _failMode = String.fromEnvironment('R8442_FAIL_CLOSED_MODE');

Future<void> _startApp(WidgetTester tester) async {
  app.main();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  if (_failMode.isEmpty) {
    test('skip — defina R8442_FAIL_CLOSED_MODE=auth|firestore', () {});
    return;
  }

  testWidgets('INTEGRATION_TEST_QA_EMULATOR_FAILS_CLOSED ($_failMode)', (tester) async {
    expect(MpEnvironmentConfig.isQa, isTrue);
    expect(MpEnvironmentConfig.useFirebaseEmulators, isTrue);

    if (_failMode == 'auth') {
      expect(
        MpEnvironmentConfig.authEmulatorHost.contains(':1'),
        isTrue,
        reason: 'Auth emulator deve usar porta inválida neste modo',
      );
    } else if (_failMode == 'firestore') {
      expect(
        MpEnvironmentConfig.firestoreEmulatorHost.contains(':1'),
        isTrue,
        reason: 'Firestore emulator deve usar porta inválida neste modo',
      );
    }

    await _startApp(tester);

    await pumpUntilFound(
      tester,
      find.byKey(const ValueKey<String>('qa-bootstrap-error')),
      stage: 'qa-bootstrap-error',
      timeout: const Duration(minutes: 2),
    );

    expect(find.byKey(const ValueKey<String>('login-email')), findsNothing);

    if (Firebase.apps.isNotEmpty) {
      expect(Firebase.app().options.projectId, isNot(kR8442ProductionProjectId));
    }
  });
}
