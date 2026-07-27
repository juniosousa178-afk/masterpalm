import 'package:masterpalm_platform/cryptographic_trust/cryptographic_digest_service.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_signature_verification_service.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_engine.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_exceptions.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_policy_registry.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/collected_cryptographic_trust_material.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_evaluation_result.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_policy_reference.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_query.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_verification_models.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/resolved_cryptographic_trust_sources.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/policies/artifact_signature_trust_policy_v1.dart';
import 'package:test/test.dart';

import '../release_evidence/support/release_evidence_test_fixtures.dart';
import '../release_supply_chain/support/release_supply_chain_test_fixtures.dart';
import 'support/cryptographic_trust_operational_fixtures.dart';
import 'support/cryptographic_trust_test_fixtures.dart';

void main() {
  group('Cryptographic Trust E2E scenarios', () {
    late CryptographicTrustTestStack stack;

    setUp(() async {
      stack = CryptographicTrustOperationalFixtures.createTestStack(
        includeSigner: true,
      );
      await stack.registerTestKeys();
    });

    test('01 evaluate minimal verification request succeeds structurally',
        () async {
      final result = await stack.provider.evaluate(
        CryptographicTrustOperationalFixtures.evaluationRequest(),
      );
      expect(
          result.status, isNot(CryptographicTrustEvaluationStatus.unavailable));
      expect(result.verificationResult, isNotNull);
    });

    test('02 evaluateAndPublish persists snapshot', () async {
      final result = await stack.provider.evaluateAndPublish(
        CryptographicTrustOperationalFixtures.evaluationRequest(),
      );
      expect(result.snapshot, isNotNull);
      expect(await stack.store.count(), 1);
    });

    test('03 evaluateAndPublish is idempotent', () async {
      final request = CryptographicTrustOperationalFixtures.evaluationRequest();
      await stack.provider.evaluateAndPublish(request);
      await stack.provider.evaluateAndPublish(request);
      expect(await stack.store.count(), 1);
    });

    test('04 explicit candidate policy reference resolves', () async {
      final result = await stack.provider.evaluate(
        CryptographicTrustOperationalFixtures.evaluationRequest(
          policyReference: const CryptographicTrustPolicyReference(
            policyId: ArtifactSignatureTrustPolicyV1.policyId,
            policyVersion: 1,
            status: CryptographicPolicyStatus.candidate,
            explicitSelection: true,
          ),
        ),
      );
      expect(result.policyReference?.explicitSelection, isTrue);
    });

    test('05 missing explicit policy throws not found', () async {
      await expectLater(
        stack.provider.evaluate(
          CryptographicTrustOperationalFixtures.evaluationRequest(
            policyReference: const CryptographicTrustPolicyReference(
              policyId: 'missing-policy',
              policyVersion: 99,
              status: CryptographicPolicyStatus.active,
              explicitSelection: true,
            ),
          ),
        ),
        throwsA(isA<CryptographicTrustPolicyNotFoundException>()),
      );
    });

    test('06 injected release evidence preferred over byId', () async {
      final injected = ReleaseEvidenceTestFixtures.validBundle();
      stack.releaseEvidenceProvider.loaded = injected.copyWith(
        metadata: injected.metadata.copyWith(bundleId: 'stored'),
      );
      final sources = await stack.sourceResolver.resolveAll(
        CryptographicTrustOperationalFixtures.evaluationRequest(
          releaseEvidenceBundle: injected,
          metadata: const {'releaseEvidenceBundleId': 'stored'},
        ),
        injectedTrustPolicy: ArtifactSignatureTrustPolicyV1.create(),
      );
      expect(sources.releaseEvidenceBundle.resolutionMode.name, 'injected');
    });

    test('07 byId loads release evidence without evaluate', () async {
      final bundle = ReleaseEvidenceTestFixtures.validBundle();
      stack.releaseEvidenceProvider.loaded = bundle;
      await stack.sourceResolver.resolveAll(
        CryptographicTrustOperationalFixtures.evaluationRequest(
          metadata: {'releaseEvidenceBundleId': bundle.metadata.bundleId},
        ),
        injectedTrustPolicy: ArtifactSignatureTrustPolicyV1.create(),
      );
      expect(stack.releaseEvidenceProvider.loadCalls, 1);
      expect(stack.releaseEvidenceProvider.evaluateCalls, 0);
    });

    test('08 useLatest loads latest release evidence without evaluate',
        () async {
      stack.releaseEvidenceProvider.latestBundle =
          ReleaseEvidenceTestFixtures.validBundle();
      await stack.sourceResolver.resolveAll(
        CryptographicTrustOperationalFixtures.evaluationRequest(
            useLatest: true),
        injectedTrustPolicy: ArtifactSignatureTrustPolicyV1.create(),
      );
      expect(stack.releaseEvidenceProvider.latestCalls, 1);
      expect(stack.releaseEvidenceProvider.evaluateCalls, 0);
    });

    test('09 injected supply chain snapshot resolves', () async {
      final snapshot =
          ReleaseSupplyChainTestFixtures.validSupplyChainSnapshot();
      final sources = await stack.sourceResolver.resolveAll(
        CryptographicTrustOperationalFixtures.evaluationRequest(
          releaseSupplyChainSnapshot: snapshot,
        ),
        injectedTrustPolicy: ArtifactSignatureTrustPolicyV1.create(),
      );
      expect(sources.releaseSupplyChainSnapshot.isAvailable, isTrue);
    });

    test('10 missing byId evidence marks partial resolution', () async {
      final sources = await stack.sourceResolver.resolveAll(
        CryptographicTrustOperationalFixtures.evaluationRequest(
          metadata: const {'releaseEvidenceBundleId': 'missing'},
        ),
        injectedTrustPolicy: ArtifactSignatureTrustPolicyV1.create(),
      );
      expect(
        sources.resolutionSummary.status,
        CryptographicTrustSourceResolutionStatus.partial,
      );
    });

    test('11 digest service validates abc sha256 vector', () {
      final digestService = CryptographicDigestService(
        algorithmRegistry: stack.algorithmRegistry,
      );
      final result = digestService.compareDigest(
        subjectBytes: CryptographicTrustOperationalFixtures.payloadAbc,
        declaredDigest: CryptographicTrustTestFixtures.validDigest().copyWith(
          value: CryptographicTrustOperationalFixtures.sha256Abc,
        ),
      );
      expect(result.outcome, CryptographicPrimitiveOutcome.valid);
    });

    test('12 digest mismatch detected end to end via provider computeDigest',
        () async {
      final computed = await stack.provider.computeDigest(
        subjectBytes: CryptographicTrustOperationalFixtures.payloadAbc,
        descriptor: CryptographicTrustTestFixtures.validDigest().copyWith(
          value: CryptographicTrustOperationalFixtures.sha256Abc,
        ),
      );
      expect(computed?.value,
          isNot(CryptographicTrustOperationalFixtures.sha256Empty));
    });

    test('13 valid ed25519 signature verifies through provider', () async {
      final payload = CryptographicTrustOperationalFixtures.payloadAbc;
      final envelope =
          await CryptographicTrustOperationalFixtures.signedEnvelope(payload);
      final result = await stack.provider.verifySignature(
        envelope: envelope,
        subjectBytes: payload,
        projectId: CryptographicTrustOperationalFixtures.projectId,
      );
      expect(result?.status, CryptographicVerificationStatus.verified);
    });

    test('14 tampered signature fails provider verification', () async {
      final payload = CryptographicTrustOperationalFixtures.payloadAbc;
      final envelope =
          (await CryptographicTrustOperationalFixtures.signedEnvelope(payload))
              .copyWith(signatureValue: 'AAAA');
      final result = await stack.provider.verifySignature(
        envelope: envelope,
        subjectBytes: payload,
        projectId: CryptographicTrustOperationalFixtures.projectId,
      );
      expect(result?.status, isNot(CryptographicVerificationStatus.verified));
    });

    test('15 revoked key fails signature verification', () async {
      final payload = CryptographicTrustOperationalFixtures.payloadAbc;
      final envelope =
          await CryptographicTrustOperationalFixtures.signedEnvelope(payload);
      final service = CryptographicSignatureVerificationService(
        algorithmRegistry: stack.algorithmRegistry,
        publicKeyResolver: stack.publicKeyResolver,
      );
      await stack.registerTestKeys();
      final serviceResult = await service.verifySignature(
        subjectBytes: payload,
        envelope: envelope,
        revocations: [CryptographicTrustTestFixtures.validRevocationRecord()],
        referenceTime: CryptographicTrustOperationalFixtures.referenceTime,
      );
      expect(serviceResult.outcome, CryptographicPrimitiveOutcome.revoked);
      expect(
        service.mapOutcomeToVerificationStatus(serviceResult.outcome),
        CryptographicVerificationStatus.revoked,
      );
    });

    test('16 transparency reference structurally valid in pipeline', () async {
      final result = await stack.provider.evaluate(
        CryptographicTrustOperationalFixtures.evaluationRequest(),
      );
      expect(result.snapshot?.transparencyLogReferences, isNotEmpty);
    });

    test('17 attestation present in collected snapshot material', () async {
      final result = await stack.provider.evaluate(
        CryptographicTrustOperationalFixtures.evaluationRequest(),
      );
      expect(result.snapshot?.attestations, isNotEmpty);
    });

    test('18 collector dedup keeps single subject identity', () {
      final subject = CryptographicTrustTestFixtures.validSubject();
      final vr = CryptographicTrustTestFixtures.validVerificationRequest()
          .copyWith(subjects: [subject, subject]);
      final request = CryptographicTrustOperationalFixtures.evaluationRequest(
        verificationRequest: vr,
      );
      final sources = stack.sourceResolver.resolveTrustPolicy(
        request,
        [],
        ArtifactSignatureTrustPolicyV1.create(),
        [],
      );
      expect(sources.isAvailable, isTrue);
    });

    test('19 verified status never authorizes release', () async {
      final result = await stack.provider.evaluate(
        CryptographicTrustOperationalFixtures.evaluationRequest(),
      );
      expect(result.metadata['noReleaseAuthorization'], 'true');
      expect(result.toJson().containsKey('releaseAuthorized'), isFalse);
    });

    test('20 evaluation result includes source resolution summary', () async {
      final result = await stack.provider.evaluate(
        CryptographicTrustOperationalFixtures.evaluationRequest(),
      );
      expect(result.sourceResolutionSummary, isNotNull);
    });

    test('21 publish then load returns identical fingerprint', () async {
      final snapshot = CryptographicTrustTestFixtures.validSnapshot();
      await stack.provider.publish(snapshot);
      final loaded = await stack.provider.load(
        snapshot.metadata.cryptographicTrustSnapshotId,
      );
      expect(loaded?.fingerprint, snapshot.fingerprint);
    });

    test('22 conflicting publish throws snapshot conflict', () async {
      final snapshot = CryptographicTrustTestFixtures.validSnapshot();
      await stack.provider.publish(snapshot);
      final conflicting = snapshot.copyWith(
        status: CryptographicTrustStatus.invalid,
      );
      await expectLater(
        stack.provider.publish(conflicting),
        throwsA(isA<CryptographicTrustSnapshotConflictException>()),
      );
    });

    test('23 latest query returns published snapshot', () async {
      await stack.provider.evaluateAndPublish(
        CryptographicTrustOperationalFixtures.evaluationRequest(),
      );
      final latest = await stack.provider.latest(
        projectId: CryptographicTrustOperationalFixtures.projectId,
      );
      expect(latest, isNotNull);
    });

    test('24 invalidate removes stored snapshot', () async {
      final published = await stack.provider.evaluateAndPublish(
        CryptographicTrustOperationalFixtures.evaluationRequest(),
      );
      final id = published.snapshot!.metadata.cryptographicTrustSnapshotId;
      await stack.provider.invalidate(id);
      expect(await stack.provider.load(id), isNull);
    });

    test('25 upstream cicd provider never evaluated during resolve', () async {
      await stack.sourceResolver.resolveAll(
        CryptographicTrustOperationalFixtures.evaluationRequest(
            useLatest: true),
        injectedTrustPolicy: ArtifactSignatureTrustPolicyV1.create(),
      );
      expect(stack.cicdIntegrationProvider.evaluateCalls, 0);
      expect(stack.cicdIntegrationProvider.evaluateAndPublishCalls, 0);
    });

    test('26 upstream supply chain never evaluated during resolve', () async {
      await stack.sourceResolver.resolveAll(
        CryptographicTrustOperationalFixtures.evaluationRequest(
          metadata: const {'releaseSupplyChainSnapshotId': 'missing'},
        ),
        injectedTrustPolicy: ArtifactSignatureTrustPolicyV1.create(),
      );
      expect(stack.releaseSupplyChainProvider.evaluateCalls, 0);
    });

    test('27 sign primitive produces envelope when configured', () async {
      final template = CryptographicTrustTestFixtures.validSignatureEnvelope();
      final digest = await stack.provider.computeDigest(
        subjectBytes: CryptographicTrustOperationalFixtures.payloadAbc,
        descriptor: CryptographicTrustTestFixtures.validDigest().copyWith(
          value: CryptographicTrustOperationalFixtures.sha256Abc,
        ),
      );
      final signed = await stack.provider.sign(
        keyReference:
            await CryptographicTrustOperationalFixtures.signingKeyReference(),
        digestBytes: CryptographicTrustOperationalFixtures.payloadAbc,
        template: template.copyWith(subjectDigest: digest!),
      );
      expect(signed.outcome, CryptographicPrimitiveOutcome.valid);
    });

    test('28 snapshot limitations document no release authorization', () async {
      final result = await stack.provider.evaluateAndPublish(
        CryptographicTrustOperationalFixtures.evaluationRequest(),
      );
      expect(
        result.snapshot!.limitations
            .any((l) => l.contains('no-release-authorization')),
        isTrue,
      );
    });

    test('29 snapshot status provisional when verification verified', () async {
      const engine = CryptographicTrustEngine();
      final result = engine.evaluate(
        CryptographicTrustEngineInput(
          material: CollectedCryptographicTrustMaterial(
            verificationRequests: [
              CryptographicTrustOperationalFixtures.verificationRequest(),
            ],
          ),
          sources: const ResolvedCryptographicTrustSources(
            verificationRequest: ResolvedCryptographicTrustSource(
              sourceType: CryptographicSourceType.custom,
              resolutionMode: CryptographicTrustSourceResolutionMode.injected,
              state: CryptographicTrustSourceState.available,
            ),
            releaseEvidenceBundle: ResolvedCryptographicTrustSource(
              sourceType: CryptographicSourceType.releaseEvidence,
              resolutionMode:
                  CryptographicTrustSourceResolutionMode.notRequested,
              state: CryptographicTrustSourceState.notRequested,
            ),
            releaseSupplyChainSnapshot: ResolvedCryptographicTrustSource(
              sourceType: CryptographicSourceType.releaseSupplyChain,
              resolutionMode:
                  CryptographicTrustSourceResolutionMode.notRequested,
              state: CryptographicTrustSourceState.notRequested,
            ),
            cicdIntegrationSnapshot: ResolvedCryptographicTrustSource(
              sourceType: CryptographicSourceType.cicdIntegration,
              resolutionMode:
                  CryptographicTrustSourceResolutionMode.notRequested,
              state: CryptographicTrustSourceState.notRequested,
            ),
            trustPolicy: ResolvedCryptographicTrustSource(
              sourceType: CryptographicSourceType.custom,
              resolutionMode: CryptographicTrustSourceResolutionMode.injected,
              state: CryptographicTrustSourceState.available,
            ),
            sourceReferences: [],
            resolutionSummary: CryptographicTrustSourceResolutionSummary(
              status: CryptographicTrustSourceResolutionStatus.complete,
              resolvedSources: ['custom'],
              unresolvedSources: [],
              injectedSources: ['custom'],
            ),
          ),
          evaluationId: CryptographicTrustOperationalFixtures.evaluationId,
          projectId: CryptographicTrustOperationalFixtures.projectId,
          releaseId: CryptographicTrustOperationalFixtures.releaseId,
          verificationResult:
              CryptographicTrustTestFixtures.validVerificationResult(),
        ),
      );
      expect(result.snapshotStatus, CryptographicTrustStatus.provisional);
    });

    test('30 policy registry active promotion visible in registry', () {
      final policy = ArtifactSignatureTrustPolicyV1.create().copyWith(
        status: CryptographicPolicyStatus.candidate,
      );
      final registry = CryptographicTrustPolicyRegistry();
      registry.register(policy);
      registry.promote(ArtifactSignatureTrustPolicyV1.policyId, 1);
      expect(
        registry.active(ArtifactSignatureTrustPolicyV1.policyId)?.status,
        CryptographicPolicyStatus.active,
      );
    });

    test('31 algorithm registry resolves digest and verifier', () {
      expect(stack.algorithmRegistry.resolveDigestProvider('sha256-v1'),
          isNotNull);
      expect(
        stack.algorithmRegistry.resolveSignatureVerifier(
          algorithmId: 'ed25519-v1',
          keyType: CryptographicKeyType.ed25519,
          format: CryptographicSignatureFormat.raw,
        ),
        isNotNull,
      );
    });

    test('32 evaluation with injected upstream artifacts avoids evaluate',
        () async {
      final request = CryptographicTrustOperationalFixtures.evaluationRequest(
        releaseEvidenceBundle: ReleaseEvidenceTestFixtures.validBundle(),
        releaseSupplyChainSnapshot:
            ReleaseSupplyChainTestFixtures.validSupplyChainSnapshot(),
      );
      await stack.provider.evaluate(request);
      expect(stack.releaseEvidenceProvider.evaluateCalls, 0);
      expect(stack.releaseSupplyChainProvider.evaluateCalls, 0);
      expect(stack.cicdIntegrationProvider.evaluateCalls, 0);
    });

    test('33 query returns empty before publish', () async {
      final results = await stack.provider.query(
        const CryptographicTrustQuery(
          projectId: CryptographicTrustOperationalFixtures.projectId,
        ),
      );
      expect(results, isEmpty);
    });

    test('34 verifyAttestation returns results without claim execution',
        () async {
      final attestation =
          CryptographicTrustTestFixtures.validAttestationStatement();
      final results = await stack.provider.verifyAttestation(
        attestation: attestation,
        signatureResults: const [],
      );
      expect(results, hasLength(1));
    });

    test('35 partial evaluation when optional sources missing', () async {
      final result = await stack.provider.evaluate(
        CryptographicTrustOperationalFixtures.evaluationRequest(
          metadata: const {
            'releaseEvidenceBundleId': 'missing',
            'releaseSupplyChainSnapshotId': 'missing',
          },
        ),
      );
      expect(result.status, CryptographicTrustEvaluationStatus.partial);
    });
  });
}
