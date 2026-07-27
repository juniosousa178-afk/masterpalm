import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:masterpalm_platform/core/provider_registry.dart';
import 'package:masterpalm_platform/cryptographic_trust/adapters/ed25519_signer.dart';
import 'package:masterpalm_platform/cryptographic_trust/adapters/ed25519_signature_verifier.dart';
import 'package:masterpalm_platform/cryptographic_trust/adapters/in_memory_ed25519_signing_key_provider.dart';
import 'package:masterpalm_platform/cryptographic_trust/adapters/in_memory_public_key_resolver.dart';
import 'package:masterpalm_platform/cryptographic_trust/adapters/sha256_digest_provider.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_algorithm_registry.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_policy_registry.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_signing_service.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_source_resolver.dart';
import 'package:masterpalm_platform/cryptographic_trust/key_material/cryptographic_public_key_material.dart';
import 'package:masterpalm_platform/cryptographic_trust/stores/in_memory_cryptographic_trust_store.dart';
import 'package:masterpalm_platform/interfaces/cicd_integration_provider.dart';
import 'package:masterpalm_platform/interfaces/cryptographic_trust_provider.dart';
import 'package:masterpalm_platform/interfaces/release_evidence_provider.dart';
import 'package:masterpalm_platform/interfaces/release_supply_chain_provider.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_query.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_request.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_result.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_snapshot.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_key_reference.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_signature_envelope.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_algorithm_descriptors.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_digest.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_evaluation_request.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_policy.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_policy_reference.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_subject.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_verification_models.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/policies/artifact_signature_trust_policy_v1.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_bundle.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_query.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_request.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_result.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_query.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_request.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_result.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_snapshot.dart';
import 'package:masterpalm_platform/providers/platform_cryptographic_trust_provider.dart';

import 'cryptographic_trust_test_fixtures.dart';

/// Shared fixtures for Cryptographic Trust operational tests (Part 2).
class CryptographicTrustOperationalFixtures {
  static const projectId = CryptographicTrustTestFixtures.projectId;
  static const releaseId = CryptographicTrustTestFixtures.releaseId;
  static const referenceTime = CryptographicTrustTestFixtures.referenceTime;
  static const evaluationId = 'ct-eval-001';
  static const signingKeyId = 'key-signer-001';

  static const sha256Empty =
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
  static const sha256Abc =
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
  static const sha256Long =
      '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1';

  static final List<int> payloadAbc = utf8.encode('abc');
  static final List<int> payloadEmpty = const <int>[];

  static SimpleKeyPair? _cachedKeyPair;
  static String? _cachedPublicKeyFingerprint;
  static CryptographicPublicKeyMaterial? _cachedPublicKeyMaterial;

  static Future<void> ensureCryptoMaterial() async {
    if (_cachedKeyPair != null) return;
    final algorithm = Ed25519();
    _cachedKeyPair = await algorithm.newKeyPairFromSeed(
      List<int>.filled(32, 0x42),
    );
    _cachedPublicKeyMaterial = await publicKeyMaterialFromKeyPair(
      keyId: signingKeyId,
      keyPair: _cachedKeyPair!,
    );
    _cachedPublicKeyFingerprint =
        await publicKeyFingerprintFromKeyPair(_cachedKeyPair!);
  }

  static Future<SimpleKeyPair> testKeyPair() async {
    await ensureCryptoMaterial();
    return _cachedKeyPair!;
  }

  static Future<CryptographicPublicKeyMaterial> testPublicKeyMaterial() async {
    await ensureCryptoMaterial();
    return _cachedPublicKeyMaterial!;
  }

  static Future<String> testPublicKeyFingerprint() async {
    await ensureCryptoMaterial();
    return _cachedPublicKeyFingerprint!;
  }

  static CryptographicDigestDescriptor sha256Descriptor() =>
      CryptographicTrustTestFixtures.validDigestDescriptor();

