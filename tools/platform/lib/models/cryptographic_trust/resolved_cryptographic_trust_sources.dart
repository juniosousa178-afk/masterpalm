import '../cicd_integration/cicd_integration_snapshot.dart';
import '../release_evidence/release_evidence_bundle.dart';
import '../release_supply_chain/release_supply_chain_snapshot.dart';
import 'cryptographic_trust_equality.dart';
import 'cryptographic_trust_enums.dart';
import 'cryptographic_trust_evaluation_result.dart';
import 'cryptographic_trust_operational_enums.dart';
import 'cryptographic_trust_operation_message.dart';
import 'cryptographic_trust_policy.dart';
import 'cryptographic_trust_source_reference.dart';
import 'cryptographic_verification_models.dart';

/// Wrapper for a resolved cryptographic trust source artifact.
class ResolvedCryptographicTrustSource<T> {
  const ResolvedCryptographicTrustSource({
    required this.sourceType,
    required this.resolutionMode,
    required this.state,
    this.requestedId,
    this.resolvedArtifact,
    this.resolvedId,
    this.fingerprint,
    this.projectId,
    this.releaseId,
    this.policyId,
    this.policyVersion,
    this.messages = const [],
    this.metadata = const {},
  });

  final CryptographicSourceType sourceType;
  final CryptographicTrustSourceResolutionMode resolutionMode;
  final CryptographicTrustSourceState state;
  final String? requestedId;
  final T? resolvedArtifact;
  final String? resolvedId;
  final String? fingerprint;
  final String? projectId;
  final String? releaseId;
  final String? policyId;
  final int? policyVersion;
  final List<CryptographicTrustOperationMessage> messages;
  final Map<String, String> metadata;

  bool get isAvailable =>
      state == CryptographicTrustSourceState.available &&
      resolvedArtifact != null;

