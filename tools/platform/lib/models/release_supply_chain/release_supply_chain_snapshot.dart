import 'artifact_registry_models.dart';
import 'compliance_models.dart';
import 'release_distribution_models.dart';
import 'release_provenance_record.dart';
import 'release_supply_chain_equality.dart';
import 'sbom_models.dart';
import 'supply_chain_models.dart';

/// Metadata for a published release supply chain snapshot.
class ReleaseSupplyChainSnapshotMetadata {
  const ReleaseSupplyChainSnapshotMetadata({
    required this.supplyChainSnapshotId,
    required this.projectId,
    required this.schemaVersion,
    required this.canonicalizationVersion,
    required this.createdAt,
    required this.evaluatedAt,
    required this.fingerprint,
    required this.supplyChainPolicyId,
    required this.supplyChainPolicyVersion,
    required this.distributionPolicyId,
    required this.distributionPolicyVersion,
    required this.compliancePolicyId,
    required this.compliancePolicyVersion,
    this.releaseId,
    this.commitId,
    this.releaseEvidenceBundleId,
    this.provenanceFingerprint,
    this.graphFingerprint,
    this.sbomFingerprint,
    this.registryFingerprint,
    this.distributionFingerprint,
    this.complianceFingerprint,
    this.limitations = const [],
  });

  static const int currentSchemaVersion = 1;
  static const int currentCanonicalizationVersion = 1;

