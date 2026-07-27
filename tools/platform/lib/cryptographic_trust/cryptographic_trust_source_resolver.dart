import '../interfaces/cicd_integration_provider.dart';
import '../interfaces/release_evidence_provider.dart';
import '../interfaces/release_supply_chain_provider.dart';
import '../models/cicd_integration/cicd_integration_snapshot.dart';
import '../models/cryptographic_trust/cryptographic_trust_enums.dart';
import '../models/cryptographic_trust/cryptographic_trust_evaluation_request.dart';
import '../models/cryptographic_trust/cryptographic_trust_evaluation_result.dart';
import '../models/cryptographic_trust/cryptographic_trust_fingerprint.dart';
import '../models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import '../models/cryptographic_trust/cryptographic_trust_operation_message.dart';
import '../models/cryptographic_trust/cryptographic_trust_policy.dart';
import '../models/cryptographic_trust/cryptographic_trust_source_reference.dart';
import '../models/cryptographic_trust/cryptographic_verification_models.dart';
import '../models/cryptographic_trust/policies/release_trust_policy_v1.dart';
import '../models/cryptographic_trust/resolved_cryptographic_trust_sources.dart';
import '../models/release_evidence/release_evidence_bundle.dart';
import '../models/release_supply_chain/release_supply_chain_snapshot.dart';
import 'cryptographic_trust_policy_registry.dart';

const _releaseEvidenceBundleIdKey = 'releaseEvidenceBundleId';
const _releaseSupplyChainSnapshotIdKey = 'releaseSupplyChainSnapshotId';
const _cicdIntegrationSnapshotIdKey = 'cicdIntegrationSnapshotId';

/// Resolves cryptographic trust source artifacts without executing origin engines.
///
/// Only load/latest provider methods are used — never evaluate, evaluateAndPublish,
/// publish, or sign on upstream providers.
class CryptographicTrustSourceResolver {
  CryptographicTrustSourceResolver({
    required ReleaseEvidenceProvider releaseEvidenceProvider,
    required ReleaseSupplyChainProvider releaseSupplyChainProvider,
    required CicdIntegrationProvider cicdIntegrationProvider,
    CryptographicTrustPolicyRegistry? trustPolicyRegistry,
  })  : _releaseEvidenceProvider = releaseEvidenceProvider,
        _releaseSupplyChainProvider = releaseSupplyChainProvider,
        _cicdIntegrationProvider = cicdIntegrationProvider,
        _trustPolicyRegistry =
            trustPolicyRegistry ?? CryptographicTrustPolicyRegistry();

  final ReleaseEvidenceProvider _releaseEvidenceProvider;
  final ReleaseSupplyChainProvider _releaseSupplyChainProvider;
  final CicdIntegrationProvider _cicdIntegrationProvider;
  final CryptographicTrustPolicyRegistry _trustPolicyRegistry;

  Future<ResolvedCryptographicTrustSources> resolveAll(
    CryptographicTrustEvaluationRequest request, {
    CryptographicTrustPolicy? injectedTrustPolicy,
  }) async {
    final refs = <CryptographicTrustSourceReference>[];
    final messages = <CryptographicTrustOperationMessage>[];
    final hints = <String>[];

    final resolved = <String>[];
    final unresolved = <String>[];
    final injected = <String>[];

    final verificationRequest = _resolveVerificationRequest(request, refs);
    _trackResolution(verificationRequest, resolved, unresolved, injected);

    final releaseEvidenceBundle = await resolveReleaseEvidenceBundle(
      request,
      refs,
      messages,
    );
    _trackResolution(releaseEvidenceBundle, resolved, unresolved, injected);

    final releaseSupplyChainSnapshot = await resolveReleaseSupplyChainSnapshot(
      request,
      refs,
      messages,
    );
    _trackResolution(
      releaseSupplyChainSnapshot,
      resolved,
      unresolved,
      injected,
    );

    final cicdIntegrationSnapshot = await resolveCicdIntegrationSnapshot(
      request,
      refs,
      messages,
    );
    _trackResolution(cicdIntegrationSnapshot, resolved, unresolved, injected);

    final trustPolicy = resolveTrustPolicy(
      request,
      refs,
      injectedTrustPolicy,
      messages,
    );
    _trackResolution(trustPolicy, resolved, unresolved, injected);

    _validateProjectAndRelease(
      request,
      verificationRequest,
      releaseEvidenceBundle,
      releaseSupplyChainSnapshot,
      cicdIntegrationSnapshot,
      hints,
      messages,
    );

    refs.sort(
      (a, b) => a.sourceType.wireName.compareTo(b.sourceType.wireName),
    );

    final summary = CryptographicTrustSourceResolutionSummary(
      status: _deriveResolutionStatus(resolved, unresolved),
      resolvedSources: resolved,
      unresolvedSources: unresolved,
      injectedSources: injected,
      fingerprint: _sourceReferencesFingerprint(refs),
    );

    return ResolvedCryptographicTrustSources(
      verificationRequest: verificationRequest,
      releaseEvidenceBundle: releaseEvidenceBundle,
      releaseSupplyChainSnapshot: releaseSupplyChainSnapshot,
      cicdIntegrationSnapshot: cicdIntegrationSnapshot,
      trustPolicy: trustPolicy,
      sourceReferences: refs,
      resolutionSummary: summary,
      messages: messages,
      compatibilityHints: hints,
    );
  }

