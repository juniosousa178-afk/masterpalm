import 'dart:convert';

import 'package:masterpalm_platform/models/persistent_artifacts/persistent_artifact_enums.dart';
import 'package:masterpalm_platform/models/persistent_artifacts/persistent_artifact_fingerprint.dart';
import 'package:masterpalm_platform/models/persistent_artifacts/persistent_artifact_infrastructure_snapshot.dart';
import 'package:masterpalm_platform/models/persistent_artifacts/persistent_artifact_manifest.dart';
import 'package:masterpalm_platform/models/persistent_artifacts/persistent_artifact_validation_result.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_test_fixtures.dart';

void main() {
  group('Persistent Artifact serialization audit', () {
    final aggregates = <String, Map<String, dynamic> Function()>{
      'PersistentArtifactSubject': () =>
          PersistentArtifactTestFixtures.validSubject().toJson(),
      'PersistentArtifactContentDescriptor': () =>
          PersistentArtifactTestFixtures.validContentDescriptor().toJson(),
      'PersistentArtifactLocationReference': () =>
          PersistentArtifactTestFixtures.validLocation().toJson(),
      'PersistentArtifactVersion': () =>
          PersistentArtifactTestFixtures.validVersion().toJson(),
      'PersistentArtifactManifest': () =>
          PersistentArtifactTestFixtures.validManifest().toJson(),
      'PersistentArtifactIntegrityRecord': () =>
          PersistentArtifactTestFixtures.validIntegrityRecord().toJson(),
      'PersistentArtifactInfrastructureSnapshot': () =>
          PersistentArtifactTestFixtures.validSnapshot().toJson(),
      'PersistentArtifactValidationResult': () =>
          PersistentArtifactTestFixtures.validValidationResult().toJson(),
    };

    for (final entry in aggregates.entries) {
      test('${entry.key} json keys are non-empty', () {
        expect(entry.value().keys, isNotEmpty);
      });
    }

    test('fingerprint stable across repeated comparable serialization', () {
      final snapshot = PersistentArtifactTestFixtures.validSnapshot();
      final fps = List.generate(
        5,
        (_) => PersistentArtifactFingerprint.fromComparableJson(
          snapshot.toComparableJson(),
        ),
      );
      expect(fps.toSet(), hasLength(1));
    });

    test('enum wireNames serialize as snake-free camelCase names', () {
      expect(
        PersistentArtifactType.releaseEvidence.wireName,
        'releaseEvidence',
      );
      expect(
        PersistentArtifactLifecycleStatus.deletionRequested.wireName,
        'deletionRequested',
      );
      expect(
        PersistentArtifactStorageClass.infrequentAccess.wireName,
        'infrequentAccess',
      );
    });

    test('subject json uses wireName for artifactType', () {
      final json = PersistentArtifactTestFixtures.validSubject().toJson();
      expect(json['artifactType'], 'releaseEvidence');
    });

    test('comparable json excludes version createdAt', () {
      final version = PersistentArtifactTestFixtures.validVersion();
      expect(version.toComparableJson().containsKey('createdAt'), isFalse);
      expect(version.toJson().containsKey('createdAt'), isTrue);
    });

    test('comparable json excludes snapshot operational timestamps', () {
      final snapshot = PersistentArtifactTestFixtures.validSnapshot();
      final comparable = snapshot.toComparableJson();
      expect(comparable.containsKey('createdAt'), isFalse);
      expect(comparable.containsKey('evaluatedAt'), isFalse);
      expect(comparable.containsKey('publishedAt'), isFalse);
    });

    test('map order independence for subject metadata comparable json', () {
      final subjectA = PersistentArtifactTestFixtures.validSubject().copyWith(
        metadata: const {'b': '2', 'a': '1'},
      );
      final subjectB = PersistentArtifactTestFixtures.validSubject().copyWith(
        metadata: const {'a': '1', 'b': '2'},
      );
      expect(
        jsonEncode(subjectA.toComparableJson()),
        jsonEncode(subjectB.toComparableJson()),
      );
    });

    test('snapshot comparable json sorts subjects by subjectId', () {
      final subjectA = PersistentArtifactTestFixtures.validSubject();
      final subjectB = subjectA.copyWith(subjectId: 'subject-pa-000');
      final snapshot = PersistentArtifactTestFixtures.validSnapshot().copyWith(
        subjects: [subjectA, subjectB],
      );
      final comparableSubjects =
          snapshot.toComparableJson()['subjects'] as List<dynamic>;
      expect(comparableSubjects.first['subjectId'], 'subject-pa-000');
    });

    test('validation result comparable json sorts issues by code', () {
      final result = PersistentArtifactValidationResult(
        isValid: false,
        issues: const [
          PersistentArtifactIssue(
            code: 'PA_Z',
            path: 'z',
            severity: PersistentArtifactIssueSeverity.warning,
            message: 'z',
          ),
          PersistentArtifactIssue(
            code: 'PA_A',
            path: 'a',
            severity: PersistentArtifactIssueSeverity.warning,
            message: 'a',
          ),
        ],
      );
      final comparableIssues =
          result.toComparableJson()['issues'] as List<dynamic>;
      expect(comparableIssues.first['code'], 'PA_A');
    });

    test('json roundtrip preserves nested subject in manifest', () {
      final manifest = PersistentArtifactTestFixtures.validManifest();
      final restored = PersistentArtifactManifest.fromJson(manifest.toJson());
      expect(restored.subject.subjectId, manifest.subject.subjectId);
    });

    test('json encode/decode roundtrip for snapshot is stable', () {
      final snapshot = PersistentArtifactTestFixtures.validSnapshot();
      final encoded = jsonEncode(snapshot.toJson());
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      final restored =
          PersistentArtifactInfrastructureSnapshot.fromJson(decoded);
      expect(restored.projectId, snapshot.projectId);
      expect(restored.toComparableJson(), equals(snapshot.toComparableJson()));
    });

    test('fingerprint derived from comparable json has sha256 length', () {
      final fingerprint = PersistentArtifactFingerprint.fromComparableJson(
        PersistentArtifactTestFixtures.validSnapshot().toComparableJson(),
      );
      expect(fingerprint, hasLength(64));
    });

    test('integrity record status serializes as wireName', () {
      final json =
          PersistentArtifactTestFixtures.validIntegrityRecord().toJson();
      expect(json['status'], 'verified');
    });
  });
}
