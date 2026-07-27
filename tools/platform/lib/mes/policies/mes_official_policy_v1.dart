import '../../models/mes/mes_enums.dart';
import '../../models/mes/mes_policy.dart';
import '../../models/score/score_enums.dart';
import '../../models/score/score_policy.dart';

/// Official MES candidate policy v1 — not calibrated, not stable.
class MesOfficialPolicyV1 {
  const MesOfficialPolicyV1._();

  static const policyId = 'mes-official-v1';

  static MESPolicy create() {
    const scale = ScoreScale();
    return MESPolicy(
      metadata: const MESPolicyMetadata(
        officialName: MESPolicyMetadata.officialNameValue,
        acronym: MESPolicyMetadata.acronymValue,
        policyId: policyId,
        policyVersion: 1,
        mesSchemaVersion: MESPolicy.currentSchemaVersion,
        mesCalculationVersion: MESPolicy.currentCalculationVersion,
        mesCanonicalizationVersion: MESPolicy.currentCanonicalizationVersion,
        status: MESPolicyStatus.candidate,
        owner: 'MasterPalm Engineering Platform',
        calibrated: false,
        description:
            'Official MES candidate policy v1. Weights are provisional and not calibrated across projects.',
        tags: ['mes', 'official', 'candidate', 'not-stable'],
      ),
      scoreScale: scale,
      globalMissingDataPolicy: ScoreMissingDataPolicy.excludeAndReweight,
      globalAggregationMethod: ScoreAggregationMethod.weightedAverage,
      eligibility: const MESEligibilityPolicy(
        minimumPolicyCoverage: 50,
        minimumRequiredDimensionCoverage: 75,
        allowPartialWithOptionalMissing: true,
        requireCompatibleMetricsSchema: true,
      ),
      coveragePolicy: const MESCoveragePolicy(
        minimumRuleCoverage: 0,
        minimumDimensionCoverage: 0,
        minimumPolicyCoverage: 50,
        minimumEvidenceCoverage: 50,
      ),
      governance: const MESGovernance(
        status: MESGovernanceStatus.candidate,
        owner: 'MasterPalm Engineering Platform',
        rationale:
            'Initial official MES candidate policy for platform evaluation foundation.',
        changeLog: [
          MESPolicyChange(
            changeType: MESPolicyChangeType.created,
            description: 'Initial mes-official-v1 candidate policy',
            version: 1,
          ),
        ],
      ),
      bands: const [
        MESBand(bandId: 'mes-band-1', min: 0, max: 19.99),
        MESBand(bandId: 'mes-band-2', min: 20, max: 39.99),
        MESBand(bandId: 'mes-band-3', min: 40, max: 59.99),
        MESBand(bandId: 'mes-band-4', min: 60, max: 79.99),
        MESBand(bandId: 'mes-band-5', min: 80, max: 100),
      ],
      dimensions: [
        MESDimensionDefinition(
          dimensionId: 'mes.architecture_structure',
          name: 'Architecture Structure',
          objective: 'Evaluate structural graph properties.',
          weightPercent: 20,
          required: true,
          evidenceTier: MESEvidenceTier.authoritative,
          metricRequirements: const [
            MESMetricRequirement(
              metricId: 'graph.component.isolated_count',
              tier: MESEvidenceTier.authoritative,
              rationale:
                  'Isolated components indicate structural fragmentation.',
            ),
            MESMetricRequirement(
              metricId: 'graph.component.weak.count',
              tier: MESEvidenceTier.authoritative,
              rationale:
                  'Weak components indicate loosely connected subgraphs.',
            ),
          ],
          rules: const [
            ScoreRule(
              ruleId: 'arch-isolated-low',
              metricId: 'graph.component.isolated_count',
              condition: ScoreRuleCondition(
                operator: ScoreRuleOperator.lessThanOrEqual,
                threshold: 0,
              ),
              outcome: ScoreRuleOutcome(score: 100),
              normalization: ScoreNormalization(
                method: ScoreNormalizationMethod.direct,
              ),
              description: 'No isolated components',
            ),
            ScoreRule(
              ruleId: 'arch-isolated-present',
              metricId: 'graph.component.isolated_count',
              condition: ScoreRuleCondition(
                operator: ScoreRuleOperator.greaterThan,
                threshold: 0,
              ),
              outcome: ScoreRuleOutcome(score: 50),
              normalization: ScoreNormalization(
                method: ScoreNormalizationMethod.inverse,
                domainMax: 10,
              ),
              description: 'Isolated components present',
            ),
            ScoreRule(
              ruleId: 'arch-weak-low',
              metricId: 'graph.component.weak.count',
              condition: ScoreRuleCondition(
                operator: ScoreRuleOperator.lessThanOrEqual,
                threshold: 0,
              ),
              outcome: ScoreRuleOutcome(score: 100),
              normalization: ScoreNormalization(
                method: ScoreNormalizationMethod.direct,
              ),
              description: 'No weak components',
            ),
            ScoreRule(
              ruleId: 'arch-weak-present',
              metricId: 'graph.component.weak.count',
              condition: ScoreRuleCondition(
                operator: ScoreRuleOperator.greaterThan,
                threshold: 0,
              ),
              outcome: ScoreRuleOutcome(score: 50),
              normalization: ScoreNormalization(
                method: ScoreNormalizationMethod.inverse,
                domainMax: 5,
              ),
              description: 'Weak components present',
            ),
          ],
          aggregationMethod: ScoreAggregationMethod.weightedAverage,
        ),
        MESDimensionDefinition(
          dimensionId: 'mes.dependency_control',
          name: 'Dependency Control',
          objective: 'Evaluate dependency concentration and dispersion.',
          weightPercent: 20,
          required: true,
          evidenceTier: MESEvidenceTier.authoritative,
          metricRequirements: const [
            MESMetricRequirement(
              metricId: 'graph.degree.fan_out.max',
              tier: MESEvidenceTier.authoritative,
              rationale: 'Maximum fan-out indicates dependency concentration.',
            ),
            MESMetricRequirement(
              metricId: 'graph.degree.fan_in.max',
              tier: MESEvidenceTier.authoritative,
              rationale:
                  'Maximum fan-in indicates inbound coupling concentration.',
            ),
          ],
          rules: const [
            ScoreRule(
              ruleId: 'dep-fan-out',
              metricId: 'graph.degree.fan_out.max',
              condition: ScoreRuleCondition(
                operator: ScoreRuleOperator.exists,
              ),
              outcome: ScoreRuleOutcome(score: 75),
              normalization: ScoreNormalization(
                method: ScoreNormalizationMethod.cappedLinear,
                domainMin: 0,
                domainMax: 20,
              ),
              description: 'Fan-out max within documented domain',
            ),
            ScoreRule(
              ruleId: 'dep-fan-in',
              metricId: 'graph.degree.fan_in.max',
              condition: ScoreRuleCondition(
                operator: ScoreRuleOperator.exists,
              ),
              outcome: ScoreRuleOutcome(score: 75),
              normalization: ScoreNormalization(
                method: ScoreNormalizationMethod.cappedLinear,
                domainMin: 0,
                domainMax: 20,
              ),
              description: 'Fan-in max within documented domain',
            ),
          ],
          aggregationMethod: ScoreAggregationMethod.arithmeticMean,
        ),
        MESDimensionDefinition(
          dimensionId: 'mes.cycle_control',
          name: 'Cycle Control',
          objective: 'Evaluate exposure to structural cycles.',
          weightPercent: 20,
          required: true,
          evidenceTier: MESEvidenceTier.authoritative,
          metricRequirements: const [
            MESMetricRequirement(
              metricId: 'graph.cycle.count',
              tier: MESEvidenceTier.authoritative,
              rationale:
                  'Cycle count measures structural circular dependencies.',
            ),
          ],
          rules: const [
            ScoreRule(
              ruleId: 'cycle-none',
              metricId: 'graph.cycle.count',
              condition: ScoreRuleCondition(
                operator: ScoreRuleOperator.lessThanOrEqual,
                threshold: 0,
              ),
              outcome: ScoreRuleOutcome(score: 100),
              normalization: ScoreNormalization(
                method: ScoreNormalizationMethod.direct,
              ),
              description: 'No structural cycles',
            ),
            ScoreRule(
              ruleId: 'cycle-present',
              metricId: 'graph.cycle.count',
              condition: ScoreRuleCondition(
                operator: ScoreRuleOperator.greaterThan,
                threshold: 0,
              ),
              outcome: ScoreRuleOutcome(score: 40),
              normalization: ScoreNormalization(
                method: ScoreNormalizationMethod.inverse,
                domainMax: 5,
              ),
              description: 'Structural cycles present',
            ),
          ],
          aggregationMethod: ScoreAggregationMethod.weightedAverage,
        ),
        MESDimensionDefinition(
          dimensionId: 'mes.guardian_compliance',
          name: 'Guardian Compliance',
          objective: 'Incorporate Guardian-classified evidence.',
          weightPercent: 25,
          required: true,
          missingDataPolicy: ScoreMissingDataPolicy.markUnavailable,
          evidenceTier: MESEvidenceTier.authoritative,
          metricRequirements: const [
            MESMetricRequirement(
              metricId: 'guardian.violation.count',
              tier: MESEvidenceTier.authoritative,
              rationale: 'Guardian violation count from prior analysis.',
              required: true,
            ),
            MESMetricRequirement(
              metricId: 'guardian.decision',
              tier: MESEvidenceTier.authoritative,
              rationale: 'Guardian GO/NO-GO decision as classified evidence.',
              required: true,
            ),
          ],
          rules: const [
            ScoreRule(
              ruleId: 'guardian-violations-zero',
              metricId: 'guardian.violation.count',
              condition: ScoreRuleCondition(
                operator: ScoreRuleOperator.lessThanOrEqual,
                threshold: 0,
              ),
              outcome: ScoreRuleOutcome(score: 100),
              normalization: ScoreNormalization(
                method: ScoreNormalizationMethod.direct,
              ),
              requiresGuardian: true,
            ),
            ScoreRule(
              ruleId: 'guardian-violations-present',
              metricId: 'guardian.violation.count',
              condition: ScoreRuleCondition(
                operator: ScoreRuleOperator.greaterThan,
                threshold: 0,
              ),
              outcome: ScoreRuleOutcome(score: 30),
              normalization: ScoreNormalization(
                method: ScoreNormalizationMethod.inverse,
                domainMax: 10,
              ),
              requiresGuardian: true,
            ),
            ScoreRule(
              ruleId: 'guardian-go',
              metricId: 'guardian.decision',
              condition: ScoreRuleCondition(
                operator: ScoreRuleOperator.equals,
                expectedText: 'go',
              ),
              outcome: ScoreRuleOutcome(score: 100),
              normalization: ScoreNormalization(
                method: ScoreNormalizationMethod.direct,
              ),
              requiresGuardian: true,
            ),
          ],
          aggregationMethod: ScoreAggregationMethod.weightedAverage,
        ),
        MESDimensionDefinition(
          dimensionId: 'mes.callable_reachability',
          name: 'Callable Reachability',
          objective: 'Evaluate callables without known call edges.',
          weightPercent: 5,
          required: false,
          evidenceTier: MESEvidenceTier.experimental,
          limitations: const [
            'callable.uncalled_count does not prove runtime dead code.',
          ],
          metricRequirements: const [
            MESMetricRequirement(
              metricId: 'callable.uncalled_count',
              tier: MESEvidenceTier.experimental,
              rationale: 'Static uncalled count from graph analysis.',
              limitation:
                  'Does not prove absence of runtime calls or dynamic dispatch.',
              required: false,
            ),
          ],
          rules: const [
            ScoreRule(
              ruleId: 'callable-uncalled-low',
              metricId: 'callable.uncalled_count',
              condition: ScoreRuleCondition(
                operator: ScoreRuleOperator.lessThanOrEqual,
                threshold: 0,
              ),
              outcome: ScoreRuleOutcome(score: 100),
              normalization: ScoreNormalization(
                method: ScoreNormalizationMethod.direct,
              ),
            ),
            ScoreRule(
              ruleId: 'callable-uncalled-present',
              metricId: 'callable.uncalled_count',
              condition: ScoreRuleCondition(
                operator: ScoreRuleOperator.greaterThan,
                threshold: 0,
              ),
              outcome: ScoreRuleOutcome(score: 50),
              normalization: ScoreNormalization(
                method: ScoreNormalizationMethod.inverse,
                domainMax: 20,
              ),
            ),
          ],
          aggregationMethod: ScoreAggregationMethod.weightedAverage,
        ),
        MESDimensionDefinition(
          dimensionId: 'mes.data_access_structure',
          name: 'Data Access Structure',
          objective: 'Describe storage access concentration.',
          weightPercent: 5,
          required: false,
          evidenceTier: MESEvidenceTier.contextual,
          limitations: const [
            'Storage access counts are contextual and not universally directional.',
          ],
          metricRequirements: const [
            MESMetricRequirement(
              metricId: 'storage.firestore.read_edge_count',
              tier: MESEvidenceTier.contextual,
              rationale: 'Firestore read edge count from graph.',
              limitation:
                  'More accesses do not automatically imply worse architecture.',
              required: false,
            ),
          ],
          rules: const [
            ScoreRule(
              ruleId: 'storage-read-edges',
              metricId: 'storage.firestore.read_edge_count',
              condition: ScoreRuleCondition(
                operator: ScoreRuleOperator.exists,
              ),
              outcome: ScoreRuleOutcome(score: 70),
              normalization: ScoreNormalization(
                method: ScoreNormalizationMethod.cappedLinear,
                domainMin: 0,
                domainMax: 50,
              ),
            ),
          ],
          aggregationMethod: ScoreAggregationMethod.weightedAverage,
        ),
        MESDimensionDefinition(
          dimensionId: 'mes.change_stability',
          name: 'Change Stability',
          objective:
              'Evaluate changes between snapshots when HistoryDiff is available.',
          weightPercent: 5,
          required: false,
          missingDataPolicy: ScoreMissingDataPolicy.markUnavailable,
          evidenceTier: MESEvidenceTier.derived,
          limitations: const [
            'Change does not automatically imply regression.',
            'Requires compatible HistoryDiff between two snapshots.',
          ],
          metricRequirements: const [
            MESMetricRequirement(
              metricId: 'history.metric',
              tier: MESEvidenceTier.derived,
              rationale: 'Metric value changes from HistoryDiff.',
              required: false,
            ),
          ],
          rules: const [
            ScoreRule(
              ruleId: 'stable-no-changes',
              metricId: 'history.stability',
              condition: ScoreRuleCondition(
                operator: ScoreRuleOperator.changed,
              ),
              outcome: ScoreRuleOutcome(score: 100),
              normalization: ScoreNormalization(
                method: ScoreNormalizationMethod.direct,
              ),
              requiresHistoryDiff: true,
            ),
            ScoreRule(
              ruleId: 'changes-detected',
              metricId: 'history.metric',
              condition: ScoreRuleCondition(
                operator: ScoreRuleOperator.changed,
                historyChangeType: 'metricValueChanged',
              ),
              outcome: ScoreRuleOutcome(score: 50),
              normalization: ScoreNormalization(
                method: ScoreNormalizationMethod.direct,
              ),
              requiresHistoryDiff: true,
            ),
          ],
          aggregationMethod: ScoreAggregationMethod.minimum,
        ),
      ],
    );
  }
}
