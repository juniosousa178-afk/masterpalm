import '../models/release_evidence/release_attestation.dart';
import '../models/release_evidence/release_evidence_artifact.dart';
import '../models/release_evidence/release_evidence_enums.dart';
import '../models/release_evidence/release_evidence_reference.dart';
import '../models/release_evidence/release_evidence_subject.dart';
import '../models/release_evidence/release_provenance.dart';
import '../models/release_governance/release_approval.dart';
import '../models/release_governance/release_decision_snapshot.dart';
import '../models/release_governance/release_governance_evidence.dart';
import '../models/quality_gate/quality_gate_snapshot.dart';
import 'resolved_release_evidence_sources.dart';

/// Collected artifacts located from resolved sources without rebuilding snapshots.
class ReleaseEvidenceCollectedArtifacts {
  const ReleaseEvidenceCollectedArtifacts({
    this.qualityGateSnapshot,
    this.releaseDecisionSnapshot,
    this.approvalEvaluationCount = 0,
    this.waiverEvaluationCount = 0,
    this.evidence = const [],
    this.provenance = const [],
    this.attestations = const [],
    this.evidenceReferences = const [],
    this.reports = const [],
  });

  final QualityGateSnapshot? qualityGateSnapshot;
  final ReleaseDecisionSnapshot? releaseDecisionSnapshot;
  final int approvalEvaluationCount;
  final int waiverEvaluationCount;
  final List<ReleaseEvidenceArtifact> evidence;
  final List<ReleaseProvenance> provenance;
  final List<ReleaseAttestation> attestations;
  final List<ReleaseEvidenceReference> evidenceReferences;
  final List<ReleaseEvidenceReference> reports;
}

/// Locates release evidence artifacts from resolved sources.
class ReleaseEvidenceCollector {
  const ReleaseEvidenceCollector();

  ReleaseEvidenceCollectedArtifacts collect(
    ReleaseEvidenceEvaluationContext context,
  ) {
    final sources = context.sources;
    final request = context.request;
    final referenceTime = request.referenceTime;
    final collected = <ReleaseEvidenceArtifact>[];
    final provenance = <ReleaseProvenance>[];
    final attestations = <ReleaseAttestation>[];
    final evidenceRefs = <ReleaseEvidenceReference>[];
    final reports = <ReleaseEvidenceReference>[];

    final qg = sources.qualityGateSnapshot.isAvailable
        ? sources.qualityGateSnapshot.resolvedArtifact
        : null;
    final rg = sources.releaseDecisionSnapshot.isAvailable
        ? sources.releaseDecisionSnapshot.resolvedArtifact
        : null;

    final seenArtifactIds = <String>{};

    void addArtifact(ReleaseEvidenceArtifact artifact) {
      final id = artifact.artifactReference.artifactId;
      if (!seenArtifactIds.add(id)) return;
      collected.add(artifact);
    }

    if (qg != null) {
      addArtifact(_artifactFromQualityGate(qg, referenceTime));
    }
    var approvalCount = 0;
    var waiverCount = 0;
    if (rg != null) {
      addArtifact(_artifactFromReleaseDecision(rg, referenceTime));
      approvalCount = rg.approvalEvaluations.length;
      waiverCount = rg.waiverEvaluations.length;
      for (final evaluation in rg.approvalEvaluations) {
        addArtifact(
          _artifactFromApprovalEvaluation(evaluation, rg, referenceTime),
        );
      }
      for (final evaluation in rg.waiverEvaluations) {
        addArtifact(
          _artifactFromWaiverEvaluation(evaluation, rg, referenceTime),
        );
      }
      for (final evidence in rg.evidence) {
        addArtifact(
          _artifactFromGovernanceEvidence(evidence, rg, referenceTime),
        );
      }
    }

    if (sources.evidenceReferences.isAvailable &&
        sources.evidenceReferences.resolvedArtifact != null) {
      evidenceRefs.addAll(sources.evidenceReferences.resolvedArtifact!);
      for (final ref in sources.evidenceReferences.resolvedArtifact!) {
        if (ref.evidenceType == ReleaseEvidenceType.report) {
          reports.add(ref);
        }
      }
    }

    if (sources.provenance.isAvailable &&
        sources.provenance.resolvedArtifact != null) {
      provenance.addAll(sources.provenance.resolvedArtifact!);
    }

    if (sources.attestationSet.isAvailable &&
        sources.attestationSet.resolvedArtifact != null) {
      attestations
          .addAll(sources.attestationSet.resolvedArtifact!.attestations);
    }

    return ReleaseEvidenceCollectedArtifacts(
      qualityGateSnapshot: qg,
      releaseDecisionSnapshot: rg,
      approvalEvaluationCount: approvalCount,
      waiverEvaluationCount: waiverCount,
      evidence: collected,
      provenance: provenance,
      attestations: attestations,
      evidenceReferences: evidenceRefs,
      reports: reports,
    );
  }

