// R8.4.43 — origin diferente não herda sessão (controle negativo).

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/r8443_auth_helpers.dart';

/// Porta de isolamento via --dart-define=R8443_ISOLATION_PORT=8812
const _isolationPort = String.fromEnvironment('R8443_ISOLATION_PORT');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  if (_isolationPort.isEmpty) {
    test('skip — defina R8443_ISOLATION_PORT', () {});
    return;
  }

  testWidgets('WEB_AUTH_STORAGE_ORIGIN_ISOLATION_CONFIRMED', (tester) async {
    binding.reportData ??= <String, String>{};

    await r8443StartApp(tester);
    await r8443AssertQaEnvironment();

    expect(FirebaseAuth.instance.currentUser, isNull);
    await r8443WaitLoginForm(tester);
    expect(find.byKey(const ValueKey<String>('home-ready')), findsNothing);

    binding.reportData!['WEB_AUTH_STORAGE_ORIGIN_ISOLATION_CONFIRMED'] = 'true';
    binding.reportData!['isolation_port'] = _isolationPort;
    r8443StampReportEnvelope(binding);
  });
}
