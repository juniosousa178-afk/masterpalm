import 'dart:io';

import 'package:path/path.dart' as p;

class FileChange {
  FileChange({
    required this.path,
    required this.status,
    this.addedLines = const [],
    this.removedLines = const [],
    this.hunks = const [],
  });

  final String path;
  final ChangeStatus status;
  final List<String> addedLines;
  final List<String> removedLines;
  final List<String> hunks;
}

enum ChangeStatus { added, modified, removed }

class DiffAnalysis {
  DiffAnalysis({
    required this.changes,
    required this.methodsChanged,
    required this.classesChanged,
    required this.importsChanged,
    required this.firestoreTouched,
    required this.hiveTouched,
    required this.transactionsTouched,
    required this.listenersTouched,
    required this.securityRulesTouched,
    required this.testsTouched,
    required this.casWeakened,
    required this.idempotencyWeakened,
    required this.repairScriptTouched,
    required this.newImportCycleSuspected,
  });

  final List<FileChange> changes;
  final List<String> methodsChanged;
  final List<String> classesChanged;
  final List<String> importsChanged;
  final List<String> firestoreTouched;
  final List<String> hiveTouched;
  final bool transactionsTouched;
  final bool listenersTouched;
  final bool securityRulesTouched;
  final bool testsTouched;
  final bool casWeakened;
  final bool idempotencyWeakened;
  final bool repairScriptTouched;
  final bool newImportCycleSuspected;

  List<String> get allPaths =>
      changes.map((c) => c.path).where((p) => p.endsWith('.dart')).toList();
}

class DiffAnalyzer {
  DiffAnalyzer({required this.repoRoot});

  final String repoRoot;

  Future<DiffAnalysis> fromGit({
    bool workingTree = false,
    bool staged = false,
    String? base,
    String? head,
    List<String>? explicitFiles,
    String? explicitBaseHead,
  }) async {
    if (explicitFiles != null && explicitFiles.isNotEmpty) {
      if (explicitBaseHead != null && explicitBaseHead.isNotEmpty) {
        return _fromExplicitFilesWithBase(explicitBaseHead, explicitFiles);
      }
      return _fromExplicitFiles(explicitFiles);
    }

    final args = <String>['diff', '--unified=0'];
    if (staged) {
      args.add('--cached');
    } else if (base != null && head != null) {
      args.add('$base..$head');
    } else if (!workingTree) {
      args.add('HEAD');
    }

    final result = await Process.run(
      'git',
      args,
      workingDirectory: repoRoot,
      runInShell: true,
    );
    if (result.exitCode != 0 && (result.stdout as String).isEmpty) {
      return _empty();
    }
    return _parseDiff((result.stdout as String));
  }

  DiffAnalysis fromPatch(String patch) => _parseDiff(patch);

  /// Modo legado: trata ficheiros inteiros como adicionados (evitar sem base).
  DiffAnalysis _fromExplicitFiles(List<String> files) {
    final changes = <FileChange>[];
    for (final f in files) {
      final rel = _normalize(f);
      final full = p.isAbsolute(f) ? f : p.join(repoRoot, rel);
      if (!File(full).existsSync()) {
        changes.add(FileChange(path: rel, status: ChangeStatus.removed));
        continue;
      }
      final content = File(full).readAsLinesSync();
      changes.add(FileChange(
        path: rel,
        status: ChangeStatus.modified,
        addedLines: content,
      ));
    }
    return _analyzeChanges(changes);
  }

  /// Modo base-aware: analisa hunks entre [baseRef] e working tree por ficheiro.
  Future<DiffAnalysis> _fromExplicitFilesWithBase(
    String baseRef,
    List<String> files,
  ) async {
    final resolvedBase = await _resolveGitRef(baseRef);
    final changes = <FileChange>[];

    for (final f in files) {
      final rel = _normalize(f);
      final full = p.isAbsolute(f) ? f : p.join(repoRoot, rel);

      final existedAtBase = await _gitPathExistsAtRef(resolvedBase, rel);

      if (!existedAtBase) {
        if (File(full).existsSync()) {
          final addedLines = _addedLinesForNewFile(rel, full);
          changes.add(FileChange(
            path: rel,
            status: ChangeStatus.added,
            addedLines: addedLines,
          ));
        } else {
          changes.add(FileChange(path: rel, status: ChangeStatus.removed));
        }
        continue;
      }

      if (!File(full).existsSync()) {
        changes.add(FileChange(path: rel, status: ChangeStatus.removed));
        continue;
      }

      final result = await Process.run(
        'git',
        ['diff', '--unified=0', resolvedBase, '--', rel],
        workingDirectory: repoRoot,
        runInShell: true,
      );
      final fileDiff = _parseDiff((result.stdout as String));
      if (fileDiff.changes.isEmpty) continue;
      changes.addAll(fileDiff.changes);
    }

    return _analyzeChanges(changes);
  }

