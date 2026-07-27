import 'dart:math';

import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/persistent_artifacts/persistent_artifact_operational_core.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_hardening_helpers.dart';
import 'support/persistent_artifact_operational_fixtures.dart';

void main() {
  group('Persistent Artifact property-based tests', () {
    const serializer = PersistentArtifactCanonicalSerializer();
    final random = Random(53);

    test('snapshot fingerprint stable across repeated serialization', () async {
      final snapshot = (await evaluatePassingSnapshot()).snapshot!;
      final fp = serializer.snapshotFingerprint(snapshot);
      for (var i = 0; i < 20; i++) {
        expect(serializer.snapshotFingerprint(snapshot), fp);
      }
    });

    test('operation result stays partial when subject list is empty', () {
      for (var i = 0; i < 15; i++) {
        final request = fixtureEvaluationRequest(
          evaluationId: 'prop-$i',
        ).copyWith(
            operationRequest: fixtureOperationRequest(subjects: const []));
        final result = const PersistentArtifactEngine().evaluateOperation(
          request: request,
          material: const CollectedPersistentArtifactMaterial(),
        );
        expect(result.status, PersistentArtifactOperationStatus.partial);
      }
    });

    test('query paging invariant: result length <= limit', () async {
      final stack = createTestStack();
      for (var i = 0; i < 10; i++) {
        await stack.provider.evaluateAndPublish(
          passingScenarioRequest(evaluationId: 'paging-$i'),
        );
      }
      for (var i = 0; i < 5; i++) {
        final limit = 1 + random.nextInt(4);
        final values = await stack.provider.query(
          PersistentArtifactQuery(projectId: 'proj-a', limit: limit),
        );
        expect(values.length <= limit, isTrue);
      }
    });

    test('deletion policy invariant: legal hold always blocks', () async {
      for (var i = 0; i < 12; i++) {
        final result = await evaluateBlockedDeletionScenario();
        expect(result.status, PersistentArtifactOperationStatus.blocked);
      }
    });
  });
}
