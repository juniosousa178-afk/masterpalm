import '../core/provider_registry.dart';
import '../interfaces/graph_provider.dart';
import '../interfaces/guardian_provider.dart';
import '../interfaces/history_provider.dart';
import '../interfaces/mes_provider.dart';
import '../interfaces/metrics_provider.dart';
import '../interfaces/quality_gate_provider.dart';
import '../interfaces/release_governance_provider.dart';
import '../interfaces/release_evidence_provider.dart';
import '../interfaces/release_supply_chain_provider.dart';
import '../interfaces/cicd_integration_provider.dart';
import '../interfaces/cryptographic_trust_provider.dart';
import '../interfaces/score_provider.dart';
import '../models/dashboard/dashboard_enums.dart';
import '../models/dashboard/dashboard_request.dart';
import '../models/dashboard/dashboard_snapshot.dart';
import '../models/graph/project_graph.dart';
import '../models/history/history_diff.dart';
import '../models/history/history_snapshot.dart';
import '../models/mes/mes_snapshot.dart';
import '../models/metrics/metrics_snapshot.dart';
import '../models/observability/telemetry_snapshot.dart';
import '../models/quality_gate/quality_gate_snapshot.dart';
import '../models/release_governance/release_decision_snapshot.dart';
import '../models/release_evidence/release_evidence_bundle.dart';
import '../models/release_supply_chain/release_supply_chain_snapshot.dart';
import '../models/cicd_integration/cicd_integration_snapshot.dart';
import '../models/cryptographic_trust/cryptographic_trust_snapshot.dart';
import '../models/score/score_snapshot.dart';

/// Container for resolved dashboard source artifacts.
class DashboardResolvedSources {
  const DashboardResolvedSources({
    this.metrics,
    this.history,
    this.historyDiff,
    this.score,
    this.mes,
    this.telemetry,
    this.qualityGate,
    this.releaseGovernance,
    this.releaseEvidence,
    this.releaseSupplyChain,
    this.cicdIntegration,
    this.cryptographicTrust,
    this.graph,
    this.guardianAnalysis,
    this.references = const [],
    this.limitations = const [],
  });

  final MetricsSnapshot? metrics;
  final HistorySnapshot? history;
  final HistoryDiff? historyDiff;
  final EngineeringScoreSnapshot? score;
  final MESSnapshot? mes;
  final TelemetrySnapshot? telemetry;
  final QualityGateSnapshot? qualityGate;
  final ReleaseDecisionSnapshot? releaseGovernance;
  final ReleaseEvidenceBundle? releaseEvidence;
  final ReleaseSupplyChainSnapshot? releaseSupplyChain;
  final CicdIntegrationSnapshot? cicdIntegration;
  final CryptographicTrustSnapshot? cryptographicTrust;
  final ProjectGraph? graph;
  final Map<String, dynamic>? guardianAnalysis;
  final List<DashboardSourceReference> references;
  final List<String> limitations;

  DashboardResolvedSources copyWith({
    MetricsSnapshot? metrics,
    HistorySnapshot? history,
    HistoryDiff? historyDiff,
    EngineeringScoreSnapshot? score,
    MESSnapshot? mes,
    TelemetrySnapshot? telemetry,
    QualityGateSnapshot? qualityGate,
    ReleaseDecisionSnapshot? releaseGovernance,
    ReleaseEvidenceBundle? releaseEvidence,
    ReleaseSupplyChainSnapshot? releaseSupplyChain,
    CicdIntegrationSnapshot? cicdIntegration,
    CryptographicTrustSnapshot? cryptographicTrust,
    ProjectGraph? graph,
    Map<String, dynamic>? guardianAnalysis,
    List<DashboardSourceReference>? references,
    List<String>? limitations,
  }) {
    return DashboardResolvedSources(
      metrics: metrics ?? this.metrics,
      history: history ?? this.history,
      historyDiff: historyDiff ?? this.historyDiff,
      score: score ?? this.score,
      mes: mes ?? this.mes,
      telemetry: telemetry ?? this.telemetry,
      qualityGate: qualityGate ?? this.qualityGate,
      releaseGovernance: releaseGovernance ?? this.releaseGovernance,
      releaseEvidence: releaseEvidence ?? this.releaseEvidence,
      releaseSupplyChain: releaseSupplyChain ?? this.releaseSupplyChain,
      cicdIntegration: cicdIntegration ?? this.cicdIntegration,
      cryptographicTrust: cryptographicTrust ?? this.cryptographicTrust,
      graph: graph ?? this.graph,
      guardianAnalysis: guardianAnalysis ?? this.guardianAnalysis,
      references: references ?? this.references,
      limitations: limitations ?? this.limitations,
    );
  }
}

