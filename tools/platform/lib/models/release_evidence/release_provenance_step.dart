import 'release_evidence_enums.dart';

/// Ordered step within a provenance chain.
class ReleaseProvenanceStep {
  const ReleaseProvenanceStep({
    required this.stepId,
    required this.order,
    required this.stepType,
    required this.name,
    required this.status,
    required this.fingerprint,
    this.actorId,
    this.toolId,
    this.inputReferences = const [],
    this.outputReferences = const [],
    this.startedAt,
    this.completedAt,
    this.resultReference,
    this.limitations = const [],
  });

  final String stepId;
  final int order;
  final ReleaseProvenanceStepType stepType;
  final String name;
  final String? actorId;
  final String? toolId;
  final List<String> inputReferences;
  final List<String> outputReferences;
  final String? startedAt;
  final String? completedAt;
  final ReleaseProvenanceStatus status;
  final String? resultReference;
  final String fingerprint;
  final List<String> limitations;

  Map<String, dynamic> toJson() => {
        'stepId': stepId,
        'order': order,
        'stepType': stepType.wireName,
        'name': name,
        if (actorId != null) 'actorId': actorId,
        if (toolId != null) 'toolId': toolId,
        if (inputReferences.isNotEmpty) 'inputReferences': inputReferences,
        if (outputReferences.isNotEmpty) 'outputReferences': outputReferences,
        if (startedAt != null) 'startedAt': startedAt,
        if (completedAt != null) 'completedAt': completedAt,
        'status': status.wireName,
        if (resultReference != null) 'resultReference': resultReference,
        'fingerprint': fingerprint,
        if (limitations.isNotEmpty) 'limitations': limitations,
      };

  factory ReleaseProvenanceStep.fromJson(Map<String, dynamic> json) {
    return ReleaseProvenanceStep(
      stepId: json['stepId'] as String,
      order: json['order'] as int,
      stepType: ReleaseProvenanceStepTypeX.fromWireName(
        json['stepType'] as String,
      ),
      name: json['name'] as String,
      actorId: json['actorId'] as String?,
      toolId: json['toolId'] as String?,
      inputReferences: List.unmodifiable(
        (json['inputReferences'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
      outputReferences: List.unmodifiable(
        (json['outputReferences'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
      startedAt: json['startedAt'] as String?,
      completedAt: json['completedAt'] as String?,
      status: ReleaseProvenanceStatusX.fromWireName(json['status'] as String),
      resultReference: json['resultReference'] as String?,
      fingerprint: json['fingerprint'] as String,
      limitations: List.unmodifiable(
        (json['limitations'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      ),
    );
  }
}
