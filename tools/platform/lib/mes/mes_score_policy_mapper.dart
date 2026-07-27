import '../models/mes/mes_enums.dart';
import '../models/mes/mes_policy.dart';
import '../models/score/score_policy.dart';
import '../score/score_canonical_serializer.dart';

/// Maps an official [MESPolicy] to an executable [ScorePolicy].
class MESScorePolicyMapper {
  const MESScorePolicyMapper({ScoreCanonicalSerializer? serializer})
      : _serializer = serializer ?? const ScoreCanonicalSerializer();

  final ScoreCanonicalSerializer _serializer;

  ScorePolicy toScorePolicy(MESPolicy mesPolicy) {
    final dimensions = mesPolicy.dimensions
        .map(
          (d) => ScoreDimensionPolicy(
            dimensionId: d.dimensionId,
            name: d.name,
            weight: ScoreWeight(value: d.weightPercent),
            rules: d.rules,
            aggregationMethod: d.aggregationMethod,
            description: d.objective,
            missingDataPolicy: d.missingDataPolicy,
          ),
        )
        .toList();

    return ScorePolicy(
      policyId: mesPolicy.policyId,
      name: mesPolicy.metadata.officialName,
      description: mesPolicy.metadata.description ??
          'Official MES policy ${mesPolicy.policyId}',
      policySchemaVersion: ScorePolicy.currentSchemaVersion,
      policyVersion: mesPolicy.policyVersion,
      canonicalizationVersion: ScorePolicy.currentCanonicalizationVersion,
      scoreScale: mesPolicy.scoreScale,
      dimensions: dimensions,
      aggregationMethod: mesPolicy.globalAggregationMethod,
      missingDataPolicy: mesPolicy.globalMissingDataPolicy,
      minimumEvidenceCoverage: mesPolicy.coveragePolicy.minimumPolicyCoverage,
      tags: [...mesPolicy.metadata.tags, 'mes:official'],
      metadata: ScorePolicyMetadata(
        experimental: mesPolicy.metadata.status == MESPolicyStatus.candidate,
        author: mesPolicy.metadata.owner,
        tags: mesPolicy.metadata.tags,
        extra: const {'mes': 'true'},
      ),
    );
  }

  String policyFingerprint(MESPolicy mesPolicy) {
    return _serializer.policyFingerprint(toScorePolicy(mesPolicy));
  }
}
