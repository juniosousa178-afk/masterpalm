import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import '../support/cloud_test_fixtures.dart';

void main() {
  group('CloudStatusMappingAudit', () {
    const mapper = PersistentArtifactCloudStatusMapper();

    final auditCases = <String, PersistentArtifactCloudOperationStatus>{
      'idempotent': PersistentArtifactCloudOperationStatus.idempotent,
      'already-exists': PersistentArtifactCloudOperationStatus.alreadyExists,
      'conflict': PersistentArtifactCloudOperationStatus.conflict,
      'not-found': PersistentArtifactCloudOperationStatus.notFound,
      'throttled': PersistentArtifactCloudOperationStatus.throttled,
      'timeout': PersistentArtifactCloudOperationStatus.timeout,
      'backend-unavailable': PersistentArtifactCloudOperationStatus.unavailable,
      'backend-unsupported': PersistentArtifactCloudOperationStatus.unsupported,
      'backend-unregistered':
          PersistentArtifactCloudOperationStatus.unregistered,
      'staging-blocked': PersistentArtifactCloudOperationStatus.stagingBlocked,
    };

    auditCases.forEach((code, expected) {
      test('audita issue $code', () {
        final result = CloudTestFixtures.operationResult().copyWith(
          issues: [
            CloudTestFixtures.issue(code: code),
          ],
        );
        expect(mapper.fromBridgeResult(result), expected);
      });
    });
  });
}
