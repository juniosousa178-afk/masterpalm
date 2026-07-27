import 'persistent_artifact_cloud_capability.dart';
import 'persistent_artifact_cloud_environment_gate.dart';
import 'persistent_artifact_cloud_operation_models.dart';
import 'persistent_artifact_cloud_operation_status.dart';

class PersistentArtifactCloudBackendPolicyEvaluator {
  const PersistentArtifactCloudBackendPolicyEvaluator({
    this.environmentGate = const PersistentArtifactCloudEnvironmentGate(),
  });

  final PersistentArtifactCloudEnvironmentGate environmentGate;

  PersistentArtifactCloudExecutionPlan evaluate({
    required PersistentArtifactCloudOperationContext context,
    required Set<PersistentArtifactCloudCapability> capabilities,
  }) {
    final environmentDecision = environmentGate.evaluate(
      backendId: context.backendId,
      runtimeEnvironment: context.runtimeEnvironment,
      classification: context.classification,
    );

    final capabilityAllowed = capabilities.contains(context.capability);
    final capabilityDecision = PersistentArtifactCloudCapabilityDecision(
      backendId: context.backendId,
      capability: context.capability,
      allowed: capabilityAllowed,
      status: capabilityAllowed
          ? PersistentArtifactCloudOperationStatus.success
          : PersistentArtifactCloudOperationStatus.unsupported,
      reasonCode: capabilityAllowed ? null : 'cloud-capability-not-supported',
      messages: capabilityAllowed
          ? const []
          : const [
              PersistentArtifactCloudExecutionMessage(
                code: 'cloud-capability-not-supported',
                message:
                    'Operation capability is not provided by backend bridge',
                severity: 'warning',
              ),
            ],
    );

    final backendResolution = PersistentArtifactCloudBackendResolution(
      backendId: context.backendId,
      resolved: true,
      status: PersistentArtifactCloudOperationStatus.success,
      classification: context.classification,
    );

    final bridgeCallAllowed = environmentDecision.allowed && capabilityAllowed;
    return PersistentArtifactCloudExecutionPlan(
      context: context,
      environmentDecision: environmentDecision,
      capabilityDecision: capabilityDecision,
      backendResolution: backendResolution,
      bridgeCallAllowed: bridgeCallAllowed,
      messages: [
        if (!environmentDecision.allowed)
          PersistentArtifactCloudExecutionMessage(
            code: environmentDecision.reasonCode ?? 'cloud-env-blocked',
            message: environmentDecision.message ?? 'Cloud environment blocked',
            severity: 'warning',
          ),
        ...capabilityDecision.messages,
      ],
    );
  }
}
