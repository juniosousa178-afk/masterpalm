import '../cryptographic_trust/cryptographic_algorithm_registry.dart';
import '../cryptographic_trust/cryptographic_attestation_verification_service.dart';
import '../cryptographic_trust/cryptographic_digest_service.dart';
import '../cryptographic_trust/cryptographic_revocation_evaluator.dart';
import '../cryptographic_trust/cryptographic_signature_verification_service.dart';
import '../cryptographic_trust/cryptographic_signing_service.dart';
import '../cryptographic_trust/cryptographic_transparency_evaluator.dart';
import '../cryptographic_trust/cryptographic_trust_chain_builder.dart';
import '../cryptographic_trust/cryptographic_trust_collector.dart';
import '../cryptographic_trust/cryptographic_trust_engine.dart';
import '../cryptographic_trust/cryptographic_trust_exceptions.dart';
import '../cryptographic_trust/cryptographic_trust_policy_evaluators.dart';
import '../cryptographic_trust/cryptographic_trust_policy_registry.dart';
import '../cryptographic_trust/cryptographic_trust_snapshot_builder.dart';
import '../cryptographic_trust/cryptographic_trust_snapshot_validator.dart';
import '../cryptographic_trust/cryptographic_trust_source_resolver.dart';
import '../cryptographic_trust/interfaces/cryptographic_public_key_resolver.dart';
import '../cryptographic_trust/interfaces/cryptographic_signer.dart';
import '../cryptographic_trust/interfaces/cryptographic_signing_key_provider.dart';
import '../cryptographic_trust/stores/cryptographic_trust_store.dart';
import '../interfaces/cryptographic_trust_provider.dart';
import '../models/cryptographic_trust/collected_cryptographic_trust_material.dart';
import '../models/cryptographic_trust/cryptographic_attestation_models.dart';
import '../models/cryptographic_trust/cryptographic_key_reference.dart';
import '../models/cryptographic_trust/cryptographic_operation_context.dart';
import '../models/cryptographic_trust/cryptographic_signature_envelope.dart';
import '../models/cryptographic_trust/cryptographic_trust_digest.dart';
import '../models/cryptographic_trust/cryptographic_trust_enums.dart';
import '../models/cryptographic_trust/cryptographic_trust_evaluation_request.dart';
import '../models/cryptographic_trust/cryptographic_trust_evaluation_result.dart';
import '../models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import '../models/cryptographic_trust/cryptographic_trust_policy.dart';
import '../models/cryptographic_trust/cryptographic_trust_policy_reference.dart';
import '../models/cryptographic_trust/cryptographic_trust_query.dart';
import '../models/cryptographic_trust/cryptographic_trust_snapshot.dart';
import '../models/cryptographic_trust/cryptographic_verification_models.dart';
import '../models/cryptographic_trust/policies/artifact_signature_trust_policy_v1.dart';

