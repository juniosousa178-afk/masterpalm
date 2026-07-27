import '../cicd_integration/cicd_integration_snapshot.dart';
import '../release_evidence/release_evidence_bundle.dart';
import '../release_supply_chain/release_supply_chain_snapshot.dart';
import 'cryptographic_trust_equality.dart';
import 'cryptographic_trust_policy_reference.dart';
import 'cryptographic_verification_models.dart';

/// Request to evaluate cryptographic trust for verification subjects.
///
/// Wraps [verificationRequest] needs with policy selection and injected sources.
/// Evaluation does not authorize release.
class CryptographicTrustEvaluationRequest {
  const CryptographicTrustEvaluationRequest({
    required this.evaluationId,
    required this.projectId,
    required this.requestedAt,
    required this.verificationRequest,
    this.releaseId,
    this.policyReference,
    this.useLatest = false,
    this.releaseEvidenceBundle,
    this.releaseSupplyChainSnapshot,
    this.cicdIntegrationSnapshot,
    this.metadata = const {},
  });

  final String evaluationId;
  final String projectId;
  final String? releaseId;
  final CryptographicVerificationRequest verificationRequest;
  final CryptographicTrustPolicyReference? policyReference;
  final bool useLatest;
  final String requestedAt;
  final ReleaseEvidenceBundle? releaseEvidenceBundle;
  final ReleaseSupplyChainSnapshot? releaseSupplyChainSnapshot;
  final CicdIntegrationSnapshot? cicdIntegrationSnapshot;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'evaluationId': evaluationId,
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        'verificationRequest': verificationRequest.toJson(),
        if (policyReference != null)
          'policyReference': policyReference!.toJson(),
        'useLatest': useLatest,
        'requestedAt': requestedAt,
        if (releaseEvidenceBundle != null)
          'releaseEvidenceBundle': releaseEvidenceBundle!.toJson(),
        if (releaseSupplyChainSnapshot != null)
          'releaseSupplyChainSnapshot': releaseSupplyChainSnapshot!.toJson(),
        if (cicdIntegrationSnapshot != null)
          'cicdIntegrationSnapshot': cicdIntegrationSnapshot!.toJson(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory CryptographicTrustEvaluationRequest.fromJson(
    Map<String, dynamic> json,
  ) {
    return CryptographicTrustEvaluationRequest(
      evaluationId: json['evaluationId'] as String,
      projectId: json['projectId'] as String,
      releaseId: json['releaseId'] as String?,
      verificationRequest: CryptographicVerificationRequest.fromJson(
        json['verificationRequest'] as Map<String, dynamic>,
      ),
      policyReference: json['policyReference'] == null
          ? null
          : CryptographicTrustPolicyReference.fromJson(
              json['policyReference'] as Map<String, dynamic>,
            ),
      useLatest: json['useLatest'] as bool? ?? false,
      requestedAt: json['requestedAt'] as String,
      releaseEvidenceBundle: json['releaseEvidenceBundle'] == null
          ? null
          : ReleaseEvidenceBundle.fromJson(
              json['releaseEvidenceBundle'] as Map<String, dynamic>,
            ),
      releaseSupplyChainSnapshot: json['releaseSupplyChainSnapshot'] == null
          ? null
          : ReleaseSupplyChainSnapshot.fromJson(
              json['releaseSupplyChainSnapshot'] as Map<String, dynamic>,
            ),
      cicdIntegrationSnapshot: json['cicdIntegrationSnapshot'] == null
          ? null
          : CicdIntegrationSnapshot.fromJson(
              json['cicdIntegrationSnapshot'] as Map<String, dynamic>,
            ),
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'evaluationId': evaluationId,
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        'verificationRequest': verificationRequest.toComparableJson(),
        if (policyReference != null)
          'policyReference': policyReference!.toComparableJson(),
        if (releaseEvidenceBundle != null)
          'releaseEvidenceBundleFingerprint':
              releaseEvidenceBundle!.fingerprint,
        if (releaseSupplyChainSnapshot != null)
          'releaseSupplyChainSnapshotFingerprint':
              releaseSupplyChainSnapshot!.fingerprint,
        if (cicdIntegrationSnapshot != null)
          'cicdIntegrationSnapshotFingerprint':
              cicdIntegrationSnapshot!.fingerprint,
      };

  CryptographicTrustEvaluationRequest copyWith({
    String? evaluationId,
    String? projectId,
    String? releaseId,
    CryptographicVerificationRequest? verificationRequest,
    CryptographicTrustPolicyReference? policyReference,
    bool? useLatest,
    String? requestedAt,
    ReleaseEvidenceBundle? releaseEvidenceBundle,
    ReleaseSupplyChainSnapshot? releaseSupplyChainSnapshot,
    CicdIntegrationSnapshot? cicdIntegrationSnapshot,
    Map<String, String>? metadata,
  }) {
    return CryptographicTrustEvaluationRequest(
      evaluationId: evaluationId ?? this.evaluationId,
      projectId: projectId ?? this.projectId,
      releaseId: releaseId ?? this.releaseId,
      verificationRequest: verificationRequest ?? this.verificationRequest,
      policyReference: policyReference ?? this.policyReference,
      useLatest: useLatest ?? this.useLatest,
      requestedAt: requestedAt ?? this.requestedAt,
      releaseEvidenceBundle:
          releaseEvidenceBundle ?? this.releaseEvidenceBundle,
      releaseSupplyChainSnapshot:
          releaseSupplyChainSnapshot ?? this.releaseSupplyChainSnapshot,
      cicdIntegrationSnapshot:
          cicdIntegrationSnapshot ?? this.cicdIntegrationSnapshot,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CryptographicTrustEvaluationRequest &&
          evaluationId == other.evaluationId &&
          projectId == other.projectId &&
          releaseId == other.releaseId &&
          verificationRequest == other.verificationRequest &&
          policyReference == other.policyReference &&
          useLatest == other.useLatest &&
          requestedAt == other.requestedAt &&
          releaseEvidenceBundle == other.releaseEvidenceBundle &&
          releaseSupplyChainSnapshot == other.releaseSupplyChainSnapshot &&
          cicdIntegrationSnapshot == other.cicdIntegrationSnapshot &&
          trustMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        evaluationId,
        projectId,
        releaseId,
        verificationRequest,
        policyReference,
        useLatest,
        requestedAt,
        releaseEvidenceBundle,
        releaseSupplyChainSnapshot,
        cicdIntegrationSnapshot,
        Object.hashAll(metadata.entries),
      );
}
