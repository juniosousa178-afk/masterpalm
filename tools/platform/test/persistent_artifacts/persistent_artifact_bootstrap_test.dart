import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

class _StubReleaseEvidenceProvider implements ReleaseEvidenceProvider {
  @override
  Future<ReleaseEvidenceResult> evaluate(
          ReleaseEvidenceRequest request) async =>
      throw UnimplementedError();
  @override
  Future<ReleaseEvidenceResult> evaluateAndPublish(
    ReleaseEvidenceRequest request,
  ) async =>
      throw UnimplementedError();
  @override
  Future<void> invalidate(String bundleId) async {}
  @override
  Future<ReleaseEvidenceBundle?> latest({
    required String projectId,
    String? releaseId,
    String? policyId,
  }) async =>
      null;
  @override
  Future<ReleaseEvidenceBundle?> load(String bundleId) async => null;
  @override
  Future<void> publish(ReleaseEvidenceBundle bundle) async {}
  @override
  Future<List<ReleaseEvidenceBundle>> query(ReleaseEvidenceQuery query) async =>
      const [];
}

class _StubReleaseSupplyChainProvider implements ReleaseSupplyChainProvider {
  @override
  Future<ReleaseSupplyChainResult> evaluate(
    ReleaseSupplyChainRequest request,
  ) async =>
      throw UnimplementedError();
  @override
  Future<ReleaseSupplyChainResult> evaluateAndPublish(
    ReleaseSupplyChainRequest request,
  ) async =>
      throw UnimplementedError();
  @override
  Future<void> invalidate(String snapshotId) async {}
  @override
  Future<ReleaseSupplyChainSnapshot?> latest({
    required String projectId,
    String? releaseId,
    String? supplyChainPolicyId,
  }) async =>
      null;
  @override
  Future<ReleaseSupplyChainSnapshot?> load(String snapshotId) async => null;
  @override
  Future<void> publish(ReleaseSupplyChainSnapshot snapshot) async {}
  @override
  Future<List<ReleaseSupplyChainSnapshot>> query(
    ReleaseSupplyChainQuery query,
  ) async =>
      const [];
}

class _StubCicdProvider implements CicdIntegrationProvider {
  @override
  Future<CicdIntegrationResult> evaluate(
          CicdIntegrationRequest request) async =>
      throw UnimplementedError();
  @override
  Future<CicdIntegrationResult> evaluateAndPublish(
    CicdIntegrationRequest request,
  ) async =>
      throw UnimplementedError();
  @override
  Future<void> invalidate(String snapshotId) async {}
  @override
  Future<CicdIntegrationSnapshot?> latest({
    required String projectId,
    String? releaseId,
    String? pipelineIntegrationPolicyId,
  }) async =>
      null;
  @override
  Future<CicdIntegrationSnapshot?> load(String snapshotId) async => null;
  @override
  Future<void> publish(CicdIntegrationSnapshot snapshot) async {}
  @override
  Future<List<CicdIntegrationSnapshot>> query(
          CicdIntegrationQuery query) async =>
      const [];
}

class _StubCryptographicTrustProvider implements CryptographicTrustProvider {
  @override
  Future<CryptographicDigest?> computeDigest({
    required List<int> subjectBytes,
    required CryptographicDigest descriptor,
  }) async =>
      null;
  @override
  Future<CryptographicTrustEvaluationResult> evaluate(
    CryptographicTrustEvaluationRequest request,
  ) async =>
      throw UnimplementedError();
  @override
  Future<CryptographicTrustEvaluationResult> evaluateAndPublish(
    CryptographicTrustEvaluationRequest request,
  ) async =>
      throw UnimplementedError();
  @override
  Future<void> invalidate(String snapshotId) async {}
  @override
  Future<CryptographicTrustSnapshot?> latest({
    required String projectId,
    String? releaseId,
    String? policyId,
  }) async =>
      null;
  @override
  Future<CryptographicTrustSnapshot?> load(String snapshotId) async => null;
  @override
  Future<void> publish(CryptographicTrustSnapshot snapshot) async {}
  @override
  Future<List<CryptographicTrustSnapshot>> query(
    CryptographicTrustQuery query,
  ) async =>
      const [];
  @override
  Future<CryptographicSigningPrimitiveResult> sign({
    required CryptographicKeyReference keyReference,
    required List<int> digestBytes,
    required CryptographicSignatureEnvelope template,
  }) async =>
      throw UnimplementedError();
  @override
  Future<List<CryptographicAttestationVerificationResult>> verifyAttestation({
    required CryptographicAttestationStatement attestation,
    required List<CryptographicSignatureVerificationResult> signatureResults,
  }) async =>
      const [];
  @override
  Future<CryptographicVerificationResult?> verifySignature({
    required CryptographicSignatureEnvelope envelope,
    required List<int> subjectBytes,
    required String projectId,
    String? releaseId,
  }) async =>
      null;
}