/// Platform implementation of [CryptographicTrustProvider].
///
/// Vendor-neutral orchestration — no algorithm switch in this class.
/// Verified status does not authorize release.
class PlatformCryptographicTrustProvider implements CryptographicTrustProvider {
  PlatformCryptographicTrustProvider({
    required CryptographicTrustPolicyRegistry policyRegistry,
    required CryptographicAlgorithmRegistry algorithmRegistry,
    required CryptographicPublicKeyResolver publicKeyResolver,
    required CryptographicTrustSourceResolver sourceResolver,
    required CryptographicTrustStore store,
    CryptographicSigningKeyProvider? signingKeyProvider,
    CryptographicTrustCollector? collector,
    CryptographicDigestService? digestService,
    CryptographicSigningService? signingService,
    CryptographicSignatureVerificationService? signatureVerificationService,
    CryptographicAttestationVerificationService? attestationVerificationService,
    CryptographicRevocationEvaluator? revocationEvaluator,
    CryptographicTransparencyEvaluator? transparencyEvaluator,
    CryptographicTrustChainBuilder? trustChainBuilder,
    CryptographicTrustEngine? engine,
    CryptographicTrustPolicyEvaluationService? policyEvaluationService,
    CryptographicTrustSnapshotBuilder? snapshotBuilder,
    CryptographicTrustSnapshotValidator? snapshotValidator,
  })  : _policyRegistry = policyRegistry,
        _sourceResolver = sourceResolver,
        _store = store,
        _collector = collector ?? const CryptographicTrustCollector(),
        _digestService = digestService ??
            CryptographicDigestService(algorithmRegistry: algorithmRegistry),
        _signingService = signingService ??
            CryptographicSigningService(
              algorithmRegistry: algorithmRegistry,
              signingKeyProvider: signingKeyProvider,
            ),
        _signatureVerificationService = signatureVerificationService ??
            CryptographicSignatureVerificationService(
              algorithmRegistry: algorithmRegistry,
              publicKeyResolver: publicKeyResolver,
              revocationEvaluator: revocationEvaluator,
            ),
        _attestationVerificationService = attestationVerificationService ??
            CryptographicAttestationVerificationService(
              signatureVerificationService: signatureVerificationService ??
                  CryptographicSignatureVerificationService(
                    algorithmRegistry: algorithmRegistry,
                    publicKeyResolver: publicKeyResolver,
                    revocationEvaluator: revocationEvaluator,
                  ),
            ),
        _revocationEvaluator =
            revocationEvaluator ?? const CryptographicRevocationEvaluator(),
        _transparencyEvaluator =
            transparencyEvaluator ?? CryptographicTransparencyEvaluator(),
        _trustChainBuilder =
            trustChainBuilder ?? const CryptographicTrustChainBuilder(),
        _engine = engine ?? const CryptographicTrustEngine(),
        _policyEvaluationService = policyEvaluationService ??
            CryptographicTrustPolicyEvaluationService(),
        _snapshotBuilder =
            snapshotBuilder ?? CryptographicTrustSnapshotBuilder(),
        _snapshotValidator =
            snapshotValidator ?? const CryptographicTrustSnapshotValidator();

  final CryptographicTrustPolicyRegistry _policyRegistry;
  final CryptographicTrustSourceResolver _sourceResolver;
  final CryptographicTrustStore _store;
  final CryptographicTrustCollector _collector;
  final CryptographicDigestService _digestService;
  final CryptographicSigningService _signingService;
  final CryptographicSignatureVerificationService _signatureVerificationService;
  final CryptographicAttestationVerificationService
      _attestationVerificationService;
  final CryptographicRevocationEvaluator _revocationEvaluator;
  final CryptographicTransparencyEvaluator _transparencyEvaluator;
  final CryptographicTrustChainBuilder _trustChainBuilder;
  final CryptographicTrustEngine _engine;
  final CryptographicTrustPolicyEvaluationService _policyEvaluationService;
  final CryptographicTrustSnapshotBuilder _snapshotBuilder;
  final CryptographicTrustSnapshotValidator _snapshotValidator;

  @override
  Future<CryptographicTrustEvaluationResult> evaluate(
    CryptographicTrustEvaluationRequest request,
  ) async {
    return _evaluatePipeline(request: request, persist: false);
  }

  @override
  Future<CryptographicTrustEvaluationResult> evaluateAndPublish(
    CryptographicTrustEvaluationRequest request,
  ) async {
    return _evaluatePipeline(request: request, persist: true);
  }

  @override
  Future<void> publish(CryptographicTrustSnapshot snapshot) async {
    await _store.save(snapshot);
  }

  @override
  Future<CryptographicTrustSnapshot?> load(String snapshotId) {
    return _store.load(snapshotId);
  }

  @override
  Future<CryptographicTrustSnapshot?> latest({
    required String projectId,
    String? releaseId,
    String? policyId,
  }) {
    return _store.latest(
      projectId: projectId,
      releaseId: releaseId,
      policyId: policyId,
    );
  }

