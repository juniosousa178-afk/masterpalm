import 'cryptographic_trust_equality.dart';
import 'cryptographic_trust_enums.dart';

/// Declarative upstream reference within the Cryptographic Trust domain.
///
/// References only — does not resolve sources or recalculate upstream
/// fingerprints. Domain fingerprint != cryptographic signature.
class CryptographicTrustSourceReference {
  const CryptographicTrustSourceReference({
    required this.sourceType,
    required this.sourceId,
    required this.projectId,
    required this.fingerprint,
    this.releaseId,
    this.version,
    this.metadata = const {},
  });

  final CryptographicSourceType sourceType;
  final String sourceId;
  final String projectId;
  final String? releaseId;
  final String fingerprint;
  final int? version;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'sourceType': sourceType.wireName,
        'sourceId': sourceId,
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        'fingerprint': fingerprint,
        if (version != null) 'version': version,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory CryptographicTrustSourceReference.fromJson(
    Map<String, dynamic> json,
  ) {
    return CryptographicTrustSourceReference(
      sourceType: CryptographicSourceTypeX.fromWireName(
        json['sourceType'] as String,
      ),
      sourceId: json['sourceId'] as String,
      projectId: json['projectId'] as String,
      releaseId: json['releaseId'] as String?,
      fingerprint: json['fingerprint'] as String,
      version: json['version'] as int?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'sourceType': sourceType.wireName,
        'sourceId': sourceId,
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        'fingerprint': fingerprint,
        if (version != null) 'version': version,
      };

  CryptographicTrustSourceReference copyWith({
    CryptographicSourceType? sourceType,
    String? sourceId,
    String? projectId,
    String? releaseId,
    String? fingerprint,
    int? version,
    Map<String, String>? metadata,
  }) {
    return CryptographicTrustSourceReference(
      sourceType: sourceType ?? this.sourceType,
      sourceId: sourceId ?? this.sourceId,
      projectId: projectId ?? this.projectId,
      releaseId: releaseId ?? this.releaseId,
      fingerprint: fingerprint ?? this.fingerprint,
      version: version ?? this.version,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CryptographicTrustSourceReference &&
          sourceType == other.sourceType &&
          sourceId == other.sourceId &&
          projectId == other.projectId &&
          releaseId == other.releaseId &&
          fingerprint == other.fingerprint &&
          version == other.version &&
          trustMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        sourceType,
        sourceId,
        projectId,
        releaseId,
        fingerprint,
        version,
        Object.hashAll(metadata.entries),
      );
}
