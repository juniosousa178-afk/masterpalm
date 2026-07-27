import 'dart:io';

import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;

import '../support/guardian_test_paths.dart';

/// Helpers for Guardian package resolution tests (offline, no network).
class PackageResolutionTestHelpers {
  PackageResolutionTestHelpers._();

  static String _fixturesRoot() {
    return p.normalize(
      p.join(
        GuardianTestPaths.guardianPackageRoot(),
        'test',
        'fixtures',
        'package_resolution',
      ),
    );
  }

  static String fixtureRoot(String name) {
    return p.normalize(p.join(_fixturesRoot(), name));
  }

  static Future<void> ensureMinimalFixturePackageConfig(String fixtureName) async {
    final root = fixtureRoot(fixtureName);
    final configFile = File(
      p.join(root, '.dart_tool', 'package_config.json'),
    );
    if (configFile.existsSync()) {
      return;
    }

    final pubspecPath = p.join(root, 'pubspec.yaml');
    final pubspecContent = File(pubspecPath).readAsStringSync();
    final nameMatch =
        RegExp(r'^name:\s*(\S+)', multiLine: true).firstMatch(pubspecContent);
    if (nameMatch == null) {
      throw StateError('unable to read package name from $pubspecPath');
    }
    final packageName = nameMatch.group(1)!;

    configFile.parent.createSync(recursive: true);
    await configFile.writeAsString(
      '''{
  "configVersion": 2,
  "packages": [
    {
      "name": "$packageName",
      "rootUri": "../",
      "packageUri": "lib/",
      "languageVersion": "3.0"
    }
  ],
  "generated": "fixture",
  "generator": "guardian-test",
  "generatorVersion": "0.0.1"
}
''',
    );
  }

  static Future<void> ensureInvalidFixturePackageConfig() async {
    final configFile = File(
      p.join(
        fixtureRoot('invalid_package_config'),
        '.dart_tool',
        'package_config.json',
      ),
    );
    configFile.parent.createSync(recursive: true);
    await configFile.writeAsString('{ not valid json\n');
  }

  static Future<PackageConfig> loadGuardianPackageConfig() async {
    final configPath = p.join(
      GuardianTestPaths.guardianPackageRoot(),
      '.dart_tool',
      'package_config.json',
    );
    return loadPackageConfigUri(Uri.file(configPath));
  }

  /// Builds a [PackageConfig] for a synthetic fixture using real dependency roots.
  static Future<PackageConfig> buildSyntheticConfig({
    required String fixtureName,
    required List<String> dependencyPackageNames,
  }) async {
    final guardianConfig = await loadGuardianPackageConfig();
    final fixtureRootPath = fixtureRoot(fixtureName);
    final packages = <Package>[
      Package(
        'fixture_$fixtureName',
        Uri.directory('$fixtureRootPath${Platform.pathSeparator}'),
        packageUriRoot: Uri.directory(
          '$fixtureRootPath${Platform.pathSeparator}lib${Platform.pathSeparator}',
        ),
        languageVersion: LanguageVersion(3, 0),
      ),
    ];

    for (final name in dependencyPackageNames) {
      final dep = guardianConfig[name];
      if (dep == null) {
        throw StateError(
          'dependency $name not found in guardian package_config; run dart pub get',
        );
      }
      packages.add(dep);
    }

    packages.sort((a, b) => a.name.compareTo(b.name));
    return PackageConfig(packages);
  }

  static Future<void> writeSyntheticPackageConfig({
    required String fixtureName,
    required List<String> dependencyPackageNames,
  }) async {
    final config = await buildSyntheticConfig(
      fixtureName: fixtureName,
      dependencyPackageNames: dependencyPackageNames,
    );
    final configDir = Directory(
      p.join(fixtureRoot(fixtureName), '.dart_tool'),
    );
    configDir.createSync(recursive: true);
    final file = File(p.join(configDir.path, 'package_config.json'));
    final buffer = StringBuffer();
    PackageConfig.writeString(
      config,
      buffer,
      Uri.directory('${configDir.path}${Platform.pathSeparator}'),
    );
    await file.writeAsString(buffer.toString());
  }
}
