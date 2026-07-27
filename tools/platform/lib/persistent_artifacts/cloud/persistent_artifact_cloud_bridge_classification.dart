enum PersistentArtifactCloudBridgeClassification {
  contractOnly,
  offlineSimulation,
}

extension PersistentArtifactCloudBridgeClassificationX
    on PersistentArtifactCloudBridgeClassification {
  String get wireName => name;

  static PersistentArtifactCloudBridgeClassification fromWireName(
    String value,
  ) {
    return PersistentArtifactCloudBridgeClassification.values.firstWhere(
      (it) => it.name == value,
      orElse: () => throw FormatException(
        'Unknown PersistentArtifactCloudBridgeClassification: $value',
      ),
    );
  }
}
