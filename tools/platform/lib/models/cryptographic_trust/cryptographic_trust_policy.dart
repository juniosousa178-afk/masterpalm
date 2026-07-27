import 'cryptographic_trust_anchor.dart';
import 'cryptographic_trust_equality.dart';
import 'cryptographic_trust_enums.dart';
import 'cryptographic_trust_requirement.dart';

/// Declarative cryptographic trust policy — not evaluated or applied in Part 1.
///
/// Policy presence does not authorize release. Domain fingerprint != signature.
class CryptographicTrustPolicy {
  const CryptographicTrustPolicy({
    required this.policyId,
    required this.version,
    required this.name,
    required this.description,
    required this.status,
    required this.requirements,
    required this.trustAnchors,
    required this.scope,
    required this.createdAt,
    this.effectiveFrom,
    this.deprecatedAt,
    this.retiredAt,
    this.metadata = const {},
  });

  final String policyId;
  final int version;
  final String name;
  final String description;
  final CryptographicPolicyStatus status;
  final List<CryptographicTrustRequirement> requirements;
  final List<CryptographicTrustAnchorReference> trustAnchors;
  final Map<String, String> scope;
  final String createdAt;
  final String? effectiveFrom;
  final String? deprecatedAt;
  final String? retiredAt;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'policyId': policyId,
        'version': version,
        'name': name,
        'description': description,
        'status': status.wireName,
        'requirements': requirements.map((e) => e.toJson()).toList(),
        'trustAnchors': trustAnchors.map((e) => e.toJson()).toList(),
        if (scope.isNotEmpty) 'scope': scope,
        'createdAt': createdAt,
        if (effectiveFrom != null) 'effectiveFrom': effectiveFrom,
        if (deprecatedAt != null) 'deprecatedAt': deprecatedAt,
        if (retiredAt != null) 'retiredAt': retiredAt,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory CryptographicTrustPolicy.fromJson(Map<String, dynamic> json) {
    return CryptographicTrustPolicy(
      policyId: json['policyId'] as String,
      version: json['version'] as int,
      name: json['name'] as String,
      description: json['description'] as String,
      status: CryptographicPolicyStatusX.fromWireName(
        json['status'] as String,
      ),
      requirements: List.unmodifiable(
        (json['requirements'] as List<dynamic>)
            .map(
              (e) => CryptographicTrustRequirement.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      trustAnchors: List.unmodifiable(
        (json['trustAnchors'] as List<dynamic>)
            .map(
              (e) => CryptographicTrustAnchorReference.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      scope: Map.unmodifiable(
        (json['scope'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
      createdAt: json['createdAt'] as String,
      effectiveFrom: json['effectiveFrom'] as String?,
      deprecatedAt: json['deprecatedAt'] as String?,
      retiredAt: json['retiredAt'] as String?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'policyId': policyId,
        'version': version,
        'name': name,
        'description': description,
        'status': status.wireName,
        'requirements': (requirements.map((e) => e.toComparableJson()).toList()
          ..sort(
            (a, b) => a['requirementId']
                .toString()
                .compareTo(b['requirementId'].toString()),
          )),
        'trustAnchors': (trustAnchors.map((e) => e.toComparableJson()).toList()
          ..sort(
            (a, b) => a['trustAnchorId']
                .toString()
                .compareTo(b['trustAnchorId'].toString()),
          )),
        if (scope.isNotEmpty)
          'scope': Map.fromEntries(
            scope.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
          ),
        if (effectiveFrom != null) 'effectiveFrom': effectiveFrom,
        if (deprecatedAt != null) 'deprecatedAt': deprecatedAt,
        if (retiredAt != null) 'retiredAt': retiredAt,
      };

  CryptographicTrustPolicy copyWith({
    String? policyId,
    int? version,
    String? name,
    String? description,
    CryptographicPolicyStatus? status,
    List<CryptographicTrustRequirement>? requirements,
    List<CryptographicTrustAnchorReference>? trustAnchors,
    Map<String, String>? scope,
    String? createdAt,
    String? effectiveFrom,
    String? deprecatedAt,
    String? retiredAt,
    Map<String, String>? metadata,
  }) {
    return CryptographicTrustPolicy(
      policyId: policyId ?? this.policyId,
      version: version ?? this.version,
      name: name ?? this.name,
      description: description ?? this.description,
      status: status ?? this.status,
      requirements: requirements ?? this.requirements,
      trustAnchors: trustAnchors ?? this.trustAnchors,
      scope: scope ?? this.scope,
      createdAt: createdAt ?? this.createdAt,
      effectiveFrom: effectiveFrom ?? this.effectiveFrom,
      deprecatedAt: deprecatedAt ?? this.deprecatedAt,
      retiredAt: retiredAt ?? this.retiredAt,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CryptographicTrustPolicy &&
          policyId == other.policyId &&
          version == other.version &&
          name == other.name &&
          description == other.description &&
          status == other.status &&
          trustListEquals(requirements, other.requirements) &&
          trustListEquals(trustAnchors, other.trustAnchors) &&
          trustMapEquals(scope, other.scope) &&
          createdAt == other.createdAt &&
          effectiveFrom == other.effectiveFrom &&
          deprecatedAt == other.deprecatedAt &&
          retiredAt == other.retiredAt &&
          trustMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        policyId,
        version,
        name,
        description,
        status,
        Object.hashAll(requirements),
        Object.hashAll(trustAnchors),
        Object.hashAll(scope.entries),
        createdAt,
        effectiveFrom,
        deprecatedAt,
        retiredAt,
        Object.hashAll(metadata.entries),
      );
}
