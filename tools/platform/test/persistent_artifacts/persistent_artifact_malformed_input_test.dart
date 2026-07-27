import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/persistent_artifacts/persistent_artifact_validators.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_operational_fixtures.dart';

void main() {
  group('Persistent Artifact malformed input tests', () {
    test('snapshot from empty json throws type error', () {
      expect(
        () => PersistentArtifactInfrastructureSnapshot.fromJson({}),
        throwsA(anything),
      );
    });

    test('invalid source type wireName throws format exception', () {
      expect(
        () => PersistentArtifactSourceTypeX.fromWireName('invalid-source'),
        throwsFormatException,
      );
    });

    test('engine marks result partial when request has empty subjects', () {
      final request = fixtureEvaluationRequest().copyWith(
        operationRequest: fixtureOperationRequest(subjects: const []),
      );
      final result = const PersistentArtifactEngine().evaluateOperation(
        request: request,
        material: const CollectedPersistentArtifactMaterial(),
      );
      expect(result.status, PersistentArtifactOperationStatus.partial);
    });

    test('subject validator rejects malformed empty subject id', () {
      final subject = fixtureSubject().copyWith(subjectId: '');
      final result =
          const PersistentArtifactSubjectValidator().validate(subject);
      expect(result.isValid, isFalse);
    });
  });
}
