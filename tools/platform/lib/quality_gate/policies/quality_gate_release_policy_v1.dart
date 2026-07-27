import '../../models/quality_gate/quality_gate_enums.dart';
import '../../models/quality_gate/quality_gate_governance.dart';
import '../../models/quality_gate/quality_gate_policy.dart';
import '../../models/quality_gate/quality_gate_rule_value.dart';

/// Default evidence policy for official release gate rules.
const QualityGateEvidencePolicy kReleaseGateEvidencePolicy =
    QualityGateEvidencePolicy(
  requireSourceReference: true,
  requireArtifactId: true,
  requireFingerprint: true,
  requirePolicyReference: true,
  requireActualValue: true,
  requireExpectedValue: true,
  requireExplanation: true,
  minimumEvidenceCount: 1,
);

/// Candidate release quality gate policy v1.
class QualityGateReleasePolicyV1 {
  const QualityGateReleasePolicyV1._();

  static const policyId = 'quality-gate-release-v1';

  static QualityGatePolicy create() {
    return QualityGatePolicy(
      metadata: const QualityGatePolicyMetadata(
        policyId: policyId,
        policyName: 'MasterPalm Release Quality Gate',
        policyVersion: 1,
        schemaVersion: QualityGatePolicy.currentSchemaVersion,
        calculationVersion: QualityGatePolicy.currentCalculationVersion,
        canonicalizationVersion:
            QualityGatePolicy.currentCanonicalizationVersion,
        status: QualityGatePolicyStatus.candidate,
        owner: 'MasterPalm Engineering Governance',
        createdAt: '2026-01-01T00:00:00.000Z',
        rationale:
            'Candidate release gate evaluating minimum engineering conditions for technical approval without recalculating upstream artifacts.',
        changelog: [
          QualityGatePolicyChangelogEntry(
            version: 1,
            summary: 'Initial candidate release quality gate policy',
            author: 'MasterPalm Engineering Governance',
            createdAt: '2026-01-01T00:00:00.000Z',
          ),
        ],
        tags: ['quality-gate', 'release', 'candidate'],
      ),
      governance: const QualityGateGovernance(
        policyOwner: 'MasterPalm Engineering Governance',
        approvalAuthority: 'MasterPalm Engineering Governance',
        versioningStrategy: 'immutable-version-on-normative-change',
        thresholdChangePolicy: 'new-policy-version-required',
        ruleChangePolicy: 'new-policy-version-required',
        deprecationPolicy: 'deprecated-policies-remain-for-historical-replay',
        rollbackPolicy: 'explicit-version-selection-only',
        evidenceRequirements:
            'every-rule-must-produce-traceable-evidence-with-source-reference',
        compatibilityRequirements:
            'explicit-compatibility-check-before-evaluation',
        auditRequirements:
            'policy-id-version-fingerprints-and-explanations-preserved',
      ),
      decisionPolicy: const QualityGateDecisionPolicy(
        failOnBlockingFailure: true,
        failOnCriticalFailure: true,
        partialOnRequiredUnavailable: true,
        unavailableOnMissingRequiredSources: true,
        incompatibleOnSourceMismatch: true,
        minimumCoveragePercentage: 100,
        minimumEvaluatedRequiredRules: 1,
        warningsAffectDecision: false,
        optionalFailuresAffectDecision: false,
        informationalRulesAffectDecision: false,
        ruleSetFailureMode: 'blocking',
      ),
      requiredSourceTypes: const [
        QualityGateSourceType.metrics,
        QualityGateSourceType.guardian,
        QualityGateSourceType.score,
        QualityGateSourceType.mes,
      ],
      ruleSets: [
        _sourceIntegrityRuleSet(),
        _guardianComplianceRuleSet(),
        _engineeringScoreRuleSet(),
        _mesComplianceRuleSet(),
        _architectureRiskRuleSet(),
        _operationalIntegrityRuleSet(),
        _historicalStabilityRuleSet(),
      ],
    );
  }

