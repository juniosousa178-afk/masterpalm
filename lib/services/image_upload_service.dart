// lib/services/image_upload_service.dart

import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// Serviço para fazer upload de imagens para o Firebase Storage
class ImageUploadService {
  static final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Faz upload de uma imagem e retorna a URL pública
  ///
  /// [imagePath]: Caminho local da imagem
  /// [folder]: Pasta no Storage (ex: 'produtos', 'clientes', 'avatares')
  /// [lojaId]: ID da loja (para organização)
  static Future<String?> uploadImage({
    required String imagePath,
    required String folder,
    required String lojaId,
  }) async {
    try {
      final file = File(imagePath);

      if (!await file.exists()) {
        debugPrint('❌ [IMAGE-UPLOAD] Arquivo não existe: $imagePath');
        return null;
      }

      // Gerar nome único para a imagem
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = path.extension(imagePath);
      final fileName = 'img_$timestamp$extension';

      // Caminho no Firebase Storage: lojas/{lojaId}/{folder}/{fileName}
      final storagePath = 'lojas/$lojaId/$folder/$fileName';

      debugPrint('📤 [IMAGE-UPLOAD] Iniciando upload: $storagePath');

      // Fazer upload
      final ref = _storage.ref().child(storagePath);
      final uploadTask = await ref.putFile(file);

      // Obter URL pública
      final downloadUrl = await uploadTask.ref.getDownloadURL();

      debugPrint('✅ [IMAGE-UPLOAD] Upload concluído: $downloadUrl');
      return downloadUrl;
    } catch (e, st) {
      debugPrint('❌ [IMAGE-UPLOAD] Erro ao fazer upload (type=${e.runtimeType})');
      debugPrint('Stack trace: $st');
      return null;
    }
  }

  /// Faz upload de bytes (ex.: thumbnail processado em PNG)
  static Future<String?> uploadImageFromBytes({
    required Uint8List bytes,
    required String folder,
    required String lojaId,
    String extension = 'png',
    String contentType = 'image/png',
  }) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'img_$timestamp.$extension';
      final storagePath = 'lojas/$lojaId/$folder/$fileName';

      debugPrint('📤 [IMAGE-UPLOAD] Upload bytes: $storagePath');

      final ref = _storage.ref().child(storagePath);
      final metadata = SettableMetadata(contentType: contentType);
      await ref.putData(bytes, metadata);

      final downloadUrl = await ref.getDownloadURL();
      debugPrint('✅ [IMAGE-UPLOAD] Upload bytes concluído: $downloadUrl');
      return downloadUrl;
    } catch (e, st) {
      debugPrint('❌ [IMAGE-UPLOAD] Erro upload bytes (type=${e.runtimeType})');
      debugPrint('$st');
      return null;
    }
  }

  /// Faz upload de múltiplas imagens
  ///
  /// Retorna lista de URLs (pode conter nulls se algum upload falhar)
  static Future<List<String>> uploadMultipleImages({
    required List<String> imagePaths,
    required String folder,
    required String lojaId,
  }) async {
    final urls = <String>[];

    for (final imagePath in imagePaths) {
      final url = await uploadImage(
        imagePath: imagePath,
        folder: folder,
        lojaId: lojaId,
      );

      if (url != null) {
        urls.add(url);
      } else {
        debugPrint('⚠️ [IMAGE-UPLOAD] Falha no upload de: $imagePath');
      }
    }

    debugPrint('📊 [IMAGE-UPLOAD] ${urls.length}/${imagePaths.length} imagens enviadas');
    return urls;
  }

  /// Deleta uma imagem do Firebase Storage pela URL
  static Future<bool> deleteImage(String imageUrl) async {
    try {
      if (imageUrl.isEmpty || !imageUrl.contains('firebase')) {
        debugPrint('⚠️ [IMAGE-UPLOAD] URL inválida ou não é do Firebase: $imageUrl');
        return false;
      }

      final ref = _storage.refFromURL(imageUrl);
      await ref.delete();

      debugPrint('🗑️ [IMAGE-UPLOAD] Imagem deletada: $imageUrl');
      return true;
    } catch (e) {
      debugPrint('❌ [IMAGE-UPLOAD] Erro ao deletar imagem (type=${e.runtimeType})');
      return false;
    }
  }

  /// Apaga no Storage somente se a URL for do Firebase **e** o objeto estiver em `lojas/{lojaId}/...`.
  /// URLs externas ou de outra loja não são removidas.
  static Future<bool> deleteImageIfManagedForLoja(String imageUrl, String lojaId) async {
    if (imageUrl.isEmpty || lojaId.isEmpty) return false;
    if (imageUrl.startsWith('data:') || imageUrl.startsWith('blob:')) return false;
    if (!isFirebaseUrl(imageUrl)) {
      debugPrint('⚠️ [IMAGE-UPLOAD] skip delete (não é URL Firebase gerenciada): ${imageUrl.length > 80 ? "${imageUrl.substring(0, 80)}..." : imageUrl}');
      return false;
    }
    try {
      final ref = _storage.refFromURL(imageUrl);
      final full = ref.fullPath;
      final prefix = 'lojas/$lojaId/';
      if (!full.startsWith(prefix)) {
        debugPrint('⚠️ [IMAGE-UPLOAD] skip delete (path fora da loja): $full');
        return false;
      }
      await ref.delete();
      debugPrint('🗑️ [IMAGE-UPLOAD] Removido objeto gerenciado: $full');
      return true;
    } catch (e) {
      debugPrint('❌ [IMAGE-UPLOAD] Falha delete seguro (type=${e.runtimeType}) url=${imageUrl.length > 60 ? "${imageUrl.substring(0, 60)}..." : imageUrl}');
      return false;
    }
  }

  /// Deleta múltiplas imagens
  static Future<void> deleteMultipleImages(List<String> imageUrls) async {
    for (final url in imageUrls) {
      await deleteImage(url);
    }
  }

  /// Verifica se uma string é uma URL do Firebase Storage
  static bool isFirebaseUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    return url.contains('firebasestorage.googleapis.com') ||
           url.contains('firebase');
  }

  /// Verifica se é um caminho local de arquivo
  static bool isLocalPath(String? path) {
    if (path == null || path.isEmpty) return false;
    return !isFirebaseUrl(path) &&
           (path.startsWith('/') || path.contains('\\') || path.startsWith('file://'));
  }
}
