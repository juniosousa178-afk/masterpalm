import '../interfaces/quality_gate_provider.dart';
import '../interfaces/release_evidence_provider.dart';
import '../interfaces/release_governance_provider.dart';
import '../models/quality_gate/quality_gate_snapshot.dart';
import '../models/release_evidence/release_evidence_bundle.dart';
import '../models/release_governance/release_context.dart';
import '../models/release_governance/release_decision_snapshot.dart';
import '../models/release_supply_chain/release_supply_chain_messages.dart';
import '../models/release_supply_chain/release_supply_chain_operational_enums.dart';
import '../models/release_supply_chain/release_supply_chain_policy_models.dart';
import '../models/release_supply_chain/release_supply_chain_request.dart';
import '../models/release_supply_chain/release_supply_chain_result.dart';
import 'policies/compliance_policy_v1.dart';
import 'policies/distribution_policy_v1.dart';
import 'policies/supply_chain_policy_v1.dart';
import 'release_supply_chain_canonical_serializer.dart';
import 'release_supply_chain_policy_registry.dart';
import 'resolved_release_supply_chain_sources.dart';

/// Resolves release supply chain source artifacts without executing origin engines.
class ReleaseSupplyChainSourceResolver {
  ReleaseSupplyChainSourceResolver({
    required QualityGateProvider qualityGateProvider,
    required ReleaseGovernanceProvider releaseGovernanceProvider,
    required ReleaseEvidenceProvider releaseEvidenceProvider,
    SupplyChainPolicyRegistry? supplyChainPolicyRegistry,
    DistributionPolicyRegistry? distributionPolicyRegistry,
    CompliancePolicyRegistry? compliancePolicyRegistry,
    ReleaseSupplyChainCanonicalSerializer? serializer,
  })  : _qualityGateProvider = qualityGateProvider,
        _releaseGovernanceProvider = releaseGovernanceProvider,
        _releaseEvidenceProvider = releaseEvidenceProvider,
        _supplyChainPolicyRegistry =
            supplyChainPolicyRegistry ?? SupplyChainPolicyRegistry(),
        _distributionPolicyRegistry =
            distributionPolicyRegistry ?? DistributionPolicyRegistry(),
        _compliancePolicyRegistry =
            compliancePolicyRegistry ?? CompliancePolicyRegistry(),
        _serializer =
            serializer ?? const ReleaseSupplyChainCanonicalSerializer();

  final QualityGateProvider _qualityGateProvider;
  final ReleaseGovernanceProvider _releaseGovernanceProvider;
  final ReleaseEvidenceProvider _releaseEvidenceProvider;
  final SupplyChainPolicyRegistry _supplyChainPolicyRegistry;
  final DistributionPolicyRegistry _distributionPolicyRegistry;
  final CompliancePolicyRegistry _compliancePolicyRegistry;
  final ReleaseSupplyChainCanonicalSerializer _serializer;

