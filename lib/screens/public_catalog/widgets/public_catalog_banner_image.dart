import 'package:flutter/material.dart';

import '../catalog_helpers.dart' show isValidHttpUrl;
import '../catalog_storage_image_url_resolver.dart'
    show resolveCatalogImageUrlForDisplay;

/// Banner compartilhado do catálogo público.
///
/// Regras centrais:
/// - largura sempre 100% do espaço disponível;
/// - proporção segue a imagem real (sem distorção);
/// - usa `BoxFit.contain` (sem crop/zoom);
/// - fallback estável enquanto a proporção ainda não foi medida.
class PublicCatalogBannerImage extends StatefulWidget {
  final String imageUrl;
  final String? resolvedLojaId;
  final double fallbackAspectRatio;
  final double minAspectRatio;
  final double maxAspectRatio;
  final Color backgroundColor;
  final Widget? overlay;
  final ValueChanged<double>? onAspectRatioResolved;
  final bool enforceAspectRatio;

  const PublicCatalogBannerImage({
    super.key,
    required this.imageUrl,
    this.resolvedLojaId,
    this.fallbackAspectRatio = 16 / 9,
    this.minAspectRatio = 0.45,
    this.maxAspectRatio = 3.2,
    this.backgroundColor = Colors.transparent,
    this.overlay,
    this.onAspectRatioResolved,
    this.enforceAspectRatio = true,
  });

  @override
  State<PublicCatalogBannerImage> createState() =>
      _PublicCatalogBannerImageState();
}

class _PublicCatalogBannerImageState extends State<PublicCatalogBannerImage> {
  String? _effectiveUrl;
  ImageProvider? _provider;
  ImageStream? _stream;
  ImageStreamListener? _streamListener;
  double? _resolvedAspectRatio;
  int _resolveVersion = 0;

  @override
  void initState() {
    super.initState();
    _resolveAndProbeImage();
  }

  @override
  void didUpdateWidget(covariant PublicCatalogBannerImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.resolvedLojaId != widget.resolvedLojaId) {
      _resolveAndProbeImage();
    }
  }

  @override
  void dispose() {
    _detachStream();
    super.dispose();
  }

  void _detachStream() {
    if (_stream != null && _streamListener != null) {
      _stream!.removeListener(_streamListener!);
    }
    _stream = null;
    _streamListener = null;
  }

  double _clampAspect(double value) {
    final min = widget.minAspectRatio <= 0 ? 0.1 : widget.minAspectRatio;
    final max = widget.maxAspectRatio < min ? min : widget.maxAspectRatio;
    return value.clamp(min, max).toDouble();
  }

  Future<void> _resolveAndProbeImage() async {
    final requestVersion = ++_resolveVersion;
    _detachStream();
    setState(() {
      _effectiveUrl = null;
      _provider = null;
      _resolvedAspectRatio = null;
    });

    final raw = widget.imageUrl.trim();
    if (raw.isEmpty) return;

    String effective = raw;
    if (isValidHttpUrl(raw)) {
      try {
        effective = await resolveCatalogImageUrlForDisplay(
          raw,
          canonicalLojaId: widget.resolvedLojaId?.trim(),
        );
      } catch (_) {
        effective = raw;
      }
    }
    if (!mounted || requestVersion != _resolveVersion) return;
    if (!isValidHttpUrl(effective)) return;

    final provider = NetworkImage(effective);
    final stream = provider.resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (ImageInfo info, bool syncCall) {
        final w = info.image.width.toDouble();
        final h = info.image.height.toDouble();
        if (!mounted || requestVersion != _resolveVersion || w <= 0 || h <= 0) {
          return;
        }
        final ratio = _clampAspect(w / h);
        setState(() {
          _resolvedAspectRatio = ratio;
        });
        widget.onAspectRatioResolved?.call(ratio);
      },
      onError: (_, __) {
        if (!mounted || requestVersion != _resolveVersion) return;
        setState(() {
          _resolvedAspectRatio = null;
        });
      },
    );
    stream.addListener(listener);
    setState(() {
      _effectiveUrl = effective;
      _provider = provider;
      _stream = stream;
      _streamListener = listener;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ratio =
        _clampAspect(_resolvedAspectRatio ?? widget.fallbackAspectRatio);

    Widget imageChild;
    if (_provider == null || !isValidHttpUrl(_effectiveUrl ?? '')) {
      imageChild =
          const Center(child: Icon(Icons.image_not_supported_outlined));
    } else {
      imageChild = Image(
        image: _provider!,
        width: double.infinity,
        height: double.infinity,
        // Não trocar para BoxFit.cover: cover corta/gera zoom no banner.
        fit: BoxFit.contain,
        alignment: Alignment.center,
        gaplessPlayback: true,
        isAntiAlias: true,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) =>
            const Center(child: Icon(Icons.broken_image_outlined)),
      );
    }

    final content = Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: widget.backgroundColor, child: imageChild),
        if (widget.overlay != null) widget.overlay!,
      ],
    );

    if (!widget.enforceAspectRatio) {
      return SizedBox.expand(child: content);
    }

    return AspectRatio(
      aspectRatio: ratio,
      child: content,
    );
  }
}
