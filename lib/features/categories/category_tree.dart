import 'package:diacritic/diacritic.dart';

import '../../models/produto.dart';

/// Árvore de categorias da loja (até [kMaxCategoryDepth] níveis), montada em memória a partir de
/// UMA leitura de `lojas/{lojaId}/categorias` + os produtos já carregados (sem consulta por nível).
///
/// Produtos antigos só têm texto (`categoria` / `subcategoria` / extras): esses nomes viram nós
/// virtuais (raiz e 2º nível) até a lojista agir sobre eles — nenhuma escrita de migração.
const int kMaxCategoryDepth = 6;
const String kCategoryDepthLimitMessage =
    'Você pode criar categorias em até 6 níveis.';
const String kCategoryHasChildrenMessage =
    'Esta categoria possui subcategorias.';
const String kCategoryHasProductsMessage =
    'Esta categoria possui produtos. Mova os produtos para outra categoria antes de excluir.';
const String kCategoryCycleSelfMessage =
    'Uma categoria não pode ser pai dela mesma.';
const String kCategoryCycleDescendantMessage =
    'Uma categoria não pode ser movida para dentro de uma subcategoria dela.';
const String kCategoryBreadcrumbSeparator = ' > ';

/// Mesmo limite do servidor (`MAX_CATEGORY_ASSIGNMENTS`); acima disso o salvamento é recusado, nunca truncado.
const int kMaxCategoryAssignments = 20;
const String kCategoryAssignmentsLimitMessage =
    'Um produto pode estar em até $kMaxCategoryAssignments categorias.';

final RegExp _spaces = RegExp(r'\s+');

/// Chave de comparação: sem acentos, minúsculas, espaços simples ("Anéis" == "aneis").
String normalizeCategoryName(String value) =>
    removeDiacritics(value.trim().replaceAll(_spaces, ' ').toLowerCase());

String cleanCategoryName(String value) => value.trim().replaceAll(_spaces, ' ');

/// Radical simples de plural em português, para a busca ("anel" encontra "Anéis").
String _stem(String word) {
  if (word.length <= 3) return word;
  if (word.endsWith('eis')) return '${word.substring(0, word.length - 3)}el';
  if (word.endsWith('ois')) return '${word.substring(0, word.length - 3)}ol';
  if (word.endsWith('ais')) return '${word.substring(0, word.length - 3)}al';
  if (word.endsWith('oes') || word.endsWith('aes') || word.endsWith('aos')) {
    return '${word.substring(0, word.length - 3)}ao';
  }
  if (word.endsWith('ns')) return '${word.substring(0, word.length - 2)}m';
  if (word.endsWith('res') || word.endsWith('zes') || word.endsWith('ses')) {
    return word.substring(0, word.length - 2);
  }
  if (word.endsWith('s')) return word.substring(0, word.length - 1);
  return word;
}

List<String> _stems(String text) => normalizeCategoryName(text)
    .split(' ')
    .where((w) => w.isNotEmpty)
    .map(_stem)
    .toList();

class CategoryNode {
  const CategoryNode({
    required this.id,
    required this.lojaId,
    required this.nome,
    required this.parentId,
    required this.depth,
    required this.pathIds,
    required this.pathNames,
    this.isDeleted = false,
    this.sortOrder,
    this.legacyNames = const [],
    this.isVirtual = false,
  });

  final String id;
  final String lojaId;
  final String nome;
  final String? parentId;
  final int depth;
  final List<String> pathIds;
  final List<String> pathNames;
  final bool isDeleted;
  final int? sortOrder;
  final List<String> legacyNames;

  /// Existe só como texto nos produtos (ainda sem documento).
  final bool isVirtual;

  bool get canAddChild => depth < kMaxCategoryDepth;
  String get breadcrumb => pathNames.join(kCategoryBreadcrumbSeparator);

  /// Referência enviada ao `categoryCommand`.
  Map<String, dynamic> toRef() =>
      isVirtual ? {'legacyPath': pathNames} : {'id': id};
}

/// O que a árvore precisa de um produto para posicioná-lo.
class CategoryProductRef {
  const CategoryProductRef({
    this.pathIds = const [],
    this.leafIds = const [],
    this.categorias = const [],
    this.subcategorias = const [],
  });

  /// Caminho legado (trio `categoryPathIds`); só a folha conta.
  final List<String> pathIds;

  /// Folhas de `categoryAssignments` (um produto em vários caminhos).
  final List<String> leafIds;
  final List<String> categorias;
  final List<String> subcategorias;

  /// Folhas efetivas: atribuições quando existem, senão a folha do trio legado.
  static List<String> _leavesFromAssignments(dynamic raw) {
    if (raw is! List) return const [];
    final out = <String>[];
    for (final item in raw) {
      if (item is! Map) continue;
      var id = (item['categoryId'] ?? '').toString().trim();
      if (id.isEmpty) {
        final path = item['pathIds'];
        if (path is List && path.isNotEmpty) id = path.last.toString().trim();
      }
      if (id.isNotEmpty && !out.contains(id)) out.add(id);
    }
    return out;
  }

