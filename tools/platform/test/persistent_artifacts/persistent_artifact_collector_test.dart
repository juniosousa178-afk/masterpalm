import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_operational_fixtures.dart';

void main() {
  group('PersistentArtifactCollector', () {
    test('coleta subjects da request', () {
      final request = fixtureEvaluationRequest();
      final collector = PersistentArtifactCollector();
      final material = collector.collect(
        PersistentArtifactOperationContext(
          operation: PersistentArtifactOperationType.persist,
          request: request,
          sources: const ResolvedPersistentArtifactSources(
            status: PersistentArtifactSourceResolutionStatus.complete,
          ),
          material: const CollectedPersistentArtifactMaterial(),
        ),
      );
      expect(material.subjects.length, 1);
    });

    test('propaga policy references', () {
      final req = fixtureEvaluationRequest().copyWith(
        policyReferences: const [
          PersistentArtifactPolicyReference(
            policyId: 'p1',
            policyVersion: 1,
            policyType: PersistentArtifactPolicyType.storage,
            policyFingerprint: 'fp',
            status: PersistentArtifactPolicyStatus.candidate,
          ),
        ],
      );
      final material = const PersistentArtifactCollector().collect(
        PersistentArtifactOperationContext(
          operation: PersistentArtifactOperationType.persist,
          request: req,
          sources: ResolvedPersistentArtifactSources(
            status: PersistentArtifactSourceResolutionStatus.complete,
            sourceReferences: const [],
          ),
          material: const CollectedPersistentArtifactMaterial(),
        ),
      );
      expect(material.policies.length, 1);
    });

    for (var i = 0; i < 4; i++) {
      test('coleta metadata $i', () {
        final request = fixtureEvaluationRequest(evaluationId: 'eval-$i');
        final material = const PersistentArtifactCollector().collect(
          PersistentArtifactOperationContext(
            operation: PersistentArtifactOperationType.persist,
            request: request,
            sources: const ResolvedPersistentArtifactSources(
              status: PersistentArtifactSourceResolutionStatus.partial,
            ),
            material: const CollectedPersistentArtifactMaterial(),
          ),
        );
        expect(material.metadata['evaluationId'], 'eval-$i');
      });
    }
  });
}
