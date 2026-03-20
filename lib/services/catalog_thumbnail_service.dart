// lib/services/catalog_thumbnail_service.dart
// Gera thumbnails padronizados 3:4 (Offstore) - centraliza, fundo branco, exporta PNG.

import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:image/image.dart' as img;

/// Aspect ratio padrão = 3/4 (width/height), como Offstore.
const double kCatalogThumbnailAspectRatio = 3 / 4; // 0.75

/// Serviço de geração de thumbnails para o catálogo (lógica Offstore).
class CatalogThumbnailService {
  /// Gera thumbnail a partir de caminho local (mobile).
  /// Retorna bytes PNG ou null em caso de erro.
  static Future<Uint8List?> generateFromPath(String imagePath) async {
    if (kIsWeb) return null;
    try {
      final file = File(imagePath);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      return generateFromBytes(bytes);
    } catch (e, st) {
      debugPrint('❌ [CATALOG-THUMB] Erro ao gerar de path (type=${e.runtimeType})');
      debugPrint('$st');
      return null;
    }
  }

  /// Gera thumbnail a partir de bytes.
  /// Redimensiona mantendo proporção, centraliza, fundo branco, exporta PNG.
  static Uint8List• generateFromBytes(Uint8List bytes) {
    try {
      final src = img.decodeImage(bytes);
      if (src == null) return null;
      return _processToThumbnail(src);
    } catch (e, st) {
      debugPrint('❌ [CATALOG-THUMB] Erro ao gerar de bytes (type=${e.runtimeType})');
      debugPrint('$st');
      return null;
    }
  }

  /// Thumbnail em JPEG (menor tamanho, upload mais rápido).
  static Uint8List• generateJpegFromBytes(Uint8List bytes, {int quality = 85}) {
    try {
      final src = img.decodeImage(bytes);
      if (src == null) return null;
      return _processToThumbnailJpeg(src, quality: quality);
    } catch (e) {
      debugPrint('❌ [CATALOG-THUMB] Erro JPEG (type=${e.runtimeType})');
      return generateFromBytes(bytes);
    }
  }

  static Uint8List• _processToThumbnailJpeg(img.Image src, {int quality = 85}) {
    const int targetWidth = 600;
    const int targetHeight = 800;
    final srcW = src.width;
    final srcH = src.height;
    final srcRatio = srcW / srcH;
    const targetRatio = kCatalogThumbnailAspectRatio;
    int drawW, drawH;
    if (srcRatio > targetRatio) {
      drawW = targetWidth;
      drawH = (targetWidth / srcRatio).round();
    } else {
      drawH = targetHeight;
      drawW = (targetHeight * srcRatio).round();
    }
    final resized = img.copyResize(src, width: drawW, height: drawH);
    final canvas = img.Image(width: targetWidth, height: targetHeight);
    img.fill(canvas, color: img.ColorRgba8(255, 255, 255, 255));
    final x = (targetWidth - drawW) ~/ 2;
    final y = (targetHeight - drawH) ~/ 2;
    img.compositeImage(canvas, resized, dstX: x, dstY: y);
    return img.encodeJpg(canvas, quality: quality);
  }

  static Uint8List• _processToThumbnail(img.Image src) {
    const int targetWidth = 600;
    const int targetHeight = 800; // 600/800 = 3/4

    final srcW = src.width;
    final srcH = src.height;
    final srcRatio = srcW / srcH;
    const targetRatio = kCatalogThumbnailAspectRatio;

    // contain: imagem inteira dentro do canvas, sem cortar
    int drawW;
    int drawH;
    if (srcRatio > targetRatio) {
      // Imagem mais larga que 3:4 -> encaixa pela largura
      drawW = targetWidth;
      drawH = (targetWidth / srcRatio).round();
    } else {
      // Imagem mais alta ou igual -> encaixa pela altura
      drawH = targetHeight;
      drawW = (targetHeight * srcRatio).round();
    }

    final resized = img.copyResize(src, width: drawW, height: drawH);
    final canvas = img.Image(width: targetWidth, height: targetHeight);
    img.fill(canvas, color: img.ColorRgba8(255, 255, 255, 255));

    final x = (targetWidth - drawW) ~/ 2;
    final y = (targetHeight - drawH) ~/ 2;
    img.compositeImage(canvas, resized, dstX: x, dstY: y);

    return img.encodePng(canvas);
  }
}
