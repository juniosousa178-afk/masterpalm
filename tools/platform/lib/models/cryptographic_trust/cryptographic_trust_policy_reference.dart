import 'cryptographic_trust_equality.dart';
import 'cryptographic_trust_enums.dart';

/// Reference to a resolved cryptographic trust policy.
///
/// Policy resolution does not authorize release.
class CryptographicTrustPolicyReference {
  const CryptographicTrustPolicyReference({
    required this.policyId,
    required this.policyVersion,
    required this.status,
    this.explicitSelection = false,
    this.metadata = const {},
  });

  final String policyId;
  final int policyVersion;
  final CryptographicPolicyStatus status;
  final bool explicitSelection;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'policyId': policyId,
        'policyVersion': policyVersion,
        'status': status.wireName,
        if (explicitSelection) 'explicitSelection': explicitSelection,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory CryptographicTrustPolicyReference.fromJson(
    Map<String, dynamic> json,
  ) {
    return CryptographicTrustPolicyReference(
      policyId: json['policyId'] as String,
      policyVersion: json['policyVersion'] as int,
      status: CryptographicPolicyStatusX.fromWireName(
        json['status'] as String,
      ),
      explicitSelection: json['explicitSelection'] as bool? ?? false,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'policyId': policyId,
        'policyVersion': policyVersion,
        'status': status.wireName,
        if (explicitSelection) 'explicitSelection': explicitSelection,
      };

  CryptographicTrustPolicyReference copyWith({
    String? policyId,
    int? policyVersion,
    CryptographicPolicyStatus? status,
    bool? explicitSelection,
    Map<String, String>? metadata,
  }) {
    return CryptographicTrustPolicyReference(
      policyId: policyId ?? this.policyId,
      policyVersion: policyVersion ?? this.policyVersion,
      status: status ?? this.status,
      explicitSelection: explicitSelection ?? this.explicitSelection,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CryptographicTrustPolicyReference &&
          policyId == other.policyId &&
          policyVersion == other.policyVersion &&
          status == other.status &&
          explicitSelection == other.explicitSelection &&
          trustMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        policyId,
        policyVersion,
        status,
        explicitSelection,
        Object.hashAll(metadata.entries),
      );
}
