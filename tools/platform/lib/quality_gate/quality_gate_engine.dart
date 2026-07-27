import '../models/quality_gate/quality_gate_enums.dart';
import '../models/quality_gate/quality_gate_evidence.dart';
import '../models/quality_gate/quality_gate_messages.dart';
import '../models/quality_gate/quality_gate_policy.dart';
import '../models/quality_gate/quality_gate_request.dart';
import '../models/quality_gate/quality_gate_snapshot.dart';
import 'quality_gate_canonical_serializer.dart';
import 'quality_gate_compatibility_checker.dart';
import 'quality_gate_coverage_calculator.dart';
import 'quality_gate_decision_aggregator.dart';
import 'quality_gate_eligibility_evaluator.dart';
import 'quality_gate_explanation_builder.dart';
import 'quality_gate_identity_builder.dart';
import 'quality_gate_policy_validator.dart';
import 'quality_gate_rule_evaluator.dart';
import 'quality_gate_rule_set_evaluator.dart';
import 'quality_gate_snapshot_validator.dart';
import 'resolved_quality_gate_sources.dart';

/// Stateless engine that evaluates quality gate policies over published artifacts.
class QualityGateEngine {
  QualityGateEngine({
    QualityGatePolicyValidator? policyValidator,
    QualityGateRuleEvaluator? ruleEvaluator,
    QualityGateRuleSetEvaluator? ruleSetEvaluator,
    QualityGateCompatibilityChecker? compatibilityChecker,
    QualityGateEligibilityEvaluator? eligibilityEvaluator,
    QualityGateCoverageCalculator? coverageCalculator,
    QualityGateDecisionAggregator? decisionAggregator,
    QualityGateExplanationBuilder? explanationBuilder,
    QualityGateIdentityBuilder? identityBuilder,
    QualityGateCanonicalSerializer? serializer,
    QualityGateSnapshotValidator? snapshotValidator,
  })  : _policyValidator =
            policyValidator ?? const QualityGatePolicyValidator(),
        _ruleEvaluator = ruleEvaluator ?? QualityGateRuleEvaluator(),
        _ruleSetEvaluator =
            ruleSetEvaluator ?? const QualityGateRuleSetEvaluator(),
        _compatibilityChecker =
            compatibilityChecker ?? const QualityGateCompatibilityChecker(),
        _eligibilityEvaluator =
            eligibilityEvaluator ?? const QualityGateEligibilityEvaluator(),
        _coverageCalculator =
            coverageCalculator ?? const QualityGateCoverageCalculator(),
        _decisionAggregator =
            decisionAggregator ?? const QualityGateDecisionAggregator(),
        _explanationBuilder =
            explanationBuilder ?? const QualityGateExplanationBuilder(),
        _identityBuilder =
            identityBuilder ?? const QualityGateIdentityBuilder(),
        _serializer = serializer ?? const QualityGateCanonicalSerializer(),
        _snapshotValidator =
            snapshotValidator ?? const QualityGateSnapshotValidator();

  final QualityGatePolicyValidator _policyValidator;
  final QualityGateRuleEvaluator _ruleEvaluator;
  final QualityGateRuleSetEvaluator _ruleSetEvaluator;
  final QualityGateCompatibilityChecker _compatibilityChecker;
  final QualityGateEligibilityEvaluator _eligibilityEvaluator;
  final QualityGateCoverageCalculator _coverageCalculator;
  final QualityGateDecisionAggregator _decisionAggregator;
  final QualityGateExplanationBuilder _explanationBuilder;
  final QualityGateIdentityBuilder _identityBuilder;
  final QualityGateCanonicalSerializer _serializer;
  final QualityGateSnapshotValidator _snapshotValidator;

