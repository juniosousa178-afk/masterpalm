import 'dart:io';

import 'package:package_config/package_config.dart';
import 'package:test/test.dart';

import '../../lib/package_resolution/guardian_package_context.dart';
import '../../lib/package_resolution/guardian_package_exceptions.dart';
import '../../lib/package_resolution/guardian_package_resolver.dart';
import 'package_resolution_test_helpers.dart';

void main() {
  const resolver = GuardianPackageResolver();

  group('GuardianPackageResolver', () {
    test('resolves package import present in target config', () async {
      final config = await PackageResolutionTestHelpers.buildSyntheticConfig(
        fixtureName: 'with_crypto',
        dependencyPackageNames: ['crypto'],
      );
      final context = GuardianPackageContext.forTest(
        packageRoot: PackageResolutionTestHelpers.fixtureRoot('with_crypto'),
        packageName: 'fixture_with_crypto',
        packageConfig: config,
      );

      final resolved = resolver.resolve('package:crypto/crypto.dart', context);
      expect(resolved, isNotNull);
      expect(resolved!.isResolved, isTrue);
      expect(resolved.packageName, 'crypto');
      expect(resolved.resolvedPath, isNotEmpty);
    });

    test('resolves cryptography and cryptography/dart.dart', () async {
      final config = await PackageResolutionTestHelpers.buildSyntheticConfig(
        fixtureName: 'with_cryptography',
        dependencyPackageNames: ['cryptography'],
      );
      final context = GuardianPackageContext.forTest(
        packageRoot:
            PackageResolutionTestHelpers.fixtureRoot('with_cryptography'),
        packageName: 'fixture_with_cryptography',
        packageConfig: config,
      );

      for (final uri in [
        'package:cryptography/cryptography.dart',
        'package:cryptography/dart.dart',
      ]) {
        final resolved = resolver.resolve(uri, context);
        expect(resolved, isNotNull, reason: uri);
        expect(resolved!.isResolved, isTrue, reason: uri);
      }
    });

    test('resolves both crypto and cryptography in same context', () async {
      final config = await PackageResolutionTestHelpers.buildSyntheticConfig(
        fixtureName: 'with_both',
        dependencyPackageNames: ['crypto', 'cryptography'],
      );
      final context = GuardianPackageContext.forTest(
        packageRoot: PackageResolutionTestHelpers.fixtureRoot('with_both'),
        packageName: 'fixture_with_both',
        packageConfig: config,
      );

      expect(
        resolver.resolve('package:crypto/crypto.dart', context)!.isResolved,
        isTrue,
      );
      expect(
        resolver
            .resolve('package:cryptography/cryptography.dart', context)!
            .isResolved,
        isTrue,
      );
    });

    test('returns unresolved for missing package', () async {
      final config = await PackageResolutionTestHelpers.buildSyntheticConfig(
        fixtureName: 'no_external_deps',
        dependencyPackageNames: [],
      );
      final context = GuardianPackageContext.forTest(
        packageRoot:
            PackageResolutionTestHelpers.fixtureRoot('no_external_deps'),
        packageName: 'fixture_no_deps',
        packageConfig: config,
      );

      final resolved =
          resolver.resolve('package:missing_dependency/missing.dart', context);
      expect(resolved, isNotNull);
      expect(resolved!.isResolved, isFalse);
    });

    test('resolveOrThrow throws for unresolved import', () async {
      final config = await PackageResolutionTestHelpers.buildSyntheticConfig(
        fixtureName: 'no_external_deps',
        dependencyPackageNames: [],
      );
      final context = GuardianPackageContext.forTest(
        packageRoot:
            PackageResolutionTestHelpers.fixtureRoot('no_external_deps'),
        packageName: 'fixture_no_deps',
        packageConfig: config,
      );

      expect(
        () => resolver.resolveOrThrow(
          'package:missing_dependency/missing.dart',
          context,
          sourceFilePath: 'lib/main.dart',
        ),
        throwsA(isA<GuardianPackageResolutionException>()),
      );
    });

    test('returns null for non-package URIs', () async {
      final config = PackageConfig([
        Package(
          'fixture',
          Uri.directory(Directory.systemTemp.path),
          languageVersion: LanguageVersion(3, 0),
        ),
      ]);
      final context = GuardianPackageContext.forTest(
        packageRoot: '/tmp',
        packageName: 'fixture',
        packageConfig: config,
      );

      expect(resolver.resolve('dart:io', context), isNull);
      expect(resolver.resolve('../other.dart', context), isNull);
    });

    test('resolves transitive dependency via target package graph', () async {
      final guardianConfig =
          await PackageResolutionTestHelpers.loadGuardianPackageConfig();
      final platform = guardianConfig['masterpalm_platform'];
      expect(platform, isNotNull);

      final context = GuardianPackageContext.forTest(
        packageRoot: '/tmp/platform',
        packageName: 'masterpalm_platform',
        packageConfig: guardianConfig,
      );

      expect(resolver.hasPackage('crypto', context), isTrue);
      expect(resolver.hasPackage('cryptography', context), isTrue);
    });
  });
}
