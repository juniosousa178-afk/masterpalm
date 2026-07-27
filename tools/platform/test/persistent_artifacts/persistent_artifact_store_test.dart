import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_operational_fixtures.dart';

PersistentArtifactInfrastructureSnapshot _snapshot(String id) {
  final subject = fixtureSubject();
  return PersistentArtifactInfrastructureSnapshot(
    projectId: 'proj-a',
    releaseId: 'rel-a',
    subjects: [subject],
    status: PersistentArtifactInfrastructureStatus.evaluated,
    createdAt: '2026-07-22T00:00:00Z',
    identity: PersistentArtifactInfrastructureIdentity(
      persistentArtifactInfrastructureId: id,
      snapshotFingerprint: 'fp-$id',
    ),
    metadata: {'snapshotId': id, 'fingerprint': 'fp-$id'},
  );
}

void main() {
  group('InMemoryPersistentArtifactSnapshotStore', () {
    test('save/load', () async {
      final store = InMemoryPersistentArtifactSnapshotStore();
      await store.save(_snapshot('s1'));
      final loaded = await store.load('s1');
      expect(loaded, isNotNull);
    });

    test('exists', () async {
      final store = InMemoryPersistentArtifactSnapshotStore();
      await store.save(_snapshot('s1'));
      expect(await store.exists('s1'), isTrue);
    });

    test('latest', () async {
      final store = InMemoryPersistentArtifactSnapshotStore();
      await store.save(_snapshot('s1'));
      final latest =
          await store.latest(projectId: 'proj-a', releaseId: 'rel-a');
      expect(latest, isNotNull);
    });

    test('query por projeto', () async {
      final store = InMemoryPersistentArtifactSnapshotStore();
      await store.save(_snapshot('s1'));
      final list =
          await store.query(const PersistentArtifactQuery(projectId: 'proj-a'));
      expect(list.length, 1);
    });

    test('invalidate remove snapshot', () async {
      final store = InMemoryPersistentArtifactSnapshotStore();
      await store.save(_snapshot('s1'));
      await store.invalidate('s1');
      expect(await store.load('s1'), isNull);
    });

    test('count', () async {
      final store = InMemoryPersistentArtifactSnapshotStore();
      await store.save(_snapshot('s1'));
      expect(await store.count(), 1);
    });

    test('clear', () async {
      final store = InMemoryPersistentArtifactSnapshotStore();
      await store.save(_snapshot('s1'));
      await store.clear();
      expect(await store.count(), 0);
    });

    test('idempotencia no save', () async {
      final store = InMemoryPersistentArtifactSnapshotStore();
      await store.save(_snapshot('s1'));
      await store.save(_snapshot('s1'));
      expect(await store.count(), 1);
    });
  });
}
