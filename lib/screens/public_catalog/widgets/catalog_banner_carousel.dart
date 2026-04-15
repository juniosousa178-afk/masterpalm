// lib/screens/public_catalog/widgets/catalog_banner_carousel.dart
// Carrossel de banners – extraído para reduzir rebuilds do catálogo principal.

import 'dart:async';

import 'package:flutter/material.dart';

import 'catalog_image_placeholder.dart';

class CatalogBannerCarousel extends StatefulWidget {
  final List<String> banners;
  final double height;
  /// Layout premium: overlay sutil e indicadores maiores
  final bool premium;

  const CatalogBannerCarousel({
    super.key,
    required this.banners,
    required this.height,
    this.premium = false,
  });

  @override
  State<CatalogBannerCarousel> createState() => _CatalogBannerCarouselState();
}

class _CatalogBannerCarouselState extends State<CatalogBannerCarousel> {
  late final PageController _ctrl;
  int _idx = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _ctrl = PageController();
    _startAuto();
  }

  void _startAuto() {
    _timer?.cancel();
    if (widget.banners.length <= 1) return;
    _timer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted) return;
      final next = (_idx + 1) % widget.banners.length;
      setState(() => _idx = next);
      _ctrl.animateToPage(
        next,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void didUpdateWidget(covariant CatalogBannerCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.banners.length != widget.banners.length) {
      _startAuto();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final banners = widget.banners;
    if (banners.isEmpty) return const SizedBox.shrink();

    final w = MediaQuery.sizeOf(context).width;
    final isDesktop = w >= 1024;
    // Desktop: altura em estilo Mercado Livre (~40% da tela); mobile inalterado
    final effectiveHeight = isDesktop
        ? (MediaQuery.sizeOf(context).height * 0.40).clamp(320.0, 520.0)
        : widget.height;

    return Column(
      children: [
        SizedBox(
          height: effectiveHeight,
          child: Stack(
            children: [
              PageView.builder(
            controller: _ctrl,
            itemCount: banners.length,
            onPageChanged: (i) => setState(() => _idx = i),
            itemBuilder: (_, i) {
              final url = banners[i];
              const borderRadiusDesktop = 24.0;
              const borderRadiusMobile = 20.0;
              if (isDesktop) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(borderRadiusDesktop),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(borderRadiusDesktop),
                      child: Container(
                        color: Colors.black.withOpacity(0.04),
                        child: Center(
                          child: CatalogImagePlaceholder(
                            url: url,
                            fit: BoxFit.contain,
                            cacheWidth: 1600,
                            cacheHeight: 800,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(borderRadiusMobile),
                  child: Container(
                    color: Colors.black.withOpacity(0.04),
                    child: Center(
                      child: CatalogImagePlaceholder(
                        url: url,
                        fit: BoxFit.contain,
                        cacheWidth: 800,
                        cacheHeight: 600,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
              if (widget.premium)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 80,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.25),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (banners.length > 1)
          Padding(
            padding: EdgeInsets.only(top: widget.premium ? 10 : 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(banners.length, (i) {
                final active = i == _idx;
                final dotW = (widget.premium ? (active ? 14.0 : 8.0) : (active ? 12.0 : 7.0));
                final dotH = widget.premium ? 5.0 : 4.0;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: dotW,
                  height: dotH,
                  decoration: BoxDecoration(
                    color: active
                        ? Colors.white
                        : Colors.white.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(999),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }
}

