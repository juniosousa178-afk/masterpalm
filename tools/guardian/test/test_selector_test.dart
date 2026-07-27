import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../lib/guardian_platform_bootstrap.dart';
import '../lib/models/impact_result.dart';
import '../lib/test_selector.dart';

void main() {
  final repoRoot = p.normalize(p.join(Directory.current.path, '..', '..'));
  final config = GuardianPlatformBootstrap.create(repoRoot: repoRoot).config;
  final selector = TestSelector(repoRoot: repoRoot, config: config);

  test('selects estoque tests for Estoque domain', () {
    final impact = ImpactResult(domains: ['Estoque']);
    final sel = selector
        .select(impact, ['lib/services/estoque_transaction_service.dart']);
    expect(sel.required, isNotEmpty);
    expect(
      sel.required.any((t) => t.contains('estoque_transaction')),
      isTrue,
    );
  });
}
