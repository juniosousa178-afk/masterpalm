import '../interfaces/history_provider.dart';
import '../models/history/history_diff.dart';
import '../models/history/history_request.dart';
import '../models/history/history_snapshot.dart';
import '../history/history_canonical_serializer.dart';
import '../history/history_comparator.dart';
import '../history/history_engine.dart';
import '../history/history_exceptions.dart';
import '../history/history_query_engine.dart';
import '../history/stores/history_store.dart';

/// Platform implementation of [HistoryProvider].
class PlatformHistoryProvider implements HistoryProvider {
  PlatformHistoryProvider({
    required HistoryEngine engine,
    required HistoryStore store,
    HistoryComparator? comparator,
    HistoryQueryEngine? queryEngine,
    HistoryCanonicalSerializer? serializer,
  })  : _engine = engine,
        _store = store,
        _comparator = comparator ?? const HistoryComparator(),
        _queryEngine = queryEngine ?? const HistoryQueryEngine(),
        _serializer = serializer ?? const HistoryCanonicalSerializer();

  final HistoryEngine _engine;
  final HistoryStore _store;
  final HistoryComparator _comparator;
  final HistoryQueryEngine _queryEngine;
  final HistoryCanonicalSerializer _serializer;

  @override
  Future<HistoryResult> capture(HistoryRequest request) async {
    final result = _engine.capture(request);
    final existing =
        await _store.load(result.snapshot.metadata.historySnapshotId);
    if (existing != null) {
      final same = _serializer.canonicalizeSnapshot(existing) ==
          _serializer.canonicalizeSnapshot(result.snapshot);
      return HistoryResult(
        status: result.status,
        snapshot: existing,
        warnings: result.warnings,
        idempotent: same,
      );
    }
    await _store.save(result.snapshot);
    final saved = await _store.load(result.snapshot.metadata.historySnapshotId);
    return HistoryResult(
      status: result.status,
      snapshot: saved ?? result.snapshot,
      warnings: result.warnings,
    );
  }

  @override
  Future<void> publish(HistorySnapshot snapshot) async {
    await _store.save(snapshot);
  }

  @override
  Future<HistorySnapshot?> loadById(String snapshotId) async {
    return _store.load(snapshotId);
  }

  @override
  Future<List<HistorySnapshot>> list(HistoryQuery query) async {
    final all = await _store.listAll();
    return _queryEngine.apply(all, query);
  }

  @override
  Future<HistorySnapshot?> latest({required String projectId}) async {
    return _store.latest(projectId);
  }

  @override
  Future<HistoryDiff> compare({
    required String fromSnapshotId,
    required String toSnapshotId,
  }) async {
    final from = await _store.load(fromSnapshotId);
    final to = await _store.load(toSnapshotId);
    if (from == null) {
      throw HistoryNotFoundException(fromSnapshotId);
    }
    if (to == null) {
      throw HistoryNotFoundException(toSnapshotId);
    }
    return _comparator.compare(from, to);
  }

  @override
  Future<void> remove(String snapshotId) async {
    if (!await _store.exists(snapshotId)) {
      throw HistoryNotFoundException(snapshotId);
    }
    await _store.delete(snapshotId);
  }
}
