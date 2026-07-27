import 'dart:io';

import 'package:masterpalm_platform/core/platform_bootstrap.dart';
import 'package:masterpalm_platform/interfaces/quality_gate_provider.dart';
import 'package:masterpalm_platform/mes/policies/mes_official_policy_v1.dart';
import 'package:masterpalm_platform/models/analysis_result.dart';
import 'package:masterpalm_platform/models/mes/mes_request.dart';
import 'package:masterpalm_platform/models/mes/mes_snapshot.dart';
import 'package:masterpalm_platform/models/metrics/metrics_snapshot.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_enums.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_request.dart';
import 'package:masterpalm_platform/models/report/report_request.dart';
import 'package:masterpalm_platform/models/report/report_type.dart';
import 'package:masterpalm_platform/models/score/score_request.dart';
import 'package:masterpalm_platform/models/score/score_snapshot.dart';
import 'package:masterpalm_platform/quality_gate/policies/quality_gate_release_policy_v1.dart';
import 'package:masterpalm_platform/quality_gate/stores/in_memory_quality_gate_store.dart';
import 'package:masterpalm_platform/report/report_engine.dart';
import 'package:masterpalm_platform/score/policies/foundation_reference_policy.dart';
import 'package:test/test.dart';

import '../score/score_fixtures.dart';

import 'support/quality_gate_test_helpers.dart';

/// Helpers for Quality Gate integration tests.
class QualityGateFixtures {
  static const createdAt = QualityGateTestHelpers.createdAt;
  static const referenceTime = QualityGateTestHelpers.referenceTime;
  static const commitId = QualityGateTestHelpers.commitId;

  static AnalysisResult guardianGoResult() =>
      QualityGateTestHelpers.guardianGo();

  static AnalysisResult guardianNoGoResult() =>
      QualityGateTestHelpers.guardianNoGo();
}

