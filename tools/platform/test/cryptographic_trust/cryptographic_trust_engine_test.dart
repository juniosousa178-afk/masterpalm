import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_engine.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/collected_cryptographic_trust_material.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_evaluation_result.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_validation_result.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_verification_models.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/resolved_cryptographic_trust_sources.dart';
import 'package:test/test.dart';

import 'support/cryptographic_trust_operational_fixtures.dart';
import 'support/cryptographic_trust_test_fixtures.dart';

void main() {
  group('CryptographicTrustEngine', () {
    const engine = CryptographicTrustEngine();

    ResolvedCryptographicTrustSources completeSources() {
      return const ResolvedCryptographicTrustSources(
        verificationRequest: ResolvedCryptographicTrustSource(
          sourceType: CryptographicSourceType.custom,
          resolutionMode: CryptographicTrustSourceResolutionMode.injected,
          state: CryptographicTrustSourceState.available,
        ),
        releaseEvidenceBundle: ResolvedCryptographicTrustSource(
          sourceType: CryptographicSourceType.releaseEvidence,
          resolutionMode: CryptographicTrustSourceResolutionMode.notRequested,
          state: CryptographicTrustSourceState.notRequested,
        ),
        releaseSupplyChainSnapshot: ResolvedCryptographicTrustSource(
          sourceType: CryptographicSourceType.releaseSupplyChain,
          resolutionMode: CryptographicTrustSourceResolutionMode.notRequested,
          state: CryptographicTrustSourceState.notRequested,
        ),
        cicdIntegrationSnapshot: ResolvedCryptographicTrustSource(
          sourceType: CryptographicSourceType.cicdIntegration,
          resolutionMode: CryptographicTrustSourceResolutionMode.notRequested,
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
      );
    }

    CryptographicTrustEngineInput baseInput({
      CryptographicVerificationResult? verificationResult,
      List<CryptographicVerificationIssue> additionalIssues = const [],
      CryptographicValidationResult? structuralValidation,
      CryptographicTrustSourceResolutionSummary? sourceSummary,
    }) {
      return CryptographicTrustEngineInput(
        material: CollectedCryptographicTrustMaterial(
          verificationRequests: [
            CryptographicTrustOperationalFixtures.verificationRequest(),
          ],
        ),
        sources: ResolvedCryptographicTrustSources(
          verificationRequest: completeSources().verificationRequest,
          releaseEvidenceBundle: completeSources().releaseEvidenceBundle,
          releaseSupplyChainSnapshot:
              completeSources().releaseSupplyChainSnapshot,
          cicdIntegrationSnapshot: completeSources().cicdIntegrationSnapshot,
          trustPolicy: completeSources().trustPolicy,
          sourceReferences: const [],
          resolutionSummary:
              sourceSummary ?? completeSources().resolutionSummary,
        ),
        evaluationId: CryptographicTrustOperationalFixtures.evaluationId,
        projectId: CryptographicTrustOperationalFixtures.projectId,
        releaseId: CryptographicTrustOperationalFixtures.releaseId,
        verificationResult: verificationResult ??
            CryptographicTrustTestFixtures.validVerificationResult(),
        additionalIssues: additionalIssues,
        structuralValidation: structuralValidation,
      );
    }

    test('verified status includes no-release-authorization warning', () {
      final result = engine.evaluate(baseInput());
      expect(
        result.verificationResult.status,
        CryptographicVerificationStatus.verified,
      );
      expect(result.warnings, contains('verified-does-not-authorize-release'));
      expect(result.limitations, contains('no-release-authorization'));
      expect(
        result.verificationResult.metadata['noReleaseAuthorization'],
        'true',
      );
    });

    test('verified does not map to release authorization fields', () {
      final result = engine.evaluate(baseInput());
      expect(
          result.verificationResult.toJson().containsKey('releaseAuthorized'),
          isFalse);
      expect(result.evaluationStatus,
          isNot(CryptographicTrustEvaluationStatus.failure));
    });

    test('critical issue forces invalid verification status', () {
      final status = engine.deriveVerificationStatus(
        issues: const [
          CryptographicVerificationIssue(
            code: 'CT_FATAL',
            severity: CryptographicIssueSeverity.critical,
            path: 'test',
            message: 'critical',
          ),
        ],
        baseResult: CryptographicTrustTestFixtures.validVerificationResult(),
      );
      expect(status, CryptographicVerificationStatus.invalid);
    });

    test('conflict issue forces invalid verification status', () {
      final status = engine.deriveVerificationStatus(
        issues: const [
          CryptographicVerificationIssue(
            code: 'CT_SOURCE_CONFLICT',
            severity: CryptographicIssueSeverity.error,
            path: 'test',
            message: 'conflict',
          ),
        ],
        baseResult: CryptographicTrustTestFixtures.validVerificationResult(),
      );
      expect(status, CryptographicVerificationStatus.invalid);
    });

    test('unsupported component yields partiallyVerified never valid', () {
      final status = engine.deriveVerificationStatus(
        issues: const [
          CryptographicVerificationIssue(
            code: 'CT_SIG_UNSUPPORTED',
            severity: CryptographicIssueSeverity.error,
            path: 'test',
            message: 'unsupported',
          ),
        ],
        baseResult: CryptographicTrustTestFixtures.validVerificationResult(),
      );
      expect(status, CryptographicVerificationStatus.partiallyVerified);
      expect(status, isNot(CryptographicVerificationStatus.verified));
    });

    test('unavailable component yields partiallyVerified never invalid', () {
      final status = engine.deriveVerificationStatus(
        issues: const [
          CryptographicVerificationIssue(
            code: 'CT_SIG_UNAVAILABLE',
            severity: CryptographicIssueSeverity.warning,
            path: 'test',
            message: 'unavailable',
          ),
        ],
        baseResult: CryptographicTrustTestFixtures.validVerificationResult()
            .copyWith(status: CryptographicVerificationStatus.pending),
      );
      expect(status, CryptographicVerificationStatus.partiallyVerified);
      expect(status, isNot(CryptographicVerificationStatus.invalid));
    });

    test('structural validation failure yields evaluation failure', () {
      final result = engine.evaluate(
        baseInput(
          structuralValidation: CryptographicValidationResult(
            isValid: false,
            issues: [CryptographicTrustTestFixtures.validValidationIssue()],
          ),
        ),
      );
      expect(
          result.evaluationStatus, CryptographicTrustEvaluationStatus.failure);
    });

    test('unavailable source summary yields unavailable evaluation status', () {
      final result = engine.evaluate(
        baseInput(
          sourceSummary: const CryptographicTrustSourceResolutionSummary(
            status: CryptographicTrustSourceResolutionStatus.unavailable,
            resolvedSources: [],
            unresolvedSources: [],
            injectedSources: [],
          ),
        ),
      );
      expect(result.evaluationStatus,
          CryptographicTrustEvaluationStatus.unavailable);
    });

    test('partial source summary yields partial evaluation status', () {
      final result = engine.evaluate(
        baseInput(
          verificationResult:
              CryptographicTrustTestFixtures.validVerificationResult().copyWith(
            status: CryptographicVerificationStatus.partiallyVerified,
          ),
          sourceSummary: const CryptographicTrustSourceResolutionSummary(
            status: CryptographicTrustSourceResolutionStatus.partial,
            resolvedSources: ['custom'],
            unresolvedSources: ['releaseEvidence'],
            injectedSources: [],
          ),
        ),
      );
      expect(
          result.evaluationStatus, CryptographicTrustEvaluationStatus.partial);
    });

    test('verified maps to provisional snapshot status not trusted', () {
      final result = engine.evaluate(baseInput());
      expect(result.snapshotStatus, CryptographicTrustStatus.provisional);
      expect(result.snapshotStatus, isNot(CryptographicTrustStatus.trusted));
    });

    test('invalid verification maps to invalid snapshot status', () {
      final result = engine.evaluate(
        baseInput(
          verificationResult:
              CryptographicTrustTestFixtures.validVerificationResult().copyWith(
            status: CryptographicVerificationStatus.invalid,
          ),
        ),
      );
      expect(result.snapshotStatus, CryptographicTrustStatus.invalid);
    });

    test('limitations always include no deployment authorization', () {
      final result = engine.evaluate(baseInput());
      expect(result.limitations, contains('no-deployment-authorization'));
    });

    test('aggregate trust level uses minimum of candidates', () {
      final result = engine.evaluate(
        baseInput(
          verificationResult:
              CryptographicTrustTestFixtures.validVerificationResult().copyWith(
            trustLevel: CryptographicTrustLevel.high,
          ),
        ),
      );
      expect(result.trustLevel, isNot(CryptographicTrustLevel.critical));
    });

    test('invalid verification forces none trust level', () {
      final result = engine.evaluate(
        baseInput(
          verificationResult:
              CryptographicTrustTestFixtures.validVerificationResult().copyWith(
            status: CryptographicVerificationStatus.invalid,
            trustLevel: CryptographicTrustLevel.high,
          ),
        ),
      );
      expect(result.trustLevel, CryptographicTrustLevel.none);
    });
  });
}
