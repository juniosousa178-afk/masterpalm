import '../../models/history/history_artifact.dart';
import '../../models/history/history_artifact_type.dart';
import '../../models/history/history_request.dart';
import 'mappers/ast_history_mapper.dart';
import 'mappers/graph_history_mapper.dart';
import 'mappers/guardian_history_mapper.dart';
import 'mappers/dashboard_history_mapper.dart';
import 'mappers/mes_history_mapper.dart';
import 'mappers/metrics_history_mapper.dart';
import 'mappers/report_history_mapper.dart';
import 'mappers/telemetry_history_mapper.dart';
import 'mappers/quality_gate_history_mapper.dart';
import 'mappers/release_governance_history_mapper.dart';
import 'mappers/release_evidence_history_mapper.dart';
import 'mappers/release_supply_chain_history_mapper.dart';
import 'mappers/cicd_integration_history_mapper.dart';
import 'mappers/cryptographic_trust_history_mapper.dart';

/// Builds [HistoryArtifact] instances from typed request payloads.
class HistoryArtifactFactory {
  HistoryArtifactFactory({
    GraphHistoryMapper? graphMapper,
    MetricsHistoryMapper? metricsMapper,
    ReportHistoryMapper? reportMapper,
    GuardianHistoryMapper? guardianMapper,
    AstHistoryMapper? astMapper,
    MESHistoryMapper? mesMapper,
    DashboardHistoryMapper? dashboardMapper,
    TelemetryHistoryMapper? telemetryMapper,
    QualityGateHistoryMapper? qualityGateMapper,
    ReleaseGovernanceHistoryMapper? releaseGovernanceMapper,
    ReleaseEvidenceHistoryMapper? releaseEvidenceMapper,
    ReleaseSupplyChainHistoryMapper? releaseSupplyChainMapper,
    CicdIntegrationHistoryMapper? cicdIntegrationMapper,
    CryptographicTrustHistoryMapper? cryptographicTrustMapper,
  })  : _graphMapper = graphMapper ?? GraphHistoryMapper(),
        _metricsMapper = metricsMapper ?? MetricsHistoryMapper(),
        _reportMapper = reportMapper ?? ReportHistoryMapper(),
        _guardianMapper = guardianMapper ?? GuardianHistoryMapper(),
        _astMapper = astMapper ?? AstHistoryMapper(),
        _mesMapper = mesMapper ?? MESHistoryMapper(),
        _dashboardMapper = dashboardMapper ?? DashboardHistoryMapper(),
        _telemetryMapper = telemetryMapper ?? TelemetryHistoryMapper(),
        _qualityGateMapper = qualityGateMapper ?? QualityGateHistoryMapper(),
        _releaseGovernanceMapper =
            releaseGovernanceMapper ?? ReleaseGovernanceHistoryMapper(),
        _releaseEvidenceMapper =
            releaseEvidenceMapper ?? ReleaseEvidenceHistoryMapper(),
        _releaseSupplyChainMapper =
            releaseSupplyChainMapper ?? ReleaseSupplyChainHistoryMapper(),
        _cicdIntegrationMapper =
            cicdIntegrationMapper ?? CicdIntegrationHistoryMapper(),
        _cryptographicTrustMapper =
            cryptographicTrustMapper ?? CryptographicTrustHistoryMapper();

  final GraphHistoryMapper _graphMapper;
  final MetricsHistoryMapper _metricsMapper;
  final ReportHistoryMapper _reportMapper;
  final GuardianHistoryMapper _guardianMapper;
  final AstHistoryMapper _astMapper;
  final MESHistoryMapper _mesMapper;
  final DashboardHistoryMapper _dashboardMapper;
  final TelemetryHistoryMapper _telemetryMapper;
  final QualityGateHistoryMapper _qualityGateMapper;
  final ReleaseGovernanceHistoryMapper _releaseGovernanceMapper;
  final ReleaseEvidenceHistoryMapper _releaseEvidenceMapper;
  final ReleaseSupplyChainHistoryMapper _releaseSupplyChainMapper;
  final CicdIntegrationHistoryMapper _cicdIntegrationMapper;
  final CryptographicTrustHistoryMapper _cryptographicTrustMapper;

