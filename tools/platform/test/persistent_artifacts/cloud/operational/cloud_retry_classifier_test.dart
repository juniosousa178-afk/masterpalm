import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

void main() {
  group('CloudRetryClassifier', () {
    const classifier = PersistentArtifactCloudRetryClassifier();

    final retryable = <PersistentArtifactCloudOperationStatus>{
      PersistentArtifactCloudOperationStatus.throttled,
      PersistentArtifactCloudOperationStatus.timeout,
      PersistentArtifactCloudOperationStatus.endpointUnavailable,
      PersistentArtifactCloudOperationStatus.regionUnavailable,
      PersistentArtifactCloudOperationStatus.unavailable,
      PersistentArtifactCloudOperationStatus.interrupted,
    };

    for (final status in PersistentArtifactCloudOperationStatus.values) {
      test('classifica ${status.name}', () {
        final decision = classifier.classify(status);
        expect(decision.retryable, retryable.contains(status));
      });
    }
  });
}
