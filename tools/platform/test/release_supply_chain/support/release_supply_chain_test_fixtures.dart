import 'package:masterpalm_platform/models/release_supply_chain/artifact_registry_models.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_snapshot.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_bundle.dart';
import 'package:masterpalm_platform/models/release_governance/release_context.dart';
import 'package:masterpalm_platform/models/release_governance/release_decision_snapshot.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_request.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_snapshot.dart';
import 'package:masterpalm_platform/release_supply_chain/policies/compliance_policy_v1.dart';
import 'package:masterpalm_platform/release_supply_chain/policies/distribution_policy_v1.dart';
import 'package:masterpalm_platform/release_supply_chain/policies/supply_chain_policy_v1.dart';

import '../../release_governance/support/release_governance_test_fixtures.dart';
import 'package:masterpalm_platform/models/release_supply_chain/compliance_models.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_distribution_models.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_provenance_models.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_provenance_record.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_enums.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_fingerprint.dart';
import 'package:masterpalm_platform/models/release_supply_chain/sbom_models.dart';
import 'package:masterpalm_platform/models/release_supply_chain/supply_chain_models.dart';

/// Shared fixtures for release supply chain domain tests.
class ReleaseSupplyChainTestFixtures {
  static const projectId = 'masterpalm-demo';
  static const releaseId = 'rel-2026-07-22-001';
  static const commitId = 'abc123def456';
  static const referenceTime = '2026-07-22T12:00:00.000Z';
  static const bundleId = 're-bundle-001';
  static const sha256PlaceholderA =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  static const sha256PlaceholderB =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  static const qgSnapshotId = 'qg-snap-001';
  static const rgSnapshotId = 'rg-snap-001';

  static ReleaseProvenanceSubject validProvenanceSubject() {
    return ReleaseProvenanceSubject(
      subjectId: 'prov-subject-001',
      subjectType: ReleaseProvenanceSubjectType.release,
      projectId: projectId,
      releaseId: releaseId,
      commitId: commitId,
    );
  }

  static ReleaseProvenanceIdentity validProvenanceIdentity() {
    return ReleaseProvenanceIdentity(
      identityId: 'prov-identity-001',
      subjectType: ReleaseProvenanceSubjectType.release,
      projectId: projectId,
      releaseId: releaseId,
      commitId: commitId,
      bundleId: bundleId,
    );
  }

  static ReleaseProvenanceArtifact validProvenanceArtifact({
    String id = 'art-qg-001',
    ReleaseProvenanceArtifactType type =
        ReleaseProvenanceArtifactType.qualityGateSnapshot,
    String fingerprint = 'fp-qg-001',
  }) {
    return ReleaseProvenanceArtifact(
      artifactId: id,
      artifactType: type,
      fingerprint: fingerprint,
      snapshotId: qgSnapshotId,
    );
  }

  static ReleaseProvenanceRelation validProvenanceRelation() {
    return const ReleaseProvenanceRelation(
      relationId: 'rel-001',
      relationType: ReleaseProvenanceRelationType.derivedFrom,
      fromArtifactId: 'art-qg-001',
      toArtifactId: 'art-rg-001',
    );
  }