  ReleaseEvidenceArtifact _artifactFromQualityGate(
    QualityGateSnapshot snapshot,
    String referenceTime,
  ) {
    return ReleaseEvidenceArtifact(
      artifactReference: ReleaseEvidenceArtifactReference(
        artifactId: snapshot.metadata.qualityGateSnapshotId,
        artifactType: ReleaseEvidenceArtifactType.qualityGate,
        fingerprint: snapshot.metadata.qualityGateFingerprint,
        schemaVersion: snapshot.metadata.schemaVersion,
      ),
      subject: ReleaseEvidenceSubject(
        subjectId: snapshot.metadata.qualityGateSnapshotId,
        subjectType: ReleaseEvidenceSubjectType.qualityGateSnapshot,
        projectId: snapshot.metadata.projectId,
        commitId: snapshot.metadata.commitId,
        branch: snapshot.metadata.branch,
      ),
      evidenceClass: ReleaseEvidenceClass.technical,
      evidenceRole: ReleaseEvidenceRole.normative,
      integrity: const ReleaseEvidenceIntegrity(
        status: ReleaseEvidenceIntegrityStatus.intact,
        fingerprintPresent: true,
        fingerprintMatches: true,
        identityPresent: true,
        schemaKnown: true,
        canonicalizationKnown: true,
        sourceTrustedByPolicy: true,
        verificationMethod: 'structural',
      ),
      availability: ReleaseEvidenceAvailabilityStatus.available,
      compatibility: ReleaseEvidenceCompatibilityStatus.compatible,
      collectedAt: referenceTime,
    );
  }

  ReleaseEvidenceArtifact _artifactFromReleaseDecision(
    ReleaseDecisionSnapshot snapshot,
    String referenceTime,
  ) {
    return ReleaseEvidenceArtifact(
      artifactReference: ReleaseEvidenceArtifactReference(
        artifactId: snapshot.metadata.snapshotId,
        artifactType: ReleaseEvidenceArtifactType.releaseGovernance,
        fingerprint: snapshot.fingerprint,
        schemaVersion: snapshot.metadata.schemaVersion,
      ),
      subject: ReleaseEvidenceSubject(
        subjectId: snapshot.metadata.snapshotId,
        subjectType: ReleaseEvidenceSubjectType.releaseDecisionSnapshot,
        projectId: snapshot.metadata.projectId,
        releaseId: snapshot.metadata.releaseId,
        releaseVersion: snapshot.metadata.releaseVersion,
        commitId: snapshot.metadata.commitId,
        branch: snapshot.metadata.branch,
        environment: snapshot.metadata.environment,
      ),
      evidenceClass: ReleaseEvidenceClass.governance,
      evidenceRole: ReleaseEvidenceRole.normative,
      integrity: const ReleaseEvidenceIntegrity(
        status: ReleaseEvidenceIntegrityStatus.intact,
        fingerprintPresent: true,
        fingerprintMatches: true,
        identityPresent: true,
        schemaKnown: true,
        canonicalizationKnown: true,
        sourceTrustedByPolicy: true,
        verificationMethod: 'structural',
      ),
      availability: ReleaseEvidenceAvailabilityStatus.available,
      compatibility: ReleaseEvidenceCompatibilityStatus.compatible,
      collectedAt: referenceTime,
    );
  }

