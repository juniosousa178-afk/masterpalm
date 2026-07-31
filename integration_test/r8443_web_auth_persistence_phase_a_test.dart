// R8.4.43 — Fase A: criar sessão real via integration_test (sem logout).

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/r8442_qa_constants.dart';
import 'support/r8443_auth_helpers.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SESSION_PHASE_A_AUTHENTICATED', (tester) async {
    binding.reportData ??= <String, String>{};

    await r8443StartApp(tester);
    await r8443AssertQaEnvironment();
    await r8443WaitLoginForm(tester);
    expect(FirebaseAuth.instance.currentUser, isNull);

    await r8443FillLogin(
      tester,
      email: kR8442UserEmail,
      password: kR8442UserPassword,
    );
    await r8443TapSubmit(tester);
    await r8443WaitAuthenticatedHome(tester, binding: binding);

    final user = FirebaseAuth.instance.currentUser!;
    binding.reportData!['SESSION_PHASE_A_AUTHENTICATED'] = 'true';
    binding.reportData!['SESSION_PHASE_A_UID_MATCH'] =
        kR8442ExpectedUid.isEmpty || user.uid == kR8442ExpectedUid
            ? 'true'
            : 'false';
    binding.reportData!['SESSION_PHASE_A_HOME_READY'] = 'true';
    binding.reportData!['uid'] = user.uid;
    r8443StampReportEnvelope(binding);
  });
}
