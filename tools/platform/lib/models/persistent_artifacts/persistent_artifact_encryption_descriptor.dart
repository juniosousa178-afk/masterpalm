import 'persistent_artifact_enums.dart';
import 'persistent_artifact_equality.dart';

/// Declarative encryption metadata for a persistent artifact.
///
/// Does not contain keys, secrets, or tokens. Does not execute encryption.
/// Encryption metadata does not prove real protection.
class PersistentArtifactEncryptionDescriptor {
  const PersistentArtifactEncryptionDescriptor({
    required this.encryptionStatus,
    this.algorithmId,
    this.keyReferenceId,
    this.keyVersion,
    this.envelopeReferenceId,
    this.encryptedContentFingerprint,
    this.metadata = const {},
  });

  final PersistentArtifactEncryptionStatus encryptionStatus;
  final String? algorithmId;
  final String? keyReferenceId;
  final String? keyVersion;
  final String? envelopeReferenceId;
  final String? encryptedContentFingerprint;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'encryptionStatus': encryptionStatus.wireName,
        if (algorithmId != null) 'algorithmId': algorithmId,
        if (keyReferenceId != null) 'keyReferenceId': keyReferenceId,
        if (keyVersion != null) 'keyVersion': keyVersion,
        if (envelopeReferenceId != null)
          'envelopeReferenceId': envelopeReferenceId,
        if (encryptedContentFingerprint != null)
          'encryptedContentFingerprint': encryptedContentFingerprint,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PersistentArtifactEncryptionDescriptor.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersistentArtifactEncryptionDescriptor(
      encryptionStatus: PersistentArtifactEncryptionStatusX.fromWireName(
        json['encryptionStatus'] as String,
      ),
      algorithmId: json['algorithmId'] as String?,
      keyReferenceId: json['keyReferenceId'] as String?,
      keyVersion: json['keyVersion'] as String?,
      envelopeReferenceId: json['envelopeReferenceId'] as String?,
      encryptedContentFingerprint:
          json['encryptedContentFingerprint'] as String?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'encryptionStatus': encryptionStatus.wireName,
        if (algorithmId != null) 'algorithmId': algorithmId,
        if (keyReferenceId != null) 'keyReferenceId': keyReferenceId,
        if (keyVersion != null) 'keyVersion': keyVersion,
        if (envelopeReferenceId != null)
          'envelopeReferenceId': envelopeReferenceId,
        if (encryptedContentFingerprint != null)
          'encryptedContentFingerprint': encryptedContentFingerprint,
        if (metadata.isNotEmpty) 'metadata': paSortedStringMap(metadata),
      };

  PersistentArtifactEncryptionDescriptor copyWith({
    PersistentArtifactEncryptionStatus? encryptionStatus,
    String? algorithmId,
    String? keyReferenceId,
    String? keyVersion,
    String? envelopeReferenceId,
    String? encryptedContentFingerprint,
    Map<String, String>? metadata,
  }) {
    return PersistentArtifactEncryptionDescriptor(
      encryptionStatus: encryptionStatus ?? this.encryptionStatus,
      algorithmId: algorithmId ?? this.algorithmId,
      keyReferenceId: keyReferenceId ?? this.keyReferenceId,
      keyVersion: keyVersion ?? this.keyVersion,
      envelopeReferenceId: envelopeReferenceId ?? this.envelopeReferenceId,
      encryptedContentFingerprint:
          encryptedContentFingerprint ?? this.encryptedContentFingerprint,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactEncryptionDescriptor &&
          encryptionStatus == other.encryptionStatus &&
          algorithmId == other.algorithmId &&
          keyReferenceId == other.keyReferenceId &&
          keyVersion == other.keyVersion &&
          envelopeReferenceId == other.envelopeReferenceId &&
          encryptedContentFingerprint == other.encryptedContentFingerprint &&
          paMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        encryptionStatus,
        algorithmId,
        keyReferenceId,
        keyVersion,
        envelopeReferenceId,
        encryptedContentFingerprint,
        Object.hashAll(metadata.entries),
      );
}
