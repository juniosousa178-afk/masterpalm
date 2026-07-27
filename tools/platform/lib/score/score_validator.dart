import '../models/score/score_enums.dart';
import '../models/score/score_snapshot.dart';

/// Validates engineering score snapshots.
class ScoreValidator {
  const ScoreValidator();

  ScoreValidationResult validate(EngineeringScoreSnapshot snapshot) {
    final errors = <String>[];
    const warnings = <String>[];

    final meta = snapshot.metadata;
    if (meta.scoreSnapshotId.isEmpty) errors.add('scoreSnapshotId is empty');
    if (meta.projectId.isEmpty) errors.add('projectId is empty');
    if (meta.policyId.isEmpty) errors.add('policyId is empty');
    if (meta.scoreFingerprint.isEmpty) errors.add('scoreFingerprint is empty');
    if (meta.dimensionCount != snapshot.dimensions.length) {
      errors.add('dimensionCount metadata mismatch');
    }

    final overall = snapshot.overallScore.value;
    if (overall.isNaN || overall.isInfinite) {
      errors.add('overallScore is not finite');
    }
    if (overall < snapshot.overallScore.scaleMin ||
        overall > snapshot.overallScore.scaleMax) {
      errors.add('overallScore out of scale');
    }

    for (final dim in snapshot.dimensions) {
      if (dim.normalizedScore != null) {
        if (dim.normalizedScore!.isNaN || dim.normalizedScore!.isInfinite) {
          errors.add('dimension score not finite: ${dim.dimensionId}');
        }
      }
      if (dim.availability == ScoreAvailability.unavailable &&
          dim.weightedContribution != null &&
          dim.weightedContribution! > 0) {
        errors.add(
          'unavailable dimension has contribution: ${dim.dimensionId}',
        );
      }
    }

    if (!_isDeterministicOrder(snapshot.dimensions)) {
      errors.add('dimensions are not in deterministic order');
    }

    return ScoreValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
      warnings: warnings,
    );
  }

  bool _isDeterministicOrder(List<ScoreDimensionResult> dimensions) {
    for (var i = 1; i < dimensions.length; i++) {
      if (dimensions[i - 1].dimensionId.compareTo(dimensions[i].dimensionId) >
          0) {
        return false;
      }
    }
    return true;
  }
}
