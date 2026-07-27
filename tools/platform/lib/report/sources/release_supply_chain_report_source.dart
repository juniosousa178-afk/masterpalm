import '../../models/release_supply_chain/release_supply_chain_enums.dart';
import '../../models/release_supply_chain/release_supply_chain_snapshot.dart';
import '../report_input.dart';

/// Converts [ReleaseSupplyChainSnapshot] into report input data.
///
/// Consumes an existing snapshot only — never executes release supply chain engines.
class ReleaseSupplyChainReportSource {
  const ReleaseSupplyChainReportSource();

  ReleaseSupplyChainReportInputData fromSnapshot(
    ReleaseSupplyChainSnapshot snapshot,
  ) {
    final meta = snapshot.metadata;
    final artifactSummaries = snapshot.artifacts
        .map(
          (a) =>
              '${a.metadata.recordId}:${a.identifier.artifactId}@${a.identifier.version}',
        )
        .toList();
    final complianceCheckSummaries = snapshot.compliance?.checks
            .map((c) => '${c.checkId}:${c.ruleId}:${c.status.wireName}')
            .toList() ??
        const [];
    final complianceViolationSummaries = snapshot.compliance?.violations
            .map((v) => '${v.violationId}:${v.ruleId}:${v.severity.wireName}')
            .toList() ??
        const [];

    return ReleaseSupplyChainReportInputData(
      snapshotId: meta.supplyChainSnapshotId,
      fingerprint: snapshot.fingerprint,
      projectId: meta.projectId,
      releaseId: meta.releaseId ?? '',
      commitId: meta.commitId ?? '',
      releaseEvidenceBundleId: meta.releaseEvidenceBundleId ?? '',
      supplyChainPolicyId: meta.supplyChainPolicyId,
      supplyChainPolicyVersion: meta.supplyChainPolicyVersion,
      distributionPolicyId: meta.distributionPolicyId,
      distributionPolicyVersion: meta.distributionPolicyVersion,
      compliancePolicyId: meta.compliancePolicyId,
      compliancePolicyVersion: meta.compliancePolicyVersion,
      supplyChainStatus: snapshot.supplyChain?.status.wireName ?? 'unavailable',
      sbomStatus: snapshot.sbom?.metadata.status.wireName ?? 'unavailable',
      sbomComponentCount: snapshot.sbom?.metadata.componentCount ?? 0,
      sbomDependencyCount: snapshot.sbom?.metadata.dependencyCount ?? 0,
      complianceStatus: snapshot.compliance?.status.wireName ?? 'unavailable',
      complianceCheckCount: snapshot.compliance?.checks.length ?? 0,
      complianceViolationCount: snapshot.compliance?.violations.length ?? 0,
      artifactCount: snapshot.artifacts.length,
      artifactSummaries: artifactSummaries,
      complianceCheckSummaries: complianceCheckSummaries,
      complianceViolationSummaries: complianceViolationSummaries,
      limitations: [
        ...meta.limitations,
        ...snapshot.limitations,
      ],
      warnings: snapshot.warnings,
    );
  }

  ReleaseSupplyChainReportInputData fromMap(Map<String, dynamic> json) {
    return fromSnapshot(ReleaseSupplyChainSnapshot.fromJson(json));
  }
}
