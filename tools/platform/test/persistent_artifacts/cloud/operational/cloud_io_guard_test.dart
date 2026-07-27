import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('CloudIoGuard', () {
    final cloudLibDir = Directory('lib/persistent_artifacts/cloud');
    final forbidden = ['dart:io', 'dart:ffi', 'HttpClient', 'Socket'];

    final files = cloudLibDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    for (final file in files) {
      test('arquivo sem API proibida: ${file.path}', () {
        final content = file.readAsStringSync();
        for (final token in forbidden) {
          expect(content.contains(token), isFalse, reason: 'token=$token');
        }
      });
    }
  });
}
