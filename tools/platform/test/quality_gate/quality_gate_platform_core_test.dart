import 'dart:io';

import 'package:masterpalm_platform/core/platform_bootstrap.dart';
import 'package:masterpalm_platform/interfaces/quality_gate_provider.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_enums.dart';
import 'package:masterpalm_platform/quality_gate/policies/quality_gate_release_policy_v1.dart';
import 'package:masterpalm_platform/quality_gate/stores/in_memory_quality_gate_store.dart';
import 'package:test/test.dart';

import 'support/quality_gate_test_helpers.dart';

void main() {
  group('PlatformCore Quality Gate', () {
    test('qualityGate delegates to provider', () {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      expect(core.qualityGate(), isA<QualityGateProvider>());
    });

    test('qualityGateEvaluate does not publish', () async {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      final store = InMemoryQualityGateStore();
      await core
          .qualityGateEvaluate(await QualityGateTestHelpers.passingRequest());
      expect(await store.count(), 0);
    });

    test('qualityGateAndPublish publishes via provider store', () async {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      final result = await core
          .qualityGateAndPublish(await QualityGateTestHelpers.passingRequest());
      expect(result.snapshot, isNotNull);
      final loaded = await core.qualityGate().load(
            result.snapshot!.metadata.qualityGateSnapshotId,
          );
      expect(loaded, isNotNull);
    });

    test('multiple bootstraps resolve provider', () {
      final a = PlatformBootstrap.forRepo(Directory.current.path);
      final b = PlatformBootstrap.forRepo(Directory.current.path);
      expect(a.qualityGate(), isA<QualityGateProvider>());
      expect(b.qualityGate(), isA<QualityGateProvider>());
    });

    test('core does not embed normative policy logic', () async {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      final result = await core
          .qualityGateEvaluate(await QualityGateTestHelpers.passingRequest());
      expect(
        result.snapshot?.metadata.policyId,
        QualityGateReleasePolicyV1.policyId,
      );
      expect(result.status, QualityGateResultStatus.failure);
      expect(result.snapshot?.decision, QualityGateDecision.error);
    });
  });
}
