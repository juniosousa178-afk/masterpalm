import 'dart:io';
import 'dart:typed_data';

Future<Uint8List> readFileBytesFromPath(String path) {
  return File(path).readAsBytes();
}
