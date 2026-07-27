import '../models/cicd_integration/deployment_models.dart';
import '../models/cicd_integration/pipeline_models.dart';

/// In-memory registry for CI/CD integration source artifacts.
class CicdIntegrationArtifactRegistry {
  final Map<String, PipelineDefinition> _definitions = {};
  final Map<String, PipelineExecution> _executions = {};
  final Map<String, PipelineExecutionResult> _executionResults = {};
  final Map<String, DeploymentPlan> _deploymentPlans = {};
  final Map<String, DeploymentResult> _deploymentResults = {};

  void registerDefinition(PipelineDefinition definition) {
    _definitions[definition.definitionId] = definition;
  }

  PipelineDefinition? loadDefinition(String definitionId) {
    return _definitions[definitionId];
  }

  PipelineDefinition? latestDefinition({required String projectId}) {
    final matches = _definitions.values
        .where((d) => d.metadata['projectId'] == projectId)
        .toList()
      ..sort((a, b) {
        final versionCmp = b.version.compareTo(a.version);
        if (versionCmp != 0) return versionCmp;
        return a.definitionId.compareTo(b.definitionId);
      });
    return matches.isEmpty ? null : matches.first;
  }

  void registerExecution(PipelineExecution execution) {
    _executions[execution.executionId] = execution;
  }

  PipelineExecution? loadExecution(String executionId) {
    return _executions[executionId];
  }

  PipelineExecution? latestExecution({required String projectId}) {
    final matches = _executions.values
        .where((e) => e.metadata['projectId'] == projectId)
        .toList()
      ..sort((a, b) {
        final startedCmp = b.startedAt.compareTo(a.startedAt);
        if (startedCmp != 0) return startedCmp;
        return a.executionId.compareTo(b.executionId);
      });
    return matches.isEmpty ? null : matches.first;
  }

  void registerExecutionResult(PipelineExecutionResult result) {
    _executionResults[result.resultId] = result;
  }

  PipelineExecutionResult? loadExecutionResult(String resultId) {
    return _executionResults[resultId];
  }

  PipelineExecutionResult? latestExecutionResult({required String projectId}) {
    final matches = _executionResults.values
        .where((r) => r.metrics['projectId'] == projectId)
        .toList()
      ..sort((a, b) {
        final completedCmp =
            (b.completedAt ?? '').compareTo(a.completedAt ?? '');
        if (completedCmp != 0) return completedCmp;
        return a.resultId.compareTo(b.resultId);
      });
    return matches.isEmpty ? null : matches.first;
  }

  void registerDeploymentPlan(DeploymentPlan plan) {
    _deploymentPlans[plan.planId] = plan;
  }

  DeploymentPlan? loadDeploymentPlan(String planId) {
    return _deploymentPlans[planId];
  }

  DeploymentPlan? latestDeploymentPlan({required String projectId}) {
    final matches = _deploymentPlans.values
        .where((p) => p.metadata['projectId'] == projectId)
        .toList()
      ..sort((a, b) => a.planId.compareTo(b.planId));
    return matches.isEmpty ? null : matches.last;
  }

  void registerDeploymentResult(DeploymentResult result) {
    _deploymentResults[result.resultId] = result;
  }

  DeploymentResult? loadDeploymentResult(String resultId) {
    return _deploymentResults[resultId];
  }

  DeploymentResult? latestDeploymentResult({required String projectId}) {
    final matches = _deploymentResults.values
        .where((r) => r.metadata['projectId'] == projectId)
        .toList()
      ..sort((a, b) {
        final startedCmp = b.startedAt.compareTo(a.startedAt);
        if (startedCmp != 0) return startedCmp;
        return a.resultId.compareTo(b.resultId);
      });
    return matches.isEmpty ? null : matches.first;
  }

  void clear() {
    _definitions.clear();
    _executions.clear();
    _executionResults.clear();
    _deploymentPlans.clear();
    _deploymentResults.clear();
  }
}
