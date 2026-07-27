import 'dart:io';

import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;

import 'guardian_package_exceptions.dart';

/// Resolved package context for a Dart package root.
///
/// Uses the target package's own [PackageConfig], never a caller's config.
class GuardianPackageContext {
  GuardianPackageContext({
    required this.packageRoot,
    required this.packageName,
    required this.packageConfig,
    required this.packageConfigPath,
    required this.pubspecPath,
  });

  final String packageRoot;
  final String packageName;
  final PackageConfig packageConfig;
  final String packageConfigPath;
  final String pubspecPath;

  /// Test-only constructor with an in-memory [PackageConfig].
  factory GuardianPackageContext.forTest({
    required String packageRoot,
    required String packageName,
    required PackageConfig packageConfig,
    String packageConfigPath = '.dart_tool/package_config.json',
    String pubspecPath = 'pubspec.yaml',
  }) {
    return GuardianPackageContext(
      packageRoot: p.normalize(p.absolute(packageRoot)),
      packageName: packageName,
      packageConfig: packageConfig,
      packageConfigPath: packageConfigPath,
      pubspecPath: pubspecPath,
    );
  }

  static const packageConfigRelativePath = '.dart_tool/package_config.json';

  /// Loads [GuardianPackageContext] from [packageRoot].
  ///
  /// Throws [GuardianPackageConfigMissingException] when config is absent.
  static Future<GuardianPackageContext> load(String packageRoot) async {
    final normalizedRoot = p.normalize(p.absolute(packageRoot));
    final pubspecPath = p.join(normalizedRoot, 'pubspec.yaml');
    if (!File(pubspecPath).existsSync()) {
      throw GuardianPackageException(
        'pubspec.yaml not found',
        packageRoot: normalizedRoot,
        path: pubspecPath,
      );
    }

    final configPath = p.join(normalizedRoot, packageConfigRelativePath);
    if (!File(configPath).existsSync()) {
      throw GuardianPackageConfigMissingException(
        packageRoot: normalizedRoot,
        expectedPath: configPath,
      );
    }

    PackageConfig packageConfig;
    try {
      packageConfig = await loadPackageConfigUri(Uri.file(configPath));
    } on FormatException catch (e) {
      throw GuardianPackageConfigInvalidException(
        packageRoot: normalizedRoot,
        configPath: configPath,
        reason: e.message,
      );
    }

    final packageName = _readPackageName(pubspecPath);
    return GuardianPackageContext(
      packageRoot: normalizedRoot,
      packageName: packageName,
      packageConfig: packageConfig,
      packageConfigPath: configPath,
      pubspecPath: pubspecPath,
    );
  }

  static String _readPackageName(String pubspecPath) {
    final content = File(pubspecPath).readAsStringSync();
    final match =
        RegExp(r'^name:\s*(\S+)', multiLine: true).firstMatch(content);
    if (match == null) {
      throw GuardianPackageException(
        'unable to read package name from pubspec',
        path: pubspecPath,
      );
    }
    return match.group(1)!;
  }
}
