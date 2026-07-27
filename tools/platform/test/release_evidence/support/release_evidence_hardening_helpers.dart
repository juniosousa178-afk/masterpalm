import 'dart:io';

import 'package:masterpalm_platform/core/platform_bootstrap.dart';
import 'package:masterpalm_platform/interfaces/quality_gate_provider.dart';
import 'package:masterpalm_platform/interfaces/release_evidence_provider.dart';
import 'package:masterpalm_platform/interfaces/release_governance_provider.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_request.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_snapshot.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_artifact.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_enums.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_request.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_result.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_subject.dart';
import 'package:masterpalm_platform/models/release_governance/release_decision_snapshot.dart';
import 'package:masterpalm_platform/models/release_governance/release_governance_request.dart';
import 'package:masterpalm_platform/release_evidence/release_evidence_collector.dart';
import 'package:masterpalm_platform/release_evidence/resolved_release_evidence_sources.dart';

import '../../release_governance/support/release_governance_test_fixtures.dart';
import 'release_evidence_test_fixtures.dart';

/// Builds a deterministic passing evaluation via PlatformCore.
Future<ReleaseEvidenceResult> evaluatePassingBundle({
  ReleaseEvidenceProvider? provider,
  ReleaseGovernanceProvider? governanceProvider,
}) async {
  final core = PlatformBootstrap.forRepo(Directory.current.path);
  final rg = governanceProvider ?? core.releaseGovernance();
  final re = provider ?? core.releaseEvidence();
  final rgResult =
      await rg.evaluate(ReleaseGovernanceTestFixtures.passingRequest());
  return re.evaluate(
    ReleaseEvidenceTestFixtures.passingRequest(
      releaseDecisionSnapshot: rgResult.snapshot,
    ),
  );
}

class FakeQualityGateProviderForEvidence implements QualityGateProvider {
  FakeQualityGateProviderForEvidence({this.loaded, this.latestSnapshot});

  QualityGateSnapshot? loaded;
  QualityGateSnapshot? latestSnapshot;
  int loadCalls = 0;
  int latestCalls = 0;
  int evaluateCalls = 0;

  @override
  Future<QualityGateResult> evaluate(QualityGateRequest request) async {
    evaluateCalls++;
    throw StateError('QualityGateProvider.evaluate must not be called');
  }

  @override
  Future<QualityGateResult> evaluateAndPublish(
    QualityGateRequest request,
  ) async {
    evaluateCalls++;
    throw StateError(
        'QualityGateProvider.evaluateAndPublish must not be called');
  }

  @override
  Future<void> publish(QualityGateSnapshot snapshot) async {}

  @override
  Future<QualityGateSnapshot?> load(String snapshotId) async {
    loadCalls++;
    return loaded;
  }

  @override
  Future<QualityGateSnapshot?> latest({
    required String projectId,
    String? policyId,
  }) async {
    latestCalls++;
    return latestSnapshot;
  }

  @override
  Future<List<QualityGateSnapshot>> query(query) async => const [];

  @override
  Future<void> invalidate(String snapshotId) async {}
}

class FakeReleaseGovernanceProviderForEvidence
    implements ReleaseGovernanceProvider {
  FakeReleaseGovernanceProviderForEvidence({this.loaded, this.latestSnapshot});

  ReleaseDecisionSnapshot? loaded;
  ReleaseDecisionSnapshot? latestSnapshot;
  int loadCalls = 0;
  int latestCalls = 0;
  int evaluateCalls = 0;

  @override
  Future<ReleaseGovernanceResult> evaluate(
    ReleaseGovernanceRequest request,
  ) async {
    evaluateCalls++;
    throw StateError('ReleaseGovernanceProvider.evaluate must not be called');
  }

  @override
  Future<ReleaseGovernanceResult> evaluateAndPublish(
    ReleaseGovernanceRequest request,
  ) async {
    evaluateCalls++;
    throw StateError(
      'ReleaseGovernanceProvider.evaluateAndPublish must not be called',
    );
  }

  @override
  Future<void> publish(ReleaseDecisionSnapshot snapshot) async {}

  @override
  Future<ReleaseDecisionSnapshot?> load(String snapshotId) async {
    loadCalls++;
    return loaded;
  }

  @override
  Future<ReleaseDecisionSnapshot?> latest({
    required String projectId,
    String? releaseId,
    String? policyId,
  }) async {
    latestCalls++;
    return latestSnapshot;
  }

  @override
  Future<List<ReleaseDecisionSnapshot>> query(query) async => const [];

  @override
  Future<void> invalidate(String snapshotId) async {}
}

ReleaseEvidenceCollectedArtifacts buildLargeCollectedArtifacts({
  int evidenceCount = 500,
  int attestationCount = 50,
}) {
  final evidence = List.generate(evidenceCount, (i) {
    return ReleaseEvidenceArtifact(
      artifactReference: ReleaseEvidenceArtifactReference(
        artifactId: 'stress-evidence-${i.toString().padLeft(5, '0')}',
        artifactType: ReleaseEvidenceArtifactType.qualityGate,
        fingerprint: 'fp-stress-$i',
      ),
      subject: ReleaseEvidenceSubject(
        subjectId: 'subject-stress-$i',
        subjectType: ReleaseEvidenceSubjectType.qualityGateSnapshot,
        projectId: ReleaseEvidenceTestFixtures.projectId,
        commitId: ReleaseEvidenceTestFixtures.commitId,
      ),
      evidenceClass: ReleaseEvidenceClass.technical,
      evidenceRole: ReleaseEvidenceRole.supporting,
      integrity: ReleaseEvidenceTestFixtures.intactIntegrity(),
      availability: ReleaseEvidenceAvailabilityStatus.available,
      compatibility: ReleaseEvidenceCompatibilityStatus.compatible,
      collectedAt: ReleaseEvidenceTestFixtures.referenceTime,
    );
  });

  final attestations = List.generate(
    attestationCount,
    (i) => ReleaseEvidenceTestFixtures.validAttestation(),
  );

  return ReleaseEvidenceCollectedArtifacts(
    qualityGateSnapshot:
        ReleaseGovernanceTestFixtures.passingQualityGateSnapshot(),
    evidence: evidence,
    attestations: attestations,
    provenance: [ReleaseEvidenceTestFixtures.validProvenance()],
  );
}

ResolvedReleaseEvidenceSource<T> notRequested<T>() {
  return const ResolvedReleaseEvidenceSource(
    sourceType: ReleaseEvidenceType.releaseContext,
    resolutionMode: ReleaseEvidenceSourceResolutionMode.notRequested,
    state: ResolvedReleaseEvidenceSourceState.notRequested,
  );
}