  Future<ResolvedCryptographicTrustSource<ReleaseEvidenceBundle>>
      resolveReleaseEvidenceBundle(
    CryptographicTrustEvaluationRequest request,
    List<CryptographicTrustSourceReference> refs,
    List<CryptographicTrustOperationMessage> messages,
  ) async {
    if (request.releaseEvidenceBundle != null) {
      final bundle = request.releaseEvidenceBundle!;
      refs.add(
        _evidenceRef(bundle, CryptographicTrustSourceResolutionMode.injected),
      );
      return _availableEvidence(bundle, refs.last);
    }

    final bundleId = request.metadata[_releaseEvidenceBundleIdKey];
    if (bundleId != null && bundleId.isNotEmpty) {
      final loaded = await _releaseEvidenceProvider.load(bundleId);
      if (loaded != null) {
        refs.add(
          _evidenceRef(loaded, CryptographicTrustSourceResolutionMode.byId),
        );
        return _availableEvidence(loaded, refs.last);
      }
      refs.add(
        _unavailableRef(
          CryptographicSourceType.releaseEvidence,
          bundleId,
          CryptographicTrustSourceResolutionMode.byId,
        ),
      );
      messages.add(
        CryptographicTrustOperationMessage(
          messageId: 'missing-release-evidence-$bundleId',
          code: 'source-unavailable',
          message: 'Release evidence bundle $bundleId unavailable',
          severity: CryptographicIssueSeverity.warning,
          operation: CryptographicTrustOperation.resolve,
          sourceType: CryptographicSourceType.releaseEvidence,
        ),
      );
      return _unavailableEvidence(bundleId);
    }

    if (request.useLatest) {
      final loaded = await _releaseEvidenceProvider.latest(
        projectId: request.projectId,
        releaseId: request.releaseId,
      );
      if (loaded != null) {
        refs.add(
          _evidenceRef(loaded, CryptographicTrustSourceResolutionMode.latest),
        );
        return _availableEvidence(loaded, refs.last);
      }
      messages.add(
        const CryptographicTrustOperationMessage(
          messageId: 'latest-release-evidence-missing',
          code: 'source-unavailable',
          message: 'Latest release evidence bundle unavailable',
          severity: CryptographicIssueSeverity.warning,
          operation: CryptographicTrustOperation.resolve,
          sourceType: CryptographicSourceType.releaseEvidence,
        ),
      );
    }

    return _notRequestedEvidence();
  }