  static Future<CryptographicDigest> digestForPayload(
    List<int> payload, {
    String subjectId = 'subject-art-001',
  }) async {
    await ensureCryptoMaterial();
    final provider = const Sha256DigestProvider();
    return provider.computeDigest(
      subjectBytes: payload,
      descriptor: sha256Descriptor(),
      subjectId: subjectId,
    );
  }

  static Future<CryptographicKeyReference> signingKeyReference() async {
    final fingerprint = await testPublicKeyFingerprint();
    return CryptographicTrustTestFixtures.validKeyReference(
      keyId: signingKeyId,
    ).copyWith(publicKeyFingerprint: fingerprint);
  }

  static Future<CryptographicTrustSubject> signedSubject(
    List<int> payload, {
    String subjectId = 'subject-art-001',
  }) async {
    final digest = await digestForPayload(payload, subjectId: subjectId);
    return CryptographicTrustTestFixtures.validSubject().copyWith(
      subjectId: subjectId,
      digest: digest,
      sourceFingerprint: digest.value,
    );
  }

  static Future<CryptographicSignatureEnvelope> signedEnvelope(
    List<int> payload, {
    String signatureId = 'sig-art-001',
    String subjectId = 'subject-art-001',
  }) async {
    await ensureCryptoMaterial();
    final subject = await signedSubject(payload, subjectId: subjectId);
    final digest = subject.digest!;
    final keyReference = await signingKeyReference();
    final registry = createAlgorithmRegistry(includeSigner: true);
    final signingKeyProvider = InMemoryEd25519SigningKeyProvider()
      ..registerKeyPair(signingKeyId, _cachedKeyPair!);
    final signingService = CryptographicSigningService(
      algorithmRegistry: registry,
      signingKeyProvider: signingKeyProvider,
    );
    final result = await signingService.signDigest(
      digestBytes: payload,
      subjectDigest: digest,
      subject: subject,
      signatureDescriptor:
          CryptographicTrustTestFixtures.validSignatureDescriptor(),
      keyReference: keyReference,
      signatureId: signatureId,
      signedAt: referenceTime,
      expiresAt: '2027-07-22T12:00:00.000Z',
    );
    if (result.outcome != CryptographicPrimitiveOutcome.valid ||
        result.envelope == null) {
      throw StateError('fixture signing failed: ${result.message}');
    }
    return result.envelope!.copyWith(
      signerIdentity: CryptographicTrustTestFixtures.validSignerIdentity(),
      trustAnchorReference:
          CryptographicTrustTestFixtures.validTrustAnchorReference(),
    );
  }

  static CryptographicVerificationRequest verificationRequest({
    List<CryptographicSignatureEnvelope>? signatures,
    CryptographicTrustPolicy? policy,
  }) {
    return CryptographicTrustTestFixtures.validVerificationRequest().copyWith(
      signatures: signatures ??
          [CryptographicTrustTestFixtures.validSignatureEnvelope()],
      policy: policy ?? ArtifactSignatureTrustPolicyV1.create(),
    );
  }

  static CryptographicTrustEvaluationRequest evaluationRequest({
    CryptographicVerificationRequest? verificationRequest,
    CryptographicTrustPolicyReference? policyReference,
    bool useLatest = false,
    ReleaseEvidenceBundle? releaseEvidenceBundle,
    ReleaseSupplyChainSnapshot? releaseSupplyChainSnapshot,
    CicdIntegrationSnapshot? cicdIntegrationSnapshot,
    Map<String, String> metadata = const {},
  }) {
    return CryptographicTrustEvaluationRequest(
      evaluationId: evaluationId,
      projectId: projectId,
      releaseId: releaseId,
      requestedAt: referenceTime,
      verificationRequest: verificationRequest ??
          CryptographicTrustOperationalFixtures.verificationRequest(),
      policyReference: policyReference,
      useLatest: useLatest,
      releaseEvidenceBundle: releaseEvidenceBundle,
      releaseSupplyChainSnapshot: releaseSupplyChainSnapshot,
      cicdIntegrationSnapshot: cicdIntegrationSnapshot,
      metadata: metadata,
    );
  }

