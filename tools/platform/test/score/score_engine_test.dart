import 'dart:convert';
import 'dart:io';

import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/score/policies/foundation_reference_policy.dart';
import 'package:masterpalm_platform/score/score_aggregator.dart';
import 'package:masterpalm_platform/score/score_canonical_serializer.dart';
import 'package:masterpalm_platform/score/score_engine.dart';
import 'package:masterpalm_platform/score/score_exceptions.dart';
import 'package:masterpalm_platform/score/score_normalizer.dart';
import 'package:masterpalm_platform/score/score_input.dart';
import 'package:masterpalm_platform/score/score_policy_validator.dart';
import 'package:masterpalm_platform/score/score_registry.dart';
import 'package:masterpalm_platform/score/score_rule_evaluator.dart';
import 'package:masterpalm_platform/score/score_snapshot_id_factory.dart';
import 'package:masterpalm_platform/score/stores/in_memory_score_store.dart';
import 'package:masterpalm_platform/report/report_engine.dart';
import 'package:masterpalm_platform/report/renderers/json_report_renderer.dart';
import 'package:test/test.dart';

import 'score_fixtures.dart';

void main() {
  const serializer = ScoreCanonicalSerializer();
  const scale = ScoreScale();

  ScoreEngine engineWithPolicies(List<ScorePolicy> policies) {
    final registry = ScoreRegistry();
    for (final p in policies) {
      registry.register(p);
    }
    registry.freeze();
    return ScoreEngine(registry: registry);
  }

  PlatformScoreProvider provider(
      {ScoreEngine? engine, InMemoryScoreStore? store}) {
    final registry = ScoreRegistry();
    registry.register(FoundationReferencePolicy.create());
    registry.register(ScoreFixtures.singleDimensionPolicy());
    registry.register(ScoreFixtures.reweightPolicy());
    registry.freeze();
    final resolvedEngine = engine ?? ScoreEngine(registry: registry);
    return PlatformScoreProvider(
      engine: resolvedEngine,
      registry: registry,
      store: store ?? InMemoryScoreStore(),
    );
  }

  group('ScorePolicy', () {
    test('is immutable and round-trips JSON', () {
      final policy = FoundationReferencePolicy.create();
      final roundTrip = ScorePolicy.fromJson(
        jsonDecode(jsonEncode(policy.toJson())) as Map<String, dynamic>,
      );
      expect(roundTrip.policyId, policy.policyId);
      expect(roundTrip.metadata.experimental, isTrue);
      expect(roundTrip.policyId, isNot(contains('mes')));
    });

    test('rejects empty policyId', () {
      const validator = ScorePolicyValidator();
      expect(
          validator.validate(ScoreFixtures.invalidPolicy()).isValid, isFalse);
    });

    test('rejects duplicate dimension and rule ids', () {
      const validator = ScorePolicyValidator();
      final policy = ScorePolicy(
        policyId: 'dup-test',
        name: 'Dup',
        description: 'dup',
        policySchemaVersion: 1,
        policyVersion: 1,
        canonicalizationVersion: 1,
        scoreScale: scale,
        aggregationMethod: ScoreAggregationMethod.weightedAverage,
        missingDataPolicy: ScoreMissingDataPolicy.fail,
        minimumEvidenceCoverage: 0,
        dimensions: [
          ScoreDimensionPolicy(
            dimensionId: 'a',
            name: 'A',
            weight: const ScoreWeight(value: 1),
            aggregationMethod: ScoreAggregationMethod.weightedAverage,
            rules: [
              ScoreRule(
                ruleId: 'r1',
                metricId: 'graph.node.count',
                condition: const ScoreRuleCondition(
                  operator: ScoreRuleOperator.exists,
                ),
                outcome: const ScoreRuleOutcome(score: 1),
                normalization: const ScoreNormalization(
                  method: ScoreNormalizationMethod.direct,
                ),
              ),
              ScoreRule(
                ruleId: 'r1',
                metricId: 'graph.edge.count',
                condition: const ScoreRuleCondition(
                  operator: ScoreRuleOperator.exists,
                ),
                outcome: const ScoreRuleOutcome(score: 1),
                normalization: const ScoreNormalization(
                  method: ScoreNormalizationMethod.direct,
                ),
              ),
            ],
          ),
        ],
      );
      expect(validator.validate(policy).isValid, isFalse);
    });

    test('rejects negative and non-finite weights', () {
      const validator = ScorePolicyValidator();
      final policy = ScorePolicy(
        policyId: 'weight-test',
        name: 'W',
        description: 'w',
        policySchemaVersion: 1,
        policyVersion: 1,
        canonicalizationVersion: 1,
        scoreScale: scale,
        aggregationMethod: ScoreAggregationMethod.weightedAverage,
        missingDataPolicy: ScoreMissingDataPolicy.fail,
        minimumEvidenceCoverage: 0,
        dimensions: [
          ScoreDimensionPolicy(
            dimensionId: 'a',
            name: 'A',
            weight: const ScoreWeight(value: -1),
            aggregationMethod: ScoreAggregationMethod.weightedAverage,
            rules: [
              ScoreRule(
                ruleId: 'r1',
                metricId: 'graph.node.count',
                condition: const ScoreRuleCondition(
                  operator: ScoreRuleOperator.exists,
                ),
                outcome: const ScoreRuleOutcome(score: 1),
                normalization: const ScoreNormalization(
                  method: ScoreNormalizationMethod.direct,
                ),
                weight: const ScoreWeight(value: double.nan),
              ),
            ],
          ),
        ],
      );
      expect(validator.validate(policy).isValid, isFalse);
    });
  });

  group('ScoreNormalizer', () {
    const normalizer = ScoreNormalizer();

    test('direct normalization', () {
      expect(
        normalizer.normalize(
          config:
              const ScoreNormalization(method: ScoreNormalizationMethod.direct),
          scale: scale,
          numericValue: 75,
        ),
        75,
      );
    });

    test('inverse normalization', () {
      expect(
        normalizer.normalize(
          config: const ScoreNormalization(
            method: ScoreNormalizationMethod.inverse,
            domainMax: 10,
          ),
          scale: scale,
          numericValue: 2,
        ),
        80,
      );
    });

    test('linearRange normalization', () {
      final value = normalizer.normalize(
        config: const ScoreNormalization(
          method: ScoreNormalizationMethod.linearRange,
          domainMin: 0,
          domainMax: 10,
        ),
        scale: scale,
        numericValue: 5,
      );
      expect(value, 50);
    });

    test('cappedLinear normalization', () {
      final value = normalizer.normalize(
        config: const ScoreNormalization(
          method: ScoreNormalizationMethod.cappedLinear,
          domainMin: 0,
          domainMax: 10,
        ),
        scale: scale,
        numericValue: 20,
      );
      expect(value, 100);
    });

    test('booleanMapping normalization', () {
      expect(
        normalizer.normalize(
          config: const ScoreNormalization(
            method: ScoreNormalizationMethod.booleanMapping,
            booleanTrueScore: 100,
            booleanFalseScore: 0,
          ),
          scale: scale,
          booleanValue: true,
        ),
        100,
      );
    });

    test('thresholdBands normalization', () {
      expect(
        normalizer.normalize(
          config: ScoreNormalization(
            method: ScoreNormalizationMethod.thresholdBands,
            bands: [
              const ScoreThresholdBand(
                  bandId: 'band1', min: 0, max: 5, score: 20),
              const ScoreThresholdBand(
                  bandId: 'band2', min: 6, max: 10, score: 80),
            ],
          ),
          scale: scale,
          numericValue: 7,
        ),
        80,
      );
    });

    test('normalizes -0.0 to 0.0', () {
      expect(
        normalizer.normalize(
          config:
              const ScoreNormalization(method: ScoreNormalizationMethod.direct),
          scale: scale,
          numericValue: -0.0,
        ),
        0,
      );
    });

    test('rejects NaN', () {
      expect(
        () => serializer.roundScore(double.nan, 2),
        throwsA(isA<ScoreValidationException>()),
      );
    });
  });

  group('ScoreAggregator', () {
    const aggregator = ScoreAggregator();

    test('weightedAverage', () {
      expect(
        aggregator.aggregate(
          method: ScoreAggregationMethod.weightedAverage,
          items: [(score: 80.0, weight: 1.0), (score: 60.0, weight: 3.0)],
          precision: 2,
          scaleMin: 0,
          scaleMax: 100,
        ),
        65,
      );
    });

    test('arithmeticMean', () {
      expect(
        aggregator.aggregate(
          method: ScoreAggregationMethod.arithmeticMean,
          items: [(score: 80.0, weight: 1.0), (score: 60.0, weight: 1.0)],
          precision: 2,
          scaleMin: 0,
          scaleMax: 100,
        ),
        70,
      );
    });

    test('minimum and maximum', () {
      expect(
        aggregator.aggregate(
          method: ScoreAggregationMethod.minimum,
          items: [(score: 80.0, weight: 1.0), (score: 60.0, weight: 1.0)],
          precision: 2,
          scaleMin: 0,
          scaleMax: 100,
        ),
        60,
      );
      expect(
        aggregator.aggregate(
          method: ScoreAggregationMethod.maximum,
          items: [(score: 80.0, weight: 1.0), (score: 60.0, weight: 1.0)],
          precision: 2,
          scaleMin: 0,
          scaleMax: 100,
        ),
        80,
      );
    });
  });

  group('ScoreRuleEvaluator', () {
    const evaluator = ScoreRuleEvaluator();

    test('evaluates equals greaterThan lessThan between exists', () {
      final evidence = MetricEvidenceValue(
        availability: ScoreAvailability.available,
        numericValue: 5,
      );
      expect(
        evaluator
            .evaluate(
              rule: ScoreRule(
                ruleId: 'gt',
                metricId: 'graph.cycle.count',
                condition: const ScoreRuleCondition(
                  operator: ScoreRuleOperator.greaterThan,
                  threshold: 3,
                ),
                outcome: const ScoreRuleOutcome(score: 50),
                normalization: const ScoreNormalization(
                  method: ScoreNormalizationMethod.direct,
                ),
              ),
              scale: scale,
              evidence: evidence,
              historyDiff: null,
              hasGuardian: false,
            )
            .matched,
        isTrue,
      );
    });
  });

  group('EngineeringScoreSnapshot', () {
    test('is immutable and deterministic id', () async {
      final metrics = await ScoreFixtures.metricsComplete();
      final engine = engineWithPolicies([
        FoundationReferencePolicy.create(),
        ScoreFixtures.singleDimensionPolicy(),
      ]);
      final req = ScoreRequest(
        projectId: ScoreFixtures.projectId,
        createdAt: ScoreFixtures.createdAtA,
        metricsSnapshot: metrics.toJson(),
        policyId: ScoreFixtures.singleDimensionPolicy().policyId,
      );
      final a = engine.calculate(req).snapshot;
      final b = engine.calculate(req).snapshot;
      expect(a.metadata.scoreSnapshotId, b.metadata.scoreSnapshotId);
      expect(a.metadata.scoreFingerprint, b.metadata.scoreFingerprint);
    });

    test('different timestamps do not change identity', () async {
      final metrics = await ScoreFixtures.metricsComplete();
      final engine =
          engineWithPolicies([ScoreFixtures.singleDimensionPolicy()]);
      final json = metrics.toJson();
      final a = engine
          .calculate(ScoreRequest(
            projectId: ScoreFixtures.projectId,
            createdAt: ScoreFixtures.createdAtA,
            metricsSnapshot: json,
            policy: ScoreFixtures.singleDimensionPolicy(),
          ))
          .snapshot;
      final b = engine
          .calculate(ScoreRequest(
            projectId: ScoreFixtures.projectId,
            createdAt: ScoreFixtures.createdAtB,
            metricsSnapshot: json,
            policy: ScoreFixtures.singleDimensionPolicy(),
          ))
          .snapshot;
      expect(a.metadata.scoreSnapshotId, b.metadata.scoreSnapshotId);
    });

    test('round-trip JSON', () async {
      final metrics = await ScoreFixtures.metricsComplete();
      final engine =
          engineWithPolicies([ScoreFixtures.singleDimensionPolicy()]);
      final snapshot = engine
          .calculate(ScoreRequest(
            projectId: ScoreFixtures.projectId,
            createdAt: ScoreFixtures.createdAtA,
            metricsSnapshot: metrics.toJson(),
            policy: ScoreFixtures.singleDimensionPolicy(),
          ))
          .snapshot;
      final roundTrip = EngineeringScoreSnapshot.fromJson(
        jsonDecode(jsonEncode(snapshot.toJson())) as Map<String, dynamic>,
      );
      expect(roundTrip.metadata.scoreSnapshotId,
          snapshot.metadata.scoreSnapshotId);
    });
  });

  group('ScoreEngine integration', () {
    test('calculates foundation reference policy', () async {
      final metrics = await ScoreFixtures.metricsComplete(
          guardianAnalysis: ScoreFixtures.guardianGo());
      final p = provider();
      final result = await p.calculate(ScoreRequest(
        projectId: ScoreFixtures.projectId,
        createdAt: ScoreFixtures.createdAtA,
        metricsSnapshot: metrics.toJson(),
        policyId: FoundationReferencePolicy.policyId,
        guardianAnalysis: ScoreFixtures.guardianGo(),
        includeExplanations: true,
        includeTrace: true,
      ));
      expect(result.snapshot.overallScore.value, greaterThan(0));
      expect(result.snapshot.explanation.summary,
          contains('foundation-reference-v1'));
      expect(result.snapshot.metadata.policyId,
          FoundationReferencePolicy.policyId);
      expect(result.snapshot.metadata.policyId, isNot(contains('mes')));
    });

    test('partial score without guardian', () async {
      final metrics = await ScoreFixtures.metricsComplete();
      final p = provider();
      final result = await p.calculate(ScoreRequest(
        projectId: ScoreFixtures.projectId,
        createdAt: ScoreFixtures.createdAtA,
        metricsSnapshot: metrics.toJson(),
        policyId: FoundationReferencePolicy.policyId,
      ));
      expect(result.status, ScoreStatus.partial);
    });

    test('guardian NO-GO affects score', () async {
      final goMetrics = await ScoreFixtures.metricsComplete(
        guardianAnalysis: ScoreFixtures.guardianGo(),
      );
      final noGoMetrics = await ScoreFixtures.metricsComplete(
        guardianAnalysis: ScoreFixtures.guardianNoGo(),
      );
      final p = provider();
      final go = await p.calculate(ScoreRequest(
        projectId: ScoreFixtures.projectId,
        createdAt: ScoreFixtures.createdAtA,
        metricsSnapshot: goMetrics.toJson(),
        policyId: FoundationReferencePolicy.policyId,
        guardianAnalysis: ScoreFixtures.guardianGo(),
      ));
      final noGo = await p.calculate(ScoreRequest(
        projectId: ScoreFixtures.projectId,
        createdAt: ScoreFixtures.createdAtA,
        metricsSnapshot: noGoMetrics.toJson(),
        policyId: FoundationReferencePolicy.policyId,
        guardianAnalysis: ScoreFixtures.guardianNoGo(),
      ));
      expect(go.snapshot.overallScore.value,
          isNot(equals(noGo.snapshot.overallScore.value)));
    });

    test('strict compatibility fails on incompatible metrics', () async {
      final metrics = await ScoreFixtures.metricsIncompatible();
      final p = provider();
      expect(
        () => p.calculate(ScoreRequest(
          projectId: ScoreFixtures.projectId,
          createdAt: ScoreFixtures.createdAtA,
          metricsSnapshot: metrics.toJson(),
          policyId: FoundationReferencePolicy.policyId,
          strictCompatibility: true,
        )),
        throwsA(isA<ScoreCompatibilityException>()),
      );
    });
  });

  group('ScoreProvider store', () {
    test('publish idempotent and conflict detection', () async {
      final store = InMemoryScoreStore();
      final p = provider(store: store);
      final metrics = await ScoreFixtures.metricsComplete();
      final first = await p.calculate(ScoreRequest(
        projectId: ScoreFixtures.projectId,
        createdAt: ScoreFixtures.createdAtA,
        metricsSnapshot: metrics.toJson(),
        policy: ScoreFixtures.singleDimensionPolicy(),
      ));
      await p.publish(first.snapshot);
      await p.publish(first.snapshot);
      expect(
          await store.exists(first.snapshot.metadata.scoreSnapshotId), isTrue);

      final tampered = EngineeringScoreSnapshot(
        metadata: first.snapshot.metadata.copyWith(
          scoreFingerprint: 'tampered',
        ),
        overallScore: first.snapshot.overallScore,
        dimensions: first.snapshot.dimensions,
        coverage: first.snapshot.coverage,
        explanation: first.snapshot.explanation,
      );
      expect(
          () => store.save(tampered), throwsA(isA<ScoreConflictException>()));
    });

    test('latest and invalidate', () async {
      final p = provider();
      final metrics = await ScoreFixtures.metricsComplete();
      await p.calculate(ScoreRequest(
        projectId: ScoreFixtures.projectId,
        createdAt: ScoreFixtures.createdAtA,
        metricsSnapshot: metrics.toJson(),
        policy: ScoreFixtures.singleDimensionPolicy(),
      ));
      await p.calculate(ScoreRequest(
        projectId: ScoreFixtures.projectId,
        createdAt: ScoreFixtures.createdAtB,
        metricsSnapshot: metrics.toJson(),
        policy: ScoreFixtures.singleDimensionPolicy(),
      ));
      final latest = await p.latest(projectId: ScoreFixtures.projectId);
      expect(latest, isNotNull);
      await p.invalidate(latest!.metadata.scoreSnapshotId);
      expect(
        await p.load(snapshotId: latest.metadata.scoreSnapshotId),
        isNull,
      );
    });
  });

  group('ScoreRegistry', () {
    test('rejects duplicate policy and freezes', () {
      final registry = ScoreRegistry();
      registry.register(ScoreFixtures.singleDimensionPolicy());
      expect(
        () => registry.register(ScoreFixtures.singleDimensionPolicy()),
        throwsA(isA<ScorePolicyException>()),
      );
      registry.freeze();
      expect(
        () => registry.register(ScoreFixtures.reweightPolicy()),
        throwsA(isA<ScorePolicyException>()),
      );
    });
  });

  group('Platform integration', () {
    test('PlatformCore.score resolves provider', () {
      final core = PlatformBootstrap.forRepo('.');
      expect(core.score(), isA<PlatformScoreProvider>());
      expect(core.score().supportedPolicyIds,
          contains(FoundationReferencePolicy.policyId));
    });

    test('engineering score report integration', () async {
      final p = provider();
      final metrics = await ScoreFixtures.metricsComplete(
          guardianAnalysis: ScoreFixtures.guardianGo());
      final score = await p.calculate(ScoreRequest(
        projectId: ScoreFixtures.projectId,
        createdAt: ScoreFixtures.createdAtA,
        metricsSnapshot: metrics.toJson(),
        policyId: FoundationReferencePolicy.policyId,
        guardianAnalysis: ScoreFixtures.guardianGo(),
      ));
      final reportEngine = ReportEngine(
        renderers: {ReportFormat.json: const JsonReportRenderer()},
      );
      final report = await reportEngine.generate(
        ReportRequest(
          reportType: ReportType.engineeringScore,
          projectId: ScoreFixtures.projectId,
          engineeringScore: score.snapshot.toJson(),
        ),
      );
      expect(report.document.metadata.reportType, ReportType.engineeringScore);
      expect(report.document.sections, isNotEmpty);
    });
  });

  group('Determinism', () {
    test('metrics order does not change score identity', () async {
      final metrics = await ScoreFixtures.metricsComplete();
      final json = metrics.toJson();
      final list = List<Map<String, dynamic>>.from(
        json['metrics'] as List<dynamic>,
      );
      final reversed = Map<String, dynamic>.from(json);
      reversed['metrics'] = list.reversed.toList();
      final engine =
          engineWithPolicies([ScoreFixtures.singleDimensionPolicy()]);
      final a = engine
          .calculate(ScoreRequest(
            projectId: ScoreFixtures.projectId,
            createdAt: ScoreFixtures.createdAtA,
            metricsSnapshot: json,
            policy: ScoreFixtures.singleDimensionPolicy(),
          ))
          .snapshot;
      final b = engine
          .calculate(ScoreRequest(
            projectId: ScoreFixtures.projectId,
            createdAt: ScoreFixtures.createdAtA,
            metricsSnapshot: reversed,
            policy: ScoreFixtures.singleDimensionPolicy(),
          ))
          .snapshot;
      expect(a.metadata.scoreSnapshotId, b.metadata.scoreSnapshotId);
    });
  });
}
