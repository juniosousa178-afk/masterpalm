import '../models/release_supply_chain/release_distribution_models.dart';
import '../models/release_supply_chain/release_supply_chain_enums.dart';
import '../models/release_supply_chain/release_supply_chain_validation_result.dart';

/// Validates structural consistency of [ReleaseDistribution].
class ReleaseDistributionValidator {
  const ReleaseDistributionValidator();

  ReleaseSupplyChainValidationResult validate(
      ReleaseDistribution distribution) {
    final issues = <ReleaseSupplyChainValidationIssue>[];
    final warnings = <String>[];
    final errors = <String>[];

    void addError(String code, String path, String message,
        {String? relatedId}) {
      errors.add(message);
      issues.add(
        ReleaseSupplyChainValidationIssue(
          code: code,
          path: path,
          severity: ReleaseSupplyChainValidationSeverity.critical,
          message: message,
          relatedId: relatedId,
        ),
      );
    }

    if (distribution.distributionId.isEmpty) {
      addError('RSC_DIST_ID', 'distributionId', 'distributionId is required');
    }
    if (distribution.fingerprint.isEmpty) {
      addError(
          'RSC_DIST_FINGERPRINT', 'fingerprint', 'fingerprint is required');
    }
    if (distribution.targets.length < distribution.policy.requiredTargetCount) {
      addError(
        'RSC_DIST_TARGET_COUNT',
        'targets',
        'target count below policy requiredTargetCount',
      );
    }

    final allowed = distribution.policy.allowedChannelTypes.toSet();
    if (!allowed.contains(distribution.channel.channelType)) {
      addError(
        'RSC_DIST_CHANNEL',
        'channel.channelType',
        'channel type not allowed by policy',
      );
    }

    if (distribution.manifest.artifactRecordIds.isEmpty) {
      addError(
        'RSC_DIST_MANIFEST_EMPTY',
        'manifest.artifactRecordIds',
        'manifest must reference at least one artifact',
      );
    }

    if (distribution.status == DistributionStatus.failed) {
      warnings.add('distribution status is failed');
    }

    return ReleaseSupplyChainValidationResult(
      isValid: errors.isEmpty,
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}