  List<HistoryArtifact> buildFromRequest(HistoryRequest request) {
    final selection = request.artifactSelection;
    final artifacts = <HistoryArtifact>[];

    void addIfSelected(HistoryArtifactType type, HistoryArtifact? artifact) {
      if (artifact == null) return;
      if (selection == null || selection.contains(type)) {
        artifacts.add(artifact);
      }
    }

    if (request.projectGraph != null && request.projectGraph!.isNotEmpty) {
      addIfSelected(
        HistoryArtifactType.graph,
        _graphMapper.fromMap(request.projectGraph!),
      );
    }
    if (request.metricsSnapshot != null &&
        request.metricsSnapshot!.isNotEmpty) {
      addIfSelected(
        HistoryArtifactType.metrics,
        _metricsMapper.fromMap(request.metricsSnapshot!),
      );
    }
    if (request.reportDocument != null && request.reportDocument!.isNotEmpty) {
      addIfSelected(
        HistoryArtifactType.report,
        _reportMapper.fromMap(request.reportDocument!),
      );
    }
    if (request.guardianAnalysis != null &&
        request.guardianAnalysis!.isNotEmpty) {
      addIfSelected(
        HistoryArtifactType.guardian,
        _guardianMapper.fromMap(request.guardianAnalysis!),
      );
    }
    if (request.astReport != null && request.astReport!.isNotEmpty) {
      addIfSelected(
        HistoryArtifactType.ast,
        _astMapper.fromMap(request.astReport!),
      );
    }
    if (request.mesSnapshot != null && request.mesSnapshot!.isNotEmpty) {
      addIfSelected(
        HistoryArtifactType.mes,
        _mesMapper.fromMap(request.mesSnapshot!),
      );
    }
    if (request.dashboardSnapshot != null &&
        request.dashboardSnapshot!.isNotEmpty) {
      addIfSelected(
        HistoryArtifactType.dashboard,
        _dashboardMapper.fromMap(request.dashboardSnapshot!),
      );
    }
    if (request.telemetrySnapshot != null &&
        request.telemetrySnapshot!.isNotEmpty) {
      addIfSelected(
        HistoryArtifactType.telemetry,
        _telemetryMapper.fromMap(request.telemetrySnapshot!),
      );
    }
    if (request.qualityGateSnapshot != null &&
        request.qualityGateSnapshot!.isNotEmpty) {
      addIfSelected(
        HistoryArtifactType.qualityGate,
        _qualityGateMapper.fromMap(request.qualityGateSnapshot!),
      );
    }
    if (request.releaseDecisionSnapshot != null &&
        request.releaseDecisionSnapshot!.isNotEmpty) {
      addIfSelected(
        HistoryArtifactType.releaseGovernance,
        _releaseGovernanceMapper.fromMap(request.releaseDecisionSnapshot!),
      );
    }
    if (request.releaseEvidenceBundle != null &&
        request.releaseEvidenceBundle!.isNotEmpty) {
      addIfSelected(
        HistoryArtifactType.releaseEvidence,
        _releaseEvidenceMapper.fromMap(request.releaseEvidenceBundle!),
      );
    }
    if (request.releaseSupplyChainSnapshot != null &&
        request.releaseSupplyChainSnapshot!.isNotEmpty) {
      addIfSelected(
        HistoryArtifactType.releaseSupplyChain,
        _releaseSupplyChainMapper.fromMap(request.releaseSupplyChainSnapshot!),
      );
    }
    if (request.cicdIntegrationSnapshot != null &&
        request.cicdIntegrationSnapshot!.isNotEmpty) {
      addIfSelected(
        HistoryArtifactType.cicdIntegration,
        _cicdIntegrationMapper.fromMap(request.cicdIntegrationSnapshot!),
      );
    }
    if (request.cryptographicTrustSnapshot != null &&
        request.cryptographicTrustSnapshot!.isNotEmpty) {
      addIfSelected(
        HistoryArtifactType.cryptographicTrust,
        _cryptographicTrustMapper.fromMap(request.cryptographicTrustSnapshot!),
      );
    }

    artifacts.sort((a, b) {
      final typeCmp =
          a.artifactType.wireName.compareTo(b.artifactType.wireName);
      if (typeCmp != 0) return typeCmp;
      return a.artifactId.compareTo(b.artifactId);
    });
    return artifacts;
  }

  Set<HistoryArtifactType> missingFromRequest(HistoryRequest request) {
    final selection = request.artifactSelection ??
        {
          if (request.projectGraph != null) HistoryArtifactType.graph,
          if (request.metricsSnapshot != null) HistoryArtifactType.metrics,
          if (request.reportDocument != null) HistoryArtifactType.report,
          if (request.guardianAnalysis != null) HistoryArtifactType.guardian,
          if (request.astReport != null) HistoryArtifactType.ast,
          if (request.mesSnapshot != null) HistoryArtifactType.mes,
          if (request.dashboardSnapshot != null) HistoryArtifactType.dashboard,
          if (request.telemetrySnapshot != null) HistoryArtifactType.telemetry,
          if (request.qualityGateSnapshot != null)
            HistoryArtifactType.qualityGate,
          if (request.releaseDecisionSnapshot != null)
            HistoryArtifactType.releaseGovernance,
          if (request.releaseEvidenceBundle != null)
            HistoryArtifactType.releaseEvidence,
          if (request.releaseSupplyChainSnapshot != null)
            HistoryArtifactType.releaseSupplyChain,
          if (request.cicdIntegrationSnapshot != null)
            HistoryArtifactType.cicdIntegration,
          if (request.cryptographicTrustSnapshot != null)
            HistoryArtifactType.cryptographicTrust,
        };
    final present =
        buildFromRequest(request).map((a) => a.artifactType).toSet();
    return selection.difference(present);
  }
}
