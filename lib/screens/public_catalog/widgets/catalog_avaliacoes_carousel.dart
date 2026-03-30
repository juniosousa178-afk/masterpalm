import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/catalog_avaliacao.dart';
import 'catalog_avaliacao_card.dart';

/// Carrossel de depoimentos: deslize manual ou rotação automática.
class CatalogAvaliacoesCarousel extends StatefulWidget {
  final List<CatalogAvaliacao> items;
  final Color cardColor;
  final Color textColor;
  final Color accentColor;

  const CatalogAvaliacoesCarousel({
    super.key,
    required this.items,
    required this.cardColor,
    required this.textColor,
    required this.accentColor,
  });

  @override
  State<CatalogAvaliacoesCarousel> createState() =>
      _CatalogAvaliacoesCarouselState();
}

class _CatalogAvaliacoesCarouselState extends State<CatalogAvaliacoesCarousel> {
  late PageController _pageController;
  Timer? _autoTimer;
  int _pageIndex = 0;

  static const double _viewportFraction = 0.88;
  static const int _autoAdvanceSeconds = 6;
  static const double _carouselHeight = 248;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: _viewportFraction);
    _restartAutoAdvance();
  }

  void _restartAutoAdvance() {
    _autoTimer?.cancel();
    if (widget.items.length <= 1) return;
    _autoTimer = Timer.periodic(
      const Duration(seconds: _autoAdvanceSeconds),
      (_) => _goNext(),
    );
  }

  void _goNext() {
    if (!mounted || widget.items.isEmpty) return;
    final n = widget.items.length;
    final cur = _pageController.hasClients
        ? (_pageController.page?.round() ?? _pageIndex)
        : _pageIndex;
    final next = (cur + 1) % n;
    _pageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void didUpdateWidget(covariant CatalogAvaliacoesCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) {
      if (_pageIndex >= widget.items.length) {
        _pageIndex = 0;
        if (_pageController.hasClients) {
          _pageController.jumpToPage(0);
        }
      }
      _restartAutoAdvance();
    }
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) return const SizedBox.shrink();

    final screenW = MediaQuery.sizeOf(context).width;
    final cardW = screenW * _viewportFraction - 12;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: _carouselHeight,
          child: PageView.builder(
            controller: _pageController,
            itemCount: items.length,
            onPageChanged: (i) {
              setState(() => _pageIndex = i);
              _restartAutoAdvance();
            },
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: CatalogAvaliacaoCard(
                  avaliacao: items[index],
                  cardColor: widget.cardColor,
                  textColor: widget.textColor,
                  accentColor: widget.accentColor,
                  cardWidth: cardW,
                ),
              );
            },
          ),
        ),
        if (items.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              items.length,
              (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _pageIndex ? 18 : 7,
                height: 7,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: i == _pageIndex
                      ? widget.accentColor
                      : widget.textColor.withValues(alpha: 0.22),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
