enum PersistentArtifactCloudOperationStatus {
  success,
  idempotent,
  alreadyExists,
  conflict,
  unavailable,
  unsupported,
  invalid,
  notFound,
  corrupted,
  tooLarge,
  permissionDenied,
  authenticationUnavailable,
  authenticationRejected,
  endpointUnavailable,
  regionUnavailable,
  throttled,
  timeout,
  interrupted,
  retryExhausted,
  preconditionFailed,
  versionConflict,
  multipartIncomplete,
  stagingBlocked,
  backendDisabled,
  unregistered,
  failed,
}

extension PersistentArtifactCloudOperationStatusX
    on PersistentArtifactCloudOperationStatus {
  String get wireName => name;

  static PersistentArtifactCloudOperationStatus fromWireName(String value) {
    return PersistentArtifactCloudOperationStatus.values.firstWhere(
      (it) => it.name == value,
      orElse: () => throw FormatException(
        'Unknown PersistentArtifactCloudOperationStatus: $value',
      ),
    );
  }
}