  Future<ResolvedReleaseSupplyChainSources> resolveAll(
    ReleaseSupplyChainRequest request, {
    RegisteredSupplyChainPolicy? injectedSupplyChainPolicy,
    RegisteredDistributionPolicy? injectedDistributionPolicy,
    RegisteredCompliancePolicy? injectedCompliancePolicy,
  }) async {
    final refs = <ReleaseSupplyChainSourceReference>[];
    final warnings = <ReleaseSupplyChainWarning>[];
    final errors = <ReleaseSupplyChainError>[];
    final limitations = <ReleaseSupplyChainLimitation>[];
    final hints = <String>[];

    final resolved = <String>[];
    final unresolved = <String>[];
    final injected = <String>[];

    final releaseContext = resolveReleaseContext(request, refs);
    _trackResolution(releaseContext, resolved, unresolved, injected);

    final qualityGate = await resolveQualityGateSnapshot(
      request,
      refs,
      limitations,
    );
    _trackResolution(qualityGate, resolved, unresolved, injected);

    final releaseDecision = await resolveReleaseDecisionSnapshot(
      request,
      refs,
      limitations,
    );
    _trackResolution(releaseDecision, resolved, unresolved, injected);

    final evidenceBundle = await resolveReleaseEvidenceBundle(
      request,
      refs,
      limitations,
    );
    _trackResolution(evidenceBundle, resolved, unresolved, injected);

    final supplyChainPolicy = resolveSupplyChainPolicy(
      request,
      refs,
      injectedSupplyChainPolicy,
      limitations,
    );
    _trackResolution(supplyChainPolicy, resolved, unresolved, injected);

    final distributionPolicy = resolveDistributionPolicy(
      request,
      refs,
      injectedDistributionPolicy,
      limitations,
    );
    _trackResolution(distributionPolicy, resolved, unresolved, injected);

    final compliancePolicy = resolveCompliancePolicy(
      request,
      refs,
      injectedCompliancePolicy,
      limitations,
    );
    _trackResolution(compliancePolicy, resolved, unresolved, injected);

    _checkProjectMismatch(request, qualityGate, hints, limitations);
    _checkCommitMismatch(
        request, qualityGate, releaseDecision, hints, limitations);

    refs.sort(
      (a, b) => a.sourceType.compareTo(b.sourceType),
    );

    final summary = ReleaseSupplyChainSourceResolutionSummary(
      resolvedSources: resolved,
      unresolvedSources: unresolved,
      injectedSources: injected,
      fingerprint: _serializer.sourceReferencesFingerprint(refs),
    );

    return ResolvedReleaseSupplyChainSources(
      releaseContext: releaseContext,
      qualityGateSnapshot: qualityGate,
      releaseDecisionSnapshot: releaseDecision,
      releaseEvidenceBundle: evidenceBundle,
      supplyChainPolicy: supplyChainPolicy,
      distributionPolicy: distributionPolicy,
      compliancePolicy: compliancePolicy,
      sourceReferences: refs,
      resolutionSummary: summary,
      warnings: warnings,
      errors: errors,
      limitations: limitations,
      compatibilityHints: hints,
    );
  }

  ResolvedReleaseSupplyChainSource<ReleaseContext> resolveReleaseContext(
    ReleaseSupplyChainRequest request,
    List<ReleaseSupplyChainSourceReference> refs,
  ) {
    final context = request.releaseContext;
    refs.add(
      ReleaseSupplyChainSourceReference(
        sourceType: ReleaseSupplyChainSourceType.releaseContext.wireName,
        resolutionMode:
            ReleaseSupplyChainSourceResolutionMode.injected.wireName,
        requestedId: context.releaseId,
        resolvedId: context.releaseId,
        fingerprint: context.releaseId,
        projectId: context.projectId,
        commitId: context.commitId,
      ),
    );
    return ResolvedReleaseSupplyChainSource<ReleaseContext>(
      sourceType: ReleaseSupplyChainSourceType.releaseContext,
      resolutionMode: ReleaseSupplyChainSourceResolutionMode.injected,
      state: ReleaseSupplyChainSourceState.available,
      resolvedArtifact: context,
      resolvedId: context.releaseId,
      fingerprint: context.releaseId,
      projectId: context.projectId,
      commitId: context.commitId,
    );
  }

  Future<ResolvedReleaseSupplyChainSource<QualityGateSnapshot>>
      resolveQualityGateSnapshot(
    ReleaseSupplyChainRequest request,
    List<ReleaseSupplyChainSourceReference> refs,
    List<ReleaseSupplyChainLimitation> limitations,
  ) async {
    if (request.qualityGateSnapshot != null) {
      final snapshot = request.qualityGateSnapshot!;
      refs.add(
          _qgRef(snapshot, ReleaseSupplyChainSourceResolutionMode.injected));
      return _availableQg(snapshot, refs.last);
    }
    if (request.qualityGateSnapshotId != null) {
      final loaded = await _qualityGateProvider.load(
        request.qualityGateSnapshotId!,
      );
      if (loaded != null) {
        refs.add(_qgRef(loaded, ReleaseSupplyChainSourceResolutionMode.byId));
        return _availableQg(loaded, refs.last);
      }
      refs.add(_unavailableRef(
        ReleaseSupplyChainSourceType.qualityGate,
        request.qualityGateSnapshotId!,
        ReleaseSupplyChainSourceResolutionMode.byId,
      ));
      limitations.add(
        const ReleaseSupplyChainLimitation(
          limitationId: 'missing-quality-gate',
          code: 'no-physical-persistence',
          description: 'Quality gate snapshot unavailable by ID',
          impact: 'Quality gate evidence may be unavailable',
        ),
      );
      return _unavailableQg(request.qualityGateSnapshotId);
    }
    if (request.useLatest) {
      final loaded = await _qualityGateProvider.latest(
        projectId: request.releaseContext.projectId,
      );
      if (loaded != null) {
        refs.add(_qgRef(loaded, ReleaseSupplyChainSourceResolutionMode.latest));
        return _availableQg(loaded, refs.last);
      }
      limitations.add(
        const ReleaseSupplyChainLimitation(
          limitationId: 'latest-quality-gate-missing',
          code: 'no-physical-persistence',
          description: 'Latest quality gate snapshot unavailable',
          impact: 'Quality gate evidence may be unavailable',
        ),
      );
    }
    return _notRequestedQg();
  }