  Future<ResolvedCryptographicTrustSource<ReleaseSupplyChainSnapshot>>
      resolveReleaseSupplyChainSnapshot(
    CryptographicTrustEvaluationRequest request,
    List<CryptographicTrustSourceReference> refs,
    List<CryptographicTrustOperationMessage> messages,
  ) async {
    if (request.releaseSupplyChainSnapshot != null) {
      final snapshot = request.releaseSupplyChainSnapshot!;
      refs.add(
        _supplyChainRef(
            snapshot, CryptographicTrustSourceResolutionMode.injected),
      );
      return _availableSupplyChain(snapshot, refs.last);
    }

    final snapshotId = request.metadata[_releaseSupplyChainSnapshotIdKey];
    if (snapshotId != null && snapshotId.isNotEmpty) {
      final loaded = await _releaseSupplyChainProvider.load(snapshotId);
      if (loaded != null) {
        refs.add(
          _supplyChainRef(loaded, CryptographicTrustSourceResolutionMode.byId),
        );
        return _availableSupplyChain(loaded, refs.last);
      }
      refs.add(
        _unavailableRef(
          CryptographicSourceType.releaseSupplyChain,
          snapshotId,
          CryptographicTrustSourceResolutionMode.byId,
        ),
      );
      messages.add(
        CryptographicTrustOperationMessage(
          messageId: 'missing-supply-chain-$snapshotId',
          code: 'source-unavailable',
          message: 'Release supply chain snapshot $snapshotId unavailable',
          severity: CryptographicIssueSeverity.warning,
          operation: CryptographicTrustOperation.resolve,
          sourceType: CryptographicSourceType.releaseSupplyChain,
        ),
      );
      return _unavailableSupplyChain(snapshotId);
    }

    if (request.useLatest) {
      final loaded = await _releaseSupplyChainProvider.latest(
        projectId: request.projectId,
        releaseId: request.releaseId,
      );
      if (loaded != null) {
        refs.add(
          _supplyChainRef(
              loaded, CryptographicTrustSourceResolutionMode.latest),
        );
        return _availableSupplyChain(loaded, refs.last);
      }
      messages.add(
        const CryptographicTrustOperationMessage(
          messageId: 'latest-supply-chain-missing',
          code: 'source-unavailable',
          message: 'Latest release supply chain snapshot unavailable',
          severity: CryptographicIssueSeverity.warning,
          operation: CryptographicTrustOperation.resolve,
          sourceType: CryptographicSourceType.releaseSupplyChain,
        ),
      );
    }

    return _notRequestedSupplyChain();
  }

  Future<ResolvedCryptographicTrustSource<CicdIntegrationSnapshot>>
      resolveCicdIntegrationSnapshot(
    CryptographicTrustEvaluationRequest request,
    List<CryptographicTrustSourceReference> refs,
    List<CryptographicTrustOperationMessage> messages,
  ) async {
    if (request.cicdIntegrationSnapshot != null) {
      final snapshot = request.cicdIntegrationSnapshot!;
      refs.add(
        _cicdRef(snapshot, CryptographicTrustSourceResolutionMode.injected),
      );
      return _availableCicd(snapshot, refs.last);
    }

    final snapshotId = request.metadata[_cicdIntegrationSnapshotIdKey];
    if (snapshotId != null && snapshotId.isNotEmpty) {
      final loaded = await _cicdIntegrationProvider.load(snapshotId);
      if (loaded != null) {
        refs.add(_cicdRef(loaded, CryptographicTrustSourceResolutionMode.byId));
        return _availableCicd(loaded, refs.last);
      }
      refs.add(
        _unavailableRef(
          CryptographicSourceType.cicdIntegration,
          snapshotId,
          CryptographicTrustSourceResolutionMode.byId,
        ),
      );
      messages.add(
        CryptographicTrustOperationMessage(
          messageId: 'missing-cicd-$snapshotId',
          code: 'source-unavailable',
          message: 'CI/CD integration snapshot $snapshotId unavailable',
          severity: CryptographicIssueSeverity.warning,
          operation: CryptographicTrustOperation.resolve,
          sourceType: CryptographicSourceType.cicdIntegration,
        ),
      );
      return _unavailableCicd(snapshotId);
    }

    if (request.useLatest) {
      final loaded = await _cicdIntegrationProvider.latest(
        projectId: request.projectId,
        releaseId: request.releaseId,
      );
      if (loaded != null) {
        refs.add(
          _cicdRef(loaded, CryptographicTrustSourceResolutionMode.latest),
        );
        return _availableCicd(loaded, refs.last);
      }
      messages.add(
        const CryptographicTrustOperationMessage(
          messageId: 'latest-cicd-missing',
          code: 'source-unavailable',
          message: 'Latest CI/CD integration snapshot unavailable',
          severity: CryptographicIssueSeverity.warning,
          operation: CryptographicTrustOperation.resolve,
          sourceType: CryptographicSourceType.cicdIntegration,
        ),
      );
    }

    return _notRequestedCicd();
  }