/// Resolves dashboard sources from injected artifacts and providers.
class DashboardSourceResolver {
  DashboardSourceResolver({
    required MetricsProvider metricsProvider,
    required HistoryProvider historyProvider,
    required ScoreProvider scoreProvider,
    required MESProvider mesProvider,
    GraphProvider? graphProvider,
    GuardianProvider? guardianProvider,
    ProviderRegistry? registry,
  })  : _metricsProvider = metricsProvider,
        _historyProvider = historyProvider,
        _scoreProvider = scoreProvider,
        _mesProvider = mesProvider,
        _graphProvider = graphProvider,
        _guardianProvider = guardianProvider,
        _registry = registry;

  final MetricsProvider _metricsProvider;
  final HistoryProvider _historyProvider;
  final ScoreProvider _scoreProvider;
  final MESProvider _mesProvider;
  final GraphProvider? _graphProvider;
  final GuardianProvider? _guardianProvider;
  final ProviderRegistry? _registry;

  Future<DashboardResolvedSources> resolve(DashboardRequest request) async {
    final refs = <DashboardSourceReference>[];
    final limitations = <String>[];

    final metrics = await _resolveMetrics(request, refs, limitations);
    final history = await _resolveHistory(request, refs, limitations);
    final historyDiff = request.historyDiff;
    if (historyDiff != null) {
      final diffId =
          '${historyDiff.fromSnapshotId}:${historyDiff.toSnapshotId}';
      refs.add(
        _reference(
          id: 'historyDiff:$diffId',
          sourceType: DashboardSourceType.historyDiff,
          providerType: DashboardProviderType.history,
          artifactId: diffId,
          projectId: request.projectId,
          createdAt: request.createdAt,
          fingerprint: diffId,
          resolutionMode: DashboardSourceResolutionMode.injected,
        ),
      );
    }

    final score = await _resolveScore(request, refs, limitations);
    final mes = await _resolveMes(request, refs, limitations);
    final graph = await _resolveGraph(request, refs, limitations);
    final guardian = _resolveGuardian(request, refs, limitations);
    final telemetry = request.telemetrySnapshot;
    if (telemetry != null) {
      refs.add(
        _reference(
          id: 'telemetry:${telemetry.metadata.telemetrySnapshotId}',
          sourceType: DashboardSourceType.telemetry,
          providerType: DashboardProviderType.observability,
          artifactId: telemetry.metadata.telemetrySnapshotId,
          projectId: request.projectId,
          createdAt: telemetry.metadata.createdAt,
          fingerprint: telemetry.metadata.telemetryFingerprint,
          resolutionMode: DashboardSourceResolutionMode.injected,
        ),
      );
    }

    final qualityGate = await _resolveQualityGate(request, refs, limitations);
    final releaseGovernance =
        await _resolveReleaseGovernance(request, refs, limitations);
    final releaseEvidence =
        await _resolveReleaseEvidence(request, refs, limitations);
    final releaseSupplyChain =
        await _resolveReleaseSupplyChain(request, refs, limitations);
    final cicdIntegration =
        await _resolveCicdIntegration(request, refs, limitations);
    final cryptographicTrust =
        await _resolveCryptographicTrust(request, refs, limitations);

    refs.sort((a, b) => a.referenceId.compareTo(b.referenceId));

    return DashboardResolvedSources(
      metrics: metrics,
      history: history,
      historyDiff: historyDiff,
      score: score,
      mes: mes,
      telemetry: telemetry,
      qualityGate: qualityGate,
      releaseGovernance: releaseGovernance,
      releaseEvidence: releaseEvidence,
      releaseSupplyChain: releaseSupplyChain,
      cicdIntegration: cicdIntegration,
      cryptographicTrust: cryptographicTrust,
      graph: graph,
      guardianAnalysis: guardian,
      references: refs,
      limitations: limitations,
    );
  }

  Future<MetricsSnapshot?> _resolveMetrics(
    DashboardRequest request,
    List<DashboardSourceReference> refs,
    List<String> limitations,
  ) async {
    if (request.metricsSnapshot != null) {
      final snapshot = request.metricsSnapshot!;
      refs.add(_metricsRef(snapshot, DashboardSourceResolutionMode.injected));
      return snapshot;
    }
    if (request.metricsSnapshotId != null) {
      final loaded = await _metricsProvider.load();
      if (loaded != null &&
          loaded.metadata.snapshotId == request.metricsSnapshotId) {
        refs.add(_metricsRef(loaded, DashboardSourceResolutionMode.byId));
        return loaded;
      }
      limitations
          .add('Metrics snapshot ${request.metricsSnapshotId} unavailable');
      refs.add(_unavailableRef(
        referenceId: 'metrics:${request.metricsSnapshotId}',
        sourceType: DashboardSourceType.metrics,
        providerType: DashboardProviderType.metrics,
        artifactId: request.metricsSnapshotId!,
        projectId: request.projectId,
      ));
      return null;
    }
    if (request.useLatest) {
      final loaded = await _metricsProvider.load();
      if (loaded != null) {
        refs.add(_metricsRef(loaded, DashboardSourceResolutionMode.latest));
        return loaded;
      }
      limitations.add('Latest metrics snapshot unavailable');
      return null;
    }
    return null;
  }