  static CryptographicAlgorithmRegistry createAlgorithmRegistry({
    bool includeSigner = false,
    bool freeze = true,
  }) {
    final registry = CryptographicAlgorithmRegistry()
      ..register(
        CryptographicAlgorithmRegistration(
          algorithmId: Sha256DigestProvider.defaultAlgorithmId,
          operation: CryptographicPrimitiveOperation.computeDigest,
          capabilities: const {CryptographicProviderCapability.digest},
          digestProvider: const Sha256DigestProvider(),
        ),
      )
      ..register(
        CryptographicAlgorithmRegistration(
          algorithmId: Ed25519SignatureVerifier.defaultAlgorithmId,
          operation: CryptographicPrimitiveOperation.verifySignature,
          capabilities: const {
            CryptographicProviderCapability.signatureVerification,
          },
          keyType: CryptographicKeyType.ed25519,
          format: CryptographicSignatureFormat.raw,
          signatureVerifier: Ed25519SignatureVerifier(),
        ),
      );
    if (includeSigner) {
      registry.register(
        CryptographicAlgorithmRegistration(
          algorithmId: Ed25519Signer.defaultAlgorithmId,
          operation: CryptographicPrimitiveOperation.sign,
          capabilities: const {CryptographicProviderCapability.signing},
          keyType: CryptographicKeyType.ed25519,
          format: CryptographicSignatureFormat.raw,
          signer: Ed25519Signer(),
        ),
      );
    }
    if (freeze) {
      registry.freeze();
    }
    return registry;
  }

  static CryptographicTrustPolicyRegistry createPolicyRegistry({
    bool registerDefaults = true,
    bool freeze = false,
  }) {
    final registry = CryptographicTrustPolicyRegistry();
    if (registerDefaults) {
      registry.registerDefaultPolicies();
    }
    if (freeze) {
      registry.freeze();
    }
    return registry;
  }

  static CryptographicTrustTestStack createTestStack({
    InMemoryCryptographicTrustStore? store,
    FakeReleaseEvidenceProviderForCryptographicTrust? releaseEvidenceProvider,
    FakeReleaseSupplyChainProviderForCryptographicTrust?
        releaseSupplyChainProvider,
    FakeCicdIntegrationProviderForCryptographicTrust? cicdIntegrationProvider,
    bool includeSigner = false,
  }) {
    final resolvedStore = store ?? InMemoryCryptographicTrustStore();
    final reProvider = releaseEvidenceProvider ??
        FakeReleaseEvidenceProviderForCryptographicTrust();
    final rscProvider = releaseSupplyChainProvider ??
        FakeReleaseSupplyChainProviderForCryptographicTrust();
    final cicdProvider = cicdIntegrationProvider ??
        FakeCicdIntegrationProviderForCryptographicTrust();
    final policyRegistry = createPolicyRegistry(freeze: true);
    final algorithmRegistry =
        createAlgorithmRegistry(includeSigner: includeSigner);
    final publicKeyResolver = InMemoryPublicKeyResolver();
    final signingKeyProvider = InMemoryEd25519SigningKeyProvider();
    return CryptographicTrustTestStack(
      store: resolvedStore,
      releaseEvidenceProvider: reProvider,
      releaseSupplyChainProvider: rscProvider,
      cicdIntegrationProvider: cicdProvider,
      policyRegistry: policyRegistry,
      algorithmRegistry: algorithmRegistry,
      publicKeyResolver: publicKeyResolver,
      signingKeyProvider: signingKeyProvider,
      sourceResolver: CryptographicTrustSourceResolver(
        releaseEvidenceProvider: reProvider,
        releaseSupplyChainProvider: rscProvider,
        cicdIntegrationProvider: cicdProvider,
        trustPolicyRegistry: policyRegistry,
      ),
      provider: PlatformCryptographicTrustProvider(
        policyRegistry: policyRegistry,
        algorithmRegistry: algorithmRegistry,
        publicKeyResolver: publicKeyResolver,
        sourceResolver: CryptographicTrustSourceResolver(
          releaseEvidenceProvider: reProvider,
          releaseSupplyChainProvider: rscProvider,
          cicdIntegrationProvider: cicdProvider,
          trustPolicyRegistry: policyRegistry,
        ),
        store: resolvedStore,
        signingKeyProvider: includeSigner ? signingKeyProvider : null,
      ),
    );
  }

