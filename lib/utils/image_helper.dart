// lib/utils/image_helper.dart
import 'dart:io' as io;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Retorna o widget de imagem correto para a plataforma.
/// - Se o path começa com http/https → Image.network
/// - Se estamos no Web → tenta Image.network (ignora paths locais)
/// - Se estamos no Mobile → Image.file
Widget buildPlatformImage(
  String path, {
  BoxFit fit = BoxFit.cover,
  double? width,
  double? height,
  int? cacheWidth,
  int? cacheHeight,
  Widget Function(BuildContext, Object, StackTrace?)? errorBuilder,
}) {
  final defaultErrorBuilder = errorBuilder ??
      (_, __, ___) => Container(
            color: Colors.grey[200],
            child: const Center(
              child: Icon(Icons.broken_image, size: 40, color: Colors.grey),
            ),
          );

  // No Web, blob: de outra origem não pode ser carregado (cross-origin).
  if (kIsWeb && path.startsWith('blob:')) {
    return defaultErrorBuilder(
      WidgetsBinding.instance.rootElement!,
      'Blob URL from other origin',
      null,
    );
  }

  // URL de rede
  if (path.startsWith('http://') || path.startsWith('https://')) {
    return Image.network(
      path,
      fit: fit,
      width: width,
      height: height,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      errorBuilder: defaultErrorBuilder,
    );
  }

  // No Web, paths locais não funcionam
  if (kIsWeb) {
    return defaultErrorBuilder(
      WidgetsBinding.instance.rootElement!,
      'Local path not supported on web',
      null,
    );
  }

  // Mobile: arquivo local
  return Image.file(
    io.File(path),
    fit: fit,
    width: width,
    height: height,
    errorBuilder: defaultErrorBuilder,
  );
}

/// Retorna o ImageProvider correto para a plataforma.
ImageProvider? buildPlatformImageProvider(String? path) {
  if (path == null || path.isEmpty) return null;

  // blob: em outra origem (ex.: app em localhost, blob de app.mastepalm.com.br) não carrega no Web.
  if (kIsWeb && path.startsWith('blob:')) return null;

  if (path.startsWith('http://') || path.startsWith('https://')) {
    return NetworkImage(path);
  }

  if (kIsWeb) return null;

  return FileImage(io.File(path));
}

/// Verifica se um arquivo de imagem existe (no web, retorna false para paths locais)
bool imageFileExists(String path) {
  if (path.startsWith('http://') || path.startsWith('https://')) return true;
  if (kIsWeb) return false;
  return io.File(path).existsSync();
}
