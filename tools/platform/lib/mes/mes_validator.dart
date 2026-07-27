import '../models/mes/mes_enums.dart';
import '../models/mes/mes_snapshot.dart';

/// Validates MES snapshot invariants.
class MESValidator {
  const MESValidator();

  MESValidationResult validate(MESSnapshot snapshot) {
    final errors = <String>[];
    final warnings = <String>[];

    final meta = snapshot.metadata;
    if (meta.mesSnapshotId.isEmpty) errors.add('mesSnapshotId is empty');
    if (meta.mesFingerprint.isEmpty) errors.add('mesFingerprint is empty');
    if (meta.projectId.isEmpty) errors.add('projectId is empty');
    if (meta.sourceEngineeringScoreSnapshotId.isEmpty) {
      errors.add('sourceEngineeringScoreSnapshotId is empty');
    }
    if (meta.policyId != 'mes-official-v1' &&
        meta.policyStatus == MESPolicyStatus.candidate) {
      warnings.add('non-standard policyId with candidate status');
    }

    if (snapshot.mesValue.value.isNaN || snapshot.mesValue.value.isInfinite) {
      errors.add('mesValue is not finite');
    }
    if (snapshot.mesValue.value < snapshot.mesValue.min ||
        snapshot.mesValue.value > snapshot.mesValue.max) {
      errors.add('mesValue out of scale');
    }

    final dimIds = <String>{};
    for (final dim in snapshot.dimensions) {
      if (!dimIds.add(dim.dimensionId)) {
        errors.add('duplicate dimension ${dim.dimensionId}');
      }
    }

    if (meta.dimensionCount != snapshot.dimensions.length) {
      errors.add('dimensionCount mismatch');
    }
    if (meta.warningCount != snapshot.warnings.length) {
      errors.add('warningCount mismatch');
    }
    if (meta.errorCount != snapshot.errors.length) {
      errors.add('errorCount mismatch');
    }

    if (snapshot.eligibility.status == MESEligibilityStatus.ineligible &&
        snapshot.metadata.status == MESStatus.success) {
      errors.add('ineligible project cannot have success status');
    }

    if (snapshot.metadata.status == MESStatus.partial &&
        snapshot.eligibility.status == MESEligibilityStatus.eligible &&
        snapshot.coverage.excludedPolicyWeight == 0) {
      warnings.add('partial status with full eligibility');
    }

    return MESValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
      warnings: warnings,
    );
  }
}
