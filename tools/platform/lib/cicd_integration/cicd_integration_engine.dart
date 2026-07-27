import '../models/cicd_integration/cicd_integration_messages.dart';
import '../models/cicd_integration/cicd_integration_operational_enums.dart';
import '../models/cicd_integration/deployment_models.dart';
import '../models/cicd_integration/pipeline_enums.dart';
import '../models/cicd_integration/pipeline_models.dart';
import 'cicd_integration_collector.dart';
import 'resolved_cicd_integration_sources.dart';

/// Structural consistency checks for CI/CD integration — never executes pipelines.
class CicdIntegrationEngine {
  const CicdIntegrationEngine();

  List<CicdIntegrationMessage> evaluate({
    required CicdIntegrationEvaluationContext context,
    required CicdIntegrationCollectedArtifacts collected,
    PipelineDefinition? pipelineDefinition,
    PipelineExecution? pipelineExecution,
    PipelineExecutionResult? pipelineExecutionResult,
    DeploymentPlan? deploymentPlan,
    DeploymentResult? deploymentResult,
  }) {
    final messages = <CicdIntegrationMessage>[];
    final integrationPolicy = context.pipelineIntegrationPolicy.policy;
    final executionPolicy = context.pipelineExecutionPolicy.policy;
    final deploymentPolicy = context.deploymentIntegrationPolicy.policy;

    if (pipelineDefinition != null) {
      final stageTypes =
          pipelineDefinition.stages.map((s) => s.stageType).toSet();
      for (final required in integrationPolicy.requiredStageTypes) {
        if (!stageTypes.contains(required)) {
          messages.add(
            CicdIntegrationMessage(
              messageId: 'msg-missing-stage-${required.wireName}',
              code: 'CICD_STRUCT_MISSING_STAGE',
              message: 'Required stage type missing: ${required.wireName}',
              severity: CicdIntegrationMessageSeverity.warning,
              operation: CicdIntegrationOperation.validate,
              sourceType: CicdIntegrationSourceType.pipelineDefinition,
              metadata: {
                'definitionId': pipelineDefinition.definitionId,
                'stageType': required.wireName,
              },
            ),
          );
        }
      }
      if (integrationPolicy.requireDefinitionFingerprint &&
          (pipelineDefinition.fingerprint == null ||
              pipelineDefinition.fingerprint!.isEmpty)) {
        messages.add(
          CicdIntegrationMessage(
            messageId: 'msg-missing-definition-fingerprint',
            code: 'CICD_STRUCT_MISSING_DEFINITION_FP',
            message: 'Pipeline definition fingerprint is required by policy',
            severity: CicdIntegrationMessageSeverity.error,
            operation: CicdIntegrationOperation.validate,
            sourceType: CicdIntegrationSourceType.pipelineDefinition,
            metadata: {'definitionId': pipelineDefinition.definitionId},
          ),
        );
      }
    } else {
      messages.add(
        const CicdIntegrationMessage(
          messageId: 'msg-missing-definition',
          code: 'CICD_STRUCT_MISSING_DEFINITION',
          message: 'Pipeline definition unavailable for structural checks',
          severity: CicdIntegrationMessageSeverity.warning,
          operation: CicdIntegrationOperation.validate,
          sourceType: CicdIntegrationSourceType.pipelineDefinition,
        ),
      );
    }

    if (pipelineExecution != null && pipelineDefinition != null) {
      if (pipelineExecution.definitionId != pipelineDefinition.definitionId) {
        messages.add(
          CicdIntegrationMessage(
            messageId: 'msg-execution-definition-mismatch',
            code: 'CICD_STRUCT_EXECUTION_DEFINITION',
            message: 'Execution definitionId ${pipelineExecution.definitionId} '
                'does not match ${pipelineDefinition.definitionId}',
            severity: CicdIntegrationMessageSeverity.error,
            operation: CicdIntegrationOperation.validate,
            sourceType: CicdIntegrationSourceType.pipelineExecution,
            metadata: {
              'executionId': pipelineExecution.executionId,
              'definitionId': pipelineExecution.definitionId,
            },
          ),
        );
      }
      if (executionPolicy.requireExecutionFingerprint &&
          (pipelineExecution.fingerprint == null ||
              pipelineExecution.fingerprint!.isEmpty)) {
        messages.add(
          CicdIntegrationMessage(
            messageId: 'msg-missing-execution-fingerprint',
            code: 'CICD_STRUCT_MISSING_EXECUTION_FP',
            message: 'Pipeline execution fingerprint is required by policy',
            severity: CicdIntegrationMessageSeverity.error,
            operation: CicdIntegrationOperation.validate,
            sourceType: CicdIntegrationSourceType.pipelineExecution,
            metadata: {'executionId': pipelineExecution.executionId},
          ),
        );
      }
    }

    if (pipelineExecutionResult != null) {
      if (!executionPolicy.requiredTerminalOutcomes
          .contains(pipelineExecutionResult.outcome)) {
        messages.add(
          CicdIntegrationMessage(
            messageId: 'msg-unexpected-outcome',
            code: 'CICD_STRUCT_UNEXPECTED_OUTCOME',
            message:
                'Execution outcome ${pipelineExecutionResult.outcome.wireName} '
                'not in policy required outcomes',
            severity: CicdIntegrationMessageSeverity.warning,
            operation: CicdIntegrationOperation.validate,
            sourceType: CicdIntegrationSourceType.pipelineExecutionResult,
            metadata: {'resultId': pipelineExecutionResult.resultId},
          ),
        );
      }
      if (executionPolicy.requireResultFingerprint &&
          (pipelineExecutionResult.fingerprint == null ||
              pipelineExecutionResult.fingerprint!.isEmpty)) {
        messages.add(
          CicdIntegrationMessage(
            messageId: 'msg-missing-result-fingerprint',
            code: 'CICD_STRUCT_MISSING_RESULT_FP',
            message:
                'Pipeline execution result fingerprint is required by policy',
            severity: CicdIntegrationMessageSeverity.error,
            operation: CicdIntegrationOperation.validate,
            sourceType: CicdIntegrationSourceType.pipelineExecutionResult,
            metadata: {'resultId': pipelineExecutionResult.resultId},
          ),
        );
      }
    }

    if (deploymentPlan != null) {
      if (!deploymentPolicy.allowedStrategies
          .contains(deploymentPlan.strategy)) {
        messages.add(
          CicdIntegrationMessage(
            messageId: 'msg-disallowed-strategy',
            code: 'CICD_STRUCT_DISALLOWED_STRATEGY',
            message: 'Deployment strategy ${deploymentPlan.strategy.wireName} '
                'not allowed by policy',
            severity: CicdIntegrationMessageSeverity.error,
            operation: CicdIntegrationOperation.validate,
            sourceType: CicdIntegrationSourceType.deploymentPlan,
            metadata: {'planId': deploymentPlan.planId},
          ),
        );
      }
      if (deploymentPolicy.requireDeploymentFingerprint &&
          (deploymentPlan.fingerprint == null ||
              deploymentPlan.fingerprint!.isEmpty)) {
        messages.add(
          CicdIntegrationMessage(
            messageId: 'msg-missing-plan-fingerprint',
            code: 'CICD_STRUCT_MISSING_PLAN_FP',
            message: 'Deployment plan fingerprint is required by policy',
            severity: CicdIntegrationMessageSeverity.error,
            operation: CicdIntegrationOperation.validate,
            sourceType: CicdIntegrationSourceType.deploymentPlan,
            metadata: {'planId': deploymentPlan.planId},
          ),
        );
      }
      if (pipelineExecution != null &&
          deploymentPlan.pipelineExecutionId != null &&
          deploymentPlan.pipelineExecutionId != pipelineExecution.executionId) {
        messages.add(
          CicdIntegrationMessage(
            messageId: 'msg-plan-execution-mismatch',
            code: 'CICD_STRUCT_PLAN_EXECUTION',
            message: 'Deployment plan pipelineExecutionId '
                '${deploymentPlan.pipelineExecutionId} '
                'does not match ${pipelineExecution.executionId}',
            severity: CicdIntegrationMessageSeverity.error,
            operation: CicdIntegrationOperation.validate,
            sourceType: CicdIntegrationSourceType.deploymentPlan,
            metadata: {'planId': deploymentPlan.planId},
          ),
        );
      }
    }

    if (deploymentResult != null && deploymentPlan != null) {
      if (deploymentResult.planId != deploymentPlan.planId) {
        messages.add(
          CicdIntegrationMessage(
            messageId: 'msg-result-plan-mismatch',
            code: 'CICD_STRUCT_RESULT_PLAN',
            message: 'Deployment result planId ${deploymentResult.planId} '
                'does not match ${deploymentPlan.planId}',
            severity: CicdIntegrationMessageSeverity.error,
            operation: CicdIntegrationOperation.validate,
            sourceType: CicdIntegrationSourceType.deploymentResult,
            metadata: {'resultId': deploymentResult.resultId},
          ),
        );
      }
    }

    if (collected.releaseEvidenceBundle == null) {
      messages.add(
        const CicdIntegrationMessage(
          messageId: 'msg-missing-evidence-link',
          code: 'CICD_STRUCT_MISSING_EVIDENCE',
          message: 'Release evidence bundle unavailable for linkage checks',
          severity: CicdIntegrationMessageSeverity.info,
          operation: CicdIntegrationOperation.validate,
          sourceType: CicdIntegrationSourceType.releaseEvidenceBundle,
        ),
      );
    }

    messages.sort((a, b) => a.messageId.compareTo(b.messageId));
    return messages;
  }
}
