// lib/src/file_saver_mobile.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

/// Salva bytes em um arquivo local (mobile/desktop)
Future<String> saveFile(Uint8List bytes, String fileName) async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsBytes(bytes);
  return file.path;
}

/// Lê bytes de um caminho de arquivo
Future<Uint8List> readFileBytes(String path) async {
  return await File(path).readAsBytes();
}

/// Lê bytes de um PlatformFile (mobile usa path, web usa bytes)
Uint8List? getBytesFromPickerResult(dynamic platformFile) {
  // Em mobile, platformFile é PlatformFile com .path
  return null; // Caller deve usar File(path).readAsBytes()
}
