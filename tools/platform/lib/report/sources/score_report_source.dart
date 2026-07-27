import '../../models/score/score_enums.dart';
import '../../models/score/score_snapshot.dart';
import '../report_input.dart';

/// Converts [EngineeringScoreSnapshot] into [EngineeringScoreReportInputData].
class ScoreReportSource {
  const ScoreReportSource();

  EngineeringScoreReportInputData fromSnapshot(
      EngineeringScoreSnapshot snapshot) {
    final dimensionSummaries = snapshot.dimensions
        .map(
          (d) =>
              '${d.dimensionId}: ${d.normalizedScore?.toStringAsFixed(2) ?? 'n/a'} (weight ${d.weight})',
        )
        .toList();

    return EngineeringScoreReportInputData(
      scoreSnapshotId: snapshot.metadata.scoreSnapshotId,
      policyId: snapshot.metadata.policyId,
      policyVersion: snapshot.metadata.policyVersion,
      overallScore: snapshot.overallScore.value,
      status: snapshot.metadata.status.wireName,
      confidence: snapshot.metadata.confidence.wireName,
      coveragePercentage: snapshot.coverage.coveragePercentage,
      dimensionSummaries: dimensionSummaries,
      limitations: snapshot.explanation.limitations,
    );
  }

  EngineeringScoreReportInputData fromMap(Map<String, dynamic> json) {
    return fromSnapshot(EngineeringScoreSnapshot.fromJson(json));
  }
}
