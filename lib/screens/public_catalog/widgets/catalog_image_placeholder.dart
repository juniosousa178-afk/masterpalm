// lib/screens/public_catalog/widgets/catalog_image_placeholder.dart
// Imagem com fallback – extraído para reutilização e testes.
// Qualidade otimizada para web e iPhone (sem distorção, sem zoom esticado).

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../../widgets/smart_image.dart';
import '../catalog_helpers.dart';

class CatalogImagePlaceholder extends StatelessWidget {
  final String url;
  final double? height;
  final double? width;
  final BorderRadius? radius;
  final BoxFit fit;
  /// Tamanho em pixels para cache. Web: 900 para qualidade; mobile: 600.
  final int? cacheWidth;
  final int? cacheHeight;

  const CatalogImagePlaceholder({
    super.key,
    required this.url,
    this.height,
    this.width,
    this.radius,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.cacheHeight,
  });

  @override
  Widget build(BuildContext context) {
    // Web: 900px para qualidade; mobile: 600px para boa nitidez no iPhone
    final cw = cacheWidth ?? (kIsWeb ? 900 : 600);
    final ch = cacheHeight ?? (kIsWeb ? 900 : 600);
    final img = (url.isEmpty || !isValidHttpUrl(url))
        ? Container(
            color: Colors.black26,
            child: const Center(
              child: Icon(
                Icons.image_not_supported_outlined,
                color: Colors.white54,
              ),
            ),
          )
        : Image(
            image: ResizeImage(
              mpImageProvider(url),
              width: cw,
              height: ch,
              policy: ResizeImagePolicy.fit,
            ),
            fit: fit,
            alignment: Alignment.center,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) => Container(
              color: Colors.black26,
              child: const Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white54,
                ),
              ),
            ),
          );

    if (radius != null) {
      return ClipRRect(
        borderRadius: radius!,
        child: SizedBox(
          height: height,
          width: width,
          child: img,
        ),
      );
    }

    return SizedBox(
      height: height,
      width: width,
      child: img,
    );
  }
}
