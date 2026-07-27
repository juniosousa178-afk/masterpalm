import 'dart:convert';

import '../../models/cicd_integration/cicd_integration_operational_enums.dart';

import '../../models/cicd_integration/cicd_integration_snapshot.dart';

import '../../models/cicd_integration/pipeline_enums.dart';

import '../../models/history/history_artifact.dart';

import '../../models/history/history_artifact_payload.dart';

import '../../models/history/history_artifact_type.dart';

import '../../models/history/history_change_type.dart';

import '../../models/history/history_diff.dart';

import '../history_canonical_serializer.dart';

/// Maps [CicdIntegrationSnapshot] to history artifacts and comparable fields.

///

/// History remains responsible for diff; this mapper does not execute CI/CD.

class CicdIntegrationHistoryMapper {
  const CicdIntegrationHistoryMapper({HistoryCanonicalSerializer? serializer})
      : _serializer = serializer ?? const HistoryCanonicalSerializer();

  final HistoryCanonicalSerializer _serializer;

  HistoryArtifact fromMap(Map<String, dynamic> json) {
    final snapshot = CicdIntegrationSnapshot.fromJson(json);

    final comparable = snapshot.toComparableJson();

    final fingerprint = _serializer.fingerprintFromString(
      jsonEncode(comparable),
    );

    return HistoryArtifact(
      artifactType: HistoryArtifactType.cicdIntegration,
      artifactId: snapshot.metadata.cicdIntegrationSnapshotId,
      schemaVersion: snapshot.metadata.schemaVersion,
      canonicalizationVersion: snapshot.metadata.canonicalizationVersion,
      fingerprint: fingerprint,
      payload: HistoryArtifactPayload(
        encoding: HistoryArtifactPayload.jsonEncoding,
        data: snapshot.toJson(),
      ),
    );
  }

