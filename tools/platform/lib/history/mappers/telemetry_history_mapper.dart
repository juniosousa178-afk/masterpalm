import '../../models/history/history_artifact.dart';
import '../../models/observability/telemetry_snapshot.dart';
import '../../observability/telemetry_history_mapper.dart' as obs;

/// History mapper for telemetry snapshots.
class TelemetryHistoryMapper {
  const TelemetryHistoryMapper();

  HistoryArtifact fromMap(Map<String, dynamic> json) {
    return const obs.TelemetryHistoryMapper()
        .toArtifact(TelemetrySnapshot.fromJson(json));
  }
}
