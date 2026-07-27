import 'cryptographic_trust_equality.dart';
import 'cryptographic_trust_operational_enums.dart';
import 'cryptographic_trust_operation_message.dart';
import 'cryptographic_trust_policy_reference.dart';
import 'cryptographic_trust_snapshot.dart';
import 'cryptographic_verification_models.dart';

/// Summary of source resolution for a cryptographic trust evaluation.
class CryptographicTrustSourceResolutionSummary {
  const CryptographicTrustSourceResolutionSummary({
    required this.status,
    required this.resolvedSources,
    required this.unresolvedSources,
    required this.injectedSources,
    this.fingerprint,
  });

  final CryptographicTrustSourceResolutionStatus status;
  final List<String> resolvedSources;
  final List<String> unresolvedSources;
  final List<String> injectedSources;
  final String? fingerprint;

  Map<String, dynamic> toJson() => {
        'status': status.wireName,
        'resolvedSources': resolvedSources,
        'unresolvedSources': unresolvedSources,
        'injectedSources': injectedSources,
        if (fingerprint != null) 'fingerprint': fingerprint,
      };

  factory CryptographicTrustSourceResolutionSummary.fromJson(
    Map<String, dynamic> json,
  ) {
    return CryptographicTrustSourceResolutionSummary(
      status: CryptographicTrustSourceResolutionStatusX.fromWireName(
        json['status'] as String,
      ),
      resolvedSources: List.unmodifiable(
        (json['resolvedSources'] as List<dynamic>)
            .map((e) => e.toString())
            .toList(),
      ),
      unresolvedSources: List.unmodifiable(
        (json['unresolvedSources'] as List<dynamic>)
            .map((e) => e.toString())
            .toList(),
      ),
      injectedSources: List.unmodifiable(
        (json['injectedSources'] as List<dynamic>)
            .map((e) => e.toString())
            .toList(),
      ),
      fingerprint: json['fingerprint'] as String?,
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'status': status.wireName,
        'resolvedSources': List<String>.from(resolvedSources)..sort(),
        'unresolvedSources': List<String>.from(unresolvedSources)..sort(),
        'injectedSources': List<String>.from(injectedSources)..sort(),
        if (fingerprint != null) 'fingerprint': fingerprint,
      };

  CryptographicTrustSourceResolutionSummary copyWith({
    CryptographicTrustSourceResolutionStatus? status,
    List<String>? resolvedSources,
    List<String>? unresolvedSources,
    List<String>? injectedSources,
    String? fingerprint,
  }) {
    return CryptographicTrustSourceResolutionSummary(
      status: status ?? this.status,
      resolvedSources: resolvedSources ?? this.resolvedSources,
      unresolvedSources: unresolvedSources ?? this.unresolvedSources,
      injectedSources: injectedSources ?? this.injectedSources,
      fingerprint: fingerprint ?? this.fingerprint,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CryptographicTrustSourceResolutionSummary &&
          status == other.status &&
          trustListEquals(resolvedSources, other.resolvedSources) &&
          trustListEquals(unresolvedSources, other.unresolvedSources) &&
          trustListEquals(injectedSources, other.injectedSources) &&
          fingerprint == other.fingerprint;

  @override
  int get hashCode => Object.hash(
        status,
        Object.hashAll(resolvedSources),
        Object.hashAll(unresolvedSources),
        Object.hashAll(injectedSources),
        fingerprint,
      );
}

/// Operational result of a cryptographic trust evaluation run.
///
/// Verified status does not authorize release or deployment.
class CryptographicTrustEvaluationResult {
  CryptographicTrustEvaluationResult({
    required this.status,
    required this.evaluationId,
    required this.projectId,
    this.releaseId,
    this.verificationResult,
    this.snapshot,
    this.policyReference,
    this.sourceResolutionSummary,
    List<CryptographicTrustOperationMessage> messages = const [],
    this.evaluatedAt,
    Map<String, String> metadata = const {},
  })  : messages = List.unmodifiable(messages),
        metadata = Map.unmodifiable(metadata);

  final CryptographicTrustEvaluationStatus status;
  final String evaluationId;
  final String projectId;
  final String? releaseId;
  final CryptographicVerificationResult? verificationResult;
  final CryptographicTrustSnapshot? snapshot;
  final CryptographicTrustPolicyReference? policyReference;
  final CryptographicTrustSourceResolutionSummary? sourceResolutionSummary;
  final List<CryptographicTrustOperationMessage> messages;
  final String? evaluatedAt;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'status': status.wireName,
        'evaluationId': evaluationId,
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        if (verificationResult != null)
          'verificationResult': verificationResult!.toJson(),
        if (snapshot != null) 'snapshot': snapshot!.toJson(),
        if (policyReference != null)
          'policyReference': policyReference!.toJson(),
        if (sourceResolutionSummary != null)
          'sourceResolutionSummary': sourceResolutionSummary!.toJson(),
        if (messages.isNotEmpty)
          'messages': messages.map((e) => e.toJson()).toList(),
        if (evaluatedAt != null) 'evaluatedAt': evaluatedAt,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory CryptographicTrustEvaluationResult.fromJson(
    Map<String, dynamic> json,
  ) {
    return CryptographicTrustEvaluationResult(
      status: CryptographicTrustEvaluationStatusX.fromWireName(
        json['status'] as String,
      ),
      evaluationId: json['evaluationId'] as String,
      projectId: json['projectId'] as String,
      releaseId: json['releaseId'] as String?,
      verificationResult: json['verificationResult'] == null
          ? null
          : CryptographicVerificationResult.fromJson(
              json['verificationResult'] as Map<String, dynamic>,
            ),
      snapshot: json['snapshot'] == null
          ? null
          : CryptographicTrustSnapshot.fromJson(
              json['snapshot'] as Map<String, dynamic>,
            ),
      policyReference: json['policyReference'] == null
          ? null
          : CryptographicTrustPolicyReference.fromJson(
              json['policyReference'] as Map<String, dynamic>,
            ),
      sourceResolutionSummary: json['sourceResolutionSummary'] == null
          ? null
          : CryptographicTrustSourceResolutionSummary.fromJson(
              json['sourceResolutionSummary'] as Map<String, dynamic>,
            ),
      messages: (json['messages'] as List<dynamic>? ?? [])
          .map(
            (e) => CryptographicTrustOperationMessage.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList(),
      evaluatedAt: json['evaluatedAt'] as String?,
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'status': status.wireName,
        'evaluationId': evaluationId,
        'projectId': projectId,
        if (releaseId != null) 'releaseId': releaseId,
        if (verificationResult != null)
          'verificationResult': verificationResult!.toComparableJson(),
        if (snapshot != null) 'snapshot': snapshot!.toComparableJson(),
        if (policyReference != null)
          'policyReference': policyReference!.toComparableJson(),
        if (sourceResolutionSummary != null)
          'sourceResolutionSummary':
              sourceResolutionSummary!.toComparableJson(),
        if (messages.isNotEmpty)
          'messages': (messages.toList()
                ..sort((a, b) => a.messageId.compareTo(b.messageId)))
              .map((e) => e.toComparableJson())
              .toList(),
      };

  CryptographicTrustEvaluationResult copyWith({
    CryptographicTrustEvaluationStatus? status,
    String? evaluationId,
    String? projectId,
    String? releaseId,
    CryptographicVerificationResult? verificationResult,
    CryptographicTrustSnapshot? snapshot,
    CryptographicTrustPolicyReference? policyReference,
    CryptographicTrustSourceResolutionSummary? sourceResolutionSummary,
    List<CryptographicTrustOperationMessage>? messages,
    String? evaluatedAt,
    Map<String, String>? metadata,
  }) {
    return CryptographicTrustEvaluationResult(
      status: status ?? this.status,
      evaluationId: evaluationId ?? this.evaluationId,
      projectId: projectId ?? this.projectId,
      releaseId: releaseId ?? this.releaseId,
      verificationResult: verificationResult ?? this.verificationResult,
      snapshot: snapshot ?? this.snapshot,
      policyReference: policyReference ?? this.policyReference,
      sourceResolutionSummary:
          sourceResolutionSummary ?? this.sourceResolutionSummary,
      messages: messages ?? this.messages,
      evaluatedAt: evaluatedAt ?? this.evaluatedAt,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CryptographicTrustEvaluationResult &&
          status == other.status &&
          evaluationId == other.evaluationId &&
          projectId == other.projectId &&
          releaseId == other.releaseId &&
          verificationResult == other.verificationResult &&
          snapshot == other.snapshot &&
          policyReference == other.policyReference &&
          sourceResolutionSummary == other.sourceResolutionSummary &&
          trustListEquals(messages, other.messages) &&
          evaluatedAt == other.evaluatedAt &&
          trustMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        status,
        evaluationId,
        projectId,
        releaseId,
        verificationResult,
        snapshot,
        policyReference,
        sourceResolutionSummary,
        Object.hashAll(messages),
        evaluatedAt,
        Object.hashAll(metadata.entries),
      );
}
