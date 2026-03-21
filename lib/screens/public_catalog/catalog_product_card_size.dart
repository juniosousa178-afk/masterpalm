// lib/screens/public_catalog/catalog_product_card_size.dart
// Escalas visuais para tamanho de card/foto no catálogo (UI only).

class CatalogProductCardSize {
  static const String small = 'small';
  static const String medium = 'medium';
  static const String large = 'large';

  static String normalize(dynamic raw) {
    final v = (raw ?? '').toString().trim().toLowerCase();
    if (v == small || v == medium || v == large) return v;
    return medium;
  }

  /// childAspectRatio para grid padrão (width/height).
  /// Spread maior = diferença mais clara na altura da célula (foto + texto).
  static double standardAspectRatio(String size) {
    switch (normalize(size)) {
      case small:
        return 0.52;
      case large:
        return 0.36;
      case medium:
      default:
        return 0.44;
    }
  }

  /// childAspectRatio para grid minimalista (crossAxis/mainAxis = width/height).
  /// Valores um pouco menores = células mais altas, evitando cortar a linha de botões.
  static double minimalAspectRatio(String size) {
    switch (normalize(size)) {
      case small:
        return 0.55;
      case large:
        return 0.40;
      case medium:
      default:
        return 0.46;
    }
  }

  static double bestSellerCardWidth(
    String size, {
    required double screenWidth,
  }) {
    final is360 = screenWidth <= 360;
    final is390 = screenWidth > 360 && screenWidth <= 390;
    switch (normalize(size)) {
      case small:
        if (is360) return 108.0;
        if (is390) return 110.0;
        return screenWidth <= 420 ? 112.0 : 122.0;
      case large:
        if (is360) return 122.0;
        if (is390) return 124.0;
        return screenWidth <= 420 ? 128.0 : 138.0;
      case medium:
      default:
        if (is360) return 114.0;
        if (is390) return 116.0;
        return screenWidth <= 420 ? 120.0 : 128.0;
    }
  }

  static double bestSellerListHeight(
    String size, {
    required double screenWidth,
  }) {
    final is360 = screenWidth <= 360;
    final is390 = screenWidth > 360 && screenWidth <= 390;
    switch (normalize(size)) {
      case small:
        if (is360) return 176.0;
        if (is390) return 178.0;
        return screenWidth <= 420 ? 182.0 : 192.0;
      case large:
        if (is360) return 198.0;
        if (is390) return 202.0;
        return screenWidth <= 420 ? 206.0 : 216.0;
      case medium:
      default:
        if (is360) return 186.0;
        if (is390) return 188.0;
        return screenWidth <= 420 ? 192.0 : 198.0;
    }
  }

  /// Cache de imagem para cards do grid principal.
  /// Escala por tamanho visual para evitar blur em cards maiores.
  static ({int width, int height}) gridImageCache({
    required String size,
    required bool minimalLayout,
    required bool isWeb,
  }) {
    final s = normalize(size);
    if (minimalLayout) {
      switch (s) {
        case small:
          return (
            width: isWeb ? 760 : 680,
            height: isWeb ? 1020 : 920,
          );
        case large:
          return (
            width: isWeb ? 1120 : 980,
            height: isWeb ? 1500 : 1320,
          );
        case medium:
        default:
          return (
            width: isWeb ? 920 : 820,
            height: isWeb ? 1240 : 1100,
          );
      }
    }

    switch (s) {
      case small:
        return (
          width: isWeb ? 680 : 620,
          height: isWeb ? 920 : 840,
        );
      case large:
        return (
          width: isWeb ? 980 : 860,
          height: isWeb ? 1320 : 1160,
        );
      case medium:
      default:
        return (
          width: isWeb ? 820 : 740,
          height: isWeb ? 1100 : 980,
        );
    }
  }

  /// Cache para cards horizontais (recentes/destaques compactos).
  static ({int width, int height}) horizontalCardImageCache({
    required String size,
    required bool isWeb,
  }) {
    switch (normalize(size)) {
      case small:
        return (
          width: isWeb ? 560 : 500,
          height: isWeb ? 760 : 680,
        );
      case large:
        return (
          width: isWeb ? 820 : 720,
          height: isWeb ? 1120 : 980,
        );
      case medium:
      default:
        return (
          width: isWeb ? 680 : 600,
          height: isWeb ? 920 : 820,
        );
    }
  }
}

