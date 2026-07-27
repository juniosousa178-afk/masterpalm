import '../models/release_governance/release_context.dart';
import '../models/release_governance/release_governance_enums.dart';
import '../models/release_governance/release_governance_messages.dart';
import '../models/release_governance/release_governance_policy.dart';

/// Validates release context artifacts.
class ReleaseContextValidator {
  const ReleaseContextValidator();

  ReleaseGovernanceValidationResult validate(
    ReleaseContext context, {
    ReleaseGovernancePolicy? policy,
  }) {
    final issues = <ReleaseGovernanceValidationIssue>[];
    final warnings = <String>[];
    final errors = <String>[];

    void addError(String code, String path, String message) {
      errors.add(message);
      issues.add(
        ReleaseGovernanceValidationIssue(
          code: code,
          path: path,
          severity: ReleaseGovernanceRuleSeverity.critical,
          message: message,
        ),
      );
    }

    if (context.projectId.trim().isEmpty) {
      addError('RG_CTX_PROJECT', 'projectId', 'projectId is required');
    }
    if (context.releaseId.trim().isEmpty) {
      addError('RG_CTX_RELEASE_ID', 'releaseId', 'releaseId is required');
    }
    if (context.releaseVersion.trim().isEmpty) {
      addError(
          'RG_CTX_VERSION', 'releaseVersion', 'releaseVersion is required');
    }
    if (context.requestedAt.trim().isEmpty) {
      addError('RG_CTX_REQUESTED_AT', 'requestedAt', 'requestedAt is required');
    }
    if (context.requestedBy.trim().isEmpty) {
      addError('RG_CTX_REQUESTED_BY', 'requestedBy', 'requestedBy is required');
    }

    final requiresCommit = policy?.evidencePolicy.requireCommitId ?? true;
    if (requiresCommit &&
        context.environment == ReleaseEnvironment.production &&
        context.commitId.trim().isEmpty) {
      addError(
        'RG_CTX_COMMIT_REQUIRED',
        'commitId',
        'commitId is required for production releases',
      );
    }

    if (context.environment == ReleaseEnvironment.unknown) {
      warnings.add('environment is unknown');
    }

    if (policy != null) {
      if (!policy.supportedEnvironments.contains(context.environment) &&
          context.environment != ReleaseEnvironment.unknown) {
        errors.add(
            'environment ${context.environment.wireName} is not supported');
      }
      if (!policy.supportedReleaseTypes.contains(context.releaseType)) {
        errors.add(
            'releaseType ${context.releaseType.wireName} is not supported');
      }
    }

    if (context.targetDate != null &&
        context.targetDate!.compareTo(context.requestedAt) < 0) {
      addError(
        'RG_CTX_TARGET_DATE',
        'targetDate',
        'targetDate must not be before requestedAt',
      );
    }

    final artifactIds = <String>{};
    for (final artifact in context.artifactReferences) {
      if (!artifactIds.add(artifact.artifactId)) {
        addError(
          'RG_CTX_DUPLICATE_ARTIFACT',
          'artifactReferences',
          'duplicate artifactId: ${artifact.artifactId}',
        );
      }
    }

    return ReleaseGovernanceValidationResult(
      isValid: errors.isEmpty,
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}
