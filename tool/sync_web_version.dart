/// Sincroniza a versão do pubspec.yaml com os arquivos web (manifest.json, index.html).
/// Execute: dart run tool/sync_web_version.dart
library;

import 'dart:convert';
import 'dart:io';

void main() {
  final pubspec = File('pubspec.yaml');
  if (!pubspec.existsSync()) {
    print('Erro: pubspec.yaml não encontrado');
    exit(1);
  }

  final content = pubspec.readAsStringSync();
  // Aceita versão no formato 1.0.0+1 ou 1.0.0+42S (sufixo opcional no build)
  final match = RegExp(r'^version:\s*([\d.]+)\+\d+[A-Za-z]*\s*$', multiLine: true).firstMatch(content);
  if (match == null) {
    print('Erro: versão não encontrada no pubspec.yaml');
    exit(1);
  }

  final version = match.group(1)!; // ex: 1.0.0

  print('Versão do pubspec: $version');

  // Atualizar manifest.json
  final manifestFile = File('web/manifest.json');
  if (manifestFile.existsSync()) {
    final manifest = jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
    manifest['version'] = version;
    manifestFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifest));
    print('  manifest.json atualizado');
  }

  // Atualizar meta version no index.html
  final indexFile = File('web/index.html');
  if (indexFile.existsSync()) {
    var index = indexFile.readAsStringSync();
    if (index.contains('name="version"')) {
      index = index.replaceAll(RegExp(r'<meta name="version" content="[^"]*">'), '<meta name="version" content="$version">');
    } else {
      index = index.replaceFirst('<meta name="description"', '<meta name="version" content="$version">\n  <meta name="description"');
    }
    indexFile.writeAsStringSync(index);
    print('  index.html atualizado');
  }

  print('Versão web sincronizada: $version');
}
