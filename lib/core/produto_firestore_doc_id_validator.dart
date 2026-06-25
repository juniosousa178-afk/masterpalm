// Validação central de storeId / docId antes de caminhos Firestore.

import '../models/produto.dart';

/// Resultado da validação de identificadores Firestore para produto.
class ProdutoFirestoreDocIdValidation {
  const ProdutoFirestoreDocIdValidation._({
    required this.ok,
    this.code,
    this.sanitizedMessage,
  });

  final bool ok;
  final String? code;
  final String? sanitizedMessage;

  static const invalidStore = 'LOJA_ID_INVALIDO';
  static const invalidProdutoId = 'PRODUTO_ID_INVALIDO';

  static ProdutoFirestoreDocIdValidation success() =>
      const ProdutoFirestoreDocIdValidation._(ok: true);

  static ProdutoFirestoreDocIdValidation failure({
    required String code,
    required String sanitizedMessage,
  }) =>
      ProdutoFirestoreDocIdValidation._(
        ok: false,
        code: code,
        sanitizedMessage: sanitizedMessage,
      );
}

/// Regras defensivas para `.doc(storeId)` e `.doc(produtoId)`.
class ProdutoFirestoreDocIdValidator {
  ProdutoFirestoreDocIdValidator._();

  static final RegExp _urlLike = RegExp(r'://', caseSensitive: false);

  static bool isProdutoIdSeguro(String? raw) {
    final id = raw?.trim() ?? '';
    if (id.isEmpty) return false;
    if (id.contains('/')) return false;
    if (_urlLike.hasMatch(id)) return false;
    if (id.contains('//')) return false;
    return true;
  }

  static bool isStoreIdSeguro(String? raw) {
    final id = raw?.trim() ?? '';
    if (id.isEmpty) return false;
    if (id.contains('/')) return false;
    if (_urlLike.hasMatch(id)) return false;
    if (id.contains('//')) return false;
    return true;
  }

  static String? resolveProdutoIdFromProduto(Produto produto) {
    final firebase = produto.idFirebase.trim();
    if (firebase.isNotEmpty) return firebase;
    final slug = produto.slug.trim();
    if (slug.isNotEmpty) return slug;
    return null;
  }

  static ProdutoFirestoreDocIdValidation validate({
    required String? storeId,
    required String? produtoId,
  }) {
    if (!isStoreIdSeguro(storeId)) {
      return ProdutoFirestoreDocIdValidation.failure(
        code: ProdutoFirestoreDocIdValidation.invalidStore,
        sanitizedMessage: 'Contexto de loja inválido para sincronização.',
      );
    }
    if (!isProdutoIdSeguro(produtoId)) {
      return ProdutoFirestoreDocIdValidation.failure(
        code: ProdutoFirestoreDocIdValidation.invalidProdutoId,
        sanitizedMessage: 'Identificador do produto inválido para sincronização.',
      );
    }
    final path =
        'lojas/${storeId!.trim()}/estoque_produtos/${produtoId!.trim()}';
    if (path.contains('//')) {
      return ProdutoFirestoreDocIdValidation.failure(
        code: ProdutoFirestoreDocIdValidation.invalidProdutoId,
        sanitizedMessage: 'Identificador do produto inválido para sincronização.',
      );
    }
    return ProdutoFirestoreDocIdValidation.success();
  }

  static ProdutoFirestoreDocIdValidation validateProduto({
    required String? storeId,
    required Produto produto,
  }) {
    final produtoId = resolveProdutoIdFromProduto(produto);
    if (produtoId == null) {
      return ProdutoFirestoreDocIdValidation.failure(
        code: ProdutoFirestoreDocIdValidation.invalidProdutoId,
        sanitizedMessage: 'Identificador do produto ausente.',
      );
    }
    return validate(storeId: storeId, produtoId: produtoId);
  }
}
