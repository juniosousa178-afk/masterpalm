// lib/src/file_saver_web.dart
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data';

/// Salva bytes disparando download no navegador
Future<String> saveFile(Uint8List bytes, String fileName) async {
  final blob = html.Blob([bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..click();
  html.Url.revokeObjectUrl(url);
  return fileName;
}

/// No web, não temos acesso a arquivos locais por path
Future<Uint8List> readFileBytes(String path) async {
  throw UnsupportedError('readFileBytes não suportado no Web');
}

/// No web, não precisa - file_picker já retorna bytes
Uint8List• getBytesFromPickerResult(dynamic platformFile) {
  return null;
}
