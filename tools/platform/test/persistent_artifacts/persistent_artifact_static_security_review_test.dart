import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('Persistent Artifact static security review', () {
    Iterable<File> dartFiles(String root) sync* {
      final dir = Directory(root);
      if (!dir.existsSync()) return;
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('.dart')) {
          yield entity;
        }
      }
    }

    test('lib/persistent_artifacts avoids HttpClient and Socket.connect', () {
      for (final file in dartFiles('lib/persistent_artifacts')) {
        final content = file.readAsStringSync();
        expect(content.contains('HttpClient'), isFalse, reason: file.path);
        expect(content.contains('Socket.connect'), isFalse, reason: file.path);
      }
    });

    test('models/persistent_artifacts avoids Process.run', () {
      for (final file in dartFiles('lib/models/persistent_artifacts')) {
        final content = file.readAsStringSync();
        expect(content.contains('Process.run'), isFalse, reason: file.path);
      }
    });

    test('provider keeps declarative no-physical-storage boundary text', () {
      final provider = File(
          'lib/persistent_artifacts/persistent_artifact_operational_core.dart');
      final content = provider.readAsStringSync();
      expect(content.contains('no-physical-storage-by-default'), isTrue);
    });

    test('in-memory store avoids filesystem adapter usage', () {
      final store = File(
          'lib/persistent_artifacts/persistent_artifact_operational_core.dart');
      final content = store.readAsStringSync();
      expect(content.contains('File('), isFalse);
      expect(content.contains('Directory('), isFalse);
    });
  });
}
