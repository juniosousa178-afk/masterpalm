import 'release_evidence_enums.dart';

/// Actor participating in a provenance chain.
class ReleaseProvenanceActor {
  const ReleaseProvenanceActor({
    required this.actorId,
    required this.actorType,
    required this.identityStatus,
    this.displayName,
    this.organization,
    this.role,
    this.authorityReference,
    this.metadata = const {},
  });

  final String actorId;
  final ReleaseProvenanceActorType actorType;
  final String? displayName;
  final String? organization;
  final String? role;
  final String? authorityReference;
  final ReleaseIdentityStatus identityStatus;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'actorId': actorId,
        'actorType': actorType.wireName,
        if (displayName != null) 'displayName': displayName,
        if (organization != null) 'organization': organization,
        if (role != null) 'role': role,
        if (authorityReference != null)
          'authorityReference': authorityReference,
        'identityStatus': identityStatus.wireName,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory ReleaseProvenanceActor.fromJson(Map<String, dynamic> json) {
    return ReleaseProvenanceActor(
      actorId: json['actorId'] as String,
      actorType: ReleaseProvenanceActorTypeX.fromWireName(
        json['actorType'] as String,
      ),
      displayName: json['displayName'] as String?,
      organization: json['organization'] as String?,
      role: json['role'] as String?,
      authorityReference: json['authorityReference'] as String?,
      identityStatus: ReleaseIdentityStatusX.fromWireName(
        json['identityStatus'] as String,
      ),
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }
}
