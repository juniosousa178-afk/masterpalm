// R8.4.43 — Fase B: restaurar sessão em novo processo Chrome (sem novo login).

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/r8443_auth_helpers.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('FLUTTER_WEB_AUTH_SESSION_RESTORED_NEW_PROCESS', (tester) async {
    binding.reportData ??= <String, String>{};

    await r8443StartApp(tester);
    await r8443AssertQaEnvironment();
    await r8443WaitRestoredSessionHome(tester);

    final user = FirebaseAuth.instance.currentUser!;
    binding.reportData!['PHASE_B_CURRENT_USER_RESTORED'] = 'true';
    binding.reportData!['PHASE_B_SIGN_IN_WITH_PASSWORD_COUNT'] =
        r8443AuthRequestMarkerVisible(tester) ? '1' : '0';
    binding.reportData!['FLUTTER_WEB_AUTH_SESSION_RESTORED_NEW_PROCESS'] = 'true';
    binding.reportData!['FLUTTER_WEB_AUTH_PERSISTENCE_BROWSER_RESTART_GREEN'] =
        'true';
    binding.reportData!['uid'] = user.uid;

    expect(
      binding.reportData!['PHASE_B_SIGN_IN_WITH_PASSWORD_COUNT'],
      '0',
    );
    r8443StampReportEnvelope(binding);
  });
}
