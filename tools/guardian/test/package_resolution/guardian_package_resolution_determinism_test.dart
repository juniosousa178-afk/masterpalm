import 'package:test/test.dart';

import '../../lib/package_resolution/guardian_package_analyzer.dart';
import 'package_resolution_test_helpers.dart';

void main() {
  const analyzer = GuardianPackageAnalyzer();

  setUpAll(() async {
    await PackageResolutionTestHelpers.ensureMinimalFixturePackageConfig(
      'no_external_deps',
    );
  });

  test('five consecutive runs produce identical results', () async {
    final root = PackageResolutionTestHelpers.fixtureRoot('no_external_deps');
    final fingerprints = <String>[];
    final fileLists = <List<String>>[];

    for (var i = 0; i < 5; i++) {
      final result = await analyzer.analyzePackage(root);
      fingerprints.add(result.analysisFingerprint);
      fileLists.add(result.analyzedFiles);
    }

    expect(fingerprints.toSet().length, 1);
    for (final files in fileLists) {
      expect(files, fileLists.first);
    }
  });
}
