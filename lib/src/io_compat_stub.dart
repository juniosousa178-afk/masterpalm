/// No Web não existe dart:io File.
/// Este stub fornece classes/funções vazias para permitir compilação web.
library;

class File {
  File(String path);

  Future<bool> exists() async => false;
  Future<void> delete() async {}
}

Future<String> getAppDocsDirPath() async {
  return '/web/hive'; // Web não tem diretório real
}

/// Wrapper para criar File - lança erro no web
dynamic createFile(String path) {
  throw UnsupportedError('File não é suportado no Web. Use Uint8List.');
}

/// No Web não existe dart:io File.
/// Este tipo só serve para compilar; no Web você usará enqueueBytes().
class PlatformFile {
  const PlatformFile();
}

/// No Web, não dá pra criar File por path local.
PlatformFile fileFromPath(String path) {
  throw UnsupportedError('fileFromPath() não é suportado no Web.');
}

/// No Web, caminho local não existe.
bool fileExistsAtPath(String path) => false;
