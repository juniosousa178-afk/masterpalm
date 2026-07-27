import 'package:masterpalm_platform/models/release_evidence/release_attestation.dart';
import 'package:masterpalm_platform/models/release_evidence/release_attestation_authority.dart';
import 'package:masterpalm_platform/models/release_evidence/release_attestation_issuer.dart';
import 'package:masterpalm_platform/models/release_evidence/release_attestation_metadata.dart';
import 'package:masterpalm_platform/models/release_evidence/release_attestation_predicate.dart';
import 'package:masterpalm_platform/models/release_evidence/release_attestation_statement.dart';
import 'package:masterpalm_platform/models/release_evidence/release_attestation_subject.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_artifact.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_bundle.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_bundle_metadata.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_compatibility.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_enums.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_reference.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_result.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_subject.dart';
import 'package:masterpalm_platform/models/release_evidence/release_provenance.dart';
import 'package:masterpalm_platform/models/release_evidence/release_provenance_actor.dart';
import 'package:masterpalm_platform/models/release_evidence/release_provenance_step.dart';
import 'package:masterpalm_platform/models/release_evidence/release_verification_check.dart';
import 'package:masterpalm_platform/models/release_evidence/release_verification_policy.dart';
import 'package:masterpalm_platform/models/release_evidence/release_verification_result.dart';
import 'package:masterpalm_platform/models/release_governance/release_governance_enums.dart';
import 'package:masterpalm_platform/models/release_evidence/release_attestation_set.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_request.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_snapshot.dart';
import 'package:masterpalm_platform/models/release_governance/release_decision_snapshot.dart';
import 'package:masterpalm_platform/models/release_governance/release_context.dart';
import 'package:masterpalm_platform/release_evidence/policies/release_attestation_policy_v1.dart';
import 'package:masterpalm_platform/release_evidence/policies/release_evidence_policy_v1.dart';
import 'package:masterpalm_platform/release_evidence/policies/release_verification_policy_v1.dart';

import '../../release_governance/support/release_governance_test_fixtures.dart';

class ReleaseEvidenceTestFixtures {
  static const referenceTime = '2026-06-15T12:00:00.000Z';
  static const projectId = 'masterpalm-demo';
  static const releaseId = 'rel-2026-06-15-001';
  static const commitId = 'abc123def456';
  static const bundleId = 'bundle-2026-06-15-001';
  static const policyId = ReleaseEvidencePolicyV1.policyId;
  static const policyFingerprint = 'fp-policy-release-evidence-v1';
  static const bundleFingerprint = 'fp-bundle-001';

  static ReleaseEvidenceSubject validSubject() {
    return ReleaseEvidenceSubject(
      subjectId: 'subject-release-001',
      subjectType: ReleaseEvidenceSubjectType.release,
      projectId: projectId,
      releaseId: releaseId,
      releaseVersion: '4.0.0-beta.1',
      commitId: commitId,
      environment: ReleaseEnvironment.production,
    );
  }

  static ReleaseEvidenceIntegrity intactIntegrity() {
    return const ReleaseEvidenceIntegrity(
      status: ReleaseEvidenceIntegrityStatus.intact,
      fingerprintPresent: true,
      fingerprintMatches: true,
      identityPresent: true,
      schemaKnown: true,
      canonicalizationKnown: true,
      sourceTrustedByPolicy: true,
      verificationMethod: 'structural',
    );
  }

  static ReleaseEvidenceArtifact qualityGateArtifact() {
    return ReleaseEvidenceArtifact(
      artifactReference: const ReleaseEvidenceArtifactReference(
        artifactId: 'qg-snapshot-001',
        artifactType: ReleaseEvidenceArtifactType.qualityGate,
        fingerprint: 'fp-qg-001',
      ),
      subject: validSubject().copyWith(
        subjectType: ReleaseEvidenceSubjectType.qualityGateSnapshot,
      ),
      evidenceClass: ReleaseEvidenceClass.technical,
      evidenceRole: ReleaseEvidenceRole.normative,
      integrity: intactIntegrity(),
      availability: ReleaseEvidenceAvailabilityStatus.available,
      compatibility: ReleaseEvidenceCompatibilityStatus.compatible,
      collectedAt: referenceTime,
    );
  }

