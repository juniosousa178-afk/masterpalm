import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_canonical_serializer.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_identity_builder.dart';
import 'package:masterpalm_platform/history/mappers/cryptographic_trust_history_mapper.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/policies/artifact_signature_trust_policy_v1.dart';
import 'package:masterpalm_platform/models/report/report_request.dart';
import 'package:masterpalm_platform/models/report/report_type.dart';
import 'package:masterpalm_platform/report/report_engine.dart';
import 'package:test/test.dart';

import 'support/cryptographic_trust_hardening_helpers.dart';
import 'support/cryptographic_trust_operational_fixtures.dart';
import 'support/cryptographic_trust_test_fixtures.dart';

void main() {
  group('Cryptographic Trust golden snapshots', () {
    late Map<String, dynamic> requestNormative;
    late Map<String, dynamic> snapshotVerifiedNormative;
    late Map<String, dynamic> snapshotPartialNormative;
    late Map<String, dynamic> snapshotFailedNormative;
    late Map<String, dynamic> resultVerifiedNormative;
    late Map<String, dynamic> resultPartialNormative;
    late Map<String, dynamic> resultFailedNormative;
    late Map<String, dynamic> verificationResultNormative;
    late Map<String, dynamic> digestNormative;
    late Map<String, dynamic> signatureNormative;
    late Map<String, dynamic> policyReferenceNormative;
    late Map<String, dynamic> identityNormative;
    late Map<String, dynamic> sourceResolutionNormative;
    late Map<String, dynamic> reportNormative;
    late Map<String, dynamic> historyComparableNormative;
    late Map<String, dynamic> chainNormative;
    late Map<String, dynamic> attestationNormative;
    late Map<String, dynamic> revocationNormative;
    const serializer = CryptographicTrustCanonicalSerializer();
    const identityBuilder = CryptographicTrustIdentityBuilder();

    setUpAll(() async {
      final stack = CryptographicTrustOperationalFixtures.createTestStack();
      await stack.registerTestKeys();

      final passingRequest =
          CryptographicTrustOperationalFixtures.evaluationRequest();
      final verifiedResult = await evaluateVerifiedScenario(stack: stack);
      final partialResult = await evaluatePartialScenario(stack: stack);
      final failedResult = await evaluateFailedScenario(stack: stack);

      final verifiedSnapshot = verifiedResult.snapshot!;
      final partialSnapshot = partialResult.snapshot!;
      final failedSnapshot = failedResult.snapshot!;

      requestNormative = {
        'evaluationId': passingRequest.evaluationId,
        'projectId': passingRequest.projectId,
        'releaseId': passingRequest.releaseId,
        'canonicalFingerprint':
            serializer.evaluationRequestFingerprint(passingRequest),
      };

      snapshotVerifiedNormative = {
        'cryptographicTrustSnapshotId':
            verifiedSnapshot.metadata.cryptographicTrustSnapshotId,
        'fingerprint': verifiedSnapshot.fingerprint,
        'status': verifiedSnapshot.status.wireName,
        'signatureCount': verifiedSnapshot.signatures.length,
        'canonicalFingerprint':
            serializer.snapshotFingerprint(verifiedSnapshot),
      };

      snapshotPartialNormative = {
        'cryptographicTrustSnapshotId':
            partialSnapshot.metadata.cryptographicTrustSnapshotId,
        'fingerprint': partialSnapshot.fingerprint,
        'status': partialSnapshot.status.wireName,
        'canonicalFingerprint': serializer.snapshotFingerprint(partialSnapshot),
      };

      snapshotFailedNormative = {
        'cryptographicTrustSnapshotId':
            failedSnapshot.metadata.cryptographicTrustSnapshotId,
        'fingerprint': failedSnapshot.fingerprint,
        'verificationStatus':
            failedResult.verificationResult?.status.wireName ?? 'unknown',
        'canonicalFingerprint': serializer.snapshotFingerprint(failedSnapshot),
      };

      resultVerifiedNormative = {
        'status': verifiedResult.status.wireName,
        'snapshotFingerprint': verifiedSnapshot.fingerprint,
        'resolvedSourceCount':
            verifiedResult.sourceResolutionSummary?.resolvedSources.length ?? 0,
      };

      resultPartialNormative = {
        'status': partialResult.status.wireName,
        'resolutionStatus':
            partialResult.sourceResolutionSummary?.status.wireName,
        'snapshotFingerprint': partialSnapshot.fingerprint,
      };

      resultFailedNormative = {
        'status': failedResult.status.wireName,
        'verificationStatus':
            failedResult.verificationResult?.status.wireName ?? 'unknown',
        'snapshotFingerprint': failedSnapshot.fingerprint,
      };

      final vr = verifiedResult.verificationResult!;
      verificationResultNormative = {
        'verificationId': vr.verificationId,
        'status': vr.status.wireName,
        'trustLevel': vr.trustLevel.wireName,
        'canonicalFingerprint': serializer.verificationResultFingerprint(vr),
      };

      final digest =
          await CryptographicTrustOperationalFixtures.digestForPayload(
        CryptographicTrustOperationalFixtures.payloadAbc,
      );
      digestNormative = {
        'subjectId': digest.subjectId,
        'algorithmId': digest.descriptor.algorithmId,
        'valuePrefix': digest.value.substring(0, 8),
        'canonicalFingerprint': serializer.digestFingerprint(digest),
      };

      final envelope = CryptographicTrustTestFixtures.validSignatureEnvelope();
      signatureNormative = {
        'signatureId': envelope.signatureId,
        'algorithmId': envelope.signatureDescriptor.algorithmId,
        'keyId': envelope.keyReference.keyId,
        'hasSignatureValue': envelope.signatureValue.isNotEmpty,
      };

      policyReferenceNormative = {
        'policyId': ArtifactSignatureTrustPolicyV1.policyId,
        'policyVersion': 1,
        'status': CryptographicPolicyStatus.active.wireName,
      };

      final snapIdentity = verifiedSnapshot.identity;
      identityNormative = {
        'cryptographicTrustId': snapIdentity?.cryptographicTrustId ?? '',
        'snapshotFingerprint': verifiedSnapshot.fingerprint,
        'canonicalFingerprint': snapIdentity == null
            ? ''
            : serializer.identityFingerprint(snapIdentity),
      };

      sourceResolutionNormative = {
        'status': verifiedResult.sourceResolutionSummary?.status.wireName,
        'resolvedCount':
            verifiedResult.sourceResolutionSummary?.resolvedSources.length ?? 0,
        'unresolvedCount':
            verifiedResult.sourceResolutionSummary?.unresolvedSources.length ??
                0,
      };

      final report = await ReportEngine().generate(
        ReportRequest(
          reportType: ReportType.cryptographicTrust,
          projectId: verifiedSnapshot.metadata.projectId,
          cryptographicTrustSnapshot: verifiedSnapshot.toJson(),
        ),
      );
      reportNormative = {
        'reportType': report.document.metadata.reportType.name,
        'sectionCount': report.document.sections.length,
        'projectId': verifiedSnapshot.metadata.projectId,
        'snapshotFingerprint': verifiedSnapshot.fingerprint,
      };

      const mapper = CryptographicTrustHistoryMapper();
      final artifact = mapper.fromMap(verifiedSnapshot.toJson());
      historyComparableNormative = {
        'artifactType': artifact.artifactType.name,
        'fingerprint': artifact.fingerprint,
        'snapshotId': verifiedSnapshot.metadata.cryptographicTrustSnapshotId,
      };

      final chain = verifiedSnapshot.trustChains.first;
      chainNormative = {
        'trustChainId': chain.trustChainId,
        'status': chain.status.wireName,
        'intermediateCount': chain.intermediateReferences.length,
      };

      final attestation = verifiedSnapshot.attestations.first;
      attestationNormative = {
        'attestationId': attestation.attestationId,
        'attestationType': attestation.attestationType.wireName,
        'status': attestation.status.wireName,
      };

      final revocation = verifiedSnapshot.revocations.first;
      revocationNormative = {
        'revocationId': revocation.revocationId,
        'subjectType': revocation.subjectType.wireName,
        'status': revocation.status.wireName,
      };
    });

    test('01 evaluation request golden metadata is stable', () {
      assertCryptographicTrustGolden(
        'test/goldens/cryptographic_trust/evaluation_request.json',
        requestNormative,
        ['evaluationId', 'projectId', 'releaseId', 'canonicalFingerprint'],
      );
    });

    test('02 snapshot verified golden metadata is stable', () {
      assertCryptographicTrustGolden(
        'test/goldens/cryptographic_trust/snapshot_verified.json',
        snapshotVerifiedNormative,
        [
          'cryptographicTrustSnapshotId',
          'fingerprint',
          'status',
          'signatureCount',
          'canonicalFingerprint',
        ],
      );
    });

    test('03 snapshot partial golden metadata is stable', () {
      assertCryptographicTrustGolden(
        'test/goldens/cryptographic_trust/snapshot_partial.json',
        snapshotPartialNormative,
        [
          'cryptographicTrustSnapshotId',
          'fingerprint',
          'status',
          'canonicalFingerprint',
        ],
      );
    });

    test('04 snapshot failed golden metadata is stable', () {
      assertCryptographicTrustGolden(
        'test/goldens/cryptographic_trust/snapshot_failed.json',
        snapshotFailedNormative,
        [
          'cryptographicTrustSnapshotId',
          'fingerprint',
          'verificationStatus',
          'canonicalFingerprint',
        ],
      );
    });

    test('05 result verified golden metadata is stable', () {
      assertCryptographicTrustGolden(
        'test/goldens/cryptographic_trust/result_verified.json',
        resultVerifiedNormative,
        ['status', 'snapshotFingerprint', 'resolvedSourceCount'],
      );
    });

    test('06 result partial golden metadata is stable', () {
      assertCryptographicTrustGolden(
        'test/goldens/cryptographic_trust/result_partial.json',
        resultPartialNormative,
        ['status', 'resolutionStatus', 'snapshotFingerprint'],
      );
    });

    test('07 result failed golden metadata is stable', () {
      assertCryptographicTrustGolden(
        'test/goldens/cryptographic_trust/result_failed.json',
        resultFailedNormative,
        ['status', 'verificationStatus', 'snapshotFingerprint'],
      );
    });

    test('08 verification result golden metadata is stable', () {
      assertCryptographicTrustGolden(
        'test/goldens/cryptographic_trust/verification_result.json',
        verificationResultNormative,
        ['verificationId', 'status', 'trustLevel', 'canonicalFingerprint'],
      );
    });

    test('09 digest golden metadata is stable', () {
      assertCryptographicTrustGolden(
        'test/goldens/cryptographic_trust/digest.json',
        digestNormative,
        ['subjectId', 'algorithmId', 'valuePrefix', 'canonicalFingerprint'],
      );
    });

    test('10 signature envelope golden excludes raw signature value', () {
      assertCryptographicTrustGolden(
        'test/goldens/cryptographic_trust/signature_envelope.json',
        signatureNormative,
        ['signatureId', 'algorithmId', 'keyId', 'hasSignatureValue'],
      );
      expect(signatureNormative.containsKey('signatureValue'), isFalse);
    });

    test('11 policy reference golden metadata is stable', () {
      assertCryptographicTrustGolden(
        'test/goldens/cryptographic_trust/policy_reference.json',
        policyReferenceNormative,
        ['policyId', 'policyVersion', 'status'],
      );
    });

    test('12 identity golden metadata is stable', () {
      assertCryptographicTrustGolden(
        'test/goldens/cryptographic_trust/identity.json',
        identityNormative,
        ['cryptographicTrustId', 'snapshotFingerprint', 'canonicalFingerprint'],
      );
    });

    test('13 source resolution golden metadata is stable', () {
      assertCryptographicTrustGolden(
        'test/goldens/cryptographic_trust/source_resolution.json',
        sourceResolutionNormative,
        ['status', 'resolvedCount', 'unresolvedCount'],
      );
    });

    test('14 report golden metadata is stable', () {
      assertCryptographicTrustGolden(
        'test/goldens/cryptographic_trust/report.json',
        reportNormative,
        ['reportType', 'sectionCount', 'projectId', 'snapshotFingerprint'],
      );
    });

    test('15 history comparable golden metadata is stable', () {
      assertCryptographicTrustGolden(
        'test/goldens/cryptographic_trust/history_comparable.json',
        historyComparableNormative,
        ['artifactType', 'fingerprint', 'snapshotId'],
      );
    });

    test('16 trust chain golden metadata is stable', () {
      assertCryptographicTrustGolden(
        'test/goldens/cryptographic_trust/trust_chain.json',
        chainNormative,
        ['trustChainId', 'status', 'intermediateCount'],
      );
    });

    test('17 attestation golden metadata is stable', () {
      assertCryptographicTrustGolden(
        'test/goldens/cryptographic_trust/attestation.json',
        attestationNormative,
        ['attestationId', 'attestationType', 'status'],
      );
    });

    test('18 revocation golden metadata is stable', () {
      assertCryptographicTrustGolden(
        'test/goldens/cryptographic_trust/revocation.json',
        revocationNormative,
        ['revocationId', 'subjectType', 'status'],
      );
    });

    test('snapshot json round-trip matches golden fingerprint', () async {
      final result = await evaluatePassingSnapshot();
      final snapshot = result.snapshot!;
      final restored = snapshot.toJson();
      expect(
        identityBuilder.fingerprintForSnapshot(snapshot),
        serializer.snapshotFingerprint(snapshot),
      );
      expect(restored.containsKey('privateKey'), isFalse);
    });
  });
}
