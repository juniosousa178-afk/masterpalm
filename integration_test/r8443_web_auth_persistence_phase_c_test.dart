// R8.4.43 — Fase C: reload real com flag em sessionStorage (sobrevive ao reload).

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/r8442_qa_constants.dart';
import 'support/r8443_auth_helpers.dart';

const _kReloadFlag = 'r8443_reload_pending';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final reloadPending = html.window.sessionStorage[_kReloadFlag] == '1';

  testWidgets('WEB_REAL_RELOAD_AUTH_PERSISTENCE_GREEN', (tester) async {
    binding.reportData ??= <String, String>{};

    await r8443StartApp(tester);
    await r8443AssertQaEnvironment();

    if (!reloadPending) {
      await r8443WaitRestoredSessionHome(tester);
      final uidBefore = FirebaseAuth.instance.currentUser!.uid;
      html.window.sessionStorage[_kReloadFlag] = '1';
      binding.reportData!['PHASE_C_UID_BEFORE_RELOAD'] = uidBefore;
      html.window.location.reload();
      return;
    }

    html.window.sessionStorage.remove(_kReloadFlag);

    await r8443WaitRestoredSessionHome(tester);
    final uid = FirebaseAuth.instance.currentUser!.uid;
    if (kR8442ExpectedUid.isNotEmpty) {
      expect(uid, kR8442ExpectedUid);
    }

    expect(
      find.byKey(const ValueKey<String>('qa-auth-request-started')),
      findsNothing,
      reason: 'reload nao deve disparar novo signInWithPassword',
    );

    binding.reportData!['WEB_REAL_RELOAD_AUTH_PERSISTENCE_GREEN'] = 'true';
    binding.reportData!['PHASE_C_SIGN_IN_WITH_PASSWORD_COUNT'] = '0';
    binding.reportData!['uid'] = uid;
  });
}
