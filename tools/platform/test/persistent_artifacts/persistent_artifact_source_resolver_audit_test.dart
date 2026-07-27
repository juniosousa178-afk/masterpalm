import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_hardening_helpers.dart';

void main() {
  group('Persistent Artifact source resolver audit', () {
    test('resolver returns unavailable when upstream snapshots absent',
        () async {
      final stack = createTestStack();
      final result =
          await stack.sourceResolver.resolveAll(passingScenarioRequest());
      expect(
          result.status, PersistentArtifactSourceResolutionStatus.unavailable);
      expect(result.resolvedSources, isEmpty);
      expect(result.unresolvedSources.length, 4);
    });

    test('injected source ids are represented as injected fingerprints',
        () async {
      final stack = createTestStack();
      final request = passingScenarioRequest().copyWith(
        injectedSources: const {'releaseEvidenceBundleId': 'bundle-1'},
      );
      final result = await stack.sourceResolver.resolveAll(request);
      expect(result.injectedSources,
          contains(PersistentArtifactSourceType.releaseEvidence.wireName));
      expect(result.sourceReferences.first.fingerprint, contains('injected:'));
    });

    test('resolver output fingerprint is deterministic per input', () async {
      final stack = createTestStack();
      final a = await stack.sourceResolver.resolveAll(passingScenarioRequest());
      final b = await stack.sourceResolver.resolveAll(passingScenarioRequest());
      expect(a.fingerprint, b.fingerprint);
    });
  });
}
