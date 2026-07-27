/// Score aggregation result for future Score Engine integration.
class ScoreResult {
  const ScoreResult({
    required this.name,
    required this.score,
    this.maxScore = 100,
    this.breakdown = const {},
  });

  final String name;
  final double score;
  final double maxScore;
  final Map<String, double> breakdown;

  Map<String, dynamic> toJson() => {
        'name': name,
        'score': score,
        'maxScore': maxScore,
        if (breakdown.isNotEmpty) 'breakdown': breakdown,
      };
}
