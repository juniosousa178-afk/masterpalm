import '../models/history/history_diff.dart';
import '../models/metrics/metrics_snapshot.dart';
import '../models/score/score_enums.dart';
import '../models/score/score_policy.dart';
import '../models/score/score_request.dart';
import '../models/score/score_snapshot.dart';
import 'calculators/dimension_score_calculator.dart';
import 'calculators/overall_score_calculator.dart';
import 'policies/foundation_reference_policy.dart';
import 'score_canonical_serializer.dart';
import 'score_compatibility_checker.dart';
import 'score_exceptions.dart';
import 'score_explanation_builder.dart';
import 'score_input.dart';
import 'score_policy_validator.dart';
import 'score_registry.dart';
import 'score_snapshot_id_factory.dart';
import 'score_validator.dart';

/// Stateless engine that evaluates policies against platform evidence.
class ScoreEngine {
  ScoreEngine({
    required ScoreRegistry registry,
    ScorePolicyValidator? policyValidator,
    ScoreValidator? validator,
    ScoreCompatibilityChecker? compatibilityChecker,
    DimensionScoreCalculator? dimensionCalculator,
    OverallScoreCalculator? overallCalculator,
    ScoreExplanationBuilder? explanationBuilder,
    ScoreCanonicalSerializer? serializer,
    ScoreSnapshotIdFactory? idFactory,
  })  : _registry = registry,
        _policyValidator = policyValidator ?? const ScorePolicyValidator(),
        _validator = validator ?? const ScoreValidator(),
        _compatibilityChecker =
            compatibilityChecker ?? const ScoreCompatibilityChecker(),
        _dimensionCalculator =
            dimensionCalculator ?? const DimensionScoreCalculator(),
        _overallCalculator =
            overallCalculator ?? const OverallScoreCalculator(),
        _explanationBuilder =
            explanationBuilder ?? const ScoreExplanationBuilder(),
        _serializer = serializer ?? const ScoreCanonicalSerializer(),
        _idFactory = idFactory ?? const ScoreSnapshotIdFactory();

  final ScoreRegistry _registry;
  final ScorePolicyValidator _policyValidator;
  final ScoreValidator _validator;
  final ScoreCompatibilityChecker _compatibilityChecker;
  final DimensionScoreCalculator _dimensionCalculator;
  final OverallScoreCalculator _overallCalculator;
  final ScoreExplanationBuilder _explanationBuilder;
  final ScoreCanonicalSerializer _serializer;
  final ScoreSnapshotIdFactory _idFactory;

