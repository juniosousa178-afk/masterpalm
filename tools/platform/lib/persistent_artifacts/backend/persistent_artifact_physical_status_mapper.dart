import '../adapters/filesystem/secure_filesystem_backend_result.dart';
import 'persistent_artifact_physical_operation_status.dart';

class PersistentArtifactPhysicalStatusMapper {
  const PersistentArtifactPhysicalStatusMapper._();

  static PersistentArtifactPhysicalOperationStatus fromFilesystemOutcome(
    SecureFilesystemBackendOutcome outcome,
  ) {
    switch (outcome) {
      case SecureFilesystemBackendOutcome.succeeded:
        return PersistentArtifactPhysicalOperationStatus.succeeded;
      case SecureFilesystemBackendOutcome.notFound:
        return PersistentArtifactPhysicalOperationStatus.notFound;
      case SecureFilesystemBackendOutcome.conflict:
        return PersistentArtifactPhysicalOperationStatus.conflict;
      case SecureFilesystemBackendOutcome.rejected:
        return PersistentArtifactPhysicalOperationStatus.rejected;
      case SecureFilesystemBackendOutcome.exceededLimit:
        return PersistentArtifactPhysicalOperationStatus.exceededLimit;
      case SecureFilesystemBackendOutcome.ioError:
        return PersistentArtifactPhysicalOperationStatus.ioError;
    }
  }

  static PersistentArtifactPhysicalOperationStatus fromIssueCode(
    String? code, {
    PersistentArtifactPhysicalOperationStatus fallback =
        PersistentArtifactPhysicalOperationStatus.failed,
  }) {
    switch (code) {
      case 'idempotent':
        return PersistentArtifactPhysicalOperationStatus.idempotent;
      case 'invalid':
        return PersistentArtifactPhysicalOperationStatus.invalid;
      case 'corrupted':
        return PersistentArtifactPhysicalOperationStatus.corrupted;
      case 'permission-denied':
        return PersistentArtifactPhysicalOperationStatus.permissionDenied;
      case 'path-rejected':
        return PersistentArtifactPhysicalOperationStatus.pathRejected;
      case 'digest-mismatch':
        return PersistentArtifactPhysicalOperationStatus.digestMismatch;
      case 'interrupted':
        return PersistentArtifactPhysicalOperationStatus.interrupted;
      case 'quarantined':
        return PersistentArtifactPhysicalOperationStatus.quarantined;
      case 'environment-blocked':
        return PersistentArtifactPhysicalOperationStatus.environmentBlocked;
      case 'backend-disabled':
        return PersistentArtifactPhysicalOperationStatus.backendDisabled;
      case 'backend-unregistered':
        return PersistentArtifactPhysicalOperationStatus.unregistered;
      case 'backend-unavailable':
        return PersistentArtifactPhysicalOperationStatus.unavailable;
      case 'backend-unsupported':
        return PersistentArtifactPhysicalOperationStatus.unsupported;
      default:
        return fallback;
    }
  }
}
