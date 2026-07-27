import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

import '../lib/package_resolution/guardian_package_analyzer.dart';
import '../lib/package_resolution/guardian_package_analysis_result.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('package', abbr: 'p', help: 'Package root to analyze')
    ..addFlag(
      'cryptographic-trust',
      negatable: false,
      help: 'Run Cryptographic Trust adapter compatibility gate',
    )
    ..addFlag('json', negatable: false, help: 'Emit JSON output');

  final args = parser.parse(arguments);
  final packageRoot = args['package'] as String? ??
      _defaultPlatformRoot(Directory.current.path);

  final analyzer = const GuardianPackageAnalyzer();
  final GuardianPackageAnalysisResult result;

  if (args['cryptographic-trust'] as bool) {
    result = await analyzer.analyzeCryptographicTrustPackage(packageRoot);
  } else {
    result = await analyzer.analyzePackage(packageRoot);
  }

  if (args['json'] as bool) {
    stdout.writeln(
        const JsonEncoder.withIndent('  ').convert(result.toComparableJson()));
  } else {
    stdout.writeln('Guardian package analysis: ${result.packageName}');
    stdout.writeln('Root: ${result.packageRoot}');
    stdout.writeln('Files: ${result.analyzedFiles.length}');
    stdout.writeln('Unresolved: ${result.unresolvedImports.length}');
    stdout.writeln('Adapters analyzed: ${result.analyzedAdapterPaths.length}');
    stdout.writeln('Complete: ${result.isComplete}');
    stdout.writeln('Fingerprint: ${result.analysisFingerprint}');
  }

  if (!result.isComplete) {
    stderr.writeln('Package analysis incomplete.');
    for (final issue in result.unresolvedImports) {
      stderr.writeln('  unresolved: ${issue.uri} in ${issue.filePath}');
    }
    for (final missing in result.missingAdapterPaths) {
      stderr.writeln('  missing adapter: $missing');
    }
    exit(1);
  }
}

String _defaultPlatformRoot(String cwd) {
  final candidate =
      Directory(cwd).parent.path == cwd ? cwd : Directory(cwd).path;
  final platformSibling =
      Directory('$candidate${Platform.pathSeparator}platform');
  if (platformSibling.existsSync()) {
    return platformSibling.path;
  }
  final nested = Directory(
    '$candidate${Platform.pathSeparator}..${Platform.pathSeparator}platform',
  );
  if (nested.existsSync()) {
    return nested.absolute.path;
  }
  return candidate;
}
