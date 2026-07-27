import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_hardening_helpers.dart';

void main() {
  group('Persistent Artifact hardening umbrella', () {
    test('evaluate publish load roundtrip preserves fingerprint', () async {
      final stack = createTestStack();
      final published = await publishPassingSnapshot(stack: stack);
      final loaded =
          await stack.provider.load(published.snapshotReference!.snapshotId);
      expect(loaded, isNotNull);
      expect(loaded!.metadata['fingerprint'],
          published.snapshot!.metadata['fingerprint']);
    });

    test('partial and blocked deletion produce distinct statuses', () async {
      final partial = await evaluatePartialScenario();
      final blocked = await evaluateBlockedDeletionScenario();
      expect(partial.status, PersistentArtifactEvaluationStatus.partial);
      expect(blocked.status, PersistentArtifactOperationStatus.blocked);
    });

    test('store idempotency holds under umbrella scenario', () async {
      final stack = createTestStack();
      final snapshot = (await evaluatePassingSnapshot(stack: stack)).snapshot!;
      await stack.store.save(snapshot);
      await stack.store.save(snapshot);
      expect(await stack.store.count(), 1);
    });

    test('declarative boundaries are exposed in evaluation metadata', () async {
      final result = await evaluatePassingSnapshot();
      expect(result.metadata['declarativeBoundaries'],
          contains('no-physical-storage'));
    });
  });
}
