import '../models/release_governance/release_context.dart';
import '../models/release_governance/release_governance_enums.dart';
import '../models/release_governance/release_governance_evidence.dart';
import '../models/release_governance/release_governance_messages.dart';
import '../models/release_governance/release_governance_policy.dart';
import '../models/release_governance/release_waiver.dart';
import 'release_governance_canonical_serializer.dart';
import 'resolved_release_governance_sources.dart';

/// Evaluates waivers and applies waiver outcomes to rule evaluations.
class ReleaseGovernanceWaiverEvaluator {
  const ReleaseGovernanceWaiverEvaluator({
    ReleaseGovernanceCanonicalSerializer? serializer,
  }) : _serializer = serializer ?? const ReleaseGovernanceCanonicalSerializer();

  final ReleaseGovernanceCanonicalSerializer _serializer;

  List<ReleaseWaiverEvaluation> evaluate({
    required ReleaseGovernancePolicy policy,
    required ReleaseContext releaseContext,
    required ResolvedReleaseGovernanceSources sources,
    required String referenceTime,
    required List<ReleaseGovernanceEvaluation> evaluations,
  }) {
    if (!sources.waiverSet.isAvailable) return const [];

    final waivers = sources.waiverSet.resolvedArtifact!.waivers.toList()
      ..sort((a, b) => a.waiverId.compareTo(b.waiverId));

    final refTime = DateTime.tryParse(referenceTime)?.toUtc();
    final waiverPolicy = policy.waiverRules;

    return waivers.map((waiver) {
      final expirationValid = !_isExpired(waiver, refTime);
      final scopeValid = waiver.scope.projectId == releaseContext.projectId &&
          waiver.scope.releaseId == releaseContext.releaseId &&
          (waiver.scope.commitId == null ||
              waiver.scope.commitId == releaseContext.commitId);
      final authorityValid =
          waiver.authority.status == ReleaseAuthorityStatus.active &&
              waiverPolicy.allowedAuthorities
                  .contains(waiver.authority.authorityId);
      final policyValid = waiver.policyId == policy.metadata.policyId &&
          waiver.policyVersion == policy.metadata.policyVersion;
      final releaseValid = waiver.releaseId == releaseContext.releaseId;
      final commitValid = waiver.scope.commitId == null ||
          waiver.scope.commitId == releaseContext.commitId;
      final environmentValid =
          waiver.scope.environment == releaseContext.environment;
      final ruleCoverageValid = waiver.affectedRuleIds.isNotEmpty;
      final compensatingControlsValid =
          !waiverPolicy.compensatingControlsRequired ||
              waiver.compensatingControls.any(
                (c) => c.status == ReleaseCompensatingControlStatus.active,
              );
      final usageValid = waiver.status == ReleaseWaiverStatus.active ||
          waiver.status == ReleaseWaiverStatus.approved;

      final allValid = expirationValid &&
          scopeValid &&
          authorityValid &&
          policyValid &&
          releaseValid &&
          commitValid &&
          environmentValid &&
          ruleCoverageValid &&
          compensatingControlsValid &&
          usageValid;

      final status = allValid
          ? ReleaseWaiverStatus.active
          : _isExpired(waiver, refTime)
              ? ReleaseWaiverStatus.expired
              : ReleaseWaiverStatus.invalid;

      final affectedEvaluationIds = evaluations
          .where(
            (e) =>
                waiver.affectedRuleIds.contains(e.ruleId) &&
                e.status == ReleaseGovernanceRuleStatus.failed,
          )
          .map((e) => e.evaluationId)
          .toList()
        ..sort();

      final explanation = ReleaseGovernanceExplanation(
        explanationId: 'rgwv:${waiver.waiverId}:${status.wireName}',
        type: allValid
            ? ReleaseGovernanceExplanationType.waiverAccepted
            : status == ReleaseWaiverStatus.expired
                ? ReleaseGovernanceExplanationType.waiverExpired
                : ReleaseGovernanceExplanationType.waiverRejected,
        summary: 'Waiver ${waiver.waiverId} ${status.wireName}',
        detail: waiver.justification,
        templateId: 'waiver.${status.wireName}',
      );

      final evaluation = ReleaseWaiverEvaluation(
        waiverId: waiver.waiverId,
        status: status,
        scopeValid: scopeValid,
        authorityValid: authorityValid,
        expirationValid: expirationValid,
        policyValid: policyValid,
        releaseValid: releaseValid,
        commitValid: commitValid,
        environmentValid: environmentValid,
        ruleCoverageValid: ruleCoverageValid,
        compensatingControlsValid: compensatingControlsValid,
        usageValid: usageValid,
        affectedEvaluationIds: affectedEvaluationIds,
        decisionImpact: allValid
            ? ReleaseGovernanceDecisionImpact.contributesToConditions
            : ReleaseGovernanceDecisionImpact.blocksApproval,
        evidenceIds: waiver.evidence.map((e) => e.evidenceId).toList(),
        explanation: explanation,
        fingerprint: '',
      );

      return ReleaseWaiverEvaluation(
        waiverId: evaluation.waiverId,
        status: evaluation.status,
        scopeValid: evaluation.scopeValid,
        authorityValid: evaluation.authorityValid,
        expirationValid: evaluation.expirationValid,
        policyValid: evaluation.policyValid,
        releaseValid: evaluation.releaseValid,
        commitValid: evaluation.commitValid,
        environmentValid: evaluation.environmentValid,
        ruleCoverageValid: evaluation.ruleCoverageValid,
        compensatingControlsValid: evaluation.compensatingControlsValid,
        usageValid: evaluation.usageValid,
        affectedEvaluationIds: evaluation.affectedEvaluationIds,
        decisionImpact: evaluation.decisionImpact,
        evidenceIds: evaluation.evidenceIds,
        explanation: evaluation.explanation,
        fingerprint: _serializer.waiverEvaluationFingerprint(evaluation),
      );
    }).toList();
  }

