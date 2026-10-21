import '../../models/produto.dart';
import 'category_tree.dart';

/// Um caminho do produto na árvore: [categoryId] é a folha escolhida (qualquer nível).
class ProductCategoryAssignment {
  const ProductCategoryAssignment({
    required this.categoryId,
    required this.pathIds,
    required this.pathNames,
  });

  factory ProductCategoryAssignment.fromNode(CategoryNode node) =>
      ProductCategoryAssignment(
        categoryId: node.id,
        pathIds: List<String>.unmodifiable(node.pathIds),
        pathNames: List<String>.unmodifiable(node.pathNames),
      );

  final String categoryId;
  final List<String> pathIds;
  final List<String> pathNames;

  bool get isCoherent =>
      categoryId.isNotEmpty &&
      pathIds.isNotEmpty &&
      pathIds.length <= kMaxCategoryDepth &&
      pathIds.last == categoryId &&
      pathNames.length == pathIds.length &&
      pathIds.toSet().length == pathIds.length;

  Map<String, dynamic> toMap() => {
        'categoryId': categoryId,
        'pathIds': List<String>.from(pathIds),
        'pathNames': List<String>.from(pathNames),
      };

  static ProductCategoryAssignment? fromRaw(dynamic raw) {
    if (raw is! Map) return null;
    final ids = ProductCategoryFields._list(raw['pathIds']);
    var id = (raw['categoryId'] ?? '').toString().trim();
    if (id.isEmpty && ids.isNotEmpty) id = ids.last;
    if (id.isEmpty) return null;
    return ProductCategoryAssignment(
      categoryId: id,
      pathIds: ids.isEmpty ? [id] : ids,
      pathNames: ProductCategoryFields._list(raw['pathNames']),
    );
  }

  /// Caminho atual da árvore (nomes renomeados, ids estáveis); nó ausente mantém o gravado.
  ProductCategoryAssignment refreshedFrom(CategoryTree? tree) {
    final node = tree?.node(categoryId);
    if (node == null || node.isVirtual || node.isDeleted) return this;
    return ProductCategoryAssignment.fromNode(node);
  }
}

enum CategoryAddOutcome {
  added,

  /// O nó é descendente de um caminho já escolhido: o caminho mais específico toma o lugar dele.
  replacedAncestor,
  duplicate,

  /// O nó é ancestral de um caminho já escolhido (o produto já aparece nele).
  coveredByDescendant,
  limitReached,

  /// Categoria que existe só como texto dos produtos (sem id na árvore).
  virtualNode,
}

/// Campos hierárquicos do produto entre Firestore e Hive.
///
/// `categoryAssignments` é a fonte canônica (vários caminhos); o trio `categoryId`/`categoryPathIds`/
/// `categoryPathNames` espelha o primeiro caminho para APKs anteriores. Sem atribuições, o trio vale como
/// uma atribuição (produtos antigos, sem migração em massa).
abstract final class ProductCategoryFields {
  static const assignmentsKey = 'categoryAssignments';
  static const legacyKeys = <String>{
    'categoryId',
    'categoryPathIds',
    'categoryPathNames',
  };
  static const keys = <String>{...legacyKeys, assignmentsKey};

  static List<String> _list(dynamic raw) => raw is List
      ? raw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList()
      : <String>[];

  static String idFrom(Map<String, dynamic> data) =>
      (data['categoryId'] ?? '').toString().trim();
  static List<String> pathIdsFrom(Map<String, dynamic> data) =>
      _list(data['categoryPathIds']);
  static List<String> pathNamesFrom(Map<String, dynamic> data) =>
      _list(data['categoryPathNames']);

  /// Formato Hive de `categoryAssignments` (só entradas legíveis).
  static List<Map<String, dynamic>> assignmentMapsFrom(
          Map<String, dynamic> data) =>
      [
        for (final a in _parseAssignments(data[assignmentsKey])) a.toMap(),
      ];

  static List<ProductCategoryAssignment> _parseAssignments(dynamic raw) {
    if (raw is! List) return const [];
    final out = <ProductCategoryAssignment>[];
    for (final item in raw) {
      final a = ProductCategoryAssignment.fromRaw(item);
      if (a != null) out.add(a);
    }
    return out;
  }

  static ProductCategoryAssignment? _legacy(
      String id, List<String> ids, List<String> names) {
    final a = ProductCategoryAssignment(
        categoryId: id, pathIds: ids, pathNames: names);
    return a.isCoherent ? a : null;
  }

  /// Caminhos efetivos do produto: atribuições quando existem, senão o trio legado (se coerente).
  static List<ProductCategoryAssignment> assignmentsOf(Produto p) {
    final parsed = _parseAssignments(p.categoryAssignments);
    if (parsed.isNotEmpty) return parsed;
    final legacy = _legacy(p.categoryId, p.categoryPathIds, p.categoryPathNames);
    return legacy == null ? const [] : [legacy];
  }

