// R8.4.42 — login Web QA via integration_test + Auth/Firestore Emulator.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:master_palm/config/mp_environment_config.dart';
import 'package:master_palm/main.dart' as app;
import 'package:master_palm/widgets/mp_qa_login_trace.dart';

import 'support/r8442_pump_helpers.dart';
import 'support/r8442_qa_constants.dart';

const _kEmailKey = ValueKey<String>('login-email');
const _kPasswordKey = ValueKey<String>('login-password');
const _kSubmitKey = ValueKey<String>('login-submit');

Future<void> _startApp(WidgetTester tester) async {
  MpQaLoginTraceState.instance.reset();
  app.main();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _waitLoginForm(WidgetTester tester) async {
  await pumpUntilFound(
    tester,
    find.byKey(_kEmailKey),
    stage: 'login-email',
    timeout: const Duration(minutes: 3),
  );
}

Future<void> _fillLogin(
  WidgetTester tester, {
  required String email,
  required String password,
}) async {
  final emailField = find.byKey(_kEmailKey);
  final passField = find.byKey(_kPasswordKey);
  expect(emailField, findsOneWidget);
  expect(passField, findsOneWidget);

  await tester.enterText(emailField, email);
  await tester.pump();
  await tester.enterText(passField, password);
  await tester.pump();

  final emailWidget = tester.widget<TextField>(emailField);
  expect(emailWidget.controller?.text, email);
  final passWidget = tester.widget<TextField>(passField);
  expect(passWidget.controller?.text.isNotEmpty, isTrue);
}

Future<void> _tapSubmit(WidgetTester tester) async {
  final submit = find.byKey(_kSubmitKey);
  expect(submit, findsOneWidget);
  await tester.ensureVisible(submit);
  await tester.tap(submit);
  await tester.pump();
}

Future<void> _assertQaEnvironment() async {
  expect(MpEnvironmentConfig.isQa, isTrue);
  expect(MpEnvironmentConfig.isProduction, isFalse);
  expect(MpEnvironmentConfig.useFirebaseEmulators, isTrue);
  final projectId = Firebase.app().options.projectId;
  expect(projectId, kR8442QaProjectId);
  expect(projectId, isNot(kR8442ProductionProjectId));
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('R8442 Web login emulator', () {
    testWidgets('INTEGRATION_TEST_INVALID_LOGIN_FAILS_CLOSED', (tester) async {
      await _startApp(tester);
      await _waitLoginForm(tester);
      await _assertQaEnvironment();

      await _fillLogin(
        tester,
        email: kR8442UserEmail,
        password: kR8442InvalidPassword,
      );
      await _tapSubmit(tester);

      await pumpUntilFound(
        tester,
        find.byKey(const ValueKey<String>('qa-login-submit-dispatched')),
        stage: 'qa-login-submit-dispatched',
      );
      await pumpUntilFound(
        tester,
        find.byKey(const ValueKey<String>('qa-auth-request-started')),
        stage: 'qa-auth-request-started',
      );
      await pumpUntilFound(
        tester,
        find.byKey(const ValueKey<String>('qa-auth-request-failed')),
        stage: 'qa-auth-request-failed',
      );

      expect(FirebaseAuth.instance.currentUser, isNull);
      expect(find.byKey(const ValueKey<String>('home-ready')), findsNothing);

      await pumpUntilAbsent(
        tester,
        find.byKey(const ValueKey<String>('qa-login-loading')),
        stage: 'qa-login-loading',
      );
      expect(find.byKey(_kSubmitKey), findsOneWidget);
    });

    testWidgets('INTEGRATION_TEST_WEB_LOGIN_GREEN', (tester) async {
      binding.reportData ??= <String, String>{};

      final t0 = DateTime.now();
      await _startApp(tester);
      await _waitLoginForm(tester);
      await _assertQaEnvironment();

      await _fillLogin(
        tester,
        email: kR8442UserEmail,
        password: kR8442UserPassword,
      );
      await _tapSubmit(tester);

      await pumpUntilFound(
        tester,
        find.byKey(const ValueKey<String>('qa-login-submit-dispatched')),
        stage: 'qa-login-submit-dispatched',
      );
      await pumpUntilFound(
        tester,
        find.byKey(const ValueKey<String>('qa-login-validation-passed')),
        stage: 'qa-login-validation-passed',
      );
      await pumpUntilFound(
        tester,
        find.byKey(const ValueKey<String>('qa-auth-request-started')),
        stage: 'qa-auth-request-started',
      );
      await pumpUntilFound(
        tester,
        find.byKey(const ValueKey<String>('qa-auth-request-succeeded')),
        stage: 'qa-auth-request-succeeded',
      );
      await pumpUntilFound(
        tester,
        find.byKey(const ValueKey<String>('qa-app-authenticated')),
        stage: 'qa-app-authenticated',
      );

      await pumpUntilCondition(
        tester,
        () => FirebaseAuth.instance.currentUser != null,
        stage: 'FirebaseAuth.currentUser',
      );
      final user = FirebaseAuth.instance.currentUser!;
      expect(user.email?.toLowerCase(), kR8442UserEmail);
      if (kR8442ExpectedUid.isNotEmpty) {
        expect(user.uid, kR8442ExpectedUid);
      }

      var authStreamSeen = false;
      final sub = FirebaseAuth.instance.authStateChanges().listen((u) {
        if (u != null) authStreamSeen = true;
      });
      await pumpUntilCondition(
        tester,
        () => authStreamSeen || FirebaseAuth.instance.currentUser != null,
        stage: 'authStateChanges',
        timeout: const Duration(seconds: 30),
      );
      await sub.cancel();

      await pumpUntilFound(
        tester,
        find.byKey(const ValueKey<String>('company-loaded')),
        stage: 'company-loaded',
        timeout: const Duration(minutes: 2),
      );
      await pumpUntilFound(
        tester,
        find.byKey(const ValueKey<String>('navigation-ready')),
        stage: 'navigation-ready',
        timeout: const Duration(minutes: 2),
      );
      await pumpUntilFound(
        tester,
        find.byKey(const ValueKey<String>('home-ready')),
        stage: 'home-ready',
        timeout: const Duration(minutes: 3),
      );

      expect(find.textContaining(kR8442EmpresaNome), findsWidgets);

      binding.reportData!['INTEGRATION_TEST_WEB_LOGIN_GREEN'] = 'true';
      binding.reportData!['elapsed_ms'] =
          DateTime.now().difference(t0).inMilliseconds.toString();
      binding.reportData!['uid'] = user.uid;
    });
  });
}
