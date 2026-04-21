// lib/widgets/smart_image.dart
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Carrega imagem de URL ou de caminho local, com fallback e bordas arredondadas.
class SmartImage extends StatelessWidget {
  final String src;
  final BoxFit fit;
  final BorderRadius? radius;

  const SmartImage({
    super.key,
    required this.src,
    this.fit = BoxFit.cover,
    this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final Widget child;

    // blob: no Web não pode ser carregado se for de outra origem (ex.: localhost vs app.mastepalm.com.br).
    if (src.startsWith('blob:') && kIsWeb) {
      child = const Center(child: Icon(Icons.broken_image));
    } else if (src.startsWith('http')) {
      child = Image.network(
        src,
        fit: fit,
        width: double.infinity,
        gaplessPlayback: true,
        filterQuality: kIsWeb ? FilterQuality.medium : FilterQuality.high,
        errorBuilder: (_, __, ___) =>
            const Center(child: Icon(Icons.broken_image)),
      );
    } else if (!kIsWeb) {
      child = Image.file(
        File(src),
        fit: fit,
        width: double.infinity,
        gaplessPlayback: true,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) =>
            const Center(child: Icon(Icons.broken_image)),
      );
    } else {
      child = const Center(child: Icon(Icons.broken_image));
    }

    if (radius == null) return child;
    return ClipRRect(borderRadius: radius!, child: child);
  }
  
}
// =======================================================================
// FUNÇÃO UTILIZADA PELO CATÁLOGO — mpImageProvider
// (mantida por compatibilidade com versões anteriores)
// =======================================================================

ImageProvider mpImageProvider(String url) {
  if (url.trim().isEmpty) {
    return const AssetImage('assets/placeholder.png');
  }

  // URL http/https
  if (url.startsWith('http://') || url.startsWith('https://')) {
    return NetworkImage(url);
  }

  // Asset interno
  if (!url.contains('/') && !url.contains('\\')) {
    return AssetImage(url);
  }

  // Web não consegue ler caminho local
  if (kIsWeb) {
    return const AssetImage('assets/placeholder.png');
  }

  // Caminho local (Android/iOS)
  return FileImage(
    File(url),
  );
}
