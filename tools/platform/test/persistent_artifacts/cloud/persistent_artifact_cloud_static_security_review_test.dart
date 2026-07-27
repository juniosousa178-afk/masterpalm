import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/cloud_test_fixtures.dart';

void main() {
  group('Persistent Artifact Cloud static security review', () {
    final payloads = <Map<String, String>>[
      {'accessKey': 'x'},
      {'secretKey': 'x'},
      {'token': 'x'},
      {'password': 'x'},
      {'url': 'https://example.invalid/file?sig=123'},
      {'auth': 'eyJhbGciOiJIUzI1NiJ9.payload.signature'},
      {'combined': 'my-secretkey-token'},
      {'jwt_hint': 'jwt'},
      {'pre_signed_url': 'presigned'},
      {'sessionToken': 'abc'},
    ];

    for (var i = 0; i < payloads.length; i++) {
      test('payload #$i blocked in backend metadata', () {
        final issues =
            PersistentArtifactCloudValidators.validateBackendDescriptor(
          CloudTestFixtures.backendDescriptor().copyWith(metadata: payloads[i]),
        );
        expect(
          issues.where((e) => e.code == 'CLOUD_SENSITIVE_MATERIAL'),
          isNotEmpty,
        );
      });
    }

    test('security issues are critical', () {
      final issues =
          PersistentArtifactCloudValidators.validateAuthenticationReference(
        CloudTestFixtures.authentication().copyWith(
          metadata: const {'token': 'abc'},
        ),
      );
      expect(
        issues
            .where((e) => e.code == 'CLOUD_SENSITIVE_MATERIAL')
            .every((e) => e.severity == CloudIssueSeverity.critical),
        isTrue,
      );
    });
  });
}
