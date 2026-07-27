import '../../models/persistent_artifacts/cloud/persistent_artifact_cloud_enums.dart';
import '../../models/persistent_artifacts/cloud/persistent_artifact_cloud_models.dart';
import 'persistent_artifact_cloud_validators.dart';

class PersistentArtifactCloudStagingGovernanceEvaluator {
  const PersistentArtifactCloudStagingGovernanceEvaluator();

  PersistentArtifactCloudStagingReadinessDecision evaluate({
    required PersistentArtifactCloudBackendDescriptor descriptor,
    required PersistentArtifactCloudStagingPromotionCriteria criteria,
  }) {
    final issues = <PersistentArtifactCloudIssue>[];
    issues.addAll(PersistentArtifactCloudValidators.validateBackendDescriptor(
        descriptor));

    if (descriptor.replication.mode != criteria.requiredReplicationMode) {
      issues.add(
        const PersistentArtifactCloudIssue(
          code: 'CLOUD_REPLICATION_MODE_MISMATCH',
          message: 'Replication mode does not satisfy promotion criteria.',
          severity: CloudIssueSeverity.critical,
          path: 'replication.mode',
        ),
      );
    }

    if (descriptor.consistency.readConsistency !=
        criteria.requiredReadConsistency) {
      issues.add(
        const PersistentArtifactCloudIssue(
          code: 'CLOUD_CONSISTENCY_MISMATCH',
          message: 'Read consistency does not satisfy promotion criteria.',
          severity: CloudIssueSeverity.critical,
          path: 'consistency.readConsistency',
        ),
      );
    }

    if (criteria.requireEncryptionAtRest && !descriptor.encryption.atRest) {
      issues.add(
        const PersistentArtifactCloudIssue(
          code: 'CLOUD_ENCRYPTION_AT_REST_REQUIRED',
          message: 'Encryption at rest is required for staging.',
          severity: CloudIssueSeverity.critical,
          path: 'encryption.atRest',
        ),
      );
    }

    if (criteria.requireEncryptionInTransit &&
        !descriptor.encryption.inTransit) {
      issues.add(
        const PersistentArtifactCloudIssue(
          code: 'CLOUD_ENCRYPTION_IN_TRANSIT_REQUIRED',
          message: 'Encryption in transit is required for staging.',
          severity: CloudIssueSeverity.critical,
          path: 'encryption.inTransit',
        ),
      );
    }

    if (descriptor.metadata.keys
            .toSet()
            .intersection(criteria.requiredMetadataKeys.toSet())
            .length !=
        criteria.requiredMetadataKeys.length) {
      issues.add(
        const PersistentArtifactCloudIssue(
          code: 'CLOUD_REQUIRED_METADATA_MISSING',
          message: 'Required metadata keys for staging are missing.',
          severity: CloudIssueSeverity.warning,
          path: 'metadata',
        ),
      );
    }

    final meetsDurability = descriptor.replication.targetRegionIds.length >=
            criteria.minimumDurability.minimumReplicas &&
        descriptor.replication.targetRegionIds.toSet().length >=
            criteria.minimumDurability.failureDomainDiversity;

    if (!meetsDurability) {
      issues.add(
        const PersistentArtifactCloudIssue(
          code: 'CLOUD_DURABILITY_REQUIREMENT_NOT_MET',
          message:
              'Replication topology does not satisfy minimum durability criteria.',
          severity: CloudIssueSeverity.critical,
          path: 'replication',
        ),
      );
    }

    final criticalCount =
        issues.where((it) => it.severity == CloudIssueSeverity.critical).length;
    final approved = descriptor.stagingEligible &&
        !descriptor.productionEligible &&
        criticalCount == 0 &&
        issues.length <= criteria.maxAllowedIssues;

    final status = approved
        ? CloudPromotionStatus.approved
        : descriptor.stagingEligible
            ? CloudPromotionStatus.blocked
            : CloudPromotionStatus.rejected;

    return PersistentArtifactCloudStagingReadinessDecision(
      backendId: descriptor.backendId,
      criteriaId: criteria.criteriaId,
      status: status,
      stagingEligible: descriptor.stagingEligible,
      productionEligible: descriptor.productionEligible,
      approved: approved,
      issues: List.unmodifiable(issues),
      metadata: {
        'issueCount': issues.length.toString(),
        'criticalCount': criticalCount.toString(),
      },
    );
  }
}
