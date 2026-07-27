import 'cryptographic_trust_digest.dart';
import 'cryptographic_trust_enums.dart';
import 'cryptographic_trust_equality.dart';

Map<String, String> _sortedStringMap(Map<String, String> input) {
  if (input.isEmpty) return const {};
  return Map.fromEntries(
    input.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
}

/// Object to which cryptographic trust refers.
///
/// References upstream modules by IDs and fingerprints only.
/// Does not carry artifact bytes, file paths, or external URLs.
/// Domain fingerprint != cryptographic signature.
class CryptographicTrustSubject {
  const CryptographicTrustSubject({
    required this.subjectId,
    required this.subjectType,
    required this.projectId,
    required this.sourceModule,
    required this.sourceFingerprint,
    this.releaseId,
    this.artifactId,
    this.artifactType,
    this.digest,
    this.metadata = const {},
  });

  final String subjectId;
  final CryptographicTrustSubjectType subjectType;
  final String projectId;
  final String? releaseId;
  final String? artifactId;
  final String? artifactType;
  final String sourceModule;
  final String sourceFingerprint;
  final CryptographicDigest? digest;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'subjectId': subjectId,
        'subjectType': subjectType.wireName,
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        if (artifactId != null) 'artifactId': artifactId,
        if (artifactType != null) 'artifactType': artifactType,
        'sourceModule': sourceModule,
        'sourceFingerprint': sourceFingerprint,
        if (digest != null) 'digest': digest!.toJson(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory CryptographicTrustSubject.fromJson(Map<String, dynamic> json) {
    return CryptographicTrustSubject(
      subjectId: json['subjectId'] as String,
      subjectType: CryptographicTrustSubjectTypeX.fromWireName(
        json['subjectType'] as String,
      ),
      projectId: json['projectId'] as String,
      releaseId: json['releaseId'] as String?,
      artifactId: json['artifactId'] as String?,
      artifactType: json['artifactType'] as String?,
      sourceModule: json['sourceModule'] as String,
      sourceFingerprint: json['sourceFingerprint'] as String,
      digest: json['digest'] == null
          ? null
          : CryptographicDigest.fromJson(
              json['digest'] as Map<String, dynamic>),
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'subjectId': subjectId,
        'subjectType': subjectType.wireName,
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        if (artifactId != null) 'artifactId': artifactId,
        if (artifactType != null) 'artifactType': artifactType,
        'sourceModule': sourceModule,
        'sourceFingerprint': sourceFingerprint,
        if (digest != null) 'digest': digest!.toComparableJson(),
        if (metadata.isNotEmpty) 'metadata': _sortedStringMap(metadata),
      };

  CryptographicTrustSubject copyWith({
    String? subjectId,
    CryptographicTrustSubjectType? subjectType,
    String? projectId,
    String? releaseId,
    String? artifactId,
    String? artifactType,
    String? sourceModule,
    String? sourceFingerprint,
    CryptographicDigest? digest,
    Map<String, String>? metadata,
  }) {
    return CryptographicTrustSubject(
      subjectId: subjectId ?? this.subjectId,
      subjectType: subjectType ?? this.subjectType,
      projectId: projectId ?? this.projectId,
      releaseId: releaseId ?? this.releaseId,
      artifactId: artifactId ?? this.artifactId,
      artifactType: artifactType ?? this.artifactType,
      sourceModule: sourceModule ?? this.sourceModule,
      sourceFingerprint: sourceFingerprint ?? this.sourceFingerprint,
      digest: digest ?? this.digest,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CryptographicTrustSubject &&
          subjectId == other.subjectId &&
          subjectType == other.subjectType &&
          projectId == other.projectId &&
          releaseId == other.releaseId &&
          artifactId == other.artifactId &&
          artifactType == other.artifactType &&
          sourceModule == other.sourceModule &&
          sourceFingerprint == other.sourceFingerprint &&
          digest == other.digest &&
          trustMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        subjectId,
        subjectType,
        projectId,
        releaseId,
        artifactId,
        artifactType,
        sourceModule,
        sourceFingerprint,
        digest,
        Object.hashAll(metadata.entries),
      );
}
