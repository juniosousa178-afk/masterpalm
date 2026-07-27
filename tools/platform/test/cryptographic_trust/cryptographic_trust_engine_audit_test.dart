import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_engine.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/collected_cryptographic_trust_material.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_evaluation_result.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_validation_result.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_verification_models.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/policies/artifact_signature_trust_policy_v1.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/resolved_cryptographic_trust_sources.dart';
import 'package:test/test.dart';

import 'support/cryptographic_trust_hardening_helpers.dart';
import 'support/cryptographic_trust_operational_fixtures.dart';
import 'support/cryptographic_trust_test_fixtures.dart';

void main() {
  group('Cryptographic Trust engine audit', () {
    const engine = CryptographicTrustEngine();

    CryptographicTrustEngineInput buildInput({
      CryptographicVerificationResult? verificationResult,
      CryptographicTrustSourceResolutionSummary? summary,
    }) {
      final material = CollectedCryptographicTrustMaterial(
        subjects: [CryptographicTrustTestFixtures.validSubject()],
        signatures: [CryptographicTrustTestFixtures.validSignatureEnvelope()],
        keyReferences: [CryptographicTrustTestFixtures.validKeyReference()],
        policies: [ArtifactSignatureTrustPolicyV1.create()],
      );
      return CryptographicTrustEngineInput(
        material: material,
        sources: ResolvedCryptographicTrustSources(
          verificationRequest: ctNotRequested(CryptographicSourceType.custom),
          releaseEvidenceBundle:
              ctNotRequested(CryptographicSourceType.releaseEvidence),
          releaseSupplyChainSnapshot:
              ctNotRequested(CryptographicSourceType.releaseSupplyChain),
          cicdIntegrationSnapshot:
              ctNotRequested(CryptographicSourceType.cicdIntegration),
          trustPolicy: ctNotRequested(CryptographicSourceType.custom),
          sourceReferences: const [],
          resolutionSummary: summary ??
              const CryptographicTrustSourceResolutionSummary(
                status: CryptographicTrustSourceResolutionStatus.complete,
                resolvedSources: [],
                unresolvedSources: [],
                injectedSources: [],
              ),
        ),
        evaluationId: CryptographicTrustOperationalFixtures.evaluationId,
        projectId: CryptographicTrustOperationalFixtures.projectId,
        releaseId: CryptographicTrustOperationalFixtures.releaseId,
        policy: ArtifactSignatureTrustPolicyV1.create(),
        verificationResult: verificationResult ??
            CryptographicTrustTestFixtures.validVerificationResult(),
        structuralValidation:
            const CryptographicValidationResult(isValid: true),
      );
    }

    test('engine produces evaluation status for valid inputs', () {
      final result = engine.evaluate(buildInput());
      expect(result.evaluationStatus, isNotNull);
      expect(result.verificationResult, isNotNull);
    });

    test('verified status never implies release authorization', () {
      final result = engine.evaluate(buildInput());
      expect(result.limitations, contains('no-release-authorization'));
    });

    test('partial source summary yields partial evaluation status', () {
      final result = engine.evaluate(
        buildInput(
          summary: const CryptographicTrustSourceResolutionSummary(
            status: CryptographicTrustSourceResolutionStatus.partial,
            resolvedSources: [],
            unresolvedSources: ['releaseEvidence'],
            injectedSources: [],
          ),
        ),
      );
      expect(
        result.evaluationStatus,
        CryptographicTrustEvaluationStatus.partial,
      );
    });

    test('unsupported verification component yields partiallyVerified', () {
      final vr =
          CryptographicTrustTestFixtures.validVerificationResult().copyWith(
        status: CryptographicVerificationStatus.partiallyVerified,
      );
      final result = engine.evaluate(buildInput(verificationResult: vr));
      expect(
        result.verificationResult.status,
        CryptographicVerificationStatus.partiallyVerified,
      );
    });

    test('engine evaluates without mutating material fingerprints', () {
      final material = CollectedCryptographicTrustMaterial(
        subjects: [CryptographicTrustTestFixtures.validSubject()],
        signatures: [CryptographicTrustTestFixtures.validSignatureEnvelope()],
        keyReferences: [CryptographicTrustTestFixtures.validKeyReference()],
        policies: [ArtifactSignatureTrustPolicyV1.create()],
      );
      final subjectFp = material.subjects.first.sourceFingerprint;
      engine.evaluate(
        CryptographicTrustEngineInput(
          material: material,
          sources: buildInput().sources,
          evaluationId: CryptographicTrustOperationalFixtures.evaluationId,
          projectId: CryptographicTrustOperationalFixtures.projectId,
          verificationResult:
              CryptographicTrustTestFixtures.validVerificationResult(),
        ),
      );
      expect(material.subjects.first.sourceFingerprint, subjectFp);
    });

    test('invalid structural validation surfaces in engine output', () {
      final result = engine.evaluate(
        buildInput().copyWith(
          structuralValidation: const CryptographicValidationResult(
            isValid: false,
            errors: ['structural-error'],
          ),
        ),
      );
      expect(result.evaluationStatus, isNotNull);
    });
  });
}

extension on CryptographicTrustEngineInput {
  CryptographicTrustEngineInput copyWith({
    CryptographicValidationResult? structuralValidation,
  }) {
    return CryptographicTrustEngineInput(
      material: material,
      sources: sources,
      evaluationId: evaluationId,
      projectId: projectId,
      releaseId: releaseId,
      policy: policy,
      verificationResult: verificationResult,
      structuralValidation: structuralValidation ?? this.structuralValidation,
    );
  }
}