  Future<ResolvedReleaseSupplyChainSource<ReleaseDecisionSnapshot>>
      resolveReleaseDecisionSnapshot(
    ReleaseSupplyChainRequest request,
    List<ReleaseSupplyChainSourceReference> refs,
    List<ReleaseSupplyChainLimitation> limitations,
  ) async {
    if (request.releaseDecisionSnapshot != null) {
      final snapshot = request.releaseDecisionSnapshot!;
      refs.add(
          _rgRef(snapshot, ReleaseSupplyChainSourceResolutionMode.injected));
      return _availableRg(snapshot, refs.last);
    }
    if (request.releaseDecisionSnapshotId != null) {
      final loaded = await _releaseGovernanceProvider.load(
        request.releaseDecisionSnapshotId!,
      );
      if (loaded != null) {
        refs.add(_rgRef(loaded, ReleaseSupplyChainSourceResolutionMode.byId));
        return _availableRg(loaded, refs.last);
      }
      refs.add(_unavailableRef(
        ReleaseSupplyChainSourceType.releaseGovernance,
        request.releaseDecisionSnapshotId!,
        ReleaseSupplyChainSourceResolutionMode.byId,
      ));
      limitations.add(
        const ReleaseSupplyChainLimitation(
          limitationId: 'missing-release-decision',
          code: 'no-physical-persistence',
          description: 'Release decision snapshot unavailable by ID',
          impact: 'Release governance evidence may be unavailable',
        ),
      );
      return _unavailableRg(request.releaseDecisionSnapshotId);
    }
    if (request.useLatest) {
      final loaded = await _releaseGovernanceProvider.latest(
        projectId: request.releaseContext.projectId,
        releaseId: request.releaseContext.releaseId,
      );
      if (loaded != null) {
        refs.add(_rgRef(loaded, ReleaseSupplyChainSourceResolutionMode.latest));
        return _availableRg(loaded, refs.last);
      }
      limitations.add(
        const ReleaseSupplyChainLimitation(
          limitationId: 'latest-release-decision-missing',
          code: 'no-physical-persistence',
          description: 'Latest release decision snapshot unavailable',
          impact: 'Release governance evidence may be unavailable',
        ),
      );
    }
    return _notRequestedRg();
  }

