// R8.4.43 — helpers compartilhados para persistência de sessão Web QA.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:master_palm/config/mp_environment_config.dart';
import 'package:master_palm/main.dart' as app;
import 'package:master_palm/widgets/mp_qa_login_trace.dart';

import 'r8442_pump_helpers.dart';
import 'r8442_qa_constants.dart';

const kR8443EmailKey = ValueKey<String>('login-email');
const kR8443PasswordKey = ValueKey<String>('login-password');
const kR8443SubmitKey = ValueKey<String>('login-submit');

Future<void> r8443StartApp(WidgetTester tester, {bool resetLoginTrace = true}) async {
  if (resetLoginTrace) {
    MpQaLoginTraceState.instance.reset();
  }
  app.main();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> r8443AssertQaEnvironment() async {
  expect(MpEnvironmentConfig.isQa, isTrue);
  expect(MpEnvironmentConfig.isProduction, isFalse);
  expect(MpEnvironmentConfig.useFirebaseEmulators, isTrue);
  final projectId = Firebase.app().options.projectId;
  expect(projectId, kR8442QaProjectId);
  expect(projectId, isNot(kR8442ProductionProjectId));
}

Future<void> r8443WaitLoginForm(WidgetTester tester) async {
  await pumpUntilFound(
    tester,
    find.byKey(kR8443EmailKey),
    stage: 'login-email',
    timeout: const Duration(minutes: 3),
  );
}

Future<void> r8443FillLogin(
  WidgetTester tester, {
  required String email,
  required String password,
}) async {
  final emailField = find.byKey(kR8443EmailKey);
  final passField = find.byKey(kR8443PasswordKey);
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

Future<void> r8443TapSubmit(WidgetTester tester) async {
  final submit = find.byKey(kR8443SubmitKey);
  expect(submit, findsOneWidget);
  await tester.ensureVisible(submit);
  await tester.tap(submit);
  await tester.pump();
}

Future<void> r8443WaitAuthenticatedHome(
  WidgetTester tester, {
  IntegrationTestWidgetsFlutterBinding? binding,
}) async {
  await pumpUntilFound(
    tester,
    find.byKey(const ValueKey<String>('qa-login-submit-dispatched')),
    stage: 'qa-login-submit-dispatched',
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

  binding?.reportData ??= <String, String>{};
  binding?.reportData?['uid'] = user.uid;
}

Future<void> r8443WaitRestoredSessionHome(WidgetTester tester) async {
  await pumpUntilCondition(
    tester,
    () => FirebaseAuth.instance.currentUser != null,
    stage: 'FirebaseAuth.currentUser.restore',
    timeout: const Duration(minutes: 2),
  );

  final user = FirebaseAuth.instance.currentUser!;
  if (kR8442ExpectedUid.isNotEmpty) {
    expect(user.uid, kR8442ExpectedUid);
  }

  var authStreamSeen = false;
  final sub = FirebaseAuth.instance.authStateChanges().listen((u) {
    if (u != null) authStreamSeen = true;
  });
  await pumpUntilCondition(
    tester,
    () => authStreamSeen,
    stage: 'authStateChanges.restore',
    timeout: const Duration(seconds: 30),
  );
  await sub.cancel();

  expect(
    find.byKey(const ValueKey<String>('qa-auth-request-started')),
    findsNothing,
    reason: 'sessão restaurada não deve disparar novo signInWithPassword',
  );
  expect(
    find.byKey(const ValueKey<String>('qa-login-submit-dispatched')),
    findsNothing,
    reason: 'login-submit não deve ser acionado na restauração',
  );

  await pumpUntilAbsent(
    tester,
    find.byKey(kR8443EmailKey),
    stage: 'login-email.absent',
    timeout: const Duration(minutes: 2),
  );

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
}

bool r8443AuthRequestMarkerVisible(WidgetTester tester) {
  return find
      .byKey(const ValueKey<String>('qa-auth-request-started'))
      .evaluate()
      .isNotEmpty;
}
