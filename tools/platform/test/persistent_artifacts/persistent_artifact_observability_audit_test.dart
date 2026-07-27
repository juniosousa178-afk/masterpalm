import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_hardening_helpers.dart';

void main() {
  group('Persistent Artifact observability audit', () {
    test('telemetry component enum includes persistentArtifacts', () {
      expect(
        TelemetryComponent.values
            .contains(TelemetryComponent.persistentArtifacts),
        isTrue,
      );
    });

    test('operation result includes metadata map for observability tags', () {
      final result = const PersistentArtifactOperationResult(
        resultId: 'obs-1',
        requestId: 'req-1',
        operationType: PersistentArtifactOperationType.persist,
        projectId: 'proj-a',
        status: PersistentArtifactOperationStatus.succeeded,
        metadata: {'traceId': 't-1'},
      );
      expect(result.metadata['traceId'], 't-1');
    });

    test('evaluation result metadata exposes declarative boundary marker',
        () async {
      final evaluation = await createTestStack().provider.evaluate(
            passingScenarioRequest(evaluationId: 'obs'),
          );
      expect(evaluation.metadata['declarativeBoundaries'], isNotEmpty);
    });
  });
}