  Future<ResolvedReleaseSupplyChainSource<ReleaseEvidenceBundle>>
      resolveReleaseEvidenceBundle(
    ReleaseSupplyChainRequest request,
    List<ReleaseSupplyChainSourceReference> refs,
    List<ReleaseSupplyChainLimitation> limitations,
  ) async {
    if (request.releaseEvidenceBundle != null) {
      final bundle = request.releaseEvidenceBundle!;
      refs.add(_reRef(bundle, ReleaseSupplyChainSourceResolutionMode.injected));
      return _availableRe(bundle, refs.last);
    }
    if (request.releaseEvidenceBundleId != null) {
      final loaded = await _releaseEvidenceProvider.load(
        request.releaseEvidenceBundleId!,
      );
      if (loaded != null) {
        refs.add(_reRef(loaded, ReleaseSupplyChainSourceResolutionMode.byId));
        return _availableRe(loaded, refs.last);
      }
      refs.add(_unavailableRef(
        ReleaseSupplyChainSourceType.releaseEvidence,
        request.releaseEvidenceBundleId!,
        ReleaseSupplyChainSourceResolutionMode.byId,
      ));
      limitations.add(
        const ReleaseSupplyChainLimitation(
          limitationId: 'missing-evidence-bundle',
          code: 'no-physical-persistence',
          description: 'Release evidence bundle unavailable by ID',
          impact: 'Supply chain provenance may be incomplete',
        ),
      );
      return _unavailableRe(request.releaseEvidenceBundleId);
    }
    if (request.useLatest) {
      final loaded = await _releaseEvidenceProvider.latest(
        projectId: request.releaseContext.projectId,
        releaseId: request.releaseContext.releaseId,
      );
      if (loaded != null) {
        refs.add(_reRef(loaded, ReleaseSupplyChainSourceResolutionMode.latest));
        return _availableRe(loaded, refs.last);
      }
      limitations.add(
        const ReleaseSupplyChainLimitation(
          limitationId: 'latest-evidence-bundle-missing',
          code: 'no-physical-persistence',
          description: 'Latest release evidence bundle unavailable',
          impact: 'Supply chain provenance may be incomplete',
        ),
      );
    }
    return _notRequestedRe();
  }

  ResolvedReleaseSupplyChainSource<RegisteredSupplyChainPolicy>
      resolveSupplyChainPolicy(
    ReleaseSupplyChainRequest request,
    List<ReleaseSupplyChainSourceReference> refs,
    RegisteredSupplyChainPolicy? injectedPolicy,
    List<ReleaseSupplyChainLimitation> limitations,
  ) {
    if (injectedPolicy != null) {
      return _resolvedSupplyChainPolicy(
        policy: injectedPolicy,
        mode: ReleaseSupplyChainSourceResolutionMode.injected,
        refs: refs,
      );
    }
    final policyId =
        request.supplyChainPolicyId ?? SupplyChainPolicyV1.policyId;
    final policy = _supplyChainPolicyRegistry.resolve(
      policyId: policyId,
      policyVersion: request.supplyChainPolicyVersion,
      allowCandidate: true,
    );
    if (policy != null) {
      return _resolvedSupplyChainPolicy(
        policy: policy,
        mode: ReleaseSupplyChainSourceResolutionMode.byId,
        refs: refs,
      );
    }
    limitations.add(
      ReleaseSupplyChainLimitation(
        limitationId: 'missing-supply-chain-policy',
        code: 'no-physical-persistence',
        description: 'Supply chain policy $policyId unavailable',
        impact: 'Supply chain collection cannot proceed',
      ),
    );
    return _unavailablePolicy<RegisteredSupplyChainPolicy>(
      ReleaseSupplyChainSourceType.supplyChainPolicy,
      policyId,
    );
  }

  ResolvedReleaseSupplyChainSource<RegisteredDistributionPolicy>
      resolveDistributionPolicy(
    ReleaseSupplyChainRequest request,
    List<ReleaseSupplyChainSourceReference> refs,
    RegisteredDistributionPolicy? injectedPolicy,
    List<ReleaseSupplyChainLimitation> limitations,
  ) {
    if (injectedPolicy != null) {
      return _resolvedDistributionPolicy(
        policy: injectedPolicy,
        mode: ReleaseSupplyChainSourceResolutionMode.injected,
        refs: refs,
      );
    }
    final policyId =
        request.distributionPolicyId ?? DistributionPolicyV1.policyId;
    final policy = _distributionPolicyRegistry.resolve(
      policyId: policyId,
      policyVersion: request.distributionPolicyVersion,
      allowCandidate: true,
    );
    if (policy != null) {
      return _resolvedDistributionPolicy(
        policy: policy,
        mode: ReleaseSupplyChainSourceResolutionMode.byId,
        refs: refs,
      );
    }
    limitations.add(
      ReleaseSupplyChainLimitation(
        limitationId: 'missing-distribution-policy',
        code: 'no-physical-persistence',
        description: 'Distribution policy $policyId unavailable',
        impact: 'Distribution assembly may be limited',
      ),
    );
    return _unavailablePolicy<RegisteredDistributionPolicy>(
      ReleaseSupplyChainSourceType.distributionPolicy,
      policyId,
    );
  }

