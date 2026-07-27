import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/persistent_artifacts/persistent_artifact_operational_core.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_hardening_helpers.dart';
import 'support/persistent_artifact_test_fixtures.dart';

void main() {
  group('Persistent Artifact builders audit', () {
    const descriptorBuilder = PersistentArtifactContentDescriptorBuilder();
    const snapshotBuilder = PersistentArtifactInfrastructureSnapshotBuilder();

    test('content descriptor builder derives fingerprint from subject', () {
      final subject = PersistentArtifactTestFixtures.validSubject();
      final descriptor = descriptorBuilder.fromSubject(
        subject,
        contentId: 'content-from-subject',
      );
      expect(descriptor.contentId, 'content-from-subject');
      expect(descriptor.contentFingerprint, isNotEmpty);
    });

    test('snapshot builder enriches metadata with snapshotId and fingerprint',
        () {
      final request = passingScenarioRequest(evaluationId: 'builder-snapshot');
      final operation = PersistentArtifactTestFixtures.validOperationResult();
      final snapshot = snapshotBuilder.build(
        request: request,
        material: const CollectedPersistentArtifactMaterial(),
        operationResult: operation,
        evaluatedAt: request.requestedAt,
      );
      expect(snapshot.metadata['snapshotId'], isNotEmpty);
      expect(snapshot.metadata['fingerprint'], isNotEmpty);
    });

    test('snapshot builder switches status when publishedAt is provided', () {
      final request = passingScenarioRequest(evaluationId: 'builder-publish');
      final operation = PersistentArtifactTestFixtures.validOperationResult();
      final evaluated = snapshotBuilder.build(
        request: request,
        material: const CollectedPersistentArtifactMaterial(),
        operationResult: operation,
        evaluatedAt: request.requestedAt,
      );
      final published = snapshotBuilder.build(
        request: request,
        material: const CollectedPersistentArtifactMaterial(),
        operationResult: operation,
        evaluatedAt: request.requestedAt,
        publishedAt: request.requestedAt,
      );
      expect(
          evaluated.status, PersistentArtifactInfrastructureStatus.evaluated);
      expect(
          published.status, PersistentArtifactInfrastructureStatus.published);
    });
  });
}
