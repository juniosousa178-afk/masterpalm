import 'package:masterpalm_platform/masterpalm_platform.dart';

import 'guardian_config.dart';
import 'guardian_engine.dart';
import 'providers/guardian_engine_provider.dart';

/// Composition root for Guardian via Platform Core.
class GuardianPlatformBootstrap {
  const GuardianPlatformBootstrap._();

  static GuardianSession create({
    required String repoRoot,
    PlatformCore? platform,
    ProviderRegistry? registry,
    GuardianConfig? config,
    AstProvider? astProvider,
    bool registerDefaultAst = true,
  }) {
    final resolvedRegistry = registry ?? ProviderRegistry();
    final platformConfig = PlatformConfig.forRepo(repoRoot);
    final resolvedConfig =
        config ?? GuardianConfig.load(repoRoot, paths: platformConfig.paths);

    if (astProvider != null && !resolvedRegistry.isRegistered<AstProvider>()) {
      resolvedRegistry.registerInstance<AstProvider>(astProvider);
    }

    if (!resolvedRegistry.isRegistered<AstProvider>()) {
      if (!registerDefaultAst) {
        throw ProviderException(
          'AstProvider is not registered',
          providerType: 'AstProvider',
        );
      }
    }

    final core = platform ??
        PlatformBootstrap.forRepo(
          repoRoot,
          config: platformConfig,
          registry: resolvedRegistry,
        );

    final ast = resolvedRegistry.resolve<AstProvider>();

    final engine = GuardianEngine.compose(
      repoRoot: repoRoot,
      platform: core,
      config: resolvedConfig,
      ast: ast,
    );

    final provider = GuardianEngineProvider(engine: engine);

    if (!resolvedRegistry.isRegistered<GuardianProvider>()) {
      resolvedRegistry.registerInstance<GuardianProvider>(provider);
    }

    return GuardianSession(
      platform: core,
      config: resolvedConfig,
      engine: engine,
      provider: provider,
    );
  }
}

/// Instance-scoped Guardian runtime bound to Platform Core.
class GuardianSession {
  GuardianSession({
    required this.platform,
    required this.config,
    required this.engine,
    required this.provider,
  });

  final PlatformCore platform;
  final GuardianConfig config;
  final GuardianEngine engine;
  final GuardianProvider provider;

  GuardianEngineProvider get engineProvider =>
      provider as GuardianEngineProvider;
}
