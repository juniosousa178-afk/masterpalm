import '../interfaces/quality_gate_provider.dart';
import '../models/quality_gate/quality_gate_snapshot.dart';
import '../models/release_governance/release_approval.dart';
import '../models/release_governance/release_context.dart';
import '../models/release_governance/release_governance_enums.dart';
import '../models/release_governance/release_governance_evidence.dart';
import '../models/release_governance/release_governance_messages.dart';
import '../models/release_governance/release_governance_policy.dart';
import '../models/release_governance/release_governance_request.dart';
import '../models/release_governance/release_waiver.dart';
import 'release_governance_canonical_serializer.dart';
import 'resolved_release_governance_sources.dart';

/// Resolves release governance source artifacts without executing origin engines.
class ReleaseGovernanceSourceResolver {
  ReleaseGovernanceSourceResolver({
    required QualityGateProvider qualityGateProvider,
    ReleaseGovernanceCanonicalSerializer? serializer,
  })  : _qualityGateProvider = qualityGateProvider,
        _serializer =
            serializer ?? const ReleaseGovernanceCanonicalSerializer();

  final QualityGateProvider _qualityGateProvider;
  final ReleaseGovernanceCanonicalSerializer _serializer;

  Future<ResolvedReleaseGovernanceSources> resolveAll(
    ReleaseGovernanceRequest request,
    ReleaseGovernancePolicy policy,
  ) async {
    final refs = <ReleaseGovernanceSourceReference>[];
    final warnings = <ReleaseGovernanceWarning>[];
    final errors = <ReleaseGovernanceError>[];
    final limitations = <ReleaseGovernanceLimitation>[];
    final hints = <String>[];

    final resolved = <String>[];
    final unresolved = <String>[];
    final injected = <String>[];

    final releaseContext = resolveReleaseContext(request, refs);
    _trackResolution(releaseContext, resolved, unresolved, injected);

    final qualityGate =
        await resolveQualityGateSnapshot(request, refs, limitations);
    _trackResolution(qualityGate, resolved, unresolved, injected);

    final approvalSet = resolveApprovalSet(request, refs, limitations);
    _trackResolution(approvalSet, resolved, unresolved, injected);

    final waiverSet = resolveWaiverSet(request, refs, limitations);
    _trackResolution(waiverSet, resolved, unresolved, injected);

    final policySource = resolvePolicy(request, policy, refs);
    _trackResolution(policySource, resolved, unresolved, injected);

    _checkProjectMismatch(request, qualityGate, hints, limitations);

    refs.sort((a, b) => a.sourceType.wireName.compareTo(b.sourceType.wireName));

    final summary = ReleaseGovernanceSourceResolutionSummary(
      resolvedSources: resolved,
      unresolvedSources: unresolved,
      injectedSources: injected,
      fingerprint: _serializer.sourceReferencesFingerprint(refs),
    );

    return ResolvedReleaseGovernanceSources(
      releaseContext: releaseContext,
      qualityGateSnapshot: qualityGate,
      policy: policySource,
      approvalSet: approvalSet,
      waiverSet: waiverSet,
      sourceReferences: refs,
      resolutionSummary: summary,
      warnings: warnings,
      errors: errors,
      limitations: limitations,
      compatibilityHints: hints,
    );
  }

  ResolvedReleaseGovernanceSource<ReleaseContext> resolveReleaseContext(
    ReleaseGovernanceRequest request,
    List<ReleaseGovernanceSourceReference> refs,
  ) {
    final context = request.releaseContext;
    refs.add(
      ReleaseGovernanceSourceReference(
        sourceType: ReleaseGovernanceSourceType.releaseContext,
        resolutionMode: ReleaseGovernanceSourceResolutionMode.injected,
        requestedId: context.releaseId,
        resolvedId: context.releaseId,
        fingerprint: context.releaseId,
        projectId: context.projectId,
        commitId: context.commitId,
        compatibility: ReleaseGovernanceCompatibilityStatus.compatible,
      ),
    );
    return ResolvedReleaseGovernanceSource<ReleaseContext>(
      sourceType: ReleaseGovernanceSourceType.releaseContext,
      resolutionMode: ReleaseGovernanceSourceResolutionMode.injected,
      state: ResolvedReleaseGovernanceSourceState.available,
      resolvedArtifact: context,
      resolvedId: context.releaseId,
      fingerprint: context.releaseId,
      projectId: context.projectId,
      commitId: context.commitId,
    );
  }