  static ReleaseEvidenceArtifact releaseDecisionArtifact() {
    return ReleaseEvidenceArtifact(
      artifactReference: const ReleaseEvidenceArtifactReference(
        artifactId: 'rg-snapshot-001',
        artifactType: ReleaseEvidenceArtifactType.releaseGovernance,
        fingerprint: 'fp-rg-001',
      ),
      subject: validSubject().copyWith(
        subjectType: ReleaseEvidenceSubjectType.releaseDecisionSnapshot,
      ),
      evidenceClass: ReleaseEvidenceClass.governance,
      evidenceRole: ReleaseEvidenceRole.normative,
      integrity: intactIntegrity(),
      availability: ReleaseEvidenceAvailabilityStatus.available,
      compatibility: ReleaseEvidenceCompatibilityStatus.compatible,
      collectedAt: referenceTime,
    );
  }

  static ReleaseEvidenceCoverage validCoverage({
    int evidenceCount = 2,
    int attestationCount = 1,
  }) {
    return ReleaseEvidenceCoverage(
      requiredEvidenceCount: 2,
      presentEvidenceCount: evidenceCount,
      validEvidenceCount: evidenceCount,
      invalidEvidenceCount: 0,
      unavailableEvidenceCount: 0,
      incompatibleEvidenceCount: 0,
      expiredEvidenceCount: 0,
      normativeEvidenceCount: evidenceCount,
      supportingEvidenceCount: 0,
      requiredAttestationCount: 1,
      presentAttestationCount: attestationCount,
      validAttestationCount: attestationCount,
      invalidAttestationCount: 0,
      expiredAttestationCount: 0,
      unverifiedAttestationCount: 0,
      provenanceRequiredCount: 1,
      provenancePresentCount: 1,
      evidenceCoveragePercentage: 100,
      attestationCoveragePercentage: 100,
      provenanceCoveragePercentage: 100,
      sourceCoveragePercentage: 100,
      fingerprint: 'fp-coverage-001',
    );
  }

  static ReleaseEvidenceCompatibility validCompatibility() {
    return const ReleaseEvidenceCompatibility(
      status: ReleaseEvidenceCompatibilityStatus.compatible,
      checks: [],
      compatibleSources: [
        ReleaseEvidenceType.qualityGate,
        ReleaseEvidenceType.releaseGovernance,
      ],
      partiallyCompatibleSources: [],
      incompatibleSources: [],
      unknownSources: [],
      reasons: ['all sources compatible'],
      compatibilityFingerprint: 'fp-compat-001',
    );
  }

  static ReleaseEvidenceEligibility validEligibility() {
    return const ReleaseEvidenceEligibility(
      status: ReleaseEvidenceEligibilityStatus.eligible,
      reasons: ['all required sources present'],
      missingSources: [],
      incompatibleSources: [],
      eligibilityFingerprint: 'fp-elig-001',
    );
  }

  static ReleaseProvenance validProvenance() {
    return ReleaseProvenance(
      provenanceId: 'prov-001',
      subjectId: 'subject-release-001',
      provenanceType: ReleaseProvenanceType.releaseGovernance,
      origin: 'masterpalm-platform',
      actors: const [
        ReleaseProvenanceActor(
          actorId: 'release-bot',
          actorType: ReleaseProvenanceActorType.automation,
          identityStatus: ReleaseIdentityStatus.declared,
        ),
      ],
      steps: const [
        ReleaseProvenanceStep(
          stepId: 'step-collect',
          order: 1,
          stepType: ReleaseProvenanceStepType.releaseGovernance,
          name: 'Collect evidence',
          status: ReleaseProvenanceStatus.completed,
          fingerprint: 'fp-step-001',
        ),
      ],
      inputs: const ['qg-snapshot-001', 'rg-snapshot-001'],
      outputs: const [bundleId],
      environment: ReleaseEnvironment.production,
      toolReferences: const ['masterpalm-platform'],
      evidenceReferences: const [],
      status: ReleaseProvenanceStatus.completed,
      fingerprint: 'fp-prov-001',
      schemaVersion: 1,
      completedAt: referenceTime,
    );
  }

