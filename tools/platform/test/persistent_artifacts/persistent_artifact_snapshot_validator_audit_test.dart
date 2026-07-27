import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/persistent_artifacts/persistent_artifact_validators.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_test_fixtures.dart';

void main() {
  group('Persistent Artifact snapshot validator audit', () {
    const validator = PersistentArtifactInfrastructureSnapshotValidator();

    test('valid fixture snapshot passes validation', () {
      final result =
          validator.validate(PersistentArtifactTestFixtures.validSnapshot());
      expect(result.isValid, isTrue);
    });

    test('empty projectId snapshot fails validation', () {
      final snapshot = PersistentArtifactTestFixtures.validSnapshot()
          .copyWith(projectId: '');
      final result = validator.validate(snapshot);
      expect(result.isValid, isFalse);
    });

    test('empty createdAt snapshot fails validation', () {
      final snapshot = PersistentArtifactTestFixtures.validSnapshot()
          .copyWith(createdAt: '');
      final result = validator.validate(snapshot);
      expect(result.isValid, isFalse);
    });
  });
}
