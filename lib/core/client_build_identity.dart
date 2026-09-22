// Identity baked into the running bundle (dart-define overrides defaults).
// Never use remote /version.json as the sole proof of which build is loaded.
// Never silently report "dev" as a production CLIENT_BUILD_ID.

/// Release stamp — must be overridden via --dart-define in production builds.
const String kClientBuildId = String.fromEnvironment(
  'CATALOG_BUILD_ID',
  defaultValue: 'PENDING_STAMP',
);

const String kClientGitCommit = String.fromEnvironment(
  'GIT_COMMIT',
  defaultValue: 'PENDING_STAMP',
);

const String kClientAppVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '0.0.0+0',
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
  if (id == 'pending_stamp' || id == 'PENDING_STAMP'.toLowerCase()) {
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
