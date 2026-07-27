/// Deterministic identity for a CI/CD integration snapshot.
class CicdIntegrationIdentity {
  const CicdIntegrationIdentity({
    required this.cicdIntegrationId,
    this.pipelineFingerprint,
    this.executionFingerprint,
    this.executionResultFingerprint,
    this.deploymentPlanFingerprint,
    this.deploymentResultFingerprint,
    this.snapshotFingerprint,
  });

  final String cicdIntegrationId;
  final String? pipelineFingerprint;
  final String? executionFingerprint;
  final String? executionResultFingerprint;
  final String? deploymentPlanFingerprint;
  final String? deploymentResultFingerprint;
  final String? snapshotFingerprint;

  Map<String, dynamic> toJson() => {
        'cicdIntegrationId': cicdIntegrationId,
        if (pipelineFingerprint != null)
          'pipelineFingerprint': pipelineFingerprint,
        if (executionFingerprint != null)
          'executionFingerprint': executionFingerprint,
        if (executionResultFingerprint != null)
          'executionResultFingerprint': executionResultFingerprint,
        if (deploymentPlanFingerprint != null)
          'deploymentPlanFingerprint': deploymentPlanFingerprint,
        if (deploymentResultFingerprint != null)
          'deploymentResultFingerprint': deploymentResultFingerprint,
        if (snapshotFingerprint != null)
          'snapshotFingerprint': snapshotFingerprint,
      };

  factory CicdIntegrationIdentity.fromJson(Map<String, dynamic> json) {
    return CicdIntegrationIdentity(
      cicdIntegrationId: json['cicdIntegrationId'] as String,
      pipelineFingerprint: json['pipelineFingerprint'] as String?,
      executionFingerprint: json['executionFingerprint'] as String?,
      executionResultFingerprint: json['executionResultFingerprint'] as String?,
      deploymentPlanFingerprint: json['deploymentPlanFingerprint'] as String?,
      deploymentResultFingerprint:
          json['deploymentResultFingerprint'] as String?,
      snapshotFingerprint: json['snapshotFingerprint'] as String?,
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'cicdIntegrationId': cicdIntegrationId,
        if (pipelineFingerprint != null)
          'pipelineFingerprint': pipelineFingerprint,
        if (executionFingerprint != null)
          'executionFingerprint': executionFingerprint,
        if (executionResultFingerprint != null)
          'executionResultFingerprint': executionResultFingerprint,
        if (deploymentPlanFingerprint != null)
          'deploymentPlanFingerprint': deploymentPlanFingerprint,
        if (deploymentResultFingerprint != null)
          'deploymentResultFingerprint': deploymentResultFingerprint,
        if (snapshotFingerprint != null)
          'snapshotFingerprint': snapshotFingerprint,
      };

  CicdIntegrationIdentity copyWith({
    String? cicdIntegrationId,
    String? pipelineFingerprint,
    String? executionFingerprint,
    String? executionResultFingerprint,
    String? deploymentPlanFingerprint,
    String? deploymentResultFingerprint,
    String? snapshotFingerprint,
  }) {
    return CicdIntegrationIdentity(
      cicdIntegrationId: cicdIntegrationId ?? this.cicdIntegrationId,
      pipelineFingerprint: pipelineFingerprint ?? this.pipelineFingerprint,
      executionFingerprint: executionFingerprint ?? this.executionFingerprint,
      executionResultFingerprint:
          executionResultFingerprint ?? this.executionResultFingerprint,
      deploymentPlanFingerprint:
          deploymentPlanFingerprint ?? this.deploymentPlanFingerprint,
      deploymentResultFingerprint:
          deploymentResultFingerprint ?? this.deploymentResultFingerprint,
      snapshotFingerprint: snapshotFingerprint ?? this.snapshotFingerprint,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CicdIntegrationIdentity &&
          cicdIntegrationId == other.cicdIntegrationId &&
          pipelineFingerprint == other.pipelineFingerprint &&
          executionFingerprint == other.executionFingerprint &&
          executionResultFingerprint == other.executionResultFingerprint &&
          deploymentPlanFingerprint == other.deploymentPlanFingerprint &&
          deploymentResultFingerprint == other.deploymentResultFingerprint &&
          snapshotFingerprint == other.snapshotFingerprint;

  @override
  int get hashCode => Object.hash(
        cicdIntegrationId,
        pipelineFingerprint,
        executionFingerprint,
        executionResultFingerprint,
        deploymentPlanFingerprint,
        deploymentResultFingerprint,
        snapshotFingerprint,
      );
}
