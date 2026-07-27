import '../quality_gate/quality_gate_snapshot.dart';
import '../release_governance/release_context.dart';
import '../release_governance/release_decision_snapshot.dart';
import 'release_attestation_set.dart';
import 'release_evidence_reference.dart';
import 'release_provenance.dart';

/// Request to collect and compose release evidence.
class ReleaseEvidenceRequest {
  const ReleaseEvidenceRequest({
    required this.releaseContext,
    required this.referenceTime,
    this.releaseContextId,
    this.qualityGateSnapshot,
    this.qualityGateSnapshotId,
    this.releaseDecisionSnapshot,
    this.releaseDecisionSnapshotId,
    this.evidencePolicyId,
    this.evidencePolicyVersion,
    this.attestationPolicyId,
    this.attestationPolicyVersion,
    this.verificationPolicyId,
    this.verificationPolicyVersion,
    this.evidenceReferences = const [],
    this.evidenceReferenceIds = const [],
    this.attestationSet,
    this.attestationSetId,
    this.provenance = const [],
    this.provenanceIds = const [],
    this.useLatest = false,
    this.historicalEvaluation = false,
    this.includeVerification = true,
    this.includeEvidence = true,
    this.includeExplanations = true,
    this.publish = false,
    this.metadata = const {},
  });

