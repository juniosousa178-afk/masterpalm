import '../interfaces/score_provider.dart';
import '../models/mes/mes_enums.dart';
import '../models/mes/mes_policy.dart';
import '../models/mes/mes_request.dart';
import '../models/mes/mes_snapshot.dart';
import '../models/metrics/metrics_snapshot.dart';
import '../models/score/score_request.dart';
import 'mes_compatibility_checker.dart';
import 'mes_exceptions.dart';
import 'mes_policy_validator.dart';
import 'mes_registry.dart';
import 'mes_score_policy_mapper.dart';
import 'mes_snapshot_mapper.dart';
import 'mes_validator.dart';
import 'policies/mes_official_policy_v1.dart';

/// Thin orchestrator that applies official MES policy via Score Engine.
class MESEngine {
  MESEngine({
    required MESPolicyRegistry registry,
    required ScoreProvider scoreProvider,
    MESPolicyValidator? policyValidator,
    MESValidator? validator,
    MESCompatibilityChecker? compatibilityChecker,
    MESScorePolicyMapper? policyMapper,
    MESSnapshotMapper? snapshotMapper,
  })  : _registry = registry,
        _scoreProvider = scoreProvider,
        _policyValidator = policyValidator ?? const MESPolicyValidator(),
        _validator = validator ?? const MESValidator(),
        _compatibilityChecker =
            compatibilityChecker ?? const MESCompatibilityChecker(),
        _policyMapper = policyMapper ?? const MESScorePolicyMapper(),
        _snapshotMapper = snapshotMapper ?? const MESSnapshotMapper();

  final MESPolicyRegistry _registry;
  final ScoreProvider _scoreProvider;
  final MESPolicyValidator _policyValidator;
  final MESValidator _validator;
  final MESCompatibilityChecker _compatibilityChecker;
  final MESScorePolicyMapper _policyMapper;
  final MESSnapshotMapper _snapshotMapper;

  Future<MESResult> calculate(MESRequest request) async {
    if (request.projectId.isEmpty) {
      throw MESValidationException('projectId is required');
    }
    if (request.createdAt.isEmpty) {
      throw MESValidationException('createdAt is required');
    }
    if (request.metricsSnapshot.isEmpty) {
      throw MESValidationException('metricsSnapshot is required');
    }

    final policy = _resolvePolicy(request);
    final policyValidation = _policyValidator.validate(policy);
    if (!policyValidation.isValid) {
      throw MESPolicyException(policyValidation.errors.join('; '));
    }

    if (!request.allowedPolicyStatuses.contains(policy.metadata.status)) {
      throw MESPolicyException(
        'Policy status ${policy.metadata.status.wireName} not allowed',
      );
    }

    final metricsSnapshot = MetricsSnapshot.fromJson(request.metricsSnapshot);
    final compatibility = _compatibilityChecker.check(
      policy: policy,
      metricsSnapshot: metricsSnapshot,
      strict: request.strictCompatibility,
    );

    if (request.strictCompatibility &&
        compatibility == MESCompatibilityStatus.incompatible) {
      return MESResult(
        status: MESStatus.incompatible,
        eligibility: const MESEligibility(
          status: MESEligibilityStatus.incompatible,
          reasons: ['Strict compatibility failed'],
          missingRequiredDimensions: [],
          missingOptionalDimensions: [],
        ),
        errors: [
          const MESError(
            code: 'compatibility',
            message: 'Strict compatibility failed',
          ),
        ],
      );
    }

    final scorePolicy = _policyMapper.toScorePolicy(policy);
    final scoreRequest = ScoreRequest(
      projectId: request.projectId,
      createdAt: request.createdAt,
      metricsSnapshot: request.metricsSnapshot,
      policy: scorePolicy,
      policyId: policy.policyId,
      guardianAnalysis: request.guardianAnalysis,
      historyDiff: request.historyDiff,
      historySnapshot: request.historySnapshot,
      gitRef: request.gitRef,
      branch: request.branch,
      sourceEventId: request.sourceEventId,
      requestedDimensions: request.requestedDimensions,
      strictCompatibility: request.strictCompatibility,
      includeTrace: request.includeTrace,
      includeExplanations: request.includeExplanations,
    );

    final scoreResult = await _scoreProvider.calculate(scoreRequest);

    final historyDiffId = request.historyDiff == null
        ? null
        : '${request.historyDiff!['fromSnapshotId']}|${request.historyDiff!['toSnapshotId']}';

    final snapshot = _snapshotMapper.map(
      policy: policy,
      scoreSnapshot: scoreResult.snapshot,
      projectId: request.projectId,
      createdAt: request.createdAt,
      compatibility: compatibility,
      includeExplanations: request.includeExplanations,
      includeTrace: request.includeTrace,
      gitRef: request.gitRef,
      branch: request.branch,
      sourceHistoryDiffId: historyDiffId,
      sourceHistorySnapshotId:
          request.historySnapshot?['snapshotId'] as String?,
    );

    final validation = _validator.validate(snapshot);
    if (!validation.isValid) {
      throw MESValidationException(validation.errors.join('; '));
    }

    if (request.eligibilityOnly) {
      return MESResult(
        status: snapshot.metadata.status,
        eligibility: snapshot.eligibility,
        warnings: snapshot.warnings,
      );
    }

    return MESResult(
      status: snapshot.metadata.status,
      eligibility: snapshot.eligibility,
      snapshot: snapshot,
      warnings: snapshot.warnings,
    );
  }

  Future<MESEligibility> checkEligibility(MESRequest request) async {
    final result = await calculate(
      MESRequest(
        projectId: request.projectId,
        createdAt: request.createdAt,
        metricsSnapshot: request.metricsSnapshot,
        policyId: request.policyId,
        policy: request.policy,
        guardianAnalysis: request.guardianAnalysis,
        historyDiff: request.historyDiff,
        historySnapshot: request.historySnapshot,
        gitRef: request.gitRef,
        branch: request.branch,
        sourceEventId: request.sourceEventId,
        requestedDimensions: request.requestedDimensions,
        strictCompatibility: request.strictCompatibility,
        includeTrace: request.includeTrace,
        includeExplanations: request.includeExplanations,
        eligibilityOnly: true,
        allowedPolicyStatuses: request.allowedPolicyStatuses,
      ),
    );
    return result.eligibility;
  }

  MESPolicy _resolvePolicy(MESRequest request) {
    if (request.policy != null) return request.policy!;
    final policyId = request.policyId ?? MesOfficialPolicyV1.policyId;
    final policy = _registry.getPolicy(policyId);
    if (policy == null) {
      throw MESPolicyException('Unknown MES policy: $policyId');
    }
    return policy;
  }
}