  static List<String> _uniq(Iterable<String> values, {bool skipCombo = false}) {
    final seen = <String>{};
    final out = <String>[];
    for (final raw in values) {
      final v = cleanCategoryName(raw);
      final key = normalizeCategoryName(v);
      if (key.isEmpty || (skipCombo && key == 'combo')) continue;
      if (seen.add(key)) out.add(v);
    }
    return out;
  }

  static List<String> _strings(dynamic raw) =>
      raw is List ? raw.map((e) => e.toString()).toList() : const <String>[];

  /// Documento do catálogo / Firestore. No catálogo, "Combo" de produto combo não é categoria.
  factory CategoryProductRef.fromMap(Map<String, dynamic> m,
      {bool skipComboLabel = false}) {
    final tipo = (m['tipoProduto'] ?? m['tipo'] ?? '').toString().trim().toLowerCase();
    final skip = skipComboLabel && tipo == 'combo';
    final leaves = _leavesFromAssignments(m['categoryAssignments']);
    return CategoryProductRef(
      pathIds: leaves.isNotEmpty
          ? const []
          : _strings(m['categoryPathIds'])
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList(),
      leafIds: leaves,
      categorias: _uniq([
        (m['categoria'] ?? m['categoriaId'] ?? '').toString(),
        ..._strings(m['categoriasAssociadas']),
        ..._strings(m['categoriasExtras']),
      ], skipCombo: skip),
      subcategorias: _uniq([
        (m['subcategoria'] ?? m['subcategoriaId'] ?? '').toString(),
        ..._strings(m['subcategoriasAssociadas']),
        ..._strings(m['subcategoriasExtras']),
      ], skipCombo: skip),
    );
  }

  factory CategoryProductRef.fromProduto(Produto p) {
    final leaves = _leavesFromAssignments(p.categoryAssignments);
    return CategoryProductRef(
      pathIds: leaves.isNotEmpty ? const [] : List<String>.from(p.categoryPathIds),
      leafIds: leaves,
      categorias: _uniq([p.categoria, ...p.categoriasExtras]),
      subcategorias: _uniq([p.subcategoria, ...p.subcategoriasExtras]),
    );
  }
}

class CategoryTree {
  CategoryTree._(this.lojaId, this._nodes, this.quarantined);

  final String lojaId;
  final Map<String, CategoryNode> _nodes;

  /// Documentos ignorados: id → CROSS_TENANT | CYCLE | DEPTH_LIMIT | NOT_FOUND.
  final Map<String, String> quarantined;

  final Map<String, List<CategoryNode>> _children = {};
  final Map<String, Map<String, String>> _byName = {};
  final Map<String, Map<String, String>> _byLegacyName = {};
  final Map<String, int> _counts = {};

  static const String _rootKey = '\u0000root';
  static String _key(String? parentId) => parentId ?? _rootKey;

  static CategoryTree empty(String lojaId) =>
      CategoryTree.build(lojaId: lojaId, docs: const []);

