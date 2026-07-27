import '../models/quality_gate/quality_gate_enums.dart';
import '../models/quality_gate/quality_gate_evidence.dart';
import '../models/quality_gate/quality_gate_messages.dart';
import '../models/quality_gate/quality_gate_policy.dart';
import '../models/quality_gate/quality_gate_snapshot.dart';
import 'resolved_quality_gate_sources.dart';

/// Calculates evaluation coverage from rule outcomes.
class QualityGateCoverageCalculator {
  const QualityGateCoverageCalculator();

  QualityGateCoverage calculate({
    required QualityGatePolicy policy,
    required List<QualityGateEvaluation> evaluations,
    required List<QualityGateRuleSetEvaluation> ruleSetEvaluations,
    required ResolvedQualityGateSources sources,
  }) {
    final allRules = policy.allRules;
    final enabledRules = allRules.where((r) => r.enabled).toList();
    final requiredRules = enabledRules
        .where((r) => r.requirement == QualityGateRuleRequirement.required)
        .toList();

    final passed = _count(evaluations, QualityGateRuleStatus.passed);
    final failed = _count(evaluations, QualityGateRuleStatus.failed);
    final unavailable = _count(evaluations, QualityGateRuleStatus.unavailable);
    final incompatible =
        _count(evaluations, QualityGateRuleStatus.incompatible);
    final skipped = _count(evaluations, QualityGateRuleStatus.skipped);
    final notApplicable =
        _count(evaluations, QualityGateRuleStatus.notApplicable);
    final evaluated = passed + failed;

    final evaluatedRequired = evaluations
        .where(
          (e) =>
              requiredRules.any((r) => r.ruleId == e.ruleId) &&
              (e.status == QualityGateRuleStatus.passed ||
                  e.status == QualityGateRuleStatus.failed),
        )
        .length;

    final requiredCoverage = _percentage(
      evaluatedRequired,
      requiredRules.length,
      zeroDefault: 100,
    );
    final overallCoverage = _percentage(
      evaluated,
      enabledRules.length,
      zeroDefault: 0,
    );

    final evidenceCoverage = evaluations.isEmpty
        ? 0
        : _percentage(
            evaluations.where((e) => e.evidence.isNotEmpty).length,
            evaluations.length,
          );

    final availableSources = sources.sourceReferences
        .where(
          (r) => r.availability == QualityGateSourceAvailability.available,
        )
        .length;
    final sourceCoverage = policy.requiredSourceTypes.isEmpty
        ? 100
        : _percentage(
            availableSources,
            policy.requiredSourceTypes.length,
          );

    final ruleSetCoverage = <String, double>{};
    for (final setEval in ruleSetEvaluations) {
      final set = policy.ruleSets.cast<QualityGateRuleSet?>().firstWhere(
            (s) => s?.ruleSetId == setEval.ruleSetId,
            orElse: () => null,
          );
      if (set == null) continue;
      final denominator = set.rules.where((r) => r.enabled).length;
      ruleSetCoverage[setEval.ruleSetId] = _percentage(
        setEval.evaluatedRuleCount,
        denominator,
      );
    }

    final missingRuleIds = enabledRules
        .where(
          (rule) => !evaluations.any((e) => e.ruleId == rule.ruleId),
        )
        .map((r) => r.ruleId)
        .toList()
      ..sort();

    final missingSourceTypes = policy.requiredSourceTypes.where((type) {
      final source = sources.allSources.firstWhere((s) => s.sourceType == type);
      return !source.isAvailable;
    }).toList()
      ..sort((a, b) => a.wireName.compareTo(b.wireName));

    final limitations = <String>[];
    if (requiredRules.isEmpty) {
      limitations.add('Policy has no required rules');
    }
    if (enabledRules.isEmpty) {
      limitations.add('Policy has no enabled rules');
    }

    return QualityGateCoverage(
      totalRuleCount: allRules.length,
      enabledRuleCount: enabledRules.length,
      evaluatedRuleCount: evaluated,
      passedRuleCount: passed,
      failedRuleCount: failed,
      unavailableRuleCount: unavailable,
      incompatibleRuleCount: incompatible,
      skippedRuleCount: skipped,
      notApplicableRuleCount: notApplicable,
      requiredRuleCount: requiredRules.length,
      evaluatedRequiredRuleCount: evaluatedRequired,
      requiredRuleCoveragePercentage: requiredCoverage.toDouble(),
      overallRuleCoveragePercentage: overallCoverage.toDouble(),
      evidenceCoveragePercentage: evidenceCoverage.toDouble(),
      sourceCoveragePercentage: sourceCoverage.toDouble(),
      ruleSetCoverage: ruleSetCoverage,
      missingRuleIds: missingRuleIds,
      missingSourceTypes: missingSourceTypes,
      limitations: limitations,
    );
  }

  int _count(
      List<QualityGateEvaluation> evaluations, QualityGateRuleStatus status) {
    return evaluations.where((e) => e.status == status).length;
  }

  double _percentage(int numerator, int denominator, {double zeroDefault = 0}) {
    if (denominator <= 0) return zeroDefault;
    final value = (numerator / denominator) * 100;
    if (value < 0) return 0;
    if (value > 100) return 100;
    return double.parse(value.toStringAsFixed(2));
  }
}