  ResolvedReleaseSupplyChainSource<RegisteredCompliancePolicy>
      resolveCompliancePolicy(
    ReleaseSupplyChainRequest request,
    List<ReleaseSupplyChainSourceReference> refs,
    RegisteredCompliancePolicy? injectedPolicy,
    List<ReleaseSupplyChainLimitation> limitations,
  ) {
    if (injectedPolicy != null) {
      return _resolvedCompliancePolicy(
        policy: injectedPolicy,
        mode: ReleaseSupplyChainSourceResolutionMode.injected,
        refs: refs,
      );
    }
    final policyId = request.compliancePolicyId ?? CompliancePolicyV1.policyId;
    final policy = _compliancePolicyRegistry.resolve(
      policyId: policyId,
      policyVersion: request.compliancePolicyVersion,
      allowCandidate: true,
    );
    if (policy != null) {
      return _resolvedCompliancePolicy(
        policy: policy,
        mode: ReleaseSupplyChainSourceResolutionMode.byId,
        refs: refs,
      );
    }
    limitations.add(
      ReleaseSupplyChainLimitation(
        limitationId: 'missing-compliance-policy',
        code: 'no-physical-persistence',
        description: 'Compliance policy $policyId unavailable',
        impact: 'Compliance evaluation may be limited',
      ),
    );
    return _unavailablePolicy<RegisteredCompliancePolicy>(
      ReleaseSupplyChainSourceType.compliancePolicy,
      policyId,
    );
  }

  void _checkProjectMismatch(
    ReleaseSupplyChainRequest request,
    ResolvedReleaseSupplyChainSource<QualityGateSnapshot> qg,
    List<String> hints,
    List<ReleaseSupplyChainLimitation> limitations,
  ) {
    if (!qg.isAvailable) return;
    final qgProject = qg.resolvedArtifact!.metadata.projectId;
    final expected = request.releaseContext.projectId;
    if (qgProject != expected) {
      hints.add('Project mismatch on qualityGate: $qgProject != $expected');
      limitations.add(
        ReleaseSupplyChainLimitation(
          limitationId: 'project-mismatch-quality-gate',
          code: 'historical-data-incomplete',
          description:
              'Quality gate projectId $qgProject differs from release $expected',
          impact: 'Cross-artifact consistency may be reduced',
        ),
      );
    }
  }

  void _checkCommitMismatch(
    ReleaseSupplyChainRequest request,
    ResolvedReleaseSupplyChainSource<QualityGateSnapshot> qg,
    ResolvedReleaseSupplyChainSource<ReleaseDecisionSnapshot> rg,
    List<String> hints,
    List<ReleaseSupplyChainLimitation> limitations,
  ) {
    final expected = request.releaseContext.commitId;
    if (qg.isAvailable) {
      final qgCommit = qg.resolvedArtifact!.metadata.commitId;
      if (qgCommit != null && qgCommit != expected) {
        hints.add('Commit mismatch on qualityGate: $qgCommit != $expected');
      }
    }
    if (rg.isAvailable) {
      final rgCommit = rg.resolvedArtifact!.metadata.commitId;
      if (rgCommit != expected) {
        hints.add('Commit mismatch on releaseDecision: $rgCommit != $expected');
      }
    }
  }

  void _trackResolution(
    ResolvedReleaseSupplyChainSource<dynamic> source,
    List<String> resolved,
    List<String> unresolved,
    List<String> injected,
  ) {
    final name = source.sourceType.wireName;
    switch (source.resolutionMode) {
      case ReleaseSupplyChainSourceResolutionMode.injected:
        if (source.isAvailable) {
          injected.add(name);
          resolved.add(name);
        }
      case ReleaseSupplyChainSourceResolutionMode.byId:
        if (source.isAvailable) {
          resolved.add(name);
        } else if (source.state != ReleaseSupplyChainSourceState.notRequested) {
          unresolved.add(name);
        }
      case ReleaseSupplyChainSourceResolutionMode.latest:
        if (source.isAvailable) {
          resolved.add(name);
        } else {
          unresolved.add(name);
        }
      case ReleaseSupplyChainSourceResolutionMode.notRequested:
        break;
    }
  }

