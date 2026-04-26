import 'dart:async';
import 'package:flutter/material.dart';

import 'public_catalog_banner_image.dart';

class CatalogBannerCarousel extends StatefulWidget {
  final List<String> banners;
  final double height;

  /// Layout premium: overlay sutil e indicadores maiores
  final bool premium;

  /// ID canónico da loja para corrigir paths do Storage (`lojas/{id}/…`).
  final String? resolvedLojaId;

  /// Toque no slide (ex.: abrir o URL da imagem ou link configurado). Web depende de abrir em nova aba.
  final void Function(int index, String imageUrl)? onBannerPressed;

  const CatalogBannerCarousel({
    super.key,
    required this.banners,
    required this.height,
    this.premium = false,
    this.resolvedLojaId,
    this.onBannerPressed,
  });

  @override
  State<CatalogBannerCarousel> createState() => _CatalogBannerCarouselState();
}

class _CatalogBannerCarouselState extends State<CatalogBannerCarousel> {
  late final PageController _ctrl;
  int _idx = 0;
  Timer? _timer;
  final Map<String, double> _aspectRatioByUrl = <String, double>{};

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
    final bannersChanged =
        oldWidget.banners.join('|') != widget.banners.join('|');
    if (bannersChanged) {
      _aspectRatioByUrl.removeWhere(
        (key, value) => !widget.banners.contains(key),
      );
      if (_idx >= widget.banners.length) {
        _idx = 0;
      }
    }
    if (oldWidget.banners.length != widget.banners.length || bannersChanged) {
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final currentBanner = banners[_idx.clamp(0, banners.length - 1)].trim();
        final widthForAspect = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final fallbackAspect = widget.height > 0
            ? (widthForAspect / widget.height).clamp(0.45, 3.2).toDouble()
            : (16 / 9);
        final currentAspect =
            (_aspectRatioByUrl[currentBanner] ?? fallbackAspect)
                .clamp(0.45, 3.2)
                .toDouble();

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: AspectRatio(
                  // A altura do carrossel deriva da largura disponível / aspecto real.
                  aspectRatio: currentAspect,
                  child: Stack(
                    children: [
                      PageView.builder(
                        controller: _ctrl,
                        itemCount: banners.length,
                        onPageChanged: (i) {
                          setState(() => _idx = i);
                        },
                        itemBuilder: (context, i) {
                          final url = banners[i].trim();
                          const borderRadiusDesktop = 24.0;
                          const borderRadiusMobile = 20.0;
                          final isDesktop =
                              MediaQuery.sizeOf(context).width >= 1024;
                          if (isDesktop) {
                            Widget page = Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(
                                      borderRadiusDesktop),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.12),
                                      blurRadius: 20,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                      borderRadiusDesktop),
                                  child: PublicCatalogBannerImage(
                                    imageUrl: url,
                                    resolvedLojaId: widget.resolvedLojaId,
                                    fallbackAspectRatio: fallbackAspect,
                                    backgroundColor:
                                        Colors.black.withOpacity(0.04),
                                    enforceAspectRatio: false,
                                    onAspectRatioResolved: (ratio) {
                                      if (!mounted) return;
                                      if (_aspectRatioByUrl[url] == ratio) {
                                        return;
                                      }
                                      setState(
                                          () => _aspectRatioByUrl[url] = ratio);
                                    },
                                  ),
                                ),
                              ),
                            );
                            if (widget.onBannerPressed != null &&
                                url.trim().isNotEmpty) {
                              page = Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () => widget.onBannerPressed!(i, url),
                                  child: page,
                                ),
                              );
                            }
                            return page;
                          }

                          Widget page = ClipRRect(
                            borderRadius:
                                BorderRadius.circular(borderRadiusMobile),
                            child: PublicCatalogBannerImage(
                              imageUrl: url,
                              resolvedLojaId: widget.resolvedLojaId,
                              fallbackAspectRatio: fallbackAspect,
                              backgroundColor: Colors.black.withOpacity(0.04),
                              enforceAspectRatio: false,
                              onAspectRatioResolved: (ratio) {
                                if (!mounted) return;
                                if (_aspectRatioByUrl[url] == ratio) return;
                                setState(() => _aspectRatioByUrl[url] = ratio);
                              },
                            ),
                          );
                          if (widget.onBannerPressed != null &&
                              url.trim().isNotEmpty) {
                            page = Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => widget.onBannerPressed!(i, url),
                                child: page,
                              ),
                            );
                          }
                          return page;
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
              ),
            ),
            if (banners.length > 1)
              Padding(
                padding: EdgeInsets.only(top: widget.premium ? 10 : 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(banners.length, (i) {
                    final active = i == _idx;
                    final dotW = (widget.premium
                        ? (active ? 14.0 : 8.0)
                        : (active ? 12.0 : 7.0));
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
      },
    );
  }
}
