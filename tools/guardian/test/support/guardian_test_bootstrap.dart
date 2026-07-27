import 'dart:io';

import 'package:path/path.dart' as p;

import 'guardian_test_paths.dart';

/// Ensures generated artifacts required by Guardian integration tests exist.
class GuardianTestBootstrap {
  GuardianTestBootstrap._();

  static Future<void> ensurePlatformPackageConfig() async {
    final platformRoot = GuardianTestPaths.platformPackageRoot();
    final configPath = p.join(
      platformRoot,
      '.dart_tool',
      'package_config.json',
    );
    if (File(configPath).existsSync()) {
      return;
    }
    final pubspec = File(p.join(platformRoot, 'pubspec.yaml'));
    if (!pubspec.existsSync()) {
      throw StateError('tools/platform pubspec.yaml missing at $platformRoot');
    }
    final result = await Process.run(
      'dart',
      const ['pub', 'get'],
      workingDirectory: platformRoot,
      runInShell: true,
    );
    if (result.exitCode != 0) {
      throw StateError(
        'dart pub get failed in tools/platform (${result.exitCode}): ${result.stderr}',
      );
    }
    if (!File(configPath).existsSync()) {
      throw StateError('package_config still missing after pub get: $configPath');
    }
  }
}
