// Guardian — bloqueia padrões fail-open no gate de build do cliente (R8.4.6).

import 'dart:io';

import 'package:test/test.dart';

void main() {
  final repoRoot = Directory.current.parent.parent;
  final libDir = Directory('${repoRoot.path}/lib');

  test('CLIENT_BUILD_GATE_FAIL_OPEN_PATTERN_BLOCKED', () {
    final violations = <String>[];
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final content = entity.readAsStringSync();
      if (RegExp(
        r'return\s+debugClientBuildNumberOverride\s*\?\?\s*kMinStockRevisionClientVersion',
      ).hasMatch(content)) {
        violations.add('${entity.path}: direct kMin fallback in resolve');
      }
      if (RegExp(r'clientBuildNumber\s*=\s*kMinStockRevisionClientVersion')
          .hasMatch(content)) {
        violations.add('${entity.path}: default clientBuildNumber = kMin');
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
