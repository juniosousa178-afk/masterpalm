import '../core/provider_registry.dart';
import '../interfaces/dashboard_provider.dart';
import '../interfaces/history_provider.dart';
import '../interfaces/mes_provider.dart';
import '../interfaces/metrics_provider.dart';
import '../interfaces/observability_provider.dart';
import '../interfaces/quality_gate_provider.dart';
import '../interfaces/release_governance_provider.dart';
import '../interfaces/release_evidence_provider.dart';
import '../interfaces/release_supply_chain_provider.dart';
import '../interfaces/cicd_integration_provider.dart';
import '../interfaces/cryptographic_trust_provider.dart';
import '../interfaces/persistent_artifact_provider.dart';
import '../interfaces/report_provider.dart';
import '../interfaces/score_provider.dart';
import '../models/observability/telemetry_enums.dart';
import '../providers/platform_observability_provider.dart';
import 'clocks/platform_clock.dart';
import 'clocks/system_platform_clock.dart';
import 'instrumentation/observable_dashboard_provider.dart';
import 'instrumentation/observable_history_provider.dart';
import 'instrumentation/observable_mes_provider.dart';
import 'instrumentation/observable_metrics_provider.dart';
import 'instrumentation/observable_quality_gate_provider.dart';
import 'instrumentation/observable_release_governance_provider.dart';
import 'instrumentation/observable_release_evidence_provider.dart';
import 'instrumentation/observable_release_supply_chain_provider.dart';
import 'instrumentation/observable_cicd_integration_provider.dart';
import 'instrumentation/observable_cryptographic_trust_provider.dart';
import 'instrumentation/observable_persistent_artifact_provider.dart';
import 'instrumentation/observable_report_provider.dart';
import 'instrumentation/observable_score_provider.dart';
import 'instrumentation/telemetry_instrumentation.dart';
import 'observability_collector.dart';
import 'observability_engine.dart';
import 'sinks/in_memory_telemetry_event_sink.dart';
import 'sinks/no_op_telemetry_event_sink.dart';
import 'stores/in_memory_observability_store.dart';
import 'telemetry_event_sink.dart';
import 'telemetry_registry.dart';
import 'telemetry_timer.dart';

/// Composition root for Observability integration.
class TelemetryPlatformBootstrap {
  const TelemetryPlatformBootstrap._();

