// Preflight local — pubspec buildNumber deve ser >= kMinStockRevisionClientVersion.

import 'dart:io';

void main() {
  final repoRoot = Directory.current;
  final pubspec = File('${repoRoot.path}/pubspec.yaml');
  final enforcement = File(
    '${repoRoot.path}/lib/core/produto_stock_write_enforcement.dart',
  );

  if (!pubspec.existsSync()) {
    stderr.writeln('PREFLIGHT_FAIL: pubspec.yaml not found');
    exit(1);
  }
  if (!enforcement.existsSync()) {
    stderr.writeln('PREFLIGHT_FAIL: produto_stock_write_enforcement.dart not found');
    exit(1);
  }

  final versionLine = pubspec
      .readAsLinesSync()
      .firstWhere((l) => l.trim().startsWith('version:'), orElse: () => '');
  final match = RegExp(r'\+(\d+)\s*$').firstMatch(versionLine.trim());
  if (match == null) {
    stderr.writeln('PREFLIGHT_FAIL: cannot parse pubspec version line: $versionLine');
    exit(1);
  }
  final pubspecBuild = int.parse(match.group(1)!);

  final minMatch = RegExp(
    r'const int kMinStockRevisionClientVersion = (\d+);',
  ).firstMatch(enforcement.readAsStringSync());
  if (minMatch == null) {
    stderr.writeln('PREFLIGHT_FAIL: kMinStockRevisionClientVersion not found');
    exit(1);
  }
  final minBuild = int.parse(minMatch.group(1)!);

  if (pubspecBuild < minBuild) {
    stderr.writeln(
      'PREFLIGHT_FAIL: pubspec build $pubspecBuild < minimum $minBuild',
    );
    exit(1);
  }

  stdout.writeln(
    'PREFLIGHT_OK: pubspec build $pubspecBuild >= minimum $minBuild',
  );
}
