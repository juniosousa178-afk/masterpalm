import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_operational_fixtures.dart';

void main() {
  group('PersistentArtifactSecurityOperational', () {
    test('legal hold bloqueia delecao com force', () async {
      final evaluator = const PersistentArtifactDeletionEvaluator();
      final result = evaluator.evaluate(
        request:
            fixtureEvaluationRequest(metadata: const {'legalHold': 'true'}),
        force: true,
      );
      expect(result.status, PersistentArtifactOperationStatus.blocked);
    });

    test('mensagem de bloqueio presente', () async {
      final evaluator = const PersistentArtifactDeletionEvaluator();
      final result = evaluator.evaluate(
        request:
            fixtureEvaluationRequest(metadata: const {'legalHold': 'true'}),
        force: false,
      );
      expect(result.issues.first.code, 'legal-hold-blocks-deletion');
    });

    test('conteudo sem backend nao permitido', () async {
      final provider = PlatformPersistentArtifactProvider(
        policyRegistry:
            PersistentArtifactPolicyRegistry(registerDefaults: true),
        sourceResolver: PersistentArtifactSourceResolver(
          releaseEvidenceProvider: _FakeReleaseEvidenceProvider(),
          releaseSupplyChainProvider: _FakeSupplyChainProvider(),
          cicdIntegrationProvider: _FakeCicdProvider(),
          cryptographicTrustProvider: _FakeCtProvider(),
        ),
        store: InMemoryPersistentArtifactSnapshotStore(),
      );
      expect(
        () => provider.writeContent(contentId: 'c', bytes: const [1]),
        throwsA(isA<PersistentArtifactContentUnavailableException>()),
      );
    });

    for (var i = 0; i < 3; i++) {
      test('cenario seguranca $i', () {
        final result = const PersistentArtifactDeletionEvaluator().evaluate(
          request: fixtureEvaluationRequest(
            metadata: {'legalHold': i == 0 ? 'true' : 'false'},
          ),
          force: i == 2,
        );
        expect(result.metadata['legalHold'], isNotNull);
      });
    }
  });
}

class _FakeReleaseEvidenceProvider extends _BaseNullReleaseEvidenceProvider {}

class _FakeSupplyChainProvider extends _BaseNullSupplyChainProvider {}

class _FakeCicdProvider extends _BaseNullCicdProvider {}

class _FakeCtProvider extends _BaseNullCryptographicTrustProvider {}

class _BaseNullReleaseEvidenceProvider implements ReleaseEvidenceProvider {
  @override
  Future<ReleaseEvidenceResult> evaluate(
          ReleaseEvidenceRequest request) async =>
      throw UnimplementedError();
  @override
  Future<ReleaseEvidenceResult> evaluateAndPublish(
          ReleaseEvidenceRequest request) async =>
      throw UnimplementedError();
  @override
  Future<void> invalidate(String bundleId) async {}
  @override
  Future<ReleaseEvidenceBundle?> latest(
          {required String projectId,
          String? releaseId,
          String? policyId}) async =>
      null;
  @override
  Future<ReleaseEvidenceBundle?> load(String bundleId) async => null;
  @override
  Future<void> publish(ReleaseEvidenceBundle bundle) async {}
  @override
  Future<List<ReleaseEvidenceBundle>> query(ReleaseEvidenceQuery query) async =>
      const [];
}

class _BaseNullSupplyChainProvider implements ReleaseSupplyChainProvider {
  @override
  Future<ReleaseSupplyChainResult> evaluate(
          ReleaseSupplyChainRequest request) async =>
      throw UnimplementedError();
  @override
  Future<ReleaseSupplyChainResult> evaluateAndPublish(
          ReleaseSupplyChainRequest request) async =>
      throw UnimplementedError();
  @override
  Future<void> invalidate(String snapshotId) async {}
  @override
  Future<ReleaseSupplyChainSnapshot?> latest(
          {required String projectId,
          String? releaseId,
          String? supplyChainPolicyId}) async =>
      null;
  @override
  Future<ReleaseSupplyChainSnapshot?> load(String snapshotId) async => null;
  @override
  Future<void> publish(ReleaseSupplyChainSnapshot snapshot) async {}
  @override
  Future<List<ReleaseSupplyChainSnapshot>> query(
          ReleaseSupplyChainQuery query) async =>
      const [];
}

class _BaseNullCicdProvider implements CicdIntegrationProvider {
  @override
  Future<CicdIntegrationResult> evaluate(
          CicdIntegrationRequest request) async =>
      throw UnimplementedError();
  @override
  Future<CicdIntegrationResult> evaluateAndPublish(
          CicdIntegrationRequest request) async =>
      throw UnimplementedError();
  @override
  Future<void> invalidate(String snapshotId) async {}
  @override
  Future<CicdIntegrationSnapshot?> latest(
          {required String projectId,
          String? releaseId,
          String? pipelineIntegrationPolicyId}) async =>
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

class _BaseNullCryptographicTrustProvider
    implements CryptographicTrustProvider {
  @override
  Future<CryptographicDigest?> computeDigest(
          {required List<int> subjectBytes,
          required CryptographicDigest descriptor}) async =>
      null;
  @override
  Future<CryptographicTrustEvaluationResult> evaluate(
          CryptographicTrustEvaluationRequest request) async =>
      throw UnimplementedError();
  @override
  Future<CryptographicTrustEvaluationResult> evaluateAndPublish(
          CryptographicTrustEvaluationRequest request) async =>
      throw UnimplementedError();
  @override
  Future<void> invalidate(String snapshotId) async {}
  @override
  Future<CryptographicTrustSnapshot?> latest(
          {required String projectId,
          String? releaseId,
          String? policyId}) async =>
      null;
  @override
  Future<CryptographicTrustSnapshot?> load(String snapshotId) async => null;
  @override
  Future<void> publish(CryptographicTrustSnapshot snapshot) async {}
  @override
  Future<List<CryptographicTrustSnapshot>> query(
          CryptographicTrustQuery query) async =>
      const [];
  @override
  Future<CryptographicSigningPrimitiveResult> sign(
          {required CryptographicKeyReference keyReference,
          required List<int> digestBytes,
          required CryptographicSignatureEnvelope template}) async =>
      throw UnimplementedError();
  @override
  Future<List<CryptographicAttestationVerificationResult>> verifyAttestation(
          {required CryptographicAttestationStatement attestation,
          required List<CryptographicSignatureVerificationResult>
              signatureResults}) async =>
      const [];
  @override
  Future<CryptographicVerificationResult?> verifySignature(
          {required CryptographicSignatureEnvelope envelope,
          required List<int> subjectBytes,
          required String projectId,
          String? releaseId}) async =>
      null;
}
