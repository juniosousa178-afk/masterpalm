import 'dart:convert';

import '../../models/history/history_artifact.dart';
import '../../models/history/history_artifact_payload.dart';
import '../../models/history/history_artifact_type.dart';
import '../../models/history/history_change_type.dart';
import '../../models/history/history_diff.dart';
import '../../models/release_supply_chain/release_supply_chain_enums.dart';
import '../../models/release_supply_chain/release_supply_chain_snapshot.dart';
import '../history_canonical_serializer.dart';

/// Maps [ReleaseSupplyChainSnapshot] to history artifacts and comparable fields.
///
/// History remains responsible for diff; this mapper does not execute RSC.
class ReleaseSupplyChainHistoryMapper {
  const ReleaseSupplyChainHistoryMapper(
      {HistoryCanonicalSerializer? serializer})
      : _serializer = serializer ?? const HistoryCanonicalSerializer();

  final HistoryCanonicalSerializer _serializer;

  HistoryArtifact fromMap(Map<String, dynamic> json) {
    final snapshot = ReleaseSupplyChainSnapshot.fromJson(json);
    final comparable = snapshot.toComparableJson();
    final fingerprint = _serializer.fingerprintFromString(
      jsonEncode(comparable),
    );
    return HistoryArtifact(
      artifactType: HistoryArtifactType.releaseSupplyChain,
      artifactId: snapshot.metadata.supplyChainSnapshotId,
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
    ReleaseSupplyChainSnapshot? from,
    ReleaseSupplyChainSnapshot? to,
  ) {
    if (from == null || to == null) return const [];
    final changes = <HistoryChange>[];

    final fromMeta = from.metadata;
    final toMeta = to.metadata;

    if (fromMeta.supplyChainPolicyId != toMeta.supplyChainPolicyId ||
        fromMeta.supplyChainPolicyVersion != toMeta.supplyChainPolicyVersion) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactChanged,
          category: HistoryChangeCategory.artifact,
          subjectId: 'supplyChainPolicy',
          previousValue:
              '${fromMeta.supplyChainPolicyId}@${fromMeta.supplyChainPolicyVersion}',
          currentValue:
              '${toMeta.supplyChainPolicyId}@${toMeta.supplyChainPolicyVersion}',
        ),
      );
    }
    if (fromMeta.distributionPolicyId != toMeta.distributionPolicyId ||
        fromMeta.distributionPolicyVersion !=
            toMeta.distributionPolicyVersion) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactChanged,
          category: HistoryChangeCategory.artifact,
          subjectId: 'distributionPolicy',
          previousValue:
              '${fromMeta.distributionPolicyId}@${fromMeta.distributionPolicyVersion}',
          currentValue:
              '${toMeta.distributionPolicyId}@${toMeta.distributionPolicyVersion}',
        ),
      );
    }
    if (fromMeta.compliancePolicyId != toMeta.compliancePolicyId ||
        fromMeta.compliancePolicyVersion != toMeta.compliancePolicyVersion) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactChanged,
          category: HistoryChangeCategory.artifact,
          subjectId: 'compliancePolicy',
          previousValue:
              '${fromMeta.compliancePolicyId}@${fromMeta.compliancePolicyVersion}',
          currentValue:
              '${toMeta.compliancePolicyId}@${toMeta.compliancePolicyVersion}',
        ),
      );
    }
    if (fromMeta.releaseId != toMeta.releaseId ||
        fromMeta.commitId != toMeta.commitId) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactChanged,
          category: HistoryChangeCategory.artifact,
          subjectId: 'releaseContext',
          previousValue: '${fromMeta.releaseId}@${fromMeta.commitId}',
          currentValue: '${toMeta.releaseId}@${toMeta.commitId}',
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
    if (from.supplyChain?.status != to.supplyChain?.status) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactChanged,
          category: HistoryChangeCategory.artifact,
          subjectId: 'supplyChainStatus',
          previousValue: from.supplyChain?.status.wireName,
          currentValue: to.supplyChain?.status.wireName,
        ),
      );
    }
    if (from.sbom?.metadata.status != to.sbom?.metadata.status) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactChanged,
          category: HistoryChangeCategory.artifact,
          subjectId: 'sbomStatus',
          previousValue: from.sbom?.metadata.status.wireName,
          currentValue: to.sbom?.metadata.status.wireName,
        ),
      );
    }
    if (from.compliance?.status != to.compliance?.status) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactChanged,
          category: HistoryChangeCategory.artifact,
          subjectId: 'complianceStatus',
          previousValue: from.compliance?.status.wireName,
          currentValue: to.compliance?.status.wireName,
        ),
      );
    }

    _diffIds(
      from.artifacts.map((a) => a.metadata.recordId).toList(),
      to.artifacts.map((a) => a.metadata.recordId).toList(),
      'artifact',
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
