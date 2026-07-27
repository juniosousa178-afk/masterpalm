/// Base exception for observability operations.
class TelemetryException implements Exception {
  const TelemetryException(this.message);

  final String message;

  @override
  String toString() => 'TelemetryException: $message';
}

class TelemetryValidationException extends TelemetryException {
  const TelemetryValidationException(super.message);
}

class TelemetryConflictException extends TelemetryException {
  const TelemetryConflictException(this.eventOrSnapshotId)
      : super('Telemetry conflict: $eventOrSnapshotId');

  final String eventOrSnapshotId;
}

class TelemetryRegistryException extends TelemetryException {
  const TelemetryRegistryException(super.message);
}

class TelemetryDataPolicyException extends TelemetryException {
  const TelemetryDataPolicyException(super.message);
}
