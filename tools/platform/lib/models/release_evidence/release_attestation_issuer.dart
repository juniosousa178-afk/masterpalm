import 'release_evidence_enums.dart';
import 'release_evidence_reference.dart';

/// Entity that issued an attestation.
class ReleaseAttestationIssuer {
  const ReleaseAttestationIssuer({
    required this.issuerId,
    required this.issuerType,
    required this.identityStatus,
    required this.validFrom,
    this.displayName,
    this.organization,
    this.role,
    this.authorityId,
    this.expiresAt,
    this.evidenceReferences = const [],
    this.metadata = const {},
  });

  final String issuerId;
  final ReleaseAttestationIssuerType issuerType;
  final String? displayName;
  final String? organization;
  final String? role;
  final String? authorityId;
  final ReleaseIdentityStatus identityStatus;
  final String validFrom;
  final String? expiresAt;
  final List<ReleaseEvidenceReference> evidenceReferences;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'issuerId': issuerId,
        'issuerType': issuerType.wireName,
        if (displayName != null) 'displayName': displayName,
        if (organization != null) 'organization': organization,
        if (role != null) 'role': role,
        if (authorityId != null) 'authorityId': authorityId,
        'identityStatus': identityStatus.wireName,
        'validFrom': validFrom,
        if (expiresAt != null) 'expiresAt': expiresAt,
        if (evidenceReferences.isNotEmpty)
          'evidenceReferences':
              evidenceReferences.map((e) => e.toJson()).toList(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory ReleaseAttestationIssuer.fromJson(Map<String, dynamic> json) {
    return ReleaseAttestationIssuer(
      issuerId: json['issuerId'] as String,
      issuerType: ReleaseAttestationIssuerTypeX.fromWireName(
        json['issuerType'] as String,
      ),
      displayName: json['displayName'] as String?,
      organization: json['organization'] as String?,
      role: json['role'] as String?,
      authorityId: json['authorityId'] as String?,
      identityStatus: ReleaseIdentityStatusX.fromWireName(
        json['identityStatus'] as String,
      ),
      validFrom: json['validFrom'] as String,
      expiresAt: json['expiresAt'] as String?,
      evidenceReferences: List.unmodifiable(
        (json['evidenceReferences'] as List<dynamic>? ?? [])
            .map(
              (e) => ReleaseEvidenceReference.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }
}