  ScoreResult calculate(ScoreRequest request) {
    if (request.projectId.isEmpty) {
      throw ScoreValidationException('projectId is required');
    }
    if (request.createdAt.isEmpty) {
      throw ScoreValidationException('createdAt is required');
    }
    if (request.metricsSnapshot.isEmpty) {
      throw ScoreValidationException('metricsSnapshot is required');
    }

    final policy = _resolvePolicy(request);
    final policyValidation = _policyValidator.validate(policy);
    if (!policyValidation.isValid) {
      throw ScorePolicyException(policyValidation.errors.join('; '));
    }

    final metricsSnapshot = MetricsSnapshot.fromJson(request.metricsSnapshot);
    final compatibility = _compatibilityChecker.check(
      policy: policy,
      metricsSnapshot: metricsSnapshot,
      strict: request.strictCompatibility,
    );
    if (request.strictCompatibility &&
        compatibility == ScoreCompatibilityStatus.incompatible) {
      throw ScoreCompatibilityException('Strict compatibility failed');
    }

    final historyDiff = request.historyDiff == null
        ? null
        : HistoryDiff.fromJson(request.historyDiff!);

    final input = ScoreInput(
      projectId: request.projectId,
      metricsSnapshot: metricsSnapshot,
      policy: policy,
      guardianAnalysis: request.guardianAnalysis,
      historyDiff: historyDiff,
      historySnapshot: request.historySnapshot,
      requestedDimensions: request.requestedDimensions,
      requestedRuleIds: request.requestedRuleIds,
      strictCompatibility: request.strictCompatibility,
      includeTrace: request.includeTrace,
      includeExplanations: request.includeExplanations,
      gitRef: request.gitRef,
      branch: request.branch,
      sourceEventId: request.sourceEventId,
      createdAt: request.createdAt,
    );

    final dimensions = <ScoreDimensionResult>[];
    final warnings = <ScoreWarning>[];
    const errors = <ScoreError>[];

    final sortedDims = policy.dimensions.toList()
      ..sort((a, b) => a.dimensionId.compareTo(b.dimensionId));

    for (final dim in sortedDims) {
      if (input.requestedDimensions != null &&
          !input.requestedDimensions!.contains(dim.dimensionId)) {
        continue;
      }
      final result = _dimensionCalculator.calculate(
        dimension: dim,
        policy: policy,
        input: input,
        missingPolicy: policy.missingDataPolicy,
      );
      dimensions.add(result);
      for (final w in result.warnings) {
        warnings.add(ScoreWarning(code: 'dimension_warning', message: w));
      }
    }

    final overallScore = _overallCalculator.calculate(
      policy: policy,
      dimensions: dimensions,
    );

    final coverage = _buildCoverage(dimensions);
    final confidence = _deriveConfidence(coverage, compatibility);
    final status = _deriveStatus(coverage, policy, dimensions);

    final policyFp = _serializer.policyFingerprint(policy);
    final dimFps = dimensions
        .map((d) => '${d.dimensionId}:${d.normalizedScore ?? 'na'}:${d.weight}')
        .toList()
      ..sort();

    final fingerprint = _serializer.scoreFingerprint(
      projectId: request.projectId,
      policyId: policy.policyId,
      policyVersion: policy.policyVersion,
      policyFingerprint: policyFp,
      metricsSnapshotId: metricsSnapshot.metadata.snapshotId,
      historyDiffFingerprint: historyDiff == null
          ? null
          : _serializer.fingerprintFromString(
              '${historyDiff.fromSnapshotId}|${historyDiff.toSnapshotId}',
            ),
      guardianFingerprint: request.guardianAnalysis == null
          ? null
          : _serializer.fingerprintFromString(
              request.guardianAnalysis!['decision']?.toString() ?? '',
            ),
      overallScore:
          overallScore.value.toStringAsFixed(policy.scoreScale.precision),
      dimensionFingerprints: dimFps,
    );

    final snapshotId = _idFactory.create(
      projectId: request.projectId,
      policyId: policy.policyId,
      policyVersion: policy.policyVersion,
      scoreFingerprint: fingerprint,
    );

    final ruleCount = dimensions.fold<int>(0, (sum, d) => sum + d.rules.length);

    final metadata = ScoreMetadata(
      scoreSnapshotId: snapshotId,
      scoreSchemaVersion: ScoreMetadata.currentSchemaVersion,
      scoreCalculationVersion: ScoreMetadata.currentCalculationVersion,
      scoreCanonicalizationVersion:
          ScoreMetadata.currentCanonicalizationVersion,
      projectId: request.projectId,
      policyId: policy.policyId,
      policyVersion: policy.policyVersion,
      sourceMetricsSnapshotId: metricsSnapshot.metadata.snapshotId,
      createdAt: request.createdAt,
      scoreFingerprint: fingerprint,
      status: status,
      confidence: confidence,
      compatibilityStatus: compatibility,
      dimensionCount: dimensions.length,
      ruleCount: ruleCount,
      warningCount: warnings.length,
      errorCount: errors.length,
      sourceHistoryDiffId: historyDiff == null
          ? null
          : '${historyDiff.fromSnapshotId}|${historyDiff.toSnapshotId}',
      gitRef: request.gitRef,
      branch: request.branch,
      sourceEventId: request.sourceEventId,
    );

    final snapshotWithoutExplanation = EngineeringScoreSnapshot(
      metadata: metadata,
      overallScore: overallScore,
      dimensions: dimensions,
      coverage: coverage,
      explanation: const ScoreExplanation(
        summary: '',
        policySummary: '',
        dimensionSummaries: [],
        limitations: [],
      ),
      warnings: warnings,
      errors: errors,
    );

    final snapshot = EngineeringScoreSnapshot(
      metadata: metadata,
      overallScore: overallScore,
      dimensions: dimensions,
      coverage: coverage,
      explanation: request.includeExplanations
          ? _explanationBuilder.build(
              policy: policy,
              snapshot: snapshotWithoutExplanation,
              includeTrace: request.includeTrace,
            )
          : const ScoreExplanation(
              summary: 'Explanations disabled',
              policySummary: '',
              dimensionSummaries: [],
              limitations: [],
            ),
      warnings: warnings,
      errors: errors,
    );

    final validation = _validator.validate(snapshot);
    if (!validation.isValid) {
      throw ScoreValidationException(validation.errors.join('; '));
    }

    return ScoreResult(
      status: status,
      snapshot: snapshot,
      warnings: warnings,
      errors: errors,
    );
  }

