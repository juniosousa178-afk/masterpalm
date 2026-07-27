import 'collected_cryptographic_trust_material.dart';
import 'cryptographic_trust_equality.dart';
import 'cryptographic_trust_evaluation_request.dart';
import 'cryptographic_trust_operational_enums.dart';
import 'cryptographic_trust_policy.dart';
import 'cryptographic_trust_policy_reference.dart';
import 'resolved_cryptographic_trust_sources.dart';

/// Evaluation context passed through the cryptographic trust pipeline.
///
/// Context does not authorize release or deployment.
class CryptographicOperationContext {
  const CryptographicOperationContext({
    required this.operation,
    required this.request,
    required this.sources,
    required this.material,
    this.policy,
    this.policyReference,
    this.metadata = const {},
  });

  final CryptographicTrustOperation operation;
  final CryptographicTrustEvaluationRequest request;
  final ResolvedCryptographicTrustSources sources;
  final CollectedCryptographicTrustMaterial material;
  final CryptographicTrustPolicy? policy;
  final CryptographicTrustPolicyReference? policyReference;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'operation': operation.wireName,
        'request': request.toJson(),
        'sources': sources.toJson(),
        'material': material.toJson(),
        if (policy != null) 'policy': policy!.toJson(),
        if (policyReference != null)
          'policyReference': policyReference!.toJson(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory CryptographicOperationContext.fromJson(Map<String, dynamic> json) {
    return CryptographicOperationContext(
      operation: CryptographicTrustOperationX.fromWireName(
        json['operation'] as String,
      ),
      request: CryptographicTrustEvaluationRequest.fromJson(
        json['request'] as Map<String, dynamic>,
      ),
      sources: ResolvedCryptographicTrustSources.fromJson(
        json['sources'] as Map<String, dynamic>,
      ),
      material: CollectedCryptographicTrustMaterial.fromJson(
        json['material'] as Map<String, dynamic>,
      ),
      policy: json['policy'] == null
          ? null
          : CryptographicTrustPolicy.fromJson(
              json['policy'] as Map<String, dynamic>,
            ),
      policyReference: json['policyReference'] == null
          ? null
          : CryptographicTrustPolicyReference.fromJson(
              json['policyReference'] as Map<String, dynamic>,
            ),
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'operation': operation.wireName,
        'request': request.toComparableJson(),
        'sources': sources.toComparableJson(),
        'material': material.toComparableJson(),
        if (policy != null) 'policy': policy!.toComparableJson(),
        if (policyReference != null)
          'policyReference': policyReference!.toComparableJson(),
      };

  CryptographicOperationContext copyWith({
    CryptographicTrustOperation? operation,
    CryptographicTrustEvaluationRequest? request,
    ResolvedCryptographicTrustSources? sources,
    CollectedCryptographicTrustMaterial? material,
    CryptographicTrustPolicy? policy,
    CryptographicTrustPolicyReference? policyReference,
    Map<String, String>? metadata,
  }) {
    return CryptographicOperationContext(
      operation: operation ?? this.operation,
      request: request ?? this.request,
      sources: sources ?? this.sources,
      material: material ?? this.material,
      policy: policy ?? this.policy,
      policyReference: policyReference ?? this.policyReference,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CryptographicOperationContext &&
          operation == other.operation &&
          request == other.request &&
          sources == other.sources &&
          material == other.material &&
          policy == other.policy &&
          policyReference == other.policyReference &&
          trustMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        operation,
        request,
        sources,
        material,
        policy,
        policyReference,
        Object.hashAll(metadata.entries),
      );
}
