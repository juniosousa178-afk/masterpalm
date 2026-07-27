import 'package:masterpalm_platform/models/release_evidence/release_evidence_result.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_enums.dart';
import 'package:masterpalm_platform/release_evidence/policies/release_evidence_policy_v1.dart';
import 'package:masterpalm_platform/release_evidence/release_evidence_collector.dart';
import 'package:masterpalm_platform/release_evidence/resolved_release_evidence_sources.dart';
import 'package:test/test.dart';

import '../release_governance/support/release_governance_test_fixtures.dart';
import 'support/release_evidence_hardening_helpers.dart';
import 'support/release_evidence_test_fixtures.dart';

void main() {
  group('Release Evidence collector audit', () {
    const collector = ReleaseEvidenceCollector();

    ResolvedReleaseEvidenceSources buildSources({
      required dynamic qg,
      required dynamic rg,
    }) {
      return ResolvedReleaseEvidenceSources(
        releaseContext: ResolvedReleaseEvidenceSource(
          sourceType: ReleaseEvidenceType.releaseContext,
          resolutionMode: ReleaseEvidenceSourceResolutionMode.injected,
          state: ResolvedReleaseEvidenceSourceState.available,
        ),
        qualityGateSnapshot: ResolvedReleaseEvidenceSource(
          sourceType: ReleaseEvidenceType.qualityGate,
          resolutionMode: ReleaseEvidenceSourceResolutionMode.injected,
          state: ResolvedReleaseEvidenceSourceState.available,
          resolvedArtifact: qg,
        ),
        releaseDecisionSnapshot: ResolvedReleaseEvidenceSource(
          sourceType: ReleaseEvidenceType.releaseGovernance,
          resolutionMode: ReleaseEvidenceSourceResolutionMode.injected,
          state: ResolvedReleaseEvidenceSourceState.available,
          resolvedArtifact: rg,
        ),
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
      );
    }

    test('deduplicates evidence by artifactId', () {
      final qg = ReleaseEvidenceTestFixtures.passingQualityGateSnapshot();
      final context = ReleaseEvidenceEvaluationContext(
        request: ReleaseEvidenceTestFixtures.passingRequest(
          qualityGateSnapshot: qg,
        ),
        sources: buildSources(qg: qg, rg: null),
        evidencePolicy: ReleaseEvidencePolicyV1.create(),
      );
      final collected = collector.collect(context);
      final ids = collected.evidence
          .map((e) => e.artifactReference.artifactId)
          .toList();
      expect(ids, equals(ids.toSet().toList()..sort()));
    });

    test('does not duplicate QG fingerprint in multiple artifacts for same id',
        () {
      final qg = ReleaseEvidenceTestFixtures.passingQualityGateSnapshot();
      final context = ReleaseEvidenceEvaluationContext(
        request: ReleaseEvidenceTestFixtures.passingRequest(
          qualityGateSnapshot: qg,
        ),
        sources: buildSources(qg: qg, rg: null),
        evidencePolicy: ReleaseEvidencePolicyV1.create(),
      );
      final collected = collector.collect(context);
      final qgArtifacts = collected.evidence
          .where(
            (e) =>
                e.artifactReference.artifactId ==
                qg.metadata.qualityGateSnapshotId,
          )
          .toList();
      expect(qgArtifacts, hasLength(1));
    });

    test('absent sources produce no artifacts for that type', () {
      final context = ReleaseEvidenceEvaluationContext(
        request: ReleaseEvidenceTestFixtures.passingRequest(),
        sources: buildSources(qg: null, rg: null),
        evidencePolicy: ReleaseEvidencePolicyV1.create(),
      );
      final collected = collector.collect(context);
      expect(collected.qualityGateSnapshot, isNull);
      expect(collected.releaseDecisionSnapshot, isNull);
      expect(collected.evidence, isEmpty);
    });

    test('artifacts reference fingerprints not payloads', () {
      final qg = ReleaseEvidenceTestFixtures.passingQualityGateSnapshot();
      final context = ReleaseEvidenceEvaluationContext(
        request: ReleaseEvidenceTestFixtures.passingRequest(
          qualityGateSnapshot: qg,
        ),
        sources: buildSources(qg: qg, rg: null),
        evidencePolicy: ReleaseEvidencePolicyV1.create(),
      );
      final collected = collector.collect(context);
      for (final artifact in collected.evidence) {
        expect(artifact.artifactReference.fingerprint, isNotEmpty);
        expect(artifact.toJson().containsKey('payload'), isFalse);
      }
    });
  });
}