  Map<String, dynamic> toJson() => {
        'sourceType': sourceType.wireName,
        'resolutionMode': resolutionMode.wireName,
        'state': state.wireName,
        if (requestedId != null) 'requestedId': requestedId,
        if (resolvedId != null) 'resolvedId': resolvedId,
        if (fingerprint != null) 'fingerprint': fingerprint,
        if (projectId != null) 'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        if (policyId != null) 'policyId': policyId,
        if (policyVersion != null) 'policyVersion': policyVersion,
        if (messages.isNotEmpty)
          'messages': messages.map((e) => e.toJson()).toList(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory ResolvedCryptographicTrustSource.fromJson(
    Map<String, dynamic> json,
  ) {
    return ResolvedCryptographicTrustSource<T>(
      sourceType: CryptographicSourceTypeX.fromWireName(
        json['sourceType'] as String,
      ),
      resolutionMode: CryptographicTrustSourceResolutionModeX.fromWireName(
        json['resolutionMode'] as String,
      ),
      state: CryptographicTrustSourceStateX.fromWireName(
        json['state'] as String,
      ),
      requestedId: json['requestedId'] as String?,
      resolvedId: json['resolvedId'] as String?,
      fingerprint: json['fingerprint'] as String?,
      projectId: json['projectId'] as String?,
      releaseId: json['releaseId'] as String?,
      policyId: json['policyId'] as String?,
      policyVersion: json['policyVersion'] as int?,
      messages: List.unmodifiable(
        (json['messages'] as List<dynamic>? ?? [])
            .map(
              (e) => CryptographicTrustOperationMessage.fromJson(
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
        'sourceType': sourceType.wireName,
        'resolutionMode': resolutionMode.wireName,
        'state': state.wireName,
        if (requestedId != null) 'requestedId': requestedId,
        if (resolvedId != null) 'resolvedId': resolvedId,
        if (fingerprint != null) 'fingerprint': fingerprint,
        if (projectId != null) 'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        if (policyId != null) 'policyId': policyId,
        if (policyVersion != null) 'policyVersion': policyVersion,
      };

  ResolvedCryptographicTrustSource<T> copyWith({
    CryptographicSourceType? sourceType,
    CryptographicTrustSourceResolutionMode? resolutionMode,
    CryptographicTrustSourceState? state,
    String? requestedId,
    T? resolvedArtifact,
    String? resolvedId,
    String? fingerprint,
    String? projectId,
    String? releaseId,
    String? policyId,
    int? policyVersion,
    List<CryptographicTrustOperationMessage>? messages,
    Map<String, String>? metadata,
  }) {
    return ResolvedCryptographicTrustSource<T>(
      sourceType: sourceType ?? this.sourceType,
      resolutionMode: resolutionMode ?? this.resolutionMode,
      state: state ?? this.state,
      requestedId: requestedId ?? this.requestedId,
      resolvedArtifact: resolvedArtifact ?? this.resolvedArtifact,
      resolvedId: resolvedId ?? this.resolvedId,
      fingerprint: fingerprint ?? this.fingerprint,
      projectId: projectId ?? this.projectId,
      releaseId: releaseId ?? this.releaseId,
      policyId: policyId ?? this.policyId,
      policyVersion: policyVersion ?? this.policyVersion,
      messages: messages ?? this.messages,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResolvedCryptographicTrustSource<T> &&
          sourceType == other.sourceType &&
          resolutionMode == other.resolutionMode &&
          state == other.state &&
          requestedId == other.requestedId &&
          resolvedArtifact == other.resolvedArtifact &&
          resolvedId == other.resolvedId &&
          fingerprint == other.fingerprint &&
          projectId == other.projectId &&
          releaseId == other.releaseId &&
          policyId == other.policyId &&
          policyVersion == other.policyVersion &&
          trustListEquals(messages, other.messages) &&
          trustMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        sourceType,
        resolutionMode,
        state,
        requestedId,
        resolvedArtifact,
        resolvedId,
        fingerprint,
        projectId,
        releaseId,
        policyId,
        policyVersion,
        Object.hashAll(messages),
        Object.hashAll(metadata.entries),
      );
}

/// Container for all resolved cryptographic trust sources.
class ResolvedCryptographicTrustSources {
  const ResolvedCryptographicTrustSources({
    required this.verificationRequest,
    required this.releaseEvidenceBundle,
    required this.releaseSupplyChainSnapshot,
    required this.cicdIntegrationSnapshot,
    required this.trustPolicy,
    required this.sourceReferences,
    required this.resolutionSummary,
    this.messages = const [],
    this.compatibilityHints = const [],
    this.metadata = const {},
  });

  final ResolvedCryptographicTrustSource<CryptographicVerificationRequest>
      verificationRequest;
  final ResolvedCryptographicTrustSource<ReleaseEvidenceBundle>
      releaseEvidenceBundle;
  final ResolvedCryptographicTrustSource<ReleaseSupplyChainSnapshot>
      releaseSupplyChainSnapshot;
  final ResolvedCryptographicTrustSource<CicdIntegrationSnapshot>
      cicdIntegrationSnapshot;
  final ResolvedCryptographicTrustSource<CryptographicTrustPolicy> trustPolicy;
  final List<CryptographicTrustSourceReference> sourceReferences;
  final CryptographicTrustSourceResolutionSummary resolutionSummary;
  final List<CryptographicTrustOperationMessage> messages;
  final List<String> compatibilityHints;
  final Map<String, String> metadata;

  List<ResolvedCryptographicTrustSource<dynamic>> get allSources => [
        verificationRequest,
        releaseEvidenceBundle,
        releaseSupplyChainSnapshot,
        cicdIntegrationSnapshot,
        trustPolicy,
      ];

  Map<String, dynamic> toJson() => {
        'verificationRequest': verificationRequest.toJson(),
        'releaseEvidenceBundle': releaseEvidenceBundle.toJson(),
        'releaseSupplyChainSnapshot': releaseSupplyChainSnapshot.toJson(),
        'cicdIntegrationSnapshot': cicdIntegrationSnapshot.toJson(),
        'trustPolicy': trustPolicy.toJson(),
        'sourceReferences': sourceReferences.map((e) => e.toJson()).toList(),
        'resolutionSummary': resolutionSummary.toJson(),
        if (messages.isNotEmpty)
          'messages': messages.map((e) => e.toJson()).toList(),
        if (compatibilityHints.isNotEmpty)
          'compatibilityHints': compatibilityHints,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory ResolvedCryptographicTrustSources.fromJson(
      Map<String, dynamic> json) {
    return ResolvedCryptographicTrustSources(
      verificationRequest: ResolvedCryptographicTrustSource<
          CryptographicVerificationRequest>.fromJson(
        json['verificationRequest'] as Map<String, dynamic>,
      ),
      releaseEvidenceBundle:
          ResolvedCryptographicTrustSource<ReleaseEvidenceBundle>.fromJson(
        json['releaseEvidenceBundle'] as Map<String, dynamic>,
      ),
      releaseSupplyChainSnapshot:
          ResolvedCryptographicTrustSource<ReleaseSupplyChainSnapshot>.fromJson(
        json['releaseSupplyChainSnapshot'] as Map<String, dynamic>,
      ),
      cicdIntegrationSnapshot:
          ResolvedCryptographicTrustSource<CicdIntegrationSnapshot>.fromJson(
        json['cicdIntegrationSnapshot'] as Map<String, dynamic>,
      ),
      trustPolicy:
          ResolvedCryptographicTrustSource<CryptographicTrustPolicy>.fromJson(
        json['trustPolicy'] as Map<String, dynamic>,
      ),
      sourceReferences: List.unmodifiable(
        (json['sourceReferences'] as List<dynamic>)
            .map(
              (e) => CryptographicTrustSourceReference.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      resolutionSummary: CryptographicTrustSourceResolutionSummary.fromJson(
        json['resolutionSummary'] as Map<String, dynamic>,
      ),
      messages: List.unmodifiable(
        (json['messages'] as List<dynamic>? ?? [])
            .map(
              (e) => CryptographicTrustOperationMessage.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      compatibilityHints: List.unmodifiable(
        (json['compatibilityHints'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
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
        'verificationRequest': verificationRequest.toComparableJson(),
        'releaseEvidenceBundle': releaseEvidenceBundle.toComparableJson(),
        'releaseSupplyChainSnapshot':
            releaseSupplyChainSnapshot.toComparableJson(),
        'cicdIntegrationSnapshot': cicdIntegrationSnapshot.toComparableJson(),
        'trustPolicy': trustPolicy.toComparableJson(),
        'sourceReferences': (sourceReferences
            .map((e) => e.toComparableJson())
            .toList()
          ..sort(
            (a, b) =>
                a['sourceId'].toString().compareTo(b['sourceId'].toString()),
          )),
        'resolutionSummary': resolutionSummary.toComparableJson(),
        if (compatibilityHints.isNotEmpty)
          'compatibilityHints': List<String>.from(compatibilityHints)..sort(),
      };

  ResolvedCryptographicTrustSources copyWith({
    ResolvedCryptographicTrustSource<CryptographicVerificationRequest>?
        verificationRequest,
    ResolvedCryptographicTrustSource<ReleaseEvidenceBundle>?
        releaseEvidenceBundle,
    ResolvedCryptographicTrustSource<ReleaseSupplyChainSnapshot>?
        releaseSupplyChainSnapshot,
    ResolvedCryptographicTrustSource<CicdIntegrationSnapshot>?
        cicdIntegrationSnapshot,
    ResolvedCryptographicTrustSource<CryptographicTrustPolicy>? trustPolicy,
    List<CryptographicTrustSourceReference>? sourceReferences,
    CryptographicTrustSourceResolutionSummary? resolutionSummary,
    List<CryptographicTrustOperationMessage>? messages,
    List<String>? compatibilityHints,
    Map<String, String>? metadata,
  }) {
    return ResolvedCryptographicTrustSources(
      verificationRequest: verificationRequest ?? this.verificationRequest,
      releaseEvidenceBundle:
          releaseEvidenceBundle ?? this.releaseEvidenceBundle,
      releaseSupplyChainSnapshot:
          releaseSupplyChainSnapshot ?? this.releaseSupplyChainSnapshot,
      cicdIntegrationSnapshot:
          cicdIntegrationSnapshot ?? this.cicdIntegrationSnapshot,
      trustPolicy: trustPolicy ?? this.trustPolicy,
      sourceReferences: sourceReferences ?? this.sourceReferences,
      resolutionSummary: resolutionSummary ?? this.resolutionSummary,
      messages: messages ?? this.messages,
      compatibilityHints: compatibilityHints ?? this.compatibilityHints,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResolvedCryptographicTrustSources &&
          verificationRequest == other.verificationRequest &&
          releaseEvidenceBundle == other.releaseEvidenceBundle &&
          releaseSupplyChainSnapshot == other.releaseSupplyChainSnapshot &&
          cicdIntegrationSnapshot == other.cicdIntegrationSnapshot &&
          trustPolicy == other.trustPolicy &&
          trustListEquals(sourceReferences, other.sourceReferences) &&
          resolutionSummary == other.resolutionSummary &&
          trustListEquals(messages, other.messages) &&
          trustListEquals(compatibilityHints, other.compatibilityHints) &&
          trustMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        verificationRequest,
        releaseEvidenceBundle,
        releaseSupplyChainSnapshot,
        cicdIntegrationSnapshot,
        trustPolicy,
        Object.hashAll(sourceReferences),
        resolutionSummary,
        Object.hashAll(messages),
        Object.hashAll(compatibilityHints),
        Object.hashAll(metadata.entries),
      );
}
