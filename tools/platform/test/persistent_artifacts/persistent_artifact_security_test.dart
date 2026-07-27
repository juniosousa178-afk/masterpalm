import 'dart:io';

import 'package:masterpalm_platform/models/persistent_artifacts/persistent_artifact_enums.dart';
import 'package:masterpalm_platform/persistent_artifacts/persistent_artifact_validators.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_test_fixtures.dart';

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

    test('models avoid privateKey in toJson serializers', () {
      for (final file in dartFiles('lib/models/persistent_artifacts')) {
        final content = file.readAsStringSync();
        expect(content.contains("'privateKey':"), isFalse, reason: file.path);
        expect(content.contains('"privateKey":'), isFalse, reason: file.path);
      }
    });

    test('models avoid secret field in toJson serializers', () {
      for (final file in dartFiles('lib/models/persistent_artifacts')) {
        final content = file.readAsStringSync();
        expect(content.contains("'secret':"), isFalse, reason: file.path);
        expect(content.contains('"secret":'), isFalse, reason: file.path);
      }
    });

    test('models avoid password field in toJson serializers', () {
      for (final file in dartFiles('lib/models/persistent_artifacts')) {
        final content = file.readAsStringSync();
        expect(content.contains("'password':"), isFalse, reason: file.path);
        expect(content.contains('"password":'), isFalse, reason: file.path);
      }
    });

    test('models avoid token field in toJson serializers', () {
      for (final file in dartFiles('lib/models/persistent_artifacts')) {
        final content = file.readAsStringSync();
        expect(content.contains("'token':"), isFalse, reason: file.path);
        expect(content.contains('"token":'), isFalse, reason: file.path);
      }
    });

    test('models avoid credential field in toJson serializers', () {
      for (final file in dartFiles('lib/models/persistent_artifacts')) {
        final content = file.readAsStringSync();
        expect(content.contains("'credential':"), isFalse, reason: file.path);
        expect(content.contains('"credential":'), isFalse, reason: file.path);
      }
    });

    test('validators reject sensitive metadata on subject', () {
      final subject = PersistentArtifactTestFixtures.validSubject().copyWith(
        metadata: const {'privateKey': 'must-not-appear'},
      );
      final result =
          const PersistentArtifactSubjectValidator().validate(subject);
      expect(result.isValid, isFalse);
      expect(
        result.issues.any((i) => i.code == 'PA_SENSITIVE_METADATA'),
        isTrue,
      );
    });

    test('validators reject password metadata on content descriptor', () {
      final content = PersistentArtifactTestFixtures.validContentDescriptor()
          .copyWith(metadata: const {'password': 'secret-value'});
      final result = const PersistentArtifactContentDescriptorValidator()
          .validate(content);
      expect(result.isValid, isFalse);
      expect(
        result.issues.any((i) => i.code == 'PA_SENSITIVE_METADATA'),
        isTrue,
      );
    });

    test('validators reject presigned URL in location metadata', () {
      final location = PersistentArtifactTestFixtures.validLocation().copyWith(
        metadata: const {
          'url':
              'https://bucket.example.com/key?X-Amz-Signature=abc&Expires=99',
        },
      );
      final result =
          const PersistentArtifactLocationValidator().validate(location);
      expect(result.isValid, isFalse);
      expect(
        result.issues.any((i) => i.code == 'PA_PRESIGNED_METADATA_VALUE'),
        isTrue,
      );
    });

    test('validators reject presigned URL in encryption metadata', () {
      final descriptor =
          PersistentArtifactTestFixtures.validEncryptionDescriptor().copyWith(
        metadata: const {'link': 'https://example.com/presigned?sig=abc'},
      );
      final result =
          const PersistentArtifactEncryptionDescriptorValidator().validate(
        descriptor,
      );
      expect(result.isValid, isFalse);
      expect(
        result.issues.any((i) => i.code == 'PA_ENCRYPTION_PRESIGNED_METADATA'),
        isTrue,
      );
    });

    test(
        'validators reject release authorization metadata on operation request',
        () {
      final request =
          PersistentArtifactTestFixtures.validOperationRequest().copyWith(
        metadata: const {'releaseAuthorized': 'true'},
      );
      final result =
          const PersistentArtifactOperationRequestValidator().validate(request);
      expect(result.isValid, isFalse);
      expect(
        result.issues.any(
          (i) => i.code == 'PA_RELEASE_AUTHORIZATION_METADATA',
        ),
        isTrue,
      );
    });

    test('encryption descriptor model has no key material fields in json', () {
      final json =
          PersistentArtifactTestFixtures.validEncryptionDescriptor().toJson();
      expect(json.containsKey('privateKey'), isFalse);
      expect(json.containsKey('secret'), isFalse);
      expect(json.containsKey('keyBytes'), isFalse);
    });

    test('persistent artifact lib avoids HttpClient network calls', () {
      for (final file in dartFiles('lib/persistent_artifacts')) {
        final content = file.readAsStringSync();
        expect(content.contains('HttpClient'), isFalse, reason: file.path);
        expect(content.contains('Socket.connect'), isFalse, reason: file.path);
      }
    });
  });
}
