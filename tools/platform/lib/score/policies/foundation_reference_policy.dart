import '../../models/score/score_enums.dart';
import '../../models/score/score_policy.dart';

/// Experimental reference policy for Score Engine validation.
/// This is NOT the MasterPalm Engineering Score (MES).
class FoundationReferencePolicy {
  const FoundationReferencePolicy._();

  static const policyId = 'foundation-reference-v1';

  static ScorePolicy create() {
    const scale = ScoreScale();
    return ScorePolicy(
      policyId: policyId,
      name: 'Foundation Reference Policy v1',
      description:
          'Experimental scoring policy for engine validation. Not MES.',
      policySchemaVersion: ScorePolicy.currentSchemaVersion,
      policyVersion: 1,
      canonicalizationVersion: ScorePolicy.currentCanonicalizationVersion,
      scoreScale: scale,
      aggregationMethod: ScoreAggregationMethod.weightedAverage,
      missingDataPolicy: ScoreMissingDataPolicy.excludeAndReweight,
      minimumEvidenceCoverage: 50,
      metadata: const ScorePolicyMetadata(
        experimental: true,
        author: 'platform-score-engine',
        tags: ['experimental', 'foundation', 'not-mes'],
      ),
      dimensions: [
        ScoreDimensionPolicy(
          dimensionId: 'cycleExposure',
          name: 'Cycle Exposure',
          weight: ScoreWeight(value: 1.2),
          aggregationMethod: ScoreAggregationMethod.weightedAverage,
          rules: [
            ScoreRule(
              ruleId: 'cycle-count-low',
              metricId: 'graph.cycle.count',
              condition: const ScoreRuleCondition(
                operator: ScoreRuleOperator.lessThanOrEqual,
                threshold: 0,
              ),
              outcome: const ScoreRuleOutcome(score: 100),
              normalization: const ScoreNormalization(
                method: ScoreNormalizationMethod.direct,
              ),
              description: 'No structural cycles detected',
            ),
            ScoreRule(
              ruleId: 'cycle-count-present',
              metricId: 'graph.cycle.count',
              condition: const ScoreRuleCondition(
                operator: ScoreRuleOperator.greaterThan,
                threshold: 0,
              ),
              outcome: const ScoreRuleOutcome(score: 40),
              normalization: const ScoreNormalization(
                method: ScoreNormalizationMethod.inverse,
                domainMax: 5,
              ),
              description: 'Structural cycles present',
            ),
          ],
        ),
        ScoreDimensionPolicy(
          dimensionId: 'connectivity',
          name: 'Connectivity',
          weight: ScoreWeight(value: 1.0),
          aggregationMethod: ScoreAggregationMethod.weightedAverage,
          rules: [
            ScoreRule(
              ruleId: 'isolated-count',
              metricId: 'graph.component.isolated_count',
              condition: const ScoreRuleCondition(
                operator: ScoreRuleOperator.exists,
              ),
              outcome: const ScoreRuleOutcome(score: 80),
              normalization: const ScoreNormalization(
                method: ScoreNormalizationMethod.inverse,
                domainMax: 10,
              ),
            ),
          ],
        ),
        ScoreDimensionPolicy(
          dimensionId: 'dependencyStructure',
          name: 'Dependency Structure',
          weight: ScoreWeight(value: 1.0),
          aggregationMethod: ScoreAggregationMethod.weightedAverage,
          rules: [
            ScoreRule(
              ruleId: 'graph-density',
              metricId: 'graph.density',
              condition: const ScoreRuleCondition(
                operator: ScoreRuleOperator.exists,
              ),
              outcome: const ScoreRuleOutcome(score: 70),
              normalization: const ScoreNormalization(
                method: ScoreNormalizationMethod.linearRange,
                domainMin: 0,
                domainMax: 1,
              ),
            ),
          ],
        ),
        ScoreDimensionPolicy(
          dimensionId: 'structuralComplexity',
          name: 'Structural Complexity',
          weight: ScoreWeight(value: 0.8),
          aggregationMethod: ScoreAggregationMethod.weightedAverage,
          rules: [
            ScoreRule(
              ruleId: 'fan-out-max',
              metricId: 'graph.degree.fan_out.max',
              condition: const ScoreRuleCondition(
                operator: ScoreRuleOperator.exists,
              ),
              outcome: const ScoreRuleOutcome(score: 75),
              normalization: const ScoreNormalization(
                method: ScoreNormalizationMethod.cappedLinear,
                domainMin: 0,
                domainMax: 20,
              ),
            ),
          ],
        ),
        ScoreDimensionPolicy(
          dimensionId: 'guardianCompliance',
          name: 'Guardian Compliance',
          weight: ScoreWeight(value: 1.5),
          aggregationMethod: ScoreAggregationMethod.weightedAverage,
          missingDataPolicy: ScoreMissingDataPolicy.markUnavailable,
          rules: [
            ScoreRule(
              ruleId: 'violation-count-zero',
              metricId: 'guardian.violation.count',
              condition: const ScoreRuleCondition(
                operator: ScoreRuleOperator.lessThanOrEqual,
                threshold: 0,
              ),
              outcome: const ScoreRuleOutcome(score: 100),
              normalization: const ScoreNormalization(
                method: ScoreNormalizationMethod.direct,
              ),
              requiresGuardian: true,
            ),
            ScoreRule(
              ruleId: 'violation-count-high',
              metricId: 'guardian.violation.count',
              condition: const ScoreRuleCondition(
                operator: ScoreRuleOperator.greaterThan,
                threshold: 0,
              ),
              outcome: const ScoreRuleOutcome(score: 30),
              normalization: const ScoreNormalization(
                method: ScoreNormalizationMethod.inverse,
                domainMax: 10,
              ),
              requiresGuardian: true,
            ),
            ScoreRule(
              ruleId: 'guardian-go',
              metricId: 'guardian.decision',
              condition: const ScoreRuleCondition(
                operator: ScoreRuleOperator.equals,
                expectedText: 'go',
              ),
              outcome: const ScoreRuleOutcome(score: 100),
              normalization: const ScoreNormalization(
                method: ScoreNormalizationMethod.direct,
              ),
              requiresGuardian: true,
            ),
          ],
        ),
        ScoreDimensionPolicy(
          dimensionId: 'changeStability',
          name: 'Change Stability',
          weight: ScoreWeight(value: 0.5),
          aggregationMethod: ScoreAggregationMethod.minimum,
          missingDataPolicy: ScoreMissingDataPolicy.markUnavailable,
          rules: [
            ScoreRule(
              ruleId: 'no-metric-changes',
              metricId: 'history.metric',
              condition: const ScoreRuleCondition(
                operator: ScoreRuleOperator.changed,
                historyChangeType: 'metricValueChanged',
              ),
              outcome: const ScoreRuleOutcome(score: 50),
              normalization: const ScoreNormalization(
                method: ScoreNormalizationMethod.direct,
              ),
              requiresHistoryDiff: true,
            ),
            ScoreRule(
              ruleId: 'stable-no-changes',
              metricId: 'history.stability',
              condition: const ScoreRuleCondition(
                operator: ScoreRuleOperator.changed,
              ),
              outcome: const ScoreRuleOutcome(score: 100),
              normalization: const ScoreNormalization(
                method: ScoreNormalizationMethod.direct,
              ),
              requiresHistoryDiff: true,
            ),
          ],
        ),
      ],
    );
  }
}
