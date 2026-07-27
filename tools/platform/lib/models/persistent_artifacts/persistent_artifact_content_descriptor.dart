import 'persistent_artifact_enums.dart';
import 'persistent_artifact_equality.dart';

/// Declarative content descriptor for a persistent artifact.
///
/// Describes content only — does not carry bytes or compute digests.
/// Domain fingerprint != cryptographic signature.
class PersistentArtifactContentDescriptor {
  const PersistentArtifactContentDescriptor({
    required this.contentId,
    required this.mediaType,
    required this.format,
    required this.encoding,
    required this.compression,
    required this.contentFingerprint,
    this.sizeBytes,
    this.canonicalDigest,
    this.schemaVersion,
    this.metadata = const {},
  });

  final String contentId;
  final String mediaType;
  final PersistentArtifactFormat format;
  final PersistentArtifactEncoding encoding;
  final PersistentArtifactCompression compression;
  final int? sizeBytes;
  final String? canonicalDigest;
  final String? schemaVersion;
  final String contentFingerprint;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'contentId': contentId,
        'mediaType': mediaType,
        'format': format.wireName,
        'encoding': encoding.wireName,
        'compression': compression.wireName,
        if (sizeBytes != null) 'sizeBytes': sizeBytes,
        if (canonicalDigest != null) 'canonicalDigest': canonicalDigest,
        if (schemaVersion != null) 'schemaVersion': schemaVersion,
        'contentFingerprint': contentFingerprint,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactContentDescriptor.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersistentArtifactContentDescriptor(
      contentId: json['contentId'] as String,
      mediaType: json['mediaType'] as String,
      format: PersistentArtifactFormatX.fromWireName(json['format'] as String),
      encoding: PersistentArtifactEncodingX.fromWireName(
        json['encoding'] as String,
      ),
      compression: PersistentArtifactCompressionX.fromWireName(
        json['compression'] as String,
      ),
      sizeBytes: json['sizeBytes'] as int?,
      canonicalDigest: json['canonicalDigest'] as String?,
      schemaVersion: json['schemaVersion'] as String?,
      contentFingerprint: json['contentFingerprint'] as String,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'contentId': contentId,
        'mediaType': mediaType,
        'format': format.wireName,
        'encoding': encoding.wireName,
        'compression': compression.wireName,
        if (sizeBytes != null) 'sizeBytes': sizeBytes,
        if (canonicalDigest != null) 'canonicalDigest': canonicalDigest,
        if (schemaVersion != null) 'schemaVersion': schemaVersion,
        'contentFingerprint': contentFingerprint,
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactContentDescriptor copyWith({
    String? contentId,
    String? mediaType,
    PersistentArtifactFormat? format,
    PersistentArtifactEncoding? encoding,
    PersistentArtifactCompression? compression,
    int? sizeBytes,
    String? canonicalDigest,
    String? schemaVersion,
    String? contentFingerprint,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactContentDescriptor(
      contentId: contentId ?? this.contentId,
      mediaType: mediaType ?? this.mediaType,
      format: format ?? this.format,
      encoding: encoding ?? this.encoding,
      compression: compression ?? this.compression,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      canonicalDigest: canonicalDigest ?? this.canonicalDigest,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      contentFingerprint: contentFingerprint ?? this.contentFingerprint,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactContentDescriptor &&
          contentId == other.contentId &&
          mediaType == other.mediaType &&
          format == other.format &&
          encoding == other.encoding &&
          compression == other.compression &&
          sizeBytes == other.sizeBytes &&
          canonicalDigest == other.canonicalDigest &&
          schemaVersion == other.schemaVersion &&
          contentFingerprint == other.contentFingerprint &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        contentId,
        mediaType,
        format,
        encoding,
        compression,
        sizeBytes,
        canonicalDigest,
        schemaVersion,
        contentFingerprint,
        Object.hashAll(metadata.entries),
      );
}