  static ReleaseEvidenceBundle validBundle() {
    final evidence = [qualityGateArtifact(), releaseDecisionArtifact()];
    final attestations = [validAttestation()];
    return ReleaseEvidenceBundle(
      metadata: ReleaseEvidenceBundleMetadata(
        bundleId: bundleId,
        projectId: projectId,
        releaseId: releaseId,
        releaseVersion: '4.0.0-beta.1',
        commitId: commitId,
        environment: ReleaseEnvironment.production,
        policyId: policyId,
        policyVersion: 1,
        policyFingerprint: policyFingerprint,
        schemaVersion: 1,
        calculationVersion: 1,
        canonicalizationVersion: 1,
        sourceSetFingerprint: 'fp-sources-001',
        requestFingerprint: 'fp-request-001',
        createdAt: referenceTime,
        evaluatedAt: referenceTime,
        referenceTime: referenceTime,
        evidenceCount: evidence.length,
        attestationCount: attestations.length,
        fingerprint: bundleFingerprint,
      ),
      subject: validSubject(),
      policyReference: const ReleaseEvidencePolicyReference(
        policyId: policyId,
        policyVersion: 1,
        policyFingerprint: policyFingerprint,
      ),
      releaseContextReference: ReleaseReleaseContextReference(
        releaseContextId: 'ctx-001',
        projectId: projectId,
        releaseId: releaseId,
        fingerprint: 'fp-ctx-001',
        commitId: commitId,
      ),
      qualityGateReference: const ReleaseQualityGateEvidenceReference(
        qualityGateSnapshotId: 'qg-snapshot-001',
        qualityGateFingerprint: 'fp-qg-001',
        policyId: 'quality-gate-release-v1',
        policyVersion: 1,
        decision: 'passed',
        projectId: projectId,
        commitId: commitId,
      ),
      releaseDecisionReference: const ReleaseDecisionEvidenceReference(
        releaseDecisionSnapshotId: 'rg-snapshot-001',
        releaseDecisionFingerprint: 'fp-rg-001',
        policyId: 'release-governance-v1',
        policyVersion: 1,
        decision: 'approved',
        qualityGateSnapshotId: 'qg-snapshot-001',
        projectId: projectId,
        commitId: commitId,
      ),
      evidence: evidence,
      provenance: [validProvenance()],
      attestations: attestations,
      compatibility: validCompatibility(),
      eligibility: validEligibility(),
      coverage: validCoverage(
        evidenceCount: evidence.length,
        attestationCount: attestations.length,
      ),
      sourceReferences: const [
        ReleaseEvidenceSourceReference(
          sourceType: ReleaseEvidenceType.qualityGate,
          resolutionMode: ReleaseEvidenceSourceResolutionMode.injected,
          requestedId: 'qg-snapshot-001',
          resolvedId: 'qg-snapshot-001',
          fingerprint: 'fp-qg-001',
          projectId: projectId,
          commitId: commitId,
          availability: ReleaseEvidenceAvailabilityStatus.available,
          compatibility: ReleaseEvidenceCompatibilityStatus.compatible,
        ),
        ReleaseEvidenceSourceReference(
          sourceType: ReleaseEvidenceType.releaseGovernance,
          resolutionMode: ReleaseEvidenceSourceResolutionMode.injected,
          requestedId: 'rg-snapshot-001',
          resolvedId: 'rg-snapshot-001',
          fingerprint: 'fp-rg-001',
          projectId: projectId,
          commitId: commitId,
          availability: ReleaseEvidenceAvailabilityStatus.available,
          compatibility: ReleaseEvidenceCompatibilityStatus.compatible,
        ),
      ],
      fingerprint: bundleFingerprint,
    );
  }