  QualityGateResult evaluate({
    required QualityGateRequest request,
    required QualityGatePolicy policy,
    required ResolvedQualityGateSources sources,
  }) {
    final policyValidation = _policyValidator.validate(
      policy,
      allowRetired: request.historicalEvaluation,
    );
    if (!policyValidation.isValid) {
      return QualityGateResult(
        status: QualityGateResultStatus.failure,
        errors: [
          QualityGateError(
            errorId: 'policy-invalid',
            code: 'policy_invalid',
            message: policyValidation.errors.join('; '),
            recoverable: false,
            classification: 'validation',
          ),
        ],
        validationResult: policyValidation,
        sourceResolutionSummary: sources.resolutionSummary,
      );
    }

    if (request.projectId.isEmpty) {
      return QualityGateResult(
        status: QualityGateResultStatus.failure,
        errors: const [
          QualityGateError(
            errorId: 'request-invalid',
            code: 'request_invalid',
            message: 'projectId is required',
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

    final orderedRuleSets = policy.ruleSets.toList()
      ..sort((a, b) {
        final orderCmp = a.order.compareTo(b.order);
        if (orderCmp != 0) return orderCmp;
        return a.ruleSetId.compareTo(b.ruleSetId);
      });

    final filteredRuleSets = request.requestedRuleSetIds == null
        ? orderedRuleSets
        : orderedRuleSets
            .where((s) => request.requestedRuleSetIds!.contains(s.ruleSetId))
            .toList();

    final enabledRules = policy.allRules.where((rule) {
      if (!rule.enabled) return false;
      if (request.requestedRuleSetIds != null) {
        final parent = filteredRuleSets.cast<QualityGateRuleSet?>().firstWhere(
              (set) => set!.rules.any((r) => r.ruleId == rule.ruleId),
              orElse: () => null,
            );
        if (parent == null) return false;
      }
      return true;
    }).toList();

    final eligibility = _eligibilityEvaluator.evaluate(
      request: request,
      policy: policy,
      sources: sources,
      compatibility: compatibility,
      enabledRules: enabledRules
          .where(
              (r) => r.requirement != QualityGateRuleRequirement.informational)
          .toList(),
    );

    final evaluations = <QualityGateEvaluation>[];
    final ruleSetEvaluations = <QualityGateRuleSetEvaluation>[];
    final warnings = <QualityGateWarning>[...sources.warnings];
    final errors = <QualityGateError>[...sources.errors];
    final limitations = <QualityGateLimitation>[...sources.limitations];

    for (final ruleSet in filteredRuleSets) {
      final orderedRules = ruleSet.rules.toList()
        ..sort((a, b) {
          final orderCmp = a.order.compareTo(b.order);
          if (orderCmp != 0) return orderCmp;
          return a.ruleId.compareTo(b.ruleId);
        });

      final memberEvaluations = <QualityGateEvaluation>[];
      for (final rule in orderedRules) {
        final evaluation = _ruleEvaluator.evaluate(
          rule: rule,
          policy: policy,
          request: request,
          sources: sources,
          ruleSetId: ruleSet.ruleSetId,
        );
        memberEvaluations.add(evaluation);
        evaluations.add(evaluation);
        warnings.addAll(evaluation.warnings);
        errors.addAll(evaluation.errors);
        limitations.addAll(evaluation.limitations);
      }

      ruleSetEvaluations.add(
        _ruleSetEvaluator.evaluate(
          ruleSet: ruleSet,
          memberEvaluations: memberEvaluations,
        ),
      );
    }

    evaluations.sort((a, b) => a.ruleId.compareTo(b.ruleId));

    final coverage = _coverageCalculator.calculate(
      policy: policy,
      evaluations: evaluations,
      ruleSetEvaluations: ruleSetEvaluations,
      sources: sources,
    );

    final decision = _decisionAggregator.aggregate(
      decisionPolicy: policy.decisionPolicy,
      compatibility: compatibility,
      eligibility: eligibility,
      coverage: coverage,
      evaluations: evaluations,
      ruleSetEvaluations: ruleSetEvaluations,
      sourceResolutionSummary: sources.resolutionSummary,
      errors: errors,
    );

    final policyFingerprint = _serializer.policyFingerprint(policy);
    final requestFingerprint = _serializer.requestFingerprint(request);
    final sourceSetFingerprint = _serializer.sourceSetFingerprint(
      sources.sourceReferences.map((r) => r.toJson()).toList(),
    );

    final decisionExplanation = _explanationBuilder.buildDecisionExplanation(
      decision: decision,
      policyId: policy.metadata.policyId,
      policyVersion: policy.metadata.policyVersion,
      failedRuleCount: coverage.failedRuleCount,
      blockingFailureCount: evaluations
          .where(
            (e) =>
                e.status == QualityGateRuleStatus.failed &&
                e.decisionImpact == QualityGateDecisionImpact.blocksApproval,
          )
          .length,
    );

    final explanations = <QualityGateExplanation>[
      decisionExplanation,
      ...evaluations.map((e) => e.explanation),
      ...ruleSetEvaluations
          .where((e) => e.explanation != null)
          .map((e) => e.explanation!),
    ]..sort((a, b) => a.explanationId.compareTo(b.explanationId));

    final evidence = evaluations.expand((e) => e.evidence).toList()
      ..sort((a, b) {
        final sourceCmp =
            a.sourceType.wireName.compareTo(b.sourceType.wireName);
        if (sourceCmp != 0) return sourceCmp;
        return a.evidenceId.compareTo(b.evidenceId);
      });

    final blockingFailureCount = evaluations
        .where(
          (e) =>
              e.status == QualityGateRuleStatus.failed &&
              e.decisionImpact == QualityGateDecisionImpact.blocksApproval,
        )
        .length;

    final snapshotWithoutFingerprint = QualityGateSnapshot(
      metadata: QualityGateSnapshotMetadata(
        qualityGateSnapshotId: '',
        qualityGateFingerprint: '',
        requestFingerprint: requestFingerprint,
        policyFingerprint: policyFingerprint,
        projectId: request.projectId,
        commitId: request.commitId,
        branch: request.branch,
        schemaVersion: QualityGateSnapshotMetadata.currentSchemaVersion,
        calculationVersion:
            QualityGateSnapshotMetadata.currentCalculationVersion,
        canonicalizationVersion:
            QualityGateSnapshotMetadata.currentCanonicalizationVersion,
        createdAt: request.createdAt,
        evaluatedAt: request.referenceTime,
        decision: decision,
        policyId: policy.metadata.policyId,
        policyVersion: policy.metadata.policyVersion,
        totalRuleCount: coverage.totalRuleCount,
        evaluatedRuleCount: coverage.evaluatedRuleCount,
        failedRuleCount: coverage.failedRuleCount,
        blockingFailureCount: blockingFailureCount,
        warningCount: warnings.length,
        errorCount: errors.length,
        sourceCount: sources.sourceReferences.length,
      ),
      policyReference: policy.metadata.versionRef,
      decision: decision,
      eligibility: eligibility,
      compatibility: compatibility,
      coverage: coverage,
      evaluations: evaluations,
      ruleSetEvaluations: ruleSetEvaluations,
      evidence: evidence,
      sourceReferences: sources.sourceReferences,
      explanations: request.includeExplanations ? explanations : const [],
      warnings: request.includeWarnings ? warnings : const [],
      errors: errors,
      limitations: request.includeLimitations ? limitations : const [],
    );

    final qualityGateFingerprint = _serializer.fingerprintFromString(
      [
        policyFingerprint,
        requestFingerprint,
        sourceSetFingerprint,
        _serializer.snapshotFingerprint(snapshotWithoutFingerprint),
      ].join(':'),
    );

    final snapshotId = _identityBuilder.buildSnapshotId(
      projectId: request.projectId,
      policyId: policy.metadata.policyId,
      policyVersion: policy.metadata.policyVersion,
      qualityGateFingerprint: qualityGateFingerprint,
      schemaVersion: QualityGateSnapshotMetadata.currentSchemaVersion,
    );

    final snapshot = QualityGateSnapshot(
      metadata: QualityGateSnapshotMetadata(
        qualityGateSnapshotId: snapshotId,
        qualityGateFingerprint: qualityGateFingerprint,
        requestFingerprint: requestFingerprint,
        policyFingerprint: policyFingerprint,
        projectId: request.projectId,
        commitId: request.commitId,
        branch: request.branch,
        schemaVersion: QualityGateSnapshotMetadata.currentSchemaVersion,
        calculationVersion:
            QualityGateSnapshotMetadata.currentCalculationVersion,
        canonicalizationVersion:
            QualityGateSnapshotMetadata.currentCanonicalizationVersion,
        createdAt: request.createdAt,
        evaluatedAt: request.referenceTime,
        decision: decision,
        policyId: policy.metadata.policyId,
        policyVersion: policy.metadata.policyVersion,
        totalRuleCount: coverage.totalRuleCount,
        evaluatedRuleCount: coverage.evaluatedRuleCount,
        failedRuleCount: coverage.failedRuleCount,
        blockingFailureCount: blockingFailureCount,
        warningCount: warnings.length,
        errorCount: errors.length,
        sourceCount: sources.sourceReferences.length,
      ),
      policyReference: policy.metadata.versionRef,
      decision: decision,
      eligibility: eligibility,
      compatibility: compatibility,
      coverage: coverage,
      evaluations: evaluations,
      ruleSetEvaluations: ruleSetEvaluations,
      evidence: request.includeEvidence ? evidence : const [],
      sourceReferences: sources.sourceReferences,
      explanations: request.includeExplanations ? explanations : const [],
      warnings: request.includeWarnings ? warnings : const [],
      errors: errors,
      limitations: request.includeLimitations ? limitations : const [],
    );

    final validationResult = _snapshotValidator.validate(snapshot);
    final resultStatus = _deriveResultStatus(
      decision: decision,
      validationResult: validationResult,
      errors: errors,
    );

    return QualityGateResult(
      status: resultStatus,
      snapshot: snapshot,
      warnings: snapshot.warnings,
      errors: snapshot.errors,
      limitations: snapshot.limitations,
      validationResult: validationResult,
      sourceResolutionSummary: sources.resolutionSummary,
    );
  }

  QualityGateResultStatus _deriveResultStatus({
    required QualityGateDecision decision,
    required QualityGateValidationResult validationResult,
    required List<QualityGateError> errors,
  }) {
    if (!validationResult.isValid || errors.any((e) => !e.recoverable)) {
      return QualityGateResultStatus.failure;
    }
    return switch (decision) {
      QualityGateDecision.passed ||
      QualityGateDecision.failed =>
        QualityGateResultStatus.success,
      QualityGateDecision.partial => QualityGateResultStatus.partial,
      QualityGateDecision.unavailable => QualityGateResultStatus.unavailable,
      QualityGateDecision.incompatible => QualityGateResultStatus.incompatible,
      QualityGateDecision.error => QualityGateResultStatus.failure,
    };
  }
}