  Future<bool> _gitPathExistsAtRef(String ref, String relPath) async {
    final result = await Process.run(
      'git',
      ['cat-file', '-e', '$ref:$relPath'],
      workingDirectory: repoRoot,
      runInShell: true,
    );
    return result.exitCode == 0;
  }

  /// Ficheiros de tooling/docs novos não devem inflar domínios de produção.
  List<String> _addedLinesForNewFile(String rel, String fullPath) {
    final path = rel.replaceAll('\\', '/');
    if (path.startsWith('tools/') ||
        path.startsWith('docs/') ||
        path.startsWith('.cursor/') ||
        path.startsWith('qa_reports/') ||
        path.endsWith('.json')) {
      return const [];
    }
    if (path.startsWith('test/') && path.contains('guardian')) {
      return const [];
    }
    return File(fullPath).readAsLinesSync();
  }

  Future<String> _resolveGitRef(String ref) async {
    final verify = await Process.run(
      'git',
      ['rev-parse', '--verify', ref],
      workingDirectory: repoRoot,
      runInShell: true,
    );
    if (verify.exitCode == 0) {
      return (verify.stdout as String).trim();
    }
    final root = await Process.run(
      'git',
      ['rev-list', '--max-parents=0', 'HEAD'],
      workingDirectory: repoRoot,
      runInShell: true,
    );
    if (root.exitCode == 0 && (root.stdout as String).trim().isNotEmpty) {
      return (root.stdout as String).trim();
    }
    return ref;
  }

  DiffAnalysis _parseDiff(String diff) {
    final changes = <FileChange>[];
    final lines = diff.split('\n');
    String? currentFile;
    ChangeStatus? status;
    final added = <String>[];
    final removed = <String>[];
    final hunks = <String>[];

    void flush() {
      if (currentFile == null || status == null) return;
      changes.add(FileChange(
        path: currentFile,
        status: status,
        addedLines: List.from(added),
        removedLines: List.from(removed),
        hunks: List.from(hunks),
      ));
      added.clear();
      removed.clear();
      hunks.clear();
    }

    for (final line in lines) {
      if (line.startsWith('diff --git ')) {
        flush();
        final parts = line.split(' ');
        if (parts.length >= 4) {
          var path = parts[3];
          if (path.startsWith('b/')) path = path.substring(2);
          currentFile = _normalize(path);
          status = ChangeStatus.modified;
        }
      } else if (line.startsWith('new file mode')) {
        status = ChangeStatus.added;
      } else if (line.startsWith('deleted file mode')) {
        status = ChangeStatus.removed;
      } else if (line.startsWith('+++') || line.startsWith('---')) {
        continue;
      } else if (line.startsWith('@@')) {
        hunks.add(line);
      } else if (line.startsWith('+') && !line.startsWith('+++')) {
        added.add(line.substring(1));
      } else if (line.startsWith('-') && !line.startsWith('---')) {
        removed.add(line.substring(1));
      }
    }
    flush();
    return _analyzeChanges(changes);
  }

