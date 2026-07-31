// R8.4.44A — controle: envelope sem marcador obrigatório da fase.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/r8443_auth_helpers.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('CONTROL_MISSING_MARKER', (tester) async {
    binding.reportData ??= <String, String>{};
    r8443StampReportEnvelope(binding);
    // Sem SESSION_PHASE_A_AUTHENTICATED quando testCaseId=phase_a
  });
}
