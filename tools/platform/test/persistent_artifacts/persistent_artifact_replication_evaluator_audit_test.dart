import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_hardening_helpers.dart';

void main() {
  group('Persistent Artifact replication evaluator audit', () {
    test('replication evaluator is wired in policy evaluators', () {
      const evaluators = PersistentArtifactPolicyEvaluators();
      expect(evaluators.replication,
          isA<PersistentArtifactReplicationEvaluator>());
    });

    test('replication operation returns succeeded', () async {
      final result = await evaluateReplicationScenario();
      expect(result.status, PersistentArtifactOperationStatus.succeeded);
    });

    test('replication path remains deterministic for fixed request', () async {
      final a = await evaluateReplicationScenario();
      final b = await evaluateReplicationScenario();
      expect(a.resultId, b.resultId);
    });
  });
}
