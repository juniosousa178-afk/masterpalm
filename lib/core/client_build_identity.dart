// Identity baked into the running bundle (dart-define overrides defaults).
// Never use remote /version.json as the sole proof of which build is loaded.

/// Release stamp — updated with each hosting deploy of this app.
const String kClientBuildId = String.fromEnvironment(
  'CATALOG_BUILD_ID',
  defaultValue: 'sale-forensic-trace-1.0.96',
);

const String kClientGitCommit = String.fromEnvironment(
  'GIT_COMMIT',
  defaultValue: '',
);

const String kClientAppVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '1.0.96+110',
);

Map<String, String> clientBuildProofMap() => {
      'CLIENT_BUILD_ID': kClientBuildId,
      'CLIENT_GIT_COMMIT': kClientGitCommit,
      'APP_VERSION': kClientAppVersion,
    };
