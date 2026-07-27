import '../config/platform_config.dart';
import '../graph/graph_platform_bootstrap.dart';
import '../history/history_platform_bootstrap.dart';
import '../metrics/metrics_platform_bootstrap.dart';
import '../dashboard/dashboard_platform_bootstrap.dart';
import '../observability/telemetry_platform_bootstrap.dart';
import '../quality_gate/quality_gate_platform_bootstrap.dart';
import '../release_governance/release_governance_platform_bootstrap.dart';
import '../release_evidence/release_evidence_platform_bootstrap.dart';
import '../release_supply_chain/release_supply_chain_platform_bootstrap.dart';
import '../cicd_integration/cicd_integration_platform_bootstrap.dart';
import '../cryptographic_trust/cryptographic_trust_platform_bootstrap.dart';
import '../persistent_artifacts/persistent_artifact_platform_bootstrap.dart';
import '../mes/mes_platform_bootstrap.dart';
import '../score/score_platform_bootstrap.dart';
import '../report/report_platform_bootstrap.dart';
import '../models/observability/telemetry_enums.dart';
import '../interfaces/ast_provider.dart';
import '../models/platform_project.dart';
import '../providers/file_system_ast_provider.dart';
import 'platform_core.dart';
import 'provider_registry.dart';

/// Factory for constructing a configured [PlatformCore] instance.
class PlatformBootstrap {
  const PlatformBootstrap._();

  static PlatformCore forRepo(
    String repoRoot, {
    PlatformConfig? config,
    ProviderRegistry? registry,
    void Function(ProviderRegistry registry, PlatformConfig config)? configure,
  }) {
    final resolvedConfig = config ?? PlatformConfig.forRepo(repoRoot);
    final resolvedRegistry = registry ?? ProviderRegistry();

    if (!resolvedRegistry.isRegistered<AstProvider>()) {
      resolvedRegistry.registerInstance<AstProvider>(
        FileSystemAstProvider(config: resolvedConfig),
      );
    }

    configure?.call(resolvedRegistry, resolvedConfig);

    GraphPlatformBootstrap.register(registry: resolvedRegistry);

    ReportPlatformBootstrap.register(registry: resolvedRegistry);

    MetricsPlatformBootstrap.register(registry: resolvedRegistry);

    HistoryPlatformBootstrap.register(registry: resolvedRegistry);

    ScorePlatformBootstrap.register(
      registry: resolvedRegistry,
      extraPolicies: MESPlatformBootstrap.scorePoliciesForBootstrap(),
    );

    MESPlatformBootstrap.register(registry: resolvedRegistry);

    DashboardPlatformBootstrap.register(registry: resolvedRegistry);

    TelemetryPlatformBootstrap.register(
      registry: resolvedRegistry,
      mode: ObservabilityMode.disabled,
    );

    QualityGatePlatformBootstrap.register(registry: resolvedRegistry);

    ReleaseGovernancePlatformBootstrap.register(registry: resolvedRegistry);

    ReleaseEvidencePlatformBootstrap.register(registry: resolvedRegistry);

    ReleaseSupplyChainPlatformBootstrap.register(registry: resolvedRegistry);

    CicdIntegrationPlatformBootstrap.register(registry: resolvedRegistry);

    CryptographicTrustPlatformBootstrap.register(registry: resolvedRegistry);
    PersistentArtifactPlatformBootstrap.register(registry: resolvedRegistry);

    TelemetryPlatformBootstrap.wrapLateProviders(registry: resolvedRegistry);

    return PlatformCore(
      config: resolvedConfig,
      registry: resolvedRegistry,
    );
  }

  static PlatformProject projectFromRepo(String repoRoot, {String? name}) {
    return PlatformProject(
      rootPath: repoRoot,
      name: name ?? 'masterpalm',
    );
  }
}