  final ReleaseContext releaseContext;
  final String? releaseContextId;
  final QualityGateSnapshot? qualityGateSnapshot;
  final String? qualityGateSnapshotId;
  final ReleaseDecisionSnapshot? releaseDecisionSnapshot;
  final String? releaseDecisionSnapshotId;
  final String? evidencePolicyId;
  final int? evidencePolicyVersion;
  final String? attestationPolicyId;
  final int? attestationPolicyVersion;
  final String? verificationPolicyId;
  final int? verificationPolicyVersion;
  final List<ReleaseEvidenceReference> evidenceReferences;
  final List<String> evidenceReferenceIds;
  final ReleaseAttestationSet? attestationSet;
  final String? attestationSetId;
  final List<ReleaseProvenance> provenance;
  final List<String> provenanceIds;
  final bool useLatest;
  final String referenceTime;
  final bool historicalEvaluation;
  final bool includeVerification;
  final bool includeEvidence;
  final bool includeExplanations;
  final bool publish;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'releaseContext': releaseContext.toJson(),
        if (releaseContextId != null) 'releaseContextId': releaseContextId,
        if (qualityGateSnapshot != null)
          'qualityGateSnapshot': qualityGateSnapshot!.toJson(),
        if (qualityGateSnapshotId != null)
          'qualityGateSnapshotId': qualityGateSnapshotId,
        if (releaseDecisionSnapshot != null)
          'releaseDecisionSnapshot': releaseDecisionSnapshot!.toJson(),
        if (releaseDecisionSnapshotId != null)
          'releaseDecisionSnapshotId': releaseDecisionSnapshotId,
        if (evidencePolicyId != null) 'evidencePolicyId': evidencePolicyId,
        if (evidencePolicyVersion != null)
          'evidencePolicyVersion': evidencePolicyVersion,
        if (attestationPolicyId != null)
          'attestationPolicyId': attestationPolicyId,
        if (attestationPolicyVersion != null)
          'attestationPolicyVersion': attestationPolicyVersion,
        if (verificationPolicyId != null)
          'verificationPolicyId': verificationPolicyId,
        if (verificationPolicyVersion != null)
          'verificationPolicyVersion': verificationPolicyVersion,
        if (evidenceReferences.isNotEmpty)
          'evidenceReferences':
              evidenceReferences.map((e) => e.toJson()).toList(),
        if (evidenceReferenceIds.isNotEmpty)
          'evidenceReferenceIds': evidenceReferenceIds,
        if (attestationSet != null) 'attestationSet': attestationSet!.toJson(),
        if (attestationSetId != null) 'attestationSetId': attestationSetId,
        if (provenance.isNotEmpty)
          'provenance': provenance.map((e) => e.toJson()).toList(),
        if (provenanceIds.isNotEmpty) 'provenanceIds': provenanceIds,
        'useLatest': useLatest,
        'referenceTime': referenceTime,
        'historicalEvaluation': historicalEvaluation,
        'includeVerification': includeVerification,
        'includeEvidence': includeEvidence,
        'includeExplanations': includeExplanations,
        'publish': publish,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory ReleaseEvidenceRequest.fromJson(Map<String, dynamic> json) {
    return ReleaseEvidenceRequest(
      releaseContext: ReleaseContext.fromJson(
        json['releaseContext'] as Map<String, dynamic>,
      ),
      releaseContextId: json['releaseContextId'] as String?,
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
      evidencePolicyId: json['evidencePolicyId'] as String?,
      evidencePolicyVersion: json['evidencePolicyVersion'] as int?,
      attestationPolicyId: json['attestationPolicyId'] as String?,
      attestationPolicyVersion: json['attestationPolicyVersion'] as int?,
      verificationPolicyId: json['verificationPolicyId'] as String?,
      verificationPolicyVersion: json['verificationPolicyVersion'] as int?,
      evidenceReferences: List.unmodifiable(
        (json['evidenceReferences'] as List<dynamic>? ?? [])
            .map(
              (e) => ReleaseEvidenceReference.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      evidenceReferenceIds: List.unmodifiable(
        (json['evidenceReferenceIds'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
      attestationSet: json['attestationSet'] == null
          ? null
          : ReleaseAttestationSet.fromJson(
              json['attestationSet'] as Map<String, dynamic>,
            ),
      attestationSetId: json['attestationSetId'] as String?,
      provenance: List.unmodifiable(
        (json['provenance'] as List<dynamic>? ?? [])
            .map((e) => ReleaseProvenance.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      provenanceIds: List.unmodifiable(
        (json['provenanceIds'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
      useLatest: json['useLatest'] as bool? ?? false,
      referenceTime: json['referenceTime'] as String,
      historicalEvaluation: json['historicalEvaluation'] as bool? ?? false,
      includeVerification: json['includeVerification'] as bool? ?? true,
      includeEvidence: json['includeEvidence'] as bool? ?? true,
      includeExplanations: json['includeExplanations'] as bool? ?? true,
      publish: json['publish'] as bool? ?? false,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  ReleaseEvidenceRequest copyWith({
    ReleaseContext? releaseContext,
    String? releaseContextId,
    QualityGateSnapshot? qualityGateSnapshot,
    String? qualityGateSnapshotId,
    ReleaseDecisionSnapshot? releaseDecisionSnapshot,
    String? releaseDecisionSnapshotId,
    String? evidencePolicyId,
    int? evidencePolicyVersion,
    String? attestationPolicyId,
    int? attestationPolicyVersion,
    String? verificationPolicyId,
    int? verificationPolicyVersion,
    List<ReleaseEvidenceReference>? evidenceReferences,
    List<String>? evidenceReferenceIds,
    ReleaseAttestationSet? attestationSet,
    String? attestationSetId,
    List<ReleaseProvenance>? provenance,
    List<String>? provenanceIds,
    bool? useLatest,
    String? referenceTime,
    bool? historicalEvaluation,
    bool? includeVerification,
    bool? includeEvidence,
    bool? includeExplanations,
    bool? publish,
    Map<String, String>? metadata,
  }) {
    return ReleaseEvidenceRequest(
      releaseContext: releaseContext ?? this.releaseContext,
      releaseContextId: releaseContextId ?? this.releaseContextId,
      qualityGateSnapshot: qualityGateSnapshot ?? this.qualityGateSnapshot,
      qualityGateSnapshotId:
          qualityGateSnapshotId ?? this.qualityGateSnapshotId,
      releaseDecisionSnapshot:
          releaseDecisionSnapshot ?? this.releaseDecisionSnapshot,
      releaseDecisionSnapshotId:
          releaseDecisionSnapshotId ?? this.releaseDecisionSnapshotId,
      evidencePolicyId: evidencePolicyId ?? this.evidencePolicyId,
      evidencePolicyVersion:
          evidencePolicyVersion ?? this.evidencePolicyVersion,
      attestationPolicyId: attestationPolicyId ?? this.attestationPolicyId,
      attestationPolicyVersion:
          attestationPolicyVersion ?? this.attestationPolicyVersion,
      verificationPolicyId: verificationPolicyId ?? this.verificationPolicyId,
      verificationPolicyVersion:
          verificationPolicyVersion ?? this.verificationPolicyVersion,
      evidenceReferences: evidenceReferences ?? this.evidenceReferences,
      evidenceReferenceIds: evidenceReferenceIds ?? this.evidenceReferenceIds,
      attestationSet: attestationSet ?? this.attestationSet,
      attestationSetId: attestationSetId ?? this.attestationSetId,
      provenance: provenance ?? this.provenance,
      provenanceIds: provenanceIds ?? this.provenanceIds,
      useLatest: useLatest ?? this.useLatest,
      referenceTime: referenceTime ?? this.referenceTime,
      historicalEvaluation: historicalEvaluation ?? this.historicalEvaluation,
      includeVerification: includeVerification ?? this.includeVerification,
      includeEvidence: includeEvidence ?? this.includeEvidence,
      includeExplanations: includeExplanations ?? this.includeExplanations,
      publish: publish ?? this.publish,
      metadata: metadata ?? this.metadata,
    );
  }
}
