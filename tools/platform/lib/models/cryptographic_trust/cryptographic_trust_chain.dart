import 'cryptographic_key_reference.dart';
import 'cryptographic_trust_anchor.dart';
import 'cryptographic_trust_equality.dart';
import 'cryptographic_trust_enums.dart';
import 'cryptographic_verification_models.dart';

/// Declarative trust chain — does not validate certificates or build paths.
///
/// Chain presence does not imply automatic trust or release authorization.
class CryptographicTrustChain {
  const CryptographicTrustChain({
    required this.trustChainId,
    required this.subjectId,
    required this.leafKey,
    required this.trustAnchor,
    required this.status,
    this.signatureId,
    this.intermediateReferences = const [],
    this.issues = const [],
    this.metadata = const {},
  });

  final String trustChainId;
  final String subjectId;
  final String? signatureId;
  final CryptographicKeyReference leafKey;
  final List<CryptographicKeyReference> intermediateReferences;
  final CryptographicTrustAnchorReference trustAnchor;
  final CryptographicTrustStatus status;
  final List<CryptographicVerificationIssue> issues;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'trustChainId': trustChainId,
        'subjectId': subjectId,
        if (signatureId != null) 'signatureId': signatureId,
        'leafKey': leafKey.toJson(),
        if (intermediateReferences.isNotEmpty)
          'intermediateReferences':
              intermediateReferences.map((e) => e.toJson()).toList(),
        'trustAnchor': trustAnchor.toJson(),
        'status': status.wireName,
        if (issues.isNotEmpty) 'issues': issues.map((e) => e.toJson()).toList(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory CryptographicTrustChain.fromJson(Map<String, dynamic> json) {
    return CryptographicTrustChain(
      trustChainId: json['trustChainId'] as String,
      subjectId: json['subjectId'] as String,
      signatureId: json['signatureId'] as String?,
      leafKey: CryptographicKeyReference.fromJson(
        json['leafKey'] as Map<String, dynamic>,
      ),
      intermediateReferences: List.unmodifiable(
        (json['intermediateReferences'] as List<dynamic>? ?? [])
            .map(
              (e) => CryptographicKeyReference.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      trustAnchor: CryptographicTrustAnchorReference.fromJson(
        json['trustAnchor'] as Map<String, dynamic>,
      ),
      status: CryptographicTrustStatusX.fromWireName(
        json['status'] as String,
      ),
      issues: List.unmodifiable(
        (json['issues'] as List<dynamic>? ?? [])
            .map(
              (e) => CryptographicVerificationIssue.fromJson(
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
        'trustChainId': trustChainId,
        'subjectId': subjectId,
        if (signatureId != null) 'signatureId': signatureId,
        'leafKey': leafKey.toComparableJson(),
        if (intermediateReferences.isNotEmpty)
          'intermediateReferences': (intermediateReferences
              .map((e) => e.toComparableJson())
              .toList()
            ..sort(
              (a, b) => a['keyId'].toString().compareTo(b['keyId'].toString()),
            )),
        'trustAnchor': trustAnchor.toComparableJson(),
        'status': status.wireName,
        if (issues.isNotEmpty)
          'issues': (issues.map((e) => e.toComparableJson()).toList()
            ..sort(
              (a, b) => a['code'].toString().compareTo(b['code'].toString()),
            )),
      };

  CryptographicTrustChain copyWith({
    String? trustChainId,
    String? subjectId,
    String? signatureId,
    CryptographicKeyReference? leafKey,
    List<CryptographicKeyReference>? intermediateReferences,
    CryptographicTrustAnchorReference? trustAnchor,
    CryptographicTrustStatus? status,
    List<CryptographicVerificationIssue>? issues,
    Map<String, String>? metadata,
  }) {
    return CryptographicTrustChain(
      trustChainId: trustChainId ?? this.trustChainId,
      subjectId: subjectId ?? this.subjectId,
      signatureId: signatureId ?? this.signatureId,
      leafKey: leafKey ?? this.leafKey,
      intermediateReferences:
          intermediateReferences ?? this.intermediateReferences,
      trustAnchor: trustAnchor ?? this.trustAnchor,
      status: status ?? this.status,
      issues: issues ?? this.issues,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CryptographicTrustChain &&
          trustChainId == other.trustChainId &&
          subjectId == other.subjectId &&
          signatureId == other.signatureId &&
          leafKey == other.leafKey &&
          trustListEquals(
              intermediateReferences, other.intermediateReferences) &&
          trustAnchor == other.trustAnchor &&
          status == other.status &&
          trustListEquals(issues, other.issues) &&
          trustMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        trustChainId,
        subjectId,
        signatureId,
        leafKey,
        Object.hashAll(intermediateReferences),
        trustAnchor,
        status,
        Object.hashAll(issues),
        Object.hashAll(metadata.entries),
      );
}
