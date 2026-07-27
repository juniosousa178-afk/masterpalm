import 'package:masterpalm_platform/models/quality_gate/quality_gate_enums.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_governance.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_messages.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_snapshot.dart';
import 'package:masterpalm_platform/models/release_governance/release_approval.dart';
import 'package:masterpalm_platform/models/release_governance/release_context.dart';
import 'package:masterpalm_platform/models/release_governance/release_governance_enums.dart';
import 'package:masterpalm_platform/models/release_governance/release_governance_evidence.dart';
import 'package:masterpalm_platform/models/release_governance/release_governance_request.dart';
import 'package:masterpalm_platform/models/release_governance/release_waiver.dart';
import 'package:masterpalm_platform/quality_gate/policies/quality_gate_release_policy_v1.dart';
import 'package:masterpalm_platform/release_governance/policies/release_governance_policy_v1.dart';

class ReleaseGovernanceTestFixtures {
  static const referenceTime = '2026-06-15T12:00:00.000Z';
  static const projectId = 'masterpalm-demo';
  static const releaseId = 'rel-2026-06-15-001';
  static const commitId = 'abc123def456';
  static const policyId = 'release-governance-v1';

  static ReleaseContext validContext({
    ReleaseEnvironment environment = ReleaseEnvironment.production,
    ReleaseType releaseType = ReleaseType.production,
  }) {
    return ReleaseContext(
      projectId: projectId,
      releaseId: releaseId,
      releaseName: 'Release 4.0 Beta',
      releaseVersion: '4.0.0-beta.1',
      commitId: commitId,
      branch: 'release/4.0-beta',
      environment: environment,
      releaseType: releaseType,
      requestedAt: '2026-06-15T10:00:00.000Z',
      requestedBy: 'release-bot',
      targetDate: '2026-06-20T00:00:00.000Z',
      artifactReferences: const [
        ReleaseArtifactReference(
          artifactId: 'artifact-apk-001',
          artifactType: 'apk',
          fingerprint: 'fp-artifact-001',
        ),
      ],
    );
  }

  static ReleaseApprovalAuthority activeAuthority({
    String authorityId = 'eng-prod',
    ReleaseApprovalType type = ReleaseApprovalType.engineering,
    String separationOfDutiesGroup = 'engineering',
  }) {
    return ReleaseApprovalAuthority(
      authorityId: authorityId,
      authorityType: 'role',
      role: type.wireName,
      organization: 'MasterPalm',
      allowedApprovalTypes: [type],
      allowedEnvironments: [ReleaseEnvironment.production],
      allowedReleaseTypes: [ReleaseType.production],
      separationOfDutiesGroup: separationOfDutiesGroup,
      validFrom: '2026-01-01T00:00:00.000Z',
      status: ReleaseAuthorityStatus.active,
      schemaVersion: 1,
    );
  }

  static ReleaseApproval validApproval({
    String approvalId = 'approval-eng-001',
    ReleaseApprovalType type = ReleaseApprovalType.engineering,
    ReleaseApprovalStatus status = ReleaseApprovalStatus.approved,
    String? expiresAt = '2026-12-31T23:59:59.000Z',
    String authorityId = 'eng-prod',
    String approverId = 'user-eng-001',
    String? separationOfDutiesGroup,
  }) {
    final sodGroup = separationOfDutiesGroup ??
        switch (type) {
          ReleaseApprovalType.quality => 'quality',
          ReleaseApprovalType.releaseManager => 'release-management',
          _ => 'engineering',
        };
    return ReleaseApproval(
      approvalId: approvalId,
      releaseId: releaseId,
      policyId: policyId,
      policyVersion: 1,
      approvalType: type,
      authority: activeAuthority(
        authorityId: authorityId,
        type: type,
        separationOfDutiesGroup: sodGroup,
      ),
      approverId: approverId,
      status: status,
      decision: ReleaseGovernanceDecision.approved,
      scope: ReleaseApprovalScope(
        projectId: projectId,
        releaseId: releaseId,
        commitId: commitId,
        environment: ReleaseEnvironment.production,
        releaseType: ReleaseType.production,
        policyId: policyId,
        policyVersion: 1,
      ),
      issuedAt: '2026-06-15T11:00:00.000Z',
      validFrom: '2026-06-15T11:00:00.000Z',
      expiresAt: expiresAt,
      evidence: [minimalEvidence('ev-approval-001')],
      reason: 'Engineering sign-off',
      fingerprint: 'fp-approval-001',
      schemaVersion: 1,
    );
  }