  /// [docs]: mapas do Firestore com a chave `id`. Estrutura vem da cadeia de `parentId`
  /// (não de `pathIds` gravado); ciclos, outra loja e >6 níveis ficam em quarentena.
  factory CategoryTree.build({
    required String lojaId,
    required Iterable<Map<String, dynamic>> docs,
    Iterable<CategoryProductRef> products = const [],
  }) {
    final raw = <String, Map<String, dynamic>>{};
    final quarantined = <String, String>{};
    for (final d in docs) {
      final id = (d['id'] ?? '').toString();
      if (id.isEmpty || id.contains('/') || id.startsWith(_virtualPrefix)) continue;
      final docLoja = d['lojaId'];
      if (docLoja != null && docLoja.toString() != lojaId) {
        quarantined[id] = 'CROSS_TENANT';
        continue;
      }
      raw[id] = d;
    }
    final nodes = <String, CategoryNode>{};
    CategoryNode? resolve(String id, List<String> trail) {
      final done = nodes[id];
      if (done != null) return done;
      if (quarantined.containsKey(id)) return null;
      final d = raw[id];
      if (d == null) return null;
      if (trail.contains(id)) {
        for (final t in trail.sublist(trail.indexOf(id))) {
          quarantined[t] = 'CYCLE';
        }
        return null;
      }
      final nomeRaw = cleanCategoryName((d['nome'] ?? '').toString());
      final nome = nomeRaw.isEmpty ? id : nomeRaw;
      final parentRaw = (d['parentId'] ?? '').toString().trim();
      final parentId = parentRaw.isEmpty ? null : parentRaw;
      var pathIds = <String>[id];
      var pathNames = <String>[nome];
      if (parentId != null) {
        final parent = resolve(parentId, [...trail, id]);
        if (quarantined.containsKey(id)) return null;
        if (parent == null) {
          quarantined[id] = quarantined[parentId] == 'CROSS_TENANT'
              ? 'CROSS_TENANT'
              : 'NOT_FOUND';
          return null;
        }
        pathIds = [...parent.pathIds, id];
        pathNames = [...parent.pathNames, nome];
      }
      if (pathIds.length > kMaxCategoryDepth) {
        quarantined[id] = 'DEPTH_LIMIT';
        return null;
      }
      final legacy = d['legacyNames'];
      final node = CategoryNode(
        id: id,
        lojaId: lojaId,
        nome: nome,
        parentId: parentId,
        depth: pathIds.length,
        pathIds: List.unmodifiable(pathIds),
        pathNames: List.unmodifiable(pathNames),
        isDeleted: d['isDeleted'] == true || d['deletedAt'] != null,
        sortOrder: d['sortOrder'] is int ? d['sortOrder'] as int : null,
        legacyNames: legacy is List
            ? List.unmodifiable(legacy
                .map((e) => cleanCategoryName(e.toString()))
                .where((e) => e.isNotEmpty))
            : const [],
      );
      nodes[id] = node;
      return node;
    }

    for (final id in raw.keys) {
      resolve(id, const []);
    }
    final tree = CategoryTree._(lojaId, nodes, quarantined);
    for (final n in nodes.values) {
      if (!n.isDeleted) tree._index(n);
    }
    final refs = products.toList();
    for (final ref in refs) {
      tree._addLegacy(ref);
    }
    tree._sortChildren();
    for (final ref in refs) {
      for (final id in tree.idsForProduct(ref)) {
        tree._counts[id] = (tree._counts[id] ?? 0) + 1;
      }
    }
    return tree;
  }

  static const String _virtualPrefix = 'v:';

  void _index(CategoryNode n) {
    final k = _key(n.parentId);
    _children.putIfAbsent(k, () => []).add(n);
    _byName.putIfAbsent(k, () => {}).putIfAbsent(normalizeCategoryName(n.nome), () => n.id);
    for (final l in n.legacyNames) {
      _byLegacyName.putIfAbsent(k, () => {}).putIfAbsent(normalizeCategoryName(l), () => n.id);
    }
  }

  void _sortChildren() {
    for (final list in _children.values) {
      list.sort(compareCategoryNodes);
    }
  }

  CategoryNode _virtual(CategoryNode? parent, String nome) {
    final key = normalizeCategoryName(nome);
    final id = parent == null
        ? '$_virtualPrefix$key'
        : '$_virtualPrefix${parent.id}/$key';
    final node = CategoryNode(
      id: id,
      lojaId: lojaId,
      nome: nome,
      parentId: parent?.id,
      depth: (parent?.depth ?? 0) + 1,
      pathIds: List.unmodifiable([...?parent?.pathIds, id]),
      pathNames: List.unmodifiable([...?parent?.pathNames, nome]),
      isVirtual: true,
    );
    _nodes[id] = node;
    _index(node);
    return node;
  }

  void _addLegacy(CategoryProductRef ref) {
    for (final c in ref.categorias) {
      final root = activeChildByName(null, c) ?? _virtual(null, c);
      if (!root.canAddChild) continue;
      for (final s in ref.subcategorias) {
        activeChildByName(root.id, s) ?? _virtual(root, s);
      }
    }
  }

  static int compareCategoryNodes(CategoryNode a, CategoryNode b) {
    const big = 1 << 30;
    final ao = a.sortOrder ?? big;
    final bo = b.sortOrder ?? big;
    if (ao != bo) return ao.compareTo(bo);
    final c = normalizeCategoryName(a.nome).compareTo(normalizeCategoryName(b.nome));
    if (c != 0) return c;
    return a.id.compareTo(b.id);
  }

  CategoryNode? node(String? id) => id == null ? null : _nodes[id];

  List<CategoryNode> get roots => childrenOf(null);

  /// Filhos ativos, na ordem visual (sortOrder, depois nome).
  List<CategoryNode> childrenOf(String? parentId) =>
      List.unmodifiable(_children[_key(parentId)] ?? const <CategoryNode>[]);

  bool hasChildren(String id) => (_children[id] ?? const []).isNotEmpty;

  Iterable<CategoryNode> get activeNodes =>
      _nodes.values.where((n) => !n.isDeleted);

  bool get isEmpty => _children.isEmpty;

