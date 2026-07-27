import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_operational_fixtures.dart';

class _CountingReleaseEvidenceProvider implements ReleaseEvidenceProvider {
  int evaluateCalls = 0;
  int latestCalls = 0;

  @override
  Future<ReleaseEvidenceResult> evaluate(ReleaseEvidenceRequest request) async {
    evaluateCalls++;
    throw UnimplementedError();
  }

  @override
  Future<ReleaseEvidenceResult> evaluateAndPublish(
    ReleaseEvidenceRequest request,
  ) async {
    evaluateCalls++;
    throw UnimplementedError();
  }

  @override
  Future<void> invalidate(String bundleId) async {}

  @override
  Future<ReleaseEvidenceBundle?> latest({
    required String projectId,
    String? releaseId,
    String? policyId,
  }) async {
    latestCalls++;
    return null;
  }

  @override
  Future<ReleaseEvidenceBundle?> load(String bundleId) async => null;

  @override
  Future<void> publish(ReleaseEvidenceBundle bundle) async {}

  @override
  Future<List<ReleaseEvidenceBundle>> query(ReleaseEvidenceQuery query) async =>
      const [];
}

class _CountingSupplyChainProvider implements ReleaseSupplyChainProvider {
  int evaluateCalls = 0;
  int latestCalls = 0;

  @override
  Future<ReleaseSupplyChainResult> evaluate(
    ReleaseSupplyChainRequest request,
  ) async {
    evaluateCalls++;
    throw UnimplementedError();
  }

  @override
  Future<ReleaseSupplyChainResult> evaluateAndPublish(
    ReleaseSupplyChainRequest request,
  ) async {
    evaluateCalls++;
    throw UnimplementedError();
  }

  @override
  Future<void> invalidate(String snapshotId) async {}

  @override
  Future<ReleaseSupplyChainSnapshot?> latest({
    required String projectId,
    String? releaseId,
    String? supplyChainPolicyId,
  }) async {
    latestCalls++;
    return null;
  }

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

class _CountingCicdProvider implements CicdIntegrationProvider {
  int evaluateCalls = 0;
  int latestCalls = 0;

  @override
  Future<CicdIntegrationResult> evaluate(CicdIntegrationRequest request) async {
    evaluateCalls++;
    throw UnimplementedError();
  }

  @override
  Future<CicdIntegrationResult> evaluateAndPublish(
    CicdIntegrationRequest request,
  ) async {
    evaluateCalls++;
    throw UnimplementedError();
  }

  @override
  Future<void> invalidate(String snapshotId) async {}

  @override
  Future<CicdIntegrationSnapshot?> latest({
    required String projectId,
    String? releaseId,
    String? pipelineIntegrationPolicyId,
  }) async {
    latestCalls++;
    return null;
  }

  @override
  Future<CicdIntegrationSnapshot?> load(String snapshotId) async => null;

  @override
  Future<void> publish(CicdIntegrationSnapshot snapshot) async {}

  @override
  Future<List<CicdIntegrationSnapshot>> query(
          CicdIntegrationQuery query) async =>
      const [];
}

class _CountingCryptographicTrustProvider
    implements CryptographicTrustProvider {
  int evaluateCalls = 0;
  int latestCalls = 0;

  @override
  Future<CryptographicDigest?> computeDigest({
    required List<int> subjectBytes,
    required CryptographicDigest descriptor,
  }) async =>
      null;

  @override
  Future<CryptographicTrustEvaluationResult> evaluate(
    CryptographicTrustEvaluationRequest request,
  ) async {
    evaluateCalls++;
    throw UnimplementedError();
  }

  @override
  Future<CryptographicTrustEvaluationResult> evaluateAndPublish(
    CryptographicTrustEvaluationRequest request,
  ) async {
    evaluateCalls++;
    throw UnimplementedError();
  }

  @override
  Future<void> invalidate(String snapshotId) async {}

  @override
  Future<CryptographicTrustSnapshot?> latest({
    required String projectId,
    String? releaseId,
    String? policyId,
  }) async {
    latestCalls++;
    return null;
  }

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
  group('PersistentArtifactSourceResolver', () {
    test('usa somente latest/load e nunca evaluate', () async {
      final re = _CountingReleaseEvidenceProvider();
      final sc = _CountingSupplyChainProvider();
      final ci = _CountingCicdProvider();
      final ct = _CountingCryptographicTrustProvider();

      final resolver = PersistentArtifactSourceResolver(
        releaseEvidenceProvider: re,
        releaseSupplyChainProvider: sc,
        cicdIntegrationProvider: ci,
        cryptographicTrustProvider: ct,
      );

      final result = await resolver.resolveAll(fixtureEvaluationRequest());
      expect(
          result.status, PersistentArtifactSourceResolutionStatus.unavailable);
      expect(re.evaluateCalls, 0);
      expect(sc.evaluateCalls, 0);
      expect(ci.evaluateCalls, 0);
      expect(ct.evaluateCalls, 0);
      expect(re.latestCalls, 1);
      expect(sc.latestCalls, 1);
      expect(ci.latestCalls, 1);
      expect(ct.latestCalls, 1);
    });

    for (var i = 0; i < 7; i++) {
      test('resolve cenario basico $i', () async {
        final resolver = PersistentArtifactSourceResolver(
          releaseEvidenceProvider: _CountingReleaseEvidenceProvider(),
          releaseSupplyChainProvider: _CountingSupplyChainProvider(),
          cicdIntegrationProvider: _CountingCicdProvider(),
          cryptographicTrustProvider: _CountingCryptographicTrustProvider(),
        );
        final result = await resolver.resolveAll(
          fixtureEvaluationRequest(evaluationId: 'eval-$i'),
        );
        expect(result.fingerprint, isNotNull);
      });
    }
  });
}
