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

/// Shared fixtures for Persistent Artifact Infrastructure domain tests.
class PersistentArtifactTestFixtures {
  static const projectId = 'masterpalm-demo';
  static const referenceTime = '2026-07-22T12:00:00.000Z';
  static const sha256Placeholder =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  static const releaseId = 'rel-2026-07-22-001';

  static const artifactId = 'art-pa-001';
  static const versionId = 'ver-pa-001';
  static const subjectId = 'subject-pa-001';
  static const contentId = 'content-pa-001';
  static const locationId = 'loc-pa-001';
  static const manifestId = 'manifest-pa-001';
  static const integrityRecordId = 'integrity-pa-001';
  static const publicationId = 'pub-pa-001';
  static const lifecycleRecordId = 'lifecycle-pa-001';
  static const retentionPolicyId = 'retention-policy-pa-001';
  static const storagePolicyId = 'storage-policy-pa-001';
  static const requirementId = 'repl-req-pa-001';
  static const replicaId = 'replica-pa-001';
  static const availabilityRecordId = 'avail-pa-001';
  static const retentionRecordId = 'retention-rec-pa-001';
  static const deletionRequestId = 'del-req-pa-001';
  static const deletionResultId = 'del-res-pa-001';
  static const tombstoneId = 'tombstone-pa-001';
  static const operationRequestId = 'op-req-pa-001';
  static const operationResultId = 'op-res-pa-001';
  static const infrastructureId = 'pai-infra-001';
  static const sourceId = 'src-evidence-pa-001';

  static PersistentArtifactSubject validSubject() {
    return PersistentArtifactSubject(
      subjectId: subjectId,
      artifactType: PersistentArtifactType.releaseEvidence,
      projectId: projectId,
      releaseId: releaseId,
      sourceModule: 'release-evidence',
      sourceId: sourceId,
      sourceFingerprint: sha256Placeholder,
      contentType: 'application/json',
      schemaVersion: '1',
      metadata: const {'channel': 'staging'},
    );
  }

  static PersistentArtifactContentDescriptor validContentDescriptor() {
    return PersistentArtifactContentDescriptor(
      contentId: contentId,
      mediaType: 'application/json',
      format: PersistentArtifactFormat.json,
      encoding: PersistentArtifactEncoding.utf8,
      compression: PersistentArtifactCompression.none,
      contentFingerprint: sha256Placeholder,
      sizeBytes: 1024,
      canonicalDigest: sha256Placeholder,
      schemaVersion: '1',
      metadata: const {'projectId': projectId},
    );
  }

  static PersistentArtifactLocationReference validLocation() {
    return PersistentArtifactLocationReference(
      locationId: locationId,
      locationType: PersistentArtifactLocationType.objectStore,
      storageProviderId: 'gcs-provider',
      storageNamespace: 'pa-demo',
      objectKey: 'artifacts/$artifactId/$versionId/content.json',
      region: 'us-central1',
      storageClass: PersistentArtifactStorageClass.standard,
      accessScope: PersistentArtifactAccessScope.project,
      contentFingerprint: sha256Placeholder,
      metadata: const {'tier': 'primary'},
    );
  }

  static PersistentArtifactVersion validVersion() {
    return PersistentArtifactVersion(
      artifactId: artifactId,
      versionId: versionId,
      revision: 1,
      status: PersistentArtifactVersionStatus.active,
      contentDescriptor: validContentDescriptor(),
      createdAt: referenceTime,
      sourceReferences: [validSourceReference()],
      metadata: const {'projectId': projectId},
    );
  }

  static PersistentArtifactIntegrityRecord validIntegrityRecord() {
    return PersistentArtifactIntegrityRecord(
      integrityRecordId: integrityRecordId,
      artifactId: artifactId,
      versionId: versionId,
      digestAlgorithmId: 'sha256-v1',
      digestValue: sha256Placeholder,
      contentFingerprint: sha256Placeholder,
      status: PersistentArtifactIntegrityStatus.verified,
      verifiedAt: referenceTime,
      metadata: const {'algorithm': 'sha256'},
    );
  }

