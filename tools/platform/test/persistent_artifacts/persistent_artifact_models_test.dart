import 'package:masterpalm_platform/models/persistent_artifacts/persistent_artifact_availability_record.dart';
import 'package:masterpalm_platform/models/persistent_artifacts/persistent_artifact_content_descriptor.dart';
import 'package:masterpalm_platform/models/persistent_artifacts/persistent_artifact_deletion_models.dart';
import 'package:masterpalm_platform/models/persistent_artifacts/persistent_artifact_encryption_descriptor.dart';
import 'package:masterpalm_platform/models/persistent_artifacts/persistent_artifact_enums.dart';
import 'package:masterpalm_platform/models/persistent_artifacts/persistent_artifact_identity.dart';
import 'package:masterpalm_platform/models/persistent_artifacts/persistent_artifact_infrastructure_identity.dart';
import 'package:masterpalm_platform/models/persistent_artifacts/persistent_artifact_infrastructure_snapshot.dart';
import 'package:masterpalm_platform/models/persistent_artifacts/persistent_artifact_integrity_record.dart';
import 'package:masterpalm_platform/models/persistent_artifacts/persistent_artifact_lifecycle_record.dart';
import 'package:masterpalm_platform/models/persistent_artifacts/persistent_artifact_location_reference.dart';
import 'package:masterpalm_platform/models/persistent_artifacts/persistent_artifact_manifest.dart';
import 'package:masterpalm_platform/models/persistent_artifacts/persistent_artifact_operation_models.dart';
import 'package:masterpalm_platform/models/persistent_artifacts/persistent_artifact_policy_models.dart';
import 'package:masterpalm_platform/models/persistent_artifacts/persistent_artifact_publication_record.dart';
import 'package:masterpalm_platform/models/persistent_artifacts/persistent_artifact_reference_models.dart';
import 'package:masterpalm_platform/models/persistent_artifacts/persistent_artifact_replica_record.dart';
import 'package:masterpalm_platform/models/persistent_artifacts/persistent_artifact_replication_requirement.dart';
import 'package:masterpalm_platform/models/persistent_artifacts/persistent_artifact_retention_record.dart';
import 'package:masterpalm_platform/models/persistent_artifacts/persistent_artifact_subject.dart';
import 'package:masterpalm_platform/models/persistent_artifacts/persistent_artifact_validation_result.dart';
import 'package:masterpalm_platform/models/persistent_artifacts/persistent_artifact_version.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_test_fixtures.dart';