  ResolvedReleaseSupplyChainSource<RegisteredSupplyChainPolicy>
      _resolvedSupplyChainPolicy({
    required RegisteredSupplyChainPolicy policy,
    required ReleaseSupplyChainSourceResolutionMode mode,
    required List<ReleaseSupplyChainSourceReference> refs,
  }) {
    final fingerprint = policy.metadata.fingerprint ?? policy.metadata.policyId;
    refs.add(
      ReleaseSupplyChainSourceReference(
        sourceType: ReleaseSupplyChainSourceType.supplyChainPolicy.wireName,
        resolutionMode: mode.wireName,
        requestedId: policy.metadata.policyId,
        resolvedId: policy.metadata.policyId,
        fingerprint: fingerprint,
        policyId: policy.metadata.policyId,
        policyVersion: policy.metadata.policyVersion,
      ),
    );
    return ResolvedReleaseSupplyChainSource<RegisteredSupplyChainPolicy>(
      sourceType: ReleaseSupplyChainSourceType.supplyChainPolicy,
      resolutionMode: mode,
      state: ReleaseSupplyChainSourceState.available,
      resolvedArtifact: policy,
      resolvedId: policy.metadata.policyId,
      fingerprint: fingerprint,
      policyId: policy.metadata.policyId,
      policyVersion: policy.metadata.policyVersion,
    );
  }

  ResolvedReleaseSupplyChainSource<RegisteredDistributionPolicy>
      _resolvedDistributionPolicy({
    required RegisteredDistributionPolicy policy,
    required ReleaseSupplyChainSourceResolutionMode mode,
    required List<ReleaseSupplyChainSourceReference> refs,
  }) {
    final fingerprint = policy.metadata.fingerprint ?? policy.metadata.policyId;
    refs.add(
      ReleaseSupplyChainSourceReference(
        sourceType: ReleaseSupplyChainSourceType.distributionPolicy.wireName,
        resolutionMode: mode.wireName,
        requestedId: policy.metadata.policyId,
        resolvedId: policy.metadata.policyId,
        fingerprint: fingerprint,
        policyId: policy.metadata.policyId,
        policyVersion: policy.metadata.policyVersion,
      ),
    );
    return ResolvedReleaseSupplyChainSource<RegisteredDistributionPolicy>(
      sourceType: ReleaseSupplyChainSourceType.distributionPolicy,
      resolutionMode: mode,
      state: ReleaseSupplyChainSourceState.available,
      resolvedArtifact: policy,
      resolvedId: policy.metadata.policyId,
      fingerprint: fingerprint,
      policyId: policy.metadata.policyId,
      policyVersion: policy.metadata.policyVersion,
    );
  }

  ResolvedReleaseSupplyChainSource<RegisteredCompliancePolicy>
      _resolvedCompliancePolicy({
    required RegisteredCompliancePolicy policy,
    required ReleaseSupplyChainSourceResolutionMode mode,
    required List<ReleaseSupplyChainSourceReference> refs,
  }) {
    final fingerprint = policy.metadata.fingerprint ?? policy.metadata.policyId;
    refs.add(
      ReleaseSupplyChainSourceReference(
        sourceType: ReleaseSupplyChainSourceType.compliancePolicy.wireName,
        resolutionMode: mode.wireName,
        requestedId: policy.metadata.policyId,
        resolvedId: policy.metadata.policyId,
        fingerprint: fingerprint,
        policyId: policy.metadata.policyId,
        policyVersion: policy.metadata.policyVersion,
      ),
    );
    return ResolvedReleaseSupplyChainSource<RegisteredCompliancePolicy>(
      sourceType: ReleaseSupplyChainSourceType.compliancePolicy,
      resolutionMode: mode,
      state: ReleaseSupplyChainSourceState.available,
      resolvedArtifact: policy,
      resolvedId: policy.metadata.policyId,
      fingerprint: fingerprint,
      policyId: policy.metadata.policyId,
      policyVersion: policy.metadata.policyVersion,
    );
  }

