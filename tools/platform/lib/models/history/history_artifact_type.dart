/// Supported artifact types in a [HistorySnapshot].
enum HistoryArtifactType {
  graph,
  metrics,
  report,
  guardian,
  ast,
  mes,
  dashboard,
  telemetry,
  qualityGate,
  releaseGovernance,
  releaseEvidence,
  releaseSupplyChain,
  cicdIntegration,
  cryptographicTrust,
  persistentArtifacts,
}

extension HistoryArtifactTypeX on HistoryArtifactType {
  String get wireName => name;

  static HistoryArtifactType fromWireName(String value) {
    return HistoryArtifactType.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown HistoryArtifactType: $value'),
    );
  }
}
