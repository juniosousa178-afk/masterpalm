// lib/src/io_compat_io.dart
import 'package:path_provider/path_provider.dart';
import 'dart:io' as io;

export 'dart:io' show File;

Future<String> getAppDocsDirPath() async {
  final dir = await getApplicationDocumentsDirectory();
  return dir.path;
}

/// Wrapper para criar File que funciona em IO mas não no web
dynamic createFile(String path) {
  return io.File(path);
}
