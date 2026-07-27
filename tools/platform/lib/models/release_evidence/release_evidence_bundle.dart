import 'release_attestation.dart';
import 'release_evidence_artifact.dart';
import 'release_evidence_bundle_metadata.dart';
import 'release_evidence_compatibility.dart';
import 'release_evidence_messages.dart';
import 'release_evidence_reference.dart';
import 'release_evidence_subject.dart';
import 'release_provenance.dart';

/// Reference to the evidence collection policy used by a bundle.
class ReleaseEvidencePolicyReference {
  const ReleaseEvidencePolicyReference({
    required this.policyId,
    required this.policyVersion,
    required this.policyFingerprint,
  });

  final String policyId;
  final int policyVersion;
  final String policyFingerprint;

  Map<String, dynamic> toJson() => {
        'policyId': policyId,
        'policyVersion': policyVersion,
        'policyFingerprint': policyFingerprint,
      };

  factory ReleaseEvidencePolicyReference.fromJson(Map<String, dynamic> json) {
    return ReleaseEvidencePolicyReference(
      policyId: json['policyId'] as String,
      policyVersion: json['policyVersion'] as int,
      policyFingerprint: json['policyFingerprint'] as String,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseEvidencePolicyReference &&
          runtimeType == other.runtimeType &&
          policyId == other.policyId &&
          policyVersion == other.policyVersion &&
          policyFingerprint == other.policyFingerprint;

  @override
  int get hashCode => Object.hash(policyId, policyVersion, policyFingerprint);
}

/// Reference to a published release context artifact.
class ReleaseReleaseContextReference {
  const ReleaseReleaseContextReference({
    required this.releaseContextId,
    required this.projectId,
    required this.releaseId,
    required this.fingerprint,
    this.commitId,
  });

  final String releaseContextId;
  final String projectId;
  final String releaseId;
  final String fingerprint;
  final String? commitId;

  Map<String, dynamic> toJson() => {
        'releaseContextId': releaseContextId,
        'projectId': projectId,
        'releaseId': releaseId,
        'fingerprint': fingerprint,
        if (commitId != null) 'commitId': commitId,
      };

  factory ReleaseReleaseContextReference.fromJson(Map<String, dynamic> json) {
    return ReleaseReleaseContextReference(
      releaseContextId: json['releaseContextId'] as String,
      projectId: json['projectId'] as String,
      releaseId: json['releaseId'] as String,
      fingerprint: json['fingerprint'] as String,
      commitId: json['commitId'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseReleaseContextReference &&
          runtimeType == other.runtimeType &&
          releaseContextId == other.releaseContextId &&
          projectId == other.projectId &&
          releaseId == other.releaseId &&
          fingerprint == other.fingerprint &&
          commitId == other.commitId;

  @override
  int get hashCode => Object.hash(
      releaseContextId, projectId, releaseId, fingerprint, commitId);
}

/// Reference to a published Quality Gate snapshot used as evidence.
class ReleaseQualityGateEvidenceReference {
  const ReleaseQualityGateEvidenceReference({
    required this.qualityGateSnapshotId,
    required this.qualityGateFingerprint,
    required this.policyId,
    required this.policyVersion,
    required this.decision,
    this.projectId,
    this.commitId,
  });

  final String qualityGateSnapshotId;
  final String qualityGateFingerprint;
  final String policyId;
  final int policyVersion;
  final String decision;
  final String? projectId;
  final String? commitId;

  Map<String, dynamic> toJson() => {
        'qualityGateSnapshotId': qualityGateSnapshotId,
        'qualityGateFingerprint': qualityGateFingerprint,
        'policyId': policyId,
        'policyVersion': policyVersion,
        'decision': decision,
        if (projectId != null) 'projectId': projectId,
        if (commitId != null) 'commitId': commitId,
      };

  factory ReleaseQualityGateEvidenceReference.fromJson(
    Map<String, dynamic> json,
  ) {
    return ReleaseQualityGateEvidenceReference(
      qualityGateSnapshotId: json['qualityGateSnapshotId'] as String,
      qualityGateFingerprint: json['qualityGateFingerprint'] as String,
      policyId: json['policyId'] as String,
      policyVersion: json['policyVersion'] as int,
      decision: json['decision'] as String,
      projectId: json['projectId'] as String?,
      commitId: json['commitId'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseQualityGateEvidenceReference &&
          runtimeType == other.runtimeType &&
          qualityGateSnapshotId == other.qualityGateSnapshotId &&
          qualityGateFingerprint == other.qualityGateFingerprint &&
          policyId == other.policyId &&
          policyVersion == other.policyVersion &&
          decision == other.decision &&
          projectId == other.projectId &&
          commitId == other.commitId;

  @override
  int get hashCode => Object.hash(
        qualityGateSnapshotId,
        qualityGateFingerprint,
        policyId,
        policyVersion,
        decision,
        projectId,
        commitId,
      );
}

/// Reference to a published Release Decision snapshot used as evidence.
class ReleaseDecisionEvidenceReference {
  const ReleaseDecisionEvidenceReference({
    required this.releaseDecisionSnapshotId,
    required this.releaseDecisionFingerprint,
    required this.policyId,
    required this.policyVersion,
    required this.decision,
    this.qualityGateSnapshotId,
    this.projectId,
    this.commitId,
  });

  final String releaseDecisionSnapshotId;
  final String releaseDecisionFingerprint;
  final String policyId;
  final int policyVersion;
  final String decision;
  final String? qualityGateSnapshotId;
  final String? projectId;
  final String? commitId;

  Map<String, dynamic> toJson() => {
        'releaseDecisionSnapshotId': releaseDecisionSnapshotId,
        'releaseDecisionFingerprint': releaseDecisionFingerprint,
        'policyId': policyId,
        'policyVersion': policyVersion,
        'decision': decision,
        if (qualityGateSnapshotId != null)
          'qualityGateSnapshotId': qualityGateSnapshotId,
        if (projectId != null) 'projectId': projectId,
        if (commitId != null) 'commitId': commitId,
      };

  factory ReleaseDecisionEvidenceReference.fromJson(
    Map<String, dynamic> json,
  ) {
    return ReleaseDecisionEvidenceReference(
      releaseDecisionSnapshotId: json['releaseDecisionSnapshotId'] as String,
      releaseDecisionFingerprint: json['releaseDecisionFingerprint'] as String,
      policyId: json['policyId'] as String,
      policyVersion: json['policyVersion'] as int,
      decision: json['decision'] as String,
      qualityGateSnapshotId: json['qualityGateSnapshotId'] as String?,
      projectId: json['projectId'] as String?,
      commitId: json['commitId'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseDecisionEvidenceReference &&
          runtimeType == other.runtimeType &&
          releaseDecisionSnapshotId == other.releaseDecisionSnapshotId &&
          releaseDecisionFingerprint == other.releaseDecisionFingerprint &&
          policyId == other.policyId &&
          policyVersion == other.policyVersion &&
          decision == other.decision &&
          qualityGateSnapshotId == other.qualityGateSnapshotId &&
          projectId == other.projectId &&
          commitId == other.commitId;

  @override
  int get hashCode => Object.hash(
        releaseDecisionSnapshotId,
        releaseDecisionFingerprint,
        policyId,
        policyVersion,
        decision,
        qualityGateSnapshotId,
        projectId,
        commitId,
      );
}

/// Immutable audit bundle organizing release evidence references.
class ReleaseEvidenceBundle {
  ReleaseEvidenceBundle({
    required this.metadata,
    required this.subject,
    required this.policyReference,
    required this.releaseContextReference,
    required this.qualityGateReference,
    required this.releaseDecisionReference,
    required this.compatibility,
    required this.eligibility,
    required this.coverage,
    required this.fingerprint,
    List<ReleaseEvidenceArtifact> evidence = const [],
    List<ReleaseProvenance> provenance = const [],
    List<ReleaseAttestation> attestations = const [],
    List<ReleaseEvidenceExplanation> explanations = const [],
    List<ReleaseEvidenceWarning> warnings = const [],
    List<ReleaseEvidenceError> errors = const [],
    List<ReleaseEvidenceLimitation> limitations = const [],
    List<ReleaseEvidenceSourceReference> sourceReferences = const [],
  })  : evidence = List.unmodifiable(evidence),
        provenance = List.unmodifiable(provenance),
        attestations = List.unmodifiable(attestations),
        explanations = List.unmodifiable(explanations),
        warnings = List.unmodifiable(warnings),
        errors = List.unmodifiable(errors),
        limitations = List.unmodifiable(limitations),
        sourceReferences = List.unmodifiable(sourceReferences);

  final ReleaseEvidenceBundleMetadata metadata;
  final ReleaseEvidenceSubject subject;
  final ReleaseEvidencePolicyReference policyReference;
  final ReleaseReleaseContextReference releaseContextReference;
  final ReleaseQualityGateEvidenceReference qualityGateReference;
  final ReleaseDecisionEvidenceReference releaseDecisionReference;
  final List<ReleaseEvidenceArtifact> evidence;
  final List<ReleaseProvenance> provenance;
  final List<ReleaseAttestation> attestations;
  final ReleaseEvidenceCompatibility compatibility;
  final ReleaseEvidenceEligibility eligibility;
  final ReleaseEvidenceCoverage coverage;
  final List<ReleaseEvidenceExplanation> explanations;
  final List<ReleaseEvidenceWarning> warnings;
  final List<ReleaseEvidenceError> errors;
  final List<ReleaseEvidenceLimitation> limitations;
  final List<ReleaseEvidenceSourceReference> sourceReferences;
  final String fingerprint;

  Map<String, dynamic> toJson() => {
        'metadata': metadata.toJson(),
        'subject': subject.toJson(),
        'policyReference': policyReference.toJson(),
        'releaseContextReference': releaseContextReference.toJson(),
        'qualityGateReference': qualityGateReference.toJson(),
        'releaseDecisionReference': releaseDecisionReference.toJson(),
        'evidence': evidence.map((e) => e.toJson()).toList(),
        'provenance': provenance.map((e) => e.toJson()).toList(),
        'attestations': attestations.map((e) => e.toJson()).toList(),
        'compatibility': compatibility.toJson(),
        'eligibility': eligibility.toJson(),
        'coverage': coverage.toJson(),
        if (explanations.isNotEmpty)
          'explanations': explanations.map((e) => e.toJson()).toList(),
        if (warnings.isNotEmpty)
          'warnings': warnings.map((e) => e.toJson()).toList(),
        if (errors.isNotEmpty) 'errors': errors.map((e) => e.toJson()).toList(),
        if (limitations.isNotEmpty)
          'limitations': limitations.map((e) => e.toJson()).toList(),
        if (sourceReferences.isNotEmpty)
          'sourceReferences': sourceReferences.map((e) => e.toJson()).toList(),
        'fingerprint': fingerprint,
      };

  factory ReleaseEvidenceBundle.fromJson(Map<String, dynamic> json) {
    return ReleaseEvidenceBundle(
      metadata: ReleaseEvidenceBundleMetadata.fromJson(
        json['metadata'] as Map<String, dynamic>,
      ),
      subject: ReleaseEvidenceSubject.fromJson(
        json['subject'] as Map<String, dynamic>,
      ),
      policyReference: ReleaseEvidencePolicyReference.fromJson(
        json['policyReference'] as Map<String, dynamic>,
      ),
      releaseContextReference: ReleaseReleaseContextReference.fromJson(
        json['releaseContextReference'] as Map<String, dynamic>,
      ),
      qualityGateReference: ReleaseQualityGateEvidenceReference.fromJson(
        json['qualityGateReference'] as Map<String, dynamic>,
      ),
      releaseDecisionReference: ReleaseDecisionEvidenceReference.fromJson(
        json['releaseDecisionReference'] as Map<String, dynamic>,
      ),
      evidence: (json['evidence'] as List<dynamic>? ?? [])
          .map(
            (e) => ReleaseEvidenceArtifact.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      provenance: (json['provenance'] as List<dynamic>? ?? [])
          .map((e) => ReleaseProvenance.fromJson(e as Map<String, dynamic>))
          .toList(),
      attestations: (json['attestations'] as List<dynamic>? ?? [])
          .map((e) => ReleaseAttestation.fromJson(e as Map<String, dynamic>))
          .toList(),
      compatibility: ReleaseEvidenceCompatibility.fromJson(
        json['compatibility'] as Map<String, dynamic>,
      ),
      eligibility: ReleaseEvidenceEligibility.fromJson(
        json['eligibility'] as Map<String, dynamic>,
      ),
      coverage: ReleaseEvidenceCoverage.fromJson(
        json['coverage'] as Map<String, dynamic>,
      ),
      explanations: (json['explanations'] as List<dynamic>? ?? [])
          .map(
            (e) => ReleaseEvidenceExplanation.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList(),
      warnings: (json['warnings'] as List<dynamic>? ?? [])
          .map(
            (e) => ReleaseEvidenceWarning.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      errors: (json['errors'] as List<dynamic>? ?? [])
          .map(
            (e) => ReleaseEvidenceError.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      limitations: (json['limitations'] as List<dynamic>? ?? [])
          .map(
            (e) => ReleaseEvidenceLimitation.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList(),
      sourceReferences: (json['sourceReferences'] as List<dynamic>? ?? [])
          .map(
            (e) => ReleaseEvidenceSourceReference.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList(),
      fingerprint: json['fingerprint'] as String,
    );
  }

  ReleaseEvidenceBundle copyWith({
    ReleaseEvidenceBundleMetadata? metadata,
    ReleaseEvidenceSubject? subject,
    ReleaseEvidencePolicyReference? policyReference,
    ReleaseReleaseContextReference? releaseContextReference,
    ReleaseQualityGateEvidenceReference? qualityGateReference,
    ReleaseDecisionEvidenceReference? releaseDecisionReference,
    List<ReleaseEvidenceArtifact>? evidence,
    List<ReleaseProvenance>? provenance,
    List<ReleaseAttestation>? attestations,
    ReleaseEvidenceCompatibility? compatibility,
    ReleaseEvidenceEligibility? eligibility,
    ReleaseEvidenceCoverage? coverage,
    List<ReleaseEvidenceExplanation>? explanations,
    List<ReleaseEvidenceWarning>? warnings,
    List<ReleaseEvidenceError>? errors,
    List<ReleaseEvidenceLimitation>? limitations,
    List<ReleaseEvidenceSourceReference>? sourceReferences,
    String? fingerprint,
  }) {
    return ReleaseEvidenceBundle(
      metadata: metadata ?? this.metadata,
      subject: subject ?? this.subject,
      policyReference: policyReference ?? this.policyReference,
      releaseContextReference:
          releaseContextReference ?? this.releaseContextReference,
      qualityGateReference: qualityGateReference ?? this.qualityGateReference,
      releaseDecisionReference:
          releaseDecisionReference ?? this.releaseDecisionReference,
      evidence: evidence ?? this.evidence,
      provenance: provenance ?? this.provenance,
      attestations: attestations ?? this.attestations,
      compatibility: compatibility ?? this.compatibility,
      eligibility: eligibility ?? this.eligibility,
      coverage: coverage ?? this.coverage,
      explanations: explanations ?? this.explanations,
      warnings: warnings ?? this.warnings,
      errors: errors ?? this.errors,
      limitations: limitations ?? this.limitations,
      sourceReferences: sourceReferences ?? this.sourceReferences,
      fingerprint: fingerprint ?? this.fingerprint,
    );
  }
}
