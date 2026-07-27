import '../interfaces/quality_gate_provider.dart';
import '../interfaces/release_governance_provider.dart';
import '../models/quality_gate/quality_gate_snapshot.dart';
import '../models/release_evidence/release_attestation_policy.dart';
import '../models/release_evidence/release_attestation_set.dart';
import '../models/release_evidence/release_evidence_enums.dart';
import '../models/release_evidence/release_evidence_messages.dart';
import '../models/release_evidence/release_evidence_policy.dart';
import '../models/release_evidence/release_evidence_reference.dart';
import '../models/release_evidence/release_evidence_request.dart';
import '../models/release_evidence/release_evidence_result.dart';
import '../models/release_evidence/release_provenance.dart';
import '../models/release_evidence/release_verification_policy.dart';
import '../models/release_governance/release_context.dart';
import '../models/release_governance/release_decision_snapshot.dart';
import 'policies/release_attestation_policy_v1.dart';
import 'policies/release_evidence_policy_v1.dart';
import 'policies/release_verification_policy_v1.dart';
import 'release_evidence_canonical_serializer.dart';
import 'release_evidence_policy_registry.dart';
import 'resolved_release_evidence_sources.dart';

/// Resolves release evidence source artifacts without executing origin engines.
class ReleaseEvidenceSourceResolver {
  ReleaseEvidenceSourceResolver({
    required QualityGateProvider qualityGateProvider,
    required ReleaseGovernanceProvider releaseGovernanceProvider,
    ReleaseEvidencePolicyRegistry? evidencePolicyRegistry,
    ReleaseAttestationPolicyRegistry? attestationPolicyRegistry,
    ReleaseVerificationPolicyRegistry? verificationPolicyRegistry,
    ReleaseEvidenceCanonicalSerializer? serializer,
  })  : _qualityGateProvider = qualityGateProvider,
        _releaseGovernanceProvider = releaseGovernanceProvider,
        _evidencePolicyRegistry =
            evidencePolicyRegistry ?? ReleaseEvidencePolicyRegistry(),
        _attestationPolicyRegistry =
            attestationPolicyRegistry ?? ReleaseAttestationPolicyRegistry(),
        _verificationPolicyRegistry =
            verificationPolicyRegistry ?? ReleaseVerificationPolicyRegistry(),
        _serializer = serializer ?? const ReleaseEvidenceCanonicalSerializer();

  final QualityGateProvider _qualityGateProvider;
  final ReleaseGovernanceProvider _releaseGovernanceProvider;
  final ReleaseEvidencePolicyRegistry _evidencePolicyRegistry;
  final ReleaseAttestationPolicyRegistry _attestationPolicyRegistry;
  final ReleaseVerificationPolicyRegistry _verificationPolicyRegistry;
  final ReleaseEvidenceCanonicalSerializer _serializer;

  Future<ResolvedReleaseEvidenceSources> resolveAll(
    ReleaseEvidenceRequest request, {
    ReleaseEvidencePolicy? injectedEvidencePolicy,
    ReleaseAttestationPolicy? injectedAttestationPolicy,
    ReleaseVerificationPolicy? injectedVerificationPolicy,
  }) async {
    final refs = <ReleaseEvidenceSourceReference>[];
    final warnings = <ReleaseEvidenceWarning>[];
    final errors = <ReleaseEvidenceError>[];
    final limitations = <ReleaseEvidenceLimitation>[];
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

    final evidencePolicy = resolveEvidencePolicy(
      request,
      refs,
      injectedEvidencePolicy,
      limitations,
    );
    _trackResolution(evidencePolicy, resolved, unresolved, injected);

    final attestationPolicy = resolveAttestationPolicy(
      request,
      refs,
      injectedAttestationPolicy,
      limitations,
    );
    _trackResolution(attestationPolicy, resolved, unresolved, injected);

    final verificationPolicy = resolveVerificationPolicy(
      request,
      refs,
      injectedVerificationPolicy,
      limitations,
    );
    _trackResolution(verificationPolicy, resolved, unresolved, injected);

    final evidenceRefs = resolveEvidenceReferences(request, refs, limitations);
    _trackResolution(evidenceRefs, resolved, unresolved, injected);

    final attestationSet = resolveAttestationSet(request, refs, limitations);
    _trackResolution(attestationSet, resolved, unresolved, injected);

    final provenance = resolveProvenance(request, refs, limitations);
    _trackResolution(provenance, resolved, unresolved, injected);

    _checkProjectMismatch(request, qualityGate, hints, limitations);
    _checkCommitMismatch(
        request, qualityGate, releaseDecision, hints, limitations);

    refs.sort(
      (a, b) => a.sourceType.wireName.compareTo(b.sourceType.wireName),
    );

    final summary = ReleaseEvidenceSourceResolutionSummary(
      resolvedSources: resolved,
      unresolvedSources: unresolved,
      injectedSources: injected,
      fingerprint: _serializer.sourceReferencesFingerprint(refs),
    );

    return ResolvedReleaseEvidenceSources(
      releaseContext: releaseContext,
      qualityGateSnapshot: qualityGate,
      releaseDecisionSnapshot: releaseDecision,
      evidencePolicy: evidencePolicy,
      attestationPolicy: attestationPolicy,
      verificationPolicy: verificationPolicy,
      evidenceReferences: evidenceRefs,
      attestationSet: attestationSet,
      provenance: provenance,
      sourceReferences: refs,
      resolutionSummary: summary,
      warnings: warnings,
      errors: errors,
      limitations: limitations,
      compatibilityHints: hints,
    );
  }

