import '../quality_gate/quality_gate_snapshot.dart';
import '../release_evidence/release_evidence_bundle.dart';
import '../release_governance/release_context.dart';
import '../release_governance/release_decision_snapshot.dart';

/// Request to collect and compose a release supply chain snapshot.
class ReleaseSupplyChainRequest {
  const ReleaseSupplyChainRequest({
    required this.releaseContext,
    required this.referenceTime,
    this.releaseContextId,
    this.releaseEvidenceBundle,
    this.releaseEvidenceBundleId,
    this.qualityGateSnapshot,
    this.qualityGateSnapshotId,
    this.releaseDecisionSnapshot,
    this.releaseDecisionSnapshotId,
    this.supplyChainPolicyId,
    this.supplyChainPolicyVersion,
    this.distributionPolicyId,
    this.distributionPolicyVersion,
    this.compliancePolicyId,
    this.compliancePolicyVersion,
    this.useLatest = false,
    this.publish = false,
    this.metadata = const {},
  });

  final ReleaseContext releaseContext;
  final String? releaseContextId;
  final ReleaseEvidenceBundle? releaseEvidenceBundle;
  final String? releaseEvidenceBundleId;
  final QualityGateSnapshot? qualityGateSnapshot;
  final String? qualityGateSnapshotId;
  final ReleaseDecisionSnapshot? releaseDecisionSnapshot;
  final String? releaseDecisionSnapshotId;
  final String? supplyChainPolicyId;
  final int? supplyChainPolicyVersion;
  final String? distributionPolicyId;
  final int? distributionPolicyVersion;
  final String? compliancePolicyId;
  final int? compliancePolicyVersion;
  final bool useLatest;
  final String referenceTime;
  final bool publish;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'releaseContext': releaseContext.toJson(),
        if (releaseContextId != null) 'releaseContextId': releaseContextId,
        if (releaseEvidenceBundle != null)
          'releaseEvidenceBundle': releaseEvidenceBundle!.toJson(),
        if (releaseEvidenceBundleId != null)
          'releaseEvidenceBundleId': releaseEvidenceBundleId,
        if (qualityGateSnapshot != null)
          'qualityGateSnapshot': qualityGateSnapshot!.toJson(),
        if (qualityGateSnapshotId != null)
          'qualityGateSnapshotId': qualityGateSnapshotId,
        if (releaseDecisionSnapshot != null)
          'releaseDecisionSnapshot': releaseDecisionSnapshot!.toJson(),
        if (releaseDecisionSnapshotId != null)
          'releaseDecisionSnapshotId': releaseDecisionSnapshotId,
        if (supplyChainPolicyId != null)
          'supplyChainPolicyId': supplyChainPolicyId,
        if (supplyChainPolicyVersion != null)
          'supplyChainPolicyVersion': supplyChainPolicyVersion,
        if (distributionPolicyId != null)
          'distributionPolicyId': distributionPolicyId,
        if (distributionPolicyVersion != null)
          'distributionPolicyVersion': distributionPolicyVersion,
        if (compliancePolicyId != null)
          'compliancePolicyId': compliancePolicyId,
        if (compliancePolicyVersion != null)
          'compliancePolicyVersion': compliancePolicyVersion,
        'useLatest': useLatest,
        'referenceTime': referenceTime,
        'publish': publish,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory ReleaseSupplyChainRequest.fromJson(Map<String, dynamic> json) {
    return ReleaseSupplyChainRequest(
      releaseContext: ReleaseContext.fromJson(
        json['releaseContext'] as Map<String, dynamic>,
      ),
      releaseContextId: json['releaseContextId'] as String?,
      releaseEvidenceBundle: json['releaseEvidenceBundle'] == null
          ? null
          : ReleaseEvidenceBundle.fromJson(
              json['releaseEvidenceBundle'] as Map<String, dynamic>,
            ),
      releaseEvidenceBundleId: json['releaseEvidenceBundleId'] as String?,
      qualityGateSnapshot: json['qualityGateSnapshot'] == null
          ? null
          : QualityGateSnapshot.fromJson(
              json['qualityGateSnapshot'] as Map<String, dynamic>,
            ),
      qualityGateSnapshotId: json['qualityGateSnapshotId'] as String?,
      releaseDecisionSnapshot: json['releaseDecisionSnapshot'] == null
          ? null
          : ReleaseDecisionSnapshot.fromJson(
              json['releaseDecisionSnapshot'] as Map<String, dynamic>,
            ),
      releaseDecisionSnapshotId: json['releaseDecisionSnapshotId'] as String?,
      supplyChainPolicyId: json['supplyChainPolicyId'] as String?,
      supplyChainPolicyVersion: json['supplyChainPolicyVersion'] as int?,
      distributionPolicyId: json['distributionPolicyId'] as String?,
      distributionPolicyVersion: json['distributionPolicyVersion'] as int?,
      compliancePolicyId: json['compliancePolicyId'] as String?,
      compliancePolicyVersion: json['compliancePolicyVersion'] as int?,
      useLatest: json['useLatest'] as bool? ?? false,
      referenceTime: json['referenceTime'] as String,
      publish: json['publish'] as bool? ?? false,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  ReleaseSupplyChainRequest copyWith({
    ReleaseContext? releaseContext,
    String? releaseContextId,
    ReleaseEvidenceBundle? releaseEvidenceBundle,
    String? releaseEvidenceBundleId,
    QualityGateSnapshot? qualityGateSnapshot,
    String? qualityGateSnapshotId,
    ReleaseDecisionSnapshot? releaseDecisionSnapshot,
    String? releaseDecisionSnapshotId,
    String? supplyChainPolicyId,
    int? supplyChainPolicyVersion,
    String? distributionPolicyId,
    int? distributionPolicyVersion,
    String? compliancePolicyId,
    int? compliancePolicyVersion,
    bool? useLatest,
    String? referenceTime,
    bool? publish,
    Map<String, String>? metadata,
  }) {
    return ReleaseSupplyChainRequest(
      releaseContext: releaseContext ?? this.releaseContext,
      releaseContextId: releaseContextId ?? this.releaseContextId,
      releaseEvidenceBundle:
          releaseEvidenceBundle ?? this.releaseEvidenceBundle,
      releaseEvidenceBundleId:
          releaseEvidenceBundleId ?? this.releaseEvidenceBundleId,
      qualityGateSnapshot: qualityGateSnapshot ?? this.qualityGateSnapshot,
      qualityGateSnapshotId:
          qualityGateSnapshotId ?? this.qualityGateSnapshotId,
      releaseDecisionSnapshot:
          releaseDecisionSnapshot ?? this.releaseDecisionSnapshot,
      releaseDecisionSnapshotId:
          releaseDecisionSnapshotId ?? this.releaseDecisionSnapshotId,
      supplyChainPolicyId: supplyChainPolicyId ?? this.supplyChainPolicyId,
      supplyChainPolicyVersion:
          supplyChainPolicyVersion ?? this.supplyChainPolicyVersion,
      distributionPolicyId: distributionPolicyId ?? this.distributionPolicyId,
      distributionPolicyVersion:
          distributionPolicyVersion ?? this.distributionPolicyVersion,
      compliancePolicyId: compliancePolicyId ?? this.compliancePolicyId,
      compliancePolicyVersion:
          compliancePolicyVersion ?? this.compliancePolicyVersion,
      useLatest: useLatest ?? this.useLatest,
      referenceTime: referenceTime ?? this.referenceTime,
      publish: publish ?? this.publish,
      metadata: metadata ?? this.metadata,
    );
  }
}
