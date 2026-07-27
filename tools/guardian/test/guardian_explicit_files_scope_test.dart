import 'dart:io';

import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../lib/diff_analyzer.dart';
import '../lib/guardian_config.dart';
import '../lib/impact_analyzer.dart';

/// GF1–GF6 — escopo do modo --files com base-aware diff.
void main() {
  final configRepo =
      p.normalize(p.join(Directory.current.path, '..', '..'));
  final config = GuardianConfig.load(configRepo);
  final ast = _NoopAst();

  late Directory repo;
  late String baselineSha;

  Future<void> initRepo() async {
    repo = await Directory.systemTemp.createTemp('gf_scope_');
    await Process.run('git', ['init', '-q'], workingDirectory: repo.path);
    await Process.run('git', ['config', 'user.email', 'gf@test.local'],
        workingDirectory: repo.path);
    await Process.run('git', ['config', 'user.name', 'gf'],
        workingDirectory: repo.path);
    await Process.run('git', ['config', 'core.autocrlf', 'false'],
        workingDirectory: repo.path);
    await Directory(p.join(repo.path, 'lib', 'services')).create(recursive: true);
    await Directory(p.join(repo.path, 'docs', 'guardian')).create(recursive: true);
    await File(p.join(repo.path, 'firestore.rules'))
        .writeAsString('rules_version = "2";\n');
    await File(p.join(repo.path, 'pubspec.yaml')).writeAsString('name: app\n');
    await Process.run('git', ['add', '-A'], workingDirectory: repo.path);
    await Process.run('git', ['commit', '-q', '-m', 'baseline'],
        workingDirectory: repo.path);
    baselineSha = (await Process.run('git', ['rev-parse', 'HEAD'],
            workingDirectory: repo.path))
        .stdout
        .toString()
        .trim();
  }

  Future<void> writeAndCommit(String rel, String content, String msg) async {
    final full = p.join(repo.path, rel);
    await File(full).parent.create(recursive: true);
    await File(full).writeAsString(content);
    await Process.run('git', ['add', '-A'], workingDirectory: repo.path);
    await Process.run('git', ['commit', '-q', '-m', msg],
        workingDirectory: repo.path);
    baselineSha = (await Process.run('git', ['rev-parse', 'HEAD'],
            workingDirectory: repo.path))
        .stdout
        .toString()
        .trim();
  }

  Future<DiffAnalysis> diffFiles(List<String> files) async {
    final analyzer = DiffAnalyzer(repoRoot: repo.path);
    return analyzer.fromGit(
      explicitFiles: files,
      explicitBaseHead: baselineSha,
    );
  }

  setUp(() async {
    await initRepo();
  });

  tearDown(() async {
    if (repo.existsSync()) await repo.delete(recursive: true);
  });

  test('GF1 — termos históricos não alterados não acionam domínios alheios', () async {
    await writeAndCommit(
      'lib/services/estoque_transaction_service.dart',
      '''
// financeiro contas_receber fiado catalogo public_catalog
class EstoqueTransactionService {
  static Future<void> legacy() async {}
}
''',
      'base service',
    );

    await File(p.join(repo.path, 'lib/services/estoque_transaction_service.dart'))
        .writeAsString('''
// financeiro contas_receber fiado catalogo public_catalog
class EstoqueTransactionService {
  static Future<void> legacy() async {}
  static Future<void> baixarEstoqueTransactionBatchIdempotente() async {}
}
''');

    final diff = await diffFiles(['lib/services/estoque_transaction_service.dart']);
    final imp = ImpactAnalyzer(config: config, ast: ast).analyze(diff);

    expect(imp.domains, contains('Estoque'));
    expect(imp.domains, isNot(contains('Financeiro')));
    expect(imp.domains, isNot(contains('Fiado')));
    expect(imp.domains, isNot(contains('Catálogo')));
  });

  test('GF2 — ficheiro listado sem mudança não gera alteração', () async {
    await writeAndCommit(
      'lib/services/estoque_service.dart',
      'class EstoqueService {}\n',
      'stable',
    );

    final diff = await diffFiles(['lib/services/estoque_service.dart']);
    expect(diff.changes, isEmpty);
  });

  test('GF3 — somente documentação não aciona domínio de produção', () async {
    await File(p.join(repo.path, 'docs/guardian/notes.md'))
        .writeAsString('# estoque financeiro pdv\n');

    final diff = await diffFiles(['docs/guardian/notes.md']);
    final imp = ImpactAnalyzer(config: config, ast: ast).analyze(diff);

    expect(
      imp.domains.where((d) => d == 'Estoque' || d == 'Financeiro'),
      isEmpty,
    );
  });

  test('GF4 — firestore.rules alterado aciona segurança', () async {
    await File(p.join(repo.path, 'firestore.rules'))
        .writeAsString('rules_version = "2";\nmatch /x { allow read: if true; }\n');

    final diff = await diffFiles(['firestore.rules']);
    expect(diff.securityRulesTouched, isTrue);
  });

  test('GF5 — serviço de estoque alterado aciona Estoque', () async {
    await File(p.join(repo.path, 'lib/services/estoque_transaction_service.dart'))
        .writeAsString('''
class EstoqueTransactionService {
  static Future<void> baixarEstoqueTransactionBatchIdempotente() async {}
}
''');

    final diff = await diffFiles(['lib/services/estoque_transaction_service.dart']);
    final imp = ImpactAnalyzer(config: config, ast: ast).analyze(diff);
    expect(imp.domains, contains('Estoque'));
  });

  test('GF6 — edição não financeira em ficheiro com código financeiro antigo',
      () async {
    await writeAndCommit(
      'lib/services/vendas_service.dart',
      '''
class VendasService {
  Future<void> lancamento_financeiro() async {}
  Future<void> salvarVenda() async {}
}
''',
      'vendas base',
    );

    await File(p.join(repo.path, 'lib/services/vendas_service.dart'))
        .writeAsString('''
class VendasService {
  Future<void> lancamento_financeiro() async {}
  Future<void> salvarVenda() async {}
  Future<void> baixarEstoqueTransactionBatchIdempotente() async {}
}
''');

    final diff = await diffFiles(['lib/services/vendas_service.dart']);
    final imp = ImpactAnalyzer(config: config, ast: ast).analyze(diff);

    expect(imp.domains, contains('PDV'));
    expect(imp.domains, isNot(contains('Financeiro')));
  });
}

class _NoopAst implements AstProvider {
  @override
  String get reportPath => '';

  @override
  Map<String, dynamic> loadReport() => {};

  @override
  void saveReport(Map<String, dynamic> report) {}

  @override
  int? complexityForMethod(String methodKey) => null;

  @override
  int? complexityForFile(String relPath) => null;

  @override
  int? linesForFile(String relPath) => null;

  @override
  List<String> callersForFile(String relPath) => const [];

  @override
  bool hasImportCycle(List<String> changedFiles) => false;
}
