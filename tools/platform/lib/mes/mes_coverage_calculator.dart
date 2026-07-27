import '../models/mes/mes_policy.dart';
import '../models/mes/mes_snapshot.dart';
import '../models/score/score_enums.dart';
import '../models/score/score_snapshot.dart';

/// Calculates hierarchical MES coverage from score snapshot and policy.
class MESCoverageCalculator {
  const MESCoverageCalculator();

  MESCoverage calculate({
    required MESPolicy policy,
    required EngineeringScoreSnapshot scoreSnapshot,
  }) {
    var requestedRules = 0;
    var availableRules = 0;
    var usedRules = 0;

    var totalDimWeight = 0.0;
    var appliedDimWeight = 0.0;
    var requiredDimWeight = 0.0;
    var appliedRequiredDimWeight = 0.0;
    var optionalDimWeight = 0.0;
    var appliedOptionalDimWeight = 0.0;

    final missingRequired = <String>[];
    final missingOptional = <String>[];

    for (final dimDef in policy.dimensions) {
      final scoreDim = scoreSnapshot.dimensions
          .where((d) => d.dimensionId == dimDef.dimensionId)
          .firstOrNull;

      requestedRules += scoreDim?.coverage.requestedEvidenceCount ?? 0;
      availableRules += scoreDim?.coverage.availableEvidenceCount ?? 0;
      usedRules += scoreDim?.coverage.usedEvidenceCount ?? 0;

      totalDimWeight += dimDef.weightPercent;
      final available = scoreDim != null &&
          scoreDim.availability != ScoreAvailability.unavailable &&
          scoreDim.normalizedScore != null;

      if (available) {
        appliedDimWeight += dimDef.weightPercent;
        if (dimDef.required) {
          appliedRequiredDimWeight += dimDef.weightPercent;
        } else {
          appliedOptionalDimWeight += dimDef.weightPercent;
        }
      } else {
        for (final req in dimDef.metricRequirements) {
          if (!req.metricId.startsWith('history.')) {
            if (dimDef.required) {
              if (!missingRequired.contains(req.metricId)) {
                missingRequired.add(req.metricId);
              }
            } else {
              if (!missingOptional.contains(req.metricId)) {
                missingOptional.add(req.metricId);
              }
            }
          }
        }
      }

      if (dimDef.required) {
        requiredDimWeight += dimDef.weightPercent;
      } else {
        optionalDimWeight += dimDef.weightPercent;
      }
    }

    missingRequired.sort();
    missingOptional.sort();

    final ruleCoverage =
        requestedRules == 0 ? 0.0 : (usedRules / requestedRules) * 100;
    final dimensionCoverage =
        totalDimWeight == 0 ? 0.0 : (appliedDimWeight / totalDimWeight) * 100;
    final policyCoverage = dimensionCoverage;
    final evidenceCoverage = (ruleCoverage * 0.4) + (dimensionCoverage * 0.6);
    final requiredDimensionCoverage = requiredDimWeight == 0
        ? 100.0
        : (appliedRequiredDimWeight / requiredDimWeight) * 100;
    final optionalDimensionCoverage = optionalDimWeight == 0
        ? 100.0
        : (appliedOptionalDimWeight / optionalDimWeight) * 100;

    return MESCoverage(
      ruleCoverage: _round(ruleCoverage),
      dimensionCoverage: _round(dimensionCoverage),
      policyCoverage: _round(policyCoverage),
      evidenceCoverage: _round(evidenceCoverage),
      requiredDimensionCoverage: _round(requiredDimensionCoverage),
      optionalDimensionCoverage: _round(optionalDimensionCoverage),
      missingRequiredMetricIds: missingRequired,
      missingOptionalMetricIds: missingOptional,
      totalPolicyWeight: totalDimWeight,
      appliedPolicyWeight: appliedDimWeight,
      excludedPolicyWeight: totalDimWeight - appliedDimWeight,
      requestedRuleCount: requestedRules,
      availableRuleCount: availableRules,
      usedRuleCount: usedRules,
    );
  }

  double _round(double v) => double.parse(v.toStringAsFixed(2));
}