  List<HistoryChange> compare(
    CicdIntegrationSnapshot? from,
    CicdIntegrationSnapshot? to,
  ) {
    if (from == null || to == null) return const [];

    final changes = <HistoryChange>[];

    final fromMeta = from.metadata;

    final toMeta = to.metadata;

    if (fromMeta.pipelineIntegrationPolicyId !=
            toMeta.pipelineIntegrationPolicyId ||
        fromMeta.pipelineIntegrationPolicyVersion !=
            toMeta.pipelineIntegrationPolicyVersion) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactChanged,
          category: HistoryChangeCategory.artifact,
          subjectId: 'pipelineIntegrationPolicy',
          previousValue:
              '${fromMeta.pipelineIntegrationPolicyId}@${fromMeta.pipelineIntegrationPolicyVersion}',
          currentValue:
              '${toMeta.pipelineIntegrationPolicyId}@${toMeta.pipelineIntegrationPolicyVersion}',
        ),
      );
    }

    if (fromMeta.pipelineExecutionPolicyId !=
            toMeta.pipelineExecutionPolicyId ||
        fromMeta.pipelineExecutionPolicyVersion !=
            toMeta.pipelineExecutionPolicyVersion) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactChanged,
          category: HistoryChangeCategory.artifact,
          subjectId: 'pipelineExecutionPolicy',
          previousValue:
              '${fromMeta.pipelineExecutionPolicyId}@${fromMeta.pipelineExecutionPolicyVersion}',
          currentValue:
              '${toMeta.pipelineExecutionPolicyId}@${toMeta.pipelineExecutionPolicyVersion}',
        ),
      );
    }

    if (fromMeta.deploymentIntegrationPolicyId !=
            toMeta.deploymentIntegrationPolicyId ||
        fromMeta.deploymentIntegrationPolicyVersion !=
            toMeta.deploymentIntegrationPolicyVersion) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactChanged,
          category: HistoryChangeCategory.artifact,
          subjectId: 'deploymentIntegrationPolicy',
          previousValue:
              '${fromMeta.deploymentIntegrationPolicyId}@${fromMeta.deploymentIntegrationPolicyVersion}',
          currentValue:
              '${toMeta.deploymentIntegrationPolicyId}@${toMeta.deploymentIntegrationPolicyVersion}',
        ),
      );
    }

    if (fromMeta.releaseId != toMeta.releaseId ||
        fromMeta.pipelineDefinitionId != toMeta.pipelineDefinitionId ||
        fromMeta.pipelineExecutionId != toMeta.pipelineExecutionId) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactChanged,
          category: HistoryChangeCategory.artifact,
          subjectId: 'pipelineContext',
          previousValue:
              '${fromMeta.releaseId}@${fromMeta.pipelineDefinitionId}@${fromMeta.pipelineExecutionId}',
          currentValue:
              '${toMeta.releaseId}@${toMeta.pipelineDefinitionId}@${toMeta.pipelineExecutionId}',
        ),
      );
    }

    if (fromMeta.releaseEvidenceBundleId != toMeta.releaseEvidenceBundleId) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactChanged,
          category: HistoryChangeCategory.artifact,
          subjectId: 'releaseEvidenceReference',
          previousValue: fromMeta.releaseEvidenceBundleId,
          currentValue: toMeta.releaseEvidenceBundleId,
        ),
      );
    }

    if (fromMeta.releaseSupplyChainSnapshotId !=
        toMeta.releaseSupplyChainSnapshotId) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactChanged,
          category: HistoryChangeCategory.artifact,
          subjectId: 'releaseSupplyChainReference',
          previousValue: fromMeta.releaseSupplyChainSnapshotId,
          currentValue: toMeta.releaseSupplyChainSnapshotId,
        ),
      );
    }

    if (from.status != to.status) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactChanged,
          category: HistoryChangeCategory.artifact,
          subjectId: 'snapshotStatus',
          previousValue: from.status.wireName,
          currentValue: to.status.wireName,
        ),
      );
    }

    if (from.pipelineExecution?.status != to.pipelineExecution?.status) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactChanged,
          category: HistoryChangeCategory.artifact,
          subjectId: 'pipelineExecutionStatus',
          previousValue: from.pipelineExecution?.status.wireName,
          currentValue: to.pipelineExecution?.status.wireName,
        ),
      );
    }

    if (from.deploymentResult?.status != to.deploymentResult?.status) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactChanged,
          category: HistoryChangeCategory.artifact,
          subjectId: 'deploymentResultStatus',
          previousValue: from.deploymentResult?.status.wireName,
          currentValue: to.deploymentResult?.status.wireName,
        ),
      );
    }

    _diffIds(
      from.sourceReferences
          .map((r) => r.resolvedId ?? r.requestedId)
          .where((id) => id.isNotEmpty)
          .toList(),
      to.sourceReferences
          .map((r) => r.resolvedId ?? r.requestedId)
          .where((id) => id.isNotEmpty)
          .toList(),
      'sourceReference',
      changes,
    );

    final fromFp = fromMeta.fingerprint;

    final toFp = toMeta.fingerprint;

    if (fromFp != toFp) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactChanged,
          category: HistoryChangeCategory.artifact,
          subjectId: 'fingerprint',
          previousValue: fromFp,
          currentValue: toFp,
        ),
      );
    }

    return changes;
  }

  void _diffIds(
    List<String> fromIds,
    List<String> toIds,
    String subject,
    List<HistoryChange> changes,
  ) {
    final fromSet = fromIds.toSet();

    final toSet = toIds.toSet();

    for (final added in toSet.difference(fromSet)) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactAdded,
          category: HistoryChangeCategory.artifact,
          subjectId: '$subject:$added',
        ),
      );
    }

    for (final removed in fromSet.difference(toSet)) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactRemoved,
          category: HistoryChangeCategory.artifact,
          subjectId: '$subject:$removed',
        ),
      );
    }
  }
}
