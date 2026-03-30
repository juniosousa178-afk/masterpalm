// Ponto único para entrada de fotos nas avaliações do catálogo:
// URLs no texto (vírgulas) e/ou importação da galeria com upload para Storage.

import 'package:image_picker/image_picker.dart';

import 'image_upload_service.dart';

class CatalogAvaliacaoFotosInput {
  CatalogAvaliacaoFotosInput._();

  static const int maxFotosPorAvaliacao = 8;
  static const int maxBytesPorFoto = 4 * 1024 * 1024;
  static const String _storageFolder = 'catalog_avaliacoes_fotos';

  /// Parse do campo de texto do formulário (vírgulas).
  static List<String> parseUrlsFromFormText(String raw) {
    if (raw.trim().isEmpty) return [];
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// [pickedCount] = quantas imagens o usuario escolheu (0 = cancelou / nada).
  /// [urls] = uploads bem-sucedidos.
  static Future<({List<String> urls, int pickedCount})> pickGalleryAndUploadUrls({
    required String lojaId,
    required int remainingSlots,
  }) async {
    final lid = lojaId.trim();
    if (lid.isEmpty || remainingSlots < 1) {
      return (urls: <String>[], pickedCount: 0);
    }

    final picker = ImagePicker();
    List<XFile> files;
    try {
      files = await picker.pickMultiImage(imageQuality: 82);
    } catch (_) {
      return (urls: <String>[], pickedCount: 0);
    }
    if (files.isEmpty) return (urls: <String>[], pickedCount: 0);

    final capped = files.take(remainingSlots).toList();
    final urls = <String>[];
    for (final x in capped) {
      final bytes = await x.readAsBytes();
      if (bytes.length > maxBytesPorFoto) continue;
      final meta = _mimeFromXFile(x);
      final url = await ImageUploadService.uploadImageFromBytes(
        bytes: bytes,
        folder: _storageFolder,
        lojaId: lid,
        extension: meta.$1,
        contentType: meta.$2,
      );
      if (url != null) urls.add(url);
    }
    return (urls: urls, pickedCount: capped.length);
  }

  static (String, String) _mimeFromXFile(XFile x) {
    final mt = x.mimeType?.toLowerCase() ?? '';
    if (mt.contains('png')) return ('png', 'image/png');
    if (mt.contains('webp')) return ('webp', 'image/webp');
    if (mt.contains('gif')) return ('gif', 'image/gif');
    final name = x.name.toLowerCase();
    if (name.endsWith('.png')) return ('png', 'image/png');
    if (name.endsWith('.webp')) return ('webp', 'image/webp');
    if (name.endsWith('.gif')) return ('gif', 'image/gif');
    return ('jpg', 'image/jpeg');
  }
}
