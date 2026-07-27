import '../models/release_supply_chain/artifact_registry_models.dart';
import '../models/release_supply_chain/compliance_models.dart';
import '../models/release_supply_chain/release_distribution_models.dart';
import '../models/release_supply_chain/release_provenance_record.dart';
import '../models/release_supply_chain/release_supply_chain_enums.dart';
import '../models/release_supply_chain/release_supply_chain_fingerprint.dart';
import '../models/release_supply_chain/sbom_models.dart';
import '../models/release_supply_chain/supply_chain_models.dart';
import 'release_supply_chain_collector.dart';
import 'resolved_release_supply_chain_sources.dart';

/// Structural and consistency compliance evaluation — never approves release.
class ComplianceEngine {
  const ComplianceEngine();

  ComplianceResult evaluate({
    required ReleaseSupplyChainEvaluationContext context,
    required ReleaseSupplyChainCollectedArtifacts collected,
    ReleaseProvenanceRecord? provenance,
    SupplyChainRecord? supplyChain,
    SoftwareBillOfMaterials? sbom,
    List<ArtifactRecord> artifacts = const [],
    ReleaseDistribution? distribution,
    required String evaluatedAt,
  }) {
    final releaseContext = context.request.releaseContext;
    final policy = context.compliancePolicy.policy;
    final bundle = collected.releaseEvidenceBundle;

    final checks = <ComplianceCheck>[];
    final violations = <ComplianceViolation>[];

    for (final rule in policy.rules) {
      final passed = _evaluateRule(
        rule: rule,
        releaseContext: releaseContext,
        bundleId: bundle?.metadata.bundleId,
        provenance: provenance,
        supplyChain: supplyChain,
        sbom: sbom,
        artifacts: artifacts,
        distribution: distribution,
      );

      final evidence = <ComplianceEvidence>[];
      if (bundle != null) {
        evidence.add(
          ComplianceEvidence(
            evidenceId: 'ce-re-bundle',
            evidenceType: 'releaseEvidenceBundle',
            fingerprint: bundle.fingerprint,
            snapshotId: bundle.metadata.bundleId,
          ),
        );
      }
      if (provenance != null) {
        evidence.add(
          ComplianceEvidence(
            evidenceId: 'ce-prov',
            evidenceType: 'provenance',
            fingerprint: provenance.metadata.fingerprint,
            snapshotId: provenance.metadata.provenanceRecordId,
          ),
        );
      }

      checks.add(
        ComplianceCheck(
          checkId: 'check-${rule.ruleId}',
          ruleId: rule.ruleId,
          status: passed
              ? ComplianceStatus.compliant
              : ComplianceStatus.nonCompliant,
          evidence: evidence,
          evaluatedAt: evaluatedAt,
          message:
              passed ? 'Structural check passed' : 'Structural check failed',
        ),
      );

      if (!passed) {
        violations.add(
          ComplianceViolation(
            violationId: 'violation-${rule.ruleId}',
            ruleId: rule.ruleId,
            severity: rule.severity,
            message: 'Rule ${rule.ruleId} failed: ${rule.name}',
          ),
        );
      }
    }

    final status = violations.isEmpty
        ? ComplianceStatus.compliant
        : ComplianceStatus.nonCompliant;

    final comparable = {
      'projectId': releaseContext.projectId,
      'releaseId': releaseContext.releaseId,
      'status': status.wireName,
      'policy': policy.toComparableJson(),
      'checks': checks.map((e) => e.toComparableJson()).toList(),
      'violations': violations.map((e) => e.toComparableJson()).toList(),
      'schemaVersion': ComplianceResult.currentSchemaVersion,
    };
    final fingerprint =
        ReleaseSupplyChainFingerprint.fromComparableJson(comparable);

    return ComplianceResult(
      resultId: 'comp-result-${releaseContext.releaseId}',
      projectId: releaseContext.projectId,
      releaseId: releaseContext.releaseId,
      commitId: releaseContext.commitId,
      releaseEvidenceBundleId: bundle?.metadata.bundleId,
      status: status,
      fingerprint: fingerprint,
      policy: policy,
      checks: checks,
      violations: violations,
      schemaVersion: ComplianceResult.currentSchemaVersion,
      evaluatedAt: evaluatedAt,
    );
  }

  bool _evaluateRule({
    required ComplianceRule rule,
    required dynamic releaseContext,
    String? bundleId,
    ReleaseProvenanceRecord? provenance,
    SupplyChainRecord? supplyChain,
    SoftwareBillOfMaterials? sbom,
    List<ArtifactRecord> artifacts = const [],
    ReleaseDistribution? distribution,
  }) {
    switch (rule.ruleId) {
      case 'COMP001':
        return bundleId != null;
      case 'COMP002':
        return releaseContext.projectId.isNotEmpty;
      case 'COMP003':
        return provenance?.metadata.fingerprint.isNotEmpty ?? false;
      default:
        return true;
    }
  }
}
