import '../release_governance/release_governance_enums.dart';
import 'release_evidence_enums.dart';
import 'release_evidence_reference.dart';
import 'release_provenance_actor.dart';
import 'release_provenance_step.dart';

/// Immutable provenance record for a release subject.
class ReleaseProvenance {
  const ReleaseProvenance({
    required this.provenanceId,
    required this.subjectId,
    required this.provenanceType,
    required this.origin,
    required this.actors,
    required this.steps,
    required this.inputs,
    required this.outputs,
    required this.environment,
    required this.toolReferences,
    required this.evidenceReferences,
    required this.status,
    required this.fingerprint,
    required this.schemaVersion,
    this.startedAt,
    this.completedAt,
    this.limitations = const [],
  });

  final String provenanceId;
  final String subjectId;
  final ReleaseProvenanceType provenanceType;
  final String origin;
  final List<ReleaseProvenanceActor> actors;
  final List<ReleaseProvenanceStep> steps;
  final List<String> inputs;
  final List<String> outputs;
  final String? startedAt;
  final String? completedAt;
  final ReleaseEnvironment environment;
  final List<String> toolReferences;
  final List<ReleaseEvidenceReference> evidenceReferences;
  final ReleaseProvenanceStatus status;
  final String fingerprint;
  final int schemaVersion;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'provenanceId': provenanceId,
        'subjectId': subjectId,
        'provenanceType': provenanceType.wireName,
        'origin': origin,
        'actors': actors.map((e) => e.toJson()).toList(),
        'steps': steps.map((e) => e.toJson()).toList(),
        if (inputs.isNotEmpty) 'inputs': inputs,
        if (outputs.isNotEmpty) 'outputs': outputs,
        if (startedAt != null) 'startedAt': startedAt,
        if (completedAt != null) 'completedAt': completedAt,
        'environment': environment.wireName,
        if (toolReferences.isNotEmpty) 'toolReferences': toolReferences,
        if (evidenceReferences.isNotEmpty)
          'evidenceReferences':
              evidenceReferences.map((e) => e.toJson()).toList(),
        'status': status.wireName,
        'fingerprint': fingerprint,
        'schemaVersion': schemaVersion,
        if (limitations.isNotEmpty) 'limitations': limitations,
      };

  factory ReleaseProvenance.fromJson(Map<String, dynamic> json) {
    return ReleaseProvenance(
      provenanceId: json['provenanceId'] as String,
      subjectId: json['subjectId'] as String,
      provenanceType: ReleaseProvenanceTypeX.fromWireName(
        json['provenanceType'] as String,
      ),
      origin: json['origin'] as String,
      actors: List.unmodifiable(
        (json['actors'] as List<dynamic>)
            .map(
              (e) => ReleaseProvenanceActor.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      steps: List.unmodifiable(
        (json['steps'] as List<dynamic>)
            .map(
              (e) => ReleaseProvenanceStep.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      inputs: List.unmodifiable(
        (json['inputs'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
      outputs: List.unmodifiable(
        (json['outputs'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
      startedAt: json['startedAt'] as String?,
      completedAt: json['completedAt'] as String?,
      environment: ReleaseEnvironmentX.fromWireName(
        json['environment'] as String,
      ),
      toolReferences: List.unmodifiable(
        (json['toolReferences'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
      evidenceReferences: List.unmodifiable(
        (json['evidenceReferences'] as List<dynamic>? ?? [])
            .map(
              (e) => ReleaseEvidenceReference.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      ),
      status: ReleaseProvenanceStatusX.fromWireName(json['status'] as String),
      fingerprint: json['fingerprint'] as String,
      schemaVersion: json['schemaVersion'] as int,
      limitations: List.unmodifiable(
        (json['limitations'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
    );
  }
}
