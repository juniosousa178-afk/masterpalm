import 'dart:io';

import 'package:masterpalm_platform/cryptographic_trust/cryptographic_key_reference_validator.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_fingerprint.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/cryptographic_trust_test_fixtures.dart';

void main() {
  group('Cryptographic Trust security review', () {
    const forbiddenFieldNames = [
      'privateKey',
      'secret',
      'password',
      'token',
      'seed',
    ];

    test('sha256 placeholder is sentinel string not crypto claim', () {
      expect(CryptographicTrustTestFixtures.sha256Placeholder, hasLength(64));
      expect(
        CryptographicTrustTestFixtures.validDigest().value,
        CryptographicTrustTestFixtures.sha256Placeholder,
      );
    });

    test('domain fingerprint differs from signature value', () {
      final envelope = CryptographicTrustTestFixtures.validSignatureEnvelope();
      final fingerprint = CryptographicTrustFingerprint.fromComparableJson(
        envelope.toComparableJson(),
      );
      expect(fingerprint, isNot(envelope.signatureValue));
      expect(fingerprint, hasLength(64));
    });

    test('CryptographicDigest model has no privateKey field', () {
      final digest = CryptographicTrustTestFixtures.validDigest();
      expect(digest.toJson().containsKey('privateKey'), isFalse);
      expect(digest.toJson().containsKey('secret'), isFalse);
    });

    test('CryptographicKeyReference model has no private key material fields',
        () {
      final key = CryptographicTrustTestFixtures.validKeyReference();
      final json = key.toJson();
      for (final field in forbiddenFieldNames) {
        expect(json.containsKey(field), isFalse, reason: field);
      }
      expect(json.containsKey('publicKeyFingerprint'), isTrue);
    });

    test('CryptographicSignatureEnvelope stores public signature data only',
        () {
      final envelope = CryptographicTrustTestFixtures.validSignatureEnvelope();
      expect(envelope.toJson().containsKey('privateKey'), isFalse);
      expect(envelope.signatureValue, isNotEmpty);
    });

    test('key reference validator rejects sensitive metadata keys', () {
      for (final field in forbiddenFieldNames) {
        final key = CryptographicTrustTestFixtures.validKeyReference().copyWith(
          metadata: {field: 'forbidden'},
        );
        final result = const CryptographicKeyReferenceValidator().validate(key);
        expect(result.isValid, isFalse, reason: field);
        expect(
          result.issues.any((i) => i.code == 'CT_KEY_SENSITIVE_METADATA'),
          isTrue,
          reason: field,
        );
      }
    });

    test('key reference validator rejects case-insensitive sensitive metadata',
        () {
      final key = CryptographicTrustTestFixtures.validKeyReference().copyWith(
        metadata: const {'MyPrivateKey': 'hidden'},
      );
      final result = const CryptographicKeyReferenceValidator().validate(key);
      expect(result.isValid, isFalse);
    });

    group('lib/models/cryptographic_trust static checks', () {
      late List<File> modelFiles;

      setUpAll(() {
        final libDir =
            Directory(p.join('lib', 'models', 'cryptographic_trust'));
        modelFiles = libDir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .toList();
        expect(modelFiles, isNotEmpty);
      });

      test('model sources do not declare privateKey fields', () {
        for (final file in modelFiles) {
          final content = file.readAsStringSync();
          expect(
            RegExp(r'final\s+\w+\??\s+privateKey').hasMatch(content),
            isFalse,
            reason: file.path,
          );
        }
      });

      test('model sources do not declare secret/password/token fields', () {
        for (final file in modelFiles) {
          final content = file.readAsStringSync();
          for (final field in ['secret', 'password', 'token']) {
            expect(
              RegExp('final\\s+\\w+\\??\\s+$field').hasMatch(content),
              isFalse,
              reason: '${file.path} ($field)',
            );
          }
        }
      });

      test('model sources do not expose callback or function fields', () {
        for (final file in modelFiles) {
          final content = file.readAsStringSync();
          expect(content.contains('Function'), isFalse, reason: file.path);
          expect(content.contains('typedef'), isFalse, reason: file.path);
        }
      });
    });

    group('lib/cryptographic_trust static checks', () {
      late List<File> validatorFiles;

      setUpAll(() {
        final libDir = Directory(p.join('lib', 'cryptographic_trust'));
        validatorFiles = libDir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .toList();
        expect(validatorFiles, isNotEmpty);
      });

      test('validators do not perform real crypto operations', () {
        for (final file in validatorFiles) {
          if (file.path.contains('${p.separator}adapters${p.separator}') ||
              file.path.contains('${p.separator}interfaces${p.separator}') ||
              file.path.contains('${p.separator}key_material${p.separator}') ||
              file.path.endsWith('_service.dart')) {
            continue;
          }
          final content = file.readAsStringSync();
          expect(content.contains('PointyCastle'), isFalse, reason: file.path);
          expect(content.contains('PrivateKey'), isFalse, reason: file.path);
          expect(content.contains('sign('), isFalse, reason: file.path);
          expect(
            RegExp(r'\bverify\s*\(').hasMatch(content),
            isFalse,
            reason: file.path,
          );
        }
      });
    });
  });
}
