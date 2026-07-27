import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Shared file-system helpers for platform providers.
class FileHelpers {
  const FileHelpers();

  bool exists(String path) => File(path).existsSync();

  bool directoryExists(String path) => Directory(path).existsSync();

  String readText(String path) => File(path).readAsStringSync();

  Map<String, dynamic> readJsonMap(String path) {
    final decoded = jsonDecode(readText(path));
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('Expected JSON object at $path');
    }
    return decoded;
  }

  List<String> listFilesRecursive(
    String directory, {
    bool Function(File file)? filter,
  }) {
    final dir = Directory(directory);
    if (!dir.existsSync()) return [];

    final results = <String>[];
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (filter != null && !filter(entity)) continue;
      results.add(p.normalize(entity.path));
    }
    results.sort();
    return results;
  }

  void ensureDirectory(String directory) {
    Directory(directory).createSync(recursive: true);
  }

  void writeText(String path, String content) {
    File(path).writeAsStringSync(content);
  }
}
