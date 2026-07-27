import '../interfaces/ast_provider.dart';
import '../interfaces/graph_provider.dart';
import '../models/graph/project_graph.dart';
import '../models/report/report_document.dart';
import '../models/report/report_format.dart';
import '../models/report/report_request.dart';
import '../models/report/report_status.dart';
import '../models/report/report_type.dart';
import 'report_composer.dart';
import 'report_exceptions.dart';
import 'report_input.dart';
import 'renderers/report_renderer.dart';
import 'report_validator.dart';
import 'sources/dashboard_report_source.dart';
import 'sources/observability_report_source.dart';
import 'sources/quality_gate_report_source.dart';
import 'sources/release_governance_report_source.dart';
import 'sources/release_evidence_report_source.dart';
import 'sources/release_supply_chain_report_source.dart';
import 'sources/cicd_integration_report_source.dart';
import 'sources/cryptographic_trust_report_source.dart';
import 'sources/persistent_artifact_report_source.dart';
import 'sources/ast_report_source.dart';
import 'sources/history_diff_report_source.dart';
import 'sources/metrics_report_source.dart';
import 'sources/mes_report_source.dart';
import 'sources/score_report_source.dart';

/// Coordinates report generation from platform providers and typed inputs.
class ReportEngine {
  ReportEngine({
    AstReportSource? astSource,
    GuardianReportSource? guardianSource,
    GraphReportSource? graphSource,
    MetricsReportSource? metricsSource,
    HistoryDiffReportSource? historySource,
    ScoreReportSource? scoreSource,
    MESReportSource? mesSource,
    DashboardReportSource? dashboardSource,
    ObservabilityReportSource? observabilitySource,
    QualityGateReportSource? qualityGateSource,
    ReleaseGovernanceReportSource? releaseGovernanceSource,
    ReleaseEvidenceReportSource? releaseEvidenceSource,
    ReleaseSupplyChainReportSource? releaseSupplyChainSource,
    CicdIntegrationReportSource? cicdIntegrationSource,
    CryptographicTrustReportSource? cryptographicTrustSource,
    PersistentArtifactReportSource? persistentArtifactSource,
    ReportComposer? composer,
    ReportValidator? validator,
    Map<ReportFormat, ReportRenderer>? renderers,
    AstProvider? astProvider,
    GraphProvider? graphProvider,
  })  : _astSource = astSource ?? const AstReportSource(),
        _guardianSource = guardianSource ?? const GuardianReportSource(),
        _graphSource = graphSource ?? const GraphReportSource(),
        _metricsSource = metricsSource ?? const MetricsReportSource(),
        _historySource = historySource ?? const HistoryDiffReportSource(),
        _scoreSource = scoreSource ?? const ScoreReportSource(),
        _mesSource = mesSource ?? const MESReportSource(),
        _dashboardSource = dashboardSource ?? const DashboardReportSource(),
        _observabilitySource =
            observabilitySource ?? const ObservabilityReportSource(),
        _qualityGateSource =
            qualityGateSource ?? const QualityGateReportSource(),
        _releaseGovernanceSource =
            releaseGovernanceSource ?? const ReleaseGovernanceReportSource(),
        _releaseEvidenceSource =
            releaseEvidenceSource ?? const ReleaseEvidenceReportSource(),
        _releaseSupplyChainSource =
            releaseSupplyChainSource ?? const ReleaseSupplyChainReportSource(),
        _cicdIntegrationSource =
            cicdIntegrationSource ?? const CicdIntegrationReportSource(),
        _cryptographicTrustSource =
            cryptographicTrustSource ?? const CryptographicTrustReportSource(),
        _persistentArtifactSource =
            persistentArtifactSource ?? const PersistentArtifactReportSource(),
        _composer = composer ?? const ReportComposer(),
        _validator = validator ?? const ReportValidator(),
        _renderers = renderers ?? const {},
        _astProvider = astProvider,
        _graphProvider = graphProvider;