  static ReleaseGovernanceEvidence minimalEvidence(String id) {
    return ReleaseGovernanceEvidence(
      evidenceId: id,
      evidenceType: ReleaseGovernanceEvidenceType.approval,
      sourceArtifactId: 'artifact-$id',
      sourceFingerprint: 'fp-$id',
      sourceType: 'approval',
      status: 'present',
      observedAt: referenceTime,
      reference: ReleaseGovernanceSourceReference(
        sourceType: ReleaseGovernanceSourceType.approval,
        resolutionMode: ReleaseGovernanceSourceResolutionMode.injected,
        requestedId: id,
        resolvedId: id,
      ),
      fingerprint: 'fp-evidence-$id',
    );
  }

  static ReleaseWaiverAuthority activeWaiverAuthority() {
    return ReleaseWaiverAuthority(
      authorityId: 'waiver-prod-rm',
      role: 'release-manager',
      allowedSeverities: [
        ReleaseGovernanceRuleSeverity.warning,
        ReleaseGovernanceRuleSeverity.blocking,
      ],
      allowedRuleIds: ['RG007', 'RG008'],
      allowedEnvironments: [ReleaseEnvironment.production],
      allowedReleaseTypes: [ReleaseType.production],
      maximumWaiverDuration: 'P1D',
      emergencyOnly: false,
      separationOfDutiesGroup: 'waiver',
      status: ReleaseAuthorityStatus.active,
      validFrom: '2026-01-01T00:00:00.000Z',
    );
  }

  static ReleaseWaiver validWaiver({
    String waiverId = 'waiver-001',
    ReleaseWaiverStatus status = ReleaseWaiverStatus.active,
  }) {
    return ReleaseWaiver(
      waiverId: waiverId,
      releaseId: releaseId,
      policyId: policyId,
      policyVersion: 1,
      status: status,
      scope: ReleaseWaiverScope(
        projectId: projectId,
        releaseId: releaseId,
        commitId: commitId,
        environment: ReleaseEnvironment.production,
        releaseType: ReleaseType.production,
        policyId: policyId,
        policyVersion: 1,
        ruleIds: ['RG007'],
      ),
      authority: activeWaiverAuthority(),
      issuerId: 'user-rm-001',
      issuedAt: '2026-06-15T11:30:00.000Z',
      expiration: const ReleaseWaiverExpiration(
        validFrom: '2026-06-15T11:30:00.000Z',
        expiresAt: '2026-06-16T11:30:00.000Z',
        maximumDuration: 'P1D',
        expirationMode: ReleaseWaiverExpirationMode.singleUse,
      ),
      justification: 'Temporary coverage gap with compensating monitoring',
      compensatingControls: const [
        ReleaseCompensatingControl(
          controlId: 'cc-001',
          name: 'Enhanced monitoring',
          description: '24h enhanced monitoring',
          owner: 'ops-team',
          status: ReleaseCompensatingControlStatus.active,
          evidenceReferences: ['ev-cc-001'],
          validFrom: '2026-06-15T11:30:00.000Z',
        ),
      ],
      evidence: [minimalEvidence('ev-waiver-001')],
      affectedRuleIds: ['RG007'],
      fingerprint: 'fp-waiver-001',
      schemaVersion: 1,
    );
  }

