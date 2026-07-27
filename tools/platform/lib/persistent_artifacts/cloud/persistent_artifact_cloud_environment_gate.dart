import '../backend/persistent_artifact_environment_gate.dart';
import 'persistent_artifact_cloud_bridge_classification.dart';
import 'persistent_artifact_cloud_operation_models.dart';
import 'persistent_artifact_cloud_operation_status.dart';

class PersistentArtifactCloudEnvironmentGate {
  const PersistentArtifactCloudEnvironmentGate();

  PersistentArtifactCloudEnvironmentDecision evaluate({
    required String backendId,
    required PersistentArtifactRuntimeEnvironment runtimeEnvironment,
    required PersistentArtifactCloudBridgeClassification classification,
  }) {
    if (classification ==
        PersistentArtifactCloudBridgeClassification.contractOnly) {
      switch (runtimeEnvironment) {
        case PersistentArtifactRuntimeEnvironment.test:
        case PersistentArtifactRuntimeEnvironment.development:
        case PersistentArtifactRuntimeEnvironment.localReference:
          return PersistentArtifactCloudEnvironmentDecision(
            backendId: backendId,
            runtimeEnvironment: runtimeEnvironment,
            allowed: true,
            status: PersistentArtifactCloudOperationStatus.success,
            reasonCode: 'cloud-contract-only-validation',
            message:
                'Contract-only bridge permitted for structural validation only',
            classification: classification,
          );
        case PersistentArtifactRuntimeEnvironment.staging:
          return PersistentArtifactCloudEnvironmentDecision(
            backendId: backendId,
            runtimeEnvironment: runtimeEnvironment,
            allowed: false,
            status: PersistentArtifactCloudOperationStatus.stagingBlocked,
            reasonCode: 'cloud-staging-blocked',
            message: 'Staging cloud operation is blocked by policy',
            classification: classification,
          );
        case PersistentArtifactRuntimeEnvironment.production:
          return PersistentArtifactCloudEnvironmentDecision(
            backendId: backendId,
            runtimeEnvironment: runtimeEnvironment,
            allowed: false,
            status: PersistentArtifactCloudOperationStatus.stagingBlocked,
            reasonCode: 'cloud-production-blocked',
            message: 'Production cloud operation is blocked by policy',
            classification: classification,
          );
      }
    }

    switch (runtimeEnvironment) {
      case PersistentArtifactRuntimeEnvironment.test:
      case PersistentArtifactRuntimeEnvironment.development:
      case PersistentArtifactRuntimeEnvironment.localReference:
        return PersistentArtifactCloudEnvironmentDecision(
          backendId: backendId,
          runtimeEnvironment: runtimeEnvironment,
          allowed: true,
          status: PersistentArtifactCloudOperationStatus.success,
          classification: classification,
        );
      case PersistentArtifactRuntimeEnvironment.staging:
        return PersistentArtifactCloudEnvironmentDecision(
          backendId: backendId,
          runtimeEnvironment: runtimeEnvironment,
          allowed: false,
          status: PersistentArtifactCloudOperationStatus.stagingBlocked,
          reasonCode: 'cloud-staging-blocked',
          message: 'Staging cloud operation is blocked by policy',
          classification: classification,
        );
      case PersistentArtifactRuntimeEnvironment.production:
        return PersistentArtifactCloudEnvironmentDecision(
          backendId: backendId,
          runtimeEnvironment: runtimeEnvironment,
          allowed: false,
          status: PersistentArtifactCloudOperationStatus.stagingBlocked,
          reasonCode: 'cloud-production-blocked',
          message: 'Production cloud operation is blocked by policy',
          classification: classification,
        );
    }
  }
}
