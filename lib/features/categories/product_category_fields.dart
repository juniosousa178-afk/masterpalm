import '../../models/produto.dart';
import 'category_tree.dart';

/// Campos hierárquicos do produto entre Firestore e Hive.
abstract final class ProductCategoryFields {
  static const keys = <String>{'categoryId', 'categoryPathIds', 'categoryPathNames'};

  static List<String> _list(dynamic raw) => raw is List
      ? raw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList()
      : <String>[];

  static String idFrom(Map<String, dynamic> data) =>
      (data['categoryId'] ?? '').toString().trim();
  static List<String> pathIdsFrom(Map<String, dynamic> data) =>
      _list(data['categoryPathIds']);
  static List<String> pathNamesFrom(Map<String, dynamic> data) =>
      _list(data['categoryPathNames']);

  /// Payload sempre coerente com a validação do servidor; um trio inconsistente é enviado vazio.
  static Map<String, dynamic> toMap(Produto p) {
    final ids = List<String>.from(p.categoryPathIds);
    final names = List<String>.from(p.categoryPathNames);
    final coherent = ids.isNotEmpty &&
        ids.length <= kMaxCategoryDepth &&
        ids.last == p.categoryId &&
        names.length == ids.length &&
        ids.toSet().length == ids.length;
    if (!coherent) {
      return {'categoryId': '', 'categoryPathIds': <String>[], 'categoryPathNames': <String>[]};
    }
    return {'categoryId': p.categoryId, 'categoryPathIds': ids, 'categoryPathNames': names};
  }

  /// Aplica apenas as chaves presentes (documentos antigos não apagam a escolha local).
  static void applyFromMap(Produto p, Map<String, dynamic> data) {
    if (data.containsKey('categoryId')) p.categoryId = idFrom(data);
    if (data.containsKey('categoryPathIds')) p.categoryPathIds = pathIdsFrom(data);
    if (data.containsKey('categoryPathNames')) p.categoryPathNames = pathNamesFrom(data);
  }

  static void copy(Produto from, Produto to) {
    to.categoryId = from.categoryId;
    to.categoryPathIds = List<String>.from(from.categoryPathIds);
    to.categoryPathNames = List<String>.from(from.categoryPathNames);
  }

  /// O caminho só vale enquanto os campos de texto (categoria/subcategoria) correspondem aos dois primeiros níveis.
  static bool pathAgreesWithText(
      List<String> pathNames, String categoria, String subcategoria) {
    if (pathNames.isEmpty) return false;
    if (normalizeCategoryName(categoria) != normalizeCategoryName(pathNames[0])) {
      return false;
    }
    final expectedSub = pathNames.length > 1 ? pathNames[1] : '';
    return normalizeCategoryName(subcategoria) == normalizeCategoryName(expectedSub);
  }

  static void clear(Produto p) {
    p.categoryId = '';
    p.categoryPathIds = <String>[];
    p.categoryPathNames = <String>[];
  }

  /// Importação: um caminho novo substitui o atual; texto de categoria diferente do caminho o invalida.
  static void mergeImported({required Produto existente, required Produto novo}) {
    if (novo.categoryId.trim().isNotEmpty) {
      copy(novo, existente);
      return;
    }
    if (existente.categoryId.isEmpty) return;
    final names = existente.categoryPathNames;
    bool differs(String text, int level) =>
        text.trim().isNotEmpty &&
        (names.length <= level ||
            normalizeCategoryName(text) != normalizeCategoryName(names[level]));
    if (differs(novo.categoria, 0) || differs(novo.subcategoria, 1)) clear(existente);
  }

  /// Escolha na árvore: nó real grava o caminho; nó só-legado (texto dos produtos) limpa o trio.
  static void applySelection(Produto p, CategoryNode? node) {
    if (node == null || node.isVirtual) {
      clear(p);
      return;
    }
    p.categoryId = node.id;
    p.categoryPathIds = List<String>.from(node.pathIds);
    p.categoryPathNames = List<String>.from(node.pathNames);
  }
}
