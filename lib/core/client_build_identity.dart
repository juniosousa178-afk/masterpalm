// Identity baked into the running bundle (dart-define overrides defaults).
// Never use remote /version.json as the sole proof of which build is loaded.
// Never silently report "dev" as a production CLIENT_BUILD_ID.

/// Release stamp — updated with each hosting deploy of this app.
const String kClientBuildId = String.fromEnvironment(
  'CATALOG_BUILD_ID',
  defaultValue: 'stock-tombstone-restore-hotfix-1.0.100',
);

const String kClientGitCommit = String.fromEnvironment(
  'GIT_COMMIT',
  defaultValue: '5cc37ee557573c0e42a8aebc30691ebe9549cd89',
);

const String kClientAppVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '1.0.100+114',
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