  ResolvedReleaseSupplyChainSource<QualityGateSnapshot> _availableQg(
    QualityGateSnapshot snapshot,
    ReleaseSupplyChainSourceReference ref,
  ) {
    return ResolvedReleaseSupplyChainSource<QualityGateSnapshot>(
      sourceType: ReleaseSupplyChainSourceType.qualityGate,
      resolutionMode: ReleaseSupplyChainSourceResolutionModeX.fromWireName(
        ref.resolutionMode,
      ),
      state: ReleaseSupplyChainSourceState.available,
      resolvedArtifact: snapshot,
      resolvedId: ref.resolvedId,
      fingerprint: ref.fingerprint,
      projectId: ref.projectId,
      commitId: ref.commitId,
      policyId: ref.policyId,
      policyVersion: ref.policyVersion,
    );
  }

  ResolvedReleaseSupplyChainSource<QualityGateSnapshot> _unavailableQg(
    String? requestedId,
  ) {
    return ResolvedReleaseSupplyChainSource<QualityGateSnapshot>(
      sourceType: ReleaseSupplyChainSourceType.qualityGate,
      resolutionMode: ReleaseSupplyChainSourceResolutionMode.injected,
      state: ReleaseSupplyChainSourceState.unavailable,
      requestedId: requestedId,
    );
  }

  ResolvedReleaseSupplyChainSource<QualityGateSnapshot> _notRequestedQg() {
    return const ResolvedReleaseSupplyChainSource<QualityGateSnapshot>(
      sourceType: ReleaseSupplyChainSourceType.qualityGate,
      resolutionMode: ReleaseSupplyChainSourceResolutionMode.injected,
      state: ReleaseSupplyChainSourceState.notRequested,
    );
  }

  ResolvedReleaseSupplyChainSource<ReleaseDecisionSnapshot> _availableRg(
    ReleaseDecisionSnapshot snapshot,
    ReleaseSupplyChainSourceReference ref,
  ) {
    return ResolvedReleaseSupplyChainSource<ReleaseDecisionSnapshot>(
      sourceType: ReleaseSupplyChainSourceType.releaseGovernance,
      resolutionMode: ReleaseSupplyChainSourceResolutionModeX.fromWireName(
        ref.resolutionMode,
      ),
      state: ReleaseSupplyChainSourceState.available,
      resolvedArtifact: snapshot,
      resolvedId: ref.resolvedId,
      fingerprint: ref.fingerprint,
      projectId: ref.projectId,
      commitId: ref.commitId,
      policyId: ref.policyId,
      policyVersion: ref.policyVersion,
    );
  }

  ResolvedReleaseSupplyChainSource<ReleaseDecisionSnapshot> _unavailableRg(
    String? requestedId,
  ) {
    return ResolvedReleaseSupplyChainSource<ReleaseDecisionSnapshot>(
      sourceType: ReleaseSupplyChainSourceType.releaseGovernance,
      resolutionMode: ReleaseSupplyChainSourceResolutionMode.injected,
      state: ReleaseSupplyChainSourceState.unavailable,
      requestedId: requestedId,
    );
  }

  ResolvedReleaseSupplyChainSource<ReleaseDecisionSnapshot> _notRequestedRg() {
    return const ResolvedReleaseSupplyChainSource<ReleaseDecisionSnapshot>(
      sourceType: ReleaseSupplyChainSourceType.releaseGovernance,
      resolutionMode: ReleaseSupplyChainSourceResolutionMode.injected,
      state: ReleaseSupplyChainSourceState.notRequested,
    );
  }

  ResolvedReleaseSupplyChainSource<ReleaseEvidenceBundle> _availableRe(
    ReleaseEvidenceBundle bundle,
    ReleaseSupplyChainSourceReference ref,
  ) {
    return ResolvedReleaseSupplyChainSource<ReleaseEvidenceBundle>(
      sourceType: ReleaseSupplyChainSourceType.releaseEvidence,
      resolutionMode: ReleaseSupplyChainSourceResolutionModeX.fromWireName(
        ref.resolutionMode,
      ),
      state: ReleaseSupplyChainSourceState.available,
      resolvedArtifact: bundle,
      resolvedId: ref.resolvedId,
      fingerprint: ref.fingerprint,
      projectId: ref.projectId,
      commitId: ref.commitId,
      policyId: ref.policyId,
      policyVersion: ref.policyVersion,
    );
  }

