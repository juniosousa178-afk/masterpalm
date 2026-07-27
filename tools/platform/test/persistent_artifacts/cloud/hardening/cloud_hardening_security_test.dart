import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('CloudHardeningSecurityReview', () {
    final cloudLibDir = Directory('lib/persistent_artifacts/cloud');
    final forbidden = [
      'HttpClient',
      'dart:io',
      'package:aws',
      'package:googleapis',
      'package:azure',
    ];

    test('cloud lib sem tokens proibidos de rede/SDK', () {
      final files = cloudLibDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
      for (final file in files) {
        final content = file.readAsStringSync();
        for (final token in forbidden) {
          expect(content.contains(token), isFalse,
              reason: '${file.path} $token');
        }
      }
    });

    test('admission evaluator em lib sem dependência de rede', () {
      final content = File(
        'lib/persistent_artifacts/cloud/persistent_artifact_real_cloud_adapter_admission_evaluator.dart',
      ).readAsStringSync();
      expect(content.contains('HttpClient'), isFalse);
      expect(content.contains('dart:io'), isFalse);
    });
  });
}