  static List<ProductCategoryAssignment> assignmentsFromMap(
      Map<String, dynamic> data) {
    final parsed = _parseAssignments(data[assignmentsKey]);
    if (parsed.isNotEmpty) return parsed;
    final legacy = _legacy(idFrom(data), pathIdsFrom(data), pathNamesFrom(data));
    return legacy == null ? const [] : [legacy];
  }

  /// Sem folhas repetidas e sem ancestral de outra folha escolhida (fica o caminho mais específico).
  /// Ramos independentes são mantidos, na ordem da primeira aparição.
  static List<ProductCategoryAssignment> normalize(
      Iterable<ProductCategoryAssignment> input) {
    final unique = <ProductCategoryAssignment>[];
    final seen = <String>{};
    for (final a in input) {
      if (a.categoryId.isEmpty || !seen.add(a.categoryId)) continue;
      unique.add(a);
    }
    return [
      for (final a in unique)
        if (!unique.any((b) =>
            b.categoryId != a.categoryId && b.pathIds.contains(a.categoryId)))
          a,
    ];
  }

  /// "+ Adicionar categoria": mesma normalização do servidor, com o motivo para a mensagem da UI.
  static ({List<ProductCategoryAssignment> assignments, CategoryAddOutcome outcome})
      addAssignment(List<ProductCategoryAssignment> current, CategoryNode node) {
    if (node.isVirtual) {
      return (assignments: current, outcome: CategoryAddOutcome.virtualNode);
    }
    if (current.any((a) => a.categoryId == node.id)) {
      return (assignments: current, outcome: CategoryAddOutcome.duplicate);
    }
    if (current.any((a) => a.pathIds.contains(node.id))) {
      return (assignments: current, outcome: CategoryAddOutcome.coveredByDescendant);
    }
    final added = ProductCategoryAssignment.fromNode(node);
    final ancestorAt =
        current.indexWhere((a) => node.pathIds.contains(a.categoryId));
    if (ancestorAt >= 0) {
      final next = [
        for (var i = 0; i < current.length; i++)
          if (i == ancestorAt)
            added
          else if (!node.pathIds.contains(current[i].categoryId))
            current[i],
      ];
      return (assignments: next, outcome: CategoryAddOutcome.replacedAncestor);
    }
    if (current.length >= kMaxCategoryAssignments) {
      return (assignments: current, outcome: CategoryAddOutcome.limitReached);
    }
    return (assignments: [...current, added], outcome: CategoryAddOutcome.added);
  }

  /// Remove só o vínculo com [categoryId] (estoque, preço e o próprio produto não mudam).
  static List<ProductCategoryAssignment> removeAssignment(
          List<ProductCategoryAssignment> current, String categoryId) =>
      [for (final a in current) if (a.categoryId != categoryId) a];

  /// Trio legado coerente (ou vazio): o servidor recusa trios incoerentes.
  static Map<String, dynamic> toMap(Produto p) {
    final primary = assignmentsOf(p).where((a) => a.isCoherent).firstOrNull;
    if (primary == null) {
      return {'categoryId': '', 'categoryPathIds': <String>[], 'categoryPathNames': <String>[]};
    }
    return {
      'categoryId': primary.categoryId,
      'categoryPathIds': List<String>.from(primary.pathIds),
      'categoryPathNames': List<String>.from(primary.pathNames),
    };
  }

  /// Todos os caminhos + trio do primeiro. No `stockCatalogCommand` o servidor revalida cada folha na
  /// árvore atual e grava caminhos/nomes canônicos. Escritas diretas com merge usam só [toMap], para não
  /// sobrescrever as atribuições gravadas pelo servidor.
  static Map<String, dynamic> toFullMap(Produto p) => {
        ...toMap(p),
        assignmentsKey: [
          for (final a in assignmentsOf(p))
            if (a.isCoherent) a.toMap(),
        ],
      };

  /// Aplica apenas as chaves presentes (documentos antigos não apagam a escolha local).
  static void applyFromMap(Produto p, Map<String, dynamic> data) {
    if (data.containsKey('categoryId')) p.categoryId = idFrom(data);
    if (data.containsKey('categoryPathIds')) p.categoryPathIds = pathIdsFrom(data);
    if (data.containsKey('categoryPathNames')) p.categoryPathNames = pathNamesFrom(data);
    if (data.containsKey(assignmentsKey)) {
      p.categoryAssignments = assignmentMapsFrom(data);
    }
  }

  static void copy(Produto from, Produto to) {
    to.categoryId = from.categoryId;
    to.categoryPathIds = List<String>.from(from.categoryPathIds);
    to.categoryPathNames = List<String>.from(from.categoryPathNames);
    to.categoryAssignments = [
      for (final m in from.categoryAssignments) Map<String, dynamic>.from(m),
    ];
  }

