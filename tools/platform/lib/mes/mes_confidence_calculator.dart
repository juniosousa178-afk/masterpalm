import '../models/mes/mes_enums.dart';
import '../models/mes/mes_policy.dart';
import '../models/mes/mes_snapshot.dart';

/// Derives deterministic MES confidence from coverage and compatibility.
class MESConfidenceCalculator {
  const MESConfidenceCalculator();

  MESConfidence calculate({
    required MESCoverage coverage,
    required MESCompatibilityStatus compatibility,
    required MESPolicy policy,
    required int unavailableRequiredDimensions,
    required int unavailableOptionalDimensions,
  }) {
    if (compatibility == MESCompatibilityStatus.incompatible) {
      return MESConfidence.incompatible;
    }

    final policyCov = coverage.policyCoverage;
    final hasExperimental = policy.dimensions.any(
      (d) => d.evidenceTier == MESEvidenceTier.experimental,
    );

    if (policyCov >= 100 && unavailableOptionalDimensions == 0) {
      return MESConfidence.full;
    }
    if (policyCov >= 85 && unavailableRequiredDimensions == 0) {
      return hasExperimental ? MESConfidence.high : MESConfidence.full;
    }
    if (policyCov >= 70 && unavailableRequiredDimensions == 0) {
      return MESConfidence.high;
    }
    if (policyCov >= 50) {
      return MESConfidence.moderate;
    }
    if (policyCov >= 25) {
      return MESConfidence.low;
    }
    if (policyCov > 0) {
      return MESConfidence.insufficient;
    }
    return MESConfidence.unknown;
  }

  String explain({
    required MESConfidence confidence,
    required MESCoverage coverage,
    required int unavailableOptionalDimensions,
    required MESCompatibilityStatus compatibility,
  }) {
    return 'confidence=$confidence because policyCoverage=${coverage.policyCoverage.toStringAsFixed(2)}%, '
        'evidenceCoverage=${coverage.evidenceCoverage.toStringAsFixed(2)}%, '
        'optionalDimensionsUnavailable=$unavailableOptionalDimensions, '
        'compatibility=$compatibility';
  }
}