  ScorePolicy _resolvePolicy(ScoreRequest request) {
    if (request.policy != null) return request.policy!;
    final policyId = request.policyId ?? FoundationReferencePolicy.policyId;
    final policy = _registry.getPolicy(policyId);
    if (policy == null) {
      throw ScorePolicyException('Unknown policy: $policyId');
    }
    return policy;
  }

  ScoreCoverage _buildCoverage(List<ScoreDimensionResult> dimensions) {
    var requested = 0;
    var available = 0;
    var unavailable = 0;
    var used = 0;
    var totalWeight = 0.0;
    var appliedWeight = 0.0;
    final missing = <String>[];

    for (final dim in dimensions) {
      requested += dim.coverage.requestedEvidenceCount;
      available += dim.coverage.availableEvidenceCount;
      unavailable += dim.coverage.unavailableEvidenceCount;
      used += dim.coverage.usedEvidenceCount;
      totalWeight += dim.weight;
      if (dim.availability != ScoreAvailability.unavailable) {
        appliedWeight += dim.weight;
      }
      missing.addAll(dim.coverage.missingMetricIds);
    }

    return ScoreCoverage(
      requestedEvidenceCount: requested,
      availableEvidenceCount: available,
      unavailableEvidenceCount: unavailable,
      usedEvidenceCount: used,
      coveragePercentage: requested == 0 ? 0 : (used / requested) * 100,
      totalConfiguredWeight: totalWeight,
      appliedWeight: appliedWeight,
      excludedWeight: totalWeight - appliedWeight,
      missingMetricIds: missing.toSet().toList()..sort(),
    );
  }

  ScoreConfidence _deriveConfidence(
    ScoreCoverage coverage,
    ScoreCompatibilityStatus compatibility,
  ) {
    if (compatibility == ScoreCompatibilityStatus.incompatible) {
      return ScoreConfidence.incompatible;
    }
    if (coverage.coveragePercentage >= 100) return ScoreConfidence.full;
    if (coverage.coveragePercentage >= 50) return ScoreConfidence.partial;
    if (coverage.coveragePercentage > 0) return ScoreConfidence.insufficient;
    return ScoreConfidence.unknown;
  }

  ScoreStatus _deriveStatus(
    ScoreCoverage coverage,
    ScorePolicy policy,
    List<ScoreDimensionResult> dimensions,
  ) {
    final hasUnavailable = dimensions.any(
      (d) => d.availability == ScoreAvailability.unavailable,
    );
    final hasPartialDimension = dimensions.any(
      (d) => d.availability == ScoreAvailability.partial,
    );
    final hasScoredDimension = dimensions.any(
      (d) =>
          d.normalizedScore != null &&
          d.availability != ScoreAvailability.unavailable,
    );

    if ((hasUnavailable ||
            hasPartialDimension ||
            coverage.excludedWeight > 0) &&
        hasScoredDimension) {
      return ScoreStatus.partial;
    }

    if (coverage.coveragePercentage < policy.minimumEvidenceCoverage) {
      if (policy.missingDataPolicy == ScoreMissingDataPolicy.fail) {
        return ScoreStatus.failure;
      }
      return ScoreStatus.unavailable;
    }

    if (hasUnavailable || hasPartialDimension || coverage.excludedWeight > 0) {
      return ScoreStatus.partial;
    }
    return ScoreStatus.success;
  }
}
