// R8.4.43 — sessão persistida não contorna Emulator indisponível.

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:master_palm/config/mp_environment_config.dart';
import 'package:master_palm/main.dart' as app;

import 'support/r8442_pump_helpers.dart';
import 'support/r8442_qa_constants.dart';

const _failMode = String.fromEnvironment('R8443_FAIL_CLOSED_MODE');

Future<void> _startApp(WidgetTester tester) async {
  app.main();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  if (_failMode != 'persisted-firestore') {
    test('skip — defina R8443_FAIL_CLOSED_MODE=persisted-firestore', () {});
    return;
  }

  testWidgets('PERSISTED_SESSION_QA_EMULATOR_FAILS_CLOSED', (tester) async {
    expect(MpEnvironmentConfig.isQa, isTrue);
    expect(
      MpEnvironmentConfig.firestoreEmulatorHost.contains(':1'),
      isTrue,
      reason: 'Firestore emulator deve usar porta inválida',
    );

    await _startApp(tester);

    await pumpUntilFound(
      tester,
      find.byKey(const ValueKey<String>('qa-bootstrap-error')),
      stage: 'qa-bootstrap-error',
      timeout: const Duration(minutes: 2),
    );

    expect(find.byKey(const ValueKey<String>('home-ready')), findsNothing);
    expect(Firebase.app().options.projectId, isNot(kR8442ProductionProjectId));
  });
}
