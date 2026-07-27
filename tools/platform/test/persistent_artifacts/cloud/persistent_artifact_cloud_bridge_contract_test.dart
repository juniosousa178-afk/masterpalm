import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/cloud_test_fixtures.dart';
import 'support/fake_persistent_artifact_cloud_backend_bridge.dart';

void main() {
  group('Persistent Artifact Cloud bridge contract', () {
    final bridge = FakePersistentArtifactCloudBackendBridge();
    final request = CloudTestFixtures.operationRequest();

    test('describe returns cloud descriptor', () async {
      final descriptor = await bridge.describe();
      expect(descriptor.backendId, 'cloud-backend-1');
      expect(descriptor.productionEligible, isFalse);
    });

    test('evaluateCapabilities contains put/get/list primitives', () async {
      final capabilities = await bridge.evaluateCapabilities();
      expect(
          capabilities, contains(PersistentArtifactCloudCapability.putObject));
      expect(
          capabilities, contains(PersistentArtifactCloudCapability.getObject));
      expect(capabilities,
          contains(PersistentArtifactCloudCapability.listObjects));
    });

    test('putObject contract returns requestId', () async {
      final result = await bridge.putObject(request);
      expect(result.requestId, request.requestId);
      expect(result.operationType, CloudOperationType.putObject);
    });

    test('getObject contract returns success status', () async {
      final result = await bridge.getObject(
        request.copyWith(operationType: CloudOperationType.getObject),
      );
      expect(result.status, CloudOperationStatus.succeeded);
    });

    test('headObject contract returns success status', () async {
      final result = await bridge.headObject(
        request.copyWith(operationType: CloudOperationType.headObject),
      );
      expect(result.status, CloudOperationStatus.succeeded);
    });

    test('objectExists returns true when object reference exists', () async {
      expect(await bridge.objectExists(request), isTrue);
    });

    test('listObjects returns deterministic two entries', () async {
      final results = await bridge.listObjects(
        request.copyWith(operationType: CloudOperationType.listObjects),
      );
      expect(results, hasLength(2));
      expect(results.first.requestId, request.requestId);
    });

    test('deleteObject contract', () async {
      final result = await bridge.deleteObject(
        request.copyWith(operationType: CloudOperationType.deleteObject),
      );
      expect(result.status, CloudOperationStatus.succeeded);
    });

    test('copyObject contract', () async {
      final result = await bridge.copyObject(
        request.copyWith(operationType: CloudOperationType.copyObject),
      );
      expect(result.status, CloudOperationStatus.succeeded);
    });

    test('multipart lifecycle contract', () async {
      final begin = await bridge.beginMultipart(
        request.copyWith(operationType: CloudOperationType.beginMultipart),
      );
      final upload = await bridge.uploadPart(
        request.copyWith(operationType: CloudOperationType.uploadPart),
      );
      final complete = await bridge.completeMultipart(
        request.copyWith(operationType: CloudOperationType.completeMultipart),
      );
      final abort = await bridge.abortMultipart(
        request.copyWith(operationType: CloudOperationType.abortMultipart),
      );
      expect(begin.multipartStatus, CloudMultipartStatus.initiated);
      expect(upload.multipartStatus, CloudMultipartStatus.uploading);
      expect(complete.multipartStatus, CloudMultipartStatus.completed);
      expect(abort.multipartStatus, CloudMultipartStatus.aborted);
    });
  });
}
