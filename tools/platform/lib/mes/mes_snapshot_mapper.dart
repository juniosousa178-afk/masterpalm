import '../models/mes/mes_enums.dart';
import '../models/mes/mes_policy.dart';
import '../models/mes/mes_snapshot.dart';
import '../models/score/score_enums.dart';
import '../models/score/score_snapshot.dart';
import 'mes_canonical_serializer.dart';
import 'mes_confidence_calculator.dart';
import 'mes_coverage_calculator.dart';
import 'mes_eligibility_evaluator.dart';
import 'mes_explanation_builder.dart';
import 'mes_score_policy_mapper.dart';
import 'mes_snapshot_id_factory.dart';

/// Maps [EngineeringScoreSnapshot] to official [MESSnapshot].
class MESSnapshotMapper {
  const MESSnapshotMapper({
    MESCoverageCalculator? coverageCalculator,
    MESEligibilityEvaluator? eligibilityEvaluator,
    MESConfidenceCalculator? confidenceCalculator,
    MESExplanationBuilder? explanationBuilder,
    MESScorePolicyMapper? policyMapper,
    MESCanonicalSerializer? serializer,
    MESSnapshotIdFactory? idFactory,
  })  : _coverageCalculator =
            coverageCalculator ?? const MESCoverageCalculator(),
        _eligibilityEvaluator =
            eligibilityEvaluator ?? const MESEligibilityEvaluator(),
        _confidenceCalculator =
            confidenceCalculator ?? const MESConfidenceCalculator(),
        _explanationBuilder =
            explanationBuilder ?? const MESExplanationBuilder(),
        _policyMapper = policyMapper ?? const MESScorePolicyMapper(),
        _serializer = serializer ?? const MESCanonicalSerializer(),
        _idFactory = idFactory ?? const MESSnapshotIdFactory();

  final MESCoverageCalculator _coverageCalculator;
  final MESEligibilityEvaluator _eligibilityEvaluator;
  final MESConfidenceCalculator _confidenceCalculator;
  final MESExplanationBuilder _explanationBuilder;
  final MESScorePolicyMapper _policyMapper;
  final MESCanonicalSerializer _serializer;
  final MESSnapshotIdFactory _idFactory;

