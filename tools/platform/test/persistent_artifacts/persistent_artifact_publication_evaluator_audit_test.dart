import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/persistent_artifacts/persistent_artifact_operational_core.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_hardening_helpers.dart';

void main() {
  group('Persistent Artifact publication evaluator audit', () {
    test('publication evaluator is constructible', () {
      const evaluator = PersistentArtifactPublicationEvaluator();
      expect(evaluator, isNotNull);
    });

    test('publication operation returns succeeded', () async {
      final result = await evaluatePublicationScenario();
      expect(result.status, PersistentArtifactOperationStatus.succeeded);
    });

    test('publish scenario results in published snapshot status', () async {
      final result = await publishPassingSnapshot();
      expect(result.snapshot!.status,
          PersistentArtifactInfrastructureStatus.published);
    });
  });
}
