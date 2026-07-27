import '../../models/observability/telemetry_event.dart';
import '../../models/observability/telemetry_request.dart';
import '../../models/observability/telemetry_snapshot.dart';
import '../telemetry_canonical_serializer.dart';
import '../telemetry_exceptions.dart';
import 'observability_store.dart';

/// In-memory implementation of [ObservabilityStore].
class InMemoryObservabilityStore implements ObservabilityStore {
  InMemoryObservabilityStore({TelemetryCanonicalSerializer? serializer})
      : _serializer = serializer ?? const TelemetryCanonicalSerializer();

  final TelemetryCanonicalSerializer _serializer;
  final Map<String, TelemetrySnapshot> _snapshots = {};
  final Map<String, TelemetryEvent> _events = {};

  @override
  Future<void> saveSnapshot(TelemetrySnapshot snapshot) async {
    final id = snapshot.metadata.telemetrySnapshotId;
    final existing = _snapshots[id];
    if (existing != null &&
        _serializer.canonicalizeSnapshot(existing) !=
            _serializer.canonicalizeSnapshot(snapshot)) {
      throw TelemetryConflictException(id);
    }
    _snapshots[id] = snapshot;
  }

  @override
  Future<TelemetrySnapshot?> loadSnapshot(String snapshotId) async {
    return _snapshots[snapshotId];
  }

  @override
  Future<bool> snapshotExists(String snapshotId) async {
    return _snapshots.containsKey(snapshotId);
  }

  @override
  Future<TelemetrySnapshot?> latestSnapshot({
    String? projectId,
    String? correlationId,
  }) async {
    final matches = _snapshots.values.where((s) {
      if (projectId != null && s.metadata.projectId != projectId) return false;
      if (correlationId != null && s.metadata.correlationId != correlationId) {
        return false;
      }
      return true;
    }).toList()
      ..sort(
        (a, b) => a.metadata.createdAt.compareTo(b.metadata.createdAt),
      );
    return matches.isEmpty ? null : matches.last;
  }

  @override
  Future<List<TelemetrySnapshot>> querySnapshots(TelemetryQuery query) async {
    var results = _snapshots.values.where((s) {
      if (query.projectId != null && s.metadata.projectId != query.projectId) {
        return false;
      }
      if (query.correlationId != null &&
          s.metadata.correlationId != query.correlationId) {
        return false;
      }
      if (query.from != null &&
          s.metadata.createdAt.compareTo(query.from!) < 0) {
        return false;
      }
      if (query.to != null && s.metadata.createdAt.compareTo(query.to!) > 0) {
        return false;
      }
      return true;
    }).toList()
      ..sort(
        (a, b) => a.metadata.createdAt.compareTo(b.metadata.createdAt),
      );
    if (query.limit != null && results.length > query.limit!) {
      results = results.sublist(0, query.limit!);
    }
    return results;
  }

  @override
  Future<void> deleteSnapshot(String snapshotId) async {
    _snapshots.remove(snapshotId);
  }

  @override
  Future<void> saveEvent(TelemetryEvent event) async {
    final existing = _events[event.eventId];
    if (existing != null &&
        _serializer.canonicalizeEvent(existing) !=
            _serializer.canonicalizeEvent(event)) {
      throw TelemetryConflictException(event.eventId);
    }
    _events[event.eventId] = event;
  }

  @override
  Future<TelemetryEvent?> loadEvent(String eventId) async {
    return _events[eventId];
  }

  @override
  Future<bool> eventExists(String eventId) async {
    return _events.containsKey(eventId);
  }

  @override
  Future<List<TelemetryEvent>> queryEvents(TelemetryEventQuery query) async {
    var results = _events.values.where((event) {
      if (query.correlationId != null &&
          event.correlation.correlationId != query.correlationId) {
        return false;
      }
      if (query.operationId != null &&
          event.correlation.operationId != query.operationId) {
        return false;
      }
      if (query.component != null && event.component != query.component) {
        return false;
      }
      if (query.projectId != null &&
          event.correlation.projectId != query.projectId) {
        return false;
      }
      if (query.from != null && event.startedAt.compareTo(query.from!) < 0) {
        return false;
      }
      if (query.to != null && event.startedAt.compareTo(query.to!) > 0) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) {
        final cmp = a.startedAt.compareTo(b.startedAt);
        if (cmp != 0) return cmp;
        return a.eventId.compareTo(b.eventId);
      });
    if (query.limit != null && results.length > query.limit!) {
      results = results.sublist(0, query.limit!);
    }
    return results;
  }
}
