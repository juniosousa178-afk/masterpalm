import '../../models/cicd_integration/cicd_integration_operational_enums.dart';
import '../../models/cicd_integration/cicd_integration_policy_models.dart';
import '../../models/cicd_integration/pipeline_enums.dart';

/// Candidate pipeline integration policy v1.
class PipelineIntegrationPolicyV1 {
  const PipelineIntegrationPolicyV1._();

  static const policyId = 'pipeline-integration-v1';

  static RegisteredPipelineIntegrationPolicy create() {
    return RegisteredPipelineIntegrationPolicy(
      metadata: const RegisteredPipelineIntegrationPolicyMetadata(
        policyId: policyId,
        policyVersion: 1,
        displayName: 'Default Pipeline Integration Policy',
        status: CicdIntegrationPolicyStatus.candidate,
        limitations: [
          'no-pipeline-execution',
          'no-remote-provider-fetch',
          'structural-assembly-only',
        ],
      ),
      policy: PipelineIntegrationPolicy(
        policyId: policyId,
        policyVersion: 1,
        name: 'Default Pipeline Integration Policy',
        requiredStageTypes: [
          PipelineStageType.sequential,
          PipelineStageType.gate,
          PipelineStageType.deployment,
        ],
        limitations: const [
          'no-pipeline-execution',
          'no-remote-provider-fetch',
        ],
      ),
    );
  }
}
