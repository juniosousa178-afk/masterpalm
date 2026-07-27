import '../interfaces/release_supply_chain_provider.dart';
import '../models/release_supply_chain/release_supply_chain_messages.dart';
import '../models/release_supply_chain/release_supply_chain_operational_enums.dart';
import '../models/release_supply_chain/release_supply_chain_policy_models.dart';
import '../models/release_supply_chain/release_supply_chain_query.dart';
import '../models/release_supply_chain/release_supply_chain_request.dart';
import '../models/release_supply_chain/release_supply_chain_result.dart';
import '../models/release_supply_chain/release_supply_chain_snapshot.dart';
import '../release_supply_chain/policies/compliance_policy_v1.dart';
import '../release_supply_chain/policies/distribution_policy_v1.dart';
import '../release_supply_chain/policies/supply_chain_policy_v1.dart';
import '../release_supply_chain/release_supply_chain_collector.dart';
import '../release_supply_chain/release_supply_chain_exceptions.dart';
import '../release_supply_chain/release_supply_chain_policy_registry.dart';
import '../release_supply_chain/release_supply_chain_snapshot_builder.dart';
import '../release_supply_chain/release_supply_chain_snapshot_validator.dart';
import '../release_supply_chain/release_supply_chain_source_resolver.dart';
import '../release_supply_chain/resolved_release_supply_chain_sources.dart';
import '../release_supply_chain/stores/release_supply_chain_store.dart';

/// Platform implementation of [ReleaseSupplyChainProvider].
class PlatformReleaseSupplyChainProvider implements ReleaseSupplyChainProvider {
  PlatformReleaseSupplyChainProvider({
    required ReleaseSupplyChainSourceResolver sourceResolver,
    required SupplyChainPolicyRegistry supplyChainPolicyRegistry,
    required DistributionPolicyRegistry distributionPolicyRegistry,
    required CompliancePolicyRegistry compliancePolicyRegistry,
    required ReleaseSupplyChainStore store,
    ReleaseSupplyChainCollector? collector,
    ReleaseSupplyChainSnapshotBuilder? snapshotBuilder,
    ReleaseSupplyChainSnapshotValidator? snapshotValidator,
  })  : _sourceResolver = sourceResolver,
        _supplyChainPolicyRegistry = supplyChainPolicyRegistry,
        _distributionPolicyRegistry = distributionPolicyRegistry,
        _compliancePolicyRegistry = compliancePolicyRegistry,
        _store = store,
        _collector = collector ?? const ReleaseSupplyChainCollector(),
        _snapshotBuilder =
            snapshotBuilder ?? ReleaseSupplyChainSnapshotBuilder(),
        _snapshotValidator =
            snapshotValidator ?? const ReleaseSupplyChainSnapshotValidator();

  final ReleaseSupplyChainSourceResolver _sourceResolver;
  final SupplyChainPolicyRegistry _supplyChainPolicyRegistry;
  final DistributionPolicyRegistry _distributionPolicyRegistry;
  final CompliancePolicyRegistry _compliancePolicyRegistry;
  final ReleaseSupplyChainStore _store;
  final ReleaseSupplyChainCollector _collector;
  final ReleaseSupplyChainSnapshotBuilder _snapshotBuilder;
  final ReleaseSupplyChainSnapshotValidator _snapshotValidator;

  @override
  Future<ReleaseSupplyChainResult> evaluate(
    ReleaseSupplyChainRequest request,
  ) async {
    final supplyChainPolicy = _resolveSupplyChainPolicy(request);
    if (supplyChainPolicy == null) {
      throw ReleaseSupplyChainPolicyNotFoundException(
        request.supplyChainPolicyId ?? SupplyChainPolicyV1.policyId,
        policyVersion: request.supplyChainPolicyVersion,
      );
    }

    final distributionPolicy = _resolveDistributionPolicy(request);
    if (distributionPolicy == null) {
      throw ReleaseSupplyChainPolicyNotFoundException(
        request.distributionPolicyId ?? DistributionPolicyV1.policyId,
        policyVersion: request.distributionPolicyVersion,
      );
    }

    final compliancePolicy = _resolveCompliancePolicy(request);
    if (compliancePolicy == null) {
      throw ReleaseSupplyChainPolicyNotFoundException(
        request.compliancePolicyId ?? CompliancePolicyV1.policyId,
        policyVersion: request.compliancePolicyVersion,
      );
    }

    final sources = await _sourceResolver.resolveAll(
      request,
      injectedSupplyChainPolicy: supplyChainPolicy,
      injectedDistributionPolicy: distributionPolicy,
      injectedCompliancePolicy: compliancePolicy,
    );

    return _evaluatePipeline(
      request: request,
      sources: sources,
      supplyChainPolicy: supplyChainPolicy,
      distributionPolicy: distributionPolicy,
      compliancePolicy: compliancePolicy,
    );
  }

