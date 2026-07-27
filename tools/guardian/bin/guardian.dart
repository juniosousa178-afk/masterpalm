import 'dart:io';

import 'package:args/args.dart';
import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:path/path.dart' as p;

import '../lib/generate_report.dart';
import '../lib/guardian_evidence.dart';
import '../lib/guardian_platform_bootstrap.dart';
import '../lib/models/guardian_result.dart';
import '../lib/providers/guardian_engine_provider.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addFlag('working-tree', negatable: false)
    ..addFlag('staged', negatable: false)
    ..addFlag('simulation', defaultsTo: true)
    ..addOption('files', help: 'Comma-separated file list')
    ..addOption('files-manifest',
        help: 'Path to manifest file (one relative path per line)')
    ..addOption('base', defaultsTo: 'HEAD~1')
    ..addOption('head', defaultsTo: 'HEAD')
    ..addOption('report',
        defaultsTo: 'markdown', allowed: ['markdown', 'json'])
    ..addOption('evidence', help: 'Path to guardian-evidence.json (G009)')
    ..addOption('candidate-patch-sha256',
        help: 'SHA-256 esperado do patch funcional (alias)')
    ..addOption('functional-patch-sha256',
        help: 'SHA-256 esperado do patch funcional R845')
    ..addOption('base-head',
        help: 'HEAD lógico esperado na evidência G009 (ex.: 17fb382…)')
    ..addOption('diff-base',
        help: 'Ref git para diff no modo --files (default: base-head ou root commit)');

  final args = parser.parse(arguments);
  final repoRoot = _findRepoRoot();
  final session = GuardianPlatformBootstrap.create(repoRoot: repoRoot);

  List<String>? files;
  if (args['files'] != null) {
    files = (args['files'] as String)
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }
  final manifestPath = args['files-manifest'] as String?;
  if (manifestPath != null && manifestPath.isNotEmpty) {
    final manifestFile = File(manifestPath);
    if (!manifestFile.existsSync()) {
      stderr.writeln('files-manifest not found: $manifestPath');
      exit(2);
    }
    final fromManifest = manifestFile
        .readAsLinesSync()
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && !e.startsWith('#'))
        .toList();
    files = [...?files, ...fromManifest];
  }

  final useWorkingTree = args['working-tree'] as bool;
  final useStaged = args['staged'] as bool;

  final request = GuardianAnalysisRequest(
    context: AnalysisContext(
      project: PlatformBootstrap.projectFromRepo(repoRoot),
      snapshot: PlatformSnapshot.fresh(),
      changedFiles: files ?? const [],
      labels: const {'module': 'guardian'},
    ),
    workingTree: useWorkingTree,
    staged: useStaged,
    base: files == null && !useWorkingTree && !useStaged
        ? args['base'] as String
        : null,
    head: files == null && !useWorkingTree && !useStaged
        ? args['head'] as String
        : null,
    files: files,
    simulationOnly: args['simulation'] as bool,
  );

  final functionalPatchSha =
      (args['functional-patch-sha256'] as String?) ??
          (args['candidate-patch-sha256'] as String?);
  final baseHead = args['base-head'] as String?;
  final diffBase = (args['diff-base'] as String?) ?? baseHead;

  var g009EvidenceSatisfied = false;
  final evidencePath = args['evidence'] as String?;
  if (evidencePath != null && evidencePath.isNotEmpty) {
    final validation = GuardianEvidenceValidator.validate(
      repoRoot: repoRoot,
      evidencePath: evidencePath,
      expectedFunctionalPatchSha256: functionalPatchSha,
      expectedBaseHead: baseHead,
    );
    g009EvidenceSatisfied = validation.isValid;
    if (!validation.isValid) {
      stderr.writeln(
          'G009 evidence rejected: ${validation.rejectionReason}');
    }
  }

  final provider = session.platform.guardian() as GuardianEngineProvider;
  final result = await provider.analyzeGuardian(
    request,
    g009EvidenceSatisfied: g009EvidenceSatisfied,
    explicitBaseHead: files != null && files.isNotEmpty ? diffBase : null,
  );

  if (args['report'] == 'json') {
    stdout.writeln(ReportGenerator.toJson(result));
  } else {
    stdout.writeln(ReportGenerator.toMarkdown(result));
  }

  exit(result.decision == GuardianDecision.go ? 0 : 1);
}

String _findRepoRoot() {
  var dir = Directory.current;
  while (true) {
    if (File(p.join(dir.path, 'pubspec.yaml')).existsSync() &&
        Directory(p.join(dir.path, 'lib')).existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return Directory.current.path;
}
