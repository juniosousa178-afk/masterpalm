import 'package:masterpalm_platform/models/cryptographic_trust/collected_cryptographic_trust_material.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_evaluation_result.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_policy.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_operation_context.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_evaluation_request.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_evaluation_result.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_operation_message.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_policy_reference.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_query.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/resolved_cryptographic_trust_sources.dart';
import 'package:test/test.dart';

import 'support/cryptographic_trust_operational_fixtures.dart';
import 'support/cryptographic_trust_test_fixtures.dart';

void main() {
  group('Cryptographic Trust operational models', () {
    test('operational enums roundtrip wire names', () {
      for (final value in CryptographicTrustOperation.values) {
        expect(
          CryptographicTrustOperationX.fromWireName(value.wireName),
          value,
        );
      }
      for (final value in CryptographicTrustEvaluationStatus.values) {
        expect(
          CryptographicTrustEvaluationStatusX.fromWireName(value.wireName),
          value,
        );
      }
      for (final value in CryptographicTrustSourceResolutionStatus.values) {
        expect(
          CryptographicTrustSourceResolutionStatusX.fromWireName(
              value.wireName),
          value,
        );
      }
      for (final value in CryptographicPrimitiveOutcome.values) {
        expect(
          CryptographicPrimitiveOutcomeX.fromWireName(value.wireName),
          value,
        );
      }
    });

    test('CryptographicTrustEvaluationRequest json roundtrip', () {
      final request = CryptographicTrustOperationalFixtures.evaluationRequest();
      final restored =
          CryptographicTrustEvaluationRequest.fromJson(request.toJson());
      expect(restored.evaluationId, request.evaluationId);
      expect(restored.projectId, request.projectId);
      expect(restored.verificationRequest.requestId,
          request.verificationRequest.requestId);
    });

    test('CryptographicTrustPolicyReference json roundtrip', () {
      const reference = CryptographicTrustPolicyReference(
        policyId: 'artifact-signature-trust-v1',
        policyVersion: 1,
        status: CryptographicPolicyStatus.candidate,
        explicitSelection: true,
      );
      final restored =
          CryptographicTrustPolicyReference.fromJson(reference.toJson());
      expect(restored, reference);
    });

    test('CryptographicTrustOperationMessage json roundtrip', () {
      const message = CryptographicTrustOperationMessage(
        messageId: 'msg-001',
        code: 'source-unavailable',
        message: 'missing source',
        severity: CryptographicIssueSeverity.warning,
        operation: CryptographicTrustOperation.resolve,
        conflictType: CryptographicTrustConflictType.fingerprintMismatch,
      );
      final restored =
          CryptographicTrustOperationMessage.fromJson(message.toJson());
      expect(restored, message);
    });

    test('CryptographicTrustSourceResolutionSummary json roundtrip', () {
      const summary = CryptographicTrustSourceResolutionSummary(
        status: CryptographicTrustSourceResolutionStatus.partial,
        resolvedSources: ['releaseEvidence'],
        unresolvedSources: ['cicdIntegration'],
        injectedSources: ['custom'],
        fingerprint: 'abc123',
      );
      final restored =
          CryptographicTrustSourceResolutionSummary.fromJson(summary.toJson());
      expect(restored, summary);
    });

    test('ResolvedCryptographicTrustSource json preserves mode and state', () {
      const source = ResolvedCryptographicTrustSource<CryptographicTrustPolicy>(
        sourceType: CryptographicSourceType.custom,
        resolutionMode: CryptographicTrustSourceResolutionMode.injected,
        state: CryptographicTrustSourceState.available,
        resolvedId: 'artifact-signature-trust-v1',
      );
      final restored =
          ResolvedCryptographicTrustSource<CryptographicTrustPolicy>.fromJson(
              source.toJson());
      expect(restored.resolutionMode, source.resolutionMode);
      expect(restored.state, source.state);
    });

    test('CollectedCryptographicTrustMaterial json roundtrip', () {
      final material = CollectedCryptographicTrustMaterial(
        subjects: [CryptographicTrustTestFixtures.validSubject()],
        digests: [CryptographicTrustTestFixtures.validDigest()],
        signatures: [CryptographicTrustTestFixtures.validSignatureEnvelope()],
        metadata: const {'evaluationId': 'ct-eval-001'},
      );
      final restored =
          CollectedCryptographicTrustMaterial.fromJson(material.toJson());
      expect(restored.subjects, material.subjects);
      expect(restored.digests, material.digests);
      expect(restored.signatures, material.signatures);
    });

    test('CryptographicTrustEvaluationResult json roundtrip', () {
      final result = CryptographicTrustEvaluationResult(
        status: CryptographicTrustEvaluationStatus.success,
        evaluationId: CryptographicTrustOperationalFixtures.evaluationId,
        projectId: CryptographicTrustOperationalFixtures.projectId,
        releaseId: CryptographicTrustOperationalFixtures.releaseId,
        verificationResult:
            CryptographicTrustTestFixtures.validVerificationResult(),
        snapshot: CryptographicTrustTestFixtures.validSnapshot(),
        metadata: const {'noReleaseAuthorization': 'true'},
        evaluatedAt: CryptographicTrustOperationalFixtures.referenceTime,
      );
      final restored =
          CryptographicTrustEvaluationResult.fromJson(result.toJson());
      expect(restored.status, result.status);
      expect(restored.evaluationId, result.evaluationId);
      expect(restored.metadata, result.metadata);
    });

    test('CryptographicOperationContext json roundtrip', () {
      final request = CryptographicTrustOperationalFixtures.evaluationRequest();
      final context = CryptographicOperationContext(
        operation: CryptographicTrustOperation.evaluate,
        request: request,
        sources: const ResolvedCryptographicTrustSources(
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
          sourceReferences: const [],
          resolutionSummary: CryptographicTrustSourceResolutionSummary(
            status: CryptographicTrustSourceResolutionStatus.complete,
            resolvedSources: const [],
            unresolvedSources: const [],
            injectedSources: const [],
          ),
        ),
        material: const CollectedCryptographicTrustMaterial(),
      );
      final restored = CryptographicOperationContext.fromJson(context.toJson());
      expect(restored.operation, context.operation);
      expect(restored.request.evaluationId, context.request.evaluationId);
    });

    test('CryptographicTrustQuery json roundtrip', () {
      const query = CryptographicTrustQuery(
        projectId: CryptographicTrustOperationalFixtures.projectId,
        releaseId: CryptographicTrustOperationalFixtures.releaseId,
        limit: 10,
        offset: 0,
      );
      final restored = CryptographicTrustQuery.fromJson(query.toJson());
      expect(restored, query);
    });

    test('evaluation result metadata documents no release authorization', () {
      final result = CryptographicTrustEvaluationResult(
        status: CryptographicTrustEvaluationStatus.success,
        evaluationId: 'ct-eval-meta',
        projectId: CryptographicTrustOperationalFixtures.projectId,
        metadata: const {'noReleaseAuthorization': 'true'},
      );
      expect(result.metadata['noReleaseAuthorization'], 'true');
      expect(result.toJson().containsKey('releaseAuthorized'), isFalse);
    });
  });
}