  static QualityGateRuleSet _sourceIntegrityRuleSet() {
    return QualityGateRuleSet(
      ruleSetId: 'source-integrity',
      name: 'Source Integrity',
      description:
          'Ensures injected artifacts belong to a coherent project context.',
      aggregationMode: QualityGateRuleSetAggregationMode.all,
      required: true,
      severity: QualityGateRuleSeverity.critical,
      order: 1,
      rules: [
        QualityGateRule(
          ruleId: 'QG001',
          name: 'Sources belong to same project',
          description:
              'All required source artifacts must reference the same project.',
          target: QualityGateRuleTarget.sourceProjectConsistency,
          operator: QualityGateRuleOperator.isTrue,
          requirement: QualityGateRuleRequirement.required,
          severity: QualityGateRuleSeverity.critical,
          missingDataPolicy: QualityGateMissingDataPolicy.unavailable,
          incompatibleDataPolicy:
              QualityGateIncompatibleDataPolicy.incompatible,
          evidencePolicy: kReleaseGateEvidencePolicy,
          explanationTemplateId: 'qg.source-project-consistency',
          order: 1,
        ),
        QualityGateRule(
          ruleId: 'QG002',
          name: 'Sources belong to same commit when required',
          description:
              'When commit context is required, all sources must share the same commit.',
          target: QualityGateRuleTarget.sourceCommitConsistency,
          operator: QualityGateRuleOperator.isTrue,
          requirement: QualityGateRuleRequirement.required,
          severity: QualityGateRuleSeverity.blocking,
          missingDataPolicy: QualityGateMissingDataPolicy.notApplicable,
          incompatibleDataPolicy:
              QualityGateIncompatibleDataPolicy.incompatible,
          evidencePolicy: kReleaseGateEvidencePolicy,
          explanationTemplateId: 'qg.source-commit-consistency',
          order: 2,
        ),
      ],
    );
  }

  static QualityGateRuleSet _guardianComplianceRuleSet() {
    return QualityGateRuleSet(
      ruleSetId: 'guardian-compliance',
      name: 'Guardian Compliance',
      description: 'Guardian GO/NO-GO and critical violation thresholds.',
      aggregationMode: QualityGateRuleSetAggregationMode.all,
      required: true,
      severity: QualityGateRuleSeverity.critical,
      order: 2,
      rules: [
        QualityGateRule(
          ruleId: 'QG003',
          name: 'Guardian decision must be GO',
          description: 'Guardian decision must be GO for release approval.',
          target: QualityGateRuleTarget.guardianDecision,
          operator: QualityGateRuleOperator.equals,
          expectedValue: const QualityGateStringValue('GO'),
          requirement: QualityGateRuleRequirement.required,
          severity: QualityGateRuleSeverity.critical,
          missingDataPolicy: QualityGateMissingDataPolicy.unavailable,
          incompatibleDataPolicy: QualityGateIncompatibleDataPolicy.fail,
          evidencePolicy: kReleaseGateEvidencePolicy,
          explanationTemplateId: 'qg.guardian-go',
          order: 3,
        ),
        QualityGateRule(
          ruleId: 'QG004',
          name: 'Guardian has no critical violations',
          description: 'Guardian must report zero critical violations.',
          target: QualityGateRuleTarget.guardianCriticalViolationCount,
          operator: QualityGateRuleOperator.equals,
          expectedValue: const QualityGateIntegerValue(0),
          requirement: QualityGateRuleRequirement.required,
          severity: QualityGateRuleSeverity.critical,
          missingDataPolicy: QualityGateMissingDataPolicy.unavailable,
          incompatibleDataPolicy: QualityGateIncompatibleDataPolicy.fail,
          evidencePolicy: kReleaseGateEvidencePolicy,
          explanationTemplateId: 'qg.guardian-critical-violations',
          order: 4,
        ),
      ],
    );
  }

  static QualityGateRuleSet _engineeringScoreRuleSet() {
    return QualityGateRuleSet(
      ruleSetId: 'engineering-score',
      name: 'Engineering Score',
      description: 'Minimum engineering score and coverage thresholds.',
      aggregationMode: QualityGateRuleSetAggregationMode.all,
      required: true,
      severity: QualityGateRuleSeverity.blocking,
      order: 3,
      rules: [
        QualityGateRule(
          ruleId: 'QG005',
          name: 'Engineering Score minimum',
          description: 'Global engineering score must be at least 75.',
          target: QualityGateRuleTarget.engineeringScoreGlobal,
          operator: QualityGateRuleOperator.greaterThanOrEqual,
          expectedValue: const QualityGateDecimalValue(75),
          requirement: QualityGateRuleRequirement.required,
          severity: QualityGateRuleSeverity.blocking,
          missingDataPolicy: QualityGateMissingDataPolicy.unavailable,
          incompatibleDataPolicy: QualityGateIncompatibleDataPolicy.fail,
          evidencePolicy: kReleaseGateEvidencePolicy,
          explanationTemplateId: 'qg.engineering-score-minimum',
          order: 5,
        ),
        QualityGateRule(
          ruleId: 'QG006',
          name: 'Engineering Score coverage minimum',
          description: 'Engineering score coverage must be at least 80%.',
          target: QualityGateRuleTarget.engineeringScoreCoverage,
          operator: QualityGateRuleOperator.greaterThanOrEqual,
          expectedValue: const QualityGatePercentageValue(80),
          requirement: QualityGateRuleRequirement.required,
          severity: QualityGateRuleSeverity.blocking,
          missingDataPolicy: QualityGateMissingDataPolicy.unavailable,
          incompatibleDataPolicy: QualityGateIncompatibleDataPolicy.fail,
          evidencePolicy: kReleaseGateEvidencePolicy,
          explanationTemplateId: 'qg.engineering-score-coverage',
          order: 6,
        ),
      ],
    );
  }

