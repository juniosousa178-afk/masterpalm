import '../../models/persistent_artifacts/cloud/persistent_artifact_cloud_enums.dart';
import '../../models/persistent_artifacts/cloud/persistent_artifact_cloud_models.dart';
import '../../models/persistent_artifacts/cloud/persistent_artifact_real_cloud_adapter_admission.dart';

/// Pure evaluator for real cloud adapter prototype admission.
///
/// Does not install SDKs, alter registry state, enable environments,
/// or authorize release.
class PersistentArtifactRealCloudAdapterAdmissionEvaluator {
  const PersistentArtifactRealCloudAdapterAdmissionEvaluator();

  PersistentArtifactRealCloudAdapterAdmissionDecision evaluate({
    required PersistentArtifactRealCloudAdapterAdmissionCriteria criteria,
    String? manualApprovalReference,
    bool rejected = false,
    bool blocked = false,
  }) {
    final missing = criteria.missingCriterionIds();
    final total =
        PersistentArtifactRealCloudAdapterAdmissionCriteria.criterionIds.length;
    final satisfied = total - missing.length;
    final issues = <PersistentArtifactCloudIssue>[];

    if (rejected) {
      issues.add(
        const PersistentArtifactCloudIssue(
          code: 'REAL_ADAPTER_ADMISSION_REJECTED',
          message: 'Real cloud adapter admission was explicitly rejected.',
          severity: CloudIssueSeverity.critical,
        ),
      );
      return _decision(
        status: RealCloudAdapterAdmissionStatus.rejected,
        satisfied: satisfied,
        total: total,
        missing: missing,
        issues: issues,
      );
    }

    if (blocked) {
      issues.add(
        const PersistentArtifactCloudIssue(
          code: 'REAL_ADAPTER_ADMISSION_BLOCKED',
          message:
              'Real cloud adapter admission is blocked until governance review.',
          severity: CloudIssueSeverity.critical,
        ),
      );
      return _decision(
        status: RealCloudAdapterAdmissionStatus.blocked,
        satisfied: satisfied,
        total: total,
        missing: missing,
        issues: issues,
      );
    }

    if (satisfied == 0) {
      issues.add(
        const PersistentArtifactCloudIssue(
          code: 'REAL_ADAPTER_ADMISSION_NOT_EVALUATED',
          message: 'No admission criteria have been satisfied yet.',
          severity: CloudIssueSeverity.info,
        ),
      );
      return _decision(
        status: RealCloudAdapterAdmissionStatus.notEvaluated,
        satisfied: satisfied,
        total: total,
        missing: missing,
        issues: issues,
      );
    }

    if (missing.isNotEmpty) {
      for (final criterionId in missing) {
        issues.add(
          PersistentArtifactCloudIssue(
            code: 'REAL_ADAPTER_CRITERION_MISSING',
            message: 'Admission criterion not satisfied: $criterionId.',
            severity: CloudIssueSeverity.warning,
            path: criterionId,
          ),
        );
      }
      return _decision(
        status: RealCloudAdapterAdmissionStatus.incomplete,
        satisfied: satisfied,
        total: total,
        missing: missing,
        issues: issues,
      );
    }

    final hasManualApproval = manualApprovalReference != null &&
        manualApprovalReference.trim().isNotEmpty;
    if (!hasManualApproval) {
      issues.add(
        const PersistentArtifactCloudIssue(
          code: 'REAL_ADAPTER_MANUAL_APPROVAL_REQUIRED',
          message:
              'All criteria satisfied; manual approval reference required for prototype admission.',
          severity: CloudIssueSeverity.warning,
        ),
      );
      return _decision(
        status: RealCloudAdapterAdmissionStatus.eligibleForDesignReview,
        satisfied: satisfied,
        total: total,
        missing: missing,
        issues: issues,
      );
    }

    return PersistentArtifactRealCloudAdapterAdmissionDecision(
      status: RealCloudAdapterAdmissionStatus.approvedForPrototype,
      satisfiedCriteriaCount: satisfied,
      totalCriteriaCount: total,
      missingCriteria: const [],
      manualApprovalReference: manualApprovalReference,
      stagingApproved: false,
      productionApproved: false,
      prototypeAdmissionGranted: true,
      issues: const [
        PersistentArtifactCloudIssue(
          code: 'REAL_ADAPTER_PROTOTYPE_ADMITTED',
          message:
              'Prototype admission granted; staging and production remain blocked.',
          severity: CloudIssueSeverity.info,
        ),
      ],
      metadata: const {
        'stagingBlocked': 'true',
        'productionBlocked': 'true',
        'sdkInstallation': 'not-authorized',
        'releaseAuthorization': 'not-authorized',
      },
    );
  }

  PersistentArtifactRealCloudAdapterAdmissionDecision _decision({
    required RealCloudAdapterAdmissionStatus status,
    required int satisfied,
    required int total,
    required List<String> missing,
    required List<PersistentArtifactCloudIssue> issues,
  }) {
    return PersistentArtifactRealCloudAdapterAdmissionDecision(
      status: status,
      satisfiedCriteriaCount: satisfied,
      totalCriteriaCount: total,
      missingCriteria: missing,
      stagingApproved: false,
      productionApproved: false,
      prototypeAdmissionGranted: false,
      issues: issues,
      metadata: const {
        'stagingBlocked': 'true',
        'productionBlocked': 'true',
      },
    );
  }
}