  ResolvedReleaseEvidenceSource<ReleaseContext> resolveReleaseContext(
    ReleaseEvidenceRequest request,
    List<ReleaseEvidenceSourceReference> refs,
  ) {
    final context = request.releaseContext;
    refs.add(
      ReleaseEvidenceSourceReference(
        sourceType: ReleaseEvidenceType.releaseContext,
        resolutionMode: ReleaseEvidenceSourceResolutionMode.injected,
        requestedId: context.releaseId,
        resolvedId: context.releaseId,
        fingerprint: context.releaseId,
        projectId: context.projectId,
        commitId: context.commitId,
        availability: ReleaseEvidenceAvailabilityStatus.available,
        compatibility: ReleaseEvidenceCompatibilityStatus.compatible,
      ),
    );
    return ResolvedReleaseEvidenceSource<ReleaseContext>(
      sourceType: ReleaseEvidenceType.releaseContext,
      resolutionMode: ReleaseEvidenceSourceResolutionMode.injected,
      state: ResolvedReleaseEvidenceSourceState.available,
      resolvedArtifact: context,
      resolvedId: context.releaseId,
      fingerprint: context.releaseId,
      projectId: context.projectId,
      commitId: context.commitId,
    );
  }

  Future<ResolvedReleaseEvidenceSource<QualityGateSnapshot>>
      resolveQualityGateSnapshot(
    ReleaseEvidenceRequest request,
    List<ReleaseEvidenceSourceReference> refs,
    List<ReleaseEvidenceLimitation> limitations,
  ) async {
    if (request.qualityGateSnapshot != null) {
      final snapshot = request.qualityGateSnapshot!;
      refs.add(_qgRef(snapshot, ReleaseEvidenceSourceResolutionMode.injected));
      return _availableQg(snapshot, refs.last);
    }
    if (request.qualityGateSnapshotId != null) {
      final loaded = await _qualityGateProvider.load(
        request.qualityGateSnapshotId!,
      );
      if (loaded != null) {
        refs.add(_qgRef(loaded, ReleaseEvidenceSourceResolutionMode.byId));
        return _availableQg(loaded, refs.last);
      }
      refs.add(_unavailableRef(
        ReleaseEvidenceType.qualityGate,
        request.qualityGateSnapshotId!,
        ReleaseEvidenceSourceResolutionMode.byId,
      ));
      limitations.add(
        const ReleaseEvidenceLimitation(
          limitationId: 'missing-quality-gate',
          code: ReleaseEvidenceLimitationCode.noPhysicalPersistence,
          description: 'Quality gate snapshot unavailable by ID',
          impact: 'Quality gate evidence may be unavailable',
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
        refs.add(_qgRef(loaded, ReleaseEvidenceSourceResolutionMode.latest));
        return _availableQg(loaded, refs.last);
      }
      limitations.add(
        const ReleaseEvidenceLimitation(
          limitationId: 'latest-quality-gate-missing',
          code: ReleaseEvidenceLimitationCode.noPhysicalPersistence,
          description: 'Latest quality gate snapshot unavailable',
          impact: 'Quality gate evidence may be unavailable',
          resolvable: true,
        ),
      );
    }
    return _notRequestedQg();
  }

  Future<ResolvedReleaseEvidenceSource<ReleaseDecisionSnapshot>>
      resolveReleaseDecisionSnapshot(
    ReleaseEvidenceRequest request,
    List<ReleaseEvidenceSourceReference> refs,
    List<ReleaseEvidenceLimitation> limitations,
  ) async {
    if (request.releaseDecisionSnapshot != null) {
      final snapshot = request.releaseDecisionSnapshot!;
      refs.add(_rgRef(snapshot, ReleaseEvidenceSourceResolutionMode.injected));
      return _availableRg(snapshot, refs.last);
    }
    if (request.releaseDecisionSnapshotId != null) {
      final loaded = await _releaseGovernanceProvider.load(
        request.releaseDecisionSnapshotId!,
      );
      if (loaded != null) {
        refs.add(_rgRef(loaded, ReleaseEvidenceSourceResolutionMode.byId));
        return _availableRg(loaded, refs.last);
      }
      refs.add(_unavailableRef(
        ReleaseEvidenceType.releaseGovernance,
        request.releaseDecisionSnapshotId!,
        ReleaseEvidenceSourceResolutionMode.byId,
      ));
      limitations.add(
        const ReleaseEvidenceLimitation(
          limitationId: 'missing-release-decision',
          code: ReleaseEvidenceLimitationCode.noPhysicalPersistence,
          description: 'Release decision snapshot unavailable by ID',
          impact: 'Release governance evidence may be unavailable',
          resolvable: true,
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
        refs.add(_rgRef(loaded, ReleaseEvidenceSourceResolutionMode.latest));
        return _availableRg(loaded, refs.last);
      }
      limitations.add(
        const ReleaseEvidenceLimitation(
          limitationId: 'latest-release-decision-missing',
          code: ReleaseEvidenceLimitationCode.noPhysicalPersistence,
          description: 'Latest release decision snapshot unavailable',
          impact: 'Release governance evidence may be unavailable',
          resolvable: true,
        ),
      );
    }
    return _notRequestedRg();
  }

  ResolvedReleaseEvidenceSource<ReleaseEvidencePolicy> resolveEvidencePolicy(
    ReleaseEvidenceRequest request,
    List<ReleaseEvidenceSourceReference> refs,
    ReleaseEvidencePolicy? injectedPolicy,
    List<ReleaseEvidenceLimitation> limitations,
  ) {
    if (injectedPolicy != null) {
      return _resolvedPolicy(
        policy: injectedPolicy,
        sourceType: ReleaseEvidenceType.unknown,
        mode: ReleaseEvidenceSourceResolutionMode.injected,
        refs: refs,
      );
    }
    final policyId =
        request.evidencePolicyId ?? ReleaseEvidencePolicyV1.policyId;
    final policy = _evidencePolicyRegistry.resolve(
      policyId: policyId,
      policyVersion: request.evidencePolicyVersion,
      allowCandidate: true,
      historicalEvaluation: request.historicalEvaluation,
    );
    if (policy != null) {
      return _resolvedPolicy(
        policy: policy,
        sourceType: ReleaseEvidenceType.unknown,
        mode: ReleaseEvidenceSourceResolutionMode.byId,
        refs: refs,
      );
    }
    limitations.add(
      ReleaseEvidenceLimitation(
        limitationId: 'missing-evidence-policy',
        code: ReleaseEvidenceLimitationCode.noPhysicalPersistence,
        description: 'Evidence policy $policyId unavailable',
        impact: 'Evidence collection cannot proceed',
        resolvable: true,
      ),
    );
    return _unavailablePolicy<ReleaseEvidencePolicy>(
      ReleaseEvidenceType.unknown,
      policyId,
    );
  }

  ResolvedReleaseEvidenceSource<ReleaseAttestationPolicy>
      resolveAttestationPolicy(
    ReleaseEvidenceRequest request,
    List<ReleaseEvidenceSourceReference> refs,
    ReleaseAttestationPolicy? injectedPolicy,
    List<ReleaseEvidenceLimitation> limitations,
  ) {
    if (injectedPolicy != null) {
      return _resolvedAttestationPolicy(
        policy: injectedPolicy,
        mode: ReleaseEvidenceSourceResolutionMode.injected,
        refs: refs,
      );
    }
    final policyId =
        request.attestationPolicyId ?? ReleaseAttestationPolicyV1.policyId;
    final policy = _attestationPolicyRegistry.resolve(
      policyId: policyId,
      policyVersion: request.attestationPolicyVersion,
      allowCandidate: true,
      historicalEvaluation: request.historicalEvaluation,
    );
    if (policy != null) {
      return _resolvedAttestationPolicy(
        policy: policy,
        mode: ReleaseEvidenceSourceResolutionMode.byId,
        refs: refs,
      );
    }
    limitations.add(
      ReleaseEvidenceLimitation(
        limitationId: 'missing-attestation-policy',
        code: ReleaseEvidenceLimitationCode.noPhysicalPersistence,
        description: 'Attestation policy $policyId unavailable',
        impact: 'Attestation evaluation may be limited',
        resolvable: true,
      ),
    );
    return _unavailablePolicy<ReleaseAttestationPolicy>(
      ReleaseEvidenceType.unknown,
      policyId,
    );
  }

  ResolvedReleaseEvidenceSource<ReleaseVerificationPolicy>
      resolveVerificationPolicy(
    ReleaseEvidenceRequest request,
    List<ReleaseEvidenceSourceReference> refs,
    ReleaseVerificationPolicy? injectedPolicy,
    List<ReleaseEvidenceLimitation> limitations,
  ) {
    if (!request.includeVerification) {
      return const ResolvedReleaseEvidenceSource<ReleaseVerificationPolicy>(
        sourceType: ReleaseEvidenceType.unknown,
        resolutionMode: ReleaseEvidenceSourceResolutionMode.injected,
        state: ResolvedReleaseEvidenceSourceState.notRequested,
      );
    }
    if (injectedPolicy != null) {
      return _resolvedVerificationPolicy(
        policy: injectedPolicy,
        mode: ReleaseEvidenceSourceResolutionMode.injected,
        refs: refs,
      );
    }
    final policyId =
        request.verificationPolicyId ?? ReleaseVerificationPolicyV1.policyId;
    final policy = _verificationPolicyRegistry.resolve(
      policyId: policyId,
      policyVersion: request.verificationPolicyVersion,
      allowCandidate: true,
      historicalEvaluation: request.historicalEvaluation,
    );
    if (policy != null) {
      return _resolvedVerificationPolicy(
        policy: policy,
        mode: ReleaseEvidenceSourceResolutionMode.byId,
        refs: refs,
      );
    }
    limitations.add(
      ReleaseEvidenceLimitation(
        limitationId: 'missing-verification-policy',
        code: ReleaseEvidenceLimitationCode.noPhysicalPersistence,
        description: 'Verification policy $policyId unavailable',
        impact: 'Verification may be unavailable',
        resolvable: true,
      ),
    );
    return _unavailablePolicy<ReleaseVerificationPolicy>(
      ReleaseEvidenceType.unknown,
      policyId,
    );
  }

  ResolvedReleaseEvidenceSource<List<ReleaseEvidenceReference>>
      resolveEvidenceReferences(
    ReleaseEvidenceRequest request,
    List<ReleaseEvidenceSourceReference> refs,
    List<ReleaseEvidenceLimitation> limitations,
  ) {
    if (request.evidenceReferences.isNotEmpty) {
      refs.add(
        ReleaseEvidenceSourceReference(
          sourceType: ReleaseEvidenceType.external,
          resolutionMode: ReleaseEvidenceSourceResolutionMode.injected,
          requestedId: 'evidence-references',
          resolvedId: 'evidence-references',
          fingerprint: '${request.evidenceReferences.length}',
          projectId: request.releaseContext.projectId,
          availability: ReleaseEvidenceAvailabilityStatus.available,
          compatibility: ReleaseEvidenceCompatibilityStatus.compatible,
        ),
      );
      return ResolvedReleaseEvidenceSource<List<ReleaseEvidenceReference>>(
        sourceType: ReleaseEvidenceType.external,
        resolutionMode: ReleaseEvidenceSourceResolutionMode.injected,
        state: ResolvedReleaseEvidenceSourceState.available,
        resolvedArtifact: request.evidenceReferences,
        resolvedId: 'evidence-references',
      );
    }
    if (request.evidenceReferenceIds.isNotEmpty) {
      refs.add(_unavailableRef(
        ReleaseEvidenceType.external,
        request.evidenceReferenceIds.first,
        ReleaseEvidenceSourceResolutionMode.byId,
      ));
      limitations.add(
        const ReleaseEvidenceLimitation(
          limitationId: 'evidence-ref-byid-unsupported',
          code: ReleaseEvidenceLimitationCode.noRemoteEvidenceFetch,
          description:
              'Evidence references must be injected; load by ID is not supported',
          impact: 'External evidence references unavailable',
          resolvable: true,
        ),
      );
      return const ResolvedReleaseEvidenceSource<
          List<ReleaseEvidenceReference>>(
        sourceType: ReleaseEvidenceType.external,
        resolutionMode: ReleaseEvidenceSourceResolutionMode.unavailable,
        state: ResolvedReleaseEvidenceSourceState.unavailable,
      );
    }
    return const ResolvedReleaseEvidenceSource<List<ReleaseEvidenceReference>>(
      sourceType: ReleaseEvidenceType.external,
      resolutionMode: ReleaseEvidenceSourceResolutionMode.injected,
      state: ResolvedReleaseEvidenceSourceState.notRequested,
      resolvedArtifact: [],
    );
  }

  ResolvedReleaseEvidenceSource<ReleaseAttestationSet> resolveAttestationSet(
    ReleaseEvidenceRequest request,
    List<ReleaseEvidenceSourceReference> refs,
    List<ReleaseEvidenceLimitation> limitations,
  ) {
    if (request.attestationSet != null) {
      final set = request.attestationSet!;
      refs.add(
        ReleaseEvidenceSourceReference(
          sourceType: ReleaseEvidenceType.unknown,
          resolutionMode: ReleaseEvidenceSourceResolutionMode.injected,
          requestedId: set.subjectId,
          resolvedId: set.subjectId,
          fingerprint: set.fingerprint,
          availability: ReleaseEvidenceAvailabilityStatus.available,
          compatibility: ReleaseEvidenceCompatibilityStatus.compatible,
        ),
      );
      return ResolvedReleaseEvidenceSource<ReleaseAttestationSet>(
        sourceType: ReleaseEvidenceType.unknown,
        resolutionMode: ReleaseEvidenceSourceResolutionMode.injected,
        state: ResolvedReleaseEvidenceSourceState.available,
        resolvedArtifact: set,
        resolvedId: set.subjectId,
        fingerprint: set.fingerprint,
      );
    }
    if (request.attestationSetId != null) {
      refs.add(_unavailableRef(
        ReleaseEvidenceType.unknown,
        request.attestationSetId!,
        ReleaseEvidenceSourceResolutionMode.byId,
      ));
      limitations.add(
        const ReleaseEvidenceLimitation(
          limitationId: 'attestation-byid-unsupported',
          code: ReleaseEvidenceLimitationCode.noPhysicalPersistence,
          description:
              'Attestation set must be injected; load by ID is not supported',
          impact: 'Attestations may be unavailable',
          resolvable: true,
        ),
      );
      return ResolvedReleaseEvidenceSource<ReleaseAttestationSet>(
        sourceType: ReleaseEvidenceType.unknown,
        resolutionMode: ReleaseEvidenceSourceResolutionMode.unavailable,
        state: ResolvedReleaseEvidenceSourceState.unavailable,
        requestedId: request.attestationSetId,
      );
    }
    return const ResolvedReleaseEvidenceSource<ReleaseAttestationSet>(
      sourceType: ReleaseEvidenceType.unknown,
      resolutionMode: ReleaseEvidenceSourceResolutionMode.notRequested,
      state: ResolvedReleaseEvidenceSourceState.notRequested,
    );
  }

  ResolvedReleaseEvidenceSource<List<ReleaseProvenance>> resolveProvenance(
    ReleaseEvidenceRequest request,
    List<ReleaseEvidenceSourceReference> refs,
    List<ReleaseEvidenceLimitation> limitations,
  ) {
    if (request.provenance.isNotEmpty) {
      refs.add(
        ReleaseEvidenceSourceReference(
          sourceType: ReleaseEvidenceType.provenance,
          resolutionMode: ReleaseEvidenceSourceResolutionMode.injected,
          requestedId: 'provenance',
          resolvedId: 'provenance',
          fingerprint: '${request.provenance.length}',
          projectId: request.releaseContext.projectId,
          availability: ReleaseEvidenceAvailabilityStatus.available,
          compatibility: ReleaseEvidenceCompatibilityStatus.compatible,
        ),
      );
      return ResolvedReleaseEvidenceSource<List<ReleaseProvenance>>(
        sourceType: ReleaseEvidenceType.provenance,
        resolutionMode: ReleaseEvidenceSourceResolutionMode.injected,
        state: ResolvedReleaseEvidenceSourceState.available,
        resolvedArtifact: request.provenance,
        resolvedId: 'provenance',
      );
    }
    if (request.provenanceIds.isNotEmpty) {
      refs.add(_unavailableRef(
        ReleaseEvidenceType.provenance,
        request.provenanceIds.first,
        ReleaseEvidenceSourceResolutionMode.byId,
      ));
      limitations.add(
        const ReleaseEvidenceLimitation(
          limitationId: 'provenance-byid-unsupported',
          code: ReleaseEvidenceLimitationCode.noPhysicalPersistence,
          description:
              'Provenance must be injected; load by ID is not supported',
          impact: 'Provenance may be unavailable',
          resolvable: true,
        ),
      );
      return const ResolvedReleaseEvidenceSource<List<ReleaseProvenance>>(
        sourceType: ReleaseEvidenceType.provenance,
        resolutionMode: ReleaseEvidenceSourceResolutionMode.unavailable,
        state: ResolvedReleaseEvidenceSourceState.unavailable,
      );
    }
    return const ResolvedReleaseEvidenceSource<List<ReleaseProvenance>>(
      sourceType: ReleaseEvidenceType.provenance,
      resolutionMode: ReleaseEvidenceSourceResolutionMode.notRequested,
      state: ResolvedReleaseEvidenceSourceState.notRequested,
      resolvedArtifact: [],
    );
  }

  void _checkProjectMismatch(
    ReleaseEvidenceRequest request,
    ResolvedReleaseEvidenceSource<QualityGateSnapshot> qg,
    List<String> hints,
    List<ReleaseEvidenceLimitation> limitations,
  ) {
    if (!qg.isAvailable) return;
    final qgProject = qg.resolvedArtifact!.metadata.projectId;
    final expected = request.releaseContext.projectId;
    if (qgProject != expected) {
      hints.add('Project mismatch on qualityGate: $qgProject != $expected');
      limitations.add(
        ReleaseEvidenceLimitation(
          limitationId: 'project-mismatch-quality-gate',
          code: ReleaseEvidenceLimitationCode.historicalDataIncomplete,
          description:
              'Quality gate projectId $qgProject differs from release $expected',
          impact: 'Cross-artifact consistency may be reduced',
          resolvable: false,
        ),
      );
    }
  }

  void _checkCommitMismatch(
    ReleaseEvidenceRequest request,
    ResolvedReleaseEvidenceSource<QualityGateSnapshot> qg,
    ResolvedReleaseEvidenceSource<ReleaseDecisionSnapshot> rg,
    List<String> hints,
    List<ReleaseEvidenceLimitation> limitations,
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
    ResolvedReleaseEvidenceSource<dynamic> source,
    List<String> resolved,
    List<String> unresolved,
    List<String> injected,
  ) {
    final name = source.sourceType.wireName;
    switch (source.resolutionMode) {
      case ReleaseEvidenceSourceResolutionMode.injected:
        if (source.isAvailable) {
          injected.add(name);
          resolved.add(name);
        }
      case ReleaseEvidenceSourceResolutionMode.byId:
        if (source.isAvailable) {
          resolved.add(name);
        } else if (source.state !=
            ResolvedReleaseEvidenceSourceState.notRequested) {
          unresolved.add(name);
        }
      case ReleaseEvidenceSourceResolutionMode.latest:
        if (source.isAvailable) {
          resolved.add(name);
        } else {
          unresolved.add(name);
        }
      case ReleaseEvidenceSourceResolutionMode.unavailable:
        unresolved.add(name);
      case ReleaseEvidenceSourceResolutionMode.notRequested:
        break;
    }
  }

  ResolvedReleaseEvidenceSource<ReleaseEvidencePolicy> _resolvedPolicy({
    required ReleaseEvidencePolicy policy,
    required ReleaseEvidenceType sourceType,
    required ReleaseEvidenceSourceResolutionMode mode,
    required List<ReleaseEvidenceSourceReference> refs,
  }) {
    final fingerprint = policy.metadata.fingerprint ?? policy.metadata.policyId;
    refs.add(
      ReleaseEvidenceSourceReference(
        sourceType: sourceType,
        resolutionMode: mode,
        requestedId: policy.metadata.policyId,
        resolvedId: policy.metadata.policyId,
        fingerprint: fingerprint,
        policyId: policy.metadata.policyId,
        policyVersion: policy.metadata.policyVersion,
        availability: ReleaseEvidenceAvailabilityStatus.available,
        compatibility: ReleaseEvidenceCompatibilityStatus.compatible,
      ),
    );
    return ResolvedReleaseEvidenceSource<ReleaseEvidencePolicy>(
      sourceType: sourceType,
      resolutionMode: mode,
      state: ResolvedReleaseEvidenceSourceState.available,
      resolvedArtifact: policy,
      resolvedId: policy.metadata.policyId,
      fingerprint: fingerprint,
      policyId: policy.metadata.policyId,
      policyVersion: policy.metadata.policyVersion,
    );
  }

  ResolvedReleaseEvidenceSource<ReleaseAttestationPolicy>
      _resolvedAttestationPolicy({
    required ReleaseAttestationPolicy policy,
    required ReleaseEvidenceSourceResolutionMode mode,
    required List<ReleaseEvidenceSourceReference> refs,
  }) {
    final fingerprint = policy.metadata.fingerprint ?? policy.metadata.policyId;
    refs.add(
      ReleaseEvidenceSourceReference(
        sourceType: ReleaseEvidenceType.unknown,
        resolutionMode: mode,
        requestedId: policy.metadata.policyId,
        resolvedId: policy.metadata.policyId,
        fingerprint: fingerprint,
        policyId: policy.metadata.policyId,
        policyVersion: policy.metadata.policyVersion,
        availability: ReleaseEvidenceAvailabilityStatus.available,
        compatibility: ReleaseEvidenceCompatibilityStatus.compatible,
      ),
    );
    return ResolvedReleaseEvidenceSource<ReleaseAttestationPolicy>(
      sourceType: ReleaseEvidenceType.unknown,
      resolutionMode: mode,
      state: ResolvedReleaseEvidenceSourceState.available,
      resolvedArtifact: policy,
      resolvedId: policy.metadata.policyId,
      fingerprint: fingerprint,
      policyId: policy.metadata.policyId,
      policyVersion: policy.metadata.policyVersion,
    );
  }

  ResolvedReleaseEvidenceSource<ReleaseVerificationPolicy>
      _resolvedVerificationPolicy({
    required ReleaseVerificationPolicy policy,
    required ReleaseEvidenceSourceResolutionMode mode,
    required List<ReleaseEvidenceSourceReference> refs,
  }) {
    final fingerprint = policy.metadata.fingerprint ?? policy.metadata.policyId;
    refs.add(
      ReleaseEvidenceSourceReference(
        sourceType: ReleaseEvidenceType.unknown,
        resolutionMode: mode,
        requestedId: policy.metadata.policyId,
        resolvedId: policy.metadata.policyId,
        fingerprint: fingerprint,
        policyId: policy.metadata.policyId,
        policyVersion: policy.metadata.policyVersion,
        availability: ReleaseEvidenceAvailabilityStatus.available,
        compatibility: ReleaseEvidenceCompatibilityStatus.compatible,
      ),
    );
    return ResolvedReleaseEvidenceSource<ReleaseVerificationPolicy>(
      sourceType: ReleaseEvidenceType.unknown,
      resolutionMode: mode,
      state: ResolvedReleaseEvidenceSourceState.available,
      resolvedArtifact: policy,
      resolvedId: policy.metadata.policyId,
      fingerprint: fingerprint,
      policyId: policy.metadata.policyId,
      policyVersion: policy.metadata.policyVersion,
    );
  }

  ResolvedReleaseEvidenceSource<QualityGateSnapshot> _availableQg(
    QualityGateSnapshot snapshot,
    ReleaseEvidenceSourceReference ref,
  ) {
    return ResolvedReleaseEvidenceSource<QualityGateSnapshot>(
      sourceType: ReleaseEvidenceType.qualityGate,
      resolutionMode: ref.resolutionMode,
      state: ResolvedReleaseEvidenceSourceState.available,
      resolvedArtifact: snapshot,
      resolvedId: ref.resolvedId,
      fingerprint: ref.fingerprint,
      projectId: ref.projectId,
      commitId: ref.commitId,
      policyId: ref.policyId,
      policyVersion: ref.policyVersion,
    );
  }

  ResolvedReleaseEvidenceSource<QualityGateSnapshot> _unavailableQg(
    String? requestedId,
  ) {
    return ResolvedReleaseEvidenceSource<QualityGateSnapshot>(
      sourceType: ReleaseEvidenceType.qualityGate,
      resolutionMode: ReleaseEvidenceSourceResolutionMode.injected,
      state: ResolvedReleaseEvidenceSourceState.unavailable,
      requestedId: requestedId,
    );
  }

  ResolvedReleaseEvidenceSource<QualityGateSnapshot> _notRequestedQg() {
    return const ResolvedReleaseEvidenceSource<QualityGateSnapshot>(
      sourceType: ReleaseEvidenceType.qualityGate,
      resolutionMode: ReleaseEvidenceSourceResolutionMode.injected,
      state: ResolvedReleaseEvidenceSourceState.notRequested,
    );
  }

  ResolvedReleaseEvidenceSource<ReleaseDecisionSnapshot> _availableRg(
    ReleaseDecisionSnapshot snapshot,
    ReleaseEvidenceSourceReference ref,
  ) {
    return ResolvedReleaseEvidenceSource<ReleaseDecisionSnapshot>(
      sourceType: ReleaseEvidenceType.releaseGovernance,
      resolutionMode: ref.resolutionMode,
      state: ResolvedReleaseEvidenceSourceState.available,
      resolvedArtifact: snapshot,
      resolvedId: ref.resolvedId,
      fingerprint: ref.fingerprint,
      projectId: ref.projectId,
      commitId: ref.commitId,
      policyId: ref.policyId,
      policyVersion: ref.policyVersion,
    );
  }

  ResolvedReleaseEvidenceSource<ReleaseDecisionSnapshot> _unavailableRg(
    String? requestedId,
  ) {
    return ResolvedReleaseEvidenceSource<ReleaseDecisionSnapshot>(
      sourceType: ReleaseEvidenceType.releaseGovernance,
      resolutionMode: ReleaseEvidenceSourceResolutionMode.injected,
      state: ResolvedReleaseEvidenceSourceState.unavailable,
      requestedId: requestedId,
    );
  }

  ResolvedReleaseEvidenceSource<ReleaseDecisionSnapshot> _notRequestedRg() {
    return const ResolvedReleaseEvidenceSource<ReleaseDecisionSnapshot>(
      sourceType: ReleaseEvidenceType.releaseGovernance,
      resolutionMode: ReleaseEvidenceSourceResolutionMode.injected,
      state: ResolvedReleaseEvidenceSourceState.notRequested,
    );
  }

  ResolvedReleaseEvidenceSource<T> _unavailablePolicy<T>(
    ReleaseEvidenceType sourceType,
    String policyId,
  ) {
    return ResolvedReleaseEvidenceSource<T>(
      sourceType: sourceType,
      resolutionMode: ReleaseEvidenceSourceResolutionMode.injected,
      state: ResolvedReleaseEvidenceSourceState.unavailable,
      requestedId: policyId,
    );
  }

  ReleaseEvidenceSourceReference _qgRef(
    QualityGateSnapshot snapshot,
    ReleaseEvidenceSourceResolutionMode mode,
  ) {
    return ReleaseEvidenceSourceReference(
      sourceType: ReleaseEvidenceType.qualityGate,
      resolutionMode: mode,
      requestedId: snapshot.metadata.qualityGateSnapshotId,
      resolvedId: snapshot.metadata.qualityGateSnapshotId,
      fingerprint: snapshot.metadata.qualityGateFingerprint,
      projectId: snapshot.metadata.projectId,
      commitId: snapshot.metadata.commitId,
      policyId: snapshot.metadata.policyId,
      policyVersion: snapshot.metadata.policyVersion,
      availability: ReleaseEvidenceAvailabilityStatus.available,
      compatibility: ReleaseEvidenceCompatibilityStatus.compatible,
    );
  }

  ReleaseEvidenceSourceReference _rgRef(
    ReleaseDecisionSnapshot snapshot,
    ReleaseEvidenceSourceResolutionMode mode,
  ) {
    return ReleaseEvidenceSourceReference(
      sourceType: ReleaseEvidenceType.releaseGovernance,
      resolutionMode: mode,
      requestedId: snapshot.metadata.snapshotId,
      resolvedId: snapshot.metadata.snapshotId,
      fingerprint: snapshot.fingerprint,
      projectId: snapshot.metadata.projectId,
      commitId: snapshot.metadata.commitId,
      policyId: snapshot.metadata.policyId,
      policyVersion: snapshot.metadata.policyVersion,
      availability: ReleaseEvidenceAvailabilityStatus.available,
      compatibility: ReleaseEvidenceCompatibilityStatus.compatible,
    );
  }

  ReleaseEvidenceSourceReference _unavailableRef(
    ReleaseEvidenceType type,
    String artifactId,
    ReleaseEvidenceSourceResolutionMode mode,
  ) {
    return ReleaseEvidenceSourceReference(
      sourceType: type,
      resolutionMode: mode,
      requestedId: artifactId,
      resolvedId: artifactId,
      compatibility: ReleaseEvidenceCompatibilityStatus.unknown,
      limitations: const ['source unavailable'],
    );
  }
}
