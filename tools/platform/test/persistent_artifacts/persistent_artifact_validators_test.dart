import 'package:masterpalm_platform/models/persistent_artifacts/persistent_artifact_deletion_models.dart';
import 'package:masterpalm_platform/models/persistent_artifacts/persistent_artifact_enums.dart';
import 'package:masterpalm_platform/models/persistent_artifacts/persistent_artifact_validation_result.dart';
import 'package:masterpalm_platform/persistent_artifacts/persistent_artifact_validators.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_test_fixtures.dart';

void main() {
  group('Persistent Artifact validators', () {
    test('subject validator accepts valid subject', () {
      final result = const PersistentArtifactSubjectValidator().validate(
        PersistentArtifactTestFixtures.validSubject(),
      );
      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('subject validator rejects empty subjectId with PA_SUBJECT_ID', () {
      final subject =
          PersistentArtifactTestFixtures.validSubject().copyWith(subjectId: '');
      final result =
          const PersistentArtifactSubjectValidator().validate(subject);
      expect(result.isValid, isFalse);
      final issue = result.issues.firstWhere((i) => i.code == 'PA_SUBJECT_ID');
      expect(issue.path, 'subjectId');
      expect(issue.severity, PersistentArtifactIssueSeverity.critical);
    });

    test('subject validator rejects sensitive metadata', () {
      final subject = PersistentArtifactTestFixtures.validSubject().copyWith(
        metadata: const {'apiToken': 'must-not-appear'},
      );
      final result =
          const PersistentArtifactSubjectValidator().validate(subject);
      expect(result.isValid, isFalse);
      expect(
        result.issues.any((i) => i.code == 'PA_SENSITIVE_METADATA'),
        isTrue,
      );
    });

    test('subject validator issues sorted by code', () {
      final subject = PersistentArtifactTestFixtures.validSubject().copyWith(
        subjectId: '',
        projectId: '',
      );
      final result =
          const PersistentArtifactSubjectValidator().validate(subject);
      final codes = result.issues.map((i) => i.code).toList();
      expect(codes, equals(List<String>.from(codes)..sort()));
    });

    test('content descriptor validator accepts valid descriptor', () {
      final result =
          const PersistentArtifactContentDescriptorValidator().validate(
        PersistentArtifactTestFixtures.validContentDescriptor(),
      );
      expect(result.isValid, isTrue);
    });

    test('content descriptor validator rejects empty contentId', () {
      final content = PersistentArtifactTestFixtures.validContentDescriptor()
          .copyWith(contentId: '');
      final result = const PersistentArtifactContentDescriptorValidator()
          .validate(content);
      expect(result.isValid, isFalse);
      expect(
        result.issues.any((i) => i.code == 'PA_CONTENT_ID'),
        isTrue,
      );
      expect(
        result.issues.firstWhere((i) => i.code == 'PA_CONTENT_ID').path,
        'contentId',
      );
    });

    test('content descriptor validator rejects negative sizeBytes', () {
      final content = PersistentArtifactTestFixtures.validContentDescriptor()
          .copyWith(sizeBytes: -1);
      final result = const PersistentArtifactContentDescriptorValidator()
          .validate(content);
      expect(result.isValid, isFalse);
      expect(
        result.issues.any((i) => i.code == 'PA_CONTENT_SIZE_BYTES'),
        isTrue,
      );
    });

    test('content descriptor validator rejects invalid canonicalDigest', () {
      final content = PersistentArtifactTestFixtures.validContentDescriptor()
          .copyWith(canonicalDigest: 'not-hex');
      final result = const PersistentArtifactContentDescriptorValidator()
          .validate(content);
      expect(result.isValid, isFalse);
      expect(
        result.issues.any((i) => i.code == 'PA_CONTENT_CANONICAL_DIGEST'),
        isTrue,
      );
    });

    test('location validator accepts valid location', () {
      final result = const PersistentArtifactLocationValidator().validate(
        PersistentArtifactTestFixtures.validLocation(),
      );
      expect(result.isValid, isTrue);
    });

    test('location validator rejects empty locationId', () {
      final location = PersistentArtifactTestFixtures.validLocation()
          .copyWith(locationId: '');
      final result =
          const PersistentArtifactLocationValidator().validate(location);
      expect(result.isValid, isFalse);
      expect(
        result.issues.any((i) => i.code == 'PA_LOCATION_ID'),
        isTrue,
      );
    });

    test('location validator rejects presigned metadata value', () {
      final location = PersistentArtifactTestFixtures.validLocation().copyWith(
        metadata: const {
          'downloadUrl':
              'https://storage.example.com/obj?sig=abc&expires=1234567890',
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

    test('version validator accepts valid version', () {
      final result = const PersistentArtifactVersionValidator().validate(
        PersistentArtifactTestFixtures.validVersion(),
      );
      expect(result.isValid, isTrue);
    });

    test('version validator rejects revision below 1', () {
      final version =
          PersistentArtifactTestFixtures.validVersion().copyWith(revision: 0);
      final result =
          const PersistentArtifactVersionValidator().validate(version);
      expect(result.isValid, isFalse);
      expect(
        result.issues.any((i) => i.code == 'PA_VERSION_REVISION'),
        isTrue,
      );
    });

    test('version validator rejects parentVersionId equal to versionId', () {
      final version = PersistentArtifactTestFixtures.validVersion().copyWith(
        parentVersionId: PersistentArtifactTestFixtures.versionId,
      );
      final result =
          const PersistentArtifactVersionValidator().validate(version);
      expect(result.isValid, isFalse);
      expect(
        result.issues.any((i) => i.code == 'PA_VERSION_PARENT_SELF'),
        isTrue,
      );
    });

    test('version validator reports multiple issues deterministically', () {
      final version = PersistentArtifactTestFixtures.validVersion().copyWith(
        revision: 0,
        artifactId: '',
      );
      final result =
          const PersistentArtifactVersionValidator().validate(version);
      expect(result.issues.length, greaterThan(1));
      final codes = result.issues.map((i) => i.code).toList();
      expect(codes, equals(List<String>.from(codes)..sort()));
    });

    test('manifest validator accepts valid manifest', () {
      final result = const PersistentArtifactManifestValidator().validate(
        PersistentArtifactTestFixtures.validManifest(),
      );
      expect(result.isValid, isTrue);
    });

    test('manifest validator rejects empty manifestId', () {
      final manifest = PersistentArtifactTestFixtures.validManifest()
          .copyWith(manifestId: '');
      final result =
          const PersistentArtifactManifestValidator().validate(manifest);
      expect(result.isValid, isFalse);
      expect(
        result.issues.any((i) => i.code == 'PA_MANIFEST_ID'),
        isTrue,
      );
    });

    test('manifest validator rejects duplicate locationId', () {
      final location = PersistentArtifactTestFixtures.validLocation();
      final manifest = PersistentArtifactTestFixtures.validManifest().copyWith(
        locations: [location, location],
      );
      final result =
          const PersistentArtifactManifestValidator().validate(manifest);
      expect(result.isValid, isFalse);
      expect(
        result.issues.any((i) => i.code == 'PA_MANIFEST_DUPLICATE_LOCATION'),
        isTrue,
      );
    });

    test('integrity validator accepts valid record', () {
      final result = const PersistentArtifactIntegrityValidator().validate(
        PersistentArtifactTestFixtures.validIntegrityRecord(),
      );
      expect(result.isValid, isTrue);
    });

    test('integrity validator rejects empty digestValue', () {
      final record = PersistentArtifactTestFixtures.validIntegrityRecord()
          .copyWith(digestValue: '');
      final result =
          const PersistentArtifactIntegrityValidator().validate(record);
      expect(result.isValid, isFalse);
      expect(
        result.issues.any((i) => i.code == 'PA_INTEGRITY_DIGEST_VALUE'),
        isTrue,
      );
    });

    test('encryption descriptor validator accepts none status', () {
      final result = const PersistentArtifactEncryptionDescriptorValidator()
          .validate(PersistentArtifactTestFixtures.validEncryptionDescriptor());
      expect(result.isValid, isTrue);
    });

    test('encryption descriptor validator rejects declared without algorithmId',
        () {
      final descriptor =
          PersistentArtifactTestFixtures.validEncryptionDescriptor().copyWith(
        encryptionStatus: PersistentArtifactEncryptionStatus.declared,
        algorithmId: null,
      );
      final result =
          const PersistentArtifactEncryptionDescriptorValidator().validate(
        descriptor,
      );
      expect(result.isValid, isFalse);
      expect(
        result.issues.any((i) => i.code == 'PA_ENCRYPTION_ALGORITHM_ID'),
        isTrue,
      );
    });

    test('publication validator accepts valid publication', () {
      final result = const PersistentArtifactPublicationValidator().validate(
        PersistentArtifactTestFixtures.validPublication(),
      );
      expect(result.isValid, isTrue);
    });

    test('publication validator rejects published without locations', () {
      final publication =
          PersistentArtifactTestFixtures.validPublication().copyWith(
        publishedLocations: const [],
      );
      final result =
          const PersistentArtifactPublicationValidator().validate(publication);
      expect(result.isValid, isFalse);
      expect(
        result.issues.any((i) => i.code == 'PA_PUBLICATION_LOCATIONS'),
        isTrue,
      );
    });

    test('publication validator rejects release authorization metadata', () {
      final publication =
          PersistentArtifactTestFixtures.validPublication().copyWith(
        metadata: const {'releaseAuthorized': 'true'},
      );
      final result =
          const PersistentArtifactPublicationValidator().validate(publication);
      expect(result.isValid, isFalse);
      expect(
        result.issues.any(
          (i) => i.code == 'PA_RELEASE_AUTHORIZATION_METADATA',
        ),
        isTrue,
      );
    });

    test('lifecycle validator accepts valid transition', () {
      final result = const PersistentArtifactLifecycleValidator().validate(
        PersistentArtifactTestFixtures.validLifecycleRecord(),
      );
      expect(result.isValid, isTrue);
    });

    test('lifecycle validator rejects backward transition', () {
      final record =
          PersistentArtifactTestFixtures.validLifecycleRecord().copyWith(
        lifecycleStatus: PersistentArtifactLifecycleStatus.created,
        previousStatus: PersistentArtifactLifecycleStatus.published,
      );
      final result =
          const PersistentArtifactLifecycleValidator().validate(record);
      expect(result.isValid, isFalse);
      expect(
        result.issues.any((i) => i.code == 'PA_LIFECYCLE_TRANSITION_BACKWARD'),
        isTrue,
      );
    });

    test('retention policy validator accepts valid policy', () {
      final result =
          const PersistentArtifactRetentionPolicyValidator().validate(
        PersistentArtifactTestFixtures.validRetentionPolicy(),
      );
      expect(result.isValid, isTrue);
    });

    test('retention policy validator rejects empty artifactTypes', () {
      final policy = PersistentArtifactTestFixtures.validRetentionPolicy()
          .copyWith(artifactTypes: const []);
      final result =
          const PersistentArtifactRetentionPolicyValidator().validate(policy);
      expect(result.isValid, isFalse);
      expect(
        result.issues
            .any((i) => i.code == 'PA_RETENTION_POLICY_ARTIFACT_TYPES'),
        isTrue,
      );
    });

    test('storage policy validator accepts valid policy', () {
      final result = const PersistentArtifactStoragePolicyValidator().validate(
        PersistentArtifactTestFixtures.validStoragePolicy(),
      );
      expect(result.isValid, isTrue);
    });

    test('storage policy validator rejects empty allowedLocationTypes', () {
      final policy = PersistentArtifactTestFixtures.validStoragePolicy()
          .copyWith(allowedLocationTypes: const []);
      final result =
          const PersistentArtifactStoragePolicyValidator().validate(policy);
      expect(result.isValid, isFalse);
      expect(
        result.issues.any((i) => i.code == 'PA_STORAGE_POLICY_LOCATION_TYPES'),
        isTrue,
      );
    });

    test('replication requirement validator accepts valid requirement', () {
      final result =
          const PersistentArtifactReplicationRequirementValidator().validate(
        PersistentArtifactTestFixtures.validReplicationRequirement(),
      );
      expect(result.isValid, isTrue);
    });

    test('replication requirement validator rejects domain count mismatch', () {
      final requirement =
          PersistentArtifactTestFixtures.validReplicationRequirement().copyWith(
        minimumReplicaCount: 1,
        distinctFailureDomains: 2,
      );
      final result =
          const PersistentArtifactReplicationRequirementValidator().validate(
        requirement,
      );
      expect(result.isValid, isFalse);
      expect(
        result.issues.any((i) => i.code == 'PA_REPLICATION_DOMAIN_COUNT'),
        isTrue,
      );
    });

    test('replica validator accepts valid replica', () {
      final result = const PersistentArtifactReplicaValidator().validate(
        PersistentArtifactTestFixtures.validReplica(),
      );
      expect(result.isValid, isTrue);
    });

    test('replica validator rejects fingerprint mismatch', () {
      final replica = PersistentArtifactTestFixtures.validReplica().copyWith(
        contentFingerprint:
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      );
      final result =
          const PersistentArtifactReplicaValidator().validate(replica);
      expect(result.isValid, isFalse);
      expect(
        result.issues.any((i) => i.code == 'PA_REPLICA_FINGERPRINT_MISMATCH'),
        isTrue,
      );
    });

    test('availability validator accepts available status', () {
      final result = const PersistentArtifactAvailabilityValidator().validate(
        PersistentArtifactTestFixtures.validAvailabilityRecord(),
      );
      expect(result.isValid, isTrue);
    });

    test('availability validator rejects partial without locationId', () {
      final record =
          PersistentArtifactTestFixtures.validAvailabilityRecord().copyWith(
        status: PersistentArtifactAvailabilityStatus.partial,
        locationId: null,
      );
      final result =
          const PersistentArtifactAvailabilityValidator().validate(record);
      expect(result.isValid, isFalse);
      expect(
        result.issues.any((i) => i.code == 'PA_AVAILABILITY_LOCATION_ID'),
        isTrue,
      );
    });

    test('retention record validator accepts valid record', () {
      final result =
          const PersistentArtifactRetentionRecordValidator().validate(
        PersistentArtifactTestFixtures.validRetentionRecord(),
      );
      expect(result.isValid, isTrue);
    });

    test('retention record validator rejects legalHold status mismatch', () {
      final record =
          PersistentArtifactTestFixtures.validRetentionRecord().copyWith(
        legalHold: true,
        status: PersistentArtifactRetentionRecordStatus.active,
      );
      final result =
          const PersistentArtifactRetentionRecordValidator().validate(record);
      expect(result.isValid, isFalse);
      expect(
        result.issues.any((i) => i.code == 'PA_RETENTION_LEGAL_HOLD_STATUS'),
        isTrue,
      );
    });

    test('deletion request validator accepts valid request', () {
      final result =
          const PersistentArtifactDeletionRequestValidator().validate(
        PersistentArtifactTestFixtures.validDeletionRequest(),
      );
      expect(result.isValid, isTrue);
    });

    test('deletion request validator blocks when legal hold active', () {
      final request = PersistentArtifactTestFixtures.validDeletionRequest();
      final result =
          const PersistentArtifactDeletionRequestValidator().validate(
        request,
        legalHoldActive: true,
      );
      expect(result.isValid, isFalse);
      expect(
        result.issues.any((i) => i.code == 'PA_DELETION_REQUEST_LEGAL_HOLD'),
        isTrue,
      );
    });

    test('deletion result validator accepts valid result', () {
      final result = const PersistentArtifactDeletionResultValidator().validate(
        PersistentArtifactTestFixtures.validDeletionResult(),
        knownTombstoneIds: {PersistentArtifactTestFixtures.tombstoneId},
      );
      expect(result.isValid, isTrue);
    });

    test('deletion result validator rejects completed without tombstoneId', () {
      final deletionResult = PersistentArtifactDeletionResult(
        deletionResultId: PersistentArtifactTestFixtures.deletionResultId,
        deletionRequestId: PersistentArtifactTestFixtures.deletionRequestId,
        artifactId: PersistentArtifactTestFixtures.artifactId,
        versionId: PersistentArtifactTestFixtures.versionId,
        status: PersistentArtifactDeletionStatus.completed,
      );
      final result = const PersistentArtifactDeletionResultValidator().validate(
        deletionResult,
      );
      expect(result.isValid, isFalse);
      expect(
        result.issues.any((i) => i.code == 'PA_DELETION_RESULT_TOMBSTONE'),
        isTrue,
      );
    });

    test('tombstone validator accepts valid tombstone', () {
      final result = const PersistentArtifactTombstoneValidator().validate(
        PersistentArtifactTestFixtures.validTombstone(),
        knownDeletionRequestIds: {
          PersistentArtifactTestFixtures.deletionRequestId,
        },
      );
      expect(result.isValid, isTrue);
    });

    test('tombstone validator rejects unknown deletionRequestId', () {
      final tombstone = PersistentArtifactTestFixtures.validTombstone();
      final result = const PersistentArtifactTombstoneValidator().validate(
        tombstone,
        knownDeletionRequestIds: const {'other-request'},
      );
      expect(result.isValid, isFalse);
      expect(
        result.issues.any((i) => i.code == 'PA_TOMBSTONE_DELETION_REFERENCE'),
        isTrue,
      );
    });

    test('operation request validator accepts valid request', () {
      final result =
          const PersistentArtifactOperationRequestValidator().validate(
        PersistentArtifactTestFixtures.validOperationRequest(),
      );
      expect(result.isValid, isTrue);
    });

    test('operation request validator rejects empty targets', () {
      final request =
          PersistentArtifactTestFixtures.validOperationRequest().copyWith(
        artifactSubjects: const [],
        artifactIds: const [],
        versionIds: const [],
      );
      final result =
          const PersistentArtifactOperationRequestValidator().validate(request);
      expect(result.isValid, isFalse);
      expect(
        result.issues.any((i) => i.code == 'PA_OPERATION_REQUEST_TARGETS'),
        isTrue,
      );
    });

    test('operation result validator accepts valid result', () {
      final result =
          const PersistentArtifactOperationResultValidator().validate(
        PersistentArtifactTestFixtures.validOperationResult(),
        expectedRequestId: PersistentArtifactTestFixtures.operationRequestId,
        expectedProjectId: PersistentArtifactTestFixtures.projectId,
      );
      expect(result.isValid, isTrue);
    });

    test('operation result validator rejects succeeded without artifactResults',
        () {
      final operationResult =
          PersistentArtifactTestFixtures.validOperationResult().copyWith(
        artifactResults: const [],
      );
      final result =
          const PersistentArtifactOperationResultValidator().validate(
        operationResult,
      );
      expect(result.isValid, isFalse);
      expect(
        result.issues
            .any((i) => i.code == 'PA_OPERATION_RESULT_ARTIFACT_RESULTS'),
        isTrue,
      );
    });

    test('infrastructure snapshot validator accepts valid snapshot', () {
      final result =
          const PersistentArtifactInfrastructureSnapshotValidator().validate(
        PersistentArtifactTestFixtures.validSnapshot(),
      );
      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('infrastructure snapshot validator rejects empty projectId', () {
      final snapshot = PersistentArtifactTestFixtures.validSnapshot()
          .copyWith(projectId: '');
      final result =
          const PersistentArtifactInfrastructureSnapshotValidator().validate(
        snapshot,
      );
      expect(result.isValid, isFalse);
      expect(
        result.issues.any((i) => i.code == 'PA_SNAPSHOT_PROJECT_ID'),
        isTrue,
      );
    });

    test('infrastructure snapshot validator rejects incoherent timestamps', () {
      final snapshot = PersistentArtifactTestFixtures.validSnapshot().copyWith(
        createdAt: '2026-08-01T00:00:00.000Z',
        evaluatedAt: '2026-07-01T00:00:00.000Z',
      );
      final result =
          const PersistentArtifactInfrastructureSnapshotValidator().validate(
        snapshot,
      );
      expect(result.isValid, isFalse);
      expect(
        result.issues.any((i) => i.code == 'PA_SNAPSHOT_EVALUATED_AT'),
        isTrue,
      );
    });

    test('infrastructure snapshot validator issues sorted by code', () {
      final snapshot = PersistentArtifactTestFixtures.validSnapshot().copyWith(
        projectId: '',
        createdAt: '',
      );
      final result =
          const PersistentArtifactInfrastructureSnapshotValidator().validate(
        snapshot,
      );
      final codes = result.issues.map((i) => i.code).toList();
      expect(codes, equals(List<String>.from(codes)..sort()));
    });
  });
}
