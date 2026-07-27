import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../lib/package_resolution/guardian_cloud_framework_paths.dart';
import '../lib/package_resolution/guardian_cryptographic_adapter_paths.dart';
import '../lib/package_resolution/guardian_package_analyzer.dart';
import '../lib/package_resolution/guardian_package_context.dart';
import 'support/guardian_test_bootstrap.dart';
import 'support/guardian_test_paths.dart';

void main() {
  final platformRoot = GuardianTestPaths.platformPackageRoot();

  const analyzer = GuardianPackageAnalyzer();

  group('Guardian Cloud Framework Coverage — tools/platform', () {
    setUpAll(() async {
      await GuardianTestBootstrap.ensurePlatformPackageConfig();
    });

    test('loads platform package context from target package_config', () async {
      final context = await GuardianPackageContext.load(platformRoot);
      expect(context.packageName, 'masterpalm_platform');
      expect(
        File(context.packageConfigPath).existsSync(),
        isTrue,
        reason: 'must use tools/platform/.dart_tool/package_config.json',
      );
      expect(
        context.packageConfigPath.replaceAll('\\', '/'),
        contains('.dart_tool/package_config.json'),
      );
      expect(context.packageConfig['crypto'], isNotNull);
      expect(context.packageConfig['cryptography'], isNotNull);
    });

    test('cloud framework analysis is complete with zero unresolved', () async {
      final result = await analyzer.analyzeCloudFrameworkPackage(platformRoot);
      expect(result.isComplete, isTrue,
          reason: result.unresolvedImports.toString());
      expect(result.unresolvedImports, isEmpty);
      expect(result.missingAdapterPaths, isEmpty);
    });

    test('all normative cloud operational paths are analyzed', () async {
      final result = await analyzer.analyzeCloudFrameworkPackage(platformRoot);
      for (final path in GuardianCloudFrameworkPaths.cloudOperationalPaths) {
        expect(
          result.analyzedFiles,
          contains(path),
          reason: 'cloud operational path missing: $path',
        );
        expect(File(p.join(platformRoot, path)).existsSync(), isTrue);
      }
    });

    test('all normative cloud model paths are analyzed', () async {
      final result = await analyzer.analyzeCloudFrameworkPackage(platformRoot);
      for (final path in GuardianCloudFrameworkPaths.cloudModelPaths) {
        expect(result.analyzedFiles, contains(path));
      }
    });

    test('all normative filesystem adapter paths are analyzed', () async {
      final result = await analyzer.analyzeCloudFrameworkPackage(platformRoot);
      for (final path in GuardianCloudFrameworkPaths.filesystemAdapterPaths) {
        expect(result.analyzedFiles, contains(path));
      }
      expect(
        result.analyzedFiles
            .where(
              (f) => f
                  .startsWith(GuardianCloudFrameworkPaths.filesystemPathPrefix),
            )
            .length,
        greaterThanOrEqualTo(
          GuardianCloudFrameworkPaths.filesystemAdapterPaths.length,
        ),
      );
    });

    test('all 10 cryptographic trust adapters are analyzed', () async {
      final result = await analyzer.analyzeCloudFrameworkPackage(platformRoot);
      for (final path
          in GuardianCryptographicAdapterPaths.adapterRelativePaths) {
        expect(result.analyzedAdapterPaths, contains(path));
        expect(File(p.join(platformRoot, path)).existsSync(), isTrue);
      }
      expect(
        result.analyzedAdapterPaths
            .where((p) => p.startsWith('lib/cryptographic_trust/'))
            .length,
        10,
      );
    });

    test('fails when a normative cloud path is missing from analysis',
        () async {
      final result = await analyzer.analyzePackage(
        platformRoot,
        requiredAdapterRelativePaths: const [
          'lib/persistent_artifacts/cloud/nonexistent_cloud_gate.dart',
        ],
      );
      expect(result.isComplete, isFalse);
      expect(result.missingAdapterPaths, isNotEmpty);
    });

    test('five consecutive targeted runs are deterministic', () async {
      final fingerprints = <String>[];
      final fileLists = <List<String>>[];
      final unresolvedCounts = <int>[];

      for (var i = 0; i < 5; i++) {
        final result =
            await analyzer.analyzeCloudFrameworkPackage(platformRoot);
        fingerprints.add(result.analysisFingerprint);
        fileLists.add(result.analyzedFiles);
        unresolvedCounts.add(result.unresolvedImports.length);
      }

      expect(fingerprints.toSet().length, 1);
      expect(unresolvedCounts, everyElement(0));
      for (final files in fileLists) {
        expect(files, fileLists.first);
      }
      expect(fileLists.first.length, greaterThanOrEqualTo(772));
    });

    test('CLI-equivalent full package analysis matches framework completeness',
        () async {
      final full = await analyzer.analyzePackage(platformRoot);
      final framework =
          await analyzer.analyzeCloudFrameworkPackage(platformRoot);
      expect(full.isComplete, isTrue);
      expect(framework.isComplete, isTrue);
      expect(full.analysisFingerprint, framework.analysisFingerprint);
      expect(full.unresolvedImports, isEmpty);
    });
  });
}
