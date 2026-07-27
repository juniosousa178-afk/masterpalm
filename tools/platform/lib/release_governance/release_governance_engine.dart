import '../models/quality_gate/quality_gate_enums.dart';
import '../models/release_governance/release_decision_snapshot.dart';
import '../models/release_governance/release_governance_enums.dart';
import '../models/release_governance/release_governance_evidence.dart';
import '../models/release_governance/release_governance_messages.dart';
import '../models/release_governance/release_governance_policy.dart';
import '../models/release_governance/release_governance_request.dart';
import 'release_decision_snapshot_validator.dart';
import 'release_governance_approval_evaluator.dart';
import 'release_governance_canonical_serializer.dart';
import 'release_governance_compatibility_checker.dart';
import 'release_governance_condition_builder.dart';
import 'release_governance_coverage_calculator.dart';
import 'release_governance_decision_aggregator.dart';
import 'release_governance_eligibility_evaluator.dart';
import 'release_governance_explanation_builder.dart';
import 'release_governance_identity_builder.dart';
import 'release_governance_policy_validator.dart';
import 'release_governance_rule_evaluator.dart';
import 'release_governance_waiver_evaluator.dart';
import 'resolved_release_governance_sources.dart';

/// Stateless engine that evaluates release governance policies.
class ReleaseGovernanceEngine {
  ReleaseGovernanceEngine({
    ReleaseGovernancePolicyValidator? policyValidator,
    ReleaseGovernanceRuleEvaluator? ruleEvaluator,
    ReleaseGovernanceCompatibilityChecker? compatibilityChecker,
    ReleaseGovernanceEligibilityEvaluator? eligibilityEvaluator,
    ReleaseGovernanceApprovalEvaluator? approvalEvaluator,
    ReleaseGovernanceWaiverEvaluator? waiverEvaluator,
    ReleaseGovernanceConditionBuilder? conditionBuilder,
    ReleaseGovernanceCoverageCalculator? coverageCalculator,
    ReleaseGovernanceDecisionAggregator? decisionAggregator,
    ReleaseGovernanceExplanationBuilder? explanationBuilder,
    ReleaseGovernanceIdentityBuilder? identityBuilder,
    ReleaseGovernanceCanonicalSerializer? serializer,
    ReleaseDecisionSnapshotValidator? snapshotValidator,
  })  : _policyValidator =
            policyValidator ?? const ReleaseGovernancePolicyValidator(),
        _ruleEvaluator = ruleEvaluator ?? ReleaseGovernanceRuleEvaluator(),
        _compatibilityChecker = compatibilityChecker ??
            const ReleaseGovernanceCompatibilityChecker(),
        _eligibilityEvaluator = eligibilityEvaluator ??
            const ReleaseGovernanceEligibilityEvaluator(),
        _approvalEvaluator =
            approvalEvaluator ?? const ReleaseGovernanceApprovalEvaluator(),
        _waiverEvaluator =
            waiverEvaluator ?? const ReleaseGovernanceWaiverEvaluator(),
        _conditionBuilder =
            conditionBuilder ?? const ReleaseGovernanceConditionBuilder(),
        _coverageCalculator =
            coverageCalculator ?? const ReleaseGovernanceCoverageCalculator(),
        _decisionAggregator =
            decisionAggregator ?? const ReleaseGovernanceDecisionAggregator(),
        _explanationBuilder =
            explanationBuilder ?? const ReleaseGovernanceExplanationBuilder(),
        _identityBuilder =
            identityBuilder ?? const ReleaseGovernanceIdentityBuilder(),
        _serializer =
            serializer ?? const ReleaseGovernanceCanonicalSerializer(),
        _snapshotValidator = snapshotValidator ??
            const DefaultReleaseDecisionSnapshotValidator();

  final ReleaseGovernancePolicyValidator _policyValidator;
  final ReleaseGovernanceRuleEvaluator _ruleEvaluator;
  final ReleaseGovernanceCompatibilityChecker _compatibilityChecker;
  final ReleaseGovernanceEligibilityEvaluator _eligibilityEvaluator;
  final ReleaseGovernanceApprovalEvaluator _approvalEvaluator;
  final ReleaseGovernanceWaiverEvaluator _waiverEvaluator;
  final ReleaseGovernanceConditionBuilder _conditionBuilder;
  final ReleaseGovernanceCoverageCalculator _coverageCalculator;
  final ReleaseGovernanceDecisionAggregator _decisionAggregator;
  final ReleaseGovernanceExplanationBuilder _explanationBuilder;
  final ReleaseGovernanceIdentityBuilder _identityBuilder;
  final ReleaseGovernanceCanonicalSerializer _serializer;
  final ReleaseDecisionSnapshotValidator _snapshotValidator;

