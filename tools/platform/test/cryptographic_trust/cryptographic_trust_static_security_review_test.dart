import 'dart:io';

import 'package:test/test.dart';

/// Grep-style static security review for Cryptographic Trust lib files.
void main() {
  group('Cryptographic Trust static security review', () {
    Iterable<File> dartFiles(String root) sync* {
      final dir = Directory(root);
      if (!dir.existsSync()) return;
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('.dart')) {
          yield entity;
        }
      }
    }

    test('lib/cryptographic_trust avoids HttpClient network calls', () {
      for (final file in dartFiles('lib/cryptographic_trust')) {
        final content = file.readAsStringSync();
        expect(content.contains('HttpClient'), isFalse, reason: file.path);
        expect(content.contains('Socket.connect'), isFalse, reason: file.path);
      }
    });

    test('lib/models/cryptographic_trust avoids Process.run', () {
      for (final file in dartFiles('lib/models/cryptographic_trust')) {
        final content = file.readAsStringSync();
        expect(content.contains('Process.run'), isFalse, reason: file.path);
      }
    });

    test('operational layer avoids privateKey in toJson serializers', () {
      for (final file in dartFiles('lib/models/cryptographic_trust')) {
        final content = file.readAsStringSync();
        expect(content.contains("'privateKey':"), isFalse, reason: file.path);
        expect(content.contains('"privateKey":'), isFalse, reason: file.path);
      }
    });

    test('provider implementation documents no release authorization', () {
      final providerFile = File(
        'lib/providers/platform_cryptographic_trust_provider.dart',
      );
      final content = providerFile.readAsStringSync();
      expect(content.contains('noReleaseAuthorization'), isTrue);
      expect(content.contains('releaseAuthorized'), isFalse);
    });

    test('signing key handle avoids exposing key bytes in toString', () {
      final handleFile = File(
        'lib/cryptographic_trust/key_material/opaque_cryptographic_signing_key_handle.dart',
      );
      final content = handleFile.readAsStringSync();
      expect(content.contains('SimpleKeyPair'), isFalse);
    });

    test('report source never calls evaluate', () {
      final reportSource = File(
        'lib/report/sources/cryptographic_trust_report_source.dart',
      );
      final content = reportSource.readAsStringSync();
      expect(content.contains('.evaluate('), isFalse);
    });

    test('history mapper never calls evaluate', () {
      final mapper = File(
        'lib/history/mappers/cryptographic_trust_history_mapper.dart',
      );
      final content = mapper.readAsStringSync();
      expect(content.contains('.evaluate('), isFalse);
    });

    test('observable provider avoids logging signature values', () {
      final observable = File(
        'lib/observability/instrumentation/observable_cryptographic_trust_provider.dart',
      );
      final content = observable.readAsStringSync();
      expect(content.contains('signatureValue'), isFalse);
      expect(content.contains('privateKey'), isFalse);
    });

    test('in-memory store avoids external IO', () {
      final store = File(
        'lib/cryptographic_trust/stores/in_memory_cryptographic_trust_store.dart',
      );
      final content = store.readAsStringSync();
      expect(content.contains('File('), isFalse);
      expect(content.contains('HttpClient'), isFalse);
    });

    test('canonical serializer uses sha256 not md5', () {
      final serializer = File(
        'lib/cryptographic_trust/cryptographic_trust_canonical_serializer.dart',
      );
      final content = serializer.readAsStringSync();
      expect(content.contains('sha256'), isTrue);
      expect(content.contains('md5'), isFalse);
    });
  });
}