  @override
  Future<List<CryptographicTrustSnapshot>> query(
    CryptographicTrustQuery query,
  ) {
    return _store.query(query);
  }

  @override
  Future<void> invalidate(String snapshotId) async {
    if (!await _store.exists(snapshotId)) {
      throw CryptographicTrustNotFoundException(snapshotId);
    }
    await _store.invalidate(snapshotId);
  }

  @override
  Future<CryptographicDigest?> computeDigest({
    required List<int> subjectBytes,
    required CryptographicDigest descriptor,
  }) async {
    final result = _digestService.computeDigest(
      subjectBytes: subjectBytes,
      declaredDigest: descriptor,
    );
    return result.computedDigest;
  }

  @override
  Future<CryptographicVerificationResult?> verifySignature({
    required CryptographicSignatureEnvelope envelope,
    required List<int> subjectBytes,
    required String projectId,
    String? releaseId,
  }) async {
    final serviceResult = await _signatureVerificationService.verifySignature(
      subjectBytes: subjectBytes,
      envelope: envelope,
    );
    return _buildAdhocVerificationResult(
      requestId: 'adhoc-${envelope.signatureId}',
      projectId: projectId,
      releaseId: releaseId,
      signatureResults: [
        CryptographicSignatureVerificationResult(
          signatureId: envelope.signatureId,
          status: _signatureVerificationService.mapOutcomeToVerificationStatus(
            serviceResult.outcome,
          ),
          trustLevel: serviceResult.trustLevel,
          issues: serviceResult.issues,
        ),
      ],
      issues: serviceResult.issues,
    );
  }

  @override
  Future<List<CryptographicAttestationVerificationResult>> verifyAttestation({
    required CryptographicAttestationStatement attestation,
    required List<CryptographicSignatureVerificationResult> signatureResults,
  }) async {
    final serviceResult =
        await _attestationVerificationService.verifyAttestation(
      attestation: attestation,
    );
    return [
      CryptographicAttestationVerificationResult(
        attestationId: attestation.attestationId,
        status: _mapAttestationOutcome(serviceResult.signatureOutcome),
        trustLevel: serviceResult.trustLevel,
        issues: serviceResult.issues,
      ),
    ];
  }

  @override
  Future<CryptographicSigningPrimitiveResult> sign({
    required CryptographicKeyReference keyReference,
    required List<int> digestBytes,
    required CryptographicSignatureEnvelope template,
  }) async {
    final result = await _signingService.signDigest(
      digestBytes: digestBytes,
      subjectDigest: template.subjectDigest,
      subject: template.subject,
      signatureDescriptor: template.signatureDescriptor,
      keyReference: keyReference,
      signatureId: template.signatureId,
    );
    return CryptographicSigningPrimitiveResult(
      outcome: result.outcome,
      envelope: result.envelope,
      message: result.message,
    );
  }

