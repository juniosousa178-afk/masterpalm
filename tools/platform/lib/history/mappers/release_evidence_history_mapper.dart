import 'dart:convert';

import '../../models/history/history_artifact.dart';
import '../../models/history/history_artifact_payload.dart';
import '../../models/history/history_artifact_type.dart';
import '../../models/history/history_change_type.dart';
import '../../models/history/history_diff.dart';
import '../../models/release_evidence/release_evidence_bundle.dart';
import '../../models/release_evidence/release_evidence_enums.dart';
import '../history_canonical_serializer.dart';

/// Maps [ReleaseEvidenceBundle] to history artifacts and comparable fields.
///
/// History remains responsible for diff; this mapper does not execute RE.
class ReleaseEvidenceHistoryMapper {
  const ReleaseEvidenceHistoryMapper({HistoryCanonicalSerializer? serializer})
      : _serializer = serializer ?? const HistoryCanonicalSerializer();

  final HistoryCanonicalSerializer _serializer;

  HistoryArtifact fromMap(Map<String, dynamic> json) {
    final bundle = ReleaseEvidenceBundle.fromJson(json);
    final comparable = _comparableJson(bundle);
    final fingerprint = _serializer.fingerprintFromString(
      jsonEncode(comparable),
    );
    return HistoryArtifact(
      artifactType: HistoryArtifactType.releaseEvidence,
      artifactId: bundle.metadata.bundleId,
      schemaVersion: bundle.metadata.schemaVersion,
      canonicalizationVersion: bundle.metadata.canonicalizationVersion,
      calculationVersion: bundle.metadata.calculationVersion,
      fingerprint: fingerprint,
      payload: HistoryArtifactPayload(
        encoding: HistoryArtifactPayload.jsonEncoding,
        data: bundle.toJson(),
      ),
    );
  }

  List<HistoryChange> compare(
    ReleaseEvidenceBundle? from,
    ReleaseEvidenceBundle? to,
  ) {
    if (from == null || to == null) return const [];
    final changes = <HistoryChange>[];

    if (from.metadata.policyVersion != to.metadata.policyVersion ||
        from.metadata.policyId != to.metadata.policyId) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactChanged,
          category: HistoryChangeCategory.artifact,
          subjectId: 'policy',
          previousValue:
              '${from.metadata.policyId}@${from.metadata.policyVersion}',
          currentValue: '${to.metadata.policyId}@${to.metadata.policyVersion}',
        ),
      );
    }
    if (from.metadata.commitId != to.metadata.commitId ||
        from.metadata.releaseId != to.metadata.releaseId) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactChanged,
          category: HistoryChangeCategory.artifact,
          subjectId: 'releaseContext',
          previousValue: '${from.metadata.releaseId}@${from.metadata.commitId}',
          currentValue: '${to.metadata.releaseId}@${to.metadata.commitId}',
        ),
      );
    }
    if (from.qualityGateReference.qualityGateSnapshotId !=
        to.qualityGateReference.qualityGateSnapshotId) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactChanged,
          category: HistoryChangeCategory.artifact,
          subjectId: 'qualityGateReference',
          previousValue: from.qualityGateReference.qualityGateSnapshotId,
          currentValue: to.qualityGateReference.qualityGateSnapshotId,
        ),
      );
    }
    if (from.releaseDecisionReference.releaseDecisionSnapshotId !=
        to.releaseDecisionReference.releaseDecisionSnapshotId) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactChanged,
          category: HistoryChangeCategory.artifact,
          subjectId: 'releaseDecisionReference',
          previousValue:
              from.releaseDecisionReference.releaseDecisionSnapshotId,
          currentValue: to.releaseDecisionReference.releaseDecisionSnapshotId,
        ),
      );
    }
    if (from.coverage.evidenceCoveragePercentage !=
        to.coverage.evidenceCoveragePercentage) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.metricValueChanged,
          category: HistoryChangeCategory.metrics,
          subjectId: 'evidenceCoverage',
          previousValue: from.coverage.evidenceCoveragePercentage.toString(),
          currentValue: to.coverage.evidenceCoveragePercentage.toString(),
        ),
      );
    }
    if (from.compatibility.status != to.compatibility.status) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactChanged,
          category: HistoryChangeCategory.artifact,
          subjectId: 'compatibility',
          previousValue: from.compatibility.status.wireName,
          currentValue: to.compatibility.status.wireName,
        ),
      );
    }
    if (from.eligibility.status != to.eligibility.status) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactChanged,
          category: HistoryChangeCategory.artifact,
          subjectId: 'eligibility',
          previousValue: from.eligibility.status.wireName,
          currentValue: to.eligibility.status.wireName,
        ),
      );
    }

    _diffIds(
      from.evidence.map((e) => e.artifactReference.artifactId).toList(),
      to.evidence.map((e) => e.artifactReference.artifactId).toList(),
      'evidence',
      changes,
    );
    _diffIds(
      from.attestations.map((a) => a.metadata.attestationId).toList(),
      to.attestations.map((a) => a.metadata.attestationId).toList(),
      'attestation',
      changes,
    );

    final fromSourceFp = from.metadata.sourceSetFingerprint;
    final toSourceFp = to.metadata.sourceSetFingerprint;
    if (fromSourceFp != toSourceFp) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactChanged,
          category: HistoryChangeCategory.artifact,
          subjectId: 'sourceFingerprint',
          previousValue: fromSourceFp,
          currentValue: toSourceFp,
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

  Map<String, dynamic> _comparableJson(ReleaseEvidenceBundle bundle) {
    final json = bundle.toJson();
    final metadata = Map<String, dynamic>.from(json['metadata'] as Map);
    metadata.remove('bundleId');
    metadata.remove('createdAt');
    metadata.remove('evaluatedAt');
    json['metadata'] = metadata;
    json.remove('fingerprint');
    return json;
  }
}
