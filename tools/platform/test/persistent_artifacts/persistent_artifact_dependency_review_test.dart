import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('Persistent Artifact dependency review', () {
    test('persistent_artifacts layer does not import dart:io', () {
      final dir = Directory('lib/persistent_artifacts');
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final normalized = entity.path.replaceAll('\\', '/');
        final isFilesystemAdapter = normalized.contains(
          'lib/persistent_artifacts/adapters/filesystem/',
        );
        if (isFilesystemAdapter) continue;
        final content = entity.readAsStringSync();
        expect(content.contains("import 'dart:io'"), isFalse,
            reason: entity.path);
      }
    });

    test('persistent_artifacts models do not import network stacks', () {
      final dir = Directory('lib/models/persistent_artifacts');
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final content = entity.readAsStringSync();
        expect(content.contains('dart:io'), isFalse, reason: entity.path);
        expect(content.contains('package:http'), isFalse, reason: entity.path);
      }
    });

    test('test support helper keeps golden path scoped to persistent_artifacts',
        () {
      final helper = File(
        'test/persistent_artifacts/support/persistent_artifact_hardening_helpers.dart',
      ).readAsStringSync();
      expect(helper.contains('test/goldens/persistent_artifacts/'), isTrue);
    });
  });
}
