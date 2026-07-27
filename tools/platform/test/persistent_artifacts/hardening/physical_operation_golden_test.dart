import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('physical operation goldens', () {
    for (var i = 1; i <= 20; i++) {
      final name = 'physical_operation_${i.toString().padLeft(2, '0')}';
      test('$name is stable', () {
        final file =
            File('test/goldens/persistent_artifacts/integration/$name.json');
        expect(file.existsSync(), isTrue);
        final json =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        expect(json['schema'], 'persistent-artifact-physical-golden-v1');
        expect(json['name'], name);
      });
    }
  });
}
