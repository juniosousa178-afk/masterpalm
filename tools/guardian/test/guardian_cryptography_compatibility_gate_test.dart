import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../lib/package_resolution/guardian_cryptographic_adapter_paths.dart';
import '../lib/package_resolution/guardian_package_analyzer.dart';
import '../lib/package_resolution/guardian_package_context.dart';
import 'support/guardian_test_bootstrap.dart';
import 'support/guardian_test_paths.dart';

void main() {
  final platformRoot = GuardianTestPaths.platformPackageRoot();

  const analyzer = GuardianPackageAnalyzer();

  group('Guardian Cryptography Compatibility Gate — tools/platform', () {
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
      expect(context.packageConfig['crypto'], isNotNull);
      expect(context.packageConfig['cryptography'], isNotNull);
    });

    test('resolves crypto and cryptography for platform adapters', () async {
      final result =
          await analyzer.analyzeCryptographicTrustPackage(platformRoot);

      expect(result.isComplete, isTrue,
          reason: result.unresolvedImports.toString());
      expect(result.unresolvedImports, isEmpty);
      expect(result.missingAdapterPaths, isEmpty);

      expect(
        result.resolvedPackageImports,
        containsAll(GuardianCryptographicAdapterPaths.requiredPackageImports),
      );

      for (final adapterPath
          in GuardianCryptographicAdapterPaths.adapterRelativePaths) {
        expect(
          result.analyzedAdapterPaths,
          contains(adapterPath),
          reason: 'adapter must be analyzed: $adapterPath',
        );
        expect(
          File(p.join(platformRoot, adapterPath)).existsSync(),
          isTrue,
          reason: 'adapter file must exist: $adapterPath',
        );
      }
    });

    test('ensureCryptographicTrustResolvable completes without exception',
        () async {
      await expectLater(
        analyzer.ensureCryptographicTrustResolvable(platformRoot),
        completes,
      );
    });

    test('analysis fingerprint is stable across five runs', () async {
      final fingerprints = <String>[];
      final fileSets = <List<String>>[];

      for (var i = 0; i < 5; i++) {
        final result =
            await analyzer.analyzeCryptographicTrustPackage(platformRoot);
        fingerprints.add(result.analysisFingerprint);
        fileSets.add(result.analyzedFiles);
      }

      expect(fingerprints.toSet().length, 1);
      for (final files in fileSets) {
        expect(files, fileSets.first);
      }
    });

    test('fails when required adapter path is missing from analysis', () async {
      final result = await analyzer.analyzePackage(
        platformRoot,
        requiredAdapterRelativePaths: const [
          'lib/cryptographic_trust/adapters/nonexistent_adapter.dart',
        ],
      );
      expect(result.isComplete, isFalse);
      expect(result.missingAdapterPaths, isNotEmpty);
    });
  });
}
