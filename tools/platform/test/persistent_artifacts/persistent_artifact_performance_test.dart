import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_hardening_helpers.dart';

void main() {
  group('Persistent Artifact performance tests', () {
    test('evaluate 200 requests under wide baseline', () async {
      final stack = createTestStack();
      final sw = Stopwatch()..start();
      for (var i = 0; i < 200; i++) {
        await stack.provider.evaluate(
          passingScenarioRequest(evaluationId: 'perf-eval-$i'),
        );
      }
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(120000));
    });

    test('publish 200 requests under wide baseline', () async {
      final stack = createTestStack();
      final sw = Stopwatch()..start();
      for (var i = 0; i < 200; i++) {
        await stack.provider.evaluateAndPublish(
          passingScenarioRequest(evaluationId: 'perf-pub-$i'),
        );
      }
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(120000));
    });

    test('query 5000 snapshots under wide baseline', () async {
      final stack = createTestStack();
      for (var i = 0; i < 500; i++) {
        await stack.provider.evaluateAndPublish(
          passingScenarioRequest(evaluationId: 'perf-query-$i'),
        );
      }
      final sw = Stopwatch()..start();
      final values = await stack.provider.query(
        const PersistentArtifactQuery(projectId: 'proj-a'),
      );
      sw.stop();
      expect(values, isNotEmpty);
      expect(sw.elapsedMilliseconds, lessThan(10000));
    });
  });
}
