/// Domain identity fingerprints for a persistent artifact aggregate.
///
/// Model only — no operational identity builder in Part 1.
/// Domain fingerprint != cryptographic signature.
class PersistentArtifactIdentity {
  const PersistentArtifactIdentity({
    required this.artifactId,
    required this.subjectFingerprint,
    required this.contentFingerprint,
    required this.manifestFingerprint,
    required this.versionFingerprint,
    required this.lifecycleFingerprint,
    required this.policyFingerprint,
    required this.snapshotFingerprint,
  });

  final String artifactId;
  final String subjectFingerprint;
  final String contentFingerprint;
  final String manifestFingerprint;
  final String versionFingerprint;
  final String lifecycleFingerprint;
  final String policyFingerprint;
  final String snapshotFingerprint;

  Map<String, dynamic> toJson() => {
        'artifactId': artifactId,
        'subjectFingerprint': subjectFingerprint,
        'contentFingerprint': contentFingerprint,
        'manifestFingerprint': manifestFingerprint,
        'versionFingerprint': versionFingerprint,
        'lifecycleFingerprint': lifecycleFingerprint,
        'policyFingerprint': policyFingerprint,
        'snapshotFingerprint': snapshotFingerprint,
      };

  factory PersistentArtifactIdentity.fromJson(Map<String, dynamic> json) {
    return PersistentArtifactIdentity(
      artifactId: json['artifactId'] as String,
      subjectFingerprint: json['subjectFingerprint'] as String,
      contentFingerprint: json['contentFingerprint'] as String,
      manifestFingerprint: json['manifestFingerprint'] as String,
      versionFingerprint: json['versionFingerprint'] as String,
      lifecycleFingerprint: json['lifecycleFingerprint'] as String,
      policyFingerprint: json['policyFingerprint'] as String,
      snapshotFingerprint: json['snapshotFingerprint'] as String,
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'artifactId': artifactId,
        'subjectFingerprint': subjectFingerprint,
        'contentFingerprint': contentFingerprint,
        'manifestFingerprint': manifestFingerprint,
        'versionFingerprint': versionFingerprint,
        'lifecycleFingerprint': lifecycleFingerprint,
        'policyFingerprint': policyFingerprint,
        'snapshotFingerprint': snapshotFingerprint,
      };

  PersistentArtifactIdentity copyWith({
    String? artifactId,
    String? subjectFingerprint,
    String? contentFingerprint,
    String? manifestFingerprint,
    String? versionFingerprint,
    String? lifecycleFingerprint,
    String? policyFingerprint,
    String? snapshotFingerprint,
  }) {
    return PersistentArtifactIdentity(
      artifactId: artifactId ?? this.artifactId,
      subjectFingerprint: subjectFingerprint ?? this.subjectFingerprint,
      contentFingerprint: contentFingerprint ?? this.contentFingerprint,
      manifestFingerprint: manifestFingerprint ?? this.manifestFingerprint,
      versionFingerprint: versionFingerprint ?? this.versionFingerprint,
      lifecycleFingerprint: lifecycleFingerprint ?? this.lifecycleFingerprint,
      policyFingerprint: policyFingerprint ?? this.policyFingerprint,
      snapshotFingerprint: snapshotFingerprint ?? this.snapshotFingerprint,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentArtifactIdentity &&
          artifactId == other.artifactId &&
          subjectFingerprint == other.subjectFingerprint &&
          contentFingerprint == other.contentFingerprint &&
          manifestFingerprint == other.manifestFingerprint &&
          versionFingerprint == other.versionFingerprint &&
          lifecycleFingerprint == other.lifecycleFingerprint &&
          policyFingerprint == other.policyFingerprint &&
          snapshotFingerprint == other.snapshotFingerprint;

  @override
  int get hashCode => Object.hash(
        artifactId,
        subjectFingerprint,
        contentFingerprint,
        manifestFingerprint,
        versionFingerprint,
        lifecycleFingerprint,
        policyFingerprint,
        snapshotFingerprint,
      );
}
