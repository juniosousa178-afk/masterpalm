import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/persistent_artifacts/persistent_artifact_operational_core.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_hardening_helpers.dart';

void main() {
  group('Persistent Artifact availability evaluator audit', () {
    test('availability evaluator is constructible', () {
      const evaluator = PersistentArtifactAvailabilityEvaluator();
      expect(evaluator, isNotNull);
    });

    test('availability operation returns succeeded', () async {
      final result = await evaluateAvailabilityScenario();
      expect(result.status, PersistentArtifactOperationStatus.succeeded);
    });

    test('availability operation carries deterministic result id', () async {
      final result = await evaluateAvailabilityScenario();
      expect(result.resultId, contains('op:'));
    });
  });
}
