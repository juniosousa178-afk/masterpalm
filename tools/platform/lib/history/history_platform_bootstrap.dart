import '../core/provider_registry.dart';
import '../history/history_comparator.dart';
import '../history/history_compatibility_checker.dart';
import '../history/history_engine.dart';
import '../history/history_query_engine.dart';
import '../history/history_validator.dart';
import '../history/history_artifact_factory.dart';
import '../history/history_canonical_serializer.dart';
import '../history/history_snapshot_id_factory.dart';
import '../history/stores/in_memory_history_store.dart';
import '../interfaces/history_provider.dart';
import '../providers/platform_history_provider.dart';

/// Composition root for History Engine integration.
class HistoryPlatformBootstrap {
  const HistoryPlatformBootstrap._();

  static void register({
    required ProviderRegistry registry,
    HistoryProvider? historyProvider,
    InMemoryHistoryStore? store,
  }) {
    if (registry.isRegistered<HistoryProvider>()) return;

    final resolvedStore = store ?? InMemoryHistoryStore();
    final serializer = const HistoryCanonicalSerializer();
    final engine = HistoryEngine(
      artifactFactory: HistoryArtifactFactory(),
      serializer: serializer,
      idFactory: HistorySnapshotIdFactory(serializer: serializer),
      validator: HistoryValidator(
        serializer: serializer,
        idFactory: HistorySnapshotIdFactory(serializer: serializer),
      ),
      compatibilityChecker: const HistoryCompatibilityChecker(),
    );

    registry.registerInstance<HistoryProvider>(
      historyProvider ??
          PlatformHistoryProvider(
            engine: engine,
            store: resolvedStore,
            comparator: const HistoryComparator(),
            queryEngine: const HistoryQueryEngine(),
            serializer: serializer,
          ),
    );
  }
}