  MESSnapshot map({
    required MESPolicy policy,
    required EngineeringScoreSnapshot scoreSnapshot,
    required String projectId,
    required String createdAt,
    required MESCompatibilityStatus compatibility,
    required bool includeExplanations,
    required bool includeTrace,
    String? gitRef,
    String? branch,
    String? sourceHistoryDiffId,
    String? sourceHistorySnapshotId,
  }) {
    final coverage = _coverageCalculator.calculate(
      policy: policy,
      scoreSnapshot: scoreSnapshot,
    );
    final eligibility = _eligibilityEvaluator.evaluate(
      policy: policy,
      scoreSnapshot: scoreSnapshot,
      coverage: coverage,
      compatibility: compatibility,
      hasMetricsSnapshot: true,
    );

    final dimensions = <MESDimensionResult>[];
    var unavailableRequired = 0;
    var unavailableOptional = 0;

    for (final dimDef in policy.dimensions) {
      final scoreDim = scoreSnapshot.dimensions
          .where((d) => d.dimensionId == dimDef.dimensionId)
          .firstOrNull;
      final available = scoreDim != null &&
          scoreDim.availability != ScoreAvailability.unavailable &&
          scoreDim.normalizedScore != null;
      if (!available) {
        if (dimDef.required) {
          unavailableRequired++;
        } else {
          unavailableOptional++;
        }
      }
      dimensions.add(
        MESDimensionResult(
          dimensionId: dimDef.dimensionId,
          name: dimDef.name,
          required: dimDef.required,
          weightPercent: dimDef.weightPercent,
          available: available,
          normalizedScore: scoreDim?.normalizedScore,
          weightedContribution: scoreDim?.weightedContribution,
          ruleCoverage:
              scoreDim == null || scoreDim.coverage.requestedEvidenceCount == 0
                  ? null
                  : (scoreDim.coverage.usedEvidenceCount /
                          scoreDim.coverage.requestedEvidenceCount) *
                      100,
          evidenceTier: dimDef.evidenceTier,
          limitations: dimDef.limitations,
          missingMetricIds: scoreDim?.coverage.missingMetricIds ?? [],
        ),
      );
    }
    dimensions.sort((a, b) => a.dimensionId.compareTo(b.dimensionId));

    final confidence = _confidenceCalculator.calculate(
      coverage: coverage,
      compatibility: compatibility,
      policy: policy,
      unavailableRequiredDimensions: unavailableRequired,
      unavailableOptionalDimensions: unavailableOptional,
    );

    final mesValue = MESValue(
      value: _serializer.roundScore(
        scoreSnapshot.overallScore.value,
        policy.scoreScale.precision,
      ),
      min: policy.scoreScale.min,
      max: policy.scoreScale.max,
      precision: policy.scoreScale.precision,
      unit: policy.scoreScale.unit,
    );

    final band = _resolveBand(policy, mesValue.value);
    final status = _deriveStatus(eligibility, scoreSnapshot.metadata.status);
    final policyFp = _policyMapper.policyFingerprint(policy);

    final dimFps = dimensions
        .map((d) =>
            '${d.dimensionId}:${d.normalizedScore ?? 'na'}:${d.weightPercent}')
        .toList()
      ..sort();

    final mesFp = _serializer.mesFingerprint(
      projectId: projectId,
      policyId: policy.policyId,
      policyVersion: policy.policyVersion,
      policyFingerprint: policyFp,
      engineeringScoreSnapshotId: scoreSnapshot.metadata.scoreSnapshotId,
      engineeringScoreFingerprint: scoreSnapshot.metadata.scoreFingerprint,
      eligibilityStatus: eligibility.status.wireName,
      mesValue: mesValue.value.toStringAsFixed(policy.scoreScale.precision),
      dimensionFingerprints: dimFps,
      policyCoverage: coverage.policyCoverage.toStringAsFixed(2),
      confidence: confidence.wireName,
    );

    final mesSnapshotId = _idFactory.create(
      projectId: projectId,
      policyId: policy.policyId,
      policyVersion: policy.policyVersion,
      mesFingerprint: mesFp,
    );

    final limitations = <MESLimitation>[];
    for (final dim in policy.dimensions) {
      for (final lim in dim.limitations) {
        limitations.add(
          MESLimitation(
            code: 'dimension_limitation',
            message: lim,
            dimensionId: dim.dimensionId,
          ),
        );
      }
      for (final req in dim.metricRequirements) {
        if (req.limitation != null) {
          limitations.add(
            MESLimitation(
              code: 'metric_limitation',
              message: req.limitation!,
              metricId: req.metricId,
              dimensionId: dim.dimensionId,
            ),
          );
        }
      }
    }
    if (!policy.metadata.calibrated) {
      limitations.add(
        const MESLimitation(
          code: 'policy_not_calibrated',
          message: 'MES policy weights are candidate and not calibrated.',
        ),
      );
    }

    final evidenceSummary = <MESEvidenceSummary>[];
    for (final dim in policy.dimensions) {
      for (final req in dim.metricRequirements) {
        final scoreDim = scoreSnapshot.dimensions
            .where((d) => d.dimensionId == dim.dimensionId)
            .firstOrNull;
        final available = scoreDim != null &&
            !scoreDim.coverage.missingMetricIds.contains(req.metricId);
        evidenceSummary.add(
          MESEvidenceSummary(
            metricId: req.metricId,
            tier: req.tier,
            available: available,
            limitation: req.limitation,
          ),
        );
      }
    }
    evidenceSummary.sort((a, b) => a.metricId.compareTo(b.metricId));

    final warnings = scoreSnapshot.warnings
        .map((w) => MESWarning(code: w.code, message: w.message))
        .toList();

    final metadata = MESMetadata(
      mesSnapshotId: mesSnapshotId,
      mesSchemaVersion: MESMetadata.currentSchemaVersion,
      mesCalculationVersion: MESMetadata.currentCalculationVersion,
      mesCanonicalizationVersion: MESMetadata.currentCanonicalizationVersion,
      projectId: projectId,
      policyId: policy.policyId,
      policyVersion: policy.policyVersion,
      policyStatus: policy.metadata.status,
      sourceMetricsSnapshotId: scoreSnapshot.metadata.sourceMetricsSnapshotId,
      sourceEngineeringScoreSnapshotId: scoreSnapshot.metadata.scoreSnapshotId,
      sourceHistorySnapshotId: sourceHistorySnapshotId,
      sourceHistoryDiffId: sourceHistoryDiffId,
      createdAt: createdAt,
      gitRef: gitRef,
      branch: branch,
      mesFingerprint: mesFp,
      policyFingerprint: policyFp,
      status: status,
      confidence: confidence,
      compatibilityStatus: compatibility,
      bandId: band?.bandId,
      dimensionCount: dimensions.length,
      availableDimensionCount: dimensions.where((d) => d.available).length,
      unavailableDimensionCount: dimensions.where((d) => !d.available).length,
      warningCount: warnings.length,
      errorCount: 0,
    );

    final explanation = includeExplanations
        ? _explanationBuilder.build(
            policy: policy,
            scoreSnapshot: scoreSnapshot,
            eligibility: eligibility,
            coverage: coverage,
            confidence: confidence,
            dimensions: dimensions,
            policyFingerprint: policyFp,
            includeTrace: includeTrace,
          )
        : const MESExplanation(
            summary: 'Explanations disabled',
            policySummary: '',
            eligibilitySummary: '',
            coverageSummary: '',
            confidenceSummary: '',
            dimensionSummaries: [],
            weightAdjustments: [],
          );

    return MESSnapshot(
      metadata: metadata,
      mesValue: mesValue,
      dimensions: dimensions,
      eligibility: eligibility,
      coverage: coverage,
      confidence: confidence,
      evidenceSummary: evidenceSummary,
      explanation: explanation,
      limitations: limitations,
      warnings: warnings,
      errors: const [],
      band: band,
    );
  }

  MESBand? _resolveBand(MESPolicy policy, double value) {
    for (final band in policy.bands) {
      if (value >= band.min && value <= band.max) return band;
    }
    return null;
  }

  MESStatus _deriveStatus(MESEligibility eligibility, ScoreStatus scoreStatus) {
    if (eligibility.status == MESEligibilityStatus.incompatible) {
      return MESStatus.incompatible;
    }
    if (eligibility.status == MESEligibilityStatus.ineligible) {
      return MESStatus.unavailable;
    }
    if (scoreStatus == ScoreStatus.failure) return MESStatus.failure;
    if (eligibility.status == MESEligibilityStatus.partiallyEligible ||
        scoreStatus == ScoreStatus.partial) {
      return MESStatus.partial;
    }
    if (scoreStatus == ScoreStatus.unavailable) return MESStatus.unavailable;
    return MESStatus.success;
  }
}
