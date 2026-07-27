import '../models/cicd_integration/pipeline_models.dart';
import 'cicd_integration_canonical_serializer.dart';
import 'cicd_integration_collector.dart';
import 'resolved_cicd_integration_sources.dart';

/// Result of building pipeline execution artifacts.
class PipelineExecutionBuildResult {
  const PipelineExecutionBuildResult({
    this.execution,
    this.result,
  });

  final PipelineExecution? execution;
  final PipelineExecutionResult? result;
}

/// Builds [PipelineExecution] and [PipelineExecutionResult] without mutation.
class PipelineExecutionBuilder {
  const PipelineExecutionBuilder({
    CicdIntegrationCanonicalSerializer? serializer,
  }) : _serializer = serializer ?? const CicdIntegrationCanonicalSerializer();

  final CicdIntegrationCanonicalSerializer _serializer;

  PipelineExecutionBuildResult build({
    required CicdIntegrationEvaluationContext context,
    required CicdIntegrationCollectedArtifacts collected,
    required String evaluatedAt,
  }) {
    final execution = collected.pipelineExecution;
    final standaloneResult = collected.pipelineExecutionResult;

    PipelineExecution? builtExecution;
    if (execution != null) {
      final fingerprint = execution.fingerprint ??
          _serializer.pipelineExecutionFingerprint(execution);
      builtExecution = PipelineExecution(
        executionId: execution.executionId,
        definitionId: execution.definitionId,
        definitionVersion: execution.definitionVersion,
        definitionFingerprint: execution.definitionFingerprint,
        triggerId: execution.triggerId,
        environmentId: execution.environmentId,
        status: execution.status,
        startedAt: execution.startedAt,
        completedAt: execution.completedAt,
        result: execution.result,
        artifacts: List.unmodifiable(execution.artifacts),
        fingerprint: fingerprint,
        metadata: Map.unmodifiable(execution.metadata),
        schemaVersion: execution.schemaVersion,
      );
    }

    PipelineExecutionResult? builtResult;
    final embeddedResult = execution?.result;
    if (standaloneResult != null) {
      final fingerprint = standaloneResult.fingerprint ??
          _serializer.pipelineExecutionResultFingerprint(standaloneResult);
      builtResult = PipelineExecutionResult(
        resultId: standaloneResult.resultId,
        outcome: standaloneResult.outcome,
        status: standaloneResult.status,
        summary: standaloneResult.summary,
        artifactIds: List.unmodifiable(standaloneResult.artifactIds),
        metrics: Map.unmodifiable(standaloneResult.metrics),
        fingerprint: fingerprint,
        completedAt: standaloneResult.completedAt,
      );
    } else if (embeddedResult != null) {
      final fingerprint = embeddedResult.fingerprint ??
          _serializer.pipelineExecutionResultFingerprint(embeddedResult);
      builtResult = PipelineExecutionResult(
        resultId: embeddedResult.resultId,
        outcome: embeddedResult.outcome,
        status: embeddedResult.status,
        summary: embeddedResult.summary,
        artifactIds: List.unmodifiable(embeddedResult.artifactIds),
        metrics: Map.unmodifiable(embeddedResult.metrics),
        fingerprint: fingerprint,
        completedAt: embeddedResult.completedAt,
      );
    }

    return PipelineExecutionBuildResult(
      execution: builtExecution,
      result: builtResult,
    );
  }
}
