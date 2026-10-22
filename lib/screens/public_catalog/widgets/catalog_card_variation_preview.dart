// lib/screens/public_catalog/widgets/catalog_card_variation_preview.dart
// Faixa discreta "Tamanhos [12] [14] …" no card do catálogo. Somente exibição:
// não é botão, não seleciona variação e não altera o carrinho.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../catalog_card_variation_preview_data.dart';

class CatalogCardVariationPreview extends StatelessWidget {
  const CatalogCardVariationPreview({
    super.key,
    required this.data,
    required this.textColor,
  });

  final CatalogCardVariationPreviewData data;
  final Color textColor;

  static const double topGap = 5;
  static const double labelHeight = 14;
  static const double labelGap = 3;
  static const double chipHeight = 26;

  /// Altura fixa da faixa: o card reserva exatamente este espaço.
  static const double height = topGap + labelHeight + labelGap + chipHeight;

  static const double chipSpacing = 4;
  static const double chipPaddingH = 8;
  static const double chipMaxWidth = 112;
  static const double chipFontSize = 11;
  static const double labelFontSize = 10.5;

  /// Quantos chips cabem numa linha (máx. [CatalogCardVariationPreviewData.maxVisibleChips]),
  /// reservando espaço para o chip "+N" quando sobram itens.
  static int visibleChipCount({
    required List<double> chipWidths,
    required double Function(int hidden) overflowChipWidth,
    required double maxWidth,
    double spacing = chipSpacing,
    int maxVisible = CatalogCardVariationPreviewData.maxVisibleChips,
  }) {
    final total = chipWidths.length;
    for (var k = math.min(maxVisible, total); k >= 1; k--) {
      var w = 0.0;
      for (var i = 0; i < k; i++) {
        w += chipWidths[i];
      }
      w += spacing * (k - 1);
      if (k < total) w += spacing + overflowChipWidth(total - k);
      if (w <= maxWidth) return k;
    }
    return total == 0 ? 0 : 1;
  }

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    // A medição dos chips precisa da mesma fonte que o Text herda do tema.
    final chipTextStyle = DefaultTextStyle.of(context).style.merge(TextStyle(
          fontSize: chipFontSize,
          fontWeight: FontWeight.w500,
          height: 1.1,
          color: textColor.withValues(alpha: 0.82),
        ));
    final overflowTextStyle =
        chipTextStyle.copyWith(color: textColor.withValues(alpha: 0.6));
    final borderColor = textColor.withValues(alpha: 0.2);

    return Semantics(
      container: true,
      label: data.semanticsLabel,
      child: ExcludeSemantics(
        child: SizedBox(
          height: height,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: topGap),
              SizedBox(
                height: labelHeight,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    data.title,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: labelFontSize,
                      fontWeight: FontWeight.w500,
                      height: 1.1,
                      color: textColor.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: labelGap),
              SizedBox(
                height: chipHeight,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final maxWidth = constraints.maxWidth.isFinite
                        ? math.max(0.0, constraints.maxWidth - 0.5)
                        : 320.0;
                    double measure(String text, TextStyle style) {
                      final tp = TextPainter(
                        text: TextSpan(text: text, style: style),
                        textDirection: TextDirection.ltr,
                        textScaler: textScaler,
                        maxLines: 1,
                      )..layout();
                      final w = tp.width;
                      tp.dispose();
                      return (w + chipPaddingH * 2 + 2).ceilToDouble();
                    }

                    final cap = math.min(chipMaxWidth, maxWidth);
                    final widths = [
                      for (final l in data.labels)
                        math.min(measure(l, chipTextStyle), cap),
                    ];
                    double plusWidth(int hidden) =>
                        measure('+$hidden', overflowTextStyle);
                    final visible = visibleChipCount(
                      chipWidths: widths,
                      overflowChipWidth: plusWidth,
                      maxWidth: maxWidth,
                    );
                    final hidden = data.labels.length - visible;
                    final children = <Widget>[];
                    for (var i = 0; i < visible; i++) {
                      var w = widths[i];
                      if (i == 0 && hidden > 0 && visible == 1) {
                        w = math.max(
                          0.0,
                          math.min(
                              w, maxWidth - chipSpacing - plusWidth(hidden)),
                        );
                      }
                      if (i > 0) {
                        children.add(const SizedBox(width: chipSpacing));
                      }
                      children.add(
                          _chip(data.labels[i], w, chipTextStyle, borderColor));
                    }
                    if (hidden > 0) {
                      children.add(const SizedBox(width: chipSpacing));
                      children.add(_chip(
                        '+$hidden',
                        plusWidth(hidden),
                        overflowTextStyle,
                        borderColor,
                      ));
                    }
                    return ClipRect(
                      child: OverflowBox(
                        alignment: Alignment.centerLeft,
                        minWidth: 0,
                        maxWidth: double.infinity,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: children,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String text, double width, TextStyle style, Color borderColor) {
    return Container(
      width: width,
      height: chipHeight,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: chipPaddingH),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: style,
      ),
    );
  }
}
