import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/persistent_artifacts/persistent_artifact_operational_core.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_hardening_helpers.dart';

void main() {
  group('Persistent Artifact identity audit', () {
    const identityBuilder = PersistentArtifactInfrastructureIdentityBuilder();
    const serializer = PersistentArtifactCanonicalSerializer();

    test('identity builder includes fingerprint in snapshot id', () async {
      final snapshot = (await evaluatePassingSnapshot()).snapshot!;
      final identity = identityBuilder.buildIdentity(snapshot);
      expect(identity.snapshotFingerprint,
          serializer.snapshotFingerprint(snapshot));
      expect(identity.persistentArtifactInfrastructureId,
          contains(snapshot.projectId));
    });

    test('snapshot id generation is deterministic', () {
      const fingerprint = 'abc123';
      final idA = identityBuilder.buildSnapshotId(
        projectId: 'proj-a',
        releaseId: 'rel-a',
        fingerprint: fingerprint,
      );
      final idB = identityBuilder.buildSnapshotId(
        projectId: 'proj-a',
        releaseId: 'rel-a',
        fingerprint: fingerprint,
      );
      expect(idA, idB);
    });

    test('identity changes when snapshot content changes', () async {
      final base = (await evaluatePassingSnapshot()).snapshot!;
      final mutated =
          base.copyWith(metadata: {...base.metadata, 'mutation': '1'});
      final idA = identityBuilder.buildIdentity(base);
      final idB = identityBuilder.buildIdentity(mutated);
      expect(idA.snapshotFingerprint, isNot(idB.snapshotFingerprint));
    });
  });
}