  static PersistentArtifactManifest validManifest() {
    return PersistentArtifactManifest(
      manifestId: manifestId,
      artifactId: artifactId,
      versionId: versionId,
      subject: validSubject(),
      contentDescriptor: validContentDescriptor(),
      locations: [validLocation()],
      integrityRecords: [validIntegrityRecord()],
      sourceReferences: [validSourceReference()],
      policyReferences: [validPolicyReference()],
      createdAt: referenceTime,
      metadata: const {'projectId': projectId},
    );
  }

  static PersistentArtifactEncryptionDescriptor validEncryptionDescriptor() {
    return const PersistentArtifactEncryptionDescriptor(
      encryptionStatus: PersistentArtifactEncryptionStatus.none,
      metadata: {'mode': 'structural-descriptor-only'},
    );
  }

  static PersistentArtifactPublicationRecord validPublication() {
    return PersistentArtifactPublicationRecord(
      publicationId: publicationId,
      artifactId: artifactId,
      versionId: versionId,
      publicationStatus: PersistentArtifactPublicationStatus.published,
      publishedLocations: [validLocation()],
      publishedAt: referenceTime,
      publisherIdentityId: 'publisher-001',
      sourceReferences: [validSourceReference()],
      metadata: const {'limitations': 'no-release-authorization'},
    );
  }

  static PersistentArtifactLifecycleRecord validLifecycleRecord() {
    return PersistentArtifactLifecycleRecord(
      lifecycleRecordId: lifecycleRecordId,
      artifactId: artifactId,
      versionId: versionId,
      lifecycleStatus: PersistentArtifactLifecycleStatus.published,
      effectiveAt: referenceTime,
      previousStatus: PersistentArtifactLifecycleStatus.created,
      reasonCode: 'initial-publication',
      policyId: retentionPolicyId,
      metadata: const {'projectId': projectId},
    );
  }

  static PersistentArtifactRetentionPolicy validRetentionPolicy() {
    return PersistentArtifactRetentionPolicy(
      policyId: retentionPolicyId,
      version: 1,
      name: 'Default Retention Policy',
      description: 'Retention policy fixture for persistent artifact tests.',
      status: PersistentArtifactPolicyStatus.active,
      artifactTypes: const [PersistentArtifactType.releaseEvidence],
      minimumRetention: 'P30D',
      retentionAction: PersistentArtifactRetentionAction.retain,
      legalHoldRequired: false,
      immutableUntilExpiration: false,
      scope: const {'domain': 'persistent-artifacts'},
      effectiveFrom: '2026-01-01T00:00:00.000Z',
      metadata: const {'projectId': projectId},
    );
  }

  static PersistentArtifactStoragePolicy validStoragePolicy() {
    return PersistentArtifactStoragePolicy(
      policyId: storagePolicyId,
      version: 1,
      name: 'Default Storage Policy',
      description: 'Storage policy fixture for persistent artifact tests.',
      status: PersistentArtifactPolicyStatus.active,
      allowedLocationTypes: const [PersistentArtifactLocationType.objectStore],
      allowedStorageClasses: const [PersistentArtifactStorageClass.standard],
      minimumDurability: PersistentArtifactDurabilityLevel.standard,
      consistencyModel: PersistentArtifactConsistencyModel.strong,
      minimumReplicaCount: 1,
      requireEncryption: false,
      requireIntegrityRecord: true,
      requireCryptographicTrust: false,
      allowedRegions: const ['us-central1'],
      constraints: const {'maxObjectSize': '100MB'},
      metadata: const {'projectId': projectId},
    );
  }

  static PersistentArtifactReplicationRequirement
      validReplicationRequirement() {
    return PersistentArtifactReplicationRequirement(
      requirementId: requirementId,
      artifactId: artifactId,
      minimumReplicaCount: 2,
      distinctFailureDomains: 2,
      allowedRegions: const ['us-central1', 'europe-west1'],
      requiredStorageClasses: const [PersistentArtifactStorageClass.standard],
      durabilityLevel: PersistentArtifactDurabilityLevel.standard,
      consistencyModel: PersistentArtifactConsistencyModel.strong,
      required: true,
      metadata: const {'projectId': projectId},
    );
  }