  static ReleaseAttestation validAttestation({
    ReleaseAttestationType type =
        ReleaseAttestationType.evidenceBundleIntegrity,
    ReleaseAttestationPredicateType predicateType =
        ReleaseAttestationPredicateType.evidenceBundle,
    String outcome = 'satisfied',
    bool authorizationConsistent = true,
  }) {
    return ReleaseAttestation(
      metadata: ReleaseAttestationMetadata(
        attestationId: 'att-001',
        attestationType: type,
        policyId: ReleaseAttestationPolicyV1.policyId,
        policyVersion: 1,
        policyFingerprint: 'fp-attestation-policy-v1',
        projectId: projectId,
        releaseId: releaseId,
        commitId: commitId,
        schemaVersion: 1,
        predicateType: predicateType,
        predicateVersion: '1',
        canonicalizationVersion: 1,
        calculationVersion: 1,
        createdAt: referenceTime,
        fingerprint: 'fp-att-001',
      ),
      statement: ReleaseAttestationStatement(
        statementId: 'stmt-001',
        statementType: 'integrity',
        predicateType: predicateType,
        predicateVersion: '1',
        claim: ReleaseAttestationClaim(
          claimKind: 'bundleIntegrity',
          evidenceBundleId: bundleId,
          evidenceBundleFingerprint: bundleFingerprint,
          integritySatisfied: true,
          authorizationConsistent: authorizationConsistent,
        ),
        outcome: outcome,
        confidence: 1.0,
        issuedUnderPolicy: ReleaseAttestationPolicyV1.policyId,
        evidenceBasis: const [bundleId],
        fingerprint: 'fp-stmt-001',
      ),
      subjects: const [
        ReleaseAttestationSubject(
          subjectId: 'subject-release-001',
          subjectType: ReleaseEvidenceSubjectType.evidenceBundle,
          artifactId: bundleId,
          artifactFingerprint: bundleFingerprint,
          projectId: projectId,
          releaseId: releaseId,
          commitId: commitId,
          environment: ReleaseEnvironment.production,
          schemaVersion: 1,
        ),
      ],
      predicate: EvidenceBundlePredicate(
        predicateVersion: '1',
        result: ReleaseAttestationPredicateResult.satisfied,
        evidenceIds: const [bundleId],
        limitations: const [],
        fingerprint: 'fp-predicate-001',
        expectedBundleId: bundleId,
        expectedBundleFingerprint: bundleFingerprint,
        observedBundleId: bundleId,
        observedBundleFingerprint: bundleFingerprint,
      ),
      issuer: const ReleaseAttestationIssuer(
        issuerId: 'masterpalm-platform',
        issuerType: ReleaseAttestationIssuerType.platform,
        identityStatus: ReleaseIdentityStatus.structurallyValidated,
        validFrom: '2026-01-01T00:00:00.000Z',
      ),
      authority: ReleaseAttestationAuthority(
        authorityId: 'masterpalm-attestation-authority',
        authorityType: 'platform',
        allowedAttestationTypes: const [
          ReleaseAttestationType.evidenceBundleIntegrity,
        ],
        allowedSubjectTypes: const [
          ReleaseEvidenceSubjectType.evidenceBundle,
        ],
        allowedEnvironments: const [ReleaseEnvironment.production],
        allowedReleaseTypes: const [ReleaseType.production],
        validFrom: '2026-01-01T00:00:00.000Z',
        status: ReleaseAttestationAuthorityStatus.active,
        schemaVersion: 1,
      ),
      status: ReleaseAttestationStatus.active,
      issuedAt: referenceTime,
      validFrom: referenceTime,
      expiresAt: '2026-12-31T23:59:59.000Z',
      evidenceReferences: const [
        ReleaseEvidenceReference(
          evidenceId: 'ev-qg-001',
          evidenceType: ReleaseEvidenceType.qualityGate,
          artifactType: ReleaseEvidenceArtifactType.qualityGate,
          artifactId: 'qg-snapshot-001',
          artifactFingerprint: 'fp-qg-001',
          projectId: projectId,
          schemaVersion: 1,
          sourceReference: ReleaseEvidenceSourceReference(
            sourceType: ReleaseEvidenceType.qualityGate,
            resolutionMode: ReleaseEvidenceSourceResolutionMode.injected,
            requestedId: 'qg-snapshot-001',
            resolvedId: 'qg-snapshot-001',
            fingerprint: 'fp-qg-001',
            availability: ReleaseEvidenceAvailabilityStatus.available,
            compatibility: ReleaseEvidenceCompatibilityStatus.compatible,
          ),
          observedAt: referenceTime,
          status: ReleaseEvidenceReferenceStatus.available,
        ),
      ],
      fingerprint: 'fp-att-001',
      schemaVersion: 1,
    );
  }

