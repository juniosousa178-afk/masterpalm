import '../../models/mes/mes_enums.dart';
import '../../models/mes/mes_policy.dart';
import '../../models/mes/mes_snapshot.dart';
import '../report_input.dart';

/// Converts [MESSnapshot] into [MESReportInputData].
class MESReportSource {
  const MESReportSource();

  MESReportInputData fromSnapshot(MESSnapshot snapshot) {
    final dimensionSummaries = snapshot.dimensions
        .map(
          (d) =>
              '${d.dimensionId}: ${d.normalizedScore?.toStringAsFixed(2) ?? 'n/a'} (weight ${d.weightPercent}%, required=${d.required})',
        )
        .toList();

    return MESReportInputData(
      mesSnapshotId: snapshot.metadata.mesSnapshotId,
      officialName: MESPolicyMetadata.officialNameValue,
      acronym: MESPolicyMetadata.acronymValue,
      policyId: snapshot.metadata.policyId,
      policyVersion: snapshot.metadata.policyVersion,
      policyStatus: snapshot.metadata.policyStatus.wireName,
      mesValue: snapshot.mesValue.value,
      status: snapshot.metadata.status.wireName,
      eligibility: snapshot.eligibility.status.wireName,
      confidence: snapshot.confidence.wireName,
      policyCoverage: snapshot.coverage.policyCoverage,
      evidenceCoverage: snapshot.coverage.evidenceCoverage,
      dimensionSummaries: dimensionSummaries,
      limitations: snapshot.limitations.map((l) => l.message).toList(),
      sourceEngineeringScoreSnapshotId:
          snapshot.metadata.sourceEngineeringScoreSnapshotId,
      bandId: snapshot.band?.bandId,
    );
  }

  MESReportInputData fromMap(Map<String, dynamic> json) {
    return fromSnapshot(MESSnapshot.fromJson(json));
  }
}