  ResolvedCryptographicTrustSource<CryptographicTrustPolicy> resolveTrustPolicy(
    CryptographicTrustEvaluationRequest request,
    List<CryptographicTrustSourceReference> refs,
    CryptographicTrustPolicy? injectedPolicy,
    List<CryptographicTrustOperationMessage> messages,
  ) {
    if (injectedPolicy != null) {
      return _resolvedTrustPolicy(
        policy: injectedPolicy,
        mode: CryptographicTrustSourceResolutionMode.injected,
        refs: refs,
      );
    }

    final reference = request.policyReference;
    final policyId = reference?.policyId ?? ReleaseTrustPolicyV1.policyId;
    final policy = _trustPolicyRegistry.resolve(
      policyId: policyId,
      policyVersion: reference?.policyVersion,
      allowCandidate: true,
      useLatest: reference == null,
    );

    if (policy != null) {
      return _resolvedTrustPolicy(
        policy: policy,
        mode: reference == null
            ? CryptographicTrustSourceResolutionMode.latest
            : CryptographicTrustSourceResolutionMode.byId,
        refs: refs,
      );
    }

    messages.add(
      CryptographicTrustOperationMessage(
        messageId: 'missing-trust-policy-$policyId',
        code: 'source-unavailable',
        message: 'Cryptographic trust policy $policyId unavailable',
        severity: CryptographicIssueSeverity.error,
        operation: CryptographicTrustOperation.resolve,
        sourceType: CryptographicSourceType.custom,
      ),
    );
    return _unavailablePolicy(policyId);
  }

  ResolvedCryptographicTrustSource<CryptographicVerificationRequest>
      _resolveVerificationRequest(
    CryptographicTrustEvaluationRequest request,
    List<CryptographicTrustSourceReference> refs,
  ) {
    final verificationRequest = request.verificationRequest;
    const mode = CryptographicTrustSourceResolutionMode.injected;
    refs.add(_verificationRequestRef(verificationRequest, mode));
    return _availableVerificationRequest(
      verificationRequest,
      refs.last,
      mode,
    );
  }

  void _validateProjectAndRelease(
    CryptographicTrustEvaluationRequest request,
    ResolvedCryptographicTrustSource<CryptographicVerificationRequest>
        verificationRequest,
    ResolvedCryptographicTrustSource<ReleaseEvidenceBundle> evidence,
    ResolvedCryptographicTrustSource<ReleaseSupplyChainSnapshot> supplyChain,
    ResolvedCryptographicTrustSource<CicdIntegrationSnapshot> cicd,
    List<String> hints,
    List<CryptographicTrustOperationMessage> messages,
  ) {
    if (verificationRequest.isAvailable) {
      final vr = verificationRequest.resolvedArtifact!;
      if (vr.projectId != request.projectId) {
        hints.add(
          'Project mismatch on verificationRequest: '
          '${vr.projectId} != ${request.projectId}',
        );
      }
      if (request.releaseId != null &&
          vr.releaseId != null &&
          vr.releaseId != request.releaseId) {
        hints.add(
          'Release mismatch on verificationRequest: '
          '${vr.releaseId} != ${request.releaseId}',
        );
      }
    }

    if (evidence.isAvailable) {
      final bundle = evidence.resolvedArtifact!;
      if (bundle.metadata.projectId != request.projectId) {
        hints.add(
          'Project mismatch on releaseEvidence: '
          '${bundle.metadata.projectId} != ${request.projectId}',
        );
      }
    }

    if (supplyChain.isAvailable) {
      final snapshot = supplyChain.resolvedArtifact!;
      if (snapshot.metadata.projectId != request.projectId) {
        hints.add(
          'Project mismatch on releaseSupplyChain: '
          '${snapshot.metadata.projectId} != ${request.projectId}',
        );
      }
    }

    if (cicd.isAvailable) {
      final snapshot = cicd.resolvedArtifact!;
      if (snapshot.metadata.projectId != request.projectId) {
        hints.add(
          'Project mismatch on cicdIntegration: '
          '${snapshot.metadata.projectId} != ${request.projectId}',
        );
      }
    }
  }