  /// Nome atual tem prioridade sobre nome antigo (renomeado).
  CategoryNode? activeChildByName(String? parentId, String name) {
    final k = _key(parentId);
    final key = normalizeCategoryName(name);
    if (key.isEmpty) return null;
    final id = _byName[k]?[key] ?? _byLegacyName[k]?[key];
    return id == null ? null : _nodes[id];
  }

  CategoryNode? nodeByNamePath(List<String> names) {
    CategoryNode? cur;
    for (final n in names) {
      if (n.trim().isEmpty) break;
      cur = activeChildByName(cur?.id, n);
      if (cur == null) return null;
    }
    return cur;
  }

  /// Todos os nós (com ancestrais) em que o produto aparece; vários caminhos viram um único conjunto.
  Set<String> idsForProduct(CategoryProductRef ref) {
    final ids = <String>{};
    for (final leafId in [
      ...ref.leafIds,
      if (ref.pathIds.isNotEmpty) ref.pathIds.last,
    ]) {
      final leaf = _nodes[leafId];
      if (leaf != null && !leaf.isDeleted && !leaf.isVirtual) ids.addAll(leaf.pathIds);
    }
    for (final c in ref.categorias) {
      final root = activeChildByName(null, c);
      if (root == null) continue;
      ids.add(root.id);
      for (final s in ref.subcategorias) {
        final child = activeChildByName(root.id, s);
        if (child != null) ids.add(child.id);
      }
    }
    return ids;
  }

  /// Categoria pai inclui produtos de todas as subcategorias.
  bool productMatches(CategoryProductRef ref, String nodeId) =>
      idsForProduct(ref).contains(nodeId);

  /// Nó mais profundo do produto (para exibir o caminho).
  CategoryNode? leafForProduct(CategoryProductRef ref) {
    CategoryNode? best;
    for (final id in idsForProduct(ref)) {
      final n = _nodes[id];
      if (n != null && (best == null || n.depth > best.depth)) best = n;
    }
    return best;
  }

  /// Produtos (entre os usados para montar a árvore) na subárvore do nó.
  int productCount(String nodeId) => _counts[nodeId] ?? 0;

  /// Raízes cadastradas que contêm produtos (inclui raízes de caminhos adicionais).
  List<String> rootNamesWithProducts() => [
        for (final r in roots)
          if (!r.isVirtual && productCount(r.id) > 0) r.nome,
      ];

  /// Busca por nome (ou nome antigo), tolerante a acento e plural; resultados com caminho completo.
  List<CategoryNode> search(String query) {
    final q = normalizeCategoryName(query);
    if (q.isEmpty) return const [];
    final qStems = _stems(query);
    bool hit(String name) {
      final n = normalizeCategoryName(name);
      if (n.contains(q)) return true;
      final words = _stems(name);
      return qStems.every((qs) => words.any((w) => w.startsWith(qs)));
    }

    final out = activeNodes
        .where((n) => hit(n.nome) || n.legacyNames.any(hit))
        .toList()
      ..sort((a, b) {
        final d = a.depth.compareTo(b.depth);
        return d != 0 ? d : normalizeCategoryName(a.breadcrumb).compareTo(normalizeCategoryName(b.breadcrumb));
      });
    return out;
  }

  List<CategoryNode> pathOf(String id) {
    final n = _nodes[id];
    if (n == null) return const [];
    return [for (final pid in n.pathIds) if (_nodes[pid] != null) _nodes[pid]!];
  }

  /// null = permitido; senão a mensagem exibida (bloqueia antes de qualquer escrita).
  String? validateNewChild(CategoryNode? parent) {
    if (parent != null && parent.depth >= kMaxCategoryDepth) {
      return kCategoryDepthLimitMessage;
    }
    return null;
  }

  String? validateMove(String nodeId, String? newParentId) {
    final node = _nodes[nodeId];
    if (node == null) return 'Categoria não encontrada.';
    if (newParentId != null) {
      if (newParentId == nodeId) return kCategoryCycleSelfMessage;
      final parent = _nodes[newParentId];
      if (parent == null) return 'Categoria não encontrada.';
      if (parent.pathIds.contains(nodeId)) return kCategoryCycleDescendantMessage;
    }
    final parentDepth = newParentId == null ? 0 : _nodes[newParentId]!.depth;
    var height = 1;
    for (final n in activeNodes) {
      if (n.id != nodeId && n.pathIds.contains(nodeId)) {
        final h = n.depth - node.depth + 1;
        if (h > height) height = h;
      }
    }
    if (parentDepth + height > kMaxCategoryDepth) return kCategoryDepthLimitMessage;
    return null;
  }

  /// Motivo de bloqueio da exclusão (filhos ativos ou produtos), ou null.
  String? archiveBlocker(CategoryNode node) {
    if (hasChildren(node.id)) return kCategoryHasChildrenMessage;
    if (node.isVirtual || productCount(node.id) > 0) return kCategoryHasProductsMessage;
    return null;
  }
}