void main() {
  group('Persistent Artifact models', () {
    void assertJsonRoundtrip<T>({
      required String label,
      required T original,
      required T Function(Map<String, dynamic>) fromJson,
      required Map<String, dynamic> Function(T) toJson,
    }) {
      test('$label roundtrip via json', () {
        final restored = fromJson(toJson(original));
        expect(restored, equals(original));
      });
    }

    assertJsonRoundtrip(
      label: 'PersistentArtifactSubject',
      original: PersistentArtifactTestFixtures.validSubject(),
      fromJson: PersistentArtifactSubject.fromJson,
      toJson: (v) => v.toJson(),
    );
    assertJsonRoundtrip(
      label: 'PersistentArtifactContentDescriptor',
      original: PersistentArtifactTestFixtures.validContentDescriptor(),
      fromJson: PersistentArtifactContentDescriptor.fromJson,
      toJson: (v) => v.toJson(),
    );
    assertJsonRoundtrip(
      label: 'PersistentArtifactLocationReference',
      original: PersistentArtifactTestFixtures.validLocation(),
      fromJson: PersistentArtifactLocationReference.fromJson,
      toJson: (v) => v.toJson(),
    );
    assertJsonRoundtrip(
      label: 'PersistentArtifactVersion',
      original: PersistentArtifactTestFixtures.validVersion(),
      fromJson: PersistentArtifactVersion.fromJson,
      toJson: (v) => v.toJson(),
    );
    assertJsonRoundtrip(
      label: 'PersistentArtifactManifest',
      original: PersistentArtifactTestFixtures.validManifest(),
      fromJson: PersistentArtifactManifest.fromJson,
      toJson: (v) => v.toJson(),
    );
    assertJsonRoundtrip(
      label: 'PersistentArtifactIntegrityRecord',
      original: PersistentArtifactTestFixtures.validIntegrityRecord(),
      fromJson: PersistentArtifactIntegrityRecord.fromJson,
      toJson: (v) => v.toJson(),
    );
    assertJsonRoundtrip(
      label: 'PersistentArtifactEncryptionDescriptor',
      original: PersistentArtifactTestFixtures.validEncryptionDescriptor(),
      fromJson: PersistentArtifactEncryptionDescriptor.fromJson,
      toJson: (v) => v.toJson(),
    );
    assertJsonRoundtrip(
      label: 'PersistentArtifactPublicationRecord',
      original: PersistentArtifactTestFixtures.validPublication(),
      fromJson: PersistentArtifactPublicationRecord.fromJson,
      toJson: (v) => v.toJson(),
    );
    assertJsonRoundtrip(
      label: 'PersistentArtifactLifecycleRecord',
      original: PersistentArtifactTestFixtures.validLifecycleRecord(),
      fromJson: PersistentArtifactLifecycleRecord.fromJson,
      toJson: (v) => v.toJson(),
    );
    assertJsonRoundtrip(
      label: 'PersistentArtifactRetentionPolicy',
      original: PersistentArtifactTestFixtures.validRetentionPolicy(),
      fromJson: PersistentArtifactRetentionPolicy.fromJson,
      toJson: (v) => v.toJson(),
    );
    assertJsonRoundtrip(
      label: 'PersistentArtifactStoragePolicy',
      original: PersistentArtifactTestFixtures.validStoragePolicy(),
      fromJson: PersistentArtifactStoragePolicy.fromJson,
      toJson: (v) => v.toJson(),
    );
    assertJsonRoundtrip(
      label: 'PersistentArtifactReplicationRequirement',
      original: PersistentArtifactTestFixtures.validReplicationRequirement(),
      fromJson: PersistentArtifactReplicationRequirement.fromJson,
      toJson: (v) => v.toJson(),
    );
    assertJsonRoundtrip(
      label: 'PersistentArtifactReplicaRecord',
      original: PersistentArtifactTestFixtures.validReplica(),
      fromJson: PersistentArtifactReplicaRecord.fromJson,
      toJson: (v) => v.toJson(),
    );
    assertJsonRoundtrip(
      label: 'PersistentArtifactAvailabilityRecord',
      original: PersistentArtifactTestFixtures.validAvailabilityRecord(),
      fromJson: PersistentArtifactAvailabilityRecord.fromJson,
      toJson: (v) => v.toJson(),
    );
    assertJsonRoundtrip(
      label: 'PersistentArtifactRetentionRecord',
      original: PersistentArtifactTestFixtures.validRetentionRecord(),
      fromJson: PersistentArtifactRetentionRecord.fromJson,
      toJson: (v) => v.toJson(),
    );
    assertJsonRoundtrip(
      label: 'PersistentArtifactDeletionRequest',
      original: PersistentArtifactTestFixtures.validDeletionRequest(),
      fromJson: PersistentArtifactDeletionRequest.fromJson,
      toJson: (v) => v.toJson(),
    );
    assertJsonRoundtrip(
      label: 'PersistentArtifactDeletionResult',
      original: PersistentArtifactTestFixtures.validDeletionResult(),
      fromJson: PersistentArtifactDeletionResult.fromJson,
      toJson: (v) => v.toJson(),
    );
    assertJsonRoundtrip(
      label: 'PersistentArtifactTombstone',
      original: PersistentArtifactTestFixtures.validTombstone(),
      fromJson: PersistentArtifactTombstone.fromJson,
      toJson: (v) => v.toJson(),
    );
    assertJsonRoundtrip(
      label: 'PersistentArtifactSourceReference',
      original: PersistentArtifactTestFixtures.validSourceReference(),
      fromJson: PersistentArtifactSourceReference.fromJson,
      toJson: (v) => v.toJson(),
    );
    assertJsonRoundtrip(
      label: 'PersistentArtifactPolicyReference',
      original: PersistentArtifactTestFixtures.validPolicyReference(),
      fromJson: PersistentArtifactPolicyReference.fromJson,
      toJson: (v) => v.toJson(),
    );
    assertJsonRoundtrip(
      label: 'PersistentArtifactOperationRequest',
      original: PersistentArtifactTestFixtures.validOperationRequest(),
      fromJson: PersistentArtifactOperationRequest.fromJson,
      toJson: (v) => v.toJson(),
    );
    assertJsonRoundtrip(
      label: 'PersistentArtifactOperationResult',
      original: PersistentArtifactTestFixtures.validOperationResult(),
      fromJson: PersistentArtifactOperationResult.fromJson,
      toJson: (v) => v.toJson(),
    );
    assertJsonRoundtrip(
      label: 'PersistentArtifactIdentity',
      original: PersistentArtifactTestFixtures.validArtifactIdentity(),
      fromJson: PersistentArtifactIdentity.fromJson,
      toJson: (v) => v.toJson(),
    );
    assertJsonRoundtrip(
      label: 'PersistentArtifactInfrastructureIdentity',
      original: PersistentArtifactTestFixtures.validInfrastructureIdentity(),
      fromJson: PersistentArtifactInfrastructureIdentity.fromJson,
      toJson: (v) => v.toJson(),
    );
    assertJsonRoundtrip(
      label: 'PersistentArtifactIssue',
      original: PersistentArtifactTestFixtures.validValidationIssue(),
      fromJson: PersistentArtifactIssue.fromJson,
      toJson: (v) => v.toJson(),
    );

    test(
        'PersistentArtifactInfrastructureSnapshot roundtrip preserves comparable json',
        () {
      final snapshot = PersistentArtifactTestFixtures.validSnapshot();
      final restored =
          PersistentArtifactInfrastructureSnapshot.fromJson(snapshot.toJson());
      expect(restored.toComparableJson(), equals(snapshot.toComparableJson()));
    });

    test('PersistentArtifactSubject copyWith updates changed field only', () {
      final original = PersistentArtifactTestFixtures.validSubject();
      final updated = original.copyWith(sourceModule: 'cryptographic-trust');
      expect(updated.sourceModule, 'cryptographic-trust');
      expect(updated, isNot(equals(original)));
    });

    test('PersistentArtifactContentDescriptor copyWith updates fingerprint',
        () {
      final original = PersistentArtifactTestFixtures.validContentDescriptor();
      const newFp =
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      final updated = original.copyWith(contentFingerprint: newFp);
      expect(updated.contentFingerprint, newFp);
      expect(updated, isNot(equals(original)));
    });

    test('PersistentArtifactVersion copyWith updates revision', () {
      final original = PersistentArtifactTestFixtures.validVersion();
      final updated = original.copyWith(revision: 2);
      expect(updated.revision, 2);
      expect(updated, isNot(equals(original)));
    });

    test('PersistentArtifactManifest equality is reflexive', () {
      final manifest = PersistentArtifactTestFixtures.validManifest();
      expect(manifest, equals(manifest));
    });

    test('PersistentArtifactIdentity hashCode stable across 5 reads', () {
      final identity = PersistentArtifactTestFixtures.validArtifactIdentity();
      final hashCodes = List.generate(5, (_) => identity.hashCode);
      expect(hashCodes.toSet(), hasLength(1));
    });

    test('PersistentArtifactManifest equal instances from json roundtrip', () {
      final a = PersistentArtifactTestFixtures.validManifest();
      final b = PersistentArtifactManifest.fromJson(a.toJson());
      expect(b, equals(a));
    });

    test('PersistentArtifactVersion createdAt excluded from comparable json',
        () {
      final version = PersistentArtifactTestFixtures.validVersion();
      expect(version.toComparableJson().containsKey('createdAt'), isFalse);
      expect(version.toJson().containsKey('createdAt'), isTrue);
    });

    test('PersistentArtifactVersion supersededAt excluded from comparable json',
        () {
      final version = PersistentArtifactTestFixtures.validVersion().copyWith(
        status: PersistentArtifactVersionStatus.superseded,
        supersededAt: '2026-08-01T00:00:00.000Z',
      );
      expect(version.toComparableJson().containsKey('supersededAt'), isFalse);
    });

    test('PersistentArtifactManifest createdAt excluded from comparable json',
        () {
      final manifest = PersistentArtifactTestFixtures.validManifest();
      expect(manifest.toComparableJson().containsKey('createdAt'), isFalse);
    });

    test(
        'PersistentArtifactIntegrityRecord verifiedAt excluded from comparable',
        () {
      final record = PersistentArtifactTestFixtures.validIntegrityRecord();
      expect(record.toComparableJson().containsKey('verifiedAt'), isFalse);
      expect(record.toJson().containsKey('verifiedAt'), isTrue);
    });

    test(
        'PersistentArtifactPublicationRecord publishedAt excluded from comparable',
        () {
      final publication = PersistentArtifactTestFixtures.validPublication();
      expect(
          publication.toComparableJson().containsKey('publishedAt'), isFalse);
    });

    test(
        'PersistentArtifactLifecycleRecord effectiveAt excluded from comparable',
        () {
      final record = PersistentArtifactTestFixtures.validLifecycleRecord();
      expect(record.toComparableJson().containsKey('effectiveAt'), isFalse);
    });

    test(
        'PersistentArtifactDeletionRequest requestedAt excluded from comparable',
        () {
      final request = PersistentArtifactTestFixtures.validDeletionRequest();
      expect(request.toComparableJson().containsKey('requestedAt'), isFalse);
    });

    test(
        'PersistentArtifactDeletionResult evaluatedAt excluded from comparable',
        () {
      final result = PersistentArtifactTestFixtures.validDeletionResult();
      expect(result.toComparableJson().containsKey('evaluatedAt'), isFalse);
    });

    test('PersistentArtifactTombstone createdAt excluded from comparable json',
        () {
      final tombstone = PersistentArtifactTestFixtures.validTombstone();
      expect(tombstone.toComparableJson().containsKey('createdAt'), isFalse);
      expect(tombstone.toComparableJson().containsKey('expiresAt'), isFalse);
    });

    test(
        'PersistentArtifactInfrastructureSnapshot timestamps excluded from comparable',
        () {
      final snapshot = PersistentArtifactTestFixtures.validSnapshot();
      final comparable = snapshot.toComparableJson();
      expect(comparable.containsKey('createdAt'), isFalse);
      expect(comparable.containsKey('evaluatedAt'), isFalse);
      expect(comparable.containsKey('publishedAt'), isFalse);
    });

    test(
        'PersistentArtifactInfrastructureSnapshot subjects list is immutable from json',
        () {
      final restored = PersistentArtifactInfrastructureSnapshot.fromJson(
        PersistentArtifactTestFixtures.validSnapshot().toJson(),
      );
      expect(
        () => restored.subjects
            .add(PersistentArtifactTestFixtures.validSubject()),
        throwsUnsupportedError,
      );
    });

    test(
        'PersistentArtifactInfrastructureSnapshot versions list is immutable from json',
        () {
      final restored = PersistentArtifactInfrastructureSnapshot.fromJson(
        PersistentArtifactTestFixtures.validSnapshot().toJson(),
      );
      expect(
        () => restored.versions
            .add(PersistentArtifactTestFixtures.validVersion()),
        throwsUnsupportedError,
      );
    });

    test(
        'PersistentArtifactInfrastructureSnapshot metadata is immutable from json',
        () {
      final restored = PersistentArtifactInfrastructureSnapshot.fromJson(
        PersistentArtifactTestFixtures.validSnapshot().toJson(),
      );
      expect(
        () => restored.metadata['new'] = 'value',
        throwsUnsupportedError,
      );
    });

    test('PersistentArtifactRetentionPolicy artifactTypes immutable from json',
        () {
      final restored = PersistentArtifactRetentionPolicy.fromJson(
        PersistentArtifactTestFixtures.validRetentionPolicy().toJson(),
      );
      expect(
        () => restored.artifactTypes.add(PersistentArtifactType.generic),
        throwsUnsupportedError,
      );
    });

    test(
        'PersistentArtifactOperationRequest artifactSubjects immutable from json',
        () {
      final restored = PersistentArtifactOperationRequest.fromJson(
        PersistentArtifactTestFixtures.validOperationRequest().toJson(),
      );
      expect(
        () => restored.artifactSubjects.add(
          PersistentArtifactTestFixtures.validSubject(),
        ),
        throwsUnsupportedError,
      );
    });

    test(
        'PersistentArtifactReplicaRecord replicatedAt excluded from comparable',
        () {
      final replica = PersistentArtifactTestFixtures.validReplica();
      expect(replica.toComparableJson().containsKey('replicatedAt'), isFalse);
    });

    test(
        'PersistentArtifactAvailabilityRecord checkedAt excluded from comparable',
        () {
      final record = PersistentArtifactTestFixtures.validAvailabilityRecord();
      expect(record.toComparableJson().containsKey('checkedAt'), isFalse);
    });

    test(
        'PersistentArtifactRetentionRecord evaluatedAt excluded from comparable',
        () {
      final record = PersistentArtifactTestFixtures.validRetentionRecord();
      expect(record.toComparableJson().containsKey('evaluatedAt'), isFalse);
      expect(record.toComparableJson().containsKey('retainUntil'), isFalse);
    });

    test(
        'PersistentArtifactOperationRequest requestedAt excluded from comparable',
        () {
      final request = PersistentArtifactTestFixtures.validOperationRequest();
      expect(request.toComparableJson().containsKey('requestedAt'), isFalse);
    });

    test(
        'PersistentArtifactOperationResult completedAt excluded from comparable',
        () {
      final result = PersistentArtifactTestFixtures.validOperationResult();
      expect(result.toComparableJson().containsKey('completedAt'), isFalse);
    });
  });
}
