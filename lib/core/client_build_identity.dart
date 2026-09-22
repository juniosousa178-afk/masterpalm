// Identity baked into the running bundle (dart-define overrides defaults).
// Never use remote /version.json as the sole proof of which build is loaded.
// Never silently report "dev" as a production CLIENT_BUILD_ID.

/// Release stamp — updated with each hosting deploy of this app.
const String kClientBuildId = String.fromEnvironment(
  'CATALOG_BUILD_ID',
  defaultValue: 'mirjoias-untracked-full-preservation-1.0.97',
);

const String kClientGitCommit = String.fromEnvironment(
  'GIT_COMMIT',
  defaultValue: 'a7ba2a3c3feae14aab9307d20454b8ce2f0fbd95',
);

const String kClientAppVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '1.0.97+111',
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
