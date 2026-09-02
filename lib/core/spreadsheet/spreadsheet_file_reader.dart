import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import 'spreadsheet_file_bytes_from_path_io.dart'
    if (dart.library.html) 'spreadsheet_file_bytes_from_path_stub.dart'
    as path_io;

class SpreadsheetFileReadException implements Exception {
  SpreadsheetFileReadException(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<Uint8List> readPlatformFileBytes(PlatformFile file) async {
  if (file.bytes != null && file.bytes!.isNotEmpty) {
    return file.bytes!;
  }

  final stream = file.readStream;
  if (stream != null) {
    final buffer = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      buffer.add(chunk);
    }
    final data = buffer.takeBytes();
    if (data.isNotEmpty) return data;
  }

  if (!kIsWeb) {
    final p = file.path;
    if (p != null && p.trim().isNotEmpty) {
      return path_io.readFileBytesFromPath(p);
    }
  }

  throw SpreadsheetFileReadException(
    'Não foi possível ler o arquivo (bytes/path/stream indisponíveis).',
  );
}

bool isCsvFileName(String? name) {
  if (name == null) return false;
  return name.toLowerCase().trim().endsWith('.csv');
}

bool isXlsxFileName(String? name) {
  if (name == null) return false;
  return name.toLowerCase().trim().endsWith('.xlsx');
}
