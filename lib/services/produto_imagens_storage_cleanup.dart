// lib/services/produto_imagens_storage_cleanup.dart
// Remove imagens órfãs no Firebase Storage quando seguro (prefixo lojas/{lojaId}/).

import '../models/produto.dart';
import 'image_upload_service.dart';

/// Limpeza de imagens de produto no Storage — apenas URLs gerenciadas pela loja.
class ProdutoImagensStorageCleanup {
  ProdutoImagensStorageCleanup._();

  /// URLs que estavam em [anteriores] e não estão mais em [atuais] — apaga no Storage se seguro.
  static Future<void> apagarUrlsRemovidasGerenciadas({
    required List<String> anteriores,
    required List<String> atuais,
    required String lojaId,
  }) async {
    if (lojaId.isEmpty) return;
    final atual = atuais.toSet();
    for (final url in anteriores) {
      if (url.isEmpty || atual.contains(url)) continue;
      await ImageUploadService.deleteImageIfManagedForLoja(url, lojaId);
    }
  }

  /// Todas as imagens listadas no produto (ex.: exclusão definitiva).
  static Future<void> apagarTodasImagensGerenciadasDoProduto(
    Produto produto,
    String lojaId,
  ) async {
    if (produto.imagens.isEmpty) return;
    await apagarUrlsRemovidasGerenciadas(
      anteriores: List<String>.from(produto.imagens),
      atuais: const [],
      lojaId: lojaId,
    );
  }
}