  DiffAnalysis _analyzeChanges(List<FileChange> changes) {
    final methods = <String>{};
    final classes = <String>{};
    final imports = <String>{};
    final firestore = <String>{};
    final hive = <String>{};
    var tx = false;
    var listeners = false;
    var security = false;
    var tests = false;
    var casWeakened = false;
    var idempotencyWeakened = false;
    var repair = false;
    var cycleSuspect = false;

    for (final c in changes) {
      final path = c.path.replaceAll('\\', '/');
      if (path.contains('firestore.rules') || path.contains('storage.rules')) {
        security = true;
      }
      if (path.startsWith('test/')) tests = true;
      if (path.contains('tools/maintenance/') ||
          path.contains('repair_') ||
          path.contains('reparo')) {
        repair = true;
      }

      final isLibProduction = path.startsWith('lib/') &&
          !path.contains('firestore.rules') &&
          !path.contains('storage.rules');

      for (final line in [...c.addedLines, ...c.removedLines]) {
        if (isLibProduction) {
          _scanLine(line, methods, classes, imports, firestore, hive);
          if (line.contains('runTransaction') || line.contains('.batch(')) {
            tx = true;
          }
          if (line.contains('.snapshots(') ||
              line.contains('StreamBuilder') ||
              line.contains('.listen(')) {
            listeners = true;
          }
          if (_isRemoval(line, c.removedLines) &&
              (line.contains('operationId') ||
                  line.contains('stockEffectHash') ||
                  line.contains('updateTime') ||
                  line.contains('CAS'))) {
            casWeakened = true;
          }
          if (_isRemoval(line, c.removedLines) &&
              (line.contains('idempoten') ||
                  line.contains('estoque_baixa_pagamento') ||
                  line.contains('reserveOrRecover'))) {
            idempotencyWeakened = true;
          }
        }
      }

      if (path.contains('effective_plan_access') &&
          path.contains('planos_service')) {
        cycleSuspect = true;
      }
    }

    return DiffAnalysis(
      changes: changes,
      methodsChanged: methods.toList()..sort(),
      classesChanged: classes.toList()..sort(),
      importsChanged: imports.toList()..sort(),
      firestoreTouched: firestore.toList()..sort(),
      hiveTouched: hive.toList()..sort(),
      transactionsTouched: tx,
      listenersTouched: listeners,
      securityRulesTouched: security,
      testsTouched: tests,
      casWeakened: casWeakened,
      idempotencyWeakened: idempotencyWeakened,
      repairScriptTouched: repair,
      newImportCycleSuspected: cycleSuspect,
    );
  }

  bool _isRemoval(String line, List<String> removed) =>
      removed.any((r) => r == line.replaceFirst(RegExp(r'^\+'), ''));

  void _scanLine(
    String line,
    Set<String> methods,
    Set<String> classes,
    Set<String> imports,
    Set<String> firestore,
    Set<String> hive,
  ) {
    final importMatch = RegExp(r"^import\s+'([^']+)'").firstMatch(line.trim());
    if (importMatch != null) imports.add(importMatch.group(1)!);

    final classMatch =
        RegExp(r'^\s*(abstract\s+)?class\s+(\w+)').firstMatch(line);
    if (classMatch != null) classes.add(classMatch.group(2)!);

    final methodMatch = RegExp(
      r'^\s*(?:static\s+)?(?:async\s+)?[\w<>,\s\?\[\]]+\s+(\w+)\s*\(',
    ).firstMatch(line);
    if (methodMatch != null) {
      final name = methodMatch.group(1)!;
      if (!{
        'if',
        'for',
        'while',
        'switch',
        'return',
        'class',
        'import',
      }.contains(name)) {
        methods.add(name);
      }
    }

    for (final col in [
      'estoque_produtos',
      'estoque_vendas',
      'estoque_baixa_pagamento',
      'contas_receber',
      'estoque_clientes',
      'produtos',
      'draft_produtos',
      'clientes',
      'pre_pedidos',
      'sale_intents',
      'lancamentos_financeiros',
    ]) {
      if (line.contains(col)) firestore.add(col);
    }

    for (final box in [
      'HiveBoxNames',
      'Hive.box',
      'Hive.openBox',
      'produtos_',
      'vendas_',
      'venda_operation_journal',
      'contas_receber_',
      'sync_queue',
    ]) {
      if (line.contains(box)) hive.add(box);
    }
  }

  String _normalize(String path) =>
      path.replaceAll('\\', '/').replaceFirst(RegExp(r'^/'), '');

  DiffAnalysis _empty() => DiffAnalysis(
        changes: [],
        methodsChanged: [],
        classesChanged: [],
        importsChanged: [],
        firestoreTouched: [],
        hiveTouched: [],
        transactionsTouched: false,
        listenersTouched: false,
        securityRulesTouched: false,
        testsTouched: false,
        casWeakened: false,
        idempotencyWeakened: false,
        repairScriptTouched: false,
        newImportCycleSuspected: false,
      );
}
