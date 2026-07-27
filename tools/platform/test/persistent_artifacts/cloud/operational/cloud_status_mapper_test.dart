import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import '../support/cloud_test_fixtures.dart';

void main() {
  group('CloudStatusMapper', () {
    const mapper = PersistentArtifactCloudStatusMapper();

    final statusCases =
        <CloudOperationStatus, PersistentArtifactCloudOperationStatus>{
      CloudOperationStatus.succeeded:
          PersistentArtifactCloudOperationStatus.success,
      CloudOperationStatus.pending:
          PersistentArtifactCloudOperationStatus.interrupted,
      CloudOperationStatus.partial:
          PersistentArtifactCloudOperationStatus.multipartIncomplete,
      CloudOperationStatus.failed:
          PersistentArtifactCloudOperationStatus.failed,
      CloudOperationStatus.blocked:
          PersistentArtifactCloudOperationStatus.stagingBlocked,
    };

    statusCases.forEach((source, expected) {
      test('map bridge status ${source.name} -> ${expected.name}', () {
        final result =
            CloudTestFixtures.operationResult().copyWith(status: source);
        expect(mapper.fromBridgeResult(result), expected);
      });
    });

    final issueCases = <String, PersistentArtifactCloudOperationStatus>{
      'idempotent': PersistentArtifactCloudOperationStatus.idempotent,
      'already-exists': PersistentArtifactCloudOperationStatus.alreadyExists,
      'conflict': PersistentArtifactCloudOperationStatus.conflict,
      'invalid': PersistentArtifactCloudOperationStatus.invalid,
      'not-found': PersistentArtifactCloudOperationStatus.notFound,
      'corrupted': PersistentArtifactCloudOperationStatus.corrupted,
      'too-large': PersistentArtifactCloudOperationStatus.tooLarge,
      'permission-denied':
          PersistentArtifactCloudOperationStatus.permissionDenied,
      'authentication-unavailable':
          PersistentArtifactCloudOperationStatus.authenticationUnavailable,
      'authentication-rejected':
          PersistentArtifactCloudOperationStatus.authenticationRejected,
      'endpoint-unavailable':
          PersistentArtifactCloudOperationStatus.endpointUnavailable,
      'region-unavailable':
          PersistentArtifactCloudOperationStatus.regionUnavailable,
      'throttled': PersistentArtifactCloudOperationStatus.throttled,
      'timeout': PersistentArtifactCloudOperationStatus.timeout,
      'interrupted': PersistentArtifactCloudOperationStatus.interrupted,
      'retry-exhausted': PersistentArtifactCloudOperationStatus.retryExhausted,
      'precondition-failed':
          PersistentArtifactCloudOperationStatus.preconditionFailed,
      'version-conflict':
          PersistentArtifactCloudOperationStatus.versionConflict,
      'multipart-incomplete':
          PersistentArtifactCloudOperationStatus.multipartIncomplete,
      'staging-blocked': PersistentArtifactCloudOperationStatus.stagingBlocked,
      'backend-disabled':
          PersistentArtifactCloudOperationStatus.backendDisabled,
      'backend-unregistered':
          PersistentArtifactCloudOperationStatus.unregistered,
      'backend-unavailable': PersistentArtifactCloudOperationStatus.unavailable,
      'backend-unsupported': PersistentArtifactCloudOperationStatus.unsupported,
    };

    issueCases.forEach((code, expected) {
      test('map issue code $code -> ${expected.name}', () {
        expect(mapper.fromIssueCode(code), expected);
      });
    });
  });
}
