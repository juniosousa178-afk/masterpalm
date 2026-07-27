import 'release_attestation.dart';
import 'release_evidence_reference.dart';

/// Immutable collection of attestations for a subject.
class ReleaseAttestationSet {
  const ReleaseAttestationSet({
    required this.subjectId,
    required this.attestations,
    required this.fingerprint,
    required this.schemaVersion,
    this.sourceReferences = const [],
    this.warnings = const [],
    this.limitations = const [],
  });

  final String subjectId;
  final List<ReleaseAttestation> attestations;
  final List<ReleaseEvidenceReference> sourceReferences;
  final String fingerprint;
  final int schemaVersion;
  final List<String> warnings;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'subjectId': subjectId,
        'attestations': attestations.map((e) => e.toJson()).toList(),
        if (sourceReferences.isNotEmpty)
          'sourceReferences': sourceReferences.map((e) => e.toJson()).toList(),
        'fingerprint': fingerprint,
        'schemaVersion': schemaVersion,
        if (warnings.isNotEmpty) 'warnings': warnings,
        if (limitations.isNotEmpty) 'limitations': limitations,
      };

  factory ReleaseAttestationSet.fromJson(Map<String, dynamic> json) {
    return ReleaseAttestationSet(
      subjectId: json['subjectId'] as String,
      attestations: List.unmodifiable(
        (json['attestations'] as List<dynamic>)
            .map(
              (e) => ReleaseAttestation.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
      ),
      sourceReferences: List.unmodifiable(
        (json['sourceReferences'] as List<dynamic>? ?? [])
            .map(
              (e) => ReleaseEvidenceReference.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      fingerprint: json['fingerprint'] as String,
      schemaVersion: json['schemaVersion'] as int,
      warnings: List.unmodifiable(
        (json['warnings'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
      limitations: List.unmodifiable(
        (json['limitations'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
    );
  }
}