  Future<ResolvedReleaseGovernanceSource<QualityGateSnapshot>>
      resolveQualityGateSnapshot(
    ReleaseGovernanceRequest request,
    List<ReleaseGovernanceSourceReference> refs,
    List<ReleaseGovernanceLimitation> limitations,
  ) async {
    if (request.qualityGateSnapshot != null) {
      final snapshot = request.qualityGateSnapshot!;
      refs.add(
          _qgRef(snapshot, ReleaseGovernanceSourceResolutionMode.injected));
      return _availableQg(snapshot, refs.last);
    }
    if (request.qualityGateSnapshotId != null) {
      final loaded = await _qualityGateProvider.load(
        request.qualityGateSnapshotId!,
      );
      if (loaded != null) {
        refs.add(_qgRef(loaded, ReleaseGovernanceSourceResolutionMode.byId));
        return _availableQg(loaded, refs.last);
      }
      refs.add(_unavailableRef(
        ReleaseGovernanceSourceType.qualityGateSnapshot,
        request.qualityGateSnapshotId!,
        ReleaseGovernanceSourceResolutionMode.byId,
      ));
      limitations.add(
        ReleaseGovernanceLimitation(
          limitationId: 'missing-quality-gate',
          code: ReleaseGovernanceLimitationCode.noPhysicalPersistence,
          description:
              'Quality gate snapshot ${request.qualityGateSnapshotId} unavailable',
          impact: 'Quality gate rules cannot be evaluated',
          resolvable: true,
        ),
      );
      return _unavailableQg(request.qualityGateSnapshotId);
    }
    if (request.useLatest) {
      final loaded = await _qualityGateProvider.latest(
        projectId: request.releaseContext.projectId,
      );
      if (loaded != null) {
        refs.add(_qgRef(loaded, ReleaseGovernanceSourceResolutionMode.latest));
        return _availableQg(loaded, refs.last);
      }
      limitations.add(
        const ReleaseGovernanceLimitation(
          limitationId: 'latest-quality-gate-missing',
          code: ReleaseGovernanceLimitationCode.noPhysicalPersistence,
          description: 'Latest quality gate snapshot unavailable',
          impact: 'Quality gate rules may be unavailable',
          resolvable: true,
        ),
      );
    }
    return _notRequestedQg();
  }

  ResolvedReleaseGovernanceSource<ReleaseApprovalSet> resolveApprovalSet(
    ReleaseGovernanceRequest request,
    List<ReleaseGovernanceSourceReference> refs,
    List<ReleaseGovernanceLimitation> limitations,
  ) {
    if (request.approvalSet != null) {
      final set = request.approvalSet!;
      refs.add(
        ReleaseGovernanceSourceReference(
          sourceType: ReleaseGovernanceSourceType.approvalSet,
          resolutionMode: ReleaseGovernanceSourceResolutionMode.injected,
          requestedId: set.releaseId,
          resolvedId: set.releaseId,
          fingerprint: set.fingerprint,
          compatibility: ReleaseGovernanceCompatibilityStatus.compatible,
        ),
      );
      return ResolvedReleaseGovernanceSource<ReleaseApprovalSet>(
        sourceType: ReleaseGovernanceSourceType.approvalSet,
        resolutionMode: ReleaseGovernanceSourceResolutionMode.injected,
        state: ResolvedReleaseGovernanceSourceState.available,
        resolvedArtifact: set,
        resolvedId: set.releaseId,
        fingerprint: set.fingerprint,
      );
    }
    if (request.approvalSetId != null) {
      refs.add(_unavailableRef(
        ReleaseGovernanceSourceType.approvalSet,
        request.approvalSetId!,
        ReleaseGovernanceSourceResolutionMode.byId,
      ));
      limitations.add(
        const ReleaseGovernanceLimitation(
          limitationId: 'approval-byid-unsupported',
          code: ReleaseGovernanceLimitationCode.noPhysicalPersistence,
          description:
              'Approval set must be injected; load by ID is not supported',
          impact: 'Approval rules may be pending',
          resolvable: true,
        ),
      );
      return _unavailableApproval(request.approvalSetId);
    }
    return _emptyApprovalSet();
  }

