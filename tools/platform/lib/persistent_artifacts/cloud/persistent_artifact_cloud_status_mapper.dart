import '../../models/persistent_artifacts/cloud/persistent_artifact_cloud_enums.dart';
import '../../models/persistent_artifacts/cloud/persistent_artifact_cloud_operation_result.dart';
import 'persistent_artifact_cloud_operation_status.dart';

class PersistentArtifactCloudStatusMapper {
  const PersistentArtifactCloudStatusMapper();

  PersistentArtifactCloudOperationStatus fromBridgeResult(
    PersistentArtifactCloudOperationResult result,
  ) {
    final issueStatus = _fromIssues(result);
    if (issueStatus != null) return issueStatus;

    final metadataStatus = fromWireOrNull(result.metadata['status']);
    if (metadataStatus != null) return metadataStatus;

    switch (result.status) {
      case CloudOperationStatus.succeeded:
        return PersistentArtifactCloudOperationStatus.success;
      case CloudOperationStatus.pending:
        return PersistentArtifactCloudOperationStatus.interrupted;
      case CloudOperationStatus.partial:
        return PersistentArtifactCloudOperationStatus.multipartIncomplete;
      case CloudOperationStatus.failed:
        return PersistentArtifactCloudOperationStatus.failed;
      case CloudOperationStatus.blocked:
        return PersistentArtifactCloudOperationStatus.stagingBlocked;
    }
  }

  PersistentArtifactCloudOperationStatus fromIssueCode(
    String? code, {
    PersistentArtifactCloudOperationStatus fallback =
        PersistentArtifactCloudOperationStatus.failed,
  }) {
    switch (code) {
      case 'idempotent':
        return PersistentArtifactCloudOperationStatus.idempotent;
      case 'already-exists':
        return PersistentArtifactCloudOperationStatus.alreadyExists;
      case 'conflict':
        return PersistentArtifactCloudOperationStatus.conflict;
      case 'invalid':
        return PersistentArtifactCloudOperationStatus.invalid;
      case 'not-found':
        return PersistentArtifactCloudOperationStatus.notFound;
      case 'corrupted':
        return PersistentArtifactCloudOperationStatus.corrupted;
      case 'too-large':
        return PersistentArtifactCloudOperationStatus.tooLarge;
      case 'permission-denied':
        return PersistentArtifactCloudOperationStatus.permissionDenied;
      case 'authentication-unavailable':
        return PersistentArtifactCloudOperationStatus.authenticationUnavailable;
      case 'authentication-rejected':
        return PersistentArtifactCloudOperationStatus.authenticationRejected;
      case 'endpoint-unavailable':
        return PersistentArtifactCloudOperationStatus.endpointUnavailable;
      case 'region-unavailable':
        return PersistentArtifactCloudOperationStatus.regionUnavailable;
      case 'throttled':
        return PersistentArtifactCloudOperationStatus.throttled;
      case 'timeout':
        return PersistentArtifactCloudOperationStatus.timeout;
      case 'interrupted':
        return PersistentArtifactCloudOperationStatus.interrupted;
      case 'retry-exhausted':
        return PersistentArtifactCloudOperationStatus.retryExhausted;
      case 'precondition-failed':
        return PersistentArtifactCloudOperationStatus.preconditionFailed;
      case 'version-conflict':
        return PersistentArtifactCloudOperationStatus.versionConflict;
      case 'multipart-incomplete':
        return PersistentArtifactCloudOperationStatus.multipartIncomplete;
      case 'staging-blocked':
        return PersistentArtifactCloudOperationStatus.stagingBlocked;
      case 'backend-disabled':
        return PersistentArtifactCloudOperationStatus.backendDisabled;
      case 'backend-unregistered':
        return PersistentArtifactCloudOperationStatus.unregistered;
      case 'backend-unavailable':
        return PersistentArtifactCloudOperationStatus.unavailable;
      case 'backend-unsupported':
        return PersistentArtifactCloudOperationStatus.unsupported;
      default:
        return fallback;
    }
  }

  PersistentArtifactCloudOperationStatus? fromWireOrNull(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      return PersistentArtifactCloudOperationStatusX.fromWireName(value);
    } catch (_) {
      return null;
    }
  }

  PersistentArtifactCloudOperationStatus? _fromIssues(
    PersistentArtifactCloudOperationResult result,
  ) {
    if (result.issues.isEmpty) return null;
    return fromIssueCode(
      result.issues.first.code,
      fallback: fromBridgeStatus(result.status),
    );
  }

  PersistentArtifactCloudOperationStatus fromBridgeStatus(
    CloudOperationStatus status,
  ) {
    switch (status) {
      case CloudOperationStatus.succeeded:
        return PersistentArtifactCloudOperationStatus.success;
      case CloudOperationStatus.pending:
        return PersistentArtifactCloudOperationStatus.interrupted;
      case CloudOperationStatus.partial:
        return PersistentArtifactCloudOperationStatus.multipartIncomplete;
      case CloudOperationStatus.failed:
        return PersistentArtifactCloudOperationStatus.failed;
      case CloudOperationStatus.blocked:
        return PersistentArtifactCloudOperationStatus.stagingBlocked;
    }
  }
}
