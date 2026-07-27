import '../models/mes/mes_enums.dart';
import '../models/mes/mes_policy.dart';
import '../models/mes/mes_snapshot.dart';
import '../models/score/score_snapshot.dart';

/// Builds structured MES explanations.
class MESExplanationBuilder {
  const MESExplanationBuilder();

  MESExplanation build({
    required MESPolicy policy,
    required EngineeringScoreSnapshot scoreSnapshot,
    required MESEligibility eligibility,
    required MESCoverage coverage,
    required MESConfidence confidence,
    required List<MESDimensionResult> dimensions,
    required String policyFingerprint,
    required bool includeTrace,
  }) {
    final dimSummaries = dimensions
        .map(
          (d) =>
              '${d.dimensionId}: score=${d.normalizedScore ?? 'unavailable'}, weight=${d.weightPercent}%, available=${d.available}',
        )
        .toList();

    final weightAdjustments = <String>[];
    if (coverage.excludedPolicyWeight > 0) {
      weightAdjustments.add(
        'Excluded policy weight: ${coverage.excludedPolicyWeight.toStringAsFixed(2)}% (excludeAndReweight)',
      );
    }

    return MESExplanation(
      summary:
          'MES=${scoreSnapshot.overallScore.value.toStringAsFixed(2)} under policy ${policy.policyId} v${policy.policyVersion} (${policy.metadata.status.wireName})',
      policySummary:
          '${policy.metadata.officialName} (${policy.metadata.acronym}) — candidate weights, not calibrated',
      eligibilitySummary:
          'Eligibility=${eligibility.status.wireName}: ${eligibility.reasons.join('; ')}',
      coverageSummary:
          'rule=${coverage.ruleCoverage.toStringAsFixed(2)}%, dimension=${coverage.dimensionCoverage.toStringAsFixed(2)}%, policy=${coverage.policyCoverage.toStringAsFixed(2)}%, evidence=${coverage.evidenceCoverage.toStringAsFixed(2)}%',
      confidenceSummary: 'Confidence=$confidence',
      dimensionSummaries: dimSummaries,
      weightAdjustments: weightAdjustments,
      calculationReference: MESCalculationReference(
        sourceEngineeringScoreSnapshotId:
            scoreSnapshot.metadata.scoreSnapshotId,
        scoreFingerprint: scoreSnapshot.metadata.scoreFingerprint,
        policyFingerprint: policyFingerprint,
        traceIncluded: includeTrace,
      ),
    );
  }
}