  void _trackResolution(
    ResolvedCryptographicTrustSource<dynamic> source,
    List<String> resolved,
    List<String> unresolved,
    List<String> injected,
  ) {
    final name = source.sourceType.wireName;
    switch (source.resolutionMode) {
      case CryptographicTrustSourceResolutionMode.injected:
        if (source.isAvailable) {
          injected.add(name);
          resolved.add(name);
        }
      case CryptographicTrustSourceResolutionMode.byId:
        if (source.isAvailable) {
          resolved.add(name);
        } else if (source.state != CryptographicTrustSourceState.notRequested) {
          unresolved.add(name);
        }
      case CryptographicTrustSourceResolutionMode.latest:
        if (source.isAvailable) {
          resolved.add(name);
        } else if (source.state != CryptographicTrustSourceState.notRequested) {
          unresolved.add(name);
        }
      case CryptographicTrustSourceResolutionMode.notRequested:
        break;
    }
  }

  CryptographicTrustSourceResolutionStatus _deriveResolutionStatus(
    List<String> resolved,
    List<String> unresolved,
  ) {
    if (resolved.isEmpty) {
      return CryptographicTrustSourceResolutionStatus.unavailable;
    }
    if (unresolved.isEmpty) {
      return CryptographicTrustSourceResolutionStatus.complete;
    }
    return CryptographicTrustSourceResolutionStatus.partial;
  }

  String _sourceReferencesFingerprint(
    List<CryptographicTrustSourceReference> refs,
  ) {
    final comparable = refs.map((e) => e.toComparableJson()).toList()
      ..sort(
        (a, b) => a['sourceId'].toString().compareTo(b['sourceId'].toString()),
      );
    return CryptographicTrustFingerprint.fromComparableJson({
      'sourceReferences': comparable,
    });
  }

  ResolvedCryptographicTrustSource<CryptographicTrustPolicy>
      _resolvedTrustPolicy({
    required CryptographicTrustPolicy policy,
    required CryptographicTrustSourceResolutionMode mode,
    required List<CryptographicTrustSourceReference> refs,
  }) {
    final fingerprint = CryptographicTrustFingerprint.fromComparableJson(
      policy.toComparableJson(),
    );
    refs.add(
      CryptographicTrustSourceReference(
        sourceType: CryptographicSourceType.custom,
        sourceId: policy.policyId,
        projectId: policy.metadata['projectId'] ?? '',
        releaseId: policy.metadata['releaseId'],
        fingerprint: fingerprint,
        version: policy.version,
        metadata: {
          'kind': 'trustPolicy',
          'resolutionMode': mode.wireName,
        },
      ),
    );
    return ResolvedCryptographicTrustSource<CryptographicTrustPolicy>(
      sourceType: CryptographicSourceType.custom,
      resolutionMode: mode,
      state: CryptographicTrustSourceState.available,
      resolvedArtifact: policy,
      resolvedId: policy.policyId,
      fingerprint: fingerprint,
      policyId: policy.policyId,
      policyVersion: policy.version,
    );
  }

  ResolvedCryptographicTrustSource<CryptographicVerificationRequest>
      _availableVerificationRequest(
    CryptographicVerificationRequest request,
    CryptographicTrustSourceReference ref,
    CryptographicTrustSourceResolutionMode mode,
  ) {
    return ResolvedCryptographicTrustSource<CryptographicVerificationRequest>(
      sourceType: CryptographicSourceType.custom,
      resolutionMode: mode,
      state: CryptographicTrustSourceState.available,
      resolvedArtifact: request,
      resolvedId: ref.sourceId,
      fingerprint: ref.fingerprint,
      projectId: ref.projectId,
      releaseId: ref.releaseId,
    );
  }