  @override
  Future<ReleaseSupplyChainResult> evaluateAndPublish(
    ReleaseSupplyChainRequest request,
  ) async {
    final result = await evaluate(request);
    final snapshot = result.snapshot;
    if (snapshot == null) return result;

    final validation = _snapshotValidator.validate(snapshot);
    if (!validation.isValid) {
      return ReleaseSupplyChainResult(
        status: ReleaseSupplyChainResultStatus.failure,
        snapshot: snapshot,
        policyReference: result.policyReference,
        warnings: result.warnings,
        errors: [
          ...result.errors,
          ...validation.errors.map(
            (e) => ReleaseSupplyChainError(
              errorId: 'validation-${e.hashCode}',
              code: 'snapshot-validation',
              message: e,
            ),
          ),
        ],
        limitations: result.limitations,
        sourceResolutionSummary: result.sourceResolutionSummary,
      );
    }

    final existing = await _store.load(snapshot.metadata.supplyChainSnapshotId);
    if (existing != null) {
      return ReleaseSupplyChainResult(
        status: result.status,
        snapshot: existing,
        policyReference: result.policyReference,
        warnings: result.warnings,
        errors: result.errors,
        limitations: result.limitations,
        sourceResolutionSummary: result.sourceResolutionSummary,
        publicationStatus: ReleaseSupplyChainPublicationStatus.skipped.wireName,
      );
    }

    await _store.save(snapshot);
    final saved = await _store.load(snapshot.metadata.supplyChainSnapshotId);
    return ReleaseSupplyChainResult(
      status: result.status,
      snapshot: saved ?? snapshot,
      policyReference: result.policyReference,
      warnings: result.warnings,
      errors: result.errors,
      limitations: result.limitations,
      sourceResolutionSummary: result.sourceResolutionSummary,
      publicationStatus: ReleaseSupplyChainPublicationStatus.published.wireName,
    );
  }

  @override
  Future<void> publish(ReleaseSupplyChainSnapshot snapshot) async {
    await _store.save(snapshot);
  }

  @override
  Future<ReleaseSupplyChainSnapshot?> load(String snapshotId) {
    return _store.load(snapshotId);
  }

  @override
  Future<ReleaseSupplyChainSnapshot?> latest({
    required String projectId,
    String? releaseId,
    String? supplyChainPolicyId,
  }) {
    return _store.latest(
      projectId: projectId,
      releaseId: releaseId,
      supplyChainPolicyId: supplyChainPolicyId,
    );
  }

  @override
  Future<List<ReleaseSupplyChainSnapshot>> query(
    ReleaseSupplyChainQuery query,
  ) {
    return _store.query(query);
  }

  @override
  Future<void> invalidate(String snapshotId) async {
    if (!await _store.exists(snapshotId)) {
      throw ReleaseSupplyChainNotFoundException(snapshotId);
    }
    await _store.invalidate(snapshotId);
  }

  Future<ReleaseSupplyChainResult> _evaluatePipeline({
    required ReleaseSupplyChainRequest request,
    required ResolvedReleaseSupplyChainSources sources,
    required RegisteredSupplyChainPolicy supplyChainPolicy,
    required RegisteredDistributionPolicy distributionPolicy,
    required RegisteredCompliancePolicy compliancePolicy,
  }) async {
    final context = ReleaseSupplyChainEvaluationContext(
      request: request,
      sources: sources,
      supplyChainPolicy: supplyChainPolicy,
      distributionPolicy: distributionPolicy,
      compliancePolicy: compliancePolicy,
    );

    final collected = _collector.collect(context);
    final buildResult = _snapshotBuilder.build(
      context: context,
      collected: collected,
      evaluatedAt: request.referenceTime,
    );
    final snapshot = buildResult.snapshot;

    final validation = _snapshotValidator.validate(snapshot);

    final warnings = <ReleaseSupplyChainWarning>[
      ...sources.warnings,
      ...validation.warnings.map(
        (w) => ReleaseSupplyChainWarning(
          warningId: 'validation-${w.hashCode}',
          code: 'snapshot-validation',
          message: w,
        ),
      ),
    ];
    final errors = <ReleaseSupplyChainError>[
      ...sources.errors,
      ...validation.errors.map(
        (e) => ReleaseSupplyChainError(
          errorId: 'validation-${e.hashCode}',
          code: 'snapshot-validation',
          message: e,
        ),
      ),
    ];
    final limitations = <ReleaseSupplyChainLimitation>[
      ...sources.limitations,
    ];

    var status = ReleaseSupplyChainResultStatus.success;
    if (errors.isNotEmpty) {
      status = ReleaseSupplyChainResultStatus.failure;
    } else if (limitations.isNotEmpty || warnings.isNotEmpty) {
      status = ReleaseSupplyChainResultStatus.partial;
    }
    if (collected.artifacts.isEmpty) {
      status = ReleaseSupplyChainResultStatus.unavailable;
    }

    return ReleaseSupplyChainResult(
      status: status,
      snapshot: snapshot,
      policyReference: buildResult.policyReference,
      sourceResolutionSummary: sources.resolutionSummary,
      warnings: warnings,
      errors: errors,
      limitations: limitations,
    );
  }

  RegisteredSupplyChainPolicy? _resolveSupplyChainPolicy(
    ReleaseSupplyChainRequest request,
  ) {
    final policyId =
        request.supplyChainPolicyId ?? SupplyChainPolicyV1.policyId;
    return _supplyChainPolicyRegistry.resolve(
      policyId: policyId,
      policyVersion: request.supplyChainPolicyVersion,
      allowCandidate: true,
    );
  }

  RegisteredDistributionPolicy? _resolveDistributionPolicy(
    ReleaseSupplyChainRequest request,
  ) {
    final policyId =
        request.distributionPolicyId ?? DistributionPolicyV1.policyId;
    return _distributionPolicyRegistry.resolve(
      policyId: policyId,
      policyVersion: request.distributionPolicyVersion,
      allowCandidate: true,
    );
  }

  RegisteredCompliancePolicy? _resolveCompliancePolicy(
    ReleaseSupplyChainRequest request,
  ) {
    final policyId = request.compliancePolicyId ?? CompliancePolicyV1.policyId;
    return _compliancePolicyRegistry.resolve(
      policyId: policyId,
      policyVersion: request.compliancePolicyVersion,
      allowCandidate: true,
    );
  }
}
