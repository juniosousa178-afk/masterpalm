import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../lib/diff_analyzer.dart';
import '../lib/guardian_platform_bootstrap.dart';
import '../lib/models/risk_result.dart';
import '../lib/risk_classifier.dart';

void main() {
  final repoRoot = p.normalize(p.join(Directory.current.path, '..', '..'));
  final config = GuardianPlatformBootstrap.create(repoRoot: repoRoot).config;
  final classifier = RiskClassifier(config: config);
  test('classifies estoque as red', () {
    final diff = DiffAnalyzer(repoRoot: repoRoot).fromPatch('');
    final result = classifier.classify(diff, ['Estoque']);
    expect(result.overall, RiskLevel.red);
  });
}