  static QualityGateSnapshot passingQualityGateSnapshot({
    String id = 'qg-rg-test-1',
    String fingerprint = 'fp-qg-rg-test-1',
  }) {
    return QualityGateSnapshot(
      metadata: QualityGateSnapshotMetadata(
        qualityGateSnapshotId: id,
        qualityGateFingerprint: fingerprint,
        requestFingerprint: 'req-qg-rg-1',
        policyFingerprint: 'pol-qg-rg-1',
        projectId: projectId,
        commitId: commitId,
        branch: 'release/4.0-beta',
        schemaVersion: 1,
        calculationVersion: 1,
        canonicalizationVersion: 1,
        createdAt: '2026-06-15T10:00:00.000Z',
        evaluatedAt: referenceTime,
        decision: QualityGateDecision.passed,
        policyId: QualityGateReleasePolicyV1.policyId,
        policyVersion: 1,
        totalRuleCount: 10,
        evaluatedRuleCount: 10,
        failedRuleCount: 0,
        blockingFailureCount: 0,
        warningCount: 0,
        errorCount: 0,
        sourceCount: 4,
      ),
      policyReference: const QualityGatePolicyVersion(
        policyId: QualityGateReleasePolicyV1.policyId,
        policyVersion: 1,
        schemaVersion: 1,
        calculationVersion: 1,
        canonicalizationVersion: 1,
      ),
      decision: QualityGateDecision.passed,
      eligibility: const QualityGateEligibility(
        status: QualityGateEligibilityStatus.eligible,
        reasons: [],
        requiredSources: [QualityGateSourceType.metrics],
        availableSources: [QualityGateSourceType.metrics],
        missingSources: [],
        incompatibleSources: [],
        eligibilityFingerprint: 'elig-qg-rg-1',
      ),
      compatibility: const QualityGateCompatibility(
        status: QualityGateCompatibilityStatus.compatible,
        checks: [],
        compatibleSources: [QualityGateSourceType.metrics],
        partiallyCompatibleSources: [],
        incompatibleSources: [],
        unknownSources: [],
        reasons: [],
        compatibilityFingerprint: 'compat-qg-rg-1',
      ),
      coverage: const QualityGateCoverage(
        totalRuleCount: 10,
        enabledRuleCount: 10,
        evaluatedRuleCount: 10,
        passedRuleCount: 10,
        failedRuleCount: 0,
        unavailableRuleCount: 0,
        incompatibleRuleCount: 0,
        skippedRuleCount: 0,
        notApplicableRuleCount: 0,
        requiredRuleCount: 10,
        evaluatedRequiredRuleCount: 10,
        requiredRuleCoveragePercentage: 100,
        overallRuleCoveragePercentage: 100,
        evidenceCoveragePercentage: 100,
        sourceCoveragePercentage: 100,
        ruleSetCoverage: {},
        missingRuleIds: [],
        missingSourceTypes: [],
        limitations: [],
      ),
      evaluations: const [],
      ruleSetEvaluations: const [],
      evidence: const [],
      sourceReferences: const [],
      explanations: const [],
      warnings: const [],
      errors: const [],
      limitations: const [],
    );
  }

  static ReleaseApprovalSet productionApprovalSet() {
    return ReleaseApprovalSet(
      releaseId: releaseId,
      fingerprint: 'fp-approval-set-001',
      schemaVersion: 1,
      approvals: [
        validApproval(
          approvalId: 'approval-eng-prod',
          type: ReleaseApprovalType.engineering,
        ),
        validApproval(
          approvalId: 'approval-quality-prod',
          type: ReleaseApprovalType.quality,
          authorityId: 'quality-prod',
          approverId: 'user-quality-001',
        ),
        validApproval(
          approvalId: 'approval-rm-prod',
          type: ReleaseApprovalType.releaseManager,
          authorityId: 'rm-prod',
          approverId: 'user-rm-001',
        ),
      ],
    );
  }

  static ReleaseGovernanceRequest passingRequest({
    bool useLatest = false,
    bool publish = false,
  }) {
    return ReleaseGovernanceRequest(
      releaseContext: validContext(),
      policyId: policyId,
      qualityGateSnapshot: passingQualityGateSnapshot(),
      approvalSet: productionApprovalSet(),
      referenceTime: referenceTime,
      useLatest: useLatest,
      publish: publish,
    );
  }
}
