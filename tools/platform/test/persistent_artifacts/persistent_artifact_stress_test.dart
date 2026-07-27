import 'dart:convert';

import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/persistent_artifacts/persistent_artifact_operational_core.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_hardening_helpers.dart';

void main() {
  group('Persistent Artifact stress tests', () {
    test('stores 5000 snapshots in memory store', () async {
      final stack = createTestStack();
      for (var i = 0; i < 5000; i++) {
        await stack.provider.evaluateAndPublish(
          passingScenarioRequest(evaluationId: 'stress-store-$i'),
        );
      }
      expect(await stack.store.count(), 5000);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('1000 serializer cycles keep snapshot fingerprint stable', () async {
      const serializer = PersistentArtifactCanonicalSerializer();
      final snapshot = (await evaluatePassingSnapshot()).snapshot!;
      final baseline = serializer.snapshotFingerprint(snapshot);
      for (var i = 0; i < 1000; i++) {
        final restored = PersistentArtifactInfrastructureSnapshot.fromJson(
          jsonDecode(jsonEncode(snapshot.toJson())) as Map<String, dynamic>,
        );
        expect(serializer.snapshotFingerprint(restored), baseline);
      }
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('repeated conflict detection stays deterministic under load',
        () async {
      final stack = createTestStack();
      final base = (await publishPassingSnapshot(stack: stack)).snapshot!;
      for (var i = 0; i < 100; i++) {
        final mutated = base.copyWith(
          status: PersistentArtifactInfrastructureStatus.invalidated,
        );
        expect(
          () => stack.store.save(mutated),
          throwsA(isA<PersistentArtifactSnapshotConflictException>()),
        );
      }
    });
  });
}
