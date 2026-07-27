import 'cryptographic_key_reference.dart';
import 'cryptographic_signer_identity.dart';
import 'cryptographic_trust_algorithm_descriptors.dart';
import 'cryptographic_trust_anchor.dart';
import 'cryptographic_trust_digest.dart';
import 'cryptographic_trust_equality.dart';
import 'cryptographic_trust_subject.dart';

Map<String, String> _sortedStringMap(Map<String, String> input) {
  if (input.isEmpty) return const {};
  return Map.fromEntries(
    input.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
}

List<Map<String, String>> _sortedSourceReferences(
  List<Map<String, String>> input,
) {
  if (input.isEmpty) return const [];
  final copies =
      input.map((e) => _sortedStringMap(Map<String, String>.from(e))).toList()
        ..sort((a, b) {
          final aId = a['sourceId'] ?? '';
          final bId = b['sourceId'] ?? '';
          return aId.compareTo(bId);
        });
  return List<Map<String, String>>.unmodifiable(copies);
}

/// Existing signature envelope — does not sign, verify, or authorize release.
///
/// [signatureValue] is public signature data, never a secret.
/// [signedAt] and [expiresAt] are excluded from [toComparableJson].
/// Domain fingerprint != cryptographic signature.
class CryptographicSignatureEnvelope {
  const CryptographicSignatureEnvelope({
    required this.signatureId,
    required this.subject,
    required this.subjectDigest,
    required this.signatureDescriptor,
    required this.signatureValue,
    required this.signatureEncoding,
    required this.keyReference,
    this.signerIdentity,
    this.signedAt,
    this.expiresAt,
    this.trustAnchorReference,
    this.sourceReferences = const [],
    this.metadata = const {},
  });

  final String signatureId;
  final CryptographicTrustSubject subject;
  final CryptographicDigest subjectDigest;
  final CryptographicSignatureDescriptor signatureDescriptor;
  final String signatureValue;
  final String signatureEncoding;
  final CryptographicKeyReference keyReference;
  final CryptographicSignerIdentity? signerIdentity;
  final String? signedAt;
  final String? expiresAt;
  final CryptographicTrustAnchorReference? trustAnchorReference;
  final List<Map<String, String>> sourceReferences;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'signatureId': signatureId,
        'subject': subject.toJson(),
        'subjectDigest': subjectDigest.toJson(),
        'signatureDescriptor': signatureDescriptor.toJson(),
        'signatureValue': signatureValue,
        'signatureEncoding': signatureEncoding,
        'keyReference': keyReference.toJson(),
        if (signerIdentity != null) 'signerIdentity': signerIdentity!.toJson(),
        if (signedAt != null) 'signedAt': signedAt,
        if (expiresAt != null) 'expiresAt': expiresAt,
        if (trustAnchorReference != null)
          'trustAnchorReference': trustAnchorReference!.toJson(),
        if (sourceReferences.isNotEmpty) 'sourceReferences': sourceReferences,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory CryptographicSignatureEnvelope.fromJson(Map<String, dynamic> json) {
    return CryptographicSignatureEnvelope(
      signatureId: json['signatureId'] as String,
      subject: CryptographicTrustSubject.fromJson(
        json['subject'] as Map<String, dynamic>,
      ),
      subjectDigest: CryptographicDigest.fromJson(
        json['subjectDigest'] as Map<String, dynamic>,
      ),
      signatureDescriptor: CryptographicSignatureDescriptor.fromJson(
        json['signatureDescriptor'] as Map<String, dynamic>,
      ),
      signatureValue: json['signatureValue'] as String,
      signatureEncoding: json['signatureEncoding'] as String,
      keyReference: CryptographicKeyReference.fromJson(
        json['keyReference'] as Map<String, dynamic>,
      ),
      signerIdentity: json['signerIdentity'] == null
          ? null
          : CryptographicSignerIdentity.fromJson(
              json['signerIdentity'] as Map<String, dynamic>,
            ),
      signedAt: json['signedAt'] as String?,
      expiresAt: json['expiresAt'] as String?,
      trustAnchorReference: json['trustAnchorReference'] == null
          ? null
          : CryptographicTrustAnchorReference.fromJson(
              json['trustAnchorReference'] as Map<String, dynamic>,
            ),
      sourceReferences: List.unmodifiable(
        (json['sourceReferences'] as List<dynamic>? ?? [])
            .map(
              (e) => Map<String, String>.unmodifiable(
                Map<String, String>.from(
                  (e as Map).map(
                    (k, v) => MapEntry(k.toString(), v.toString()),
                  ),
                ),
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

  Map<String, dynamic> toComparableJson() => {
        'signatureId': signatureId,
        'subject': subject.toComparableJson(),
        'subjectDigest': subjectDigest.toComparableJson(),
        'signatureDescriptor': signatureDescriptor.toComparableJson(),
        'signatureValue': signatureValue,
        'signatureEncoding': signatureEncoding,
        'keyReference': keyReference.toComparableJson(),
        if (signerIdentity != null)
          'signerIdentity': signerIdentity!.toComparableJson(),
        if (trustAnchorReference != null)
          'trustAnchorReference': trustAnchorReference!.toComparableJson(),
        if (sourceReferences.isNotEmpty)
          'sourceReferences': _sortedSourceReferences(sourceReferences),
        if (metadata.isNotEmpty) 'metadata': _sortedStringMap(metadata),
      };

  CryptographicSignatureEnvelope copyWith({
    String? signatureId,
    CryptographicTrustSubject? subject,
    CryptographicDigest? subjectDigest,
    CryptographicSignatureDescriptor? signatureDescriptor,
    String? signatureValue,
    String? signatureEncoding,
    CryptographicKeyReference? keyReference,
    CryptographicSignerIdentity? signerIdentity,
    String? signedAt,
    String? expiresAt,
    CryptographicTrustAnchorReference? trustAnchorReference,
    List<Map<String, String>>? sourceReferences,
    Map<String, String>? metadata,
  }) {
    return CryptographicSignatureEnvelope(
      signatureId: signatureId ?? this.signatureId,
      subject: subject ?? this.subject,
      subjectDigest: subjectDigest ?? this.subjectDigest,
      signatureDescriptor: signatureDescriptor ?? this.signatureDescriptor,
      signatureValue: signatureValue ?? this.signatureValue,
      signatureEncoding: signatureEncoding ?? this.signatureEncoding,
      keyReference: keyReference ?? this.keyReference,
      signerIdentity: signerIdentity ?? this.signerIdentity,
      signedAt: signedAt ?? this.signedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      trustAnchorReference: trustAnchorReference ?? this.trustAnchorReference,
      sourceReferences: sourceReferences ?? this.sourceReferences,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CryptographicSignatureEnvelope &&
          signatureId == other.signatureId &&
          subject == other.subject &&
          subjectDigest == other.subjectDigest &&
          signatureDescriptor == other.signatureDescriptor &&
          signatureValue == other.signatureValue &&
          signatureEncoding == other.signatureEncoding &&
          keyReference == other.keyReference &&
          signerIdentity == other.signerIdentity &&
          signedAt == other.signedAt &&
          expiresAt == other.expiresAt &&
          trustAnchorReference == other.trustAnchorReference &&
          _sourceReferencesEqual(sourceReferences, other.sourceReferences) &&
          trustMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        signatureId,
        subject,
        subjectDigest,
        signatureDescriptor,
        signatureValue,
        signatureEncoding,
        keyReference,
        signerIdentity,
        signedAt,
        expiresAt,
        trustAnchorReference,
        Object.hashAll(
          sourceReferences.map((m) => Object.hashAll(m.entries)),
        ),
        Object.hashAll(metadata.entries),
      );
}

bool _sourceReferencesEqual(
  List<Map<String, String>> a,
  List<Map<String, String>> b,
) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!trustMapEquals(a[i], b[i])) return false;
  }
  return true;
}
