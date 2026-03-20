// lib/screens/public_catalog/widgets/catalog_gallery_view.dart
// Galeria fullscreen de imagens – extraído para reutilização no ProductCard.

import 'package:flutter/material.dart';

import '../../../widgets/smart_image.dart';

class CatalogGalleryView extends StatefulWidget {
  final List<String> imagens;
  final int index;

  const CatalogGalleryView({
    super.key,
    required this.imagens,
    required this.index,
  });

  @override
  State<CatalogGalleryView> createState() => _CatalogGalleryViewState();
}

class _CatalogGalleryViewState extends State<CatalogGalleryView> {
  late final PageController _ctrl;
  late int _idx;

  @override
  void initState() {
    super.initState();

    if (widget.imagens.isEmpty) {
      _idx = 0;
      _ctrl = PageController(initialPage: 0);
      return;
    }

    final last = widget.imagens.length - 1;
    _idx = widget.index.clamp(0, last).toInt();
    _ctrl = PageController(initialPage: _idx);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _go(int delta) {
    if (widget.imagens.isEmpty) return;
    final next = (_idx + delta).clamp(0, widget.imagens.length - 1).toInt();
    if (next == _idx) return;

    _ctrl.animateToPage(
      next,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final imgs = widget.imagens;
    if (imgs.isEmpty) {
      return const Center(
        child: Text(
          'Sem imagens para exibir.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }
    return Stack(
      children: [
        PageView.builder(
          controller: _ctrl,
          itemCount: imgs.length,
          onPageChanged: (i) => setState(() => _idx = i),
          itemBuilder: (_, i) => InteractiveViewer(
            child: Image(
              image: mpImageProvider(imgs[i]),
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, __, ___) => const Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white54,
                  size: 64,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 8,
          top: 8,
          child: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        if (imgs.length > 1) ...[
          Positioned(
            left: 8,
            top: 0,
            bottom: 0,
            child: Center(
              child: IconButton(
                iconSize: 40,
                color: Colors.white70,
                onPressed: () => _go(-1),
                icon: const Icon(Icons.chevron_left),
              ),
            ),
          ),
          Positioned(
            right: 8,
            top: 0,
            bottom: 0,
            child: Center(
              child: IconButton(
                iconSize: 40,
                color: Colors.white70,
                onPressed: () => _go(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ),
          ),
        ],
        if (imgs.length > 1)
          Positioned(
            bottom: 14,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(imgs.length, (i) {
                final active = i == _idx;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active • 10 : 7,
                  height: active • 10 : 7,
                  decoration: BoxDecoration(
                    color: active • Colors.white : Colors.white38,
                    shape: BoxShape.circle,
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }
}