  ResolvedCryptographicTrustSource<ReleaseEvidenceBundle> _availableEvidence(
    ReleaseEvidenceBundle bundle,
    CryptographicTrustSourceReference ref,
  ) {
    return ResolvedCryptographicTrustSource<ReleaseEvidenceBundle>(
      sourceType: CryptographicSourceType.releaseEvidence,
      resolutionMode: _modeFromRef(ref),
      state: CryptographicTrustSourceState.available,
      resolvedArtifact: bundle,
      resolvedId: ref.sourceId,
      fingerprint: ref.fingerprint,
      projectId: ref.projectId,
      releaseId: ref.releaseId,
    );
  }

  ResolvedCryptographicTrustSource<ReleaseEvidenceBundle> _unavailableEvidence(
    String? requestedId,
  ) {
    return ResolvedCryptographicTrustSource<ReleaseEvidenceBundle>(
      sourceType: CryptographicSourceType.releaseEvidence,
      resolutionMode: CryptographicTrustSourceResolutionMode.byId,
      state: CryptographicTrustSourceState.unavailable,
      requestedId: requestedId,
    );
  }

  ResolvedCryptographicTrustSource<ReleaseEvidenceBundle>
      _notRequestedEvidence() {
    return const ResolvedCryptographicTrustSource<ReleaseEvidenceBundle>(
      sourceType: CryptographicSourceType.releaseEvidence,
      resolutionMode: CryptographicTrustSourceResolutionMode.notRequested,
      state: CryptographicTrustSourceState.notRequested,
    );
  }

  ResolvedCryptographicTrustSource<ReleaseSupplyChainSnapshot>
      _availableSupplyChain(
    ReleaseSupplyChainSnapshot snapshot,
    CryptographicTrustSourceReference ref,
  ) {
    return ResolvedCryptographicTrustSource<ReleaseSupplyChainSnapshot>(
      sourceType: CryptographicSourceType.releaseSupplyChain,
      resolutionMode: _modeFromRef(ref),
      state: CryptographicTrustSourceState.available,
      resolvedArtifact: snapshot,
      resolvedId: ref.sourceId,
      fingerprint: ref.fingerprint,
      projectId: ref.projectId,
      releaseId: ref.releaseId,
    );
  }

  ResolvedCryptographicTrustSource<ReleaseSupplyChainSnapshot>
      _unavailableSupplyChain(String? requestedId) {
    return ResolvedCryptographicTrustSource<ReleaseSupplyChainSnapshot>(
      sourceType: CryptographicSourceType.releaseSupplyChain,
      resolutionMode: CryptographicTrustSourceResolutionMode.byId,
      state: CryptographicTrustSourceState.unavailable,
      requestedId: requestedId,
    );
  }

  ResolvedCryptographicTrustSource<ReleaseSupplyChainSnapshot>
      _notRequestedSupplyChain() {
    return const ResolvedCryptographicTrustSource<ReleaseSupplyChainSnapshot>(
      sourceType: CryptographicSourceType.releaseSupplyChain,
      resolutionMode: CryptographicTrustSourceResolutionMode.notRequested,
      state: CryptographicTrustSourceState.notRequested,
    );
  }

  ResolvedCryptographicTrustSource<CicdIntegrationSnapshot> _availableCicd(
    CicdIntegrationSnapshot snapshot,
    CryptographicTrustSourceReference ref,
  ) {
    return ResolvedCryptographicTrustSource<CicdIntegrationSnapshot>(
      sourceType: CryptographicSourceType.cicdIntegration,
      resolutionMode: _modeFromRef(ref),
      state: CryptographicTrustSourceState.available,
      resolvedArtifact: snapshot,
      resolvedId: ref.sourceId,
      fingerprint: ref.fingerprint,
      projectId: ref.projectId,
      releaseId: ref.releaseId,
    );
  }

  ResolvedCryptographicTrustSource<CicdIntegrationSnapshot> _unavailableCicd(
    String? requestedId,
  ) {
    return ResolvedCryptographicTrustSource<CicdIntegrationSnapshot>(
      sourceType: CryptographicSourceType.cicdIntegration,
      resolutionMode: CryptographicTrustSourceResolutionMode.byId,
      state: CryptographicTrustSourceState.unavailable,
      requestedId: requestedId,
    );
  }

