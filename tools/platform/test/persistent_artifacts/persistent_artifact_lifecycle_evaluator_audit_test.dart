import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/persistent_artifacts/persistent_artifact_operational_core.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_hardening_helpers.dart';

void main() {
  group('Persistent Artifact lifecycle evaluator audit', () {
    test('lifecycle evaluator is constructible', () {
      const evaluator = PersistentArtifactLifecycleEvaluator();
      expect(evaluator, isNotNull);
    });

    test('lifecycle operation returns succeeded', () async {
      final result = await evaluateLifecycleScenario();
      expect(result.status, PersistentArtifactOperationStatus.succeeded);
    });

    test('lifecycle operation type follows request operation', () async {
      final result = await evaluateLifecycleScenario();
      expect(result.operationType, PersistentArtifactOperationType.persist);
    });
  });
}