  ResolvedReleaseSupplyChainSource<ReleaseEvidenceBundle> _unavailableRe(
    String? requestedId,
  ) {
    return ResolvedReleaseSupplyChainSource<ReleaseEvidenceBundle>(
      sourceType: ReleaseSupplyChainSourceType.releaseEvidence,
      resolutionMode: ReleaseSupplyChainSourceResolutionMode.injected,
      state: ReleaseSupplyChainSourceState.unavailable,
      requestedId: requestedId,
    );
  }

  ResolvedReleaseSupplyChainSource<ReleaseEvidenceBundle> _notRequestedRe() {
    return const ResolvedReleaseSupplyChainSource<ReleaseEvidenceBundle>(
      sourceType: ReleaseSupplyChainSourceType.releaseEvidence,
      resolutionMode: ReleaseSupplyChainSourceResolutionMode.injected,
      state: ReleaseSupplyChainSourceState.notRequested,
    );
  }

  ResolvedReleaseSupplyChainSource<T> _unavailablePolicy<T>(
    ReleaseSupplyChainSourceType sourceType,
    String policyId,
  ) {
    return ResolvedReleaseSupplyChainSource<T>(
      sourceType: sourceType,
      resolutionMode: ReleaseSupplyChainSourceResolutionMode.injected,
      state: ReleaseSupplyChainSourceState.unavailable,
      requestedId: policyId,
    );
  }

  ReleaseSupplyChainSourceReference _qgRef(
    QualityGateSnapshot snapshot,
    ReleaseSupplyChainSourceResolutionMode mode,
  ) {
    return ReleaseSupplyChainSourceReference(
      sourceType: ReleaseSupplyChainSourceType.qualityGate.wireName,
      resolutionMode: mode.wireName,
      requestedId: snapshot.metadata.qualityGateSnapshotId,
      resolvedId: snapshot.metadata.qualityGateSnapshotId,
      fingerprint: snapshot.metadata.qualityGateFingerprint,
      projectId: snapshot.metadata.projectId,
      commitId: snapshot.metadata.commitId,
      policyId: snapshot.metadata.policyId,
      policyVersion: snapshot.metadata.policyVersion,
    );
  }

  ReleaseSupplyChainSourceReference _rgRef(
    ReleaseDecisionSnapshot snapshot,
    ReleaseSupplyChainSourceResolutionMode mode,
  ) {
    return ReleaseSupplyChainSourceReference(
      sourceType: ReleaseSupplyChainSourceType.releaseGovernance.wireName,
      resolutionMode: mode.wireName,
      requestedId: snapshot.metadata.snapshotId,
      resolvedId: snapshot.metadata.snapshotId,
      fingerprint: snapshot.fingerprint,
      projectId: snapshot.metadata.projectId,
      commitId: snapshot.metadata.commitId,
      policyId: snapshot.metadata.policyId,
      policyVersion: snapshot.metadata.policyVersion,
    );
  }

  ReleaseSupplyChainSourceReference _reRef(
    ReleaseEvidenceBundle bundle,
    ReleaseSupplyChainSourceResolutionMode mode,
  ) {
    return ReleaseSupplyChainSourceReference(
      sourceType: ReleaseSupplyChainSourceType.releaseEvidence.wireName,
      resolutionMode: mode.wireName,
      requestedId: bundle.metadata.bundleId,
      resolvedId: bundle.metadata.bundleId,
      fingerprint: bundle.fingerprint,
      projectId: bundle.metadata.projectId,
      commitId: bundle.metadata.commitId,
      policyId: bundle.metadata.policyId,
      policyVersion: bundle.metadata.policyVersion,
    );
  }

  ReleaseSupplyChainSourceReference _unavailableRef(
    ReleaseSupplyChainSourceType type,
    String artifactId,
    ReleaseSupplyChainSourceResolutionMode mode,
  ) {
    return ReleaseSupplyChainSourceReference(
      sourceType: type.wireName,
      resolutionMode: mode.wireName,
      requestedId: artifactId,
      resolvedId: artifactId,
      limitations: const ['source unavailable'],
    );
  }
}
