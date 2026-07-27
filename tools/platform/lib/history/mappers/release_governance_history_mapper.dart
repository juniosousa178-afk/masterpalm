import 'dart:convert';

import '../../models/history/history_artifact.dart';
import '../../models/history/history_artifact_payload.dart';
import '../../models/history/history_artifact_type.dart';
import '../../models/history/history_change_type.dart';
import '../../models/history/history_diff.dart';
import '../../models/release_governance/release_decision_snapshot.dart';
import '../../models/release_governance/release_governance_enums.dart';
import '../history_canonical_serializer.dart';

/// Maps [ReleaseDecisionSnapshot] to history artifacts and comparable fields.
///
/// History remains responsible for diff; this mapper does not execute RG.
class ReleaseGovernanceHistoryMapper {
  const ReleaseGovernanceHistoryMapper({HistoryCanonicalSerializer? serializer})
      : _serializer = serializer ?? const HistoryCanonicalSerializer();

  final HistoryCanonicalSerializer _serializer;

  HistoryArtifact fromMap(Map<String, dynamic> json) {
    final snapshot = ReleaseDecisionSnapshot.fromJson(json);
    final comparable = _comparableJson(snapshot);
    final fingerprint = _serializer.fingerprintFromString(
      jsonEncode(comparable),
    );
    return HistoryArtifact(
      artifactType: HistoryArtifactType.releaseGovernance,
      artifactId: snapshot.metadata.snapshotId,
      schemaVersion: snapshot.metadata.schemaVersion,
      canonicalizationVersion: snapshot.metadata.canonicalizationVersion,
      calculationVersion: snapshot.metadata.calculationVersion,
      fingerprint: fingerprint,
      payload: HistoryArtifactPayload(
        encoding: HistoryArtifactPayload.jsonEncoding,
        data: snapshot.toJson(),
      ),
    );
  }

  List<HistoryChange> compare(
    ReleaseDecisionSnapshot? from,
    ReleaseDecisionSnapshot? to,
  ) {
    if (from == null || to == null) return const [];
    final changes = <HistoryChange>[];

    if (from.decision != to.decision) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactChanged,
          category: HistoryChangeCategory.artifact,
          subjectId: 'decision',
          previousValue: from.decision.wireName,
          currentValue: to.decision.wireName,
        ),
      );
    }
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
    if (from.metadata.qualityGateSnapshotId !=
        to.metadata.qualityGateSnapshotId) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactChanged,
          category: HistoryChangeCategory.artifact,
          subjectId: 'qualityGateReference',
          previousValue: from.metadata.qualityGateSnapshotId,
          currentValue: to.metadata.qualityGateSnapshotId,
        ),
      );
    }
    if (from.coverage.requiredRuleCoveragePercentage !=
        to.coverage.requiredRuleCoveragePercentage) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.metricValueChanged,
          category: HistoryChangeCategory.metrics,
          subjectId: 'coverage',
          previousValue:
              from.coverage.requiredRuleCoveragePercentage.toString(),
          currentValue: to.coverage.requiredRuleCoveragePercentage.toString(),
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
      from.approvalEvaluations.map((a) => a.requirementId).toList(),
      to.approvalEvaluations.map((a) => a.requirementId).toList(),
      'approval',
      changes,
    );
    _diffApprovalStatus(from, to, changes);
    _diffIds(
      from.waiverEvaluations.map((w) => w.waiverId).toList(),
      to.waiverEvaluations.map((w) => w.waiverId).toList(),
      'waiver',
      changes,
    );
    _diffIds(
      from.conditions.map((c) => c.conditionId).toList(),
      to.conditions.map((c) => c.conditionId).toList(),
      'condition',
      changes,
    );

    final fromSourceFp = from.metadata.sourceSetFingerprint ?? '';
    final toSourceFp = to.metadata.sourceSetFingerprint ?? '';
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

  void _diffApprovalStatus(
    ReleaseDecisionSnapshot from,
    ReleaseDecisionSnapshot to,
    List<HistoryChange> changes,
  ) {
    final fromById = {
      for (final a in from.approvalEvaluations) a.requirementId: a.status,
    };
    final toById = {
      for (final a in to.approvalEvaluations) a.requirementId: a.status,
    };
    for (final id in {...fromById.keys, ...toById.keys}) {
      final prev = fromById[id];
      final curr = toById[id];
      if (prev != null && curr != null && prev != curr) {
        changes.add(
          HistoryChange(
            changeType: HistoryChangeType.artifactChanged,
            category: HistoryChangeCategory.artifact,
            subjectId: 'approvalStatus:$id',
            previousValue: prev.wireName,
            currentValue: curr.wireName,
          ),
        );
      }
    }
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

  Map<String, dynamic> _comparableJson(ReleaseDecisionSnapshot snapshot) {
    final json = snapshot.toJson();
    final metadata = Map<String, dynamic>.from(json['metadata'] as Map);
    metadata.remove('snapshotId');
    metadata.remove('createdAt');
    metadata.remove('evaluatedAt');
    json['metadata'] = metadata;
    json.remove('fingerprint');
    return json;
  }
}
