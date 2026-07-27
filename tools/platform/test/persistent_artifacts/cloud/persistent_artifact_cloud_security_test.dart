import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/cloud_test_fixtures.dart';

void main() {
  group('Persistent Artifact Cloud security', () {
    const secretVectors = <Map<String, String>>[
      {'accessKey': 'AKIA...'},
      {'secretKey': 'abcd'},
      {'token': 'x'},
      {'password': 'x'},
      {'ref': 'https://example.invalid/path?X-Amz-Signature=123'},
      {'jwt': 'eyJhbGciOiJIUzI1NiJ9.payload.signature'},
    ];

    for (var i = 0; i < secretVectors.length; i++) {
      test('secret vector #$i rejected in descriptor metadata', () {
        final descriptor = CloudTestFixtures.backendDescriptor().copyWith(
          metadata: secretVectors[i],
        );
        final issues =
            PersistentArtifactCloudValidators.validateBackendDescriptor(
                descriptor);
        expect(issues.map((e) => e.code), contains('CLOUD_SENSITIVE_MATERIAL'));
      });
    }

    for (var i = 0; i < secretVectors.length; i++) {
      test('secret vector #$i rejected in auth metadata', () {
        final auth = CloudTestFixtures.authentication().copyWith(
          metadata: secretVectors[i],
        );
        final issues =
            PersistentArtifactCloudValidators.validateAuthenticationReference(
                auth);
        expect(issues.map((e) => e.code), contains('CLOUD_SENSITIVE_MATERIAL'));
      });
    }

    test('productionEligible default false', () {
      expect(CloudTestFixtures.backendDescriptor().productionEligible, isFalse);
    });

    test('staging decision default approved false', () {
      expect(CloudTestFixtures.readinessDecision().approved, isFalse);
    });
  });
}
