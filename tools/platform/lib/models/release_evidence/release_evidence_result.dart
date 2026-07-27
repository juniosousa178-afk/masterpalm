import 'release_evidence_bundle.dart';
import 'release_evidence_enums.dart';
import 'release_evidence_messages.dart';
import 'release_verification_result.dart';

/// Summary of source resolution for a release evidence request.
class ReleaseEvidenceSourceResolutionSummary {
  const ReleaseEvidenceSourceResolutionSummary({
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

  factory ReleaseEvidenceSourceResolutionSummary.fromJson(
    Map<String, dynamic> json,
  ) {
    return ReleaseEvidenceSourceResolutionSummary(
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseEvidenceSourceResolutionSummary &&
          runtimeType == other.runtimeType &&
          _listEquals(resolvedSources, other.resolvedSources) &&
          _listEquals(unresolvedSources, other.unresolvedSources) &&
          _listEquals(injectedSources, other.injectedSources) &&
          fingerprint == other.fingerprint;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(resolvedSources),
        Object.hashAll(unresolvedSources),
        Object.hashAll(injectedSources),
        fingerprint,
      );
}

/// Operational result of a release evidence collection run.
class ReleaseEvidenceResult {
  ReleaseEvidenceResult({
    required this.status,
    this.bundle,
    this.verificationResult,
    this.policyReference,
    this.sourceResolutionSummary,
    this.publicationStatus,
    List<ReleaseEvidenceWarning> warnings = const [],
    List<ReleaseEvidenceError> errors = const [],
    List<ReleaseEvidenceLimitation> limitations = const [],
    this.duration,
    Map<String, String> metadata = const {},
  })  : warnings = List.unmodifiable(warnings),
        errors = List.unmodifiable(errors),
        limitations = List.unmodifiable(limitations),
        metadata = Map.unmodifiable(metadata);

  final ReleaseEvidenceResultStatus status;
  final ReleaseEvidenceBundle? bundle;
  final ReleaseVerificationResult? verificationResult;
  final ReleaseEvidencePolicyReference? policyReference;
  final ReleaseEvidenceSourceResolutionSummary? sourceResolutionSummary;
  final String? publicationStatus;
  final List<ReleaseEvidenceWarning> warnings;
  final List<ReleaseEvidenceError> errors;
  final List<ReleaseEvidenceLimitation> limitations;
  final Duration? duration;
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
        'status': status.wireName,
        if (bundle != null) 'bundle': bundle!.toJson(),
        if (verificationResult != null)
          'verificationResult': verificationResult!.toJson(),
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

  factory ReleaseEvidenceResult.fromJson(Map<String, dynamic> json) {
    return ReleaseEvidenceResult(
      status: ReleaseEvidenceResultStatusX.fromWireName(
        json['status'] as String,
      ),
      bundle: json['bundle'] == null
          ? null
          : ReleaseEvidenceBundle.fromJson(
              json['bundle'] as Map<String, dynamic>,
            ),
      verificationResult: json['verificationResult'] == null
          ? null
          : ReleaseVerificationResult.fromJson(
              json['verificationResult'] as Map<String, dynamic>,
            ),
      policyReference: json['policyReference'] == null
          ? null
          : ReleaseEvidencePolicyReference.fromJson(
              json['policyReference'] as Map<String, dynamic>,
            ),
      sourceResolutionSummary: json['sourceResolutionSummary'] == null
          ? null
          : ReleaseEvidenceSourceResolutionSummary.fromJson(
              json['sourceResolutionSummary'] as Map<String, dynamic>,
            ),
      publicationStatus: json['publicationStatus'] as String?,
      warnings: (json['warnings'] as List<dynamic>? ?? [])
          .map(
            (e) => ReleaseEvidenceWarning.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      errors: (json['errors'] as List<dynamic>? ?? [])
          .map(
            (e) => ReleaseEvidenceError.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      limitations: (json['limitations'] as List<dynamic>? ?? [])
          .map(
            (e) => ReleaseEvidenceLimitation.fromJson(
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

  ReleaseEvidenceResult copyWith({
    ReleaseEvidenceResultStatus? status,
    ReleaseEvidenceBundle? bundle,
    ReleaseVerificationResult? verificationResult,
    ReleaseEvidencePolicyReference? policyReference,
    ReleaseEvidenceSourceResolutionSummary? sourceResolutionSummary,
    String? publicationStatus,
    List<ReleaseEvidenceWarning>? warnings,
    List<ReleaseEvidenceError>? errors,
    List<ReleaseEvidenceLimitation>? limitations,
    Duration? duration,
    Map<String, String>? metadata,
  }) {
    return ReleaseEvidenceResult(
      status: status ?? this.status,
      bundle: bundle ?? this.bundle,
      verificationResult: verificationResult ?? this.verificationResult,
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

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
