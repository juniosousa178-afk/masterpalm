import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('metrics module has no forbidden access patterns', () {
    final metricsDir = Directory('lib/metrics');
    final providersFile = File('lib/providers/platform_metrics_provider.dart');
    final patterns = [
      RegExp(r'\bFile\s*\('),
      RegExp(r'\bDirectory\s*\('),
      RegExp(r'ast_report\.json'),
      RegExp(r'FileSystemAstProvider'),
      RegExp(r'\bFirebase\b'),
      RegExp(r'package:hive'),
      RegExp(r'https?://'),
      RegExp(r'DateTime\.now'),
    ];

    final files = [
      ...metricsDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')),
      providersFile,
    ];

    for (final file in files) {
      final content = file.readAsStringSync();
      for (final pattern in patterns) {
        expect(
          pattern.hasMatch(content),
          isFalse,
          reason: '${file.path} must not match $pattern',
        );
      }
    }
  });
}
