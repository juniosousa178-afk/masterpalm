import 'package:path/path.dart' as p;

class SecureFilesystemBackendConfig {
  const SecureFilesystemBackendConfig({
    required this.backendId,
    required this.rootDirectory,
    this.namespacePrefix,
    required this.maximumContentSizeBytes,
    this.allowOverwrite = false,
    this.verifyDigestAfterWrite = true,
    this.useAtomicWrites = true,
    this.quarantineEnabled = true,
    this.enableRecoveryInspector = false,
    this.allowUserHomeRoot = false,
    this.contentDirectoryName = 'content',
    this.manifestDirectoryName = 'manifests',
    this.tempDirectoryName = 'temp',
    this.quarantineDirectoryName = 'quarantine',
    this.metadata = const {},
  });

  final String backendId;
  final String rootDirectory;
  final String? namespacePrefix;
  final int maximumContentSizeBytes;
  final bool allowOverwrite;
  final bool verifyDigestAfterWrite;
  final bool useAtomicWrites;
  final bool quarantineEnabled;
  final bool enableRecoveryInspector;
  final bool allowUserHomeRoot;
  final String contentDirectoryName;
  final String manifestDirectoryName;
  final String tempDirectoryName;
  final String quarantineDirectoryName;
  final Map<String, String> metadata;
}

class SecureFilesystemBackendConfigValidator {
  const SecureFilesystemBackendConfigValidator._();

  static List<String> validate(SecureFilesystemBackendConfig config) {
    final errors = <String>[];
    if (config.backendId.trim().isEmpty) {
      errors.add('backendId is required');
    }
    if (!p.isAbsolute(config.rootDirectory)) {
      errors.add('rootDirectory must be absolute');
    }
    if (config.maximumContentSizeBytes <= 0) {
      errors.add('maximumContentSizeBytes must be > 0');
    }
    for (final name in <String>[
      config.contentDirectoryName,
      config.manifestDirectoryName,
      config.tempDirectoryName,
      config.quarantineDirectoryName,
    ]) {
      if (name.trim().isEmpty) {
        errors.add('directory names must be non-empty');
      }
      if (name.contains('/') || name.contains('\\') || name.contains('..')) {
        errors.add('directory names must be simple segments');
      }
    }
    final normalized = p.normalize(config.rootDirectory).trim();
    final rootOnly = p.rootPrefix(normalized);
    if (normalized == rootOnly) {
      errors.add('rootDirectory cannot be filesystem root');
    }
    final homeLikePattern = RegExp(
      r'(^[A-Za-z]:[\\/](Users|home)[\\/][^\\/]+$)|(^[\\/](Users|home)[\\/][^\\/]+$)',
      caseSensitive: false,
    );
    if (!config.allowUserHomeRoot && homeLikePattern.hasMatch(normalized)) {
      errors.add('user home root requires explicit opt-in');
    }
    return errors;
  }

  static void validateOrThrow(SecureFilesystemBackendConfig config) {
    final errors = validate(config);
    if (errors.isNotEmpty) {
      throw ArgumentError(
          'SecureFilesystemBackendConfig invalid: ${errors.join('; ')}');
    }
  }
}
