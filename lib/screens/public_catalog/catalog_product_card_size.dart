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
  static double standardAspectRatio(String size) {
    switch (normalize(size)) {
      case small:
        return 0.42;
      case large:
        return 0.34;
      case medium:
      default:
        return 0.38;
    }
  }

  /// childAspectRatio para grid minimalista (width/height).
  static double minimalAspectRatio(String size) {
    switch (normalize(size)) {
      case small:
        return 0.56;
      case large:
        return 0.47;
      case medium:
      default:
        return 0.52;
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
}