  ReleaseEvidenceArtifact _artifactFromApprovalEvaluation(
    ReleaseApprovalEvaluation evaluation,
    ReleaseDecisionSnapshot snapshot,
    String referenceTime,
  ) {
    return ReleaseEvidenceArtifact(
      artifactReference: ReleaseEvidenceArtifactReference(
        artifactId: evaluation.requirementId,
        artifactType: ReleaseEvidenceArtifactType.approval,
        fingerprint: evaluation.fingerprint,
      ),
      subject: ReleaseEvidenceSubject(
        subjectId: evaluation.requirementId,
        subjectType: ReleaseEvidenceSubjectType.approval,
        projectId: snapshot.metadata.projectId,
        releaseId: snapshot.metadata.releaseId,
        commitId: snapshot.metadata.commitId,
        environment: snapshot.metadata.environment,
      ),
      evidenceClass: ReleaseEvidenceClass.governance,
      evidenceRole: ReleaseEvidenceRole.supporting,
      integrity: const ReleaseEvidenceIntegrity(
        status: ReleaseEvidenceIntegrityStatus.intact,
        fingerprintPresent: true,
        identityPresent: true,
        schemaKnown: true,
        canonicalizationKnown: true,
        sourceTrustedByPolicy: true,
        verificationMethod: 'structural',
      ),
      availability: ReleaseEvidenceAvailabilityStatus.available,
      compatibility: ReleaseEvidenceCompatibilityStatus.compatible,
      collectedAt: referenceTime,
    );
  }

  ReleaseEvidenceArtifact _artifactFromWaiverEvaluation(
    ReleaseWaiverEvaluation evaluation,
    ReleaseDecisionSnapshot snapshot,
    String referenceTime,
  ) {
    return ReleaseEvidenceArtifact(
      artifactReference: ReleaseEvidenceArtifactReference(
        artifactId: evaluation.waiverId,
        artifactType: ReleaseEvidenceArtifactType.waiver,
        fingerprint: evaluation.fingerprint,
      ),
      subject: ReleaseEvidenceSubject(
        subjectId: evaluation.waiverId,
        subjectType: ReleaseEvidenceSubjectType.waiver,
        projectId: snapshot.metadata.projectId,
        releaseId: snapshot.metadata.releaseId,
        commitId: snapshot.metadata.commitId,
        environment: snapshot.metadata.environment,
      ),
      evidenceClass: ReleaseEvidenceClass.governance,
      evidenceRole: ReleaseEvidenceRole.supporting,
      integrity: const ReleaseEvidenceIntegrity(
        status: ReleaseEvidenceIntegrityStatus.intact,
        fingerprintPresent: true,
        identityPresent: true,
        schemaKnown: true,
        canonicalizationKnown: true,
        sourceTrustedByPolicy: true,
        verificationMethod: 'structural',
      ),
      availability: ReleaseEvidenceAvailabilityStatus.available,
      compatibility: ReleaseEvidenceCompatibilityStatus.compatible,
      collectedAt: referenceTime,
    );
  }

  ReleaseEvidenceArtifact _artifactFromGovernanceEvidence(
    ReleaseGovernanceEvidence evidence,
    ReleaseDecisionSnapshot snapshot,
    String referenceTime,
  ) {
    return ReleaseEvidenceArtifact(
      artifactReference: ReleaseEvidenceArtifactReference(
        artifactId: evidence.sourceArtifactId,
        artifactType: ReleaseEvidenceArtifactType.releaseGovernance,
        fingerprint: evidence.sourceFingerprint ?? evidence.sourceArtifactId,
      ),
      subject: ReleaseEvidenceSubject(
        subjectId: evidence.evidenceId,
        subjectType: ReleaseEvidenceSubjectType.releaseDecisionSnapshot,
        projectId: snapshot.metadata.projectId,
        releaseId: snapshot.metadata.releaseId,
        commitId: snapshot.metadata.commitId,
        environment: snapshot.metadata.environment,
      ),
      evidenceClass: ReleaseEvidenceClass.operational,
      evidenceRole: ReleaseEvidenceRole.derived,
      integrity: const ReleaseEvidenceIntegrity(
        status: ReleaseEvidenceIntegrityStatus.intact,
        fingerprintPresent: true,
        identityPresent: true,
        schemaKnown: true,
        canonicalizationKnown: true,
        sourceTrustedByPolicy: true,
        verificationMethod: 'structural',
      ),
      availability: ReleaseEvidenceAvailabilityStatus.available,
      compatibility: ReleaseEvidenceCompatibilityStatus.compatible,
      collectedAt: referenceTime,
    );
  }
}
