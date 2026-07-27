import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/persistent_artifacts/persistent_artifact_operational_core.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_hardening_helpers.dart';

void main() {
  group('Persistent Artifact tombstone builder audit', () {
    test('tombstone builder is constructible', () {
      const builder = PersistentArtifactTombstoneBuilder();
      expect(builder, isNotNull);
    });

    test('provider buildTombstone returns succeeded operation', () async {
      final stack = createTestStack();
      final result =
          await stack.provider.buildTombstone(passingScenarioRequest());
      expect(result.status, PersistentArtifactOperationStatus.succeeded);
      expect(result.metadata['tombstone'], 'built');
    });

    test('tombstone operation result id uses tombstone prefix', () async {
      final stack = createTestStack();
      final result = await stack.provider.buildTombstone(
        passingScenarioRequest(evaluationId: 'tombstone-audit'),
      );
      expect(result.resultId, 'tombstone:tombstone-audit');
    });
  });
}
