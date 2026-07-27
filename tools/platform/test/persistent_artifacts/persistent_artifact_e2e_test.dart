import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_operational_fixtures.dart';

class _E2EReleaseEvidenceProvider implements ReleaseEvidenceProvider {
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

class _E2ESupplyChainProvider implements ReleaseSupplyChainProvider {
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

class _E2ECicdProvider implements CicdIntegrationProvider {
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

class _E2ECryptographicTrustProvider implements CryptographicTrustProvider {
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

PersistentArtifactProvider _provider() {
  return PlatformPersistentArtifactProvider(
    policyRegistry: PersistentArtifactPolicyRegistry(registerDefaults: true),
    sourceResolver: PersistentArtifactSourceResolver(
      releaseEvidenceProvider: _E2EReleaseEvidenceProvider(),
      releaseSupplyChainProvider: _E2ESupplyChainProvider(),
      cicdIntegrationProvider: _E2ECicdProvider(),
      cryptographicTrustProvider: _E2ECryptographicTrustProvider(),
    ),
    store: InMemoryPersistentArtifactSnapshotStore(),
  );
}

void main() {
  group('PersistentArtifactE2E', () {
    for (var i = 0; i < 53; i++) {
      test('cenario operacional #$i', () async {
        final provider = _provider();
        final request = fixtureEvaluationRequest(evaluationId: 'e2e-$i');
        final evaluation = i.isEven
            ? await provider.evaluate(request)
            : await provider.evaluateAndPublish(request);

        expect(evaluation.evaluationId, 'e2e-$i');
        expect(evaluation.snapshot, isNotNull);
        expect(evaluation.operationResult, isNotNull);
        if (i.isOdd) {
          final loaded =
              await provider.load(evaluation.snapshotReference!.snapshotId);
          expect(loaded, isNotNull);
        }
      });
    }
  });
}
