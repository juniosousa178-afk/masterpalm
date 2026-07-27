import '../../models/release_evidence/release_evidence_bundle.dart';
import '../../models/release_evidence/release_evidence_enums.dart';
import '../../models/release_governance/release_governance_enums.dart';
import '../report_input.dart';

/// Converts [ReleaseEvidenceBundle] into report input data.
///
/// Consumes an existing bundle only — never executes release evidence engines.
class ReleaseEvidenceReportSource {
  const ReleaseEvidenceReportSource();

  ReleaseEvidenceReportInputData fromBundle(ReleaseEvidenceBundle bundle) {
    final meta = bundle.metadata;
    final evidenceSummaries = bundle.evidence
        .map(
          (e) =>
              '${e.artifactReference.artifactId}:${e.artifactReference.artifactType.wireName}',
        )
        .toList();
    final attestationSummaries = bundle.attestations
        .map(
          (a) =>
              '${a.metadata.attestationId}:${a.metadata.attestationType.wireName}',
        )
        .toList();
    final provenanceSummaries = bundle.provenance
        .map((p) => '${p.provenanceId}:${p.provenanceType.wireName}')
        .toList();
    final sourceSummaries = bundle.sourceReferences
        .map(
          (r) => '${r.sourceType.wireName}:${r.resolvedId ?? r.requestedId}',
        )
        .toList();

    return ReleaseEvidenceReportInputData(
      bundleId: meta.bundleId,
      fingerprint: bundle.fingerprint,
      policyId: meta.policyId,
      policyVersion: meta.policyVersion,
      projectId: meta.projectId,
      releaseId: meta.releaseId,
      releaseVersion: meta.releaseVersion,
      commitId: meta.commitId,
      environment: meta.environment.wireName,
      compatibility: bundle.compatibility.status.wireName,
      eligibility: bundle.eligibility.status.wireName,
      evidenceCount: meta.evidenceCount,
      attestationCount: meta.attestationCount,
      evidenceCoveragePercentage: bundle.coverage.evidenceCoveragePercentage,
      attestationCoveragePercentage:
          bundle.coverage.attestationCoveragePercentage,
      provenanceCoveragePercentage:
          bundle.coverage.provenanceCoveragePercentage,
      qualityGateSnapshotId: bundle.qualityGateReference.qualityGateSnapshotId,
      qualityGateDecision: bundle.qualityGateReference.decision,
      releaseDecisionSnapshotId:
          bundle.releaseDecisionReference.releaseDecisionSnapshotId,
      releaseDecision: bundle.releaseDecisionReference.decision,
      evidenceSummaries: evidenceSummaries,
      attestationSummaries: attestationSummaries,
      provenanceSummaries: provenanceSummaries,
      sourceSummaries: sourceSummaries,
      limitations: bundle.limitations.map((l) => l.description).toList(),
      warnings: bundle.warnings.map((w) => w.message).toList(),
      errors: bundle.errors.map((e) => e.message).toList(),
    );
  }

  ReleaseEvidenceReportInputData fromMap(Map<String, dynamic> json) {
    return fromBundle(ReleaseEvidenceBundle.fromJson(json));
  }
}
