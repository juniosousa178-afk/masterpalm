import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_hardening_helpers.dart';

void main() {
  group('Persistent Artifact collector audit', () {
    const collector = PersistentArtifactCollector();

    test('collector propagates subjects and references', () async {
      final stack = createTestStack();
      final request = passingScenarioRequest();
      final sources = await stack.sourceResolver.resolveAll(request);
      final context = PersistentArtifactOperationContext(
        operation: PersistentArtifactOperationType.persist,
        request: request,
        sources: sources,
        material: const CollectedPersistentArtifactMaterial(),
      );
      final material = collector.collect(context);
      expect(material.subjects.length,
          request.operationRequest.artifactSubjects.length);
      expect(material.sourceReferences.length, sources.sourceReferences.length);
    });

    test('collector metadata includes evaluationId and projectId', () async {
      final stack = createTestStack();
      final request = passingScenarioRequest(evaluationId: 'collector-meta');
      final sources = await stack.sourceResolver.resolveAll(request);
      final context = PersistentArtifactOperationContext(
        operation: PersistentArtifactOperationType.persist,
        request: request,
        sources: sources,
        material: const CollectedPersistentArtifactMaterial(),
      );
      final material = collector.collect(context);
      expect(material.metadata['evaluationId'], 'collector-meta');
      expect(material.metadata['projectId'], request.projectId);
    });

    test('collector output stays deterministic for same context', () async {
      final stack = createTestStack();
      final request =
          passingScenarioRequest(evaluationId: 'collector-determinism');
      final sources = await stack.sourceResolver.resolveAll(request);
      final context = PersistentArtifactOperationContext(
        operation: PersistentArtifactOperationType.persist,
        request: request,
        sources: sources,
        material: const CollectedPersistentArtifactMaterial(),
      );
      final a = collector.collect(context);
      final b = collector.collect(context);
      expect(a.toComparableJson(), b.toComparableJson());
    });
  });
}