  ReleaseGovernanceResult evaluate({
    required ReleaseGovernanceRequest request,
    required ReleaseGovernancePolicy policy,
    required ResolvedReleaseGovernanceSources sources,
  }) {
    final policyValidation = _policyValidator.validate(
      policy,
      allowRetired: request.historicalEvaluation,
    );
    if (!policyValidation.isValid) {
      return ReleaseGovernanceResult(
        status: ReleaseGovernanceResultStatus.failure,
        errors: [
          ReleaseGovernanceError(
            errorId: 'policy-invalid',
            code: ReleaseGovernanceErrorCode.invalidPolicy,
            message: policyValidation.errors.join('; '),
            recoverable: false,
            classification: 'validation',
          ),
        ],
        sourceResolutionSummary: sources.resolutionSummary,
      );
    }

    final compatibility = _compatibilityChecker.check(
      request: request,
      policy: policy,
      sources: sources,
    );

    final orderedRules = policy.rules.toList()
      ..sort((a, b) {
        final orderCmp = a.order.compareTo(b.order);
        if (orderCmp != 0) return orderCmp;
        return a.ruleId.compareTo(b.ruleId);
      });

    final enabledRules = orderedRules.where((rule) => rule.enabled).toList();

    final eligibility = _eligibilityEvaluator.evaluate(
      request: request,
      policy: policy,
      sources: sources,
      compatibility: compatibility,
      enabledRules: enabledRules
          .where(
            (r) =>
                r.requirement != ReleaseGovernanceRuleRequirement.informational,
          )
          .toList(),
    );

    final warnings = <ReleaseGovernanceWarning>[...sources.warnings];
    final errors = <ReleaseGovernanceError>[...sources.errors];
    final limitations = <ReleaseGovernanceLimitation>[...sources.limitations];

    var evaluations = <ReleaseGovernanceEvaluation>[];
    final evidenceItems = <ReleaseGovernanceEvidence>[];
    for (final rule in enabledRules) {
      final outcome = _ruleEvaluator.evaluateOutcome(
        rule: rule,
        policy: policy,
        request: request,
        sources: sources,
      );
      evaluations.add(outcome.evaluation);
      evidenceItems.addAll(outcome.evidence);
    }
    evaluations.sort((a, b) => a.ruleId.compareTo(b.ruleId));

    final approvalEvaluations = _approvalEvaluator.evaluate(
      policy: policy,
      releaseContext: request.releaseContext,
      sources: sources,
      referenceTime: request.referenceTime,
    );

    final waiverEvaluations = _waiverEvaluator.evaluate(
      policy: policy,
      releaseContext: request.releaseContext,
      sources: sources,
      referenceTime: request.referenceTime,
      evaluations: evaluations,
    );

    evaluations = _waiverEvaluator.applyWaivers(
      evaluations: evaluations,
      waiverEvaluations: waiverEvaluations,
      policy: policy,
    );

    final conditions = _conditionBuilder.build(
      policy: policy,
      evaluations: evaluations,
      approvalEvaluations: approvalEvaluations,
      waiverEvaluations: waiverEvaluations,
      referenceTime: request.referenceTime,
    );

    final evidence = <ReleaseGovernanceEvidence>[];
    if (request.includeEvidence) {
      evidence.addAll(evidenceItems);
      evidence.sort((a, b) {
        final typeCmp =
            a.evidenceType.wireName.compareTo(b.evidenceType.wireName);
        if (typeCmp != 0) return typeCmp;
        final ruleCmp = (a.ruleId ?? '').compareTo(b.ruleId ?? '');
        if (ruleCmp != 0) return ruleCmp;
        return a.evidenceId.compareTo(b.evidenceId);
      });
    }

    final coverage = _coverageCalculator.calculate(
      policy: policy,
      evaluations: evaluations,
      approvalEvaluations: approvalEvaluations,
      waiverEvaluations: waiverEvaluations,
      evidence: evidence,
      sources: sources,
    );

    final decision = _decisionAggregator.aggregate(
      decisionPolicy: policy.decisionPolicy,
      compatibility: compatibility,
      eligibility: eligibility,
      coverage: coverage,
      evaluations: evaluations,
      approvalEvaluations: approvalEvaluations,
      waiverEvaluations: waiverEvaluations,
      conditions: conditions,
      errors: errors,
    );

    final policyFingerprint = _serializer.policyFingerprint(policy);
    final requestFingerprint = _serializer.requestFingerprint(request);
    final sourceSetFingerprint = _serializer.sourceSetFingerprint(
      sources.sourceReferences.map((r) => r.toJson()).toList(),
    );

    final qgSnapshot = sources.qualityGateSnapshot.resolvedArtifact;
    final qgRef = qgSnapshot == null
        ? const ReleaseQualityGateReference(
            qualityGateSnapshotId: '',
            qualityGateFingerprint: '',
            policyId: '',
            policyVersion: 0,
            decision: 'unavailable',
          )
        : ReleaseQualityGateReference(
            qualityGateSnapshotId: qgSnapshot.metadata.qualityGateSnapshotId,
            qualityGateFingerprint: qgSnapshot.metadata.qualityGateFingerprint,
            policyId: qgSnapshot.metadata.policyId,
            policyVersion: qgSnapshot.metadata.policyVersion,
            decision: qgSnapshot.decision.wireName,
            projectId: qgSnapshot.metadata.projectId,
            commitId: qgSnapshot.metadata.commitId,
          );

    final policyReference = ReleaseGovernancePolicyReference(
      policyId: policy.metadata.policyId,
      policyVersion: policy.metadata.policyVersion,
      fingerprint: policyFingerprint,
      displayName: policy.metadata.displayName,
      status: policy.metadata.status,
    );

    final blockingFailureCount = evaluations
        .where(
          (e) =>
              e.status == ReleaseGovernanceRuleStatus.failed &&
              e.decisionImpact ==
                  ReleaseGovernanceDecisionImpact.blocksApproval,
        )
        .length;

    final decisionExplanation = _explanationBuilder.buildDecisionExplanation(
      decision: decision,
      policyId: policy.metadata.policyId,
      policyVersion: policy.metadata.policyVersion,
      failedRuleCount: coverage.failedRuleCount,
      blockingFailureCount: blockingFailureCount,
    );

    final explanations = <ReleaseGovernanceExplanation>[
      decisionExplanation,
      ...evaluations.map((e) => e.explanation),
      ...approvalEvaluations.map((e) => e.explanation),
      ...waiverEvaluations.map((e) => e.explanation),
    ]..sort((a, b) => a.explanationId.compareTo(b.explanationId));

    final snapshotWithoutFingerprint = ReleaseDecisionSnapshot(
      metadata: ReleaseDecisionSnapshotMetadata(
        snapshotId: '',
        projectId: request.releaseContext.projectId,
        releaseId: request.releaseContext.releaseId,
        releaseVersion: request.releaseContext.releaseVersion,
        commitId: request.releaseContext.commitId,
        branch: request.releaseContext.branch,
        environment: request.releaseContext.environment,
        releaseType: request.releaseContext.releaseType,
        policyId: policy.metadata.policyId,
        policyVersion: policy.metadata.policyVersion,
        policyFingerprint: policyFingerprint,
        qualityGateSnapshotId: qgRef.qualityGateSnapshotId,
        qualityGateFingerprint: qgRef.qualityGateFingerprint,
        schemaVersion: ReleaseDecisionSnapshotMetadata.currentSchemaVersion,
        calculationVersion: ReleaseGovernancePolicy.currentCalculationVersion,
        canonicalizationVersion:
            ReleaseGovernancePolicy.currentCanonicalizationVersion,
        evaluatedAt: request.referenceTime,
        createdAt: request.referenceTime,
        decision: decision,
        requestFingerprint: requestFingerprint,
        sourceSetFingerprint: sourceSetFingerprint,
      ),
      releaseContext: request.releaseContext,
      policyReference: policyReference,
      qualityGateReference: qgRef,
      decision: decision,
      compatibility: compatibility,
      eligibility: eligibility,
      coverage: coverage,
      evaluations: evaluations,
      approvalEvaluations: approvalEvaluations,
      waiverEvaluations: waiverEvaluations,
      conditions: conditions,
      evidence: request.includeEvidence ? evidence : const [],
      sourceReferences: sources.sourceReferences,
      explanations: request.includeExplanations ? explanations : const [],
      warnings: warnings,
      errors: errors,
      limitations: limitations,
      fingerprint: '',
    );

    final releaseGovernanceFingerprint = _serializer.fingerprintFromString(
      [
        policyFingerprint,
        requestFingerprint,
        sourceSetFingerprint,
        _serializer.snapshotFingerprint(snapshotWithoutFingerprint),
      ].join(':'),
    );

    final snapshotId = _identityBuilder.buildSnapshotId(
      projectId: request.releaseContext.projectId,
      releaseId: request.releaseContext.releaseId,
      policyId: policy.metadata.policyId,
      policyVersion: policy.metadata.policyVersion,
      releaseGovernanceFingerprint: releaseGovernanceFingerprint,
      schemaVersion: ReleaseDecisionSnapshotMetadata.currentSchemaVersion,
    );

    final resultStatus = _deriveResultStatus(
      decision: decision,
      errors: errors,
    );

    final snapshot = ReleaseDecisionSnapshot(
      metadata: ReleaseDecisionSnapshotMetadata(
        snapshotId: snapshotId,
        projectId: request.releaseContext.projectId,
        releaseId: request.releaseContext.releaseId,
        releaseVersion: request.releaseContext.releaseVersion,
        commitId: request.releaseContext.commitId,
        branch: request.releaseContext.branch,
        environment: request.releaseContext.environment,
        releaseType: request.releaseContext.releaseType,
        policyId: policy.metadata.policyId,
        policyVersion: policy.metadata.policyVersion,
        policyFingerprint: policyFingerprint,
        qualityGateSnapshotId: qgRef.qualityGateSnapshotId,
        qualityGateFingerprint: qgRef.qualityGateFingerprint,
        schemaVersion: ReleaseDecisionSnapshotMetadata.currentSchemaVersion,
        calculationVersion: ReleaseGovernancePolicy.currentCalculationVersion,
        canonicalizationVersion:
            ReleaseGovernancePolicy.currentCanonicalizationVersion,
        evaluatedAt: request.referenceTime,
        createdAt: request.referenceTime,
        decision: decision,
        resultStatus: resultStatus,
        requestFingerprint: requestFingerprint,
        sourceSetFingerprint: sourceSetFingerprint,
        releaseGovernanceFingerprint: releaseGovernanceFingerprint,
      ),
      releaseContext: request.releaseContext,
      policyReference: policyReference,
      qualityGateReference: qgRef,
      decision: decision,
      compatibility: compatibility,
      eligibility: eligibility,
      coverage: coverage,
      evaluations: evaluations,
      approvalEvaluations: approvalEvaluations,
      waiverEvaluations: waiverEvaluations,
      conditions: conditions,
      evidence: request.includeEvidence ? evidence : const [],
      sourceReferences: sources.sourceReferences,
      explanations: request.includeExplanations ? explanations : const [],
      warnings: warnings,
      errors: errors,
      limitations: limitations,
      fingerprint: releaseGovernanceFingerprint,
    );

    final validationResult = _snapshotValidator.validate(snapshot);
    if (!validationResult.isValid) {
      errors.add(
        ReleaseGovernanceError(
          errorId: 'snapshot-validation',
          code: ReleaseGovernanceErrorCode.snapshotValidationFailure,
          message: validationResult.errors.join('; '),
          recoverable: true,
          classification: 'validation',
        ),
      );
    }

    return ReleaseGovernanceResult(
      status: resultStatus,
      snapshot: snapshot,
      policyReference: policyReference,
      sourceResolutionSummary: sources.resolutionSummary,
      warnings: snapshot.warnings,
      errors: snapshot.errors,
      limitations: snapshot.limitations,
    );
  }

  ReleaseGovernanceResultStatus _deriveResultStatus({
    required ReleaseGovernanceDecision decision,
    required List<ReleaseGovernanceError> errors,
  }) {
    if (errors.any((e) => !e.recoverable)) {
      return ReleaseGovernanceResultStatus.failure;
    }
    return switch (decision) {
      ReleaseGovernanceDecision.approved ||
      ReleaseGovernanceDecision.approvedWithConditions ||
      ReleaseGovernanceDecision.rejected ||
      ReleaseGovernanceDecision.pending ||
      ReleaseGovernanceDecision.expired ||
      ReleaseGovernanceDecision.cancelled =>
        ReleaseGovernanceResultStatus.success,
      ReleaseGovernanceDecision.unavailable =>
        ReleaseGovernanceResultStatus.unavailable,
      ReleaseGovernanceDecision.incompatible =>
        ReleaseGovernanceResultStatus.incompatible,
      ReleaseGovernanceDecision.error => ReleaseGovernanceResultStatus.failure,
    };
  }
}
