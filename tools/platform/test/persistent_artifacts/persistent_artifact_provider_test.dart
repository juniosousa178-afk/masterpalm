import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_operational_fixtures.dart';

class _NullReleaseEvidenceProvider implements ReleaseEvidenceProvider {
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

class _NullReleaseSupplyChainProvider implements ReleaseSupplyChainProvider {
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

class _NullCicdProvider implements CicdIntegrationProvider {
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

class _NullCryptographicTrustProvider implements CryptographicTrustProvider {
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

PlatformPersistentArtifactProvider _provider() {
  return PlatformPersistentArtifactProvider(
    policyRegistry: PersistentArtifactPolicyRegistry(registerDefaults: true),
    sourceResolver: PersistentArtifactSourceResolver(
      releaseEvidenceProvider: _NullReleaseEvidenceProvider(),
      releaseSupplyChainProvider: _NullReleaseSupplyChainProvider(),
      cicdIntegrationProvider: _NullCicdProvider(),
      cryptographicTrustProvider: _NullCryptographicTrustProvider(),
    ),
    store: InMemoryPersistentArtifactSnapshotStore(),
  );
}

void main() {
  group('PlatformPersistentArtifactProvider', () {
    test('evaluate nao persiste', () async {
      final provider = _provider();
      final result = await provider.evaluate(fixtureEvaluationRequest());
      expect(result.snapshot, isNotNull);
      final list = await provider.query(
        const PersistentArtifactQuery(projectId: 'proj-a'),
      );
      expect(list, isEmpty);
    });

    test('evaluateAndPublish persiste em store in-memory', () async {
      final provider = _provider();
      final result =
          await provider.evaluateAndPublish(fixtureEvaluationRequest());
      final loaded = await provider.load(result.snapshotReference!.snapshotId);
      expect(loaded, isNotNull);
    });

    test('latest retorna snapshot publicado', () async {
      final provider = _provider();
      await provider.evaluateAndPublish(fixtureEvaluationRequest());
      final latest =
          await provider.latest(projectId: 'proj-a', releaseId: 'rel-a');
      expect(latest, isNotNull);
    });

    test('writeContent sem backend retorna unavailable', () async {
      final provider = _provider();
      expect(
        () => provider.writeContent(contentId: 'c1', bytes: const [1]),
        throwsA(isA<PersistentArtifactContentUnavailableException>()),
      );
    });

    test('readContent sem backend retorna unavailable', () async {
      final provider = _provider();
      expect(
        () => provider.readContent(
          const InMemoryPersistentArtifactContentHandle(
            handleId: 'h',
            backendId: 'b',
          ),
        ),
        throwsA(isA<PersistentArtifactContentUnavailableException>()),
      );
    });

    test('deleteContent sem backend retorna unavailable', () async {
      final provider = _provider();
      expect(
        () => provider.deleteContent(
          const InMemoryPersistentArtifactContentHandle(
            handleId: 'h',
            backendId: 'b',
          ),
        ),
        throwsA(isA<PersistentArtifactContentUnavailableException>()),
      );
    });

    test('evaluateDeletion respeita legalHold', () async {
      final provider = _provider();
      final result = await provider.evaluateDeletion(
        fixtureEvaluationRequest(metadata: const {'legalHold': 'true'}),
        force: true,
      );
      expect(result.status, PersistentArtifactOperationStatus.blocked);
    });

    test('invalidate de id ausente lança excecao', () async {
      final provider = _provider();
      expect(
        () => provider.invalidate('nao-existe'),
        throwsA(isA<PersistentArtifactNotFoundException>()),
      );
    });
  });
}
