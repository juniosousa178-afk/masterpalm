import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('Secure filesystem static security review', () {
    test('adapter files avoid unsafe network/process APIs', () {
      final dir = Directory('lib/persistent_artifacts/adapters/filesystem');
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) {
          continue;
        }
        final content = entity.readAsStringSync();
        expect(content.contains('HttpClient'), isFalse, reason: entity.path);
        expect(content.contains('Socket.connect'), isFalse,
            reason: entity.path);
        expect(content.contains('Process.run'), isFalse, reason: entity.path);
      }
    });

    test('public location references do not expose absolute paths', () {
      final file = File(
        'lib/persistent_artifacts/adapters/filesystem/secure_filesystem_path_resolver.dart',
      );
      final content = file.readAsStringSync();
      expect(content.contains('backendId}://'), isTrue);
    });
  });
}