  Future<HistorySnapshot?> _resolveHistory(
    DashboardRequest request,
    List<DashboardSourceReference> refs,
    List<String> limitations,
  ) async {
    if (request.historySnapshot != null) {
      final snapshot = request.historySnapshot!;
      refs.add(_historyRef(snapshot, DashboardSourceResolutionMode.injected));
      return snapshot;
    }
    if (request.historySnapshotId != null) {
      final loaded =
          await _historyProvider.loadById(request.historySnapshotId!);
      if (loaded != null) {
        refs.add(_historyRef(loaded, DashboardSourceResolutionMode.byId));
        return loaded;
      }
      limitations
          .add('History snapshot ${request.historySnapshotId} unavailable');
      refs.add(_unavailableRef(
        referenceId: 'history:${request.historySnapshotId}',
        sourceType: DashboardSourceType.history,
        providerType: DashboardProviderType.history,
        artifactId: request.historySnapshotId!,
        projectId: request.projectId,
      ));
      return null;
    }
    if (request.useLatest) {
      final loaded =
          await _historyProvider.latest(projectId: request.projectId);
      if (loaded != null) {
        refs.add(_historyRef(loaded, DashboardSourceResolutionMode.latest));
        return loaded;
      }
      limitations.add('Latest history snapshot unavailable');
      return null;
    }
    return null;
  }

  Future<EngineeringScoreSnapshot?> _resolveScore(
    DashboardRequest request,
    List<DashboardSourceReference> refs,
    List<String> limitations,
  ) async {
    if (request.engineeringScoreSnapshot != null) {
      final snapshot = request.engineeringScoreSnapshot!;
      refs.add(_scoreRef(snapshot, DashboardSourceResolutionMode.injected));
      return snapshot;
    }
    if (request.scoreSnapshotId != null) {
      final loaded =
          await _scoreProvider.load(snapshotId: request.scoreSnapshotId!);
      if (loaded != null) {
        refs.add(_scoreRef(loaded, DashboardSourceResolutionMode.byId));
        return loaded;
      }
      limitations.add('Score snapshot ${request.scoreSnapshotId} unavailable');
      refs.add(_unavailableRef(
        referenceId: 'score:${request.scoreSnapshotId}',
        sourceType: DashboardSourceType.score,
        providerType: DashboardProviderType.score,
        artifactId: request.scoreSnapshotId!,
        projectId: request.projectId,
      ));
      return null;
    }
    if (request.useLatest) {
      final loaded = await _scoreProvider.latest(projectId: request.projectId);
      if (loaded != null) {
        refs.add(_scoreRef(loaded, DashboardSourceResolutionMode.latest));
        return loaded;
      }
      limitations.add('Latest score snapshot unavailable');
      return null;
    }
    return null;
  }

  Future<MESSnapshot?> _resolveMes(
    DashboardRequest request,
    List<DashboardSourceReference> refs,
    List<String> limitations,
  ) async {
    if (request.mesSnapshot != null) {
      final snapshot = request.mesSnapshot!;
      refs.add(_mesRef(snapshot, DashboardSourceResolutionMode.injected));
      return snapshot;
    }
    if (request.mesSnapshotId != null) {
      final loaded = await _mesProvider.load(request.mesSnapshotId!);
      if (loaded != null) {
        refs.add(_mesRef(loaded, DashboardSourceResolutionMode.byId));
        return loaded;
      }
      limitations.add('MES snapshot ${request.mesSnapshotId} unavailable');
      refs.add(_unavailableRef(
        referenceId: 'mes:${request.mesSnapshotId}',
        sourceType: DashboardSourceType.mes,
        providerType: DashboardProviderType.mes,
        artifactId: request.mesSnapshotId!,
        projectId: request.projectId,
      ));
      return null;
    }
    if (request.useLatest) {
      final loaded = await _mesProvider.latest(projectId: request.projectId);
      if (loaded != null) {
        refs.add(_mesRef(loaded, DashboardSourceResolutionMode.latest));
        return loaded;
      }
      limitations.add('Latest MES snapshot unavailable');
      return null;
    }
    return null;
  }

  Future<QualityGateSnapshot?> _resolveQualityGate(
    DashboardRequest request,
    List<DashboardSourceReference> refs,
    List<String> limitations,
  ) async {
    if (request.qualityGateSnapshot != null) {
      final snapshot = request.qualityGateSnapshot!;
      refs.add(
          _qualityGateRef(snapshot, DashboardSourceResolutionMode.injected));
      return snapshot;
    }

    final provider = _qualityGateProvider;
    if (provider == null) {
      if (request.qualityGateSnapshotId != null) {
        limitations.add(
          'Quality Gate provider unavailable for byId resolution',
        );
      }
      return null;
    }

    if (request.qualityGateSnapshotId != null) {
      final loaded = await provider.load(request.qualityGateSnapshotId!);
      if (loaded != null) {
        refs.add(_qualityGateRef(loaded, DashboardSourceResolutionMode.byId));
        return loaded;
      }
      limitations.add(
        'Quality Gate snapshot ${request.qualityGateSnapshotId} unavailable',
      );
      refs.add(_unavailableRef(
        referenceId: 'qualityGate:${request.qualityGateSnapshotId}',
        sourceType: DashboardSourceType.qualityGate,
        providerType: DashboardProviderType.qualityGate,
        artifactId: request.qualityGateSnapshotId!,
        projectId: request.projectId,
      ));
      return null;
    }

    if (request.useLatest) {
      final loaded = await provider.latest(projectId: request.projectId);
      if (loaded != null) {
        refs.add(_qualityGateRef(loaded, DashboardSourceResolutionMode.latest));
        return loaded;
      }
      limitations.add('Latest quality gate snapshot unavailable');
      return null;
    }

    return null;
  }