  final AstReportSource _astSource;
  final GuardianReportSource _guardianSource;
  final GraphReportSource _graphSource;
  final MetricsReportSource _metricsSource;
  final HistoryDiffReportSource _historySource;
  final ScoreReportSource _scoreSource;
  final MESReportSource _mesSource;
  final DashboardReportSource _dashboardSource;
  final ObservabilityReportSource _observabilitySource;
  final QualityGateReportSource _qualityGateSource;
  final ReleaseGovernanceReportSource _releaseGovernanceSource;
  final ReleaseEvidenceReportSource _releaseEvidenceSource;
  final ReleaseSupplyChainReportSource _releaseSupplyChainSource;
  final CicdIntegrationReportSource _cicdIntegrationSource;
  final CryptographicTrustReportSource _cryptographicTrustSource;
  final PersistentArtifactReportSource _persistentArtifactSource;
  final ReportComposer _composer;
  final ReportValidator _validator;
  final Map<ReportFormat, ReportRenderer> _renderers;
  final AstProvider? _astProvider;
  final GraphProvider? _graphProvider;

  Set<ReportFormat> get supportedFormats => _renderers.keys.toSet();

  Future<ReportResult> generate(ReportRequest request) async {
    final spec = ReportTypeSpec.specs[request.reportType]!;
    final warnings = <String>[];
    final missingOptional = <String>[];

    AstReportInputData? ast;
    GuardianReportInputData? guardian;
    GraphReportInputData? graph;
    MetricsReportInputData? metrics;
    HistoryDiffReportInputData? history;
    EngineeringScoreReportInputData? engineeringScore;
    MESReportInputData? mes;
    DashboardReportInputData? dashboard;
    ObservabilityReportInputData? observability;
    QualityGateReportInputData? qualityGate;
    ReleaseGovernanceReportInputData? releaseGovernance;
    ReleaseEvidenceReportInputData? releaseEvidence;
    ReleaseSupplyChainReportInputData? releaseSupplyChain;
    CicdIntegrationReportInputData? cicdIntegration;
    CryptographicTrustReportInputData? cryptographicTrust;
    PersistentArtifactReportInputData? persistentArtifacts;

    if (spec.requiredSources.contains(ReportSourceKind.persistentArtifacts) ||
        spec.optionalSources.contains(ReportSourceKind.persistentArtifacts)) {
      persistentArtifacts = _resolvePersistentArtifacts(request);
      if (persistentArtifacts == null) {
        if (spec.requiredSources
            .contains(ReportSourceKind.persistentArtifacts)) {
          throw ReportSourceException(
            'Persistent Artifacts source is required for ${request.reportType.wireName}',
            sourceKind: 'persistentArtifacts',
          );
        }
        missingOptional.add('persistentArtifacts');
        warnings.add('Optional Persistent Artifacts source is unavailable');
      }
    }

    if (spec.requiredSources.contains(ReportSourceKind.releaseSupplyChain) ||
        spec.optionalSources.contains(ReportSourceKind.releaseSupplyChain)) {
      releaseSupplyChain = _resolveReleaseSupplyChain(request);
      if (releaseSupplyChain == null) {
        if (spec.requiredSources
            .contains(ReportSourceKind.releaseSupplyChain)) {
          throw ReportSourceException(
            'Release Supply Chain source is required for ${request.reportType.wireName}',
            sourceKind: 'releaseSupplyChain',
          );
        }
        missingOptional.add('releaseSupplyChain');
        warnings.add('Optional Release Supply Chain source is unavailable');
      }
    }

    if (spec.requiredSources.contains(ReportSourceKind.cryptographicTrust) ||
        spec.optionalSources.contains(ReportSourceKind.cryptographicTrust)) {
      cryptographicTrust = _resolveCryptographicTrust(request);
      if (cryptographicTrust == null) {
        if (spec.requiredSources
            .contains(ReportSourceKind.cryptographicTrust)) {
          throw ReportSourceException(
            'Cryptographic Trust source is required for ${request.reportType.wireName}',
            sourceKind: 'cryptographicTrust',
          );
        }
        missingOptional.add('cryptographicTrust');
        warnings.add('Optional Cryptographic Trust source is unavailable');
      }
    }

    if (spec.requiredSources.contains(ReportSourceKind.cicdIntegration) ||
        spec.optionalSources.contains(ReportSourceKind.cicdIntegration)) {
      cicdIntegration = _resolveCicdIntegration(request);
      if (cicdIntegration == null) {
        if (spec.requiredSources.contains(ReportSourceKind.cicdIntegration)) {
          throw ReportSourceException(
            'CI/CD Integration source is required for ${request.reportType.wireName}',
            sourceKind: 'cicdIntegration',
          );
        }
        missingOptional.add('cicdIntegration');
        warnings.add('Optional CI/CD Integration source is unavailable');
      }
    }

    if (spec.requiredSources.contains(ReportSourceKind.releaseEvidence) ||
        spec.optionalSources.contains(ReportSourceKind.releaseEvidence)) {
      releaseEvidence = _resolveReleaseEvidence(request);
      if (releaseEvidence == null) {
        if (spec.requiredSources.contains(ReportSourceKind.releaseEvidence)) {
          throw ReportSourceException(
            'Release Evidence source is required for ${request.reportType.wireName}',
            sourceKind: 'releaseEvidence',
          );
        }
        missingOptional.add('releaseEvidence');
        warnings.add('Optional Release Evidence source is unavailable');
      }
    }

    if (spec.requiredSources.contains(ReportSourceKind.releaseGovernance) ||
        spec.optionalSources.contains(ReportSourceKind.releaseGovernance)) {
      releaseGovernance = _resolveReleaseGovernance(request);
      if (releaseGovernance == null) {
        if (spec.requiredSources.contains(ReportSourceKind.releaseGovernance)) {
          throw ReportSourceException(
            'Release Governance source is required for ${request.reportType.wireName}',
            sourceKind: 'releaseGovernance',
          );
        }
        missingOptional.add('releaseGovernance');
        warnings.add('Optional Release Governance source is unavailable');
      }
    }

    if (spec.requiredSources.contains(ReportSourceKind.qualityGate) ||
        spec.optionalSources.contains(ReportSourceKind.qualityGate)) {
      qualityGate = _resolveQualityGate(request);
      if (qualityGate == null) {
        if (spec.requiredSources.contains(ReportSourceKind.qualityGate)) {
          throw ReportSourceException(
            'Quality Gate source is required for ${request.reportType.wireName}',
            sourceKind: 'qualityGate',
          );
        }
        missingOptional.add('qualityGate');
        warnings.add('Optional Quality Gate source is unavailable');
      }
    }

    if (spec.requiredSources.contains(ReportSourceKind.observability) ||
        spec.optionalSources.contains(ReportSourceKind.observability)) {
      observability = _resolveObservability(request);
      if (observability == null) {
        if (spec.requiredSources.contains(ReportSourceKind.observability)) {
          throw ReportSourceException(
            'Observability source is required for ${request.reportType.wireName}',
            sourceKind: 'observability',
          );
        }
        missingOptional.add('observability');
        warnings.add('Optional Observability source is unavailable');
      }
    }

    if (spec.requiredSources.contains(ReportSourceKind.dashboard) ||
        spec.optionalSources.contains(ReportSourceKind.dashboard)) {
      dashboard = _resolveDashboard(request);
      if (dashboard == null) {
        if (spec.requiredSources.contains(ReportSourceKind.dashboard)) {
          throw ReportSourceException(
            'Dashboard source is required for ${request.reportType.wireName}',
            sourceKind: 'dashboard',
          );
        }
        missingOptional.add('dashboard');
        warnings.add('Optional Dashboard source is unavailable');
      }
    }

    if (spec.requiredSources.contains(ReportSourceKind.mes) ||
        spec.optionalSources.contains(ReportSourceKind.mes)) {
      mes = _resolveMes(request);
      if (mes == null) {
        if (spec.requiredSources.contains(ReportSourceKind.mes)) {
          throw ReportSourceException(
            'MES source is required for ${request.reportType.wireName}',
            sourceKind: 'mes',
          );
        }
        missingOptional.add('mes');
        warnings.add('Optional MES source is unavailable');
      }
    }

    if (spec.requiredSources.contains(ReportSourceKind.score) ||
        spec.optionalSources.contains(ReportSourceKind.score)) {
      engineeringScore = _resolveScore(request);
      if (engineeringScore == null) {
        if (spec.requiredSources.contains(ReportSourceKind.score)) {
          throw ReportSourceException(
            'Score source is required for ${request.reportType.wireName}',
            sourceKind: 'score',
          );
        }
        missingOptional.add('score');
        warnings.add('Optional Score source is unavailable');
      }
    }

    if (spec.requiredSources.contains(ReportSourceKind.history) ||
        spec.optionalSources.contains(ReportSourceKind.history)) {
      history = _resolveHistory(request);
      if (history == null) {
        if (spec.requiredSources.contains(ReportSourceKind.history)) {
          throw ReportSourceException(
            'History source is required for ${request.reportType.wireName}',
            sourceKind: 'history',
          );
        }
        missingOptional.add('history');
        warnings.add('Optional History source is unavailable');
      }
    }

    if (spec.requiredSources.contains(ReportSourceKind.metrics) ||
        spec.optionalSources.contains(ReportSourceKind.metrics)) {
      metrics = _resolveMetrics(request);
      if (metrics == null) {
        if (spec.requiredSources.contains(ReportSourceKind.metrics)) {
          throw ReportSourceException(
            'Metrics source is required for ${request.reportType.wireName}',
            sourceKind: 'metrics',
          );
        }
        missingOptional.add('metrics');
        warnings.add('Optional Metrics source is unavailable');
      }
    }

    if (spec.requiredSources.contains(ReportSourceKind.ast) ||
        spec.optionalSources.contains(ReportSourceKind.ast)) {
      ast = _resolveAst(request);
      if (ast == null) {
        if (spec.requiredSources.contains(ReportSourceKind.ast)) {
          throw ReportSourceException(
            'AST source is required for ${request.reportType.wireName}',
            sourceKind: 'ast',
          );
        }
        missingOptional.add('ast');
        warnings.add('Optional AST source is unavailable');
      }
    }

    if (spec.requiredSources.contains(ReportSourceKind.guardian) ||
        spec.optionalSources.contains(ReportSourceKind.guardian)) {
      guardian = _resolveGuardian(request);
      if (guardian == null) {
        if (spec.requiredSources.contains(ReportSourceKind.guardian)) {
          throw ReportSourceException(
            'Guardian source is required for ${request.reportType.wireName}',
            sourceKind: 'guardian',
          );
        }
        missingOptional.add('guardian');
        warnings.add('Optional Guardian source is unavailable');
      }
    }

    if (spec.requiredSources.contains(ReportSourceKind.graph) ||
        spec.optionalSources.contains(ReportSourceKind.graph)) {
      graph = await _resolveGraph(request);
      if (graph == null) {
        if (spec.requiredSources.contains(ReportSourceKind.graph)) {
          throw ReportSourceException(
            'Graph source is required for ${request.reportType.wireName}',
            sourceKind: 'graph',
          );
        }
        missingOptional.add('graph');
        warnings.add('Optional Graph source is unavailable');
      }
    }

    final input = ReportInput(
      projectId: request.projectId,
      reportType: request.reportType,
      ast: ast,
      guardian: guardian,
      graph: graph,
      metrics: metrics,
      history: history,
      engineeringScore: engineeringScore,
      mes: mes,
      dashboard: dashboard,
      observability: observability,
      qualityGate: qualityGate,
      releaseGovernance: releaseGovernance,
      releaseEvidence: releaseEvidence,
      releaseSupplyChain: releaseSupplyChain,
      cicdIntegration: cicdIntegration,
      cryptographicTrust: cryptographicTrust,
      persistentArtifacts: persistentArtifacts,
      warnings: warnings,
      missingOptionalSources: missingOptional,
      sourceSnapshotId: request.sourceSnapshotId,
      gitRef: request.gitRef,
    );

    final document = _composer.compose(input);
    final validation = _validator.validate(
      document,
      supportedFormats: supportedFormats,
    );

    if (!validation.isValid) {
      throw ReportException(
        'Report validation failed: ${validation.errors.join('; ')}',
        code: 'validation_failed',
      );
    }

    final allWarnings = [...warnings, ...validation.warnings];
    final rendered = _renderers.containsKey(request.format)
        ? render(document, request.format)
        : null;

    return ReportResult(
      status: allWarnings.isEmpty ? ReportStatus.success : ReportStatus.warning,
      document: document,
      rendered: rendered,
      warnings: allWarnings,
    );
  }