  ResolvedReleaseGovernanceSource<ReleaseWaiverSet> resolveWaiverSet(
    ReleaseGovernanceRequest request,
    List<ReleaseGovernanceSourceReference> refs,
    List<ReleaseGovernanceLimitation> limitations,
  ) {
    if (request.waiverSet != null) {
      final set = request.waiverSet!;
      refs.add(
        ReleaseGovernanceSourceReference(
          sourceType: ReleaseGovernanceSourceType.waiverSet,
          resolutionMode: ReleaseGovernanceSourceResolutionMode.injected,
          requestedId: set.releaseId,
          resolvedId: set.releaseId,
          fingerprint: set.fingerprint,
          compatibility: ReleaseGovernanceCompatibilityStatus.compatible,
        ),
      );
      return ResolvedReleaseGovernanceSource<ReleaseWaiverSet>(
        sourceType: ReleaseGovernanceSourceType.waiverSet,
        resolutionMode: ReleaseGovernanceSourceResolutionMode.injected,
        state: ResolvedReleaseGovernanceSourceState.available,
        resolvedArtifact: set,
        resolvedId: set.releaseId,
        fingerprint: set.fingerprint,
      );
    }
    if (request.waiverSetId != null) {
      refs.add(_unavailableRef(
        ReleaseGovernanceSourceType.waiverSet,
        request.waiverSetId!,
        ReleaseGovernanceSourceResolutionMode.byId,
      ));
      limitations.add(
        const ReleaseGovernanceLimitation(
          limitationId: 'waiver-byid-unsupported',
          code: ReleaseGovernanceLimitationCode.noPhysicalPersistence,
          description:
              'Waiver set must be injected; load by ID is not supported',
          impact: 'Waiver rules use empty set',
          resolvable: true,
        ),
      );
      return _unavailableWaiver(request.waiverSetId);
    }
    return _emptyWaiverSet();
  }

  ResolvedReleaseGovernanceSource<ReleaseGovernancePolicy> resolvePolicy(
    ReleaseGovernanceRequest request,
    ReleaseGovernancePolicy policy,
    List<ReleaseGovernanceSourceReference> refs,
  ) {
    final fingerprint = policy.metadata.fingerprint ?? policy.metadata.policyId;
    refs.add(
      ReleaseGovernanceSourceReference(
        sourceType: ReleaseGovernanceSourceType.releaseGovernancePolicy,
        resolutionMode: ReleaseGovernanceSourceResolutionMode.injected,
        requestedId: policy.metadata.policyId,
        resolvedId: policy.metadata.policyId,
        fingerprint: fingerprint,
        policyId: policy.metadata.policyId,
        policyVersion: policy.metadata.policyVersion,
        compatibility: ReleaseGovernanceCompatibilityStatus.compatible,
      ),
    );
    return ResolvedReleaseGovernanceSource<ReleaseGovernancePolicy>(
      sourceType: ReleaseGovernanceSourceType.releaseGovernancePolicy,
      resolutionMode: ReleaseGovernanceSourceResolutionMode.injected,
      state: ResolvedReleaseGovernanceSourceState.available,
      resolvedArtifact: policy,
      resolvedId: policy.metadata.policyId,
      fingerprint: fingerprint,
      policyId: policy.metadata.policyId,
      policyVersion: policy.metadata.policyVersion,
    );
  }

  void _checkProjectMismatch(
    ReleaseGovernanceRequest request,
    ResolvedReleaseGovernanceSource<QualityGateSnapshot> qg,
    List<String> hints,
    List<ReleaseGovernanceLimitation> limitations,
  ) {
    if (!qg.isAvailable) return;
    final qgProject = qg.resolvedArtifact!.metadata.projectId;
    final expected = request.releaseContext.projectId;
    if (qgProject != expected) {
      hints.add('Project mismatch on qualityGate: $qgProject != $expected');
      limitations.add(
        ReleaseGovernanceLimitation(
          limitationId: 'project-mismatch-quality-gate',
          code: ReleaseGovernanceLimitationCode.historicalDataIncomplete,
          description:
              'Quality gate projectId $qgProject differs from release $expected',
          impact: 'Cross-artifact consistency rules may fail',
          resolvable: false,
        ),
      );
    }
  }

  void _trackResolution(
    ResolvedReleaseGovernanceSource<dynamic> source,
    List<String> resolved,
    List<String> unresolved,
    List<String> injected,
  ) {
    final name = source.sourceType.wireName;
    switch (source.resolutionMode) {
      case ReleaseGovernanceSourceResolutionMode.injected:
        if (source.isAvailable) {
          injected.add(name);
          resolved.add(name);
        }
      case ReleaseGovernanceSourceResolutionMode.byId:
        if (source.isAvailable) {
          resolved.add(name);
        } else {
          unresolved.add(name);
        }
      case ReleaseGovernanceSourceResolutionMode.latest:
        if (source.isAvailable) {
          resolved.add(name);
        } else {
          unresolved.add(name);
        }
      case ReleaseGovernanceSourceResolutionMode.unavailable:
      case ReleaseGovernanceSourceResolutionMode.notRequested:
        if (!source.isAvailable &&
            source.state != ResolvedReleaseGovernanceSourceState.notRequested) {
          unresolved.add(name);
        }
    }
  }

