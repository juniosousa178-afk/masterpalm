/// Deterministic identity for a Persistent Artifact infrastructure snapshot.
///
/// Model only — no operational identity builder in Part 1.
/// Domain fingerprint != cryptographic signature.
class PersistentArtifactInfrastructureIdentity {
  const PersistentArtifactInfrastructureIdentity({
    required this.persistentArtifactInfrastructureId,
    this.subjectsFingerprint,
    this.contentsFingerprint,
    this.manifestsFingerprint,
    this.locationsFingerprint,
    this.versionsFingerprint,
    this.lifecycleFingerprint,
    this.policiesFingerprint,
    this.replicationFingerprint,
    this.operationsFingerprint,
    this.snapshotFingerprint,
  });

  final String persistentArtifactInfrastructureId;
  final String? subjectsFingerprint;
  final String? contentsFingerprint;
  final String? manifestsFingerprint;
  final String? locationsFingerprint;
  final String? versionsFingerprint;
  final String? lifecycleFingerprint;
  final String? policiesFingerprint;
  final String? replicationFingerprint;
  final String? operationsFingerprint;
  final String? snapshotFingerprint;

  Map<String, dynamic> toJson() => {
        'persistentArtifactInfrastructureId':
            persistentArtifactInfrastructureId,
        if (subjectsFingerprint != null)
          'subjectsFingerprint': subjectsFingerprint,
        if (contentsFingerprint != null)
          'contentsFingerprint': contentsFingerprint,
        if (manifestsFingerprint != null)
          'manifestsFingerprint': manifestsFingerprint,
        if (locationsFingerprint != null)
          'locationsFingerprint': locationsFingerprint,
        if (versionsFingerprint != null)
          'versionsFingerprint': versionsFingerprint,
        if (lifecycleFingerprint != null)
          'lifecycleFingerprint': lifecycleFingerprint,
        if (policiesFingerprint != null)
          'policiesFingerprint': policiesFingerprint,
        if (replicationFingerprint != null)
          'replicationFingerprint': replicationFingerprint,
        if (operationsFingerprint != null)
          'operationsFingerprint': operationsFingerprint,
        if (snapshotFingerprint != null)
          'snapshotFingerprint': snapshotFingerprint,
      };

  factory PersistentArtifactInfrastructureIdentity.fromJson(
    Map<String, dynamic> json,
  ) {
    return PersistentArtifactInfrastructureIdentity(
      persistentArtifactInfrastructureId:
          json['persistentArtifactInfrastructureId'] as String,
      subjectsFingerprint: json['subjectsFingerprint'] as String?,
      contentsFingerprint: json['contentsFingerprint'] as String?,
      manifestsFingerprint: json['manifestsFingerprint'] as String?,
      locationsFingerprint: json['locationsFingerprint'] as String?,
      versionsFingerprint: json['versionsFingerprint'] as String?,
      lifecycleFingerprint: json['lifecycleFingerprint'] as String?,
      policiesFingerprint: json['policiesFingerprint'] as String?,
      replicationFingerprint: json['replicationFingerprint'] as String?,
      operationsFingerprint: json['operationsFingerprint'] as String?,
      snapshotFingerprint: json['snapshotFingerprint'] as String?,
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'persistentArtifactInfrastructureId':
            persistentArtifactInfrastructureId,
        if (subjectsFingerprint != null)
          'subjectsFingerprint': subjectsFingerprint,
        if (contentsFingerprint != null)
          'contentsFingerprint': contentsFingerprint,
        if (manifestsFingerprint != null)
          'manifestsFingerprint': manifestsFingerprint,
        if (locationsFingerprint != null)
          'locationsFingerprint': locationsFingerprint,
        if (versionsFingerprint != null)
          'versionsFingerprint': versionsFingerprint,
        if (lifecycleFingerprint != null)
          'lifecycleFingerprint': lifecycleFingerprint,
        if (policiesFingerprint != null)
          'policiesFingerprint': policiesFingerprint,
        if (replicationFingerprint != null)
          'replicationFingerprint': replicationFingerprint,
        if (operationsFingerprint != null)
          'operationsFingerprint': operationsFingerprint,
        if (snapshotFingerprint != null)
          'snapshotFingerprint': snapshotFingerprint,
      };

  PersistentArtifactInfrastructureIdentity copyWith({
    String? persistentArtifactInfrastructureId,
    String? subjectsFingerprint,
    String? contentsFingerprint,
    String? manifestsFingerprint,
    String? locationsFingerprint,
    String? versionsFingerprint,
    String? lifecycleFingerprint,
    String? policiesFingerprint,
    String? replicationFingerprint,
    String? operationsFingerprint,
    String? snapshotFingerprint,
  }) {
    return PersistentArtifactInfrastructureIdentity(
      persistentArtifactInfrastructureId: persistentArtifactInfrastructureId ??
          this.persistentArtifactInfrastructureId,
      subjectsFingerprint: subjectsFingerprint ?? this.subjectsFingerprint,
      contentsFingerprint: contentsFingerprint ?? this.contentsFingerprint,
      manifestsFingerprint: manifestsFingerprint ?? this.manifestsFingerprint,
      locationsFingerprint: locationsFingerprint ?? this.locationsFingerprint,
      versionsFingerprint: versionsFingerprint ?? this.versionsFingerprint,
      lifecycleFingerprint: lifecycleFingerprint ?? this.lifecycleFingerprint,
      policiesFingerprint: policiesFingerprint ?? this.policiesFingerprint,
      replicationFingerprint:
          replicationFingerprint ?? this.replicationFingerprint,
      operationsFingerprint:
          operationsFingerprint ?? this.operationsFingerprint,
      snapshotFingerprint: snapshotFingerprint ?? this.snapshotFingerprint,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactInfrastructureIdentity &&
          persistentArtifactInfrastructureId ==
              other.persistentArtifactInfrastructureId &&
          subjectsFingerprint == other.subjectsFingerprint &&
          contentsFingerprint == other.contentsFingerprint &&
          manifestsFingerprint == other.manifestsFingerprint &&
          locationsFingerprint == other.locationsFingerprint &&
          versionsFingerprint == other.versionsFingerprint &&
          lifecycleFingerprint == other.lifecycleFingerprint &&
          policiesFingerprint == other.policiesFingerprint &&
          replicationFingerprint == other.replicationFingerprint &&
          operationsFingerprint == other.operationsFingerprint &&
          snapshotFingerprint == other.snapshotFingerprint;

  @override
  int get hashCode => Object.hash(
        persistentArtifactInfrastructureId,
        subjectsFingerprint,
        contentsFingerprint,
        manifestsFingerprint,
        locationsFingerprint,
        versionsFingerprint,
        lifecycleFingerprint,
        policiesFingerprint,
        replicationFingerprint,
        operationsFingerprint,
        snapshotFingerprint,
      );
}
