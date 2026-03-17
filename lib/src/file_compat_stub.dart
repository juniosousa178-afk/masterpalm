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
