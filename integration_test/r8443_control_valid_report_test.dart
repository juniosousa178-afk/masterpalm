// R8.4.44A — controle positivo sintético (sem navegador real).

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/r8443_auth_helpers.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('CONTROL_VALID_REPORT', (tester) async {
    binding.reportData ??= <String, String>{};
    binding.reportData!['R8443_CONTROL_POSITIVE_GREEN'] = 'true';
    r8443StampReportEnvelope(binding);
  });
}