  String render(ReportDocument document, ReportFormat format) {
    final renderer = _renderers[format];
    if (renderer == null) {
      throw ReportException(
        'Unsupported report format: ${format.wireName}',
        code: 'unsupported_format',
      );
    }
    return renderer.render(document);
  }

  AstReportInputData? _resolveAst(ReportRequest request) {
    if (request.astReport != null && request.astReport!.isNotEmpty) {
      return _astSource.fromMap(request.astReport!);
    }
    final provider = _astProvider;
    if (provider == null) return null;
    final report = provider.loadReport();
    if (report.isEmpty) return null;
    return _astSource.fromMap(report);
  }

  GuardianReportInputData? _resolveGuardian(ReportRequest request) {
    if (request.guardianAnalysis != null &&
        request.guardianAnalysis!.isNotEmpty) {
      return _guardianSource.fromMap(request.guardianAnalysis!);
    }
    return null;
  }

  Future<GraphReportInputData?> _resolveGraph(ReportRequest request) async {
    if (request.projectGraph != null && request.projectGraph!.isNotEmpty) {
      return _graphSource.fromProjectGraph(
        ProjectGraph.fromJson(request.projectGraph!),
      );
    }
    final provider = _graphProvider;
    if (provider == null) return null;
    return _graphSource.fromProvider(provider);
  }

