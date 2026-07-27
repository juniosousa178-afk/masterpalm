import 'dart:convert';
import 'dart:io';

import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/metrics/metrics_definitions.dart';
import 'package:masterpalm_platform/metrics/metrics_engine.dart';

import '../metrics/metrics_fixtures.dart';

/// Deterministic fixtures for Score Engine tests (A–M).
class ScoreFixtures {
  static const projectId = 'demo-project';
  static const createdAtA = '2026-01-01T10:00:00.000Z';
  static const createdAtB = '2026-01-02T10:00:00.000Z';

  static Future<MetricsSnapshot> metricsMinimal() async {
    final result = await MetricsEngine().calculate(
      MetricsRequest(
        projectId: projectId,
        projectGraph: MetricsFixtures.empty().toJson(),
      ),
    );
    return result.snapshot;
  }

  static Future<MetricsSnapshot> metricsComplete({
    Map<String, dynamic>? guardianAnalysis,
  }) async {
    final result = await MetricsEngine().calculate(
      MetricsRequest(
        projectId: projectId,
        projectGraph: MetricsFixtures.linear().toJson(),
        guardianAnalysis: guardianAnalysis,
        metricIds: {
          ...MetricsDefinitions.defaultMetricIds,
          ...MetricsDefinitions.guardianMetricIds,
        },
      ),
    );
    return result.snapshot;
  }

  static Future<MetricsSnapshot> metricsIncompatible() async {
    final snapshot = await metricsMinimal();
    final json = snapshot.toJson();
    final metadata = Map<String, dynamic>.from(
      json['metadata'] as Map<String, dynamic>,
    );
    metadata['metricsSchemaVersion'] = 999;
    json['metadata'] = metadata;
    return MetricsSnapshot.fromJson(json);
  }

  static Map<String, dynamic> guardianGo() {
    return jsonDecode(
      File('test/fixtures/guardian_no_violations.json').readAsStringSync(),
    ) as Map<String, dynamic>;
  }

  static Map<String, dynamic> guardianNoGo() {
    return jsonDecode(
      File('test/fixtures/minimal_guardian_analysis.json').readAsStringSync(),
    ) as Map<String, dynamic>;
  }

  static ScorePolicy singleDimensionPolicy() {
    return ScorePolicy(
      policyId: 'test-single-dimension',
      name: 'Single Dimension Test',
      description: 'Test policy with one dimension',
      policySchemaVersion: 1,
      policyVersion: 1,
      canonicalizationVersion: 1,
      scoreScale: const ScoreScale(),
      aggregationMethod: ScoreAggregationMethod.weightedAverage,
      missingDataPolicy: ScoreMissingDataPolicy.excludeAndReweight,
      minimumEvidenceCoverage: 0,
      metadata: const ScorePolicyMetadata(experimental: true),
      dimensions: [
        ScoreDimensionPolicy(
          dimensionId: 'only',
          name: 'Only',
          weight: const ScoreWeight(value: 1),
          aggregationMethod: ScoreAggregationMethod.weightedAverage,
          rules: [
            ScoreRule(
              ruleId: 'exists-rule',
              metricId: 'graph.node.count',
              condition: const ScoreRuleCondition(
                operator: ScoreRuleOperator.exists,
              ),
              outcome: const ScoreRuleOutcome(score: 80),
              normalization: const ScoreNormalization(
                method: ScoreNormalizationMethod.direct,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static ScorePolicy invalidPolicy() {
    return ScorePolicy(
      policyId: '',
      name: 'Invalid',
      description: 'Invalid policy',
      policySchemaVersion: 0,
      policyVersion: 0,
      canonicalizationVersion: 0,
      scoreScale: const ScoreScale(min: 100, max: 0),
      dimensions: const [],
      aggregationMethod: ScoreAggregationMethod.weightedAverage,
      missingDataPolicy: ScoreMissingDataPolicy.fail,
      minimumEvidenceCoverage: 150,
    );
  }

  static ScorePolicy reweightPolicy() {
    return ScorePolicy(
      policyId: 'test-reweight',
      name: 'Reweight Policy',
      description: 'Policy with reweight missing data',
      policySchemaVersion: 1,
      policyVersion: 1,
      canonicalizationVersion: 1,
      scoreScale: const ScoreScale(),
      aggregationMethod: ScoreAggregationMethod.weightedAverage,
      missingDataPolicy: ScoreMissingDataPolicy.excludeAndReweight,
      minimumEvidenceCoverage: 0,
      metadata: const ScorePolicyMetadata(experimental: true),
      dimensions: [
        ScoreDimensionPolicy(
          dimensionId: 'present',
          name: 'Present',
          weight: const ScoreWeight(value: 1),
          aggregationMethod: ScoreAggregationMethod.weightedAverage,
          rules: [
            ScoreRule(
              ruleId: 'node-count',
              metricId: 'graph.node.count',
              condition: const ScoreRuleCondition(
                operator: ScoreRuleOperator.exists,
              ),
              outcome: const ScoreRuleOutcome(score: 90),
              normalization: const ScoreNormalization(
                method: ScoreNormalizationMethod.direct,
              ),
            ),
          ],
        ),
        ScoreDimensionPolicy(
          dimensionId: 'missing',
          name: 'Missing',
          weight: const ScoreWeight(value: 1),
          aggregationMethod: ScoreAggregationMethod.weightedAverage,
          missingDataPolicy: ScoreMissingDataPolicy.markUnavailable,
          rules: [
            ScoreRule(
              ruleId: 'guardian-missing',
              metricId: 'guardian.violation.count',
              condition: const ScoreRuleCondition(
                operator: ScoreRuleOperator.exists,
              ),
              outcome: const ScoreRuleOutcome(score: 50),
              normalization: const ScoreNormalization(
                method: ScoreNormalizationMethod.direct,
              ),
              requiresGuardian: true,
            ),
          ],
        ),
      ],
    );
  }
}