  Future<ReleaseDecisionSnapshot?> _resolveReleaseGovernance(
    DashboardRequest request,
    List<DashboardSourceReference> refs,
    List<String> limitations,
  ) async {
    if (request.releaseDecisionSnapshot != null) {
      final snapshot = request.releaseDecisionSnapshot!;
      refs.add(_releaseGovernanceRef(
        snapshot,
        DashboardSourceResolutionMode.injected,
      ));
      return snapshot;
    }

    final provider = _releaseGovernanceProvider;
    if (provider == null) {
      if (request.releaseDecisionSnapshotId != null) {
        limitations.add(
          'Release Governance provider unavailable for byId resolution',
        );
      }
      return null;
    }

    if (request.releaseDecisionSnapshotId != null) {
      final loaded = await provider.load(request.releaseDecisionSnapshotId!);
      if (loaded != null) {
        refs.add(
          _releaseGovernanceRef(loaded, DashboardSourceResolutionMode.byId),
        );
        return loaded;
      }
      limitations.add(
        'Release Governance snapshot ${request.releaseDecisionSnapshotId} unavailable',
      );
      refs.add(_unavailableRef(
        referenceId: 'releaseGovernance:${request.releaseDecisionSnapshotId}',
        sourceType: DashboardSourceType.releaseGovernance,
        providerType: DashboardProviderType.releaseGovernance,
        artifactId: request.releaseDecisionSnapshotId!,
        projectId: request.projectId,
      ));
      return null;
    }

    if (request.useLatest) {
      final loaded = await provider.latest(projectId: request.projectId);
      if (loaded != null) {
        refs.add(
          _releaseGovernanceRef(loaded, DashboardSourceResolutionMode.latest),
        );
        return loaded;
      }
      limitations.add('Latest release governance snapshot unavailable');
      return null;
    }

    return null;
  }

  Future<ReleaseEvidenceBundle?> _resolveReleaseEvidence(
    DashboardRequest request,
    List<DashboardSourceReference> refs,
    List<String> limitations,
  ) async {
    if (request.releaseEvidenceBundle != null) {
      final bundle = request.releaseEvidenceBundle!;
      refs.add(_releaseEvidenceRef(
        bundle,
        DashboardSourceResolutionMode.injected,
      ));
      return bundle;
    }

    final provider = _releaseEvidenceProvider;
    if (provider == null) {
      if (request.releaseEvidenceBundleId != null) {
        limitations.add(
          'Release Evidence provider unavailable for byId resolution',
        );
      }
      return null;
    }

    if (request.releaseEvidenceBundleId != null) {
      final loaded = await provider.load(request.releaseEvidenceBundleId!);
      if (loaded != null) {
        refs.add(
            _releaseEvidenceRef(loaded, DashboardSourceResolutionMode.byId));
        return loaded;
      }
      limitations.add(
        'Release Evidence bundle ${request.releaseEvidenceBundleId} unavailable',
      );
      refs.add(_unavailableRef(
        referenceId: 'releaseEvidence:${request.releaseEvidenceBundleId}',
        sourceType: DashboardSourceType.releaseEvidence,
        providerType: DashboardProviderType.releaseEvidence,
        artifactId: request.releaseEvidenceBundleId!,
        projectId: request.projectId,
      ));
      return null;
    }

    if (request.useLatest) {
      final loaded = await provider.latest(projectId: request.projectId);
      if (loaded != null) {
        refs.add(
          _releaseEvidenceRef(loaded, DashboardSourceResolutionMode.latest),
        );
        return loaded;
      }
      limitations.add('Latest release evidence bundle unavailable');
      return null;
    }

    return null;
  }