  Future<CryptographicTrustEvaluationResult> _evaluatePipeline({
    required CryptographicTrustEvaluationRequest request,
    required bool persist,
  }) async {
    final policy = _resolvePolicy(request);
    if (policy == null) {
      throw CryptographicTrustPolicyNotFoundException(
        request.policyReference?.policyId ??
            ArtifactSignatureTrustPolicyV1.policyId,
        policyVersion: request.policyReference?.policyVersion,
      );
    }

    final sources = await _sourceResolver.resolveAll(
      request,
      injectedTrustPolicy: policy,
    );

    final policyReference = _buildPolicyReference(request, policy);
    final context = CryptographicOperationContext(
      operation: persist
          ? CryptographicTrustOperation.evaluateAndPublish
          : CryptographicTrustOperation.evaluate,
      request: request,
      sources: sources,
      material: const CollectedCryptographicTrustMaterial(),
      policy: policy,
      policyReference: policyReference,
    );

    final collectionResult = _collector.collect(context);
    final material = collectionResult.material;
    final payloads = _extractPayloads(request);
    final issues = <CryptographicVerificationIssue>[];

    for (final digest in material.digests) {
      final payload = payloads[digest.subjectId];
      if (payload == null) {
        issues.add(
          CryptographicVerificationIssue(
            code: 'CT_DIGEST_PAYLOAD_UNAVAILABLE',
            severity: CryptographicIssueSeverity.warning,
            path: 'digests.${digest.subjectId}',
            message: 'Payload bytes unavailable for digest comparison',
            subjectId: digest.subjectId,
          ),
        );
        continue;
      }
      final comparison = _digestService.compareDigest(
        subjectBytes: payload,
        declaredDigest: digest,
      );
      issues.addAll(comparison.issues);
    }

    final signatureResults = <CryptographicSignatureVerificationResult>[];
    for (final envelope in material.signatures) {
      final payload = payloads[envelope.subject.subjectId] ?? const <int>[];
      final serviceResult = await _signatureVerificationService.verifySignature(
        subjectBytes: payload,
        envelope: envelope,
        revocations: material.revocations,
        referenceTime: request.requestedAt,
      );
      issues.addAll(serviceResult.issues);
      signatureResults.add(
        CryptographicSignatureVerificationResult(
          signatureId: envelope.signatureId,
          status: _signatureVerificationService.mapOutcomeToVerificationStatus(
            serviceResult.outcome,
          ),
          trustLevel: serviceResult.trustLevel,
          issues: serviceResult.issues,
        ),
      );
    }

    final attestationResults = <CryptographicAttestationVerificationResult>[];
    for (final attestation in material.attestations) {
      final serviceResult =
          await _attestationVerificationService.verifyAttestation(
        attestation: attestation,
        subjectBytesById: payloads,
        revocations: material.revocations,
        referenceTime: request.requestedAt,
      );
      issues.addAll(serviceResult.issues);
      attestationResults.add(
        CryptographicAttestationVerificationResult(
          attestationId: attestation.attestationId,
          status: _mapAttestationOutcome(serviceResult.signatureOutcome),
          trustLevel: serviceResult.trustLevel,
          issues: serviceResult.issues,
        ),
      );
    }

    for (final key in material.keyReferences) {
      final revocation = _revocationEvaluator.evaluateKey(
        keyId: key.keyId,
        revocations: material.revocations,
        referenceTime: request.requestedAt,
      );
      issues.addAll(revocation.issues);
    }

    for (final reference in material.transparencyLogReferences) {
      final evaluation = _transparencyEvaluator.evaluate(reference: reference);
      issues.addAll(evaluation.issues);
    }

    for (final conflict in collectionResult.conflicts) {
      issues.add(
        CryptographicVerificationIssue(
          code: conflict.code,
          severity: conflict.severity,
          path: 'collector.${conflict.messageId}',
          message: conflict.message,
        ),
      );
    }

    var verificationResult = CryptographicVerificationResult(
      verificationId: 'pending',
      requestId: request.verificationRequest.requestId,
      projectId: request.projectId,
      releaseId: request.releaseId,
      status: CryptographicVerificationStatus.pending,
      trustLevel: CryptographicTrustLevel.none,
      subjectResults: material.subjects
          .map(
            (subject) => CryptographicSubjectVerificationResult(
              subjectId: subject.subjectId,
              status: CryptographicVerificationStatus.pending,
              trustLevel: CryptographicTrustLevel.none,
            ),
          )
          .toList(),
      signatureResults: signatureResults,
      attestationResults: attestationResults,
      issues: issues,
      verifiedAt: request.requestedAt,
      metadata: const {'noReleaseAuthorization': 'true'},
    );

    final chainBuild = _trustChainBuilder.build(
      material: material,
      referenceTime: request.requestedAt,
    );

    final policyEvaluation = _policyEvaluationService.evaluate(
      policy: policy,
      material: material.copyWith(trustChains: chainBuild.chains),
      verificationResult: verificationResult,
      policyReference: policyReference,
    );

    verificationResult = verificationResult.copyWith(
      policyResults: [policyEvaluation.policyResult],
    );

    final engineResult = _engine.evaluate(
      CryptographicTrustEngineInput(
        material: material.copyWith(trustChains: chainBuild.chains),
        sources: sources,
        evaluationId: request.evaluationId,
        projectId: request.projectId,
        releaseId: request.releaseId,
        policy: policy,
        verificationResult: verificationResult,
        policyEvaluation: policyEvaluation,
        chainBuildResult: chainBuild,
        additionalIssues: issues,
        limitations: const ['verified-does-not-authorize-release'],
      ),
    );

    final buildResult = _snapshotBuilder.build(
      context: context.copyWith(material: material),
      material: material.copyWith(trustChains: engineResult.trustChains),
      engineResult: engineResult,
      evaluatedAt: request.requestedAt,
      publishedAt: persist ? request.requestedAt : null,
    );

    _snapshotValidator.validate(buildResult.snapshot);

    var snapshot = buildResult.snapshot;
    if (persist) {
      final existing = await _store.load(
        snapshot.metadata.cryptographicTrustSnapshotId,
      );
      if (existing == null) {
        await _store.save(snapshot);
        snapshot =
            await _store.load(snapshot.metadata.cryptographicTrustSnapshotId) ??
                snapshot;
      } else {
        snapshot = existing;
      }
    }

    return CryptographicTrustEvaluationResult(
      status: engineResult.evaluationStatus,
      evaluationId: request.evaluationId,
      projectId: request.projectId,
      releaseId: request.releaseId,
      verificationResult: engineResult.verificationResult,
      snapshot: snapshot,
      policyReference: policyReference,
      sourceResolutionSummary: sources.resolutionSummary,
      evaluatedAt: request.requestedAt,
      metadata: const {'noReleaseAuthorization': 'true'},
    );
  }