  /// Grava [assignments] (já normalizadas) no produto; o trio espelha o primeiro caminho.
  static void setAssignments(
      Produto p, List<ProductCategoryAssignment> assignments) {
    final primary = assignments.firstOrNull;
    p.categoryId = primary?.categoryId ?? '';
    p.categoryPathIds = List<String>.from(primary?.pathIds ?? const <String>[]);
    p.categoryPathNames = List<String>.from(primary?.pathNames ?? const <String>[]);
    p.categoryAssignments = [for (final a in assignments) a.toMap()];
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

  /// Como [pathAgreesWithText], aceitando também o nome atual e os nomes antigos (rename) de cada nível.
  static bool assignmentAgreesWithText(ProductCategoryAssignment a,
      CategoryTree? tree, String categoria, String subcategoria) {
    if (pathAgreesWithText(a.pathNames, categoria, subcategoria)) return true;
    if (tree == null) return false;
    bool level(int i, String text) {
      final key = normalizeCategoryName(text);
      if (i >= a.pathIds.length) return key.isEmpty;
      if (i < a.pathNames.length && normalizeCategoryName(a.pathNames[i]) == key) {
        return true;
      }
      final node = tree.node(a.pathIds[i]);
      if (node == null) return false;
      return normalizeCategoryName(node.nome) == key ||
          node.legacyNames.any((l) => normalizeCategoryName(l) == key);
    }

    return level(0, categoria) && level(1, subcategoria);
  }

  /// Caminhos gravados ao salvar o formulário. O primeiro acompanha os campos de texto: se a lojista
  /// trocou o texto da categoria, só esse vínculo sai; os demais caminhos ficam. Nomes vêm da árvore atual.
  static List<ProductCategoryAssignment> assignmentsForSave({
    required List<ProductCategoryAssignment> assignments,
    required CategoryTree? tree,
    required String categoria,
    required String subcategoria,
  }) {
    if (assignments.isEmpty) return const [];
    final kept = [
      if (assignmentAgreesWithText(
          assignments.first, tree, categoria, subcategoria))
        assignments.first,
      ...assignments.skip(1),
    ];
    return normalize([for (final a in kept) a.refreshedFrom(tree)]);
  }

  /// Trio gravado ao salvar o produto. Ids nunca mudam (sem reparent); nomes atuais só entram quando os
  /// campos de texto já os acompanham, senão um rename de nível 1/2 desfaria o vínculo na reabertura.
  static ({String id, List<String> pathIds, List<String> pathNames}) choiceForSave({
    required String categoryId,
    required List<String> pathIds,
    required List<String> pathNames,
    required CategoryNode? current,
    required String categoria,
    required String subcategoria,
  }) {
    const none = (id: '', pathIds: <String>[], pathNames: <String>[]);
    if (categoryId.isEmpty || !pathAgreesWithText(pathNames, categoria, subcategoria)) {
      return none;
    }
    if (current != null &&
        !current.isVirtual &&
        !current.isDeleted &&
        pathAgreesWithText(current.pathNames, categoria, subcategoria)) {
      return (
        id: current.id,
        pathIds: List<String>.from(current.pathIds),
        pathNames: List<String>.from(current.pathNames),
      );
    }
    return (
      id: categoryId,
      pathIds: List<String>.from(pathIds),
      pathNames: List<String>.from(pathNames),
    );
  }

  static void clear(Produto p) {
    p.categoryId = '';
    p.categoryPathIds = <String>[];
    p.categoryPathNames = <String>[];
    p.categoryAssignments = <Map<String, dynamic>>[];
  }

  /// Importação: caminhos novos substituem os atuais; texto de categoria diferente do primeiro caminho
  /// remove só esse vínculo (os demais caminhos ficam).
  static void mergeImported({required Produto existente, required Produto novo}) {
    if (assignmentsOf(novo).isNotEmpty) {
      copy(novo, existente);
      return;
    }
    final current = assignmentsOf(existente);
    if (current.isEmpty) return;
    final names = current.first.pathNames;
    bool differs(String text, int level) =>
        text.trim().isNotEmpty &&
        (names.length <= level ||
            normalizeCategoryName(text) != normalizeCategoryName(names[level]));
    if (differs(novo.categoria, 0) || differs(novo.subcategoria, 1)) {
      setAssignments(existente, current.skip(1).toList());
    }
  }

  /// Escolha única na árvore: nó real grava o caminho; nó só-legado (texto dos produtos) limpa os caminhos.
  static void applySelection(Produto p, CategoryNode? node) {
    if (node == null || node.isVirtual) {
      clear(p);
      return;
    }
    setAssignments(p, [ProductCategoryAssignment.fromNode(node)]);
  }
}
