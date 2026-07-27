import 'persistent_artifact_backend_environment.dart';
import 'persistent_artifact_physical_operation_status.dart';

class PersistentArtifactBackendEnvironmentDecision {
  const PersistentArtifactBackendEnvironmentDecision({
    required this.allowed,
    required this.status,
    required this.environment,
    required this.reasonCode,
    this.message,
    this.metadata = const {},
  });

  final bool allowed;
  final PersistentArtifactPhysicalOperationStatus status;
  final PersistentArtifactBackendEnvironment environment;
  final String reasonCode;
  final String? message;
  final Map<String, String> metadata;

  static PersistentArtifactBackendEnvironmentDecision allowedDecision({
    required PersistentArtifactBackendEnvironment environment,
  }) {
    return PersistentArtifactBackendEnvironmentDecision(
      allowed: true,
      status: PersistentArtifactPhysicalOperationStatus.succeeded,
      environment: environment,
      reasonCode: 'environment-allowed',
      message: 'Environment is allowed',
    );
  }

  static PersistentArtifactBackendEnvironmentDecision blockedDecision({
    required PersistentArtifactBackendEnvironment environment,
    required String reasonCode,
    required String message,
    Map<String, String> metadata = const {},
  }) {
    return PersistentArtifactBackendEnvironmentDecision(
      allowed: false,
      status: PersistentArtifactPhysicalOperationStatus.environmentBlocked,
      environment: environment,
      reasonCode: reasonCode,
      message: message,
      metadata: metadata,
    );
  }
}
