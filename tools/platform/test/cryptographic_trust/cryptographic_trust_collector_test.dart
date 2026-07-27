import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_collector.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/collected_cryptographic_trust_material.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_operation_context.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_evaluation_result.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_verification_models.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/policies/artifact_signature_trust_policy_v1.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/resolved_cryptographic_trust_sources.dart';
import 'package:test/test.dart';

import 'support/cryptographic_trust_operational_fixtures.dart';
import 'support/cryptographic_trust_test_fixtures.dart';

void main() {
  group('CryptographicTrustCollector', () {
    const collector = CryptographicTrustCollector();

    CryptographicOperationContext buildContext({
      CryptographicVerificationRequest? verificationRequest,
    }) {
      final request = CryptographicTrustOperationalFixtures.evaluationRequest(
        verificationRequest: verificationRequest,
      );
      final vr = verificationRequest ??
          CryptographicTrustOperationalFixtures.verificationRequest();
      return CryptographicOperationContext(
        operation: CryptographicTrustOperation.collect,
        request: request,
        policy: ArtifactSignatureTrustPolicyV1.create(),
        sources: ResolvedCryptographicTrustSources(
          verificationRequest: ResolvedCryptographicTrustSource(
            sourceType: CryptographicSourceType.custom,
            resolutionMode: CryptographicTrustSourceResolutionMode.injected,
            state: CryptographicTrustSourceState.available,
            resolvedArtifact: vr,
          ),
          releaseEvidenceBundle: const ResolvedCryptographicTrustSource(
            sourceType: CryptographicSourceType.releaseEvidence,
            resolutionMode: CryptographicTrustSourceResolutionMode.notRequested,
            state: CryptographicTrustSourceState.notRequested,
          ),
          releaseSupplyChainSnapshot: const ResolvedCryptographicTrustSource(
            sourceType: CryptographicSourceType.releaseSupplyChain,
            resolutionMode: CryptographicTrustSourceResolutionMode.notRequested,
            state: CryptographicTrustSourceState.notRequested,
          ),
          cicdIntegrationSnapshot: const ResolvedCryptographicTrustSource(
            sourceType: CryptographicSourceType.cicdIntegration,
            resolutionMode: CryptographicTrustSourceResolutionMode.notRequested,
            state: CryptographicTrustSourceState.notRequested,
          ),
          trustPolicy: ResolvedCryptographicTrustSource(
            sourceType: CryptographicSourceType.custom,
            resolutionMode: CryptographicTrustSourceResolutionMode.injected,
            state: CryptographicTrustSourceState.available,
            resolvedArtifact: ArtifactSignatureTrustPolicyV1.create(),
          ),
          sourceReferences: const [],
          resolutionSummary: const CryptographicTrustSourceResolutionSummary(
            status: CryptographicTrustSourceResolutionStatus.complete,
            resolvedSources: [],
            unresolvedSources: [],
            injectedSources: [],
          ),
        ),
        material: const CollectedCryptographicTrustMaterial(),
      );
    }

    test('collects subjects signatures and keys from verification request', () {
      final vr = CryptographicTrustOperationalFixtures.verificationRequest();
      final result = collector.collect(buildContext(verificationRequest: vr));

      expect(result.material.subjects, isNotEmpty);
      expect(result.material.signatures, isNotEmpty);
      expect(result.material.keyReferences, isNotEmpty);
      expect(
          result.material.verificationRequests.single.requestId, vr.requestId);
    });

    test('deduplicates identical subject by normative identity', () {
      final subject = CryptographicTrustTestFixtures.validSubject();
      final sig1 = CryptographicTrustTestFixtures.validSignatureEnvelope();
      final sig2 = sig1.copyWith(signatureId: 'sig-dup-subject');
      final vr =
          CryptographicTrustTestFixtures.validVerificationRequest().copyWith(
        subjects: [subject, subject],
        signatures: [sig1, sig2],
      );

      final result = collector.collect(buildContext(verificationRequest: vr));
      expect(
          result.material.subjects
              .where((s) => s.subjectId == subject.subjectId),
          hasLength(1));
      expect(result.conflicts, isEmpty);
    });

    test('detects fingerprint conflict for same subject id', () {
      final subjectA = CryptographicTrustTestFixtures.validSubject();
      final subjectB = subjectA.copyWith(
        metadata: const {'channel': 'production'},
      );
      final vr =
          CryptographicTrustTestFixtures.validVerificationRequest().copyWith(
        subjects: [subjectA, subjectB],
        signatures: const [],
      );

      final result = collector.collect(buildContext(verificationRequest: vr));
      expect(result.conflicts, isNotEmpty);
      expect(
        result.conflicts.first.conflictType,
        CryptographicTrustConflictType.fingerprintMismatch,
      );
      expect(result.conflicts.first.code, 'fingerprint-mismatch');
    });

    test('detects fingerprint conflict for duplicate signature id', () {
      final sigA = CryptographicTrustTestFixtures.validSignatureEnvelope();
      final sigB = sigA.copyWith(signatureValue: 'different-signature');
      final vr =
          CryptographicTrustTestFixtures.validVerificationRequest().copyWith(
        signatures: [sigA, sigB],
      );

      final result = collector.collect(buildContext(verificationRequest: vr));
      expect(result.conflicts, hasLength(1));
      expect(result.conflicts.first.metadata['kind'], 'signature');
    });

    test('deduplicates identical signature envelope', () {
      final sig = CryptographicTrustTestFixtures.validSignatureEnvelope();
      final vr =
          CryptographicTrustTestFixtures.validVerificationRequest().copyWith(
        signatures: [sig, sig],
      );

      final result = collector.collect(buildContext(verificationRequest: vr));
      expect(result.material.signatures, hasLength(1));
    });

    test('collects policy from resolved trust policy source', () {
      final result = collector.collect(buildContext());
      expect(
        result.material.policies.any(
          (p) => p.policyId == ArtifactSignatureTrustPolicyV1.policyId,
        ),
        isTrue,
      );
    });

    test('sorts collected material deterministically', () {
      final sigB = CryptographicTrustTestFixtures.validSignatureEnvelope()
          .copyWith(signatureId: 'sig-b');
      final sigA = CryptographicTrustTestFixtures.validSignatureEnvelope()
          .copyWith(signatureId: 'sig-a');
      final vr = CryptographicTrustTestFixtures.validVerificationRequest()
          .copyWith(signatures: [sigB, sigA]);

      final result = collector.collect(buildContext(verificationRequest: vr));
      expect(result.material.signatures.first.signatureId, 'sig-a');
    });

    test('metadata includes evaluation and project identifiers', () {
      final result = collector.collect(buildContext());
      expect(result.material.metadata['evaluationId'], isNotEmpty);
      expect(result.material.metadata['projectId'], isNotEmpty);
    });
  });
}
