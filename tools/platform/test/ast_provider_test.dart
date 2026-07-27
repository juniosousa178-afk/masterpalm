import 'dart:io';

import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('FileSystemAstProvider', () {
    late Directory tempDir;
    late PlatformCore platform;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('platform_ast_test_');
      platform = PlatformBootstrap.forRepo(tempDir.path);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('saveReport and loadReport round-trip', () {
      final ast = platform.ast();
      final report = {
        'meta': {'tool': 'test'},
        'methods': {
          'A.b': {'file': 'lib/a.dart', 'complexity': 5},
        },
      };

      ast.saveReport(report);
      expect(File(ast.reportPath).existsSync(), isTrue);
      expect(ast.loadReport()['meta'], {'tool': 'test'});
      expect(ast.complexityForFile('lib/a.dart'), 5);
    });

    test('reportPath uses canonical Paths.astReportJson', () {
      final ast = platform.ast();
      expect(
        ast.reportPath,
        p.join(
          tempDir.path,
          'docs',
          'intelligence',
          'ast',
          '_data',
          'ast_report.json',
        ),
      );
    });
  });
}
