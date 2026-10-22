import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../catalog/public_order_item_image.dart';

/// Foto do item na página pública do pedido. Sem foto, carregando ou com erro
/// (404/403/rede/imagem inválida) mostra o ícone genérico, no mesmo tamanho.
class PublicOrderItemThumbnail extends StatelessWidget {
  const PublicOrderItemThumbnail({
    super.key,
    required this.imageUrl,
    this.size = 72,
    this.imageProviderFor,
  });

  final String? imageUrl;
  final double size;

  /// Testes: substitui o [NetworkImage].
  final ImageProvider Function(String url)? imageProviderFor;

  @override
  Widget build(BuildContext context) {
    final url = publicOrderItemImageUrl(imageUrl);
    final placeholder = _placeholder();
    Widget child = placeholder;
    if (url != null) {
      final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
      // Web: decode sem resize, como no catálogo (falhas com Storage).
      final decodeSize = kIsWeb ? null : (size * dpr).round();
      final provider = imageProviderFor?.call(url) ?? NetworkImage(url);
      child = Image(
        key: ValueKey(url),
        image: decodeSize == null
            ? provider
            : ResizeImage.resizeIfNeeded(decodeSize, null, provider),
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        semanticLabel: 'Foto do produto',
        frameBuilder: (_, image, frame, wasSynchronouslyLoaded) =>
            wasSynchronouslyLoaded || frame != null ? image : placeholder,
        errorBuilder: (_, __, ___) => placeholder,
      );
    }
    return SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: child,
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      key: const ValueKey('public-order-item-placeholder'),
      width: size,
      height: size,
      color: Colors.grey[300],
      alignment: Alignment.center,
      child: Icon(Icons.shopping_bag, color: Colors.grey, size: size * 0.45),
    );
  }
}
