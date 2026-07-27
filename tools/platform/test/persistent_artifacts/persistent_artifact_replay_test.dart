import 'dart:convert';

import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/persistent_artifacts/persistent_artifact_operational_core.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_hardening_helpers.dart';
import 'support/persistent_artifact_operational_fixtures.dart';

void main() {
  group('Persistent Artifact replay', () {
    late PersistentArtifactTestStack stack;
    const serializer = PersistentArtifactCanonicalSerializer();
    const identityBuilder = PersistentArtifactInfrastructureIdentityBuilder();

    setUp(() {
      stack = createTestStack();
    });

    test('re-evaluate same input keeps snapshot fingerprint', () async {
      final request = passingScenarioRequest(evaluationId: 'replay-fp');
      final first = await stack.provider.evaluate(request);
      final second = await stack.provider.evaluate(request);
      expect(first.snapshot!.metadata['fingerprint'],
          second.snapshot!.metadata['fingerprint']);
      expect(first.snapshotReference!.snapshotId,
          second.snapshotReference!.snapshotId);
    });

    test('100 cycles json roundtrip preserves fingerprint', () async {
      final snapshot = (await evaluatePassingSnapshot(stack: stack)).snapshot!;
      final fp = serializer.snapshotFingerprint(snapshot);
      for (var i = 0; i < 100; i++) {
        final restored = PersistentArtifactInfrastructureSnapshot.fromJson(
          jsonDecode(jsonEncode(snapshot.toJson())) as Map<String, dynamic>,
        );
        expect(serializer.snapshotFingerprint(restored), fp);
      }
    });

    test('publish replay is idempotent for same request', () async {
      final request =
          passingScenarioRequest(evaluationId: 'publish-idempotent');
      await stack.provider.evaluateAndPublish(request);
      await stack.provider.evaluateAndPublish(request);
      expect(await stack.store.count(), 1);
    });

    group('15 scenario replays', () {
      test('01 passing evaluate scenario', () async {
        final result = await evaluatePassingSnapshot(stack: stack);
        expect(result.status, PersistentArtifactEvaluationStatus.partial);
        expect(result.snapshot, isNotNull);
      });

      test('02 passing publish scenario', () async {
        final result = await publishPassingSnapshot(stack: stack);
        expect(result.snapshot!.status,
            PersistentArtifactInfrastructureStatus.published);
      });

      test('03 partial source scenario', () async {
        final result = await evaluatePartialScenario(stack: stack);
        expect(result.status, PersistentArtifactEvaluationStatus.partial);
      });

      test('04 blocked deletion scenario', () async {
        final result = await evaluateBlockedDeletionScenario(stack: stack);
        expect(result.status, PersistentArtifactOperationStatus.blocked);
      });

      test('05 eligible deletion scenario', () async {
        final result = await evaluateDeletionEligibleScenario(stack: stack);
        expect(result.status, PersistentArtifactOperationStatus.succeeded);
      });

      test('06 integrity evaluation scenario', () async {
        final result = await evaluateIntegrityScenario(stack: stack);
        expect(result.status, PersistentArtifactOperationStatus.succeeded);
      });

      test('07 retention evaluation scenario', () async {
        final result = await evaluateRetentionScenario(stack: stack);
        expect(result.status, PersistentArtifactOperationStatus.succeeded);
      });

      test('08 replication evaluation scenario', () async {
        final result = await evaluateReplicationScenario(stack: stack);
        expect(result.status, PersistentArtifactOperationStatus.succeeded);
      });

      test('09 availability evaluation scenario', () async {
        final result = await evaluateAvailabilityScenario(stack: stack);
        expect(result.status, PersistentArtifactOperationStatus.succeeded);
      });

      test('10 lifecycle evaluation scenario', () async {
        final result = await evaluateLifecycleScenario(stack: stack);
        expect(result.status, PersistentArtifactOperationStatus.succeeded);
      });

      test('11 publication evaluation scenario', () async {
        final result = await evaluatePublicationScenario(stack: stack);
        expect(result.status, PersistentArtifactOperationStatus.succeeded);
      });

      test('12 tombstone builder scenario', () async {
        final result =
            await stack.provider.buildTombstone(fixtureEvaluationRequest());
        expect(result.metadata['tombstone'], 'built');
      });

      test('13 conflict publish scenario', () async {
        final conflict = await publishConflictingScenario(stack: stack);
        expect(conflict.toString(), contains('Snapshot conflict'));
      });

      test('14 identity builder scenario', () async {
        final snapshot =
            (await evaluatePassingSnapshot(stack: stack)).snapshot!;
        final identity = identityBuilder.buildIdentity(snapshot);
        expect(identity.persistentArtifactInfrastructureId, isNotEmpty);
      });

      test('15 query replay scenario', () async {
        await publishPassingSnapshot(stack: stack);
        final found = await stack.provider.query(
          const PersistentArtifactQuery(projectId: 'proj-a'),
        );
        expect(found, isNotEmpty);
      });
    });
  });
}
