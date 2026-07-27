import 'cicd_integration_messages.dart';
import 'cicd_integration_operational_enums.dart';
import 'cicd_integration_policy_models.dart';
import 'cicd_integration_snapshot.dart';
import 'pipeline_equality.dart';

/// Summary of source resolution for a CI/CD integration request.
class CicdIntegrationSourceResolutionSummary {
  const CicdIntegrationSourceResolutionSummary({
    required this.resolvedSources,
    required this.unresolvedSources,
    required this.injectedSources,
    this.fingerprint,
  });

  final List<String> resolvedSources;
  final List<String> unresolvedSources;
  final List<String> injectedSources;
  final String? fingerprint;

  Map<String, dynamic> toJson() => {
        'resolvedSources': resolvedSources,
        'unresolvedSources': unresolvedSources,
        'injectedSources': injectedSources,
        if (fingerprint != null) 'fingerprint': fingerprint,
      };

  factory CicdIntegrationSourceResolutionSummary.fromJson(
    Map<String, dynamic> json,
  ) {
    return CicdIntegrationSourceResolutionSummary(
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
        'resolvedSources': List<String>.from(resolvedSources)..sort(),
        'unresolvedSources': List<String>.from(unresolvedSources)..sort(),
        'injectedSources': List<String>.from(injectedSources)..sort(),
        if (fingerprint != null) 'fingerprint': fingerprint,
      };

  CicdIntegrationSourceResolutionSummary copyWith({
    List<String>? resolvedSources,
    List<String>? unresolvedSources,
    List<String>? injectedSources,
    String? fingerprint,
  }) {
    return CicdIntegrationSourceResolutionSummary(
      resolvedSources: resolvedSources ?? this.resolvedSources,
      unresolvedSources: unresolvedSources ?? this.unresolvedSources,
      injectedSources: injectedSources ?? this.injectedSources,
      fingerprint: fingerprint ?? this.fingerprint,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CicdIntegrationSourceResolutionSummary &&
          cicdListEquals(resolvedSources, other.resolvedSources) &&
          cicdListEquals(unresolvedSources, other.unresolvedSources) &&
          cicdListEquals(injectedSources, other.injectedSources) &&
          fingerprint == other.fingerprint;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(resolvedSources),
        Object.hashAll(unresolvedSources),
        Object.hashAll(injectedSources),
        fingerprint,
      );
}

/// Operational result of a CI/CD integration collection run.
class CicdIntegrationResult {
  CicdIntegrationResult({
    required this.status,
    this.snapshot,
    this.policyReference,
    this.sourceResolutionSummary,
    this.publicationStatus,
    List<CicdIntegrationMessage> messages = const [],
    List<CicdIntegrationWarning> warnings = const [],
    List<CicdIntegrationError> errors = const [],
    List<CicdIntegrationLimitation> limitations = const [],
    this.duration,
    Map<String, String> metadata = const {},
  })  : messages = List.unmodifiable(messages),
        warnings = List.unmodifiable(warnings),
        errors = List.unmodifiable(errors),
        limitations = List.unmodifiable(limitations),
        metadata = Map.unmodifiable(metadata);

  final CicdIntegrationResultStatus status;
  final CicdIntegrationSnapshot? snapshot;
  final CicdIntegrationPolicyReference? policyReference;
  final CicdIntegrationSourceResolutionSummary? sourceResolutionSummary;
  final CicdIntegrationPublicationStatus? publicationStatus;
  final List<CicdIntegrationMessage> messages;
  final List<CicdIntegrationWarning> warnings;
  final List<CicdIntegrationError> errors;
  final List<CicdIntegrationLimitation> limitations;
  final Duration? duration;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'status': status.wireName,
        if (snapshot != null) 'snapshot': snapshot!.toJson(),
        if (policyReference != null)
          'policyReference': policyReference!.toJson(),
        if (sourceResolutionSummary != null)
          'sourceResolutionSummary': sourceResolutionSummary!.toJson(),
        if (publicationStatus != null)
          'publicationStatus': publicationStatus!.wireName,
        if (messages.isNotEmpty)
          'messages': messages.map((e) => e.toJson()).toList(),
        if (warnings.isNotEmpty)
          'warnings': warnings.map((e) => e.toJson()).toList(),
        if (errors.isNotEmpty) 'errors': errors.map((e) => e.toJson()).toList(),
        if (limitations.isNotEmpty)
          'limitations': limitations.map((e) => e.toJson()).toList(),
        if (duration != null) 'durationMs': duration!.inMilliseconds,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory CicdIntegrationResult.fromJson(Map<String, dynamic> json) {
    return CicdIntegrationResult(
      status: CicdIntegrationResultStatusX.fromWireName(
        json['status'] as String,
      ),
      snapshot: json['snapshot'] == null
          ? null
          : CicdIntegrationSnapshot.fromJson(
              json['snapshot'] as Map<String, dynamic>,
            ),
      policyReference: json['policyReference'] == null
          ? null
          : CicdIntegrationPolicyReference.fromJson(
              json['policyReference'] as Map<String, dynamic>,
            ),
      sourceResolutionSummary: json['sourceResolutionSummary'] == null
          ? null
          : CicdIntegrationSourceResolutionSummary.fromJson(
              json['sourceResolutionSummary'] as Map<String, dynamic>,
            ),
      publicationStatus: json['publicationStatus'] == null
          ? null
          : CicdIntegrationPublicationStatusX.fromWireName(
              json['publicationStatus'] as String,
            ),
      messages: (json['messages'] as List<dynamic>? ?? [])
          .map(
            (e) => CicdIntegrationMessage.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList(),
      warnings: (json['warnings'] as List<dynamic>? ?? [])
          .map(
            (e) => CicdIntegrationWarning.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList(),
      errors: (json['errors'] as List<dynamic>? ?? [])
          .map(
            (e) => CicdIntegrationError.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      limitations: (json['limitations'] as List<dynamic>? ?? [])
          .map(
            (e) => CicdIntegrationLimitation.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList(),
      duration: json['durationMs'] == null
          ? null
          : Duration(milliseconds: json['durationMs'] as int),
      metadata: Map.unmodifiable(
        (json['metadata'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      ),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'status': status.wireName,
        if (snapshot != null) 'snapshot': snapshot!.toComparableJson(),
        if (policyReference != null)
          'policyReference': policyReference!.toComparableJson(),
        if (sourceResolutionSummary != null)
          'sourceResolutionSummary':
              sourceResolutionSummary!.toComparableJson(),
        if (publicationStatus != null)
          'publicationStatus': publicationStatus!.wireName,
        if (messages.isNotEmpty)
          'messages': (messages.toList()
                ..sort((a, b) => a.messageId.compareTo(b.messageId)))
              .map((e) => e.toJson())
              .toList(),
        if (warnings.isNotEmpty)
          'warnings': (warnings.toList()
                ..sort((a, b) => a.warningId.compareTo(b.warningId)))
              .map((e) => e.toJson())
              .toList(),
        if (errors.isNotEmpty)
          'errors': (errors.toList()
                ..sort((a, b) => a.errorId.compareTo(b.errorId)))
              .map((e) => e.toJson())
              .toList(),
        if (limitations.isNotEmpty)
          'limitations': (limitations.toList()
                ..sort((a, b) => a.limitationId.compareTo(b.limitationId)))
              .map((e) => e.toJson())
              .toList(),
        if (metadata.isNotEmpty)
          'metadata': Map.fromEntries(
            metadata.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
          ),
      };

  CicdIntegrationResult copyWith({
    CicdIntegrationResultStatus? status,
    CicdIntegrationSnapshot? snapshot,
    CicdIntegrationPolicyReference? policyReference,
    CicdIntegrationSourceResolutionSummary? sourceResolutionSummary,
    CicdIntegrationPublicationStatus? publicationStatus,
    List<CicdIntegrationMessage>? messages,
    List<CicdIntegrationWarning>? warnings,
    List<CicdIntegrationError>? errors,
    List<CicdIntegrationLimitation>? limitations,
    Duration? duration,
    Map<String, String>? metadata,
  }) {
    return CicdIntegrationResult(
      status: status ?? this.status,
      snapshot: snapshot ?? this.snapshot,
      policyReference: policyReference ?? this.policyReference,
      sourceResolutionSummary:
          sourceResolutionSummary ?? this.sourceResolutionSummary,
      publicationStatus: publicationStatus ?? this.publicationStatus,
      messages: messages ?? this.messages,
      warnings: warnings ?? this.warnings,
      errors: errors ?? this.errors,
      limitations: limitations ?? this.limitations,
      duration: duration ?? this.duration,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CicdIntegrationResult &&
          status == other.status &&
          snapshot == other.snapshot &&
          policyReference == other.policyReference &&
          sourceResolutionSummary == other.sourceResolutionSummary &&
          publicationStatus == other.publicationStatus &&
          cicdListEquals(messages, other.messages) &&
          cicdListEquals(warnings, other.warnings) &&
          cicdListEquals(errors, other.errors) &&
          cicdListEquals(limitations, other.limitations) &&
          duration == other.duration &&
          cicdMapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        status,
        snapshot,
        policyReference,
        sourceResolutionSummary,
        publicationStatus,
        Object.hashAll(messages),
        Object.hashAll(warnings),
        Object.hashAll(errors),
        Object.hashAll(limitations),
        duration,
        Object.hashAll(metadata.entries),
      );
}
