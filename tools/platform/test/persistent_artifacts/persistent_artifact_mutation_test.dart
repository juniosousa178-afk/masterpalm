import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/persistent_artifacts/persistent_artifact_operational_core.dart';
import 'package:masterpalm_platform/persistent_artifacts/persistent_artifact_validators.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_hardening_helpers.dart';
import 'support/persistent_artifact_test_fixtures.dart';

void main() {
  group('Persistent Artifact mutation tests', () {
    const snapshotValidator =
        PersistentArtifactInfrastructureSnapshotValidator();

    test('mutating projectId to empty makes snapshot invalid', () {
      final mutated = PersistentArtifactTestFixtures.validSnapshot()
          .copyWith(projectId: '');
      expect(snapshotValidator.validate(mutated).isValid, isFalse);
    });

    test('mutating createdAt to empty makes snapshot invalid', () {
      final mutated = PersistentArtifactTestFixtures.validSnapshot()
          .copyWith(createdAt: '');
      expect(snapshotValidator.validate(mutated).isValid, isFalse);
    });

    test('mutating metadata changes identity fingerprint', () async {
      final snapshot = (await evaluatePassingSnapshot()).snapshot!;
      const builder = PersistentArtifactInfrastructureIdentityBuilder();
      final base = builder.buildIdentity(snapshot).snapshotFingerprint;
      final mutated =
          snapshot.copyWith(metadata: {...snapshot.metadata, 'm': '1'});
      final changed = builder.buildIdentity(mutated).snapshotFingerprint;
      expect(changed, isNot(base));
    });

    test('mutating status in same snapshot id triggers conflict on save',
        () async {
      final stack = createTestStack();
      final published = (await publishPassingSnapshot(stack: stack)).snapshot!;
      final mutated = published.copyWith(
        status: PersistentArtifactInfrastructureStatus.invalidated,
      );
      expect(
        () => stack.store.save(mutated),
        throwsA(isA<PersistentArtifactSnapshotConflictException>()),
      );
    });
  });
}