  static void registerInRegistry(
    ProviderRegistry registry, {
    InMemoryCryptographicTrustStore? store,
  }) {
    if (registry.isRegistered<CryptographicTrustProvider>()) return;
    final stack = createTestStack(store: store);
    registry.registerInstance<CryptographicTrustProvider>(stack.provider);
  }
}

class CryptographicTrustTestStack {
  const CryptographicTrustTestStack({
    required this.store,
    required this.releaseEvidenceProvider,
    required this.releaseSupplyChainProvider,
    required this.cicdIntegrationProvider,
    required this.policyRegistry,
    required this.algorithmRegistry,
    required this.publicKeyResolver,
    required this.signingKeyProvider,
    required this.sourceResolver,
    required this.provider,
  });

  final InMemoryCryptographicTrustStore store;
  final FakeReleaseEvidenceProviderForCryptographicTrust
      releaseEvidenceProvider;
  final FakeReleaseSupplyChainProviderForCryptographicTrust
      releaseSupplyChainProvider;
  final FakeCicdIntegrationProviderForCryptographicTrust
      cicdIntegrationProvider;
  final CryptographicTrustPolicyRegistry policyRegistry;
  final CryptographicAlgorithmRegistry algorithmRegistry;
  final InMemoryPublicKeyResolver publicKeyResolver;
  final InMemoryEd25519SigningKeyProvider signingKeyProvider;
  final CryptographicTrustSourceResolver sourceResolver;
  final PlatformCryptographicTrustProvider provider;

  Future<void> registerTestKeys() async {
    await CryptographicTrustOperationalFixtures.ensureCryptoMaterial();
    publicKeyResolver.register(
      await CryptographicTrustOperationalFixtures.testPublicKeyMaterial(),
    );
    signingKeyProvider.registerKeyPair(
      CryptographicTrustOperationalFixtures.signingKeyId,
      await CryptographicTrustOperationalFixtures.testKeyPair(),
    );
  }
}

class FakeReleaseEvidenceProviderForCryptographicTrust
    implements ReleaseEvidenceProvider {
  FakeReleaseEvidenceProviderForCryptographicTrust(
      {this.loaded, this.latestBundle});

  ReleaseEvidenceBundle? loaded;
  ReleaseEvidenceBundle? latestBundle;
  int loadCalls = 0;
  int latestCalls = 0;
  int evaluateCalls = 0;
  int evaluateAndPublishCalls = 0;
  int publishCalls = 0;

  @override
  Future<ReleaseEvidenceResult> evaluate(ReleaseEvidenceRequest request) async {
    evaluateCalls++;
    throw StateError('ReleaseEvidenceProvider.evaluate must not be called');
  }

  @override
  Future<ReleaseEvidenceResult> evaluateAndPublish(
    ReleaseEvidenceRequest request,
  ) async {
    evaluateAndPublishCalls++;
    throw StateError(
      'ReleaseEvidenceProvider.evaluateAndPublish must not be called',
    );
  }

  @override
  Future<void> publish(ReleaseEvidenceBundle bundle) async {
    publishCalls++;
    throw StateError('ReleaseEvidenceProvider.publish must not be called');
  }

  @override
  Future<ReleaseEvidenceBundle?> load(String bundleId) async {
    loadCalls++;
    return loaded;
  }

  @override
  Future<ReleaseEvidenceBundle?> latest({
    required String projectId,
    String? releaseId,
    String? policyId,
  }) async {
    latestCalls++;
    return latestBundle;
  }

  @override
  Future<List<ReleaseEvidenceBundle>> query(ReleaseEvidenceQuery query) async =>
      const [];

  @override
  Future<void> invalidate(String bundleId) async {}
}