void main() {
  group('PersistentArtifactPlatformBootstrap', () {
    test('registra provider', () {
      final registry = ProviderRegistry()
        ..registerInstance<ReleaseEvidenceProvider>(
            _StubReleaseEvidenceProvider())
        ..registerInstance<ReleaseSupplyChainProvider>(
          _StubReleaseSupplyChainProvider(),
        )
        ..registerInstance<CicdIntegrationProvider>(_StubCicdProvider())
        ..registerInstance<CryptographicTrustProvider>(
          _StubCryptographicTrustProvider(),
        );
      PersistentArtifactPlatformBootstrap.register(registry: registry);
      expect(registry.isRegistered<PersistentArtifactProvider>(), isTrue);
    });

    test('idempotente em segunda chamada', () {
      final registry = ProviderRegistry()
        ..registerInstance<ReleaseEvidenceProvider>(
            _StubReleaseEvidenceProvider())
        ..registerInstance<ReleaseSupplyChainProvider>(
          _StubReleaseSupplyChainProvider(),
        )
        ..registerInstance<CicdIntegrationProvider>(_StubCicdProvider())
        ..registerInstance<CryptographicTrustProvider>(
          _StubCryptographicTrustProvider(),
        );
      PersistentArtifactPlatformBootstrap.register(registry: registry);
      PersistentArtifactPlatformBootstrap.register(registry: registry);
      expect(registry.isRegistered<PersistentArtifactProvider>(), isTrue);
    });

    test('falha sem dependencia release evidence', () {
      final registry = ProviderRegistry();
      expect(
        () => PersistentArtifactPlatformBootstrap.register(registry: registry),
        throwsA(isA<StateError>()),
      );
    });

    test('falha sem dependencia supply chain', () {
      final registry = ProviderRegistry()
        ..registerInstance<ReleaseEvidenceProvider>(
            _StubReleaseEvidenceProvider());
      expect(
        () => PersistentArtifactPlatformBootstrap.register(registry: registry),
        throwsA(isA<StateError>()),
      );
    });

    test('falha sem dependencia cicd', () {
      final registry = ProviderRegistry()
        ..registerInstance<ReleaseEvidenceProvider>(
            _StubReleaseEvidenceProvider())
        ..registerInstance<ReleaseSupplyChainProvider>(
          _StubReleaseSupplyChainProvider(),
        );
      expect(
        () => PersistentArtifactPlatformBootstrap.register(registry: registry),
        throwsA(isA<StateError>()),
      );
    });

    test('falha sem dependencia cryptographic trust', () {
      final registry = ProviderRegistry()
        ..registerInstance<ReleaseEvidenceProvider>(
            _StubReleaseEvidenceProvider())
        ..registerInstance<ReleaseSupplyChainProvider>(
          _StubReleaseSupplyChainProvider(),
        )
        ..registerInstance<CicdIntegrationProvider>(_StubCicdProvider());
      expect(
        () => PersistentArtifactPlatformBootstrap.register(registry: registry),
        throwsA(isA<StateError>()),
      );
    });
  });
}
