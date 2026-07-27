/// Supported engineering report types.
enum ReportType {
  architectureSummary,
  guardianAnalysis,
  graphSummary,
  combinedEngineeringReport,
  metricsSummary,
  historyDiff,
  engineeringScore,
  masterPalmEngineeringScore,
  engineeringDashboard,
  platformObservability,
  qualityGate,
  releaseGovernance,
  releaseEvidence,
  releaseSupplyChain,
  cicdIntegration,
  cryptographicTrust,
  persistentArtifacts,
}

extension ReportTypeX on ReportType {
  String get wireName => name;

  static ReportType fromWireName(String value) {
    return ReportType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw FormatException('Unknown ReportType: $value'),
    );
  }
}

/// Declares required and optional data sources per report type.
class ReportTypeSpec {
  const ReportTypeSpec({
    required this.requiredSources,
    this.optionalSources = const {},
  });

  final Set<ReportSourceKind> requiredSources;
  final Set<ReportSourceKind> optionalSources;

  static const specs = <ReportType, ReportTypeSpec>{
    ReportType.architectureSummary: ReportTypeSpec(
      requiredSources: {ReportSourceKind.ast},
      optionalSources: {ReportSourceKind.graph, ReportSourceKind.guardian},
    ),
    ReportType.guardianAnalysis: ReportTypeSpec(
      requiredSources: {ReportSourceKind.guardian},
    ),
    ReportType.graphSummary: ReportTypeSpec(
      requiredSources: {ReportSourceKind.graph},
    ),
    ReportType.combinedEngineeringReport: ReportTypeSpec(
      requiredSources: {
        ReportSourceKind.ast,
        ReportSourceKind.guardian,
        ReportSourceKind.graph,
      },
    ),
    ReportType.metricsSummary: ReportTypeSpec(
      requiredSources: {ReportSourceKind.metrics},
    ),
    ReportType.historyDiff: ReportTypeSpec(
      requiredSources: {ReportSourceKind.history},
    ),
    ReportType.engineeringScore: ReportTypeSpec(
      requiredSources: {ReportSourceKind.score},
    ),
    ReportType.masterPalmEngineeringScore: ReportTypeSpec(
      requiredSources: {ReportSourceKind.mes},
    ),
    ReportType.engineeringDashboard: ReportTypeSpec(
      requiredSources: {ReportSourceKind.dashboard},
    ),
    ReportType.platformObservability: ReportTypeSpec(
      requiredSources: {ReportSourceKind.observability},
    ),
    ReportType.qualityGate: ReportTypeSpec(
      requiredSources: {ReportSourceKind.qualityGate},
    ),
    ReportType.releaseGovernance: ReportTypeSpec(
      requiredSources: {ReportSourceKind.releaseGovernance},
    ),
    ReportType.releaseEvidence: ReportTypeSpec(
      requiredSources: {ReportSourceKind.releaseEvidence},
    ),
    ReportType.releaseSupplyChain: ReportTypeSpec(
      requiredSources: {ReportSourceKind.releaseSupplyChain},
    ),
    ReportType.cicdIntegration: ReportTypeSpec(
      requiredSources: {ReportSourceKind.cicdIntegration},
    ),
    ReportType.cryptographicTrust: ReportTypeSpec(
      requiredSources: {ReportSourceKind.cryptographicTrust},
    ),
    ReportType.persistentArtifacts: ReportTypeSpec(
      requiredSources: {ReportSourceKind.persistentArtifacts},
    ),
  };
}

enum ReportSourceKind {
  ast,
  guardian,
  graph,
  metrics,
  history,
  score,
  mes,
  dashboard,
  observability,
  qualityGate,
  releaseGovernance,
  releaseEvidence,
  releaseSupplyChain,
  cicdIntegration,
  cryptographicTrust,
  persistentArtifacts,
}
