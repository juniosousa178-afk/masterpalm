import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_hardening_helpers.dart';

void main() {
  group('Persistent Artifact deletion evaluator audit', () {
    test('deletion evaluator blocks legal hold even with force', () async {
      final result = await evaluateBlockedDeletionScenario();
      expect(result.status, PersistentArtifactOperationStatus.blocked);
      expect(result.issues.first.code, 'legal-hold-blocks-deletion');
    });

    test('deletion evaluator succeeds when legal hold is false', () async {
      final result = await evaluateDeletionEligibleScenario();
      expect(result.status, PersistentArtifactOperationStatus.succeeded);
    });

    test('deletion evaluator metadata tracks force and legalHold flags',
        () async {
      final result = await evaluateBlockedDeletionScenario();
      expect(result.metadata['force'], 'true');
      expect(result.metadata['legalHold'], 'true');
    });
  });
}
