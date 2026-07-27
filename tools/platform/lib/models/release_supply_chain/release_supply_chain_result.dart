import 'release_supply_chain_messages.dart';
import 'release_supply_chain_operational_enums.dart';
import 'release_supply_chain_policy_models.dart';
import 'release_supply_chain_snapshot.dart';

/// Summary of source resolution for a release supply chain request.
class ReleaseSupplyChainSourceResolutionSummary {
  const ReleaseSupplyChainSourceResolutionSummary({
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

  factory ReleaseSupplyChainSourceResolutionSummary.fromJson(
    Map<String, dynamic> json,
  ) {
    return ReleaseSupplyChainSourceResolutionSummary(
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
}

/// Operational result of a release supply chain collection run.
class ReleaseSupplyChainResult {
  ReleaseSupplyChainResult({
    required this.status,
    this.snapshot,
    this.policyReference,
    this.sourceResolutionSummary,
    this.publicationStatus,
    List<ReleaseSupplyChainWarning> warnings = const [],
    List<ReleaseSupplyChainError> errors = const [],
    List<ReleaseSupplyChainLimitation> limitations = const [],
    this.duration,
    Map<String, String> metadata = const {},
  })  : warnings = List.unmodifiable(warnings),
        errors = List.unmodifiable(errors),
        limitations = List.unmodifiable(limitations),
        metadata = Map.unmodifiable(metadata);

  final ReleaseSupplyChainResultStatus status;
  final ReleaseSupplyChainSnapshot? snapshot;
  final ReleaseSupplyChainPolicyReference? policyReference;
  final ReleaseSupplyChainSourceResolutionSummary? sourceResolutionSummary;
  final String? publicationStatus;
  final List<ReleaseSupplyChainWarning> warnings;
  final List<ReleaseSupplyChainError> errors;
  final List<ReleaseSupplyChainLimitation> limitations;
  final Duration? duration;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'status': status.wireName,
        if (snapshot != null) 'snapshot': snapshot!.toJson(),
        if (policyReference != null)
          'policyReference': policyReference!.toJson(),
        if (sourceResolutionSummary != null)
          'sourceResolutionSummary': sourceResolutionSummary!.toJson(),
        if (publicationStatus != null) 'publicationStatus': publicationStatus,
        if (warnings.isNotEmpty)
          'warnings': warnings.map((e) => e.toJson()).toList(),
        if (errors.isNotEmpty) 'errors': errors.map((e) => e.toJson()).toList(),
        if (limitations.isNotEmpty)
          'limitations': limitations.map((e) => e.toJson()).toList(),
        if (duration != null) 'durationMs': duration!.inMilliseconds,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory ReleaseSupplyChainResult.fromJson(Map<String, dynamic> json) {
    return ReleaseSupplyChainResult(
      status: ReleaseSupplyChainResultStatusX.fromWireName(
        json['status'] as String,
      ),
      snapshot: json['snapshot'] == null
          ? null
          : ReleaseSupplyChainSnapshot.fromJson(
              json['snapshot'] as Map<String, dynamic>,
            ),
      policyReference: json['policyReference'] == null
          ? null
          : ReleaseSupplyChainPolicyReference.fromJson(
              json['policyReference'] as Map<String, dynamic>,
            ),
      sourceResolutionSummary: json['sourceResolutionSummary'] == null
          ? null
          : ReleaseSupplyChainSourceResolutionSummary.fromJson(
              json['sourceResolutionSummary'] as Map<String, dynamic>,
            ),
      publicationStatus: json['publicationStatus'] as String?,
      warnings: (json['warnings'] as List<dynamic>? ?? [])
          .map(
            (e) => ReleaseSupplyChainWarning.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList(),
      errors: (json['errors'] as List<dynamic>? ?? [])
          .map(
            (e) => ReleaseSupplyChainError.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      limitations: (json['limitations'] as List<dynamic>? ?? [])
          .map(
            (e) => ReleaseSupplyChainLimitation.fromJson(
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

  ReleaseSupplyChainResult copyWith({
    ReleaseSupplyChainResultStatus? status,
    ReleaseSupplyChainSnapshot? snapshot,
    ReleaseSupplyChainPolicyReference? policyReference,
    ReleaseSupplyChainSourceResolutionSummary? sourceResolutionSummary,
    String? publicationStatus,
    List<ReleaseSupplyChainWarning>? warnings,
    List<ReleaseSupplyChainError>? errors,
    List<ReleaseSupplyChainLimitation>? limitations,
    Duration? duration,
    Map<String, String>? metadata,
  }) {
    return ReleaseSupplyChainResult(
      status: status ?? this.status,
      snapshot: snapshot ?? this.snapshot,
      policyReference: policyReference ?? this.policyReference,
      sourceResolutionSummary:
          sourceResolutionSummary ?? this.sourceResolutionSummary,
      publicationStatus: publicationStatus ?? this.publicationStatus,
      warnings: warnings ?? this.warnings,
      errors: errors ?? this.errors,
      limitations: limitations ?? this.limitations,
      duration: duration ?? this.duration,
      metadata: metadata ?? this.metadata,
    );
  }
}
