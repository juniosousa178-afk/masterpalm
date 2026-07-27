import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_operational_fixtures.dart';

void main() {
  group('PersistentArtifactBoundaryOperational', () {
    test('request serializa e desserializa', () {
      final request = fixtureEvaluationRequest();
      final restored =
          PersistentArtifactEvaluationRequest.fromJson(request.toJson());
      expect(restored, request);
    });

    test('result copyWith preserva campos', () {
      final result = PersistentArtifactEvaluationResult(
        status: PersistentArtifactEvaluationStatus.success,
        evaluationId: 'e',
        projectId: 'p',
        evaluatedAt: 't',
      );
      expect(result.copyWith(projectId: 'x').projectId, 'x');
    });

    test('query equality', () {
      const q1 = PersistentArtifactQuery(projectId: 'a', releaseId: 'b');
      const q2 = PersistentArtifactQuery(projectId: 'a', releaseId: 'b');
      expect(q1, q2);
    });

    test('sources comparable json ordenado', () {
      const sources = ResolvedPersistentArtifactSources(
        status: PersistentArtifactSourceResolutionStatus.partial,
        resolvedSources: ['b', 'a'],
      );
      final json = sources.toComparableJson();
      expect((json['resolvedSources'] as List).first, 'a');
    });

    for (var i = 0; i < 2; i++) {
      test('boundary cenario $i', () {
        final msg = PersistentArtifactOperationMessage(
          messageId: 'm$i',
          code: 'c',
          message: 'msg',
          severity: PersistentArtifactIssueSeverity.info,
          operation: PersistentArtifactOperationType.persist,
        );
        expect(msg.toComparableJson()['messageId'], 'm$i');
      });
    }
  });
}
