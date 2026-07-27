import '../release_governance/release_governance_enums.dart';
import 'release_evidence_enums.dart';
import 'release_evidence_reference.dart';

/// Authority permitted to endorse attestations.
class ReleaseAttestationAuthority {
  const ReleaseAttestationAuthority({
    required this.authorityId,
    required this.authorityType,
    required this.allowedAttestationTypes,
    required this.allowedSubjectTypes,
    required this.allowedEnvironments,
    required this.allowedReleaseTypes,
    required this.validFrom,
    required this.status,
    required this.schemaVersion,
    this.expiresAt,
    this.evidenceReferences = const [],
  });

  final String authorityId;
  final String authorityType;
  final List<ReleaseAttestationType> allowedAttestationTypes;
  final List<ReleaseEvidenceSubjectType> allowedSubjectTypes;
  final List<ReleaseEnvironment> allowedEnvironments;
  final List<ReleaseType> allowedReleaseTypes;
  final String validFrom;
  final String? expiresAt;
  final ReleaseAttestationAuthorityStatus status;
  final List<ReleaseEvidenceReference> evidenceReferences;
  final int schemaVersion;

  Map<String, dynamic> toJson() => {
        'authorityId': authorityId,
        'authorityType': authorityType,
        'allowedAttestationTypes':
            allowedAttestationTypes.map((e) => e.wireName).toList(),
        'allowedSubjectTypes':
            allowedSubjectTypes.map((e) => e.wireName).toList(),
        'allowedEnvironments':
            allowedEnvironments.map((e) => e.wireName).toList(),
        'allowedReleaseTypes':
            allowedReleaseTypes.map((e) => e.wireName).toList(),
        'validFrom': validFrom,
        if (expiresAt != null) 'expiresAt': expiresAt,
        'status': status.wireName,
        if (evidenceReferences.isNotEmpty)
          'evidenceReferences':
              evidenceReferences.map((e) => e.toJson()).toList(),
        'schemaVersion': schemaVersion,
      };

  factory ReleaseAttestationAuthority.fromJson(Map<String, dynamic> json) {
    return ReleaseAttestationAuthority(
      authorityId: json['authorityId'] as String,
      authorityType: json['authorityType'] as String,
      allowedAttestationTypes: List.unmodifiable(
        (json['allowedAttestationTypes'] as List<dynamic>)
            .map((e) => ReleaseAttestationTypeX.fromWireName(e as String))
            .toList(),
      ),
      allowedSubjectTypes: List.unmodifiable(
        (json['allowedSubjectTypes'] as List<dynamic>)
            .map(
              (e) => ReleaseEvidenceSubjectTypeX.fromWireName(e as String),
            )
            .toList(),
      ),
      allowedEnvironments: List.unmodifiable(
        (json['allowedEnvironments'] as List<dynamic>)
            .map((e) => ReleaseEnvironmentX.fromWireName(e as String))
            .toList(),
      ),
      allowedReleaseTypes: List.unmodifiable(
        (json['allowedReleaseTypes'] as List<dynamic>)
            .map((e) => ReleaseTypeX.fromWireName(e as String))
            .toList(),
      ),
      validFrom: json['validFrom'] as String,
      expiresAt: json['expiresAt'] as String?,
      status: ReleaseAttestationAuthorityStatusX.fromWireName(
        json['status'] as String,
      ),
      evidenceReferences: List.unmodifiable(
        (json['evidenceReferences'] as List<dynamic>? ?? [])
            .map(
              (e) => ReleaseEvidenceReference.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      schemaVersion: json['schemaVersion'] as int,
    );
  }
}
