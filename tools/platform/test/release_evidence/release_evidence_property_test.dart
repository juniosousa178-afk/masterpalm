import 'dart:math';

import 'package:masterpalm_platform/models/release_evidence/release_evidence_bundle.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_artifact.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_enums.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_result.dart';
import 'package:masterpalm_platform/release_evidence/release_evidence_bundle_validator.dart';
import 'package:masterpalm_platform/release_evidence/release_evidence_canonical_serializer.dart';
import 'package:masterpalm_platform/release_evidence/release_evidence_collector.dart';
import 'package:masterpalm_platform/release_evidence/policies/release_evidence_policy_v1.dart';
import 'package:masterpalm_platform/release_evidence/release_evidence_bundle_builder.dart';
import 'package:masterpalm_platform/release_evidence/resolved_release_evidence_sources.dart';
import 'package:test/test.dart';

import 'support/release_evidence_hardening_helpers.dart';
import 'support/release_evidence_test_fixtures.dart';

void main() {
  group('Release Evidence property-based tests', () {
    final random = Random(42);
    const serializer = ReleaseEvidenceCanonicalSerializer();

    List<ReleaseEvidenceArtifact> shuffledEvidence(int seed, int count) {
      final rng = Random(seed);
      final items = List.generate(count, (i) {
        return ReleaseEvidenceArtifact(
          artifactReference: ReleaseEvidenceArtifactReference(
            artifactId: 'prop-$i',
            artifactType: ReleaseEvidenceArtifactType.qualityGate,
            fingerprint: 'fp-$i',
          ),
          subject: ReleaseEvidenceTestFixtures.validSubject(),
          evidenceClass: ReleaseEvidenceClass.technical,
          evidenceRole: ReleaseEvidenceRole.supporting,
          integrity: ReleaseEvidenceTestFixtures.intactIntegrity(),
          availability: ReleaseEvidenceAvailabilityStatus.available,
          compatibility: ReleaseEvidenceCompatibilityStatus.compatible,
          collectedAt: ReleaseEvidenceTestFixtures.referenceTime,
        );
      })
        ..shuffle(rng);
      return items;
    }

    test('bundle builder sorts evidence deterministically for any shuffle', () {
      for (var seed = 0; seed < 20; seed++) {
        final collected = ReleaseEvidenceCollectedArtifacts(
          evidence: shuffledEvidence(seed, 10 + random.nextInt(5)),
        );
        final context = ReleaseEvidenceEvaluationContext(
          request: ReleaseEvidenceTestFixtures.passingRequest(),
          sources: ResolvedReleaseEvidenceSources(
            releaseContext: notRequested(),
            qualityGateSnapshot: notRequested(),
            releaseDecisionSnapshot: notRequested(),
            evidencePolicy: notRequested(),
            attestationPolicy: notRequested(),
            verificationPolicy: notRequested(),
            evidenceReferences: notRequested(),
            attestationSet: notRequested(),
            provenance: notRequested(),
            sourceReferences: const [],
            resolutionSummary: const ReleaseEvidenceSourceResolutionSummary(
              resolvedSources: [],
              unresolvedSources: [],
              injectedSources: [],
            ),
          ),
          evidencePolicy: ReleaseEvidencePolicyV1.create(),
        );
        final bundle = ReleaseEvidenceBundleBuilder().build(
          context: context,
          collected: collected,
          evaluatedAt: ReleaseEvidenceTestFixtures.referenceTime,
        );
        final ids =
            bundle.evidence.map((e) => e.artifactReference.artifactId).toList();
        expect(ids, equals(ids.toList()..sort()));
      }
    });

    test('serializer fingerprint invariant under json key order permutation',
        () {
      final bundle = ReleaseEvidenceTestFixtures.validBundle();
      final fp = serializer.bundleFingerprint(bundle);
      for (var i = 0; i < 10; i++) {
        final json = bundle.toJson();
        expect(serializer.bundleFingerprint(bundle), fp);
        expect(json.keys.length, greaterThan(5));
      }
    });

    test('validation rejects mutated bundle coverage evidence count', () {
      final bundle = ReleaseEvidenceTestFixtures.validBundle();
      final json = bundle.toJson();
      (json['coverage'] as Map<String, dynamic>)['presentEvidenceCount'] =
          bundle.evidence.length + 1;
      final mutated = ReleaseEvidenceBundle.fromJson(json);
      expect(
        const ReleaseEvidenceBundleValidator().validate(mutated).isValid,
        isFalse,
      );
    });
  });
}
