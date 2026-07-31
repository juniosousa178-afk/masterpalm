// R8.4.44A — controle: teste verde sem reportData.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('CONTROL_NO_REPORTDATA', (tester) async {
    expect(true, isTrue);
  });
}
