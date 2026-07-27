import '../models/release_governance/release_approval.dart';
import '../models/release_governance/release_context.dart';
import '../models/release_governance/release_governance_enums.dart';
import '../models/release_governance/release_governance_messages.dart';
import '../models/release_governance/release_governance_policy.dart';
import 'release_governance_canonical_serializer.dart';
import 'release_governance_target_registry.dart';
import 'resolved_release_governance_sources.dart';

/// Evaluates approval requirements against resolved approval set.
class ReleaseGovernanceApprovalEvaluator {
  const ReleaseGovernanceApprovalEvaluator({
    ReleaseGovernanceCanonicalSerializer? serializer,
  }) : _serializer = serializer ?? const ReleaseGovernanceCanonicalSerializer();

  final ReleaseGovernanceCanonicalSerializer _serializer;

  List<ReleaseApprovalEvaluation> evaluate({
    required ReleaseGovernancePolicy policy,
    required ReleaseContext releaseContext,
    required ResolvedReleaseGovernanceSources sources,
    required String referenceTime,
  }) {
    final requirements =
        policy.approvalRequirements.where((r) => r.enabled).toList()
          ..sort((a, b) {
            final orderCmp = a.order.compareTo(b.order);
            if (orderCmp != 0) return orderCmp;
            return a.requirementId.compareTo(b.requirementId);
          });

    final approvals = sources.approvalSet.isAvailable
        ? sources.approvalSet.resolvedArtifact!.approvals
        : <ReleaseApproval>[];

    final metrics = ReleaseGovernanceApprovalMetrics.compute(
      policy: policy,
      releaseContext: releaseContext,
      approvalSet: sources.approvalSet,
      referenceTime: referenceTime,
    );

    return requirements.map((requirement) {
      final applies = ReleaseGovernanceApprovalMetrics.requirementApplies(
        requirement,
        releaseContext,
      );
      if (!applies || requirement.minimumCount == 0) {
        return _buildEvaluation(
          requirement: requirement,
          requiredCount: requirement.minimumCount,
          validCount: 0,
          missingCount: 0,
          expiredCount: 0,
          rejectedCount: 0,
          status: ReleaseApprovalEvaluationStatus.notApplicable,
          approvalIds: const [],
          sodSatisfied: true,
        );
      }

      final matching = approvals
          .where((a) => a.approvalType == requirement.approvalType)
          .toList()
        ..sort((a, b) => a.approvalId.compareTo(b.approvalId));

      final refTime = DateTime.tryParse(referenceTime)?.toUtc();
      var validCount = 0;
      var rejectedCount = 0;
      var expiredCount = 0;
      final approvalIds = <String>[];

      for (final approval in matching) {
        if (approval.status == ReleaseApprovalStatus.rejected) {
          rejectedCount++;
          approvalIds.add(approval.approvalId);
          continue;
        }
        if (_isExpired(approval.expiresAt, refTime)) {
          expiredCount++;
          approvalIds.add(approval.approvalId);
          continue;
        }
        if (approval.status == ReleaseApprovalStatus.approved) {
          validCount++;
          approvalIds.add(approval.approvalId);
        }
      }

      final missingCount = (requirement.minimumCount - validCount)
          .clamp(0, requirement.minimumCount);

      final status = _deriveStatus(
        rejectedCount: rejectedCount,
        expiredCount: expiredCount,
        missingCount: missingCount,
        validCount: validCount,
        requiredCount: requirement.minimumCount,
      );

      return _buildEvaluation(
        requirement: requirement,
        requiredCount: requirement.minimumCount,
        validCount: validCount,
        missingCount: missingCount,
        expiredCount: expiredCount,
        rejectedCount: rejectedCount,
        status: status,
        approvalIds: approvalIds,
        sodSatisfied: metrics.separationOfDutiesSatisfied,
      );
    }).toList();
  }