  MetricsReportInputData? _resolveMetrics(ReportRequest request) {
    if (request.metricsSnapshot != null &&
        request.metricsSnapshot!.isNotEmpty) {
      return _metricsSource.fromMap(request.metricsSnapshot!);
    }
    return null;
  }

  HistoryDiffReportInputData? _resolveHistory(ReportRequest request) {
    if (request.historyDiff != null && request.historyDiff!.isNotEmpty) {
      return _historySource.fromMap(request.historyDiff!);
    }
    return null;
  }

  EngineeringScoreReportInputData? _resolveScore(ReportRequest request) {
    if (request.engineeringScore != null &&
        request.engineeringScore!.isNotEmpty) {
      return _scoreSource.fromMap(request.engineeringScore!);
    }
    return null;
  }

  MESReportInputData? _resolveMes(ReportRequest request) {
    if (request.mesSnapshot != null && request.mesSnapshot!.isNotEmpty) {
      return _mesSource.fromMap(request.mesSnapshot!);
    }
    return null;
  }

  DashboardReportInputData? _resolveDashboard(ReportRequest request) {
    if (request.dashboardSnapshot != null &&
        request.dashboardSnapshot!.isNotEmpty) {
      return _dashboardSource.fromMap(request.dashboardSnapshot!);
    }
    return null;
  }

