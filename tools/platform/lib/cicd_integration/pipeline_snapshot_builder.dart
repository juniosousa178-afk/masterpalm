import '../models/cicd_integration/pipeline_models.dart';
import 'cicd_integration_canonical_serializer.dart';
import 'cicd_integration_collector.dart';
import 'resolved_cicd_integration_sources.dart';

/// Builds [PipelineDefinition] snapshots from collected artifacts without mutation.
class PipelineSnapshotBuilder {
  const PipelineSnapshotBuilder({
    CicdIntegrationCanonicalSerializer? serializer,
  }) : _serializer = serializer ?? const CicdIntegrationCanonicalSerializer();

  final CicdIntegrationCanonicalSerializer _serializer;

  PipelineDefinition? build({
    required CicdIntegrationEvaluationContext context,
    required CicdIntegrationCollectedArtifacts collected,
    required String evaluatedAt,
  }) {
    final definition = collected.pipelineDefinition;
    if (definition == null) return null;

    final fingerprint = definition.fingerprint ??
        _serializer.pipelineDefinitionFingerprint(definition);

    return PipelineDefinition(
      definitionId: definition.definitionId,
      name: definition.name,
      version: definition.version,
      stages: List.unmodifiable(definition.stages),
      triggers: List.unmodifiable(definition.triggers),
      environments: List.unmodifiable(definition.environments),
      artifacts: List.unmodifiable(definition.artifacts),
      fingerprint: fingerprint,
      metadata: Map.unmodifiable(definition.metadata),
      schemaVersion: definition.schemaVersion,
      canonicalizationVersion: definition.canonicalizationVersion,
    );
  }
}
