import 'package:masterpalm_platform/models/analysis_result.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_request.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_snapshot.dart';
import 'package:masterpalm_platform/quality_gate/policies/quality_gate_release_policy_v1.dart';
import 'package:masterpalm_platform/quality_gate/quality_gate_engine.dart';
import 'package:masterpalm_platform/quality_gate/quality_gate_rule_evaluator.dart';
import 'package:masterpalm_platform/quality_gate/quality_gate_source_resolver.dart';
import 'package:test/test.dart';

import '../score/score_fixtures.dart';
import 'support/quality_gate_test_fakes.dart';
import 'support/quality_gate_test_helpers.dart';

void main() {
  group('QualityGate replay', () {
    late QualityGateEngine engine;
    late QualityGateSourceResolver resolver;

    setUp(() {
      engine = QualityGateEngine(
        ruleEvaluator: QualityGateRuleEvaluator(),
      );
      resolver = QualityGateSourceResolver(
        metricsProvider: FakeMetricsProvider(),
        scoreProvider: FakeScoreProvider(),
        mesProvider: FakeMESProvider(),
        observabilityProvider: FakeObservabilityProvider(),
        dashboardProvider: FakeDashboardProvider(),
      );
    });

    Future<QualityGateSnapshot> evaluateOnce({
      bool guardianGo = true,
    }) async {
      final metrics =
          await QualityGateTestHelpers.minimalMetrics(gitRef: 'abc123');
      final score = await QualityGateTestHelpers.minimalScore(gitRef: 'abc123');
      final mes = await QualityGateTestHelpers.minimalMes(gitRef: 'abc123');
      final request = QualityGateRequest(
        projectId: metrics.metadata.projectId,
        policyId: QualityGateReleasePolicyV1.policyId,
        commitId: 'abc123',
        createdAt: '2026-01-01T10:00:00.000Z',
        referenceTime: '2026-01-01T10:00:01.000Z',
        metricsSnapshot: metrics,
        guardianAnalysis: guardianGo
            ? QualityGateTestHelpers.guardianGo()
            : AnalysisResult(
                success: false,
                summary: 'NO-GO',
                details: ScoreFixtures.guardianNoGo(),
              ),
        engineeringScoreSnapshot: score,
        mesSnapshot: mes,
      );
      final policy = QualityGateReleasePolicyV1.create();
      final sources = await resolver.resolveAll(request);
      final result = engine.evaluate(
        request: request,
        policy: policy,
        sources: sources,
      );
      return result.snapshot!;
    }

    test('toJson/fromJson preserves normative identity', () async {
      final a = await evaluateOnce();
      final b = QualityGateSnapshot.fromJson(a.toJson());
      expect(
        b.metadata.qualityGateSnapshotId,
        a.metadata.qualityGateSnapshotId,
      );
      expect(
        b.metadata.qualityGateFingerprint,
        a.metadata.qualityGateFingerprint,
      );
      expect(b.decision, a.decision);
      expect(b.evaluations.length, a.evaluations.length);
    });

    test('re-evaluate with same inputs yields same fingerprint', () async {
      final a = await evaluateOnce();
      final c = await evaluateOnce();
      expect(
        c.metadata.qualityGateFingerprint,
        a.metadata.qualityGateFingerprint,
      );
      expect(
        c.metadata.qualityGateSnapshotId,
        a.metadata.qualityGateSnapshotId,
      );
    });

    test('toComparableJson excludes temporal metadata', () async {
      final snapshot = await evaluateOnce();
      final comparable = snapshot.toComparableJson();
      final meta = comparable['metadata'] as Map<String, dynamic>;
      expect(meta.containsKey('createdAt'), isFalse);
      expect(meta.containsKey('evaluatedAt'), isFalse);
    });
  });
}
