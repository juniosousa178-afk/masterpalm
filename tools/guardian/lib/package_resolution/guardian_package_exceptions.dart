/// Structured errors for Guardian package resolution.
class GuardianPackageException implements Exception {
  GuardianPackageException(this.message, {this.packageRoot, this.path});

  final String message;
  final String? packageRoot;
  final String? path;

  @override
  String toString() => 'GuardianPackageException: $message'
      '${packageRoot == null ? '' : ' (root: $packageRoot)'}'
      '${path == null ? '' : ' (path: $path)'}';
}

class GuardianPackageConfigMissingException extends GuardianPackageException {
  GuardianPackageConfigMissingException({
    required String packageRoot,
    required String expectedPath,
  }) : super(
          'package_config.json not found at $expectedPath',
          packageRoot: packageRoot,
          path: expectedPath,
        );
}

class GuardianPackageConfigInvalidException extends GuardianPackageException {
  GuardianPackageConfigInvalidException({
    required String packageRoot,
    required String configPath,
    required String reason,
  }) : super(
          'invalid package_config at $configPath: $reason',
          packageRoot: packageRoot,
          path: configPath,
        );
}

class GuardianPackageResolutionException extends GuardianPackageException {
  GuardianPackageResolutionException({
    required String uri,
    required String packageRoot,
    required String filePath,
  }) : super(
          'unresolved import $uri in $filePath',
          packageRoot: packageRoot,
          path: filePath,
        );
}
