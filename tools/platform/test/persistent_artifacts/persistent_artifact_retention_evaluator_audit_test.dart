import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_hardening_helpers.dart';

void main() {
  group('Persistent Artifact retention evaluator audit', () {
    test('retention evaluator is wired in policy evaluators', () {
      const evaluators = PersistentArtifactPolicyEvaluators();
      expect(evaluators.retention, isA<PersistentArtifactRetentionEvaluator>());
    });

    test('retention operation returns succeeded with valid request', () async {
      final result = await evaluateRetentionScenario();
      expect(result.status, PersistentArtifactOperationStatus.succeeded);
    });

    test('retention operation keeps project and release scoping', () async {
      final result = await evaluateRetentionScenario();
      expect(result.projectId, 'proj-a');
      expect(result.releaseId, 'rel-a');
    });
  });
}