  CryptographicTrustPolicy? _resolvePolicy(
    CryptographicTrustEvaluationRequest request,
  ) {
    final ref = request.policyReference;
    if (ref != null) {
      return _policyRegistry.resolveById(ref.policyId, ref.policyVersion);
    }
    return _policyRegistry.resolve(
      policyId: ArtifactSignatureTrustPolicyV1.policyId,
      allowCandidate: true,
      useLatest: request.useLatest,
    );
  }

  CryptographicTrustPolicyReference _buildPolicyReference(
    CryptographicTrustEvaluationRequest request,
    CryptographicTrustPolicy policy,
  ) {
    return CryptographicTrustPolicyReference(
      policyId: policy.policyId,
      policyVersion: policy.version,
      status: policy.status,
      explicitSelection: request.policyReference != null ||
          policy.status == CryptographicPolicyStatus.candidate,
    );
  }

  Map<String, List<int>> _extractPayloads(
    CryptographicTrustEvaluationRequest request,
  ) {
    return {
      for (final subject in request.verificationRequest.subjects)
        if (subject.digest != null) subject.subjectId: const <int>[],
    };
  }

  CryptographicVerificationResult _buildAdhocVerificationResult({
    required String requestId,
    required String projectId,
    String? releaseId,
    required List<CryptographicSignatureVerificationResult> signatureResults,
    required List<CryptographicVerificationIssue> issues,
  }) {
    final status = signatureResults.every(
      (r) => r.status == CryptographicVerificationStatus.verified,
    )
        ? CryptographicVerificationStatus.verified
        : CryptographicVerificationStatus.unverified;
    return CryptographicVerificationResult(
      verificationId: 'adhoc:$requestId',
      requestId: requestId,
      projectId: projectId,
      releaseId: releaseId,
      status: status,
      trustLevel: CryptographicTrustLevel.none,
      signatureResults: signatureResults,
      issues: issues,
      metadata: const {'noReleaseAuthorization': 'true'},
    );
  }

  CryptographicVerificationStatus _mapAttestationOutcome(
    CryptographicPrimitiveOutcome outcome,
  ) {
    return _signatureVerificationService
        .mapOutcomeToVerificationStatus(outcome);
  }
}
