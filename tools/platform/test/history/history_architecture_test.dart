import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('History architecture constraints', () {
    final historyDir = Directory('lib/history');
    final files = historyDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    final forbiddenPatterns = <String, RegExp>{
      'File': RegExp(r'\bFile\b'),
      'Directory': RegExp(r'\bDirectory\b'),
      'DateTime.now': RegExp(r'DateTime\.now\s*\('),
      'ast_report.json': RegExp(r'ast_report\.json'),
      'FileSystemAstProvider': RegExp(r'FileSystemAstProvider'),
      'Firebase': RegExp(r'Firebase'),
    };

    for (final file in files) {
      final content = file.readAsStringSync();
      final relative = file.path.replaceAll('\\', '/');

      for (final entry in forbiddenPatterns.entries) {
        test('$relative does not use ${entry.key}', () {
          expect(entry.value.hasMatch(content), isFalse,
              reason: 'Forbidden pattern ${entry.key} in $relative');
        });
      }
    }
  });
}
