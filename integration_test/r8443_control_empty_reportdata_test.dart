// R8.4.44A — controle: reportData vazio.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('CONTROL_EMPTY_REPORTDATA', (tester) async {
    binding.reportData = <String, String>{};
    expect(true, isTrue);
  });
}
