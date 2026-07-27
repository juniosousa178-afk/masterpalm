import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('Score architecture constraints', () {
    final scoreDir = Directory('lib/score');
    final files = scoreDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    final forbiddenPatterns = <String, RegExp>{
      'File': RegExp(r'\bFile\b'),
      'Directory': RegExp(r'\bDirectory\b'),
      'DateTime.now': RegExp(r'DateTime\.now\s*\('),
      'ast_report.json': RegExp(r'ast_report\.json'),
      'Firebase': RegExp(r'Firebase'),
      'eval': RegExp(r'\beval\b'),
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