  ObservabilityReportInputData? _resolveObservability(ReportRequest request) {
    if (request.telemetrySnapshot != null &&
        request.telemetrySnapshot!.isNotEmpty) {
      return _observabilitySource.fromMap(request.telemetrySnapshot!);
    }
    return null;
  }

  QualityGateReportInputData? _resolveQualityGate(ReportRequest request) {
    if (request.qualityGateSnapshot != null &&
        request.qualityGateSnapshot!.isNotEmpty) {
      return _qualityGateSource.fromMap(request.qualityGateSnapshot!);
    }
    return null;
  }

  ReleaseGovernanceReportInputData? _resolveReleaseGovernance(
    ReportRequest request,
  ) {
    if (request.releaseDecisionSnapshot != null &&
        request.releaseDecisionSnapshot!.isNotEmpty) {
      return _releaseGovernanceSource.fromMap(request.releaseDecisionSnapshot!);
    }
    return null;
  }

  ReleaseEvidenceReportInputData? _resolveReleaseEvidence(
    ReportRequest request,
  ) {
    if (request.releaseEvidenceBundle != null &&
        request.releaseEvidenceBundle!.isNotEmpty) {
      return _releaseEvidenceSource.fromMap(request.releaseEvidenceBundle!);
    }
    return null;
  }

  ReleaseSupplyChainReportInputData? _resolveReleaseSupplyChain(
    ReportRequest request,
  ) {
    if (request.releaseSupplyChainSnapshot != null &&
        request.releaseSupplyChainSnapshot!.isNotEmpty) {
      return _releaseSupplyChainSource.fromMap(
        request.releaseSupplyChainSnapshot!,
      );
    }
    return null;
  }

  CicdIntegrationReportInputData? _resolveCicdIntegration(
    ReportRequest request,
  ) {
    if (request.cicdIntegrationSnapshot != null &&
        request.cicdIntegrationSnapshot!.isNotEmpty) {
      return _cicdIntegrationSource.fromMap(request.cicdIntegrationSnapshot!);
    }
    return null;
  }

  CryptographicTrustReportInputData? _resolveCryptographicTrust(
    ReportRequest request,
  ) {
    if (request.cryptographicTrustSnapshot != null &&
        request.cryptographicTrustSnapshot!.isNotEmpty) {
      return _cryptographicTrustSource.fromMap(
        request.cryptographicTrustSnapshot!,
      );
    }
    return null;
  }

  PersistentArtifactReportInputData? _resolvePersistentArtifacts(
    ReportRequest request,
  ) {
    if (request.persistentArtifactSnapshot != null &&
        request.persistentArtifactSnapshot!.isNotEmpty) {
      return _persistentArtifactSource
          .fromMap(request.persistentArtifactSnapshot!);
    }
    return null;
  }
}
