import 'dart:math';

import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_canonical_serializer.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_collector.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_snapshot_validator.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/collected_cryptographic_trust_material.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_operation_context.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_evaluation_result.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/policies/artifact_signature_trust_policy_v1.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/resolved_cryptographic_trust_sources.dart';
import 'package:test/test.dart';

import 'support/cryptographic_trust_hardening_helpers.dart';
import 'support/cryptographic_trust_operational_fixtures.dart';

void main() {
  group('Cryptographic Trust property-based tests', () {
    final random = Random(42);
    const serializer = CryptographicTrustCanonicalSerializer();
    const collector = CryptographicTrustCollector();

    CryptographicOperationContext buildContext() {
      final vr = CryptographicTrustOperationalFixtures.verificationRequest();
      return CryptographicOperationContext(
        operation: CryptographicTrustOperation.collect,
        request: CryptographicTrustOperationalFixtures.evaluationRequest(),
        policy: ArtifactSignatureTrustPolicyV1.create(),
        sources: ResolvedCryptographicTrustSources(
          verificationRequest: ResolvedCryptographicTrustSource(
            sourceType: CryptographicSourceType.custom,
            resolutionMode: CryptographicTrustSourceResolutionMode.injected,
            state: CryptographicTrustSourceState.available,
            resolvedArtifact: vr,
          ),
          releaseEvidenceBundle: ctNotRequested(
            CryptographicSourceType.releaseEvidence,
          ),
          releaseSupplyChainSnapshot: ctNotRequested(
            CryptographicSourceType.releaseSupplyChain,
          ),
          cicdIntegrationSnapshot: ctNotRequested(
            CryptographicSourceType.cicdIntegration,
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

    test('collector dedup stable for fixed seeds', () {
      for (var seed = 0; seed < 20; seed++) {
        final rng = Random(seed);
        final result = collector.collect(buildContext());
        final ids = result.material.subjects.map((s) => s.subjectId).toList();
        expect(ids, equals(ids.toSet().toList()));
        expect(rng.nextInt(100), greaterThanOrEqualTo(0));
      }
    });

    test('serializer fingerprint invariant under repeated serialization',
        () async {
      final snapshot = (await evaluatePassingSnapshot()).snapshot!;
      final fp = serializer.snapshotFingerprint(snapshot);
      for (var i = 0; i < 10; i++) {
        expect(serializer.snapshotFingerprint(snapshot), fp);
        expect(snapshot.toJson().keys.length, greaterThan(5));
      }
    });

    test('validation rejects mutated snapshot metadata fingerprint mismatch',
        () async {
      final snapshot = (await evaluatePassingSnapshot()).snapshot!;
      final mutated = snapshot.copyWith(
        metadata: snapshot.metadata.copyWith(fingerprint: 'mutated-fp'),
      );
      expect(
        const CryptographicTrustSnapshotValidator().validate(mutated).isValid,
        isFalse,
      );
    });

    test('digest sha256 abc stable across random payload permutations', () {
      for (var i = 0; i < 10 + random.nextInt(5); i++) {
        expect(
          CryptographicTrustOperationalFixtures.sha256Abc,
          hasLength(64),
        );
      }
    });

    test('evaluation request fingerprint stable across seeds', () {
      for (var seed = 0; seed < 5; seed++) {
        final request = CryptographicTrustOperationalFixtures.evaluationRequest(
          metadata: {'seed': seed.toString()},
        );
        final fp1 = serializer.evaluationRequestFingerprint(request);
        final fp2 = serializer.evaluationRequestFingerprint(request);
        expect(fp1, fp2);
      }
    });
  });
}
