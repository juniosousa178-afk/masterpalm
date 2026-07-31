// R8.4.43 — perfil limpo exige login (controle negativo).

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/r8443_auth_helpers.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('WEB_CLEAN_PROFILE_REQUIRES_LOGIN', (tester) async {
    binding.reportData ??= <String, String>{};

    await r8443StartApp(tester);
    await r8443AssertQaEnvironment();

    expect(FirebaseAuth.instance.currentUser, isNull);
    await r8443WaitLoginForm(tester);
    expect(find.byKey(const ValueKey<String>('home-ready')), findsNothing);

    binding.reportData!['WEB_CLEAN_PROFILE_REQUIRES_LOGIN'] = 'true';
    r8443StampReportEnvelope(binding);
  });
}