  static PersistentArtifactReplicaRecord validReplica() {
    return PersistentArtifactReplicaRecord(
      replicaId: replicaId,
      artifactId: artifactId,
      versionId: versionId,
      locationReference: validLocation(),
      status: PersistentArtifactReplicationStatus.declared,
      contentFingerprint: sha256Placeholder,
      replicatedAt: referenceTime,
      metadata: const {'domain': 'us-central1'},
    );
  }

  static PersistentArtifactAvailabilityRecord validAvailabilityRecord() {
    return PersistentArtifactAvailabilityRecord(
      availabilityRecordId: availabilityRecordId,
      artifactId: artifactId,
      versionId: versionId,
      status: PersistentArtifactAvailabilityStatus.available,
      checkedAt: referenceTime,
      metadata: const {'projectId': projectId},
    );
  }

  static PersistentArtifactRetentionRecord validRetentionRecord() {
    return PersistentArtifactRetentionRecord(
      retentionRecordId: retentionRecordId,
      artifactId: artifactId,
      versionId: versionId,
      policyId: retentionPolicyId,
      legalHold: false,
      status: PersistentArtifactRetentionRecordStatus.active,
      evaluatedAt: referenceTime,
      retainUntil: '2027-07-22T12:00:00.000Z',
      metadata: const {'projectId': projectId},
    );
  }

  static PersistentArtifactDeletionRequest validDeletionRequest() {
    return PersistentArtifactDeletionRequest(
      deletionRequestId: deletionRequestId,
      artifactId: artifactId,
      versionId: versionId,
      reasonCode: 'retention-expired',
      requestedAt: referenceTime,
      force: false,
      metadata: const {'projectId': projectId},
    );
  }

  static PersistentArtifactDeletionResult validDeletionResult() {
    return PersistentArtifactDeletionResult(
      deletionResultId: deletionResultId,
      deletionRequestId: deletionRequestId,
      artifactId: artifactId,
      versionId: versionId,
      status: PersistentArtifactDeletionStatus.completed,
      tombstoneId: tombstoneId,
      evaluatedAt: referenceTime,
      metadata: const {'projectId': projectId},
    );
  }

  static PersistentArtifactTombstone validTombstone() {
    return PersistentArtifactTombstone(
      tombstoneId: tombstoneId,
      artifactId: artifactId,
      versionId: versionId,
      previousContentFingerprint: sha256Placeholder,
      deletionRequestId: deletionRequestId,
      deletionStatus: PersistentArtifactDeletionStatus.completed,
      createdAt: referenceTime,
      expiresAt: '2027-07-22T12:00:00.000Z',
      reasonCode: 'retention-expired',
      sourceReferences: [validSourceReference()],
      metadata: const {'projectId': projectId},
    );
  }

  static PersistentArtifactSourceReference validSourceReference() {
    return PersistentArtifactSourceReference(
      sourceType: PersistentArtifactSourceType.releaseEvidence,
      sourceId: sourceId,
      projectId: projectId,
      releaseId: releaseId,
      fingerprint: sha256Placeholder,
      version: '1',
      metadata: const {'module': 'release-evidence'},
    );
  }

  static PersistentArtifactPolicyReference validPolicyReference() {
    return PersistentArtifactPolicyReference(
      policyId: storagePolicyId,
      policyVersion: 1,
      policyType: PersistentArtifactPolicyType.storage,
      policyFingerprint: sha256Placeholder,
      status: PersistentArtifactPolicyStatus.active,
      metadata: const {'projectId': projectId},
    );
  }

  static PersistentArtifactItemResult validItemResult() {
    return PersistentArtifactItemResult(
      artifactId: artifactId,
      versionId: versionId,
      status: PersistentArtifactOperationStatus.succeeded,
      locationResults: const [
        PersistentArtifactLocationResult(
          locationId: locationId,
          status: PersistentArtifactOperationStatus.succeeded,
        ),
      ],
      metadata: const {'projectId': projectId},
    );
  }

