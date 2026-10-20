import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'category_tree.dart';

class CategoryException implements Exception {
  const CategoryException(this.code, this.message);

  final String code;
  final String message;

  static const depthLimit = 'CATEGORY_DEPTH_LIMIT';
  static const hasChildren = 'CATEGORY_HAS_CHILDREN';
  static const hasProducts = 'CATEGORY_HAS_PRODUCTS';
  static const notAvailable = 'CATEGORY_NOT_AVAILABLE';

  @override
  String toString() => message;
}

/// Leitura da árvore (uma consulta por loja) e escrita só via `categoryCommand`.
class CategoryService {
  CategoryService._();

  @visibleForTesting
  static Future<List<Map<String, dynamic>>> Function(String lojaId)? debugLoadDocs;

  @visibleForTesting
  static Future<Map<String, dynamic>> Function(Map<String, dynamic> data)? debugTransport;

  static final Map<String, List<Map<String, dynamic>>> _docsCache = {};

  static void invalidate(String lojaId) => _docsCache.remove(lojaId.trim());

  @visibleForTesting
  static void debugReset() {
    _docsCache.clear();
    debugLoadDocs = null;
    debugTransport = null;
  }

  /// Todos os documentos de categoria da loja numa única consulta (montagem em memória).
  static Future<List<Map<String, dynamic>>> loadDocs(String lojaId,
      {bool refresh = false}) async {
    final loja = lojaId.trim();
    if (loja.isEmpty) return const [];
    if (!refresh && _docsCache.containsKey(loja)) return _docsCache[loja]!;
    final List<Map<String, dynamic>> docs;
    if (debugLoadDocs != null) {
      docs = await debugLoadDocs!(loja);
    } else {
      final snap = await FirebaseFirestore.instance
          .collection('lojas')
          .doc(loja)
          .collection('categorias')
          .get();
      docs = [
        for (final d in snap.docs) {...d.data(), 'id': d.id},
      ];
    }
    _docsCache[loja] = docs;
    return docs;
  }

  static Future<CategoryTree> loadTree(
    String lojaId, {
    Iterable<CategoryProductRef> products = const [],
    bool refresh = false,
  }) async {
    final docs = await loadDocs(lojaId, refresh: refresh);
    return CategoryTree.build(lojaId: lojaId.trim(), docs: docs, products: products);
  }

  static Future<Map<String, dynamic>> _command(
    String lojaId,
    String operation,
    Map<String, dynamic> payload,
  ) async {
    final data = <String, dynamic>{
      'protocolVersion': 1,
      'lojaId': lojaId.trim(),
      'operation': operation,
      'operationId': 'cat_${operation}_${const Uuid().v4()}',
      'payload': payload,
    };
    try {
      final res = debugTransport != null
          ? await debugTransport!(data)
          : Map<String, dynamic>.from((await FirebaseFunctions.instanceFor(
                      region: 'southamerica-east1')
                  .httpsCallable('categoryCommand')
                  .call<Map<String, dynamic>>(data))
              .data);
      invalidate(lojaId);
      return res;
    } on FirebaseFunctionsException catch (e) {
      final details = e.details;
      final code = details is Map ? '${details['categoryCode'] ?? ''}' : '';
      if (e.code == 'not-found' && code.isEmpty) {
        throw const CategoryException(CategoryException.notAvailable,
            'Categorias em níveis ainda não estão disponíveis nesta versão do servidor.');
      }
      throw CategoryException(
        code.isEmpty ? e.code : code,
        (e.message ?? '').trim().isEmpty
            ? 'Não foi possível salvar a categoria.'
            : e.message!,
      );
    }
  }

  static Future<Map<String, dynamic>> create({
    required String lojaId,
    required CategoryTree tree,
    required CategoryNode? parent,
    required String nome,
  }) async {
    final blocked = tree.validateNewChild(parent);
    if (blocked != null) {
      throw CategoryException(CategoryException.depthLimit, blocked);
    }
    return _command(lojaId, 'create', {
      'parent': parent?.toRef(),
      'nome': cleanCategoryName(nome),
    });
  }

  static Future<Map<String, dynamic>> rename({
    required String lojaId,
    required CategoryNode node,
    required String nome,
  }) =>
      _command(lojaId, 'rename', {
        'target': node.toRef(),
        'nome': cleanCategoryName(nome),
      });

  static Future<Map<String, dynamic>> archive({
    required String lojaId,
    required CategoryTree tree,
    required CategoryNode node,
  }) async {
    final blocked = tree.archiveBlocker(node);
    if (blocked != null) {
      throw CategoryException(
        blocked == kCategoryHasChildrenMessage
            ? CategoryException.hasChildren
            : CategoryException.hasProducts,
        blocked,
      );
    }
    return _command(lojaId, 'archive', {'target': node.toRef()});
  }

  static Future<Map<String, dynamic>> reorder({
    required String lojaId,
    required CategoryNode? parent,
    required List<CategoryNode> orderedChildren,
  }) =>
      _command(lojaId, 'reorder', {
        'parent': parent?.toRef(),
        'orderedChildren': [for (final c in orderedChildren) c.toRef()],
      });
}