  ResolvedReleaseGovernanceSource<QualityGateSnapshot> _availableQg(
    QualityGateSnapshot snapshot,
    ReleaseGovernanceSourceReference ref,
  ) {
    return ResolvedReleaseGovernanceSource<QualityGateSnapshot>(
      sourceType: ReleaseGovernanceSourceType.qualityGateSnapshot,
      resolutionMode: ref.resolutionMode,
      state: ResolvedReleaseGovernanceSourceState.available,
      resolvedArtifact: snapshot,
      resolvedId: ref.resolvedId,
      fingerprint: ref.fingerprint,
      projectId: ref.projectId,
      commitId: ref.commitId,
      policyId: ref.policyId,
      policyVersion: ref.policyVersion,
    );
  }

  ResolvedReleaseGovernanceSource<QualityGateSnapshot> _unavailableQg(
    String? requestedId,
  ) {
    return ResolvedReleaseGovernanceSource<QualityGateSnapshot>(
      sourceType: ReleaseGovernanceSourceType.qualityGateSnapshot,
      resolutionMode: ReleaseGovernanceSourceResolutionMode.unavailable,
      state: ResolvedReleaseGovernanceSourceState.unavailable,
      requestedId: requestedId,
    );
  }

  ResolvedReleaseGovernanceSource<QualityGateSnapshot> _notRequestedQg() {
    return const ResolvedReleaseGovernanceSource<QualityGateSnapshot>(
      sourceType: ReleaseGovernanceSourceType.qualityGateSnapshot,
      resolutionMode: ReleaseGovernanceSourceResolutionMode.notRequested,
      state: ResolvedReleaseGovernanceSourceState.notRequested,
    );
  }

  ResolvedReleaseGovernanceSource<ReleaseApprovalSet> _unavailableApproval(
    String? requestedId,
  ) {
    return ResolvedReleaseGovernanceSource<ReleaseApprovalSet>(
      sourceType: ReleaseGovernanceSourceType.approvalSet,
      resolutionMode: ReleaseGovernanceSourceResolutionMode.unavailable,
      state: ResolvedReleaseGovernanceSourceState.unavailable,
      requestedId: requestedId,
    );
  }

  ResolvedReleaseGovernanceSource<ReleaseApprovalSet> _emptyApprovalSet() {
    return const ResolvedReleaseGovernanceSource<ReleaseApprovalSet>(
      sourceType: ReleaseGovernanceSourceType.approvalSet,
      resolutionMode: ReleaseGovernanceSourceResolutionMode.notRequested,
      state: ResolvedReleaseGovernanceSourceState.notRequested,
    );
  }

  ResolvedReleaseGovernanceSource<ReleaseWaiverSet> _unavailableWaiver(
    String? requestedId,
  ) {
    return ResolvedReleaseGovernanceSource<ReleaseWaiverSet>(
      sourceType: ReleaseGovernanceSourceType.waiverSet,
      resolutionMode: ReleaseGovernanceSourceResolutionMode.unavailable,
      state: ResolvedReleaseGovernanceSourceState.unavailable,
      requestedId: requestedId,
    );
  }

  ResolvedReleaseGovernanceSource<ReleaseWaiverSet> _emptyWaiverSet() {
    return const ResolvedReleaseGovernanceSource<ReleaseWaiverSet>(
      sourceType: ReleaseGovernanceSourceType.waiverSet,
      resolutionMode: ReleaseGovernanceSourceResolutionMode.notRequested,
      state: ResolvedReleaseGovernanceSourceState.notRequested,
    );
  }

  ReleaseGovernanceSourceReference _qgRef(
    QualityGateSnapshot snapshot,
    ReleaseGovernanceSourceResolutionMode mode,
  ) {
    return ReleaseGovernanceSourceReference(
      sourceType: ReleaseGovernanceSourceType.qualityGateSnapshot,
      resolutionMode: mode,
      requestedId: snapshot.metadata.qualityGateSnapshotId,
      resolvedId: snapshot.metadata.qualityGateSnapshotId,
      fingerprint: snapshot.metadata.qualityGateFingerprint,
      projectId: snapshot.metadata.projectId,
      commitId: snapshot.metadata.commitId,
      policyId: snapshot.metadata.policyId,
      policyVersion: snapshot.metadata.policyVersion,
      compatibility: ReleaseGovernanceCompatibilityStatus.compatible,
    );
  }

  ReleaseGovernanceSourceReference _unavailableRef(
    ReleaseGovernanceSourceType type,
    String artifactId,
    ReleaseGovernanceSourceResolutionMode mode,
  ) {
    return ReleaseGovernanceSourceReference(
      sourceType: type,
      resolutionMode: mode,
      requestedId: artifactId,
      resolvedId: artifactId,
      compatibility: ReleaseGovernanceCompatibilityStatus.unknown,
      limitations: const ['source unavailable'],
    );
  }
}