  static ReleaseProvenanceRecord validProvenanceRecord() {
    final artifacts = [
      validProvenanceArtifact(),
      validProvenanceArtifact(
        id: 'art-rg-001',
        type: ReleaseProvenanceArtifactType.releaseDecisionSnapshot,
        fingerprint: 'fp-rg-001',
      ),
      validProvenanceArtifact(
        id: 'art-re-001',
        type: ReleaseProvenanceArtifactType.releaseEvidenceBundle,
        fingerprint: 'fp-re-001',
      ),
    ];
    final relations = [validProvenanceRelation()];
    final comparable = {
      'metadata': {
        'projectId': projectId,
        'releaseId': releaseId,
        'commitId': commitId,
        'releaseEvidenceBundleId': bundleId,
        'qualityGateSnapshotId': qgSnapshotId,
        'releaseDecisionSnapshotId': rgSnapshotId,
        'schemaVersion': ReleaseProvenanceMetadata.currentSchemaVersion,
        'canonicalizationVersion':
            ReleaseProvenanceMetadata.currentCanonicalizationVersion,
        'status': ReleaseProvenanceStatus.complete.wireName,
        'artifactCount': artifacts.length,
        'relationCount': relations.length,
      },
      'subject': validProvenanceSubject().toComparableJson(),
      'identity': validProvenanceIdentity().toComparableJson(),
    };
    final fingerprint =
        ReleaseSupplyChainFingerprint.fromComparableJson(comparable);

    return ReleaseProvenanceRecord(
      metadata: ReleaseProvenanceMetadata(
        provenanceRecordId: 'prov-record-001',
        projectId: projectId,
        releaseId: releaseId,
        commitId: commitId,
        releaseEvidenceBundleId: bundleId,
        qualityGateSnapshotId: qgSnapshotId,
        releaseDecisionSnapshotId: rgSnapshotId,
        schemaVersion: ReleaseProvenanceMetadata.currentSchemaVersion,
        canonicalizationVersion:
            ReleaseProvenanceMetadata.currentCanonicalizationVersion,
        createdAt: referenceTime,
        recordedAt: referenceTime,
        status: ReleaseProvenanceStatus.complete,
        fingerprint: fingerprint,
        artifactCount: artifacts.length,
        relationCount: relations.length,
      ),
      subject: validProvenanceSubject(),
      identity: validProvenanceIdentity(),
      fingerprintDescriptor: ReleaseProvenanceFingerprint(
        algorithm: ReleaseProvenanceFingerprint.defaultAlgorithm,
        value: fingerprint,
      ),
      artifacts: artifacts,
      relations: relations,
    );
  }

  static SupplyChainPolicy validSupplyChainPolicy() {
    return const SupplyChainPolicy(
      policyId: 'supply-chain-v1',
      policyVersion: 1,
      name: 'Default Supply Chain Policy',
      requiredStageTypes: [
        SupplyChainStageType.build,
        SupplyChainStageType.source,
        SupplyChainStageType.test,
      ],
      minimumEvidenceCount: 1,
    );
  }

  static SupplyChainRecord validSupplyChainRecord() {
    const actor = SupplyChainActor(
      actorId: 'actor-ci',
      actorType: SupplyChainActorType.pipeline,
      name: 'CI Pipeline',
    );
    const stage = SupplyChainStage(
      stageId: 'stage-build',
      stageType: SupplyChainStageType.build,
      name: 'Build',
      actorId: 'actor-ci',
      outputArtifactIds: ['art-build-001'],
    );
    const node = SupplyChainNode(
      nodeId: 'node-build',
      stageId: 'stage-build',
      artifactId: 'art-build-001',
      fingerprint: 'fp-build-001',
    );
    const evidence = SupplyChainEvidence(
      evidenceId: 'ev-qg',
      artifactId: 'art-qg-001',
      fingerprint: 'fp-qg-001',
      evidenceType: 'qualityGateSnapshot',
      snapshotId: qgSnapshotId,
    );
    final comparable = {
      'projectId': projectId,
      'releaseId': releaseId,
      'status': SupplyChainStatus.active.wireName,
      'policy': validSupplyChainPolicy().toComparableJson(),
      'schemaVersion': SupplyChainRecord.currentSchemaVersion,
    };
    final fingerprint =
        ReleaseSupplyChainFingerprint.fromComparableJson(comparable);

    return SupplyChainRecord(
      recordId: 'sc-record-001',
      projectId: projectId,
      releaseId: releaseId,
      commitId: commitId,
      releaseEvidenceBundleId: bundleId,
      status: SupplyChainStatus.active,
      fingerprint: fingerprint,
      policy: validSupplyChainPolicy(),
      actors: const [actor],
      stages: const [stage],
      nodes: const [node],
      edges: const [],
      evidence: const [evidence],
      schemaVersion: SupplyChainRecord.currentSchemaVersion,
      createdAt: referenceTime,
      recordedAt: referenceTime,
    );
  }