  List<ReleaseGovernanceEvaluation> applyWaivers({
    required List<ReleaseGovernanceEvaluation> evaluations,
    required List<ReleaseWaiverEvaluation> waiverEvaluations,
    required ReleaseGovernancePolicy policy,
  }) {
    if (!policy.decisionPolicy.validWaiverMayCreateConditionalApproval) {
      return evaluations;
    }

    final rulesById = {for (final r in policy.rules) r.ruleId: r};

    final waivedRuleIds = <String>{};
    for (final waiverEval in waiverEvaluations) {
      if (waiverEval.status == ReleaseWaiverStatus.active ||
          waiverEval.status == ReleaseWaiverStatus.approved) {
        waivedRuleIds.addAll(
          evaluations
              .where(
                (e) =>
                    waiverEval.affectedEvaluationIds.contains(e.evaluationId),
              )
              .map((e) => e.ruleId),
        );
      }
    }

    return evaluations.map((evaluation) {
      if (!waivedRuleIds.contains(evaluation.ruleId) ||
          evaluation.status != ReleaseGovernanceRuleStatus.failed) {
        return evaluation;
      }

      final rule = rulesById[evaluation.ruleId];
      if (rule == null ||
          rule.waiverCapability ==
              ReleaseGovernanceWaiverCapability.forbidden ||
          rule.severity == ReleaseGovernanceRuleSeverity.critical) {
        return evaluation;
      }

      return ReleaseGovernanceEvaluation(
        evaluationId: evaluation.evaluationId,
        ruleId: evaluation.ruleId,
        ruleSetId: evaluation.ruleSetId,
        target: evaluation.target,
        operator: evaluation.operator,
        selector: evaluation.selector,
        expectedValue: evaluation.expectedValue,
        actualValue: evaluation.actualValue,
        status: ReleaseGovernanceRuleStatus.waived,
        decisionImpact: ReleaseGovernanceDecisionImpact.none,
        evidenceIds: evaluation.evidenceIds,
        waiverIds: evaluation.waiverIds,
        explanation: evaluation.explanation,
        warnings: evaluation.warnings,
        errors: evaluation.errors,
        limitations: evaluation.limitations,
        fingerprint: evaluation.fingerprint,
      );
    }).toList();
  }

  bool _isExpired(ReleaseWaiver waiver, DateTime? referenceTime) {
    if (referenceTime == null) return false;
    if (waiver.status == ReleaseWaiverStatus.expired) return true;
    final expiresAt = DateTime.tryParse(waiver.expiration.expiresAt)?.toUtc();
    if (expiresAt == null) return false;
    return expiresAt.isBefore(referenceTime);
  }
}
