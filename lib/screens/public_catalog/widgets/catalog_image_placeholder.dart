// lib/screens/public_catalog/widgets/catalog_image_placeholder.dart
// Imagem com fallback – extraído para reutilização e testes.
// Qualidade otimizada para web e iPhone (sem distorção, sem zoom esticado).
// Web: Image.network + errorBuilder (evita exceção não tratada com ResizeImage/404).

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../catalog_helpers.dart';
import '../catalog_storage_image_url_resolver.dart';

class CatalogImagePlaceholder extends StatefulWidget {
  final String url;
  final double? height;
  final double? width;
  final BorderRadius? radius;
  final BoxFit fit;
  /// Alinhamento da imagem quando não preenche o espaço (contain/fitWidth/fitHeight).
  final AlignmentGeometry alignment;
  /// Tamanho em pixels para cache. Web: 900 para qualidade; mobile: 600.
  final int? cacheWidth;
  final int? cacheHeight;
  /// ID canónico da loja (Firestore). Quando o URL do Storage usa outro segmento em `lojas/{id}/`,
  /// tenta-se resolver o download URL correto antes de carregar.
  final String? resolvedLojaId;

  const CatalogImagePlaceholder({
    super.key,
    required this.url,
    this.height,
    this.width,
    this.radius,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.cacheWidth,
    this.cacheHeight,
    this.resolvedLojaId,
  });

  @override
  State<CatalogImagePlaceholder> createState() => _CatalogImagePlaceholderState();
}

class _CatalogImagePlaceholderState extends State<CatalogImagePlaceholder> {
  late Future<String> _effectiveUrlFuture;

  @override
  void initState() {
    super.initState();
    _effectiveUrlFuture = _computeEffectiveUrlFuture();
  }

  @override
  void didUpdateWidget(covariant CatalogImagePlaceholder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.resolvedLojaId != widget.resolvedLojaId) {
      _effectiveUrlFuture = _computeEffectiveUrlFuture();
    }
  }

  Future<String> _computeEffectiveUrlFuture() {
    final url = widget.url;
    if (!isValidHttpUrl(url)) {
      return Future.value(url);
    }
    return resolveCatalogImageUrlForDisplay(
      url,
      canonicalLojaId: widget.resolvedLojaId?.trim(),
    );
  }

  static Widget _brokenPlaceholder() => Container(
        color: Colors.black26,
        child: const Center(
          child: Icon(
            Icons.broken_image_outlined,
            color: Colors.white54,
          ),
        ),
      );

  static Widget _unsupportedPlaceholder() => Container(
        color: Colors.black26,
        child: const Center(
          child: Icon(
            Icons.image_not_supported_outlined,
            color: Colors.white54,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    // Web: sem resize no decode (evita artefatos / falhas com Storage).
    // Nativo: se só [cacheWidth] ou só [cacheHeight] for passado, preserva proporção
    // da arte (evita “zoom” com par 800×600 em banner largo).
    int? cw;
    int? ch;
    if (!kIsWeb) {
      cw = widget.cacheWidth;
      ch = widget.cacheHeight;
      if (cw == null && ch == null) {
        cw = 600;
        ch = 600;
      }
    }

    Widget core(Future<String> future) {
      return FutureBuilder<String>(
        future: future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return Container(color: Colors.black26);
          }
          final effective = snap.data ?? '';
          if (effective.isEmpty || !isValidHttpUrl(effective)) {
            return _unsupportedPlaceholder();
          }
          return Image.network(
            effective,
            fit: widget.fit,
            alignment: widget.alignment,
            cacheWidth: cw,
            cacheHeight: ch,
            gaplessPlayback: true,
            filterQuality:
                kIsWeb ? FilterQuality.medium : FilterQuality.high,
            errorBuilder: (_, __, ___) => _brokenPlaceholder(),
          );
        },
      );
    }

    final img = core(_effectiveUrlFuture);

    if (widget.radius != null) {
      return ClipRRect(
        borderRadius: widget.radius!,
        child: SizedBox(
          height: widget.height,
          width: widget.width,
          child: img,
        ),
      );
    }

    return SizedBox(
      height: widget.height,
      width: widget.width,
      child: img,
    );
  }
}