  static QualityGateRuleSet _mesComplianceRuleSet() {
    return QualityGateRuleSet(
      ruleSetId: 'mes-compliance',
      name: 'MES Compliance',
      description: 'MES score, eligibility, coverage and compatibility.',
      aggregationMode: QualityGateRuleSetAggregationMode.all,
      required: true,
      severity: QualityGateRuleSeverity.blocking,
      order: 4,
      rules: [
        QualityGateRule(
          ruleId: 'QG007',
          name: 'MES minimum',
          description: 'MES global score must be at least 80.',
          target: QualityGateRuleTarget.mesGlobalScore,
          operator: QualityGateRuleOperator.greaterThanOrEqual,
          expectedValue: const QualityGateDecimalValue(80),
          requirement: QualityGateRuleRequirement.required,
          severity: QualityGateRuleSeverity.blocking,
          missingDataPolicy: QualityGateMissingDataPolicy.unavailable,
          incompatibleDataPolicy: QualityGateIncompatibleDataPolicy.fail,
          evidencePolicy: kReleaseGateEvidencePolicy,
          explanationTemplateId: 'qg.mes-minimum',
          order: 7,
        ),
        QualityGateRule(
          ruleId: 'QG008',
          name: 'MES eligible',
          description: 'MES eligibility must be eligible.',
          target: QualityGateRuleTarget.mesEligibility,
          operator: QualityGateRuleOperator.equals,
          expectedValue: const QualityGateEnumValue(
            domain: 'mesEligibility',
            value: 'eligible',
          ),
          requirement: QualityGateRuleRequirement.required,
          severity: QualityGateRuleSeverity.blocking,
          missingDataPolicy: QualityGateMissingDataPolicy.unavailable,
          incompatibleDataPolicy: QualityGateIncompatibleDataPolicy.fail,
          evidencePolicy: kReleaseGateEvidencePolicy,
          explanationTemplateId: 'qg.mes-eligibility',
          order: 8,
        ),
        QualityGateRule(
          ruleId: 'QG009',
          name: 'MES coverage minimum',
          description: 'MES coverage must be at least 80%.',
          target: QualityGateRuleTarget.mesCoverage,
          operator: QualityGateRuleOperator.greaterThanOrEqual,
          expectedValue: const QualityGatePercentageValue(80),
          requirement: QualityGateRuleRequirement.required,
          severity: QualityGateRuleSeverity.blocking,
          missingDataPolicy: QualityGateMissingDataPolicy.unavailable,
          incompatibleDataPolicy: QualityGateIncompatibleDataPolicy.fail,
          evidencePolicy: kReleaseGateEvidencePolicy,
          explanationTemplateId: 'qg.mes-coverage',
          order: 9,
        ),
        QualityGateRule(
          ruleId: 'QG010',
          name: 'MES compatible',
          description: 'MES snapshot must be compatible with required sources.',
          target: QualityGateRuleTarget.mesCompatibility,
          operator: QualityGateRuleOperator.isCompatible,
          requirement: QualityGateRuleRequirement.required,
          severity: QualityGateRuleSeverity.critical,
          missingDataPolicy: QualityGateMissingDataPolicy.unavailable,
          incompatibleDataPolicy:
              QualityGateIncompatibleDataPolicy.incompatible,
          evidencePolicy: kReleaseGateEvidencePolicy,
          explanationTemplateId: 'qg.mes-compatibility',
          order: 10,
        ),
      ],
    );
  }