class FakeReleaseSupplyChainProviderForCryptographicTrust
    implements ReleaseSupplyChainProvider {
  FakeReleaseSupplyChainProviderForCryptographicTrust({
    this.loaded,
    this.latestSnapshot,
  });

  ReleaseSupplyChainSnapshot? loaded;
  ReleaseSupplyChainSnapshot? latestSnapshot;
  int loadCalls = 0;
  int latestCalls = 0;
  int evaluateCalls = 0;
  int evaluateAndPublishCalls = 0;
  int publishCalls = 0;

  @override
  Future<ReleaseSupplyChainResult> evaluate(
    ReleaseSupplyChainRequest request,
  ) async {
    evaluateCalls++;
    throw StateError('ReleaseSupplyChainProvider.evaluate must not be called');
  }

  @override
  Future<ReleaseSupplyChainResult> evaluateAndPublish(
    ReleaseSupplyChainRequest request,
  ) async {
    evaluateAndPublishCalls++;
    throw StateError(
      'ReleaseSupplyChainProvider.evaluateAndPublish must not be called',
    );
  }

  @override
  Future<void> publish(ReleaseSupplyChainSnapshot snapshot) async {
    publishCalls++;
    throw StateError('ReleaseSupplyChainProvider.publish must not be called');
  }

  @override
  Future<ReleaseSupplyChainSnapshot?> load(String snapshotId) async {
    loadCalls++;
    return loaded;
  }

  @override
  Future<ReleaseSupplyChainSnapshot?> latest({
    required String projectId,
    String? releaseId,
    String? supplyChainPolicyId,
  }) async {
    latestCalls++;
    return latestSnapshot;
  }

  @override
  Future<List<ReleaseSupplyChainSnapshot>> query(
    ReleaseSupplyChainQuery query,
  ) async =>
      const [];

  @override
  Future<void> invalidate(String snapshotId) async {}
}

class FakeCicdIntegrationProviderForCryptographicTrust
    implements CicdIntegrationProvider {
  FakeCicdIntegrationProviderForCryptographicTrust(
      {this.loaded, this.latestSnapshot});

  CicdIntegrationSnapshot? loaded;
  CicdIntegrationSnapshot? latestSnapshot;
  int loadCalls = 0;
  int latestCalls = 0;
  int evaluateCalls = 0;
  int evaluateAndPublishCalls = 0;
  int publishCalls = 0;

  @override
  Future<CicdIntegrationResult> evaluate(CicdIntegrationRequest request) async {
    evaluateCalls++;
    throw StateError('CicdIntegrationProvider.evaluate must not be called');
  }

  @override
  Future<CicdIntegrationResult> evaluateAndPublish(
    CicdIntegrationRequest request,
  ) async {
    evaluateAndPublishCalls++;
    throw StateError(
      'CicdIntegrationProvider.evaluateAndPublish must not be called',
    );
  }

  @override
  Future<void> publish(CicdIntegrationSnapshot snapshot) async {
    publishCalls++;
    throw StateError('CicdIntegrationProvider.publish must not be called');
  }

  @override
  Future<CicdIntegrationSnapshot?> load(String snapshotId) async {
    loadCalls++;
    return loaded;
  }

  @override
  Future<CicdIntegrationSnapshot?> latest({
    required String projectId,
    String? releaseId,
    String? pipelineIntegrationPolicyId,
  }) async {
    latestCalls++;
    return latestSnapshot;
  }

  @override
  Future<List<CicdIntegrationSnapshot>> query(
    CicdIntegrationQuery query,
  ) async =>
      const [];

  @override
  Future<void> invalidate(String snapshotId) async {}
}
