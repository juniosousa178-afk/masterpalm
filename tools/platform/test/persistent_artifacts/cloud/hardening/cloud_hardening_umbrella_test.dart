import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('CloudHardeningUmbrella', () {
    test('marca presença da suíte Parte 3', () {
      expect(
        Directory('test/persistent_artifacts/cloud/hardening')
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('_test.dart'))
            .length,
        greaterThanOrEqualTo(8),
      );
    });
  });
}
