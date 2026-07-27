import 'package:masterpalm_platform/models/release_evidence/release_evidence_result.dart';
import 'package:masterpalm_platform/release_evidence/policies/release_evidence_policy_v1.dart';
import 'package:masterpalm_platform/release_evidence/release_evidence_bundle_builder.dart';
import 'package:masterpalm_platform/release_evidence/release_evidence_collector.dart';
import 'package:masterpalm_platform/release_evidence/resolved_release_evidence_sources.dart';
import 'package:test/test.dart';

import 'support/release_evidence_hardening_helpers.dart';
import 'support/release_evidence_test_fixtures.dart';

void main() {
  group('Release Evidence stress tests', () {
    test('bundle builder handles 1000 evidence artifacts', () {
      final collected = buildLargeCollectedArtifacts(evidenceCount: 1000);
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

      final stopwatch = Stopwatch()..start();
      final bundle = ReleaseEvidenceBundleBuilder().build(
        context: context,
        collected: collected,
        evaluatedAt: ReleaseEvidenceTestFixtures.referenceTime,
      );
      stopwatch.stop();

      expect(bundle.evidence, hasLength(1000));
      expect(stopwatch.elapsedMilliseconds, lessThan(5000));
    });

    test('collector dedup maintains stability at scale', () {
      final collected = buildLargeCollectedArtifacts(evidenceCount: 200);
      final ids = collected.evidence.map((e) => e.artifactReference.artifactId);
      expect(ids.length, equals(ids.toSet().length));
    });
  });
}