  ReleaseApprovalEvaluationStatus _deriveStatus({
    required int rejectedCount,
    required int expiredCount,
    required int missingCount,
    required int validCount,
    required int requiredCount,
  }) {
    if (rejectedCount > 0) return ReleaseApprovalEvaluationStatus.rejected;
    if (expiredCount > 0 && validCount < requiredCount) {
      return ReleaseApprovalEvaluationStatus.expired;
    }
    if (missingCount > 0) {
      return validCount > 0
          ? ReleaseApprovalEvaluationStatus.partiallySatisfied
          : ReleaseApprovalEvaluationStatus.missing;
    }
    return ReleaseApprovalEvaluationStatus.satisfied;
  }

  bool _isExpired(String? expiresAt, DateTime? referenceTime) {
    if (expiresAt == null || referenceTime == null) return false;
    final expiry = DateTime.tryParse(expiresAt)?.toUtc();
    if (expiry == null) return false;
    return expiry.isBefore(referenceTime);
  }

  ReleaseApprovalEvaluation _buildEvaluation({
    required ReleaseApprovalRequirement requirement,
    required int requiredCount,
    required int validCount,
    required int missingCount,
    required int expiredCount,
    required int rejectedCount,
    required ReleaseApprovalEvaluationStatus status,
    required List<String> approvalIds,
    required bool sodSatisfied,
  }) {
    final explanationType = switch (status) {
      ReleaseApprovalEvaluationStatus.satisfied =>
        ReleaseGovernanceExplanationType.approvalSatisfied,
      ReleaseApprovalEvaluationStatus.partiallySatisfied =>
        ReleaseGovernanceExplanationType.approvalMissing,
      ReleaseApprovalEvaluationStatus.missing =>
        ReleaseGovernanceExplanationType.approvalMissing,
      ReleaseApprovalEvaluationStatus.rejected =>
        ReleaseGovernanceExplanationType.approvalRejected,
      ReleaseApprovalEvaluationStatus.expired =>
        ReleaseGovernanceExplanationType.approvalExpired,
      ReleaseApprovalEvaluationStatus.incompatible =>
        ReleaseGovernanceExplanationType.compatibility,
      ReleaseApprovalEvaluationStatus.notApplicable =>
        ReleaseGovernanceExplanationType.approvalSatisfied,
      ReleaseApprovalEvaluationStatus.error =>
        ReleaseGovernanceExplanationType.decisionError,
    };

    final explanation = ReleaseGovernanceExplanation(
      explanationId: 'rgap:${requirement.requirementId}:${status.wireName}',
      type: explanationType,
      summary:
          'Approval requirement ${requirement.requirementId} ${status.wireName}',
      detail:
          'Required $requiredCount ${requirement.approvalType.wireName} approvals; valid=$validCount missing=$missingCount.',
      templateId: 'approval.${status.wireName}',
    );

    final evaluation = ReleaseApprovalEvaluation(
      requirementId: requirement.requirementId,
      approvalType: requirement.approvalType,
      requiredCount: requiredCount,
      validCount: validCount,
      missingCount: missingCount,
      expiredCount: expiredCount,
      rejectedCount: rejectedCount,
      duplicateCount: 0,
      authorityInvalidCount: 0,
      separationOfDutiesSatisfied: sodSatisfied,
      status: status,
      approvalIds: approvalIds,
      evidenceIds: const [],
      explanation: explanation,
      fingerprint: '',
    );

    return ReleaseApprovalEvaluation(
      requirementId: evaluation.requirementId,
      approvalType: evaluation.approvalType,
      requiredCount: evaluation.requiredCount,
      validCount: evaluation.validCount,
      missingCount: evaluation.missingCount,
      expiredCount: evaluation.expiredCount,
      rejectedCount: evaluation.rejectedCount,
      duplicateCount: evaluation.duplicateCount,
      authorityInvalidCount: evaluation.authorityInvalidCount,
      separationOfDutiesSatisfied: evaluation.separationOfDutiesSatisfied,
      status: evaluation.status,
      approvalIds: evaluation.approvalIds,
      evidenceIds: evaluation.evidenceIds,
      explanation: evaluation.explanation,
      fingerprint: _serializer.approvalEvaluationFingerprint(evaluation),
    );
  }
}
