// Identity baked into the running bundle (dart-define overrides defaults).
// Never use remote /version.json as the sole proof of which build is loaded.
// Never silently report "dev" as a production CLIENT_BUILD_ID.

/// Release stamp — updated with each hosting deploy of this app.
const String kClientBuildId = String.fromEnvironment(
  'CATALOG_BUILD_ID',
  defaultValue: 'nathy-sale-restore-source-operation-fix-1.0.99',
);

const String kClientGitCommit = String.fromEnvironment(
  'GIT_COMMIT',
  defaultValue: '46422a3a230e99103994d5f1680398c22f4731b7',
);

const String kClientAppVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '1.0.99+113',
);

/// True when compile-time identity looks like an unstamped/dev placeholder.
bool get kClientBuildMetadataMissing {
  final id = kClientBuildId.trim().toLowerCase();
  final commit = kClientGitCommit.trim();
  if (id.isEmpty || id == 'dev' || id == 'test-build') return true;
  if (commit.isEmpty ||
      commit == 'PENDING_STAMP' ||
      commit.toLowerCase() == 'dev') {
    return true;
  }
  return false;
}

Map<String, dynamic> clientBuildProofMap() => {
      'CLIENT_BUILD_ID': kClientBuildId,
      'CLIENT_GIT_COMMIT': kClientGitCommit,
      'APP_VERSION': kClientAppVersion,
      'BUILD_METADATA_MISSING': kClientBuildMetadataMissing,
    };
