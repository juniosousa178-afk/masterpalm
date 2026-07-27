import 'dart:convert';

import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/persistent_artifacts/persistent_artifact_operational_core.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_hardening_helpers.dart';
import 'support/persistent_artifact_test_fixtures.dart';

void main() {
  group('Persistent Artifact serialization audit', () {
    const serializer = PersistentArtifactCanonicalSerializer();

    test('snapshot json roundtrip keeps canonical fingerprint', () {
      final snapshot = PersistentArtifactTestFixtures.validSnapshot();
      final encoded = jsonEncode(snapshot.toJson());
      final restored = PersistentArtifactInfrastructureSnapshot.fromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      );
      expect(serializer.snapshotFingerprint(restored),
          serializer.snapshotFingerprint(snapshot));
    });

    test('evaluation result json roundtrip keeps snapshot reference', () async {
      final result = await evaluatePassingSnapshot();
      final restored = PersistentArtifactEvaluationResult.fromJson(
        jsonDecode(jsonEncode(result.toJson())) as Map<String, dynamic>,
      );
      expect(restored.snapshotReference?.snapshotId,
          result.snapshotReference?.snapshotId);
    });

    test('operation request and result remain serializable', () {
      final request = PersistentArtifactTestFixtures.validOperationRequest();
      final result = PersistentArtifactTestFixtures.validOperationResult();
      expect(
        PersistentArtifactOperationRequest.fromJson(request.toJson()).requestId,
        request.requestId,
      );
      expect(
        PersistentArtifactOperationResult.fromJson(result.toJson()).resultId,
        result.resultId,
      );
    });
  });
}
