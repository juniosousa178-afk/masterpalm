import 'cryptographic_trust_digest.dart';
import 'cryptographic_trust_equality.dart';
import 'cryptographic_trust_enums.dart';
import 'cryptographic_trust_source_reference.dart';

/// Vendor-neutral transparency log reference — does not fetch or validate proofs.
class CryptographicTransparencyLogReference {
  const CryptographicTransparencyLogReference({
    required this.logId,
    required this.entryId,
    required this.logType,
    required this.status,
    required this.entryDigest,
    this.integratedTime,
    this.inclusionProofReference,
    this.checkpointReference,
    this.sourceReferences = const [],
    this.metadata = const {},
  });

  final String logId;
  final String entryId;
  final String logType;
  final CryptographicTransparencyLogStatus status;
  final String? integratedTime;
  final CryptographicDigest entryDigest;
  final String? inclusionProofReference;
  final String? checkpointReference;
  final List<CryptographicTrustSourceReference> sourceReferences;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'logId': logId,
        'entryId': entryId,
        'logType': logType,
        'status': status.wireName,
        if (integratedTime != null) 'integratedTime': integratedTime,
        'entryDigest': entryDigest.toJson(),
        if (inclusionProofReference != null)
          'inclusionProofReference': inclusionProofReference,
        if (checkpointReference != null)
          'checkpointReference': checkpointReference,
        if (sourceReferences.isNotEmpty)
          'sourceReferences': sourceReferences.map((e) => e.toJson()).toList(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory CryptographicTransparencyLogReference.fromJson(
    Map<String, dynamic> json,
  ) {
    return CryptographicTransparencyLogReference(
      logId: json['logId'] as String,
      entryId: json['entryId'] as String,
      logType: json['logType'] as String,
      status: CryptographicTransparencyLogStatusX.fromWireName(
        json['status'] as String,
      ),
      integratedTime: json['integratedTime'] as String?,
      entryDigest: CryptographicDigest.fromJson(
        json['entryDigest'] as Map<String, dynamic>,
      ),
      inclusionProofReference: json['inclusionProofReference'] as String?,
      checkpointReference: json['checkpointReference'] as String?,
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
        'logId': logId,
        'entryId': entryId,
        'logType': logType,
        'status': status.wireName,
        'entryDigest': entryDigest.toComparableJson(),
        if (inclusionProofReference != null)
          'inclusionProofReference': inclusionProofReference,
        if (checkpointReference != null)
          'checkpointReference': checkpointReference,
        if (sourceReferences.isNotEmpty)
          'sourceReferences': (sourceReferences
              .map((e) => e.toComparableJson())
              .toList()
            ..sort(
              (a, b) =>
                  a['sourceId'].toString().compareTo(b['sourceId'].toString()),
            )),
      };

  CryptographicTransparencyLogReference copyWith({
    String? logId,
    String? entryId,
    String? logType,
    CryptographicTransparencyLogStatus? status,
    String? integratedTime,
    CryptographicDigest? entryDigest,
    String? inclusionProofReference,
    String? checkpointReference,
    List<CryptographicTrustSourceReference>? sourceReferences,
    Map<String, String>? metadata,
  }) {
    return CryptographicTransparencyLogReference(
      logId: logId ?? this.logId,
      entryId: entryId ?? this.entryId,
      logType: logType ?? this.logType,
      status: status ?? this.status,
      integratedTime: integratedTime ?? this.integratedTime,
      entryDigest: entryDigest ?? this.entryDigest,
      inclusionProofReference:
          inclusionProofReference ?? this.inclusionProofReference,
      checkpointReference: checkpointReference ?? this.checkpointReference,
      sourceReferences: sourceReferences ?? this.sourceReferences,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CryptographicTransparencyLogReference &&
          logId == other.logId &&
          entryId == other.entryId &&
          logType == other.logType &&
          status == other.status &&
          integratedTime == other.integratedTime &&
          entryDigest == other.entryDigest &&
          inclusionProofReference == other.inclusionProofReference &&
          checkpointReference == other.checkpointReference &&
          trustListEquals(sourceReferences, other.sourceReferences) &&
          trustMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        logId,
        entryId,
        logType,
        status,
        integratedTime,
        entryDigest,
        inclusionProofReference,
        checkpointReference,
        Object.hashAll(sourceReferences),
        Object.hashAll(metadata.entries),
      );
}
