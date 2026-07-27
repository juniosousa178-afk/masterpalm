import 'dart:convert';

import '../../models/history/history_artifact.dart';
import '../../models/history/history_artifact_payload.dart';
import '../../models/history/history_artifact_type.dart';
import '../../models/history/history_change_type.dart';
import '../../models/history/history_diff.dart';
import '../../models/quality_gate/quality_gate_enums.dart';
import '../../models/quality_gate/quality_gate_snapshot.dart';
import '../history_canonical_serializer.dart';

/// Maps [QualityGateSnapshot] to history artifacts and comparable fields.
class QualityGateHistoryMapper {
  const QualityGateHistoryMapper({HistoryCanonicalSerializer? serializer})
      : _serializer = serializer ?? const HistoryCanonicalSerializer();

  final HistoryCanonicalSerializer _serializer;

  HistoryArtifact fromMap(Map<String, dynamic> json) {
    final snapshot = QualityGateSnapshot.fromJson(json);
    final comparable = snapshot.toComparableJson();
    final fingerprint = _serializer.fingerprintFromString(
      jsonEncode(comparable),
    );
    return HistoryArtifact(
      artifactType: HistoryArtifactType.qualityGate,
      artifactId: snapshot.metadata.qualityGateSnapshotId,
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
    QualityGateSnapshot? from,
    QualityGateSnapshot? to,
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
    if (from.metadata.policyVersion != to.metadata.policyVersion) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactChanged,
          category: HistoryChangeCategory.artifact,
          subjectId: 'policyVersion',
          previousValue: from.metadata.policyVersion.toString(),
          currentValue: to.metadata.policyVersion.toString(),
        ),
      );
    }
    if (from.coverage.requiredRuleCoveragePercentage !=
        to.coverage.requiredRuleCoveragePercentage) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.metricValueChanged,
          category: HistoryChangeCategory.metrics,
          subjectId: 'requiredRuleCoveragePercentage',
          previousValue:
              from.coverage.requiredRuleCoveragePercentage.toString(),
          currentValue: to.coverage.requiredRuleCoveragePercentage.toString(),
        ),
      );
    }
    return changes;
  }
}