  final String supplyChainSnapshotId;
  final String projectId;
  final String? releaseId;
  final String? commitId;
  final String? releaseEvidenceBundleId;
  final String supplyChainPolicyId;
  final int supplyChainPolicyVersion;
  final String distributionPolicyId;
  final int distributionPolicyVersion;
  final String compliancePolicyId;
  final int compliancePolicyVersion;
  final int schemaVersion;
  final int canonicalizationVersion;
  final String createdAt;
  final String evaluatedAt;
  final String fingerprint;
  final String? provenanceFingerprint;
  final String? graphFingerprint;
  final String? sbomFingerprint;
  final String? registryFingerprint;
  final String? distributionFingerprint;
  final String? complianceFingerprint;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'supplyChainSnapshotId': supplyChainSnapshotId,
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        if (commitId != null) 'commitId': commitId,
        if (releaseEvidenceBundleId != null)
          'releaseEvidenceBundleId': releaseEvidenceBundleId,
        'supplyChainPolicyId': supplyChainPolicyId,
        'supplyChainPolicyVersion': supplyChainPolicyVersion,
        'distributionPolicyId': distributionPolicyId,
        'distributionPolicyVersion': distributionPolicyVersion,
        'compliancePolicyId': compliancePolicyId,
        'compliancePolicyVersion': compliancePolicyVersion,
        'schemaVersion': schemaVersion,
        'canonicalizationVersion': canonicalizationVersion,
        'createdAt': createdAt,
        'evaluatedAt': evaluatedAt,
        'fingerprint': fingerprint,
        if (provenanceFingerprint != null)
          'provenanceFingerprint': provenanceFingerprint,
        if (graphFingerprint != null) 'graphFingerprint': graphFingerprint,
        if (sbomFingerprint != null) 'sbomFingerprint': sbomFingerprint,
        if (registryFingerprint != null)
          'registryFingerprint': registryFingerprint,
        if (distributionFingerprint != null)
          'distributionFingerprint': distributionFingerprint,
        if (complianceFingerprint != null)
          'complianceFingerprint': complianceFingerprint,
        if (limitations.isNotEmpty) 'limitations': limitations,
      };

  factory ReleaseSupplyChainSnapshotMetadata.fromJson(
    Map<String, dynamic> json,
  ) {
    return ReleaseSupplyChainSnapshotMetadata(
      supplyChainSnapshotId: json['supplyChainSnapshotId'] as String,
      projectId: json['projectId'] as String,
      releaseId: json['releaseId'] as String?,
      commitId: json['commitId'] as String?,
      releaseEvidenceBundleId: json['releaseEvidenceBundleId'] as String?,
      supplyChainPolicyId: json['supplyChainPolicyId'] as String,
      supplyChainPolicyVersion: json['supplyChainPolicyVersion'] as int,
      distributionPolicyId: json['distributionPolicyId'] as String,
      distributionPolicyVersion: json['distributionPolicyVersion'] as int,
      compliancePolicyId: json['compliancePolicyId'] as String,
      compliancePolicyVersion: json['compliancePolicyVersion'] as int,
      schemaVersion: json['schemaVersion'] as int? ?? currentSchemaVersion,
      canonicalizationVersion: json['canonicalizationVersion'] as int? ??
          currentCanonicalizationVersion,
      createdAt: json['createdAt'] as String,
      evaluatedAt: json['evaluatedAt'] as String,
      fingerprint: json['fingerprint'] as String,
      provenanceFingerprint: json['provenanceFingerprint'] as String?,
      graphFingerprint: json['graphFingerprint'] as String?,
      sbomFingerprint: json['sbomFingerprint'] as String?,
      registryFingerprint: json['registryFingerprint'] as String?,
      distributionFingerprint: json['distributionFingerprint'] as String?,
      complianceFingerprint: json['complianceFingerprint'] as String?,
      limitations: List.unmodifiable(
        (json['limitations'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        if (commitId != null) 'commitId': commitId,
        if (releaseEvidenceBundleId != null)
          'releaseEvidenceBundleId': releaseEvidenceBundleId,
        'supplyChainPolicyId': supplyChainPolicyId,
        'supplyChainPolicyVersion': supplyChainPolicyVersion,
        'distributionPolicyId': distributionPolicyId,
        'distributionPolicyVersion': distributionPolicyVersion,
        'compliancePolicyId': compliancePolicyId,
        'compliancePolicyVersion': compliancePolicyVersion,
        'schemaVersion': schemaVersion,
        'canonicalizationVersion': canonicalizationVersion,
        if (provenanceFingerprint != null)
          'provenanceFingerprint': provenanceFingerprint,
        if (graphFingerprint != null) 'graphFingerprint': graphFingerprint,
        if (sbomFingerprint != null) 'sbomFingerprint': sbomFingerprint,
        if (registryFingerprint != null)
          'registryFingerprint': registryFingerprint,
        if (distributionFingerprint != null)
          'distributionFingerprint': distributionFingerprint,
        if (complianceFingerprint != null)
          'complianceFingerprint': complianceFingerprint,
        if (limitations.isNotEmpty)
          'limitations': List<String>.from(limitations)..sort(),
      };

  ReleaseSupplyChainSnapshotMetadata copyWith({
    String? supplyChainSnapshotId,
    String? projectId,
    String? releaseId,
    String? commitId,
    String? releaseEvidenceBundleId,
    String? supplyChainPolicyId,
    int? supplyChainPolicyVersion,
    String? distributionPolicyId,
    int? distributionPolicyVersion,
    String? compliancePolicyId,
    int? compliancePolicyVersion,
    int? schemaVersion,
    int? canonicalizationVersion,
    String? createdAt,
    String? evaluatedAt,
    String? fingerprint,
    String? provenanceFingerprint,
    String? graphFingerprint,
    String? sbomFingerprint,
    String? registryFingerprint,
    String? distributionFingerprint,
    String? complianceFingerprint,
    List<String>? limitations,
  }) {
    return ReleaseSupplyChainSnapshotMetadata(
      supplyChainSnapshotId:
          supplyChainSnapshotId ?? this.supplyChainSnapshotId,
      projectId: projectId ?? this.projectId,
      releaseId: releaseId ?? this.releaseId,
      commitId: commitId ?? this.commitId,
      releaseEvidenceBundleId:
          releaseEvidenceBundleId ?? this.releaseEvidenceBundleId,
      supplyChainPolicyId: supplyChainPolicyId ?? this.supplyChainPolicyId,
      supplyChainPolicyVersion:
          supplyChainPolicyVersion ?? this.supplyChainPolicyVersion,
      distributionPolicyId: distributionPolicyId ?? this.distributionPolicyId,
      distributionPolicyVersion:
          distributionPolicyVersion ?? this.distributionPolicyVersion,
      compliancePolicyId: compliancePolicyId ?? this.compliancePolicyId,
      compliancePolicyVersion:
          compliancePolicyVersion ?? this.compliancePolicyVersion,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      canonicalizationVersion:
          canonicalizationVersion ?? this.canonicalizationVersion,
      createdAt: createdAt ?? this.createdAt,
      evaluatedAt: evaluatedAt ?? this.evaluatedAt,
      fingerprint: fingerprint ?? this.fingerprint,
      provenanceFingerprint:
          provenanceFingerprint ?? this.provenanceFingerprint,
      graphFingerprint: graphFingerprint ?? this.graphFingerprint,
      sbomFingerprint: sbomFingerprint ?? this.sbomFingerprint,
      registryFingerprint: registryFingerprint ?? this.registryFingerprint,
      distributionFingerprint:
          distributionFingerprint ?? this.distributionFingerprint,
      complianceFingerprint:
          complianceFingerprint ?? this.complianceFingerprint,
      limitations: limitations ?? this.limitations,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseSupplyChainSnapshotMetadata &&
          supplyChainSnapshotId == other.supplyChainSnapshotId &&
          projectId == other.projectId &&
          releaseId == other.releaseId &&
          commitId == other.commitId &&
          releaseEvidenceBundleId == other.releaseEvidenceBundleId &&
          supplyChainPolicyId == other.supplyChainPolicyId &&
          supplyChainPolicyVersion == other.supplyChainPolicyVersion &&
          distributionPolicyId == other.distributionPolicyId &&
          distributionPolicyVersion == other.distributionPolicyVersion &&
          compliancePolicyId == other.compliancePolicyId &&
          compliancePolicyVersion == other.compliancePolicyVersion &&
          schemaVersion == other.schemaVersion &&
          canonicalizationVersion == other.canonicalizationVersion &&
          createdAt == other.createdAt &&
          evaluatedAt == other.evaluatedAt &&
          fingerprint == other.fingerprint &&
          provenanceFingerprint == other.provenanceFingerprint &&
          graphFingerprint == other.graphFingerprint &&
          sbomFingerprint == other.sbomFingerprint &&
          registryFingerprint == other.registryFingerprint &&
          distributionFingerprint == other.distributionFingerprint &&
          complianceFingerprint == other.complianceFingerprint &&
          rscListEquals(limitations, other.limitations);

  @override
  int get hashCode => Object.hash(
        Object.hash(
          supplyChainSnapshotId,
          projectId,
          releaseId,
          commitId,
          releaseEvidenceBundleId,
          supplyChainPolicyId,
          supplyChainPolicyVersion,
          distributionPolicyId,
          distributionPolicyVersion,
          compliancePolicyId,
          compliancePolicyVersion,
          schemaVersion,
          canonicalizationVersion,
          createdAt,
          evaluatedAt,
          fingerprint,
          provenanceFingerprint,
          graphFingerprint,
        ),
        sbomFingerprint,
        registryFingerprint,
        distributionFingerprint,
        complianceFingerprint,
        Object.hashAll(limitations),
      );
}

/// Published aggregate snapshot for release supply chain and provenance.
class ReleaseSupplyChainSnapshot {
  const ReleaseSupplyChainSnapshot({
    required this.metadata,
    required this.fingerprint,
    this.provenance,
    this.supplyChain,
    this.sbom,
    this.artifacts = const [],
    this.distribution,
    this.compliance,
    this.warnings = const [],
    this.limitations = const [],
  });

  final ReleaseSupplyChainSnapshotMetadata metadata;
  final String fingerprint;
  final ReleaseProvenanceRecord? provenance;
  final SupplyChainRecord? supplyChain;
  final SoftwareBillOfMaterials? sbom;
  final List<ArtifactRecord> artifacts;
  final ReleaseDistribution? distribution;
  final ComplianceResult? compliance;
  final List<String> warnings;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'metadata': metadata.toJson(),
        'fingerprint': fingerprint,
        if (provenance != null) 'provenance': provenance!.toJson(),
        if (supplyChain != null) 'supplyChain': supplyChain!.toJson(),
        if (sbom != null) 'sbom': sbom!.toJson(),
        if (artifacts.isNotEmpty)
          'artifacts': artifacts.map((e) => e.toJson()).toList(),
        if (distribution != null) 'distribution': distribution!.toJson(),
        if (compliance != null) 'compliance': compliance!.toJson(),
        if (warnings.isNotEmpty) 'warnings': warnings,
        if (limitations.isNotEmpty) 'limitations': limitations,
      };

  factory ReleaseSupplyChainSnapshot.fromJson(Map<String, dynamic> json) {
    return ReleaseSupplyChainSnapshot(
      metadata: ReleaseSupplyChainSnapshotMetadata.fromJson(
        json['metadata'] as Map<String, dynamic>,
      ),
      fingerprint: json['fingerprint'] as String,
      provenance: json['provenance'] == null
          ? null
          : ReleaseProvenanceRecord.fromJson(
              json['provenance'] as Map<String, dynamic>,
            ),
      supplyChain: json['supplyChain'] == null
          ? null
          : SupplyChainRecord.fromJson(
              json['supplyChain'] as Map<String, dynamic>,
            ),
      sbom: json['sbom'] == null
          ? null
          : SoftwareBillOfMaterials.fromJson(
              json['sbom'] as Map<String, dynamic>,
            ),
      artifacts: List.unmodifiable(
        (json['artifacts'] as List<dynamic>? ?? [])
            .map((e) => ArtifactRecord.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      distribution: json['distribution'] == null
          ? null
          : ReleaseDistribution.fromJson(
              json['distribution'] as Map<String, dynamic>,
            ),
      compliance: json['compliance'] == null
          ? null
          : ComplianceResult.fromJson(
              json['compliance'] as Map<String, dynamic>,
            ),
      warnings: List.unmodifiable(
        (json['warnings'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
      limitations: List.unmodifiable(
        (json['limitations'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'metadata': metadata.toComparableJson(),
        if (provenance != null) 'provenance': provenance!.toComparableJson(),
        if (supplyChain != null) 'supplyChain': supplyChain!.toComparableJson(),
        if (sbom != null) 'sbom': sbom!.toComparableJson(),
        if (artifacts.isNotEmpty)
          'artifacts': (artifacts.map((e) => e.toComparableJson()).toList()
            ..sort(
              (a, b) => (a['metadata'] as Map)['recordId']
                  .toString()
                  .compareTo((b['metadata'] as Map)['recordId'].toString()),
            )),
        if (distribution != null)
          'distribution': distribution!.toComparableJson(),
        if (compliance != null) 'compliance': compliance!.toComparableJson(),
        if (warnings.isNotEmpty)
          'warnings': List<String>.from(warnings)..sort(),
        if (limitations.isNotEmpty)
          'limitations': List<String>.from(limitations)..sort(),
      };

  ReleaseSupplyChainSnapshot copyWith({
    ReleaseSupplyChainSnapshotMetadata? metadata,
    String? fingerprint,
    ReleaseProvenanceRecord? provenance,
    SupplyChainRecord? supplyChain,
    SoftwareBillOfMaterials? sbom,
    List<ArtifactRecord>? artifacts,
    ReleaseDistribution? distribution,
    ComplianceResult? compliance,
    List<String>? warnings,
    List<String>? limitations,
  }) {
    return ReleaseSupplyChainSnapshot(
      metadata: metadata ?? this.metadata,
      fingerprint: fingerprint ?? this.fingerprint,
      provenance: provenance ?? this.provenance,
      supplyChain: supplyChain ?? this.supplyChain,
      sbom: sbom ?? this.sbom,
      artifacts: artifacts ?? this.artifacts,
      distribution: distribution ?? this.distribution,
      compliance: compliance ?? this.compliance,
      warnings: warnings ?? this.warnings,
      limitations: limitations ?? this.limitations,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseSupplyChainSnapshot &&
          metadata == other.metadata &&
          fingerprint == other.fingerprint &&
          provenance == other.provenance &&
          supplyChain == other.supplyChain &&
          sbom == other.sbom &&
          rscListEquals(artifacts, other.artifacts) &&
          distribution == other.distribution &&
          compliance == other.compliance &&
          rscListEquals(warnings, other.warnings) &&
          rscListEquals(limitations, other.limitations);

  @override
  int get hashCode => Object.hash(
        metadata,
        fingerprint,
        provenance,
        supplyChain,
        sbom,
        Object.hashAll(artifacts),
        distribution,
        compliance,
        Object.hashAll(warnings),
        Object.hashAll(limitations),
      );
}