  static PersistentArtifactOperationRequest validOperationRequest() {
    return PersistentArtifactOperationRequest(
      requestId: operationRequestId,
      operationType: PersistentArtifactOperationType.persist,
      projectId: projectId,
      releaseId: releaseId,
      requestedAt: referenceTime,
      artifactSubjects: [validSubject()],
      policyReferences: [validPolicyReference()],
      metadata: const {'limitations': 'structural-descriptor-only'},
    );
  }

  static PersistentArtifactOperationResult validOperationResult() {
    return PersistentArtifactOperationResult(
      resultId: operationResultId,
      requestId: operationRequestId,
      operationType: PersistentArtifactOperationType.persist,
      projectId: projectId,
      releaseId: releaseId,
      status: PersistentArtifactOperationStatus.succeeded,
      artifactResults: [validItemResult()],
      completedAt: referenceTime,
      metadata: const {'limitations': 'no-release-authorization'},
    );
  }

  static PersistentArtifactIdentity validArtifactIdentity() {
    return PersistentArtifactIdentity(
      artifactId: artifactId,
      subjectFingerprint: sha256Placeholder,
      contentFingerprint: sha256Placeholder,
      manifestFingerprint: sha256Placeholder,
      versionFingerprint: sha256Placeholder,
      lifecycleFingerprint: sha256Placeholder,
      policyFingerprint: sha256Placeholder,
      snapshotFingerprint: sha256Placeholder,
    );
  }

  static PersistentArtifactInfrastructureIdentity
      validInfrastructureIdentity() {
    return PersistentArtifactInfrastructureIdentity(
      persistentArtifactInfrastructureId: infrastructureId,
      subjectsFingerprint: sha256Placeholder,
      contentsFingerprint: sha256Placeholder,
      manifestsFingerprint: sha256Placeholder,
      locationsFingerprint: sha256Placeholder,
      versionsFingerprint: sha256Placeholder,
      lifecycleFingerprint: sha256Placeholder,
      policiesFingerprint: sha256Placeholder,
      replicationFingerprint: sha256Placeholder,
      operationsFingerprint: sha256Placeholder,
      snapshotFingerprint: sha256Placeholder,
    );
  }

  static PersistentArtifactIssue validValidationIssue() {
    return const PersistentArtifactIssue(
      code: 'PA_SAMPLE',
      path: 'sample.path',
      severity: PersistentArtifactIssueSeverity.warning,
      message: 'Sample validation issue',
      artifactId: artifactId,
    );
  }

  static PersistentArtifactValidationResult validValidationResult() {
    return PersistentArtifactValidationResult(
      isValid: false,
      issues: [validValidationIssue()],
      warnings: const ['sample warning'],
      errors: const ['sample error'],
    );
  }

  static PersistentArtifactInfrastructureSnapshot validSnapshot() {
    return PersistentArtifactInfrastructureSnapshot(
      projectId: projectId,
      releaseId: releaseId,
      status: PersistentArtifactInfrastructureStatus.evaluated,
      createdAt: referenceTime,
      evaluatedAt: referenceTime,
      publishedAt: referenceTime,
      subjects: [validSubject()],
      contentDescriptors: [validContentDescriptor()],
      artifactIdentities: [validArtifactIdentity()],
      versions: [validVersion()],
      manifests: [validManifest()],
      locations: [validLocation()],
      integrityRecords: [validIntegrityRecord()],
      encryptionDescriptors: [validEncryptionDescriptor()],
      publications: [validPublication()],
      lifecycleRecords: [validLifecycleRecord()],
      retentionPolicies: [validRetentionPolicy()],
      storagePolicies: [validStoragePolicy()],
      replicationRequirements: [validReplicationRequirement()],
      replicas: [validReplica()],
      availabilityRecords: [validAvailabilityRecord()],
      retentionRecords: [validRetentionRecord()],
      deletionRequests: [validDeletionRequest()],
      deletionResults: [validDeletionResult()],
      tombstones: [validTombstone()],
      sourceReferences: [validSourceReference()],
      policyReferences: [validPolicyReference()],
      operationRequests: [validOperationRequest()],
      operationResults: [validOperationResult()],
      identity: validInfrastructureIdentity(),
      metadata: const {
        'limitations': 'structural-descriptor-only,no-release-authorization',
      },
    );
  }
}
