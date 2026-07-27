import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/cloud_test_fixtures.dart';

void main() {
  group('Persistent Artifact Cloud boundary', () {
    test('zero and negative size rejected', () {
      final zero = CloudTestFixtures.multipartPart().copyWith(sizeBytes: 0);
      final negative =
          CloudTestFixtures.objectReference().copyWith(sizeBytes: -10);
      expect(
        PersistentArtifactCloudValidators.validateMultipartPart(zero),
        isNotEmpty,
      );
      expect(
        PersistentArtifactCloudValidators.validateObjectReference(negative),
        isNotEmpty,
      );
    });

    test('timeout boundaries rejected', () {
      final policy = CloudTestFixtures.timeoutPolicy().copyWith(
        connectTimeoutMs: -1,
        readTimeoutMs: 0,
        writeTimeoutMs: 0,
      );
      expect(PersistentArtifactCloudValidators.validateTimeoutPolicy(policy),
          isNotEmpty);
    });

    test('retry boundaries rejected', () {
      final policy = CloudTestFixtures.retryPolicy().copyWith(
        maxAttempts: 0,
        baseDelayMs: -1,
      );
      expect(PersistentArtifactCloudValidators.validateRetryPolicy(policy),
          isNotEmpty);
    });

    test('durability availability outside range rejected', () {
      final descriptor = CloudTestFixtures.durability().copyWith(
        expectedAvailabilityPercent: 200,
      );
      expect(
        PersistentArtifactCloudValidators.validateDurabilityDescriptor(
            descriptor),
        isNotEmpty,
      );
    });

    test('empty ids are rejected by validators', () {
      expect(
        PersistentArtifactCloudValidators.validateRegionReference(
          CloudTestFixtures.region().copyWith(regionId: ''),
        ),
        isNotEmpty,
      );
      expect(
        PersistentArtifactCloudValidators.validateIdentityReference(
          CloudTestFixtures.identity().copyWith(identityId: ''),
        ),
        isNotEmpty,
      );
    });
  });
}