  static QualityGateRuleSet _architectureRiskRuleSet() {
    return QualityGateRuleSet(
      ruleSetId: 'architecture-risk',
      name: 'Architecture Risk',
      description: 'Structural graph risk thresholds from published metrics.',
      aggregationMode: QualityGateRuleSetAggregationMode.all,
      required: true,
      severity: QualityGateRuleSeverity.critical,
      order: 5,
      rules: [
        QualityGateRule(
          ruleId: 'QG011',
          name: 'No critical cycles',
          description: 'Critical cycle count must be zero.',
          target: QualityGateRuleTarget.criticalCycleCount,
          operator: QualityGateRuleOperator.equals,
          expectedValue: const QualityGateIntegerValue(0),
          requirement: QualityGateRuleRequirement.required,
          severity: QualityGateRuleSeverity.critical,
          missingDataPolicy: QualityGateMissingDataPolicy.unavailable,
          incompatibleDataPolicy: QualityGateIncompatibleDataPolicy.fail,
          evidencePolicy: kReleaseGateEvidencePolicy,
          explanationTemplateId: 'qg.critical-cycles',
          order: 11,
        ),
      ],
    );
  }

  static QualityGateRuleSet _operationalIntegrityRuleSet() {
    return QualityGateRuleSet(
      ruleSetId: 'operational-integrity',
      name: 'Operational Integrity',
      description: 'Optional observability integrity checks.',
      aggregationMode: QualityGateRuleSetAggregationMode.all,
      required: false,
      severity: QualityGateRuleSeverity.warning,
      order: 6,
      rules: [
        QualityGateRule(
          ruleId: 'QG012',
          name: 'Telemetry has no failed operations',
          description: 'Telemetry failure count should be zero when available.',
          target: QualityGateRuleTarget.telemetryFailureCount,
          operator: QualityGateRuleOperator.equals,
          expectedValue: const QualityGateIntegerValue(0),
          requirement: QualityGateRuleRequirement.optional,
          severity: QualityGateRuleSeverity.warning,
          missingDataPolicy: QualityGateMissingDataPolicy.skip,
          incompatibleDataPolicy: QualityGateIncompatibleDataPolicy.skip,
          evidencePolicy: kReleaseGateEvidencePolicy,
          explanationTemplateId: 'qg.telemetry-failures',
          order: 12,
        ),
        QualityGateRule(
          ruleId: 'QG013',
          name: 'Telemetry has no incomplete operations',
          description:
              'Telemetry incomplete operation count should be zero when available.',
          target: QualityGateRuleTarget.telemetryIncompleteOperationCount,
          operator: QualityGateRuleOperator.equals,
          expectedValue: const QualityGateIntegerValue(0),
          requirement: QualityGateRuleRequirement.optional,
          severity: QualityGateRuleSeverity.warning,
          missingDataPolicy: QualityGateMissingDataPolicy.skip,
          incompatibleDataPolicy: QualityGateIncompatibleDataPolicy.skip,
          evidencePolicy: kReleaseGateEvidencePolicy,
          explanationTemplateId: 'qg.telemetry-incomplete',
          order: 13,
        ),
        QualityGateRule(
          ruleId: 'QG014',
          name: 'Telemetry compatibility',
          description: 'Telemetry snapshot should be compatible when provided.',
          target: QualityGateRuleTarget.telemetryCompatibility,
          operator: QualityGateRuleOperator.isCompatible,
          requirement: QualityGateRuleRequirement.optional,
          severity: QualityGateRuleSeverity.warning,
          missingDataPolicy: QualityGateMissingDataPolicy.skip,
          incompatibleDataPolicy: QualityGateIncompatibleDataPolicy.skip,
          evidencePolicy: kReleaseGateEvidencePolicy,
          explanationTemplateId: 'qg.telemetry-compatibility',
          order: 14,
        ),
      ],
    );
  }

  static QualityGateRuleSet _historicalStabilityRuleSet() {
    return QualityGateRuleSet(
      ruleSetId: 'historical-stability',
      name: 'Historical Stability',
      description: 'Optional history regression checks.',
      aggregationMode: QualityGateRuleSetAggregationMode.all,
      required: false,
      severity: QualityGateRuleSeverity.warning,
      order: 7,
      rules: [
        QualityGateRule(
          ruleId: 'QG015',
          name: 'No known structural regression',
          description:
              'History regression count should be zero when available.',
          target: QualityGateRuleTarget.historyRegressionCount,
          operator: QualityGateRuleOperator.equals,
          expectedValue: const QualityGateIntegerValue(0),
          requirement: QualityGateRuleRequirement.optional,
          severity: QualityGateRuleSeverity.warning,
          missingDataPolicy: QualityGateMissingDataPolicy.skip,
          incompatibleDataPolicy: QualityGateIncompatibleDataPolicy.skip,
          evidencePolicy: kReleaseGateEvidencePolicy,
          explanationTemplateId: 'qg.history-regression',
          order: 15,
        ),
      ],
    );
  }
}
