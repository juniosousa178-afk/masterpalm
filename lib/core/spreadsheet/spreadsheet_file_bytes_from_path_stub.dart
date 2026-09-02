import 'dart:typed_data';

Future<Uint8List> readFileBytesFromPath(String path) {
  throw UnsupportedError(
    'Leitura por path não é suportada na Web; use PlatformFile.bytes.',
  );
}
