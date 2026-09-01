import 'dart:io' if (dart.library.html) 'spreadsheet_file_reader_stub.dart'
    as io;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

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
      return io.File(p).readAsBytes();
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