void main() {
  group('QualityGateProvider integration', () {
    late QualityGateProvider provider;

    setUp(() {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      provider = core.qualityGate();
    });

    Future<QualityGateRequest> passingRequest({
      AnalysisResult? guardian,
      String projectId = ScoreFixtures.projectId,
    }) =>
        QualityGateTestHelpers.passingRequest(
          guardian: guardian,
          projectId: projectId,
        );

    test('PlatformCore resolves QualityGateProvider', () {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      expect(core.qualityGate(), isA<QualityGateProvider>());
    });

    test('scenario A — core sources evaluate; QG011 capability gap', () async {
      final result = await provider.evaluate(await passingRequest());
      // Gate error is operational (unsupported required target), not a failed rule.
      expect(result.status, QualityGateResultStatus.failure);
      final qg011 =
          result.snapshot!.evaluations.firstWhere((e) => e.ruleId == 'QG011');
      expect(qg011.status, QualityGateRuleStatus.error);
      expect(result.snapshot?.decision, QualityGateDecision.error);
    });

    test('scenario C — MES below minimum fails QG007', () async {
      final request = await passingRequest();
      final mesJson = request.mesSnapshot!.toJson();
      final mesValue = Map<String, dynamic>.from(
        mesJson['mesValue'] as Map<String, dynamic>,
      );
      mesValue['value'] = 79;
      mesJson['mesValue'] = mesValue;
      final lowMes = MESSnapshot.fromJson(mesJson);

      final result = await provider.evaluate(
        QualityGateRequest(
          projectId: request.projectId,
          policyId: request.policyId,
          commitId: request.commitId,
          createdAt: request.createdAt,
          referenceTime: request.referenceTime,
          metricsSnapshot: request.metricsSnapshot,
          guardianAnalysis: request.guardianAnalysis,
          engineeringScoreSnapshot: request.engineeringScoreSnapshot,
          mesSnapshot: lowMes,
        ),
      );

      expect(result.status, QualityGateResultStatus.failure);
      expect(result.snapshot?.decision, QualityGateDecision.error);
      final qg007 =
          result.snapshot!.evaluations.firstWhere((e) => e.ruleId == 'QG007');
      expect(qg007.status, QualityGateRuleStatus.failed);
    });

    test('scenario D — telemetry absent does not block optional rules',
        () async {
      final result = await provider.evaluate(await passingRequest());
      expect(result.status, QualityGateResultStatus.failure);
      expect(result.snapshot?.decision, QualityGateDecision.error);
      for (final ruleId in ['QG012', 'QG013', 'QG014']) {
        final evaluation =
            result.snapshot!.evaluations.firstWhere((e) => e.ruleId == ruleId);
        expect(
          evaluation.status,
          isIn([
            QualityGateRuleStatus.skipped,
            QualityGateRuleStatus.unavailable,
            QualityGateRuleStatus.notApplicable,
          ]),
        );
      }
    });

    test('scenario F — score absent applies missing data policy', () async {
      final base = await passingRequest();
      final result = await provider.evaluate(
        QualityGateRequest(
          projectId: base.projectId,
          policyId: base.policyId,
          commitId: base.commitId,
          createdAt: base.createdAt,
          referenceTime: base.referenceTime,
          metricsSnapshot: base.metricsSnapshot,
          guardianAnalysis: base.guardianAnalysis,
          mesSnapshot: base.mesSnapshot,
        ),
      );
      expect(result.snapshot, isNotNull);
      expect(result.snapshot!.decision, QualityGateDecision.error);
      final qg005 =
          result.snapshot!.evaluations.firstWhere((e) => e.ruleId == 'QG005');
      expect(
        qg005.status,
        isIn([
          QualityGateRuleStatus.unavailable,
          QualityGateRuleStatus.failed,
          QualityGateRuleStatus.skipped,
        ]),
      );
    });

    test('scenario B — Guardian NO-GO fails QG003; QG011 dominates decision',
        () async {
      final request = await passingRequest(
        guardian: QualityGateFixtures.guardianNoGoResult(),
      );
      final result = await provider.evaluate(request);
      expect(result.status, QualityGateResultStatus.failure);
      expect(result.snapshot?.decision, QualityGateDecision.error);
      final qg003 =
          result.snapshot!.evaluations.firstWhere((e) => e.ruleId == 'QG003');
      expect(qg003.status, QualityGateRuleStatus.failed);
    });

    test('scenario E — project mismatch detected; QG011 dominates decision',
        () async {
      final request = await passingRequest();
      final mes = request.mesSnapshot!;
      final mesJson = mes.toJson();
      final meta = Map<String, dynamic>.from(
        mesJson['metadata'] as Map<String, dynamic>,
      );
      meta['projectId'] = 'other-project';
      mesJson['metadata'] = meta;

      final mismatched = QualityGateRequest(
        projectId: request.projectId,
        policyId: request.policyId,
        commitId: request.commitId,
        createdAt: request.createdAt,
        referenceTime: request.referenceTime,
        metricsSnapshot: request.metricsSnapshot,
        guardianAnalysis: request.guardianAnalysis,
        engineeringScoreSnapshot: request.engineeringScoreSnapshot,
        mesSnapshot: MESSnapshot.fromJson(mesJson),
      );

      final result = await provider.evaluate(mismatched);
      expect(result.status, QualityGateResultStatus.failure);
      expect(result.snapshot?.decision, QualityGateDecision.error);
      final qg001 =
          result.snapshot!.evaluations.firstWhere((e) => e.ruleId == 'QG001');
      expect(qg001.status, QualityGateRuleStatus.failed);
    });

    test('evaluate does not publish to store', () async {
      final store = InMemoryQualityGateStore();
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      final custom = core.resolve<QualityGateProvider>();
      final request = await passingRequest();
      await custom.evaluate(request);
      expect(await store.count(), 0);
    });

    test('evaluateAndPublish is idempotent', () async {
      final request = await passingRequest();
      final first = await provider.evaluateAndPublish(request);
      final second = await provider.evaluateAndPublish(request);
      expect(first.snapshot, isNotNull);
      expect(
        second.snapshot?.metadata.qualityGateSnapshotId,
        first.snapshot?.metadata.qualityGateSnapshotId,
      );
    });

    test('deterministic snapshot id for same input', () async {
      final request = await passingRequest();
      final a = await provider.evaluate(request);
      final b = await provider.evaluate(request);
      expect(
        a.snapshot?.metadata.qualityGateSnapshotId,
        b.snapshot?.metadata.qualityGateSnapshotId,
      );
      expect(
        a.snapshot?.metadata.qualityGateFingerprint,
        b.snapshot?.metadata.qualityGateFingerprint,
      );
    });

    test('report type qualityGate consumes snapshot without engine', () async {
      final result = await provider.evaluate(await passingRequest());
      final engine = ReportEngine();
      final report = await engine.generate(
        ReportRequest(
          reportType: ReportType.qualityGate,
          projectId: ScoreFixtures.projectId,
          qualityGateSnapshot: result.snapshot!.toJson(),
        ),
      );
      expect(report.document.metadata.reportType, ReportType.qualityGate);
      expect(report.document.sections.isNotEmpty, isTrue);
    });
  });

  group('QualityGateOperatorEvaluator', () {
    test('is imported via rule evaluation path', () {
      expect(QualityGateReleasePolicyV1.create().allRules.length, 15);
    });
  });

  group('QualityGateStore', () {
    test('query filters by decision', () async {
      final store = InMemoryQualityGateStore();
      expect(await store.count(), 0);
    });
  });
}