  Future<ReleaseSupplyChainSnapshot?> _resolveReleaseSupplyChain(
    DashboardRequest request,
    List<DashboardSourceReference> refs,
    List<String> limitations,
  ) async {
    if (request.releaseSupplyChainSnapshot != null) {
      final snapshot = request.releaseSupplyChainSnapshot!;
      refs.add(_releaseSupplyChainRef(
        snapshot,
        DashboardSourceResolutionMode.injected,
      ));
      return snapshot;
    }

    final provider = _releaseSupplyChainProvider;
    if (provider == null) {
      if (request.releaseSupplyChainSnapshotId != null) {
        limitations.add(
          'Release Supply Chain provider unavailable for byId resolution',
        );
      }
      return null;
    }

    if (request.releaseSupplyChainSnapshotId != null) {
      final loaded = await provider.load(request.releaseSupplyChainSnapshotId!);
      if (loaded != null) {
        refs.add(
          _releaseSupplyChainRef(loaded, DashboardSourceResolutionMode.byId),
        );
        return loaded;
      }
      limitations.add(
        'Release Supply Chain snapshot ${request.releaseSupplyChainSnapshotId} unavailable',
      );
      refs.add(_unavailableRef(
        referenceId:
            'releaseSupplyChain:${request.releaseSupplyChainSnapshotId}',
        sourceType: DashboardSourceType.releaseSupplyChain,
        providerType: DashboardProviderType.releaseSupplyChain,
        artifactId: request.releaseSupplyChainSnapshotId!,
        projectId: request.projectId,
      ));
      return null;
    }

    if (request.useLatest) {
      final loaded = await provider.latest(projectId: request.projectId);
      if (loaded != null) {
        refs.add(
          _releaseSupplyChainRef(loaded, DashboardSourceResolutionMode.latest),
        );
        return loaded;
      }
      limitations.add('Latest release supply chain snapshot unavailable');
      return null;
    }

    return null;
  }

  Future<CicdIntegrationSnapshot?> _resolveCicdIntegration(
    DashboardRequest request,
    List<DashboardSourceReference> refs,
    List<String> limitations,
  ) async {
    if (request.cicdIntegrationSnapshot != null) {
      final snapshot = request.cicdIntegrationSnapshot!;
      refs.add(
        _cicdIntegrationRef(snapshot, DashboardSourceResolutionMode.injected),
      );
      return snapshot;
    }

    final provider = _cicdIntegrationProvider;
    if (provider == null) {
      if (request.cicdIntegrationSnapshotId != null) {
        limitations.add(
          'CI/CD Integration provider unavailable for byId resolution',
        );
      }
      return null;
    }

    if (request.cicdIntegrationSnapshotId != null) {
      final loaded = await provider.load(request.cicdIntegrationSnapshotId!);
      if (loaded != null) {
        refs.add(
          _cicdIntegrationRef(loaded, DashboardSourceResolutionMode.byId),
        );
        return loaded;
      }
      limitations.add(
        'CI/CD Integration snapshot ${request.cicdIntegrationSnapshotId} unavailable',
      );
      refs.add(_unavailableRef(
        referenceId: 'cicdIntegration:${request.cicdIntegrationSnapshotId}',
        sourceType: DashboardSourceType.cicdIntegration,
        providerType: DashboardProviderType.cicdIntegration,
        artifactId: request.cicdIntegrationSnapshotId!,
        projectId: request.projectId,
      ));
      return null;
    }

    if (request.useLatest) {
      final loaded = await provider.latest(projectId: request.projectId);
      if (loaded != null) {
        refs.add(
          _cicdIntegrationRef(loaded, DashboardSourceResolutionMode.latest),
        );
        return loaded;
      }
      limitations.add('Latest CI/CD integration snapshot unavailable');
      return null;
    }

    return null;
  }

  Future<CryptographicTrustSnapshot?> _resolveCryptographicTrust(
    DashboardRequest request,
    List<DashboardSourceReference> refs,
    List<String> limitations,
  ) async {
    if (request.cryptographicTrustSnapshot != null) {
      final snapshot = request.cryptographicTrustSnapshot!;
      refs.add(
        _cryptographicTrustRef(
          snapshot,
          DashboardSourceResolutionMode.injected,
        ),
      );
      return snapshot;
    }

    final provider = _cryptographicTrustProvider;
    if (provider == null) {
      if (request.cryptographicTrustSnapshotId != null) {
        limitations.add(
          'Cryptographic Trust provider unavailable for byId resolution',
        );
      }
      return null;
    }

    if (request.cryptographicTrustSnapshotId != null) {
      final loaded = await provider.load(request.cryptographicTrustSnapshotId!);
      if (loaded != null) {
        refs.add(
          _cryptographicTrustRef(loaded, DashboardSourceResolutionMode.byId),
        );
        return loaded;
      }
      limitations.add(
        'Cryptographic Trust snapshot ${request.cryptographicTrustSnapshotId} unavailable',
      );
      refs.add(_unavailableRef(
        referenceId:
            'cryptographicTrust:${request.cryptographicTrustSnapshotId}',
        sourceType: DashboardSourceType.cryptographicTrust,
        providerType: DashboardProviderType.cryptographicTrust,
        artifactId: request.cryptographicTrustSnapshotId!,
        projectId: request.projectId,
      ));
      return null;
    }

    if (request.useLatest) {
      final loaded = await provider.latest(projectId: request.projectId);
      if (loaded != null) {
        refs.add(
          _cryptographicTrustRef(loaded, DashboardSourceResolutionMode.latest),
        );
        return loaded;
      }
      limitations.add('Latest cryptographic trust snapshot unavailable');
      return null;
    }

    return null;
  }

