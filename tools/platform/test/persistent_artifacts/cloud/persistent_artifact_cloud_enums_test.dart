import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

void main() {
  group('Persistent Artifact Cloud enums', () {
    test('PersistentArtifactCloudProviderType roundtrip', () {
      for (final value in PersistentArtifactCloudProviderType.values) {
        expect(
          PersistentArtifactCloudProviderTypeX.fromWireName(value.wireName),
          value,
        );
      }
    });

    test('CloudServiceType roundtrip', () {
      for (final value in CloudServiceType.values) {
        expect(CloudServiceTypeX.fromWireName(value.wireName), value);
      }
    });

    test('CloudEndpointType roundtrip', () {
      for (final value in CloudEndpointType.values) {
        expect(CloudEndpointTypeX.fromWireName(value.wireName), value);
      }
    });

    test('CloudAuthenticationType roundtrip', () {
      for (final value in CloudAuthenticationType.values) {
        expect(CloudAuthenticationTypeX.fromWireName(value.wireName), value);
      }
    });

    test('CloudIdentityType roundtrip', () {
      for (final value in CloudIdentityType.values) {
        expect(CloudIdentityTypeX.fromWireName(value.wireName), value);
      }
    });

    test('CloudEncryptionMode roundtrip', () {
      for (final value in CloudEncryptionMode.values) {
        expect(CloudEncryptionModeX.fromWireName(value.wireName), value);
      }
    });

    test('CloudReplicationMode roundtrip', () {
      for (final value in CloudReplicationMode.values) {
        expect(CloudReplicationModeX.fromWireName(value.wireName), value);
      }
    });

    test('CloudConsistencyLevel roundtrip', () {
      for (final value in CloudConsistencyLevel.values) {
        expect(CloudConsistencyLevelX.fromWireName(value.wireName), value);
      }
    });

    test('CloudObjectStatus roundtrip', () {
      for (final value in CloudObjectStatus.values) {
        expect(CloudObjectStatusX.fromWireName(value.wireName), value);
      }
    });

    test('CloudOperationType roundtrip', () {
      for (final value in CloudOperationType.values) {
        expect(CloudOperationTypeX.fromWireName(value.wireName), value);
      }
    });

    test('CloudOperationStatus roundtrip', () {
      for (final value in CloudOperationStatus.values) {
        expect(CloudOperationStatusX.fromWireName(value.wireName), value);
      }
    });

    test('CloudMultipartStatus roundtrip', () {
      for (final value in CloudMultipartStatus.values) {
        expect(CloudMultipartStatusX.fromWireName(value.wireName), value);
      }
    });

    test('CloudRetryClassification roundtrip', () {
      for (final value in CloudRetryClassification.values) {
        expect(CloudRetryClassificationX.fromWireName(value.wireName), value);
      }
    });

    test('CloudRegionStatus roundtrip', () {
      for (final value in CloudRegionStatus.values) {
        expect(CloudRegionStatusX.fromWireName(value.wireName), value);
      }
    });

    test('CloudPromotionStatus roundtrip', () {
      for (final value in CloudPromotionStatus.values) {
        expect(CloudPromotionStatusX.fromWireName(value.wireName), value);
      }
    });

    test('CloudIssueSeverity roundtrip', () {
      for (final value in CloudIssueSeverity.values) {
        expect(CloudIssueSeverityX.fromWireName(value.wireName), value);
      }
    });

    test('unknown wire name throws FormatException', () {
      expect(
          () => CloudServiceTypeX.fromWireName('???'), throwsFormatException);
      expect(
          () => CloudIssueSeverityX.fromWireName('???'), throwsFormatException);
    });
  });
}
