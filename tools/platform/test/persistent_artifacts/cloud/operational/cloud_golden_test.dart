import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('CloudGolden', () {
    test('carrega 22 goldens sem auto-update', () {
      final dir =
          Directory('test/goldens/persistent_artifacts/cloud_operational');
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      expect(files.length, 22);
      for (final file in files) {
        final json =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        expect(json.containsKey('name'), isTrue);
        expect(json.containsKey('status'), isTrue);
      }
    });
  });
}