  ReleaseEvidenceProvider? get _releaseEvidenceProvider {
    final registry = _registry;
    if (registry == null || !registry.isRegistered<ReleaseEvidenceProvider>()) {
      return null;
    }
    return registry.resolve<ReleaseEvidenceProvider>();
  }

  ReleaseSupplyChainProvider? get _releaseSupplyChainProvider {
    final registry = _registry;
    if (registry == null ||
        !registry.isRegistered<ReleaseSupplyChainProvider>()) {
      return null;
    }
    return registry.resolve<ReleaseSupplyChainProvider>();
  }

  CicdIntegrationProvider? get _cicdIntegrationProvider {
    final registry = _registry;
    if (registry == null || !registry.isRegistered<CicdIntegrationProvider>()) {
      return null;
    }
    return registry.resolve<CicdIntegrationProvider>();
  }

  CryptographicTrustProvider? get _cryptographicTrustProvider {
    final registry = _registry;
    if (registry == null ||
        !registry.isRegistered<CryptographicTrustProvider>()) {
      return null;
    }
    return registry.resolve<CryptographicTrustProvider>();
  }

  ReleaseGovernanceProvider? get _releaseGovernanceProvider {
    final registry = _registry;
    if (registry == null ||
        !registry.isRegistered<ReleaseGovernanceProvider>()) {
      return null;
    }
    return registry.resolve<ReleaseGovernanceProvider>();
  }

  QualityGateProvider? get _qualityGateProvider {
    final registry = _registry;
    if (registry == null || !registry.isRegistered<QualityGateProvider>()) {
      return null;
    }
    return registry.resolve<QualityGateProvider>();
  }

  Future<ProjectGraph?> _resolveGraph(
    DashboardRequest request,
    List<DashboardSourceReference> refs,
    List<String> limitations,
  ) async {
    if (request.projectGraph != null) {
      final graph = request.projectGraph!;
      refs.add(_graphRef(
          request.projectId, graph, DashboardSourceResolutionMode.injected));
      return graph;
    }
    if (_graphProvider == null) return null;
    if (request.useLatest) {
      final loaded = await _graphProvider!.load();
      if (loaded != null) {
        refs.add(_graphRef(
            request.projectId, loaded, DashboardSourceResolutionMode.latest));
        return loaded;
      }
      limitations.add('Latest project graph unavailable');
      return null;
    }
    return null;
  }

  Map<String, dynamic>? _resolveGuardian(
    DashboardRequest request,
    List<DashboardSourceReference> refs,
    List<String> limitations,
  ) {
    if (request.guardianAnalysis != null &&
        request.guardianAnalysis!.isNotEmpty) {
      refs.add(
        _reference(
          id: 'guardian:injected',
          sourceType: DashboardSourceType.guardian,
          providerType: DashboardProviderType.guardian,
          artifactId: 'guardian:injected',
          projectId: request.projectId,
          createdAt: request.createdAt,
          fingerprint: 'guardian:injected',
          resolutionMode: DashboardSourceResolutionMode.injected,
        ),
      );
      return request.guardianAnalysis;
    }
    if (request.guardianResult != null) {
      final analysis = request.guardianResult!.toJson();
      refs.add(
        _reference(
          id: 'guardian:result',
          sourceType: DashboardSourceType.guardian,
          providerType: DashboardProviderType.guardian,
          artifactId: 'guardian:result',
          projectId: request.projectId,
          createdAt: request.createdAt,
          fingerprint: 'guardian:result',
          resolutionMode: DashboardSourceResolutionMode.injected,
        ),
      );
      return analysis;
    }
    if (_guardianProvider != null) {
      limitations
          .add('Guardian must be injected; provider analyze() is not used');
    }
    return null;
  }

  DashboardSourceReference _metricsRef(
    MetricsSnapshot snapshot,
    DashboardSourceResolutionMode mode,
  ) {
    return _reference(
      id: 'metrics:${snapshot.metadata.snapshotId}',
      sourceType: DashboardSourceType.metrics,
      providerType: DashboardProviderType.metrics,
      artifactId: snapshot.metadata.snapshotId,
      projectId: snapshot.metadata.projectId,
      schemaVersion: snapshot.metadata.metricsSchemaVersion,
      calculationVersion: snapshot.metadata.metricsCalculationVersion,
      canonicalizationVersion: snapshot.metadata.metricsCanonicalizationVersion,
      createdAt: snapshot.metadata.generatedAt ?? '',
      gitRef: snapshot.metadata.gitRef,
      fingerprint: snapshot.metadata.sourceGraphFingerprint,
      resolutionMode: mode,
      isPrimary: true,
    );
  }