  static void register({
    required ProviderRegistry registry,
    ObservabilityMode mode = ObservabilityMode.full,
    PlatformClock? clock,
    ObservabilityProvider? observabilityProvider,
    InMemoryObservabilityStore? store,
    TelemetryRegistry? telemetryRegistry,
    TelemetryEventSink? eventSink,
  }) {
    if (registry.isRegistered<ObservabilityProvider>()) return;

    final resolvedClock = clock ?? SystemPlatformClock();
    final reg = telemetryRegistry ?? TelemetryRegistry();
    if (!reg.isFrozen) {
      TelemetryRegistry.registerFoundation(reg);
      reg.freeze();
    }

    final sink = eventSink ??
        (mode == ObservabilityMode.disabled
            ? const NoOpTelemetryEventSink()
            : InMemoryTelemetryEventSink());
    final collector = ObservabilityCollector(
      sink: sink,
    );
    final engine = ObservabilityEngine(collector: collector);
    final resolvedStore = store ?? InMemoryObservabilityStore();

    final provider = observabilityProvider ??
        PlatformObservabilityProvider(
          engine: engine,
          collector: collector,
          store: resolvedStore,
          mode: mode,
        );
    registry.registerInstance<ObservabilityProvider>(provider);

    if (mode == ObservabilityMode.disabled) return;

    final instrumentation = TelemetryInstrumentation(
      collector: collector,
      clock: resolvedClock,
      timerFactory: const DefaultTelemetryTimerFactory(),
    );

    registry.registerInstance<TelemetryInstrumentation>(instrumentation);

    _wrapIfRegistered<MetricsProvider>(
      registry,
      (delegate) => ObservableMetricsProvider(
        delegate: delegate,
        instrumentation: instrumentation,
      ),
    );
    _wrapIfRegistered<HistoryProvider>(
      registry,
      (delegate) => ObservableHistoryProvider(
        delegate: delegate,
        instrumentation: instrumentation,
      ),
    );
    _wrapIfRegistered<ScoreProvider>(
      registry,
      (delegate) => ObservableScoreProvider(
        delegate: delegate,
        instrumentation: instrumentation,
      ),
    );
    _wrapIfRegistered<MESProvider>(
      registry,
      (delegate) => ObservableMESProvider(
        delegate: delegate,
        instrumentation: instrumentation,
      ),
    );
    _wrapIfRegistered<DashboardProvider>(
      registry,
      (delegate) => ObservableDashboardProvider(
        delegate: delegate,
        instrumentation: instrumentation,
      ),
    );
    _wrapIfRegistered<ReportProvider>(
      registry,
      (delegate) => ObservableReportProvider(
        delegate: delegate,
        instrumentation: instrumentation,
      ),
    );
    _wrapIfRegistered<QualityGateProvider>(
      registry,
      (delegate) => ObservableQualityGateProvider(
        delegate: delegate,
        instrumentation: instrumentation,
      ),
    );
    _wrapIfRegistered<ReleaseGovernanceProvider>(
      registry,
      (delegate) => ObservableReleaseGovernanceProvider(
        delegate: delegate,
        instrumentation: instrumentation,
      ),
    );
    _wrapIfRegistered<ReleaseEvidenceProvider>(
      registry,
      (delegate) => ObservableReleaseEvidenceProvider(
        delegate: delegate,
        instrumentation: instrumentation,
      ),
    );
    _wrapIfRegistered<ReleaseSupplyChainProvider>(
      registry,
      (delegate) => ObservableReleaseSupplyChainProvider(
        delegate: delegate,
        instrumentation: instrumentation,
      ),
    );
    _wrapIfRegistered<CicdIntegrationProvider>(
      registry,
      (delegate) => ObservableCicdIntegrationProvider(
        delegate: delegate,
        instrumentation: instrumentation,
      ),
    );
    _wrapIfRegistered<CryptographicTrustProvider>(
      registry,
      (delegate) => ObservableCryptographicTrustProvider(
        delegate: delegate,
        instrumentation: instrumentation,
      ),
    );
    _wrapIfRegistered<PersistentArtifactProvider>(
      registry,
      (delegate) => ObservablePersistentArtifactProvider(
        delegate: delegate,
        instrumentation: instrumentation,
      ),
    );
  }

  /// Wraps providers registered after [register], e.g. Quality Gate.
  static void wrapLateProviders({required ProviderRegistry registry}) {
    if (!registry.isRegistered<TelemetryInstrumentation>()) return;
    final instrumentation = registry.resolve<TelemetryInstrumentation>();
    _wrapIfRegistered<QualityGateProvider>(
      registry,
      (delegate) => ObservableQualityGateProvider(
        delegate: delegate,
        instrumentation: instrumentation,
      ),
    );
    _wrapIfRegistered<ReleaseGovernanceProvider>(
      registry,
      (delegate) => ObservableReleaseGovernanceProvider(
        delegate: delegate,
        instrumentation: instrumentation,
      ),
    );
    _wrapIfRegistered<ReleaseEvidenceProvider>(
      registry,
      (delegate) => ObservableReleaseEvidenceProvider(
        delegate: delegate,
        instrumentation: instrumentation,
      ),
    );
    _wrapIfRegistered<ReleaseSupplyChainProvider>(
      registry,
      (delegate) => ObservableReleaseSupplyChainProvider(
        delegate: delegate,
        instrumentation: instrumentation,
      ),
    );
    _wrapIfRegistered<CicdIntegrationProvider>(
      registry,
      (delegate) => ObservableCicdIntegrationProvider(
        delegate: delegate,
        instrumentation: instrumentation,
      ),
    );
    _wrapIfRegistered<CryptographicTrustProvider>(
      registry,
      (delegate) => ObservableCryptographicTrustProvider(
        delegate: delegate,
        instrumentation: instrumentation,
      ),
    );
    _wrapIfRegistered<PersistentArtifactProvider>(
      registry,
      (delegate) => ObservablePersistentArtifactProvider(
        delegate: delegate,
        instrumentation: instrumentation,
      ),
    );
  }

  static void _wrapIfRegistered<T extends Object>(
    ProviderRegistry registry,
    T Function(T delegate) wrap,
  ) {
    if (!registry.isRegistered<T>()) return;
    final delegate = registry.resolve<T>();
    if (delegate.runtimeType.toString().startsWith('Observable')) return;
    registry.registerInstance<T>(wrap(delegate));
  }
}
