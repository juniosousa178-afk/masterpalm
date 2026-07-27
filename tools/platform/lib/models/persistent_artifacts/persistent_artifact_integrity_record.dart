import 'persistent_artifact_enums.dart';
import 'persistent_artifact_equality.dart';

/// Declarative integrity record for a persistent artifact.
///
/// Digest is descriptive only — does not compute, verify, or sign content.
/// Does not replace Cryptographic Trust. Domain fingerprint != signature.
class PersistentArtifactIntegrityRecord {
  const PersistentArtifactIntegrityRecord({
    required this.integrityRecordId,
    required this.artifactId,
    required this.versionId,
    required this.digestAlgorithmId,
    required this.digestValue,
    required this.contentFingerprint,
    required this.status,
    this.cryptographicTrustReference,
    this.verifiedAt,
    this.metadata = const {},
  });

  final String integrityRecordId;
  final String artifactId;
  final String versionId;
  final String digestAlgorithmId;
  final String digestValue;
  final String contentFingerprint;
  final String? cryptographicTrustReference;
  final PersistentArtifactIntegrityStatus status;
  final String? verifiedAt;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'integrityRecordId': integrityRecordId,
        'artifactId': artifactId,
        'versionId': versionId,
        'digestAlgorithmId': digestAlgorithmId,
        'digestValue': digestValue,
        'contentFingerprint': contentFingerprint,
        if (cryptographicTrustReference != null)
          'cryptographicTrustReference': cryptographicTrustReference,
        'status': status.wireName,
        if (verifiedAt != null) 'verifiedAt': verifiedAt,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactIntegrityRecord.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersistentArtifactIntegrityRecord(
      integrityRecordId: json['integrityRecordId'] as String,
      artifactId: json['artifactId'] as String,
      versionId: json['versionId'] as String,
      digestAlgorithmId: json['digestAlgorithmId'] as String,
      digestValue: json['digestValue'] as String,
      contentFingerprint: json['contentFingerprint'] as String,
      cryptographicTrustReference:
          json['cryptographicTrustReference'] as String?,
      status: PersistentArtifactIntegrityStatusX.fromWireName(
        json['status'] as String,
      ),
      verifiedAt: json['verifiedAt'] as String?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'integrityRecordId': integrityRecordId,
        'artifactId': artifactId,
        'versionId': versionId,
        'digestAlgorithmId': digestAlgorithmId,
        'digestValue': digestValue,
        'contentFingerprint': contentFingerprint,
        if (cryptographicTrustReference != null)
          'cryptographicTrustReference': cryptographicTrustReference,
        'status': status.wireName,
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactIntegrityRecord copyWith({
    String? integrityRecordId,
    String? artifactId,
    String? versionId,
    String? digestAlgorithmId,
    String? digestValue,
    String? contentFingerprint,
    String? cryptographicTrustReference,
    PersistentArtifactIntegrityStatus? status,
    String? verifiedAt,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactIntegrityRecord(
      integrityRecordId: integrityRecordId ?? this.integrityRecordId,
      artifactId: artifactId ?? this.artifactId,
      versionId: versionId ?? this.versionId,
      digestAlgorithmId: digestAlgorithmId ?? this.digestAlgorithmId,
      digestValue: digestValue ?? this.digestValue,
      contentFingerprint: contentFingerprint ?? this.contentFingerprint,
      cryptographicTrustReference:
          cryptographicTrustReference ?? this.cryptographicTrustReference,
      status: status ?? this.status,
      verifiedAt: verifiedAt ?? this.verifiedAt,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactIntegrityRecord &&
          integrityRecordId == other.integrityRecordId &&
          artifactId == other.artifactId &&
          versionId == other.versionId &&
          digestAlgorithmId == other.digestAlgorithmId &&
          digestValue == other.digestValue &&
          contentFingerprint == other.contentFingerprint &&
          cryptographicTrustReference == other.cryptographicTrustReference &&
          status == other.status &&
          verifiedAt == other.verifiedAt &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        integrityRecordId,
        artifactId,
        versionId,
        digestAlgorithmId,
        digestValue,
        contentFingerprint,
        cryptographicTrustReference,
        status,
        verifiedAt,
        Object.hashAll(metadata.entries),
      );
}
