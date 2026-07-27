import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import '../support/cloud_test_fixtures.dart';

void main() {
  group('CloudBoundaryOperational', () {
    test('retry policy valida limites mínimos', () {
      final issues = PersistentArtifactCloudValidators.validateRetryPolicy(
        const PersistentArtifactCloudRetryPolicy(
          maxAttempts: 1,
          baseDelayMs: 1,
          maxDelayMs: 1,
          retryableClassifications: [CloudRetryClassification.transient],
        ),
      );
      expect(issues, isEmpty);
    });

    final timeoutCases = [1, 10, 100, 1000, 5000, 15000, 30000, 60000];
    for (final ms in timeoutCases) {
      test('timeout aceitável $ms ms', () {
        final issues = PersistentArtifactCloudValidators.validateTimeoutPolicy(
          PersistentArtifactCloudTimeoutPolicy(
            connectTimeoutMs: ms,
            readTimeoutMs: ms,
            writeTimeoutMs: ms,
          ),
        );
        expect(issues, isEmpty);
      });
    }

    test('descriptor padrão permanece determinístico', () {
      final d1 = CloudTestFixtures.backendDescriptor().toComparableJson();
      final d2 = CloudTestFixtures.backendDescriptor().toComparableJson();
      expect(d1, d2);
    });
  });
}
