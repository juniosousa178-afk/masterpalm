import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_hardening_helpers.dart';

void main() {
  group('Persistent Artifact store audit', () {
    test('save same snapshot twice is idempotent', () async {
      final store = InMemoryPersistentArtifactSnapshotStore();
      final snapshot = (await evaluatePassingSnapshot()).snapshot!;
      await store.save(snapshot);
      await store.save(snapshot);
      expect(await store.count(), 1);
    });

    test('save conflicting snapshot id throws conflict exception', () async {
      final store = InMemoryPersistentArtifactSnapshotStore();
      final snapshot = (await evaluatePassingSnapshot()).snapshot!;
      await store.save(snapshot);
      final conflicting = snapshot.copyWith(
        status: PersistentArtifactInfrastructureStatus.invalidated,
      );
      expect(
        () => store.save(conflicting),
        throwsA(isA<PersistentArtifactSnapshotConflictException>()),
      );
    });

    test('query with limit and offset is deterministic', () async {
      final stack =
          createTestStack(store: InMemoryPersistentArtifactSnapshotStore());
      for (var i = 0; i < 5; i++) {
        await stack.provider.evaluateAndPublish(
          passingScenarioRequest(evaluationId: 'q-$i'),
        );
      }
      final query = const PersistentArtifactQuery(
          projectId: 'proj-a', limit: 2, offset: 1);
      final values = await stack.store.query(query);
      expect(values.length, 2);
    });
  });
}