  static ReleaseVerificationResult validVerificationResult({
    ReleaseVerificationStatus status = ReleaseVerificationStatus.verified,
  }) {
    return ReleaseVerificationResult(
      verificationId: 'ver-001',
      subject: validSubject(),
      policyReference: const ReleaseVerificationPolicyReference(
        policyId: ReleaseVerificationPolicyV1.policyId,
        policyVersion: 1,
        policyFingerprint: 'fp-verification-policy-v1',
      ),
      status: status,
      checks: const [
        ReleaseVerificationCheck(
          checkId: 'check-fingerprint',
          checkType: ReleaseVerificationCheckType.fingerprint,
          subjectId: 'subject-release-001',
          status: ReleaseVerificationCheckStatus.passed,
          expected: 'present',
          actual: 'present',
        ),
      ],
      compatibility: validCompatibility(),
      eligibility: validEligibility(),
      coverage: validCoverage(),
      verifiedEvidenceIds: const ['qg-snapshot-001', 'rg-snapshot-001'],
      verifiedAttestationIds: const ['att-001'],
      evaluatedAt: referenceTime,
      referenceTime: referenceTime,
      fingerprint: 'fp-ver-001',
      schemaVersion: 1,
    );
  }

  static ReleaseEvidenceResult validResult() {
    return ReleaseEvidenceResult(
      status: ReleaseEvidenceResultStatus.success,
      bundle: validBundle(),
      verificationResult: validVerificationResult(),
      policyReference: const ReleaseEvidencePolicyReference(
        policyId: policyId,
        policyVersion: 1,
        policyFingerprint: policyFingerprint,
      ),
    );
  }

  static ReleaseContext validContext() =>
      ReleaseGovernanceTestFixtures.validContext();

  static QualityGateSnapshot passingQualityGateSnapshot() =>
      ReleaseGovernanceTestFixtures.passingQualityGateSnapshot();

  static ReleaseAttestationSet validAttestationSet() {
    return ReleaseAttestationSet(
      subjectId: 'subject-release-001',
      fingerprint: 'fp-attestation-set-001',
      schemaVersion: 1,
      attestations: [validAttestation()],
    );
  }

  static ReleaseEvidenceRequest passingRequest({
    QualityGateSnapshot? qualityGateSnapshot,
    ReleaseDecisionSnapshot? releaseDecisionSnapshot,
    ReleaseAttestationSet? attestationSet,
    bool useLatest = false,
    bool publish = false,
  }) {
    return ReleaseEvidenceRequest(
      releaseContext: validContext(),
      evidencePolicyId: ReleaseEvidencePolicyV1.policyId,
      attestationPolicyId: ReleaseAttestationPolicyV1.policyId,
      verificationPolicyId: ReleaseVerificationPolicyV1.policyId,
      qualityGateSnapshot: qualityGateSnapshot ?? passingQualityGateSnapshot(),
      releaseDecisionSnapshot: releaseDecisionSnapshot,
      attestationSet: attestationSet ?? validAttestationSet(),
      provenance: [validProvenance()],
      referenceTime: referenceTime,
      useLatest: useLatest,
      publish: publish,
    );
  }
}
