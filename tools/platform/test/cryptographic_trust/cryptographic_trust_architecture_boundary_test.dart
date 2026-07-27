import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('Cryptographic Trust architecture boundaries', () {
    test('domain models do not import package:crypto except fingerprint helper',
        () {
      final dir = Directory(p.join('lib', 'models', 'cryptographic_trust'));
      final offenders = dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where(
              (f) => !f.path.endsWith('cryptographic_trust_fingerprint.dart'))
          .where((f) => f.readAsStringSync().contains('package:crypto/'))
          .toList();
      expect(offenders, isEmpty);
    });

    test('domain models do not import package:cryptography', () {
      final dir = Directory(p.join('lib', 'models', 'cryptographic_trust'));
      final offenders = dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => f.readAsStringSync().contains('package:cryptography/'))
          .toList();
      expect(offenders, isEmpty);
    });

    test('concrete crypto libraries live only under adapters and serializers',
        () {
      final dir = Directory(p.join('lib', 'cryptographic_trust'));
      final offenders = <String>[];
      for (final file in dir.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        final content = file.readAsStringSync();
        final usesCrypto = content.contains('package:crypto/') ||
            content.contains('package:cryptography/');
        if (!usesCrypto) continue;
        if (file.path.contains('${p.separator}adapters${p.separator}')) {
          continue;
        }
        if (file.path
            .endsWith('cryptographic_trust_canonical_serializer.dart')) {
          continue;
        }
        offenders.add(file.path);
      }
      expect(offenders, isEmpty);
    });

    test('release governance domain remains unchanged by cryptographic trust',
        () {
      final rgDir = Directory(p.join('lib', 'release_governance'));
      final references = rgDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => f.readAsStringSync().contains('cryptographic_trust'))
          .toList();
      expect(references, isEmpty);
    });

    test('cryptographic trust models do not import release governance', () {
      final ctDir = Directory(p.join('lib', 'models', 'cryptographic_trust'));
      final imports = ctDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => f.readAsStringSync().contains('release_governance'))
          .toList();
      expect(imports, isEmpty);
    });

    test('interfaces define contracts without crypto imports', () {
      final dir = Directory(p.join('lib', 'cryptographic_trust', 'interfaces'));
      for (final file in dir.listSync().whereType<File>()) {
        final content = file.readAsStringSync();
        expect(content.contains('package:crypto/'), isFalse, reason: file.path);
        expect(content.contains('package:cryptography/'), isFalse,
            reason: file.path);
      }
    });

    test('provider orchestrates via registries not algorithm switches', () {
      final providerFile = File(p.join(
          'lib', 'providers', 'platform_cryptographic_trust_provider.dart'));
      final content = providerFile.readAsStringSync();
      expect(content.contains('switch ('), isFalse);
      expect(content.contains('Sha256DigestProvider'), isFalse);
      expect(content.contains('Ed25519Signer'), isFalse);
    });

    test('engine consolidates results without crypto library imports', () {
      final engineFile = File(p.join(
          'lib', 'cryptographic_trust', 'cryptographic_trust_engine.dart'));
      final content = engineFile.readAsStringSync();
      expect(content.contains('package:crypto/'), isFalse);
      expect(content.contains('package:cryptography/'), isFalse);
    });

    test('source resolver never references upstream evaluate methods', () {
      final resolverFile = File(
        p.join('lib', 'cryptographic_trust',
            'cryptographic_trust_source_resolver.dart'),
      );
      final content = resolverFile.readAsStringSync();
      expect(content.contains('.evaluate('), isFalse);
      expect(content.contains('.evaluateAndPublish('), isFalse);
      expect(content.contains('.publish('), isFalse);
    });

    test('key material opaque handle keeps private bytes opaque', () {
      final handleFile = File(
        p.join(
          'lib',
          'cryptographic_trust',
          'key_material',
          'opaque_cryptographic_signing_key_handle.dart',
        ),
      );
      final content = handleFile.readAsStringSync();
      expect(content.contains('toJson'), isFalse);
    });
  });
}
