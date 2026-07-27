import '../models/mes/mes_enums.dart';
import '../models/mes/mes_policy.dart';
import '../models/mes/mes_snapshot.dart';
import '../models/score/score_enums.dart';
import '../models/score/score_snapshot.dart';

/// Evaluates project eligibility for MES calculation.
class MESEligibilityEvaluator {
  const MESEligibilityEvaluator();

  MESEligibility evaluate({
    required MESPolicy policy,
    required EngineeringScoreSnapshot scoreSnapshot,
    required MESCoverage coverage,
    required MESCompatibilityStatus compatibility,
    required bool hasMetricsSnapshot,
  }) {
    final reasons = <String>[];
    final missingRequired = <String>[];
    final missingOptional = <String>[];

    if (!hasMetricsSnapshot) {
      return const MESEligibility(
        status: MESEligibilityStatus.ineligible,
        reasons: ['MetricsSnapshot is required'],
        missingRequiredDimensions: [],
        missingOptionalDimensions: [],
      );
    }

    if (compatibility == MESCompatibilityStatus.incompatible) {
      return const MESEligibility(
        status: MESEligibilityStatus.incompatible,
        reasons: ['Metrics schema incompatible with MES policy'],
        missingRequiredDimensions: [],
        missingOptionalDimensions: [],
      );
    }

    if (!policy.eligibility.allowedPolicyStatuses
        .contains(policy.metadata.status)) {
      reasons
          .add('Policy status ${policy.metadata.status.wireName} not allowed');
    }

    for (final dimDef in policy.dimensions) {
      final scoreDim = scoreSnapshot.dimensions
          .where((d) => d.dimensionId == dimDef.dimensionId)
          .firstOrNull;
      final unavailable = scoreDim == null ||
          scoreDim.availability == ScoreAvailability.unavailable;
      if (unavailable) {
        if (dimDef.required) {
          missingRequired.add(dimDef.dimensionId);
        } else {
          missingOptional.add(dimDef.dimensionId);
        }
      }
    }

    if (missingRequired.isNotEmpty) {
      reasons.add(
        'Required dimensions unavailable: ${missingRequired.join(', ')}',
      );
      return MESEligibility(
        status: MESEligibilityStatus.ineligible,
        reasons: reasons,
        missingRequiredDimensions: missingRequired,
        missingOptionalDimensions: missingOptional,
      );
    }

    if (coverage.policyCoverage < policy.eligibility.minimumPolicyCoverage) {
      reasons.add(
        'Policy coverage ${coverage.policyCoverage.toStringAsFixed(2)}% below minimum ${policy.eligibility.minimumPolicyCoverage}%',
      );
      return MESEligibility(
        status: MESEligibilityStatus.ineligible,
        reasons: reasons,
        missingRequiredDimensions: missingRequired,
        missingOptionalDimensions: missingOptional,
      );
    }

    if (coverage.requiredDimensionCoverage <
        policy.eligibility.minimumRequiredDimensionCoverage) {
      reasons.add(
        'Required dimension coverage below minimum',
      );
    }

    if (missingOptional.isNotEmpty ||
        coverage.excludedPolicyWeight > 0 ||
        compatibility == MESCompatibilityStatus.partiallyCompatible) {
      if (policy.eligibility.allowPartialWithOptionalMissing) {
        reasons.add('Optional dimensions or evidence missing');
        return MESEligibility(
          status: MESEligibilityStatus.partiallyEligible,
          reasons: reasons,
          missingRequiredDimensions: missingRequired,
          missingOptionalDimensions: missingOptional,
        );
      }
    }

    return MESEligibility(
      status: MESEligibilityStatus.eligible,
      reasons: reasons.isEmpty ? ['All eligibility criteria met'] : reasons,
      missingRequiredDimensions: missingRequired,
      missingOptionalDimensions: missingOptional,
    );
  }
}