  DashboardSourceReference _historyRef(
    HistorySnapshot snapshot,
    DashboardSourceResolutionMode mode,
  ) {
    return _reference(
      id: 'history:${snapshot.metadata.historySnapshotId}',
      sourceType: DashboardSourceType.history,
      providerType: DashboardProviderType.history,
      artifactId: snapshot.metadata.historySnapshotId,
      projectId: snapshot.metadata.projectId,
      schemaVersion: snapshot.metadata.historySchemaVersion,
      canonicalizationVersion: snapshot.metadata.historyCanonicalizationVersion,
      createdAt: snapshot.metadata.createdAt,
      branch: snapshot.metadata.branch,
      gitRef: snapshot.metadata.gitRef,
      fingerprint: snapshot.metadata.snapshotFingerprint,
      resolutionMode: mode,
    );
  }

  DashboardSourceReference _scoreRef(
    EngineeringScoreSnapshot snapshot,
    DashboardSourceResolutionMode mode,
  ) {
    return _reference(
      id: 'score:${snapshot.metadata.scoreSnapshotId}',
      sourceType: DashboardSourceType.score,
      providerType: DashboardProviderType.score,
      artifactId: snapshot.metadata.scoreSnapshotId,
      projectId: snapshot.metadata.projectId,
      schemaVersion: snapshot.metadata.scoreSchemaVersion,
      calculationVersion: snapshot.metadata.scoreCalculationVersion,
      canonicalizationVersion: snapshot.metadata.scoreCanonicalizationVersion,
      createdAt: snapshot.metadata.createdAt,
      branch: snapshot.metadata.branch,
      gitRef: snapshot.metadata.gitRef,
      fingerprint: snapshot.metadata.scoreFingerprint,
      resolutionMode: mode,
      isPrimary: true,
    );
  }

  DashboardSourceReference _mesRef(
    MESSnapshot snapshot,
    DashboardSourceResolutionMode mode,
  ) {
    return _reference(
      id: 'mes:${snapshot.metadata.mesSnapshotId}',
      sourceType: DashboardSourceType.mes,
      providerType: DashboardProviderType.mes,
      artifactId: snapshot.metadata.mesSnapshotId,
      projectId: snapshot.metadata.projectId,
      schemaVersion: snapshot.metadata.mesSchemaVersion,
      calculationVersion: snapshot.metadata.mesCalculationVersion,
      canonicalizationVersion: snapshot.metadata.mesCanonicalizationVersion,
      createdAt: snapshot.metadata.createdAt,
      branch: snapshot.metadata.branch,
      gitRef: snapshot.metadata.gitRef,
      fingerprint: snapshot.metadata.mesFingerprint,
      resolutionMode: mode,
      isPrimary: true,
    );
  }

  DashboardSourceReference _qualityGateRef(
    QualityGateSnapshot snapshot,
    DashboardSourceResolutionMode mode,
  ) {
    return _reference(
      id: 'qualityGate:${snapshot.metadata.qualityGateSnapshotId}',
      sourceType: DashboardSourceType.qualityGate,
      providerType: DashboardProviderType.qualityGate,
      artifactId: snapshot.metadata.qualityGateSnapshotId,
      projectId: snapshot.metadata.projectId,
      schemaVersion: snapshot.metadata.schemaVersion,
      calculationVersion: snapshot.metadata.calculationVersion,
      canonicalizationVersion: snapshot.metadata.canonicalizationVersion,
      createdAt: snapshot.metadata.createdAt,
      branch: snapshot.metadata.branch,
      fingerprint: snapshot.metadata.qualityGateFingerprint,
      resolutionMode: mode,
    );
  }

  DashboardSourceReference _releaseEvidenceRef(
    ReleaseEvidenceBundle bundle,
    DashboardSourceResolutionMode mode,
  ) {
    return _reference(
      id: 'releaseEvidence:${bundle.metadata.bundleId}',
      sourceType: DashboardSourceType.releaseEvidence,
      providerType: DashboardProviderType.releaseEvidence,
      artifactId: bundle.metadata.bundleId,
      projectId: bundle.metadata.projectId,
      schemaVersion: bundle.metadata.schemaVersion,
      calculationVersion: bundle.metadata.calculationVersion,
      canonicalizationVersion: bundle.metadata.canonicalizationVersion,
      createdAt: bundle.metadata.createdAt,
      fingerprint: bundle.fingerprint,
      resolutionMode: mode,
    );
  }

  DashboardSourceReference _releaseSupplyChainRef(
    ReleaseSupplyChainSnapshot snapshot,
    DashboardSourceResolutionMode mode,
  ) {
    return _reference(
      id: 'releaseSupplyChain:${snapshot.metadata.supplyChainSnapshotId}',
      sourceType: DashboardSourceType.releaseSupplyChain,
      providerType: DashboardProviderType.releaseSupplyChain,
      artifactId: snapshot.metadata.supplyChainSnapshotId,
      projectId: snapshot.metadata.projectId,
      schemaVersion: snapshot.metadata.schemaVersion,
      canonicalizationVersion: snapshot.metadata.canonicalizationVersion,
      createdAt: snapshot.metadata.createdAt,
      fingerprint: snapshot.fingerprint,
      resolutionMode: mode,
    );
  }