  ResolvedCryptographicTrustSource<CicdIntegrationSnapshot>
      _notRequestedCicd() {
    return const ResolvedCryptographicTrustSource<CicdIntegrationSnapshot>(
      sourceType: CryptographicSourceType.cicdIntegration,
      resolutionMode: CryptographicTrustSourceResolutionMode.notRequested,
      state: CryptographicTrustSourceState.notRequested,
    );
  }

  ResolvedCryptographicTrustSource<CryptographicTrustPolicy> _unavailablePolicy(
    String policyId,
  ) {
    return ResolvedCryptographicTrustSource<CryptographicTrustPolicy>(
      sourceType: CryptographicSourceType.custom,
      resolutionMode: CryptographicTrustSourceResolutionMode.byId,
      state: CryptographicTrustSourceState.unavailable,
      requestedId: policyId,
    );
  }

  CryptographicTrustSourceReference _verificationRequestRef(
    CryptographicVerificationRequest request,
    CryptographicTrustSourceResolutionMode mode,
  ) {
    return CryptographicTrustSourceReference(
      sourceType: CryptographicSourceType.custom,
      sourceId: request.requestId,
      projectId: request.projectId,
      releaseId: request.releaseId,
      fingerprint: CryptographicTrustFingerprint.fromComparableJson(
        request.toComparableJson(),
      ),
      metadata: {
        'kind': 'verificationRequest',
        'resolutionMode': mode.wireName,
      },
    );
  }

  CryptographicTrustSourceReference _evidenceRef(
    ReleaseEvidenceBundle bundle,
    CryptographicTrustSourceResolutionMode mode,
  ) {
    return CryptographicTrustSourceReference(
      sourceType: CryptographicSourceType.releaseEvidence,
      sourceId: bundle.metadata.bundleId,
      projectId: bundle.metadata.projectId,
      releaseId: bundle.metadata.releaseId,
      fingerprint: bundle.fingerprint,
      metadata: {'resolutionMode': mode.wireName},
    );
  }

  CryptographicTrustSourceReference _supplyChainRef(
    ReleaseSupplyChainSnapshot snapshot,
    CryptographicTrustSourceResolutionMode mode,
  ) {
    return CryptographicTrustSourceReference(
      sourceType: CryptographicSourceType.releaseSupplyChain,
      sourceId: snapshot.metadata.supplyChainSnapshotId,
      projectId: snapshot.metadata.projectId,
      releaseId: snapshot.metadata.releaseId,
      fingerprint: snapshot.fingerprint,
      metadata: {'resolutionMode': mode.wireName},
    );
  }

  CryptographicTrustSourceReference _cicdRef(
    CicdIntegrationSnapshot snapshot,
    CryptographicTrustSourceResolutionMode mode,
  ) {
    return CryptographicTrustSourceReference(
      sourceType: CryptographicSourceType.cicdIntegration,
      sourceId: snapshot.metadata.cicdIntegrationSnapshotId,
      projectId: snapshot.metadata.projectId,
      releaseId: snapshot.metadata.releaseId,
      fingerprint: snapshot.fingerprint,
      metadata: {'resolutionMode': mode.wireName},
    );
  }

  CryptographicTrustSourceReference _unavailableRef(
    CryptographicSourceType type,
    String sourceId,
    CryptographicTrustSourceResolutionMode mode,
  ) {
    return CryptographicTrustSourceReference(
      sourceType: type,
      sourceId: sourceId,
      projectId: '',
      fingerprint: 'unavailable:$sourceId',
      metadata: {
        'resolutionMode': mode.wireName,
        'unavailable': 'true',
      },
    );
  }

  CryptographicTrustSourceResolutionMode _modeFromRef(
    CryptographicTrustSourceReference ref,
  ) {
    final mode = ref.metadata['resolutionMode'];
    if (mode == null) {
      return CryptographicTrustSourceResolutionMode.injected;
    }
    return CryptographicTrustSourceResolutionModeX.fromWireName(mode);
  }
}
