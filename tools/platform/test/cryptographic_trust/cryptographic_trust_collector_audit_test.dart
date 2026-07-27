import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_collector.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/collected_cryptographic_trust_material.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_operation_context.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_evaluation_result.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/policies/artifact_signature_trust_policy_v1.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/resolved_cryptographic_trust_sources.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_verification_models.dart';
import 'package:test/test.dart';

import 'support/cryptographic_trust_operational_fixtures.dart';
import 'support/cryptographic_trust_test_fixtures.dart';

void main() {
  group('Cryptographic Trust collector audit', () {
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

    test('deduplicates subjects by normative identity', () {
      final subject = CryptographicTrustTestFixtures.validSubject();
      final vr =
          CryptographicTrustTestFixtures.validVerificationRequest().copyWith(
        subjects: [subject, subject],
      );
      final result = collector.collect(buildContext(verificationRequest: vr));
      expect(
        result.material.subjects.where((s) => s.subjectId == subject.subjectId),
        hasLength(1),
      );
    });

    test('detects fingerprint conflict for same subjectId', () {
      final subjectA = CryptographicTrustTestFixtures.validSubject();
      final subjectB = subjectA.copyWith(sourceFingerprint: 'different-fp');
      final vr =
          CryptographicTrustTestFixtures.validVerificationRequest().copyWith(
        subjects: [subjectA, subjectB],
      );
      final result = collector.collect(buildContext(verificationRequest: vr));
      expect(result.conflicts, isNotEmpty);
    });

    test('collects signatures and key references from verification request',
        () {
      final result = collector.collect(buildContext());
      expect(result.material.signatures, isNotEmpty);
      expect(result.material.keyReferences, isNotEmpty);
    });

    test('empty verification request yields empty material lists', () {
      final vr =
          CryptographicTrustTestFixtures.validVerificationRequest().copyWith(
        subjects: const [],
        signatures: const [],
        attestations: const [],
      );
      final result = collector.collect(buildContext(verificationRequest: vr));
      expect(result.material.subjects, isEmpty);
      expect(result.material.signatures, isEmpty);
    });

    test('collector does not mutate source artifact fingerprints', () {
      final subject = CryptographicTrustTestFixtures.validSubject();
      final originalFp = subject.sourceFingerprint;
      collector.collect(buildContext());
      expect(subject.sourceFingerprint, originalFp);
    });
  });
}
