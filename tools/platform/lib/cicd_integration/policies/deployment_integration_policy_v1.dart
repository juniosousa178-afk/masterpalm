import '../../models/cicd_integration/cicd_integration_operational_enums.dart';
import '../../models/cicd_integration/cicd_integration_policy_models.dart';
import '../../models/cicd_integration/pipeline_enums.dart';

/// Candidate deployment integration policy v1.
class DeploymentIntegrationPolicyV1 {
  const DeploymentIntegrationPolicyV1._();

  static const policyId = 'deployment-integration-v1';

  static RegisteredDeploymentIntegrationPolicy create() {
    return RegisteredDeploymentIntegrationPolicy(
      metadata: const RegisteredDeploymentIntegrationPolicyMetadata(
        policyId: policyId,
        policyVersion: 1,
        displayName: 'Default Deployment Integration Policy',
        status: CicdIntegrationPolicyStatus.candidate,
        limitations: [
          'no-pipeline-execution',
          'no-remote-deployment',
          'structural-plan-only',
        ],
      ),
      policy: DeploymentIntegrationPolicy(
        policyId: policyId,
        policyVersion: 1,
        name: 'Default Deployment Integration Policy',
        allowedStrategies: [
          DeploymentStrategy.rolling,
          DeploymentStrategy.blueGreen,
          DeploymentStrategy.canary,
        ],
        limitations: const [
          'no-pipeline-execution',
          'no-remote-deployment',
        ],
      ),
    );
  }
}
