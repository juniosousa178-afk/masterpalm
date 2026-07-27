enum SecureFilesystemBackendOutcome {
  succeeded,
  notFound,
  conflict,
  rejected,
  exceededLimit,
  ioError,
}

class SecureFilesystemBackendIssue {
  const SecureFilesystemBackendIssue({
    required this.code,
    required this.message,
    this.metadata = const {},
  });

  final String code;
  final String message;
  final Map<String, String> metadata;
}

typedef Issue = SecureFilesystemBackendIssue;

class SecureFilesystemWriteResult {
  const SecureFilesystemWriteResult({
    required this.outcome,
    required this.digest,
    required this.sizeBytes,
    this.locationReference,
    this.issues = const [],
    this.idempotent = false,
  });

  final SecureFilesystemBackendOutcome outcome;
  final String digest;
  final int sizeBytes;
  final String? locationReference;
  final List<SecureFilesystemBackendIssue> issues;
  final bool idempotent;
}

class SecureFilesystemReadResult {
  const SecureFilesystemReadResult({
    required this.outcome,
    this.bytes,
    this.digest,
    this.issues = const [],
  });

  final SecureFilesystemBackendOutcome outcome;
  final List<int>? bytes;
  final String? digest;
  final List<SecureFilesystemBackendIssue> issues;
}

class SecureFilesystemExistsResult {
  const SecureFilesystemExistsResult({
    required this.outcome,
    required this.exists,
    this.issues = const [],
  });

  final SecureFilesystemBackendOutcome outcome;
  final bool exists;
  final List<SecureFilesystemBackendIssue> issues;
}

class SecureFilesystemManifestSaveResult {
  const SecureFilesystemManifestSaveResult({
    required this.outcome,
    required this.manifestId,
    this.locationReference,
    this.idempotent = false,
    this.issues = const [],
  });

  final SecureFilesystemBackendOutcome outcome;
  final String manifestId;
  final String? locationReference;
  final bool idempotent;
  final List<SecureFilesystemBackendIssue> issues;
}

class SecureFilesystemManifestLoadResult<T> {
  const SecureFilesystemManifestLoadResult({
    required this.outcome,
    this.manifest,
    this.locationReference,
    this.issues = const [],
  });

  final SecureFilesystemBackendOutcome outcome;
  final T? manifest;
  final String? locationReference;
  final List<SecureFilesystemBackendIssue> issues;
}

class SecureFilesystemQuarantineResult {
  const SecureFilesystemQuarantineResult({
    required this.outcome,
    required this.quarantined,
    this.locationReference,
    this.issues = const [],
  });

  final SecureFilesystemBackendOutcome outcome;
  final bool quarantined;
  final String? locationReference;
  final List<SecureFilesystemBackendIssue> issues;
}
