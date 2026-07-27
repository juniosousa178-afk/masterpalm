import '../models/score/score_enums.dart';
import '../models/score/score_policy.dart';
import '../models/score/score_snapshot.dart';

/// Builds structured score explanations.
class ScoreExplanationBuilder {
  const ScoreExplanationBuilder();

  ScoreExplanation build({
    required ScorePolicy policy,
    required EngineeringScoreSnapshot snapshot,
    required bool includeTrace,
  }) {
    final dimensionSummaries = snapshot.dimensions.map((dim) {
      final score = dim.normalizedScore?.toStringAsFixed(2) ?? 'n/a';
      return '${dim.dimensionId}: score=$score weight=${dim.weight} '
          'availability=${dim.availability.wireName}';
    }).toList();

    final limitations = <String>[
      if (policy.metadata.experimental)
        'Policy ${policy.policyId} is experimental and not MES',
      if (snapshot.coverage.coveragePercentage < 100)
        'Coverage ${snapshot.coverage.coveragePercentage.toStringAsFixed(2)}%',
      ...snapshot.warnings.map((w) => w.message),
    ];

    final trace = includeTrace
        ? snapshot.dimensions
            .expand((d) => d.rules)
            .where((r) => r.matched)
            .map(
              (r) =>
                  '${r.ruleId}: ${r.explanation ?? r.metricId} => ${r.normalizedScore}',
            )
            .toList()
        : <String>[];

    return ScoreExplanation(
      summary:
          'Score ${snapshot.overallScore.value.toStringAsFixed(2)} under policy ${policy.policyId} v${policy.policyVersion}',
      policySummary:
          '${policy.name} (${policy.aggregationMethod.wireName}, missing=${policy.missingDataPolicy.wireName})',
      dimensionSummaries: dimensionSummaries,
      limitations: limitations,
      aggregationFormula: 'weightedAverage(sum(score×weight)/sum(weights))',
      trace: trace,
    );
  }
}
