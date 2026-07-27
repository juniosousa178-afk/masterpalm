import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/cloud_test_fixtures.dart';

void main() {
  group('Persistent Artifact Cloud validators', () {
    test('valid backend has no critical issues', () {
      final issues =
          PersistentArtifactCloudValidators.validateBackendDescriptor(
        CloudTestFixtures.backendDescriptor(),
      );
      expect(
        issues.where((i) => i.severity == CloudIssueSeverity.critical),
        isEmpty,
      );
    });

    test('productionEligible true is blocked', () {
      final issues =
          PersistentArtifactCloudValidators.validateBackendDescriptor(
        CloudTestFixtures.backendDescriptor(productionEligible: true),
      );
      expect(
        issues.map((e) => e.code),
        contains('CLOUD_PRODUCTION_BLOCKED'),
      );
    });

    test('sensitive key names are rejected', () {
      final descriptor = CloudTestFixtures.backendDescriptor().copyWith(
        metadata: const {'accessKey': 'abc'},
      );
      final issues =
          PersistentArtifactCloudValidators.validateBackendDescriptor(
        descriptor,
      );
      expect(issues.map((e) => e.code), contains('CLOUD_SENSITIVE_MATERIAL'));
    });

    test('sensitive values are rejected', () {
      final descriptor = CloudTestFixtures.backendDescriptor().copyWith(
        metadata: const {'ref': 'eyJhbGciOiJIUzI1NiJ9.payload.signature'},
      );
      final issues =
          PersistentArtifactCloudValidators.validateBackendDescriptor(
        descriptor,
      );
      expect(issues.map((e) => e.code), contains('CLOUD_SENSITIVE_MATERIAL'));
    });

    test('operation request validates nested objects', () {
      final request = CloudTestFixtures.operationRequest().copyWith(
        objectReference:
            CloudTestFixtures.objectReference().copyWith(sizeBytes: -1),
      );
      final issues = PersistentArtifactCloudValidators.validateOperationRequest(
        request,
      );
      expect(issues.map((e) => e.code), contains('CLOUD_OBJECT_SIZE_INVALID'));
    });

    test('retry policy delay boundaries', () {
      final issues = PersistentArtifactCloudValidators.validateRetryPolicy(
        CloudTestFixtures.retryPolicy()
            .copyWith(baseDelayMs: 2000, maxDelayMs: 1000),
      );
      expect(issues.map((e) => e.code), contains('CLOUD_RETRY_DELAYS_INVALID'));
    });

    test('timeout policy must be positive', () {
      final issues = PersistentArtifactCloudValidators.validateTimeoutPolicy(
        CloudTestFixtures.timeoutPolicy().copyWith(connectTimeoutMs: 0),
      );
      expect(issues.map((e) => e.code), contains('CLOUD_TIMEOUT_INVALID'));
    });

    test('multipart part validations', () {
      final issues = PersistentArtifactCloudValidators.validateMultipartPart(
        CloudTestFixtures.multipartPart().copyWith(partNumber: 0),
      );
      expect(issues.map((e) => e.code), contains('CLOUD_PART_NUMBER_INVALID'));
    });

    test('custom provider emits warning', () {
      final issues = PersistentArtifactCloudValidators.validateProviderType(
        PersistentArtifactCloudProviderType.custom,
      );
      expect(issues.single.severity, CloudIssueSeverity.warning);
    });

    test('custom service emits warning', () {
      final issues = PersistentArtifactCloudValidators.validateServiceType(
        CloudServiceType.custom,
      );
      expect(issues.single.severity, CloudIssueSeverity.warning);
    });

    for (final term in const [
      'secretKey',
      'password',
      'token',
      'jwt',
      'presigned',
    ]) {
      test('blocked term "$term" is rejected', () {
        final descriptor = CloudTestFixtures.backendDescriptor().copyWith(
          metadata: {'k': term},
        );
        final issues =
            PersistentArtifactCloudValidators.validateBackendDescriptor(
          descriptor,
        );
        expect(issues.map((e) => e.code), contains('CLOUD_SENSITIVE_MATERIAL'));
      });
    }

    for (final pair in <MapEntry<String, PersistentArtifactCloudIssue>>[
      MapEntry(
        'endpoint id empty',
        PersistentArtifactCloudValidators.validateEndpointReference(
          CloudTestFixtures.endpoint().copyWith(endpointId: ''),
        ).first,
      ),
      MapEntry(
        'region id empty',
        PersistentArtifactCloudValidators.validateRegionReference(
          CloudTestFixtures.region().copyWith(regionId: ''),
        ).first,
      ),
      MapEntry(
        'container id empty',
        PersistentArtifactCloudValidators.validateContainerReference(
          CloudTestFixtures.container().copyWith(containerId: ''),
        ).first,
      ),
    ]) {
      test('validator reports ${pair.key}', () {
        expect(pair.value.code, isNotEmpty);
      });
    }
  });
}
