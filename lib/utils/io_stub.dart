// Stub para dart:io na compilação Web.
// order_review_screen usa: import 'dart:io' as io if (dart.library.html) '...io_stub.dart'
// No Web o código que usa io.File está em branch !kIsWeb, então este stub só precisa compilar.

/// Classe substituta de dart:io File para plataforma Web (não instanciada em runtime no fluxo atual).
class File {
  final String path;
  File(this.path);
}
