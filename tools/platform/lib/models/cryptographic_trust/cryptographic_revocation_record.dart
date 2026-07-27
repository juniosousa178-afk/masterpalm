import 'cryptographic_signer_identity.dart';
import 'cryptographic_trust_equality.dart';
import 'cryptographic_trust_enums.dart';
import 'cryptographic_trust_source_reference.dart';

/// Declarative revocation record — does not consult CRL, OCSP, or external services.
class CryptographicRevocationRecord {
  const CryptographicRevocationRecord({
    required this.revocationId,
    required this.subjectType,
    required this.subjectId,
    required this.status,
    this.reasonCode,
    this.reason,
    this.revokedAt,
    this.effectiveAt,
    this.issuerIdentity,
    this.sourceReferences = const [],
    this.metadata = const {},
  });

  final String revocationId;
  final CryptographicTrustSubjectType subjectType;
  final String subjectId;
  final CryptographicRevocationStatus status;
  final String? reasonCode;
  final String? reason;
  final String? revokedAt;
  final String? effectiveAt;
  final CryptographicSignerIdentity? issuerIdentity;
  final List<CryptographicTrustSourceReference> sourceReferences;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'revocationId': revocationId,
        'subjectType': subjectType.wireName,
        'subjectId': subjectId,
        'status': status.wireName,
        if (reasonCode != null) 'reasonCode': reasonCode,
        if (reason != null) 'reason': reason,
        if (revokedAt != null) 'revokedAt': revokedAt,
        if (effectiveAt != null) 'effectiveAt': effectiveAt,
        if (issuerIdentity != null) 'issuerIdentity': issuerIdentity!.toJson(),
        if (sourceReferences.isNotEmpty)
          'sourceReferences': sourceReferences.map((e) => e.toJson()).toList(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory CryptographicRevocationRecord.fromJson(Map<String, dynamic> json) {
    return CryptographicRevocationRecord(
      revocationId: json['revocationId'] as String,
      subjectType: CryptographicTrustSubjectTypeX.fromWireName(
        json['subjectType'] as String,
      ),
      subjectId: json['subjectId'] as String,
      status: CryptographicRevocationStatusX.fromWireName(
        json['status'] as String,
      ),
      reasonCode: json['reasonCode'] as String?,
      reason: json['reason'] as String?,
      revokedAt: json['revokedAt'] as String?,
      effectiveAt: json['effectiveAt'] as String?,
      issuerIdentity: json['issuerIdentity'] == null
          ? null
          : CryptographicSignerIdentity.fromJson(
              json['issuerIdentity'] as Map<String, dynamic>,
            ),
      sourceReferences: List.unmodifiable(
        (json['sourceReferences'] as List<dynamic>? ?? [])
            .map(
              (e) => CryptographicTrustSourceReference.fromJson(
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

  Map<String, dynamic> toComparableJson() => {
        'revocationId': revocationId,
        'subjectType': subjectType.wireName,
        'subjectId': subjectId,
        'status': status.wireName,
        if (reasonCode != null) 'reasonCode': reasonCode,
        if (reason != null) 'reason': reason,
        if (issuerIdentity != null)
          'issuerIdentity': issuerIdentity!.toComparableJson(),
        if (sourceReferences.isNotEmpty)
          'sourceReferences': (sourceReferences
              .map((e) => e.toComparableJson())
              .toList()
            ..sort(
              (a, b) =>
                  a['sourceId'].toString().compareTo(b['sourceId'].toString()),
            )),
      };

  CryptographicRevocationRecord copyWith({
    String? revocationId,
    CryptographicTrustSubjectType? subjectType,
    String? subjectId,
    CryptographicRevocationStatus? status,
    String? reasonCode,
    String? reason,
    String? revokedAt,
    String? effectiveAt,
    CryptographicSignerIdentity? issuerIdentity,
    List<CryptographicTrustSourceReference>? sourceReferences,
    Map<String, String>? metadata,
  }) {
    return CryptographicRevocationRecord(
      revocationId: revocationId ?? this.revocationId,
      subjectType: subjectType ?? this.subjectType,
      subjectId: subjectId ?? this.subjectId,
      status: status ?? this.status,
      reasonCode: reasonCode ?? this.reasonCode,
      reason: reason ?? this.reason,
      revokedAt: revokedAt ?? this.revokedAt,
      effectiveAt: effectiveAt ?? this.effectiveAt,
      issuerIdentity: issuerIdentity ?? this.issuerIdentity,
      sourceReferences: sourceReferences ?? this.sourceReferences,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CryptographicRevocationRecord &&
          revocationId == other.revocationId &&
          subjectType == other.subjectType &&
          subjectId == other.subjectId &&
          status == other.status &&
          reasonCode == other.reasonCode &&
          reason == other.reason &&
          revokedAt == other.revokedAt &&
          effectiveAt == other.effectiveAt &&
          issuerIdentity == other.issuerIdentity &&
          trustListEquals(sourceReferences, other.sourceReferences) &&
          trustMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        revocationId,
        subjectType,
        subjectId,
        status,
        reasonCode,
        reason,
        revokedAt,
        effectiveAt,
        issuerIdentity,
        Object.hashAll(sourceReferences),
        Object.hashAll(metadata.entries),
      );
}
