import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/cloud_test_fixtures.dart';

void main() {
  group('Persistent Artifact Cloud models', () {
    void assertRoundtrip<T>({
      required String name,
      required T instance,
      required Map<String, dynamic> Function(T value) toJson,
      required T Function(Map<String, dynamic>) fromJson,
    }) {
      test('$name json roundtrip', () {
        expect(fromJson(toJson(instance)), equals(instance));
      });
    }

    assertRoundtrip(
      name: 'endpoint',
      instance: CloudTestFixtures.endpoint(),
      toJson: (v) => v.toJson(),
      fromJson: PersistentArtifactCloudEndpointReference.fromJson,
    );
    assertRoundtrip(
      name: 'region',
      instance: CloudTestFixtures.region(),
      toJson: (v) => v.toJson(),
      fromJson: PersistentArtifactCloudRegionReference.fromJson,
    );
    assertRoundtrip(
      name: 'failureDomain',
      instance: CloudTestFixtures.failureDomain(),
      toJson: (v) => v.toJson(),
      fromJson: PersistentArtifactCloudFailureDomainReference.fromJson,
    );
    assertRoundtrip(
      name: 'container',
      instance: CloudTestFixtures.container(),
      toJson: (v) => v.toJson(),
      fromJson: PersistentArtifactCloudContainerReference.fromJson,
    );
    assertRoundtrip(
      name: 'objectReference',
      instance: CloudTestFixtures.objectReference(),
      toJson: (v) => v.toJson(),
      fromJson: PersistentArtifactCloudObjectReference.fromJson,
    );
    assertRoundtrip(
      name: 'objectVersion',
      instance: CloudTestFixtures.objectVersion(),
      toJson: (v) => v.toJson(),
      fromJson: PersistentArtifactCloudObjectVersionReference.fromJson,
    );
    assertRoundtrip(
      name: 'authentication',
      instance: CloudTestFixtures.authentication(),
      toJson: (v) => v.toJson(),
      fromJson: PersistentArtifactCloudAuthenticationReference.fromJson,
    );
    assertRoundtrip(
      name: 'identity',
      instance: CloudTestFixtures.identity(),
      toJson: (v) => v.toJson(),
      fromJson: PersistentArtifactCloudIdentityReference.fromJson,
    );
    assertRoundtrip(
      name: 'encryption',
      instance: CloudTestFixtures.encryption(),
      toJson: (v) => v.toJson(),
      fromJson: PersistentArtifactCloudEncryptionCapability.fromJson,
    );
    assertRoundtrip(
      name: 'durability',
      instance: CloudTestFixtures.durability(),
      toJson: (v) => v.toJson(),
      fromJson: PersistentArtifactCloudDurabilityDescriptor.fromJson,
    );
    assertRoundtrip(
      name: 'replication',
      instance: CloudTestFixtures.replication(),
      toJson: (v) => v.toJson(),
      fromJson: PersistentArtifactCloudReplicationDescriptor.fromJson,
    );
    assertRoundtrip(
      name: 'consistency',
      instance: CloudTestFixtures.consistency(),
      toJson: (v) => v.toJson(),
      fromJson: PersistentArtifactCloudConsistencyCapability.fromJson,
    );
    assertRoundtrip(
      name: 'multipartUpload',
      instance: CloudTestFixtures.multipartUpload(),
      toJson: (v) => v.toJson(),
      fromJson: PersistentArtifactCloudMultipartUpload.fromJson,
    );
    assertRoundtrip(
      name: 'multipartPart',
      instance: CloudTestFixtures.multipartPart(),
      toJson: (v) => v.toJson(),
      fromJson: PersistentArtifactCloudMultipartPart.fromJson,
    );
    assertRoundtrip(
      name: 'retryPolicy',
      instance: CloudTestFixtures.retryPolicy(),
      toJson: (v) => v.toJson(),
      fromJson: PersistentArtifactCloudRetryPolicy.fromJson,
    );
    assertRoundtrip(
      name: 'timeoutPolicy',
      instance: CloudTestFixtures.timeoutPolicy(),
      toJson: (v) => v.toJson(),
      fromJson: PersistentArtifactCloudTimeoutPolicy.fromJson,
    );
    assertRoundtrip(
      name: 'operationRequest',
      instance: CloudTestFixtures.operationRequest(),
      toJson: (v) => v.toJson(),
      fromJson: PersistentArtifactCloudOperationRequest.fromJson,
    );
    assertRoundtrip(
      name: 'issue',
      instance: CloudTestFixtures.issue(),
      toJson: (v) => v.toJson(),
      fromJson: PersistentArtifactCloudIssue.fromJson,
    );
    assertRoundtrip(
      name: 'operationResult',
      instance: CloudTestFixtures.operationResult(),
      toJson: (v) => v.toJson(),
      fromJson: PersistentArtifactCloudOperationResult.fromJson,
    );
    assertRoundtrip(
      name: 'backendDescriptor',
      instance: CloudTestFixtures.backendDescriptor(),
      toJson: (v) => v.toJson(),
      fromJson: PersistentArtifactCloudBackendDescriptor.fromJson,
    );
    assertRoundtrip(
      name: 'promotionCriteria',
      instance: CloudTestFixtures.promotionCriteria(),
      toJson: (v) => v.toJson(),
      fromJson: PersistentArtifactCloudStagingPromotionCriteria.fromJson,
    );
    assertRoundtrip(
      name: 'readinessDecision',
      instance: CloudTestFixtures.readinessDecision(),
      toJson: (v) => v.toJson(),
      fromJson: PersistentArtifactCloudStagingReadinessDecision.fromJson,
    );

    test('copyWith updates endpoint field', () {
      final updated = CloudTestFixtures.endpoint().copyWith(pathPrefix: '/new');
      expect(updated.pathPrefix, '/new');
    });

    test('copyWith updates backend eligibility flags', () {
      final updated = CloudTestFixtures.backendDescriptor().copyWith(
        stagingEligible: true,
        productionEligible: false,
      );
      expect(updated.stagingEligible, isTrue);
      expect(updated.productionEligible, isFalse);
    });

    test('toComparableJson on request remains stable', () {
      final request = CloudTestFixtures.operationRequest();
      expect(request.toComparableJson(), equals(request.toComparableJson()));
    });
  });
}
