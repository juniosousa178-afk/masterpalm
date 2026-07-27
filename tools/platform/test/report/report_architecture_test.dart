import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('report module has no forbidden file or network access patterns', () {
    final reportDir = Directory('lib/report');
    final providersFile = File('lib/providers/platform_report_provider.dart');
    final patterns = [
      RegExp(r'\bFile\s*\('),
      RegExp(r'\bDirectory\s*\('),
      RegExp(r'ast_report\.json'),
      RegExp(r'FileSystemAstProvider'),
      RegExp(r'\bFirebase\b'),
      RegExp(r'Firestore\.instance'),
      RegExp(r'package:hive'),
      RegExp(r'\bHive\.'),
      RegExp(r'https?://'),
    ];

    final files = [
      ...reportDir
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
