import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/cloud_test_fixtures.dart';

void main() {
  group('Persistent Artifact Cloud fingerprint', () {
    test('backend descriptor fingerprint has sha256 length', () {
      final fp = PersistentArtifactCloudFingerprint.backendDescriptor(
        CloudTestFixtures.backendDescriptor(),
      );
      expect(fp, hasLength(64));
    });

    test('operation request fingerprint deterministic', () {
      final request = CloudTestFixtures.operationRequest();
      final values = List.generate(
        5,
        (_) => PersistentArtifactCloudFingerprint.operationRequest(request),
      );
      expect(values.toSet(), hasLength(1));
    });

    test('operation result fingerprint changes when status changes', () {
      final a = PersistentArtifactCloudFingerprint.operationResult(
        CloudTestFixtures.operationResult(),
      );
      final b = PersistentArtifactCloudFingerprint.operationResult(
        CloudTestFixtures.operationResult()
            .copyWith(status: CloudOperationStatus.failed),
      );
      expect(a, isNot(equals(b)));
    });

    test('staging decision fingerprint deterministic', () {
      final decision = CloudTestFixtures.readinessDecision();
      expect(
        PersistentArtifactCloudFingerprint.stagingDecision(decision),
        PersistentArtifactCloudFingerprint.stagingDecision(decision),
      );
    });

    test('comparable json normalization is order-independent', () {
      final requestA = CloudTestFixtures.operationRequest().copyWith(
        metadata: const {'z': '1', 'a': '2'},
      );
      final requestB = CloudTestFixtures.operationRequest().copyWith(
        metadata: const {'a': '2', 'z': '1'},
      );
      expect(
        PersistentArtifactCloudFingerprint.operationRequest(requestA),
        PersistentArtifactCloudFingerprint.operationRequest(requestB),
      );
    });
  });
}
