// Regressão estrutural — bloqueia padrões fail-open no gate de build (R8.4.6).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final repoRoot = Directory.current;
  final libDir = Directory('${repoRoot.path}/lib');

  final forbiddenPatterns = <String, String>{
    'resolveClientBuildNumber returning kMin directly':
        r'return\s+debugClientBuildNumberOverride\s*\?\?\s*kMinStockRevisionClientVersion',
    'default clientBuildNumber = kMin':
        r'clientBuildNumber\s*=\s*kMinStockRevisionClientVersion',
    'catch returning kMin': r'catch\s*\([^)]*\)\s*\{[^}]*kMinStockRevisionClientVersion',
    'tryParse fallback to kMin': r'int\.tryParse\([^)]+\)\s*\?\?\s*kMinStockRevisionClientVersion',
  };

  test('CLIENT_BUILD_GATE_FAIL_OPEN_PATTERN_BLOCKED in lib/', () {
    final violations = <String>[];
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final content = entity.readAsStringSync();
      for (final entry in forbiddenPatterns.entries) {
        if (RegExp(entry.value, multiLine: true).hasMatch(content)) {
          violations.add('${entity.path}: ${entry.key}');
        }
      }
      if (content.contains('setTestOverride') &&
          !entity.path.contains('stock_revision_client_build_resolver.dart')) {
        violations.add('${entity.path}: setTestOverride outside resolver');
      }
    }
    expect(
      violations,
      isEmpty,
      reason: violations.join('\n'),
    );
  });

  test('production lib must not reference gate test override setter', () {
    final violations = <String>[];
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.contains('stock_revision_operation_gate.dart')) continue;
      if (entity.path.contains('stock_revision_client_build_resolver.dart')) {
        continue;
      }
      final content = entity.readAsStringSync();
      if (content.contains('debugClientBuildNumberOverride')) {
        violations.add(entity.path);
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
