import 'dart:io';

import 'package:path/path.dart' as p;

/// Scans Dart source files for import directives without executing code.
class GuardianPackageImportScanner {
  const GuardianPackageImportScanner();

  static final _importPattern = RegExp(
    r"^\s*import\s+'([^']+)'\s*;",
    multiLine: true,
  );

  static final _exportPattern = RegExp(
    r"^\s*export\s+'([^']+)'\s*;",
    multiLine: true,
  );

  /// Extracts import and export URIs from [content].
  List<String> extractUris(String content) {
    final uris = <String>{};
    for (final match in _importPattern.allMatches(content)) {
      uris.add(match.group(1)!);
    }
    for (final match in _exportPattern.allMatches(content)) {
      uris.add(match.group(1)!);
    }
    return uris.toList()..sort();
  }

  /// Lists `.dart` files under [libDirectory] deterministically.
  List<String> listDartFiles(String libDirectory) {
    final dir = Directory(libDirectory);
    if (!dir.existsSync()) return const [];

    final files = <String>[];
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        files.add(p.normalize(entity.path));
      }
    }
    files.sort();
    return files;
  }
}