  static SoftwareBillOfMaterials validSbom() {
    const pkg = SbomPackage(
      packageId: 'pkg-app',
      name: 'masterpalm-app',
      version: '1.0.0',
      purl: 'pkg:apk/masterpalm-app@1.0.0',
    );
    const component = SbomComponent(
      componentId: 'comp-app',
      componentType: SbomComponentType.application,
      packageRef: pkg,
      hashes: [
        SbomHash(
          algorithm: ArtifactDigestAlgorithm.sha256,
          value: sha256PlaceholderA,
        ),
      ],
    );
    final comparable = {
      'metadata': {
        'projectId': projectId,
        'releaseId': releaseId,
        'status': SbomStatus.complete.wireName,
        'componentCount': 1,
        'dependencyCount': 0,
        'schemaVersion': SbomMetadata.currentSchemaVersion,
        'canonicalizationVersion': SbomMetadata.currentCanonicalizationVersion,
      },
      'components': [component.toComparableJson()],
      'dependencies': <Map<String, dynamic>>[],
    };
    final fingerprint =
        ReleaseSupplyChainFingerprint.fromComparableJson(comparable);

    return SoftwareBillOfMaterials(
      metadata: SbomMetadata(
        sbomId: 'sbom-001',
        projectId: projectId,
        releaseId: releaseId,
        commitId: commitId,
        schemaVersion: SbomMetadata.currentSchemaVersion,
        canonicalizationVersion: SbomMetadata.currentCanonicalizationVersion,
        createdAt: referenceTime,
        generatedAt: referenceTime,
        status: SbomStatus.complete,
        fingerprint: fingerprint,
        componentCount: 1,
        dependencyCount: 0,
      ),
      components: const [component],
      dependencies: const [],
    );
  }

  static ArtifactRecord validArtifactRecord() {
    const identifier = ArtifactIdentifier(
      artifactId: 'artifact-apk-001',
      name: 'masterpalm-app',
      version: '1.0.0',
    );
    const location = ArtifactLocation(
      locationId: 'loc-001',
      locationType: 'registry',
      uri: 'registry://artifacts/masterpalm-app/1.0.0',
    );
    const integrity = ArtifactIntegrity(
      digest: ArtifactDigest(
        algorithm: ArtifactDigestAlgorithm.sha256,
        value: sha256PlaceholderB,
      ),
      verified: true,
    );
    final comparable = {
      'metadata': {
        'projectId': projectId,
        'releaseId': releaseId,
        'status': ArtifactStatus.available.wireName,
        'schemaVersion': ArtifactMetadata.currentSchemaVersion,
      },
      'identifier': identifier.toComparableJson(),
      'location': location.toComparableJson(),
      'integrity': integrity.toComparableJson(),
    };
    final fingerprint =
        ReleaseSupplyChainFingerprint.fromComparableJson(comparable);

    return ArtifactRecord(
      metadata: ArtifactMetadata(
        recordId: 'artifact-record-001',
        projectId: projectId,
        releaseId: releaseId,
        commitId: commitId,
        schemaVersion: ArtifactMetadata.currentSchemaVersion,
        createdAt: referenceTime,
        registeredAt: referenceTime,
        status: ArtifactStatus.available,
        fingerprint: fingerprint,
        mediaType: 'application/vnd.android.package-archive',
        sizeBytes: 1024000,
      ),
      identifier: identifier,
      location: location,
      integrity: integrity,
      provenanceRecordId: 'prov-record-001',
    );
  }

  static ReleaseDistribution validReleaseDistribution() {
    const channel = ReleaseChannel(
      channelId: 'ch-prod',
      channelType: ReleaseChannelType.production,
      name: 'Production',
    );
    const policy = DistributionPolicy(
      policyId: 'distribution-v1',
      policyVersion: 1,
      name: 'Production Distribution',
      allowedChannelTypes: [ReleaseChannelType.production],
      requiredTargetCount: 1,
    );
    const target = DistributionTarget(
      targetId: 'target-registry',
      targetType: DistributionTargetType.registry,
      uri: 'registry://releases/masterpalm-app',
    );
    const manifest = DistributionManifest(
      manifestId: 'dist-manifest-001',
      artifactRecordIds: ['artifact-record-001'],
      fingerprint: 'fp-manifest-001',
    );
    final comparable = {
      'projectId': projectId,
      'releaseId': releaseId,
      'status': DistributionStatus.published.wireName,
      'channel': channel.toComparableJson(),
      'policy': policy.toComparableJson(),
      'targets': [target.toComparableJson()],
      'manifest': manifest.toComparableJson(),
      'schemaVersion': ReleaseDistribution.currentSchemaVersion,
    };
    final fingerprint =
        ReleaseSupplyChainFingerprint.fromComparableJson(comparable);

    return ReleaseDistribution(
      distributionId: 'dist-001',
      projectId: projectId,
      releaseId: releaseId,
      commitId: commitId,
      releaseEvidenceBundleId: bundleId,
      status: DistributionStatus.published,
      fingerprint: fingerprint,
      channel: channel,
      policy: policy,
      targets: const [target],
      manifest: manifest,
      schemaVersion: ReleaseDistribution.currentSchemaVersion,
      createdAt: referenceTime,
      distributedAt: referenceTime,
    );
  }

