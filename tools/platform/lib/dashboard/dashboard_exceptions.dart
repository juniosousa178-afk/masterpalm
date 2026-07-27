/// Base exception for dashboard operations.
class DashboardException implements Exception {
  const DashboardException(this.message);

  final String message;

  @override
  String toString() => 'DashboardException: $message';
}

/// Validation failure for dashboard requests or snapshots.
class DashboardValidationException extends DashboardException {
  const DashboardValidationException(super.message);
}

/// Source resolution failure.
class DashboardSourceException extends DashboardException {
  const DashboardSourceException(super.message, {this.sourceType});

  final String? sourceType;

  @override
  String toString() =>
      'DashboardSourceException${sourceType != null ? ' ($sourceType)' : ''}: $message';
}

/// Store conflict for equivalent snapshot ID with divergent payload.
class DashboardConflictException extends DashboardException {
  const DashboardConflictException(this.snapshotId)
      : super('Dashboard snapshot conflict: $snapshotId');

  final String snapshotId;
}

/// Registry mutation after freeze.
class DashboardRegistryException extends DashboardException {
  const DashboardRegistryException(super.message);
}
