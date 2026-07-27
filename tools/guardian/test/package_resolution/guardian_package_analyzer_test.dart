import 'package:test/test.dart';

import '../../lib/package_resolution/guardian_package_analyzer.dart';
import '../../lib/package_resolution/guardian_package_context.dart';
import '../../lib/package_resolution/guardian_package_exceptions.dart';
import 'package_resolution_test_helpers.dart';

void main() {
  const analyzer = GuardianPackageAnalyzer();

  setUpAll(() async {
    await PackageResolutionTestHelpers.ensureMinimalFixturePackageConfig(
      'no_external_deps',
    );
    await PackageResolutionTestHelpers.ensureInvalidFixturePackageConfig();
  });

  group('GuardianPackageContext.load', () {
    test('loads package without external dependencies', () async {
      final context = await GuardianPackageContext.load(
        PackageResolutionTestHelpers.fixtureRoot('no_external_deps'),
      );
      expect(context.packageName, 'fixture_no_deps');
      expect(context.packageConfig.packages, isNotEmpty);
    });

    test('throws structured error when package_config is missing', () async {
      expect(
        () => GuardianPackageContext.load(
          PackageResolutionTestHelpers.fixtureRoot('missing_package_config'),
        ),
        throwsA(isA<GuardianPackageConfigMissingException>()),
      );
    });

    test('throws structured error when package_config is invalid', () async {
      expect(
        () => GuardianPackageContext.load(
          PackageResolutionTestHelpers.fixtureRoot('invalid_package_config'),
        ),
        throwsA(isA<GuardianPackageConfigInvalidException>()),
      );
    });
  });

  group('GuardianPackageAnalyzer fixtures', () {
    setUpAll(() async {
      for (final fixture in [
        'no_external_deps',
        'nested/packages/inner',
        'unresolved_import',
      ]) {
        await PackageResolutionTestHelpers.ensureMinimalFixturePackageConfig(
          fixture,
        );
      }
      await PackageResolutionTestHelpers.writeSyntheticPackageConfig(
        fixtureName: 'with_crypto',
        dependencyPackageNames: ['crypto'],
      );
      await PackageResolutionTestHelpers.writeSyntheticPackageConfig(
        fixtureName: 'with_cryptography',
        dependencyPackageNames: ['cryptography'],
      );
      await PackageResolutionTestHelpers.writeSyntheticPackageConfig(
        fixtureName: 'with_both',
        dependencyPackageNames: ['crypto', 'cryptography'],
      );
    });

    test('analyzes package without external dependencies', () async {
      final result = await analyzer.analyzePackage(
        PackageResolutionTestHelpers.fixtureRoot('no_external_deps'),
      );
      expect(result.isComplete, isTrue);
      expect(result.unresolvedImports, isEmpty);
      expect(result.analyzedFiles, contains('lib/main.dart'));
    });

    test('resolves crypto dependency', () async {
      final result = await analyzer.analyzePackage(
        PackageResolutionTestHelpers.fixtureRoot('with_crypto'),
      );
      expect(result.isComplete, isTrue);
      expect(
        result.resolvedPackageImports,
        contains('package:crypto/crypto.dart'),
      );
    });

    test('resolves cryptography dependency', () async {
      final result = await analyzer.analyzePackage(
        PackageResolutionTestHelpers.fixtureRoot('with_cryptography'),
      );
      expect(result.isComplete, isTrue);
      expect(
        result.resolvedPackageImports,
        contains('package:cryptography/cryptography.dart'),
      );
      expect(
        result.resolvedPackageImports,
        contains('package:cryptography/dart.dart'),
      );
    });

    test('resolves both crypto and cryptography', () async {
      final result = await analyzer.analyzePackage(
        PackageResolutionTestHelpers.fixtureRoot('with_both'),
      );
      expect(result.isComplete, isTrue);
      expect(
        result.resolvedPackageImports,
        containsAll([
          'package:crypto/crypto.dart',
          'package:cryptography/cryptography.dart',
          'package:cryptography/dart.dart',
        ]),
      );
    });

    test('reports unresolved imports explicitly', () async {
      final result = await analyzer.analyzePackage(
        PackageResolutionTestHelpers.fixtureRoot('unresolved_import'),
      );
      expect(result.isComplete, isFalse);
      expect(result.unresolvedImports, isNotEmpty);
      expect(
        () => result.throwIfIncomplete(),
        throwsA(isA<GuardianPackageResolutionException>()),
      );
    });

    test('analyzes nested package root', () async {
      final result = await analyzer.analyzePackage(
        PackageResolutionTestHelpers.fixtureRoot('nested/packages/inner'),
      );
      expect(result.isComplete, isTrue);
      expect(result.analyzedFiles, contains('lib/inner.dart'));
    });

    test('repeated analysis is deterministic', () async {
      final root = PackageResolutionTestHelpers.fixtureRoot('no_external_deps');
      final first = await analyzer.analyzePackage(root);
      final second = await analyzer.analyzePackage(root);
      expect(second.analysisFingerprint, first.analysisFingerprint);
      expect(second.analyzedFiles, first.analyzedFiles);
      expect(second.resolvedPackageImports, first.resolvedPackageImports);
    });
  });
}