  static ComplianceResult validComplianceResult() {
    const rule = ComplianceRule(
      ruleId: 'COMP001',
      name: 'Evidence bundle required',
      severity: ComplianceRuleSeverity.high,
      expression: 'releaseEvidenceBundleId != null',
    );
    const policy = CompliancePolicy(
      policyId: 'compliance-v1',
      policyVersion: 1,
      name: 'Release Compliance',
      rules: [rule],
    );
    const evidence = ComplianceEvidence(
      evidenceId: 'ce-re-bundle',
      evidenceType: 'releaseEvidenceBundle',
      fingerprint: 'fp-re-001',
      snapshotId: bundleId,
    );
    const check = ComplianceCheck(
      checkId: 'check-001',
      ruleId: 'COMP001',
      status: ComplianceStatus.compliant,
      evidence: [evidence],
      evaluatedAt: referenceTime,
    );
    final comparable = {
      'projectId': projectId,
      'releaseId': releaseId,
      'status': ComplianceStatus.compliant.wireName,
      'policy': policy.toComparableJson(),
      'checks': [check.toComparableJson()],
      'violations': <Map<String, dynamic>>[],
      'schemaVersion': ComplianceResult.currentSchemaVersion,
    };
    final fingerprint =
        ReleaseSupplyChainFingerprint.fromComparableJson(comparable);

    return ComplianceResult(
      resultId: 'comp-result-001',
      projectId: projectId,
      releaseId: releaseId,
      commitId: commitId,
      releaseEvidenceBundleId: bundleId,
      status: ComplianceStatus.compliant,
      fingerprint: fingerprint,
      policy: policy,
      checks: const [check],
      violations: const [],
      schemaVersion: ComplianceResult.currentSchemaVersion,
      evaluatedAt: referenceTime,
    );
  }

  static ReleaseSupplyChainSnapshot validSupplyChainSnapshot() {
    return ReleaseSupplyChainSnapshot(
      metadata: ReleaseSupplyChainSnapshotMetadata(
        supplyChainSnapshotId: 'rsc-snap-001',
        projectId: projectId,
        releaseId: releaseId,
        commitId: commitId,
        releaseEvidenceBundleId: bundleId,
        supplyChainPolicyId: SupplyChainPolicyV1.policyId,
        supplyChainPolicyVersion: 1,
        distributionPolicyId: DistributionPolicyV1.policyId,
        distributionPolicyVersion: 1,
        compliancePolicyId: CompliancePolicyV1.policyId,
        compliancePolicyVersion: 1,
        schemaVersion: ReleaseSupplyChainSnapshotMetadata.currentSchemaVersion,
        canonicalizationVersion:
            ReleaseSupplyChainSnapshotMetadata.currentCanonicalizationVersion,
        createdAt: referenceTime,
        evaluatedAt: referenceTime,
        fingerprint: 'fp-snapshot-001',
      ),
      fingerprint: 'fp-snapshot-001',
      provenance: validProvenanceRecord(),
      supplyChain: validSupplyChainRecord(),
      sbom: validSbom(),
      artifacts: [validArtifactRecord()],
      distribution: validReleaseDistribution(),
      compliance: validComplianceResult(),
    );
  }

  static ReleaseContext validContext() =>
      ReleaseGovernanceTestFixtures.validContext();

  static QualityGateSnapshot passingQualityGateSnapshot() =>
      ReleaseGovernanceTestFixtures.passingQualityGateSnapshot();

  static ReleaseSupplyChainRequest passingRequest({
    QualityGateSnapshot? qualityGateSnapshot,
    ReleaseDecisionSnapshot? releaseDecisionSnapshot,
    ReleaseEvidenceBundle? releaseEvidenceBundle,
    bool useLatest = false,
    bool publish = false,
  }) {
    return ReleaseSupplyChainRequest(
      releaseContext: validContext(),
      supplyChainPolicyId: SupplyChainPolicyV1.policyId,
      distributionPolicyId: DistributionPolicyV1.policyId,
      compliancePolicyId: CompliancePolicyV1.policyId,
      qualityGateSnapshot: qualityGateSnapshot ?? passingQualityGateSnapshot(),
      releaseDecisionSnapshot: releaseDecisionSnapshot,
      releaseEvidenceBundle: releaseEvidenceBundle,
      referenceTime: referenceTime,
      useLatest: useLatest,
      publish: publish,
    );
  }
}
