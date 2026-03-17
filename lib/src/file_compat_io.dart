import 'dart:io';

typedef PlatformFile = File;

/// Cria um "File" a partir do path (somente IO: Android/Windows/iOS)
PlatformFile fileFromPath(String path) => File(path);

/// Checa existência (somente IO)
bool fileExistsAtPath(String path) => File(path).existsSync();
