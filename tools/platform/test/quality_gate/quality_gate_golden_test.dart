import 'dart:convert';
import 'dart:io';

import 'package:masterpalm_platform/models/quality_gate/quality_gate_enums.dart';
import 'package:masterpalm_platform/quality_gate/policies/quality_gate_release_policy_v1.dart';
import 'package:masterpalm_platform/quality_gate/quality_gate_engine.dart';
import 'package:masterpalm_platform/quality_gate/quality_gate_rule_evaluator.dart';
import 'package:masterpalm_platform/quality_gate/quality_gate_source_resolver.dart';
import 'package:test/test.dart';

import 'support/quality_gate_test_fakes.dart';
import 'support/quality_gate_test_helpers.dart';

void main() {
  group('Quality Gate golden snapshots', () {
    late Map<String, dynamic> normative;

    setUpAll(() async {
      final engine =
          QualityGateEngine(ruleEvaluator: QualityGateRuleEvaluator());
      final resolver = QualityGateSourceResolver(
        metricsProvider: FakeMetricsProvider(),
        scoreProvider: FakeScoreProvider(),
        mesProvider: FakeMESProvider(),
        observabilityProvider: FakeObservabilityProvider(),
        dashboardProvider: FakeDashboardProvider(),
      );
      final request = await QualityGateTestHelpers.passingRequest();
      final policy = QualityGateReleasePolicyV1.create();
      final sources = await resolver.resolveAll(request);
      final result = engine.evaluate(
        request: request,
        policy: policy,
        sources: sources,
      );
      final snapshot = result.snapshot!;
      normative = {
        'snapshotId': snapshot.metadata.qualityGateSnapshotId,
        'fingerprint': snapshot.metadata.qualityGateFingerprint,
        'decision': snapshot.decision.wireName,
        'resultStatus': result.status.wireName,
        'qg011Status': snapshot.evaluations
            .firstWhere((e) => e.ruleId == 'QG011')
            .status
            .wireName,
      };
    });

    test('error_qg011 golden metadata is stable', () {
      final goldenPath =
          'test/golden/quality_gate/error_qg011_capability_gap.json';
      final file = File(goldenPath);
      if (!file.existsSync()) {
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
          '_note':
              'Intentional golden for QG011 providerCapabilityGap. Update explicitly only.',
          ...normative,
        }));
      }
      final golden =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      expect(normative['snapshotId'], golden['snapshotId']);
      expect(normative['fingerprint'], golden['fingerprint']);
      expect(normative['decision'], golden['decision']);
      expect(normative['qg011Status'], golden['qg011Status']);
    });

    test('comparable json excludes temporal metadata', () async {
      final engine =
          QualityGateEngine(ruleEvaluator: QualityGateRuleEvaluator());
      final resolver = QualityGateSourceResolver(
        metricsProvider: FakeMetricsProvider(),
        scoreProvider: FakeScoreProvider(),
        mesProvider: FakeMESProvider(),
        observabilityProvider: FakeObservabilityProvider(),
        dashboardProvider: FakeDashboardProvider(),
      );
      final request = await QualityGateTestHelpers.passingRequest();
      final sources = await resolver.resolveAll(request);
      final result = engine.evaluate(
        request: request,
        policy: QualityGateReleasePolicyV1.create(),
        sources: sources,
      );
      final comparable = result.snapshot!.toComparableJson();
      final meta = comparable['metadata'] as Map<String, dynamic>;
      expect(meta.containsKey('createdAt'), isFalse);
      expect(meta.containsKey('evaluatedAt'), isFalse);
    });
  });
}
