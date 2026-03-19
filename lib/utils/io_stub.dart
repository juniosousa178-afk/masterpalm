// Stub para dart:io na compilação Web.
// Arquivos usam: import 'dart:io' as io if (dart.library.html) 'package:master_palm/utils/io_stub.dart';
// No Web o código que usa io.File/Directory fica sempre protegido por !kIsWeb,
// então estas implementações só precisam compilar com a mesma API básica.

import 'dart:typed_data';

/// Classe substituta de dart:io File para plataforma Web.
class File {
  final String path;
  File(this.path);

  /// Mantém assinatura compatível com File.existsSync() de dart:io.
  bool existsSync() => false;

  /// Mantém assinatura compatível com File.readAsBytes().
  Future<Uint8List> readAsBytes() async => Uint8List(0);

  /// Mantém assinatura compatível com File.writeAsBytes().
  Future<void> writeAsBytes(List<int> bytes, {bool flush = false}) async {}
}

/// Classe substituta de dart:io Directory para plataforma Web.
class Directory {
  final String path;
  Directory(this.path);

  /// Simula o diretório temporário do sistema.
  static Directory get systemTemp => Directory('/tmp');

  /// Assinatura compatível com Directory.exists().
  Future<bool> exists() async => false;

  /// Assinatura compatível com Directory.create().
  Future<Directory> create({bool recursive = false}) async => this;
}