  DashboardSourceReference _cicdIntegrationRef(
    CicdIntegrationSnapshot snapshot,
    DashboardSourceResolutionMode mode,
  ) {
    return _reference(
      id: 'cicdIntegration:${snapshot.metadata.cicdIntegrationSnapshotId}',
      sourceType: DashboardSourceType.cicdIntegration,
      providerType: DashboardProviderType.cicdIntegration,
      artifactId: snapshot.metadata.cicdIntegrationSnapshotId,
      projectId: snapshot.metadata.projectId,
      schemaVersion: snapshot.metadata.schemaVersion,
      canonicalizationVersion: snapshot.metadata.canonicalizationVersion,
      createdAt: snapshot.metadata.createdAt,
      fingerprint: snapshot.fingerprint,
      resolutionMode: mode,
    );
  }

  DashboardSourceReference _cryptographicTrustRef(
    CryptographicTrustSnapshot snapshot,
    DashboardSourceResolutionMode mode,
  ) {
    return _reference(
      id: 'cryptographicTrust:${snapshot.metadata.cryptographicTrustSnapshotId}',
      sourceType: DashboardSourceType.cryptographicTrust,
      providerType: DashboardProviderType.cryptographicTrust,
      artifactId: snapshot.metadata.cryptographicTrustSnapshotId,
      projectId: snapshot.metadata.projectId,
      schemaVersion: snapshot.metadata.schemaVersion,
      canonicalizationVersion: snapshot.metadata.canonicalizationVersion,
      createdAt: snapshot.metadata.createdAt,
      fingerprint: snapshot.fingerprint,
      resolutionMode: mode,
    );
  }

  DashboardSourceReference _releaseGovernanceRef(
    ReleaseDecisionSnapshot snapshot,
    DashboardSourceResolutionMode mode,
  ) {
    return _reference(
      id: 'releaseGovernance:${snapshot.metadata.snapshotId}',
      sourceType: DashboardSourceType.releaseGovernance,
      providerType: DashboardProviderType.releaseGovernance,
      artifactId: snapshot.metadata.snapshotId,
      projectId: snapshot.metadata.projectId,
      schemaVersion: snapshot.metadata.schemaVersion,
      calculationVersion: snapshot.metadata.calculationVersion,
      canonicalizationVersion: snapshot.metadata.canonicalizationVersion,
      createdAt: snapshot.metadata.createdAt,
      branch: snapshot.metadata.branch,
      fingerprint: snapshot.fingerprint,
      resolutionMode: mode,
    );
  }

  DashboardSourceReference _graphRef(
    String projectId,
    ProjectGraph graph,
    DashboardSourceResolutionMode mode,
  ) {
    return _reference(
      id: 'graph:${graph.metadata.source}',
      sourceType: DashboardSourceType.graph,
      providerType: DashboardProviderType.graph,
      artifactId: graph.metadata.source,
      projectId: projectId,
      schemaVersion: graph.metadata.graphSchemaVersion,
      createdAt: graph.metadata.generatedAt ?? '',
      fingerprint: '${graph.metadata.nodeCount}:${graph.metadata.edgeCount}',
      resolutionMode: mode,
    );
  }

  DashboardSourceReference _unavailableRef({
    required String referenceId,
    required DashboardSourceType sourceType,
    required DashboardProviderType providerType,
    required String artifactId,
    required String projectId,
  }) {
    return DashboardSourceReference(
      referenceId: referenceId,
      sourceType: sourceType,
      providerType: providerType,
      artifactId: artifactId,
      projectId: projectId,
      createdAt: '',
      fingerprint: '',
      availability: DashboardAvailability.unavailable,
      compatibility: DashboardCompatibility.unknown,
      resolutionMode: DashboardSourceResolutionMode.byId,
      limitations: const ['source unavailable'],
    );
  }

  DashboardSourceReference _reference({
    required String id,
    required DashboardSourceType sourceType,
    required DashboardProviderType providerType,
    required String artifactId,
    required String projectId,
    int? schemaVersion,
    int? calculationVersion,
    int? canonicalizationVersion,
    required String createdAt,
    String? branch,
    String? gitRef,
    required String fingerprint,
    required DashboardSourceResolutionMode resolutionMode,
    bool isPrimary = false,
  }) {
    return DashboardSourceReference(
      referenceId: id,
      sourceType: sourceType,
      providerType: providerType,
      artifactId: artifactId,
      projectId: projectId,
      schemaVersion: schemaVersion,
      calculationVersion: calculationVersion,
      canonicalizationVersion: canonicalizationVersion,
      createdAt: createdAt,
      branch: branch,
      gitRef: gitRef,
      fingerprint: fingerprint,
      availability: DashboardAvailability.available,
      compatibility: DashboardCompatibility.compatible,
      resolutionMode: resolutionMode,
      isPrimary: isPrimary,
    );
  }
}
