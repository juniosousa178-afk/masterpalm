import '../metrics/metrics_definitions.dart';
import '../models/mes/mes_enums.dart';
import '../models/mes/mes_policy.dart';
import 'mes_score_policy_mapper.dart';

/// Validates official MES policies.
class MESPolicyValidator {
  const MESPolicyValidator({MESScorePolicyMapper? mapper})
      : _mapper = mapper ?? const MESScorePolicyMapper();

  final MESScorePolicyMapper _mapper;

  MESPolicyValidationResult validate(MESPolicy policy) {
    final errors = <String>[];
    final warnings = <String>[];

    if (policy.policyId.isEmpty) {
      errors.add('policyId is required');
    }
    if (policy.policyId != 'mes-official-v1' &&
        policy.metadata.tags.contains('official')) {
      warnings.add('Official tag on non-standard policyId');
    }
    if (policy.metadata.officialName.isEmpty) {
      errors.add('officialName is required');
    }
    if (policy.metadata.status == MESPolicyStatus.active &&
        !policy.metadata.calibrated) {
      errors.add('active policy cannot be uncalibrated');
    }
    if (policy.metadata.tags.contains('not-mes')) {
      errors.add('not-mes tag is not allowed on official MES policy');
    }
    if ((policy.totalWeightPercent - 100).abs() > 0.01) {
      errors.add(
        'dimension weights must total 100%, got ${policy.totalWeightPercent}',
      );
    }

    final dimIds = <String>{};
    for (final dim in policy.dimensions) {
      if (!dimIds.add(dim.dimensionId)) {
        errors.add('duplicate dimensionId: ${dim.dimensionId}');
      }
      if (dim.metricRequirements.isEmpty) {
        errors.add('dimension ${dim.dimensionId} has no metric requirements');
      }
      if (dim.rules.isEmpty) {
        errors.add('dimension ${dim.dimensionId} has no rules');
      }
      for (final req in dim.metricRequirements) {
        if (req.rationale.isEmpty) {
          errors.add('metric ${req.metricId} missing rationale');
        }
        if (req.tier == MESEvidenceTier.experimental &&
            (req.limitation == null || req.limitation!.isEmpty)) {
          errors.add(
            'experimental metric ${req.metricId} requires limitation',
          );
        }
        if (!req.metricId.startsWith('history.') &&
            !MetricsDefinitions.all.containsKey(req.metricId)) {
          errors.add('unknown metricId: ${req.metricId}');
        }
      }
      for (final lim in dim.limitations) {
        if (lim.isEmpty) {
          errors.add('empty limitation on ${dim.dimensionId}');
        }
      }
    }

    final ruleIds = <String>{};
    for (final dim in policy.dimensions) {
      for (final rule in dim.rules) {
        if (!ruleIds.add(rule.ruleId)) {
          errors.add('duplicate ruleId: ${rule.ruleId}');
        }
      }
    }

    if (policy.bands.isNotEmpty) {
      final sorted = policy.bands.toList()
        ..sort((a, b) => a.min.compareTo(b.min));
      for (var i = 0; i < sorted.length; i++) {
        if (sorted[i].min > sorted[i].max) {
          errors.add('inverted band ${sorted[i].bandId}');
        }
        if (i > 0 && sorted[i].min <= sorted[i - 1].max) {
          errors.add(
              'overlapping bands ${sorted[i - 1].bandId} and ${sorted[i].bandId}');
        }
      }
    }

    if (policy.coveragePolicy.minimumPolicyCoverage < 0 ||
        policy.coveragePolicy.minimumPolicyCoverage > 100) {
      errors.add('invalid minimumPolicyCoverage');
    }

    try {
      _mapper.toScorePolicy(policy);
    } catch (e) {
      errors.add('ScorePolicy mapping failed: $e');
    }

    return MESPolicyValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
      warnings: warnings,
    );
  }
}
