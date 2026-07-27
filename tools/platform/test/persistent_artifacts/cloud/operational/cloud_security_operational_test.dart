import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import '../support/cloud_test_fixtures.dart';

void main() {
  group('CloudSecurityOperational', () {
    final blockedTokens = [
      'accessKey',
      'secretKey',
      'token',
      'password',
      'jwt',
      'presigned',
    ];

    for (final token in blockedTokens) {
      test('validador bloqueia metadata sensível: $token', () {
        final descriptor = CloudTestFixtures.backendDescriptor().copyWith(
          metadata: {token: 'value'},
        );
        final issues =
            PersistentArtifactCloudValidators.validateBackendDescriptor(
                descriptor);
        expect(issues.isNotEmpty, isTrue);
      });
    }
  });
}
