// Executa com: dart run tool/find_unreferenced.dart
//
// O script monta um grafo simples de imports/parts começando em lib/main.dart
// e lista arquivos .dart dentro de lib/ que não são alcançados.
// Ele ignora os gerados (*.g.dart), e pode ser ajustado nas listas de ignore.

import 'dart:io';

final libDir = Directory('lib');

final ignorePaths = <String>[
  // Ajuste se quiser ignorar pastas inteiras:
  // 'lib/debug/', 'lib/web/'
];

final ignoreFiles = <String>[
  // Adicione nomes específicos a ignorar se quiser manter mesmo sem referenciar:
  // 'catalog_stub.dart',
];

bool shouldIgnore(FileSystemEntity e) {
  final p = e.path.replaceAll('\\', '/');
  if (!p.endsWith('.dart')) return true;
  if (p.endsWith('.g.dart')) return true;
  for (final ig in ignorePaths) {
    if (p.startsWith(ig)) return true;
  }
  for (final ig in ignoreFiles) {
    if (p.endsWith('/$ig')) return true;
  }
  return false;
}

final importRe = RegExp(
    r'''^\s*(import|export)\s+['"]package:[^'"]*['"]|^\s*(import|export)\s+['"]([^'"]+)['"]''');
final partRe = RegExp(r'''^\s*part\s+['"]([^'"]+)['"]''');
final partOfRe = RegExp(r'^\s*part of ');

String norm(String p) => p.replaceAll('\\', '/');

Future<Set<String>> reachableFrom(String entry) async {
  final visited = <String>{};
  final queue = <String>[entry];

  while (queue.isNotEmpty) {
    final cur = queue.removeAt(0);
    if (visited.contains(cur)) continue;
    visited.add(cur);

    final file = File(cur);
    if (!await file.exists()) continue;
    final dir = norm(File(cur).parent.path);

    final lines = await file.readAsLines();
    for (final raw in lines) {
      final line = raw.trim();

      // Segue imports/exports relativos
      final m = importRe.firstMatch(line);
      if (m != null) {
        // Caso 1: import/export "caminho/relativo.dart"
        final rel = m.group(3);
        if (rel != null &&
            (rel.startsWith('./') ||
                rel.startsWith('../') ||
                !rel.contains(':'))) {
          final next = norm('$dir/$rel');
          final resolved = norm(Uri.file(next).normalizePath().toFilePath());
          if (resolved.startsWith(norm(libDir.path))) queue.add(resolved);
        }
        continue;
      }

      // Segue parts
      final pm = partRe.firstMatch(line);
      if (pm != null) {
        final rel = pm.group(1)!;
        final next = norm('$dir/$rel');
        final resolved = norm(Uri.file(next).normalizePath().toFilePath());
        if (resolved.startsWith(norm(libDir.path))) queue.add(resolved);
        continue;
      }
    }
  }
  return visited;
}

Future<void> main() async {
  if (!await libDir.exists()) {
    stderr.writeln('Pasta lib/ não encontrada. Rode na raiz do projeto.');
    exit(1);
  }

  final entry = norm('lib/main.dart');
  if (!await File(entry).exists()) {
    stderr.writeln('Arquivo lib/main.dart não encontrado.');
    exit(1);
  }

  final allFiles = <String>{};
  await for (final e in libDir.list(recursive: true)) {
    if (e is File) {
      final p = norm(e.path);
      if (!shouldIgnore(e)) allFiles.add(p);
    }
  }

  final used = await reachableFrom(entry);

  // Inclui também os arquivos que fazem "part of" de alguém visitado,
  // pois podem não ser puxados diretamente do main, e sim por uma lib principal.
  final addByPartOf = <String>{};
  for (final f in allFiles.difference(used)) {
    final content = await File(f).readAsString();
    if (partOfRe.hasMatch(content)) {
      // se algum arquivo que já está em "used" declara "part 'este.dart';", marque como usado
      final parentCandidates = Directory(norm(File(f).parent.path))
          .listSync()
          .whereType<File>()
          .where((ff) => !ff.path.endsWith('.g.dart'));
      bool isReferenced = false;
      for (final parent in parentCandidates) {
        final txt = await parent.readAsString();
        final relName = f.split('/').last;
        if (txt.contains("part '$relName'") ||
            txt.contains('part "$relName"')) {
          isReferenced = true;
          break;
        }
      }
      if (isReferenced) addByPartOf.add(f);

      if (isReferenced) addByPartOf.add(f);
    }
  }

  final actuallyUsed = used.union(addByPartOf);
  final unused = allFiles.difference(actuallyUsed).toList()..sort();
// ignore_for_file: avoid_print
  print(
      '================ Unreferenced (prováveis para remover ou integrar) ================');
  if (unused.isEmpty) {
    print(
        '✔ Nenhum arquivo órfão encontrado (considerando imports/parts relativos a partir do lib/main.dart).');
  } else {
    for (final f in unused) {
      print('- $f');
    }
  }

  print(
      '\nDica: revise antes de excluir. Alguns arquivos podem ser carregados por reflexão, rotas dinâmicas ou '
      'usados apenas em testes/ambiente web. Ajuste as listas ignorePaths/ignoreFiles conforme sua arquitetura.');
}
