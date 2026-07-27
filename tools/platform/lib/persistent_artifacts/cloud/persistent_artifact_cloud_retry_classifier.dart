import 'persistent_artifact_cloud_operation_status.dart';

class PersistentArtifactCloudRetryDecision {
  const PersistentArtifactCloudRetryDecision({
    required this.retryable,
    required this.classification,
  });

  final bool retryable;
  final String classification;
}

class PersistentArtifactCloudRetryClassifier {
  const PersistentArtifactCloudRetryClassifier();

  PersistentArtifactCloudRetryDecision classify(
    PersistentArtifactCloudOperationStatus status,
  ) {
    switch (status) {
      case PersistentArtifactCloudOperationStatus.throttled:
      case PersistentArtifactCloudOperationStatus.timeout:
      case PersistentArtifactCloudOperationStatus.endpointUnavailable:
      case PersistentArtifactCloudOperationStatus.regionUnavailable:
      case PersistentArtifactCloudOperationStatus.unavailable:
      case PersistentArtifactCloudOperationStatus.interrupted:
        return const PersistentArtifactCloudRetryDecision(
          retryable: true,
          classification: 'transient',
        );
      case PersistentArtifactCloudOperationStatus.retryExhausted:
        return const PersistentArtifactCloudRetryDecision(
          retryable: false,
          classification: 'exhausted',
        );
      case PersistentArtifactCloudOperationStatus.authenticationRejected:
      case PersistentArtifactCloudOperationStatus.permissionDenied:
      case PersistentArtifactCloudOperationStatus.unsupported:
      case PersistentArtifactCloudOperationStatus.invalid:
      case PersistentArtifactCloudOperationStatus.stagingBlocked:
      case PersistentArtifactCloudOperationStatus.backendDisabled:
      case PersistentArtifactCloudOperationStatus.unregistered:
      case PersistentArtifactCloudOperationStatus.failed:
      case PersistentArtifactCloudOperationStatus.corrupted:
      case PersistentArtifactCloudOperationStatus.tooLarge:
      case PersistentArtifactCloudOperationStatus.preconditionFailed:
      case PersistentArtifactCloudOperationStatus.versionConflict:
      case PersistentArtifactCloudOperationStatus.conflict:
      case PersistentArtifactCloudOperationStatus.notFound:
      case PersistentArtifactCloudOperationStatus.alreadyExists:
      case PersistentArtifactCloudOperationStatus.idempotent:
      case PersistentArtifactCloudOperationStatus.success:
      case PersistentArtifactCloudOperationStatus.multipartIncomplete:
      case PersistentArtifactCloudOperationStatus.authenticationUnavailable:
        return const PersistentArtifactCloudRetryDecision(
          retryable: false,
          classification: 'terminal',
        );
    }
  }
}
