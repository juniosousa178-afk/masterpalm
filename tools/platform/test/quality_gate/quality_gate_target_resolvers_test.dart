import 'package:masterpalm_platform/models/quality_gate/quality_gate_enums.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_policy.dart';
import 'package:masterpalm_platform/quality_gate/policies/quality_gate_release_policy_v1.dart';
import 'package:masterpalm_platform/quality_gate/quality_gate_target_registry.dart';
import 'package:masterpalm_platform/quality_gate/resolved_quality_gate_sources.dart';
import 'package:test/test.dart';

import 'support/quality_gate_test_helpers.dart';

void main() {
  group('QualityGateTargetResolvers', () {
    final registry = QualityGateTargetRegistry();
    const context = QualityGateEvaluationContext(
      projectId: 'proj-a',
      referenceTime: '2026-01-01T10:00:01.000Z',
      commitId: 'abc123',
    );

    late ResolvedQualityGateSources sources;

    setUpAll(() async {
      final metrics =
          await QualityGateTestHelpers.minimalMetrics(gitRef: 'abc123');
      final score = await QualityGateTestHelpers.minimalScore(gitRef: 'abc123');
      final mes = await QualityGateTestHelpers.minimalMes(gitRef: 'abc123');
      sources = QualityGateTestHelpers.minimalSources(
        metrics: metrics,
        score: score,
        mes: mes,
      );
    });

    QualityGateRule ruleFor(QualityGateRuleTarget target) {
      return QualityGateReleasePolicyV1.create().allRules.firstWhere(
            (r) => r.target == target,
          );
    }

    test('guardianDecision resolves GO', () {
      final resolution = registry.resolve(
        ruleFor(QualityGateRuleTarget.guardianDecision),
        sources,
        context,
      );
      expect(resolution.status, QualityGateTargetResolutionStatus.resolved);
      expect(resolution.actualValue?.rawValue, 'GO');
    });

    test('engineeringScoreGlobal resolves decimal', () {
      final resolution = registry.resolve(
        ruleFor(QualityGateRuleTarget.engineeringScoreGlobal),
        sources,
        context,
      );
      expect(resolution.status, QualityGateTargetResolutionStatus.resolved);
      expect(resolution.actualValue?.valueKind, 'decimal');
    });

    test('mesGlobalScore resolves decimal', () {
      final resolution = registry.resolve(
        ruleFor(QualityGateRuleTarget.mesGlobalScore),
        sources,
        context,
      );
      expect(resolution.status, QualityGateTargetResolutionStatus.resolved);
    });

    test('criticalCycleCount is unsupported', () {
      final resolution = registry.resolve(
        ruleFor(QualityGateRuleTarget.criticalCycleCount),
        sources,
        context,
      );
      expect(resolution.status, QualityGateTargetResolutionStatus.unsupported);
      expect(resolution.limitations, isNotEmpty);
    });

    test('historyRegressionCount derived with limitation', () {
      final historySources = QualityGateTestHelpers.minimalSources(
        metrics: sources.metrics.resolvedArtifact!,
        score: sources.score.resolvedArtifact!,
        mes: sources.mes.resolvedArtifact!,
        history: QualityGateTestHelpers.minimalHistoryDiff(regressionCount: 1),
      );
      final resolution = registry.resolve(
        ruleFor(QualityGateRuleTarget.historyRegressionCount),
        historySources,
        context,
      );
      expect(resolution.status, QualityGateTargetResolutionStatus.resolved);
      expect(resolution.limitations, isNotEmpty);
      expect(resolution.actualValue?.rawValue, 1);
    });

    test('sourceProjectConsistency true for aligned project', () {
      final resolution = registry.resolve(
        ruleFor(QualityGateRuleTarget.sourceProjectConsistency),
        sources,
        context,
      );
      expect(resolution.status, QualityGateTargetResolutionStatus.resolved);
      expect(resolution.actualValue?.rawValue, isTrue);
    });

    test('telemetry unavailable when not injected', () {
      final resolution = registry.resolve(
        ruleFor(QualityGateRuleTarget.telemetryFailureCount),
        sources,
        context,
      );
      expect(resolution.status, QualityGateTargetResolutionStatus.unavailable);
    });
  });
}
