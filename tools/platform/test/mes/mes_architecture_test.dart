import 'dart:io';

import 'package:test/test.dart';

void main() {
  final libMes = Directory('lib/mes');
  final forbidden = [
    'File(',
    'Directory(',
    'DateTime.now',
    'ast_report.json',
    'Firebase',
    'eval(',
    'ScoreRuleEvaluator',
    'ScoreNormalizer',
    'ScoreAggregator',
  ];

  group('MES architecture constraints', () {
    for (final entity in libMes.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final relative = entity.path.replaceAll('\\', '/');
      if (relative.contains('/stores/')) continue;
      final content = entity.readAsStringSync();
      for (final token in forbidden) {
        test('$relative does not use $token', () {
          expect(content.contains(token), isFalse, reason: 'found $token');
        });
      }
    }
  });
}
