import '../../models/cicd_integration/cicd_integration_operational_enums.dart';
import '../../models/cicd_integration/cicd_integration_policy_models.dart';
import '../../models/cicd_integration/pipeline_enums.dart';

/// Candidate pipeline execution policy v1.
class PipelineExecutionPolicyV1 {
  const PipelineExecutionPolicyV1._();

  static const policyId = 'pipeline-execution-v1';

  static RegisteredPipelineExecutionPolicy create() {
    return RegisteredPipelineExecutionPolicy(
      metadata: const RegisteredPipelineExecutionPolicyMetadata(
        policyId: policyId,
        policyVersion: 1,
        displayName: 'Default Pipeline Execution Policy',
        status: CicdIntegrationPolicyStatus.candidate,
        limitations: [
          'no-pipeline-execution',
          'structural-validation-only',
        ],
      ),
      policy: PipelineExecutionPolicy(
        policyId: policyId,
        policyVersion: 1,
        name: 'Default Pipeline Execution Policy',
        requiredTerminalOutcomes: [
          PipelineExecutionOutcome.success,
          PipelineExecutionOutcome.partial,
        ],
        limitations: const [
          'no-pipeline-execution',
        ],
      ),
    );
  }
}
