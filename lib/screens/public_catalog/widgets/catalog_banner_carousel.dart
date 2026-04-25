// lib/screens/public_catalog/widgets/catalog_banner_carousel.dart
// Carrossel de banners – extraído para reduzir rebuilds do catálogo principal.

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../catalog_helpers.dart' show isValidHttpUrl;
import '../catalog_storage_image_url_resolver.dart'
    show resolveCatalogImageUrlForDisplay;
import 'catalog_image_placeholder.dart';

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
  final Set<String> _aspectProbeInFlight = <String>{};

  @override
  void initState() {
    super.initState();
    _ctrl = PageController();
    _prefetchBannerAspectRatios();
    _startAuto();
  }

  void _prefetchBannerAspectRatios() {
    for (final raw in widget.banners) {
      _resolveBannerAspect(raw);
    }
  }

  void _resolveBannerAspect(String rawUrl) {
    _resolveBannerAspectAsync(rawUrl);
  }

  /// Mede o aspecto com a **mesma** URL de exibição do [CatalogImagePlaceholder]
  /// (Storage / token), evitando “hora carrega, hora não” e leitura errada.
  Future<void> _resolveBannerAspectAsync(String rawUrl) async {
    final url = rawUrl.trim();
    if (url.isEmpty ||
        _aspectRatioByUrl.containsKey(url) ||
        _aspectProbeInFlight.contains(url)) {
      return;
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return;
    }
    _aspectProbeInFlight.add(url);
    late final String display;
    try {
      display = await resolveCatalogImageUrlForDisplay(
        url,
        canonicalLojaId: widget.resolvedLojaId?.trim(),
      );
    } catch (_) {
      _aspectProbeInFlight.remove(url);
      return;
    }
    if (!mounted) {
      _aspectProbeInFlight.remove(url);
      return;
    }
    if (display.isEmpty || !isValidHttpUrl(display)) {
      _aspectProbeInFlight.remove(url);
      return;
    }
    final stream = NetworkImage(display).resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (ImageInfo info, bool syncCall) {
        stream.removeListener(listener);
        _aspectProbeInFlight.remove(url);
        final w = info.image.width.toDouble();
        final h = info.image.height.toDouble();
        if (!mounted || w <= 0 || h <= 0) return;
        setState(() {
          _aspectRatioByUrl[url] = w / h;
        });
      },
      onError: (_, __) {
        stream.removeListener(listener);
        _aspectProbeInFlight.remove(url);
      },
    );
    stream.addListener(listener);
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
      _prefetchBannerAspectRatios();
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

    final mq = MediaQuery.sizeOf(context);
    final w = mq.width;
    final screenH = mq.height;
    final isDesktop = w >= 1024;
    // Largura útil do slide (desktop: padding 16+16 no card; mobile: full-bleed no PageView).
    final slotW = (isDesktop ? w - 32.0 : w).clamp(120.0, 4096.0);
    const minHeight = 220.0;
    // Teto mais alto: reduz o clamp que gera “pilares” laterais (contain) em artes altas.
    final maxHeight =
        (screenH * 0.72).clamp(420.0, 800.0).toDouble();
    final currentBanner = banners[_idx.clamp(0, banners.length - 1)].trim();
    final currentAspect = _aspectRatioByUrl[currentBanner];
    // Mobile: altura fixa da config. Desktop: aspecto = slot; até medir, usa a mesma config
    // (evita salto 40% tela → proporção e sensação de “instável”).
    final effectiveHeight = !isDesktop
        ? widget.height
        : ((currentAspect != null && currentAspect > 0)
            ? (slotW / currentAspect).clamp(minHeight, maxHeight).toDouble()
            : widget.height.clamp(minHeight, maxHeight).toDouble());

    return Column(
      children: [
        SizedBox(
          height: effectiveHeight,
          child: Stack(
            children: [
              PageView.builder(
            controller: _ctrl,
            itemCount: banners.length,
            onPageChanged: (i) {
              _resolveBannerAspect(banners[i]);
              setState(() => _idx = i);
            },
            itemBuilder: (context, i) {
              final url = banners[i];
              final dpr = MediaQuery.devicePixelRatioOf(context);
              final decodeW =
                  kIsWeb ? null : (slotW * dpr).round().clamp(720, 2800);
              final decodeH =
                  kIsWeb ? null : (effectiveHeight * dpr).round().clamp(400, 2400);
              const borderRadiusDesktop = 24.0;
              const borderRadiusMobile = 20.0;
              if (isDesktop) {
                Widget page = Padding(
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
                        // Contain: arte completa (sem crop); faixas discretas no card.
                        child: SizedBox.expand(
                          child: CatalogImagePlaceholder(
                            url: url,
                            resolvedLojaId: widget.resolvedLojaId,
                            fit: BoxFit.contain,
                            alignment: Alignment.center,
                            cacheWidth: decodeW,
                            cacheHeight: decodeH,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
                if (widget.onBannerPressed != null && url.trim().isNotEmpty) {
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
              // Mobile: sem padding horizontal — mesma largura útil da faixa de conteúdo
              // (evita banner visualmente “mais estreito” que a busca e sensação de instável).
              Widget page = Padding(
                padding: const EdgeInsets.symmetric(horizontal: 0.0, vertical: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(borderRadiusMobile),
                  child: Container(
                    color: Colors.black.withOpacity(0.04),
                    // Igual ao desktop: sem `SizedBox.expand`, o placeholder (sem width/height)
                    // recebe constraints fracas e a imagem pode ficar com área 0 no mobile.
                    child: SizedBox.expand(
                      child: CatalogImagePlaceholder(
                        url: url,
                        resolvedLojaId: widget.resolvedLojaId,
                        fit: BoxFit.contain,
                        alignment: Alignment.center,
                        cacheWidth: decodeW,
                        cacheHeight: decodeH,
                      ),
                    ),
                  ),
                ),
              );
              if (widget.onBannerPressed != null && url.trim().isNotEmpty) {
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

