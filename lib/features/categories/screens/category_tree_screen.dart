import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../../../core/hive_box_names.dart';
import '../../../models/produto.dart';
import '../category_service.dart';
import '../category_tree.dart';
import '../widgets/category_breadcrumb.dart';

/// Produtos da loja já em cache local (Hive) — usados para contagem e categorias legadas.
Future<List<CategoryProductRef>> loadLocalCategoryProductRefs(String lojaId) async {
  final loja = lojaId.trim();
  if (loja.isEmpty) return const [];
  final name = HiveBoxNames.produtos(loja);
  final box = Hive.isBoxOpen(name) ? Hive.box<Produto>(name) : await Hive.openBox<Produto>(name);
  return [
    for (final p in box.values)
      if (p.lojaId.trim().isEmpty || p.lojaId.trim() == loja) CategoryProductRef.fromProduto(p),
  ];
}

class _CategoryNameDialog extends StatefulWidget {
  const _CategoryNameDialog({required this.title, this.parent, this.editing});

  final String title;
  final CategoryNode? parent;
  final CategoryNode? editing;

  @override
  State<_CategoryNameDialog> createState() => _CategoryNameDialogState();
}

class _CategoryNameDialogState extends State<_CategoryNameDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.editing?.nome ?? '');

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = cleanCategoryName(_ctrl.text);
    if (v.isNotEmpty) Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    final parent = widget.parent;
    final editing = widget.editing;
    final level = editing?.depth ?? (parent?.depth ?? 0) + 1;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (parent != null && editing == null) ...[
              const Text('Nova subcategoria de:'),
              const SizedBox(height: 2),
              Text(parent.nome,
                  key: const ValueKey('category_dialog_parent'), style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              CategoryBreadcrumb(
                key: const ValueKey('category_dialog_path'),
                rootLabel: null,
                names: parent.pathNames,
                trailing: '+',
              ),
            ],
            if (editing != null && editing.depth > 1)
              CategoryBreadcrumb(rootLabel: null, names: editing.pathNames),
            Text('Nível $level de $kMaxCategoryDepth',
                key: const ValueKey('category_dialog_level'), style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('category_name_field'),
              controller: _ctrl,
              autofocus: true,
              maxLength: 60,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nome', border: OutlineInputBorder()),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('category_dialog_cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const ValueKey('category_dialog_save'),
          onPressed: _submit,
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}

class CategoryTreeScreen extends StatefulWidget {
  const CategoryTreeScreen({super.key, required this.lojaId, this.productRefsLoader});

  final String lojaId;
  final Future<List<CategoryProductRef>> Function()? productRefsLoader;

  @override
  State<CategoryTreeScreen> createState() => _CategoryTreeScreenState();
}

class _CategoryTreeScreenState extends State<CategoryTreeScreen> {
  final _search = TextEditingController();
  final Set<String> _expanded = {};
  CategoryTree? _tree;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) async {
    try {
      final refs = await (widget.productRefsLoader?.call() ??
          loadLocalCategoryProductRefs(widget.lojaId));
      final tree = await CategoryService.loadTree(widget.lojaId, products: refs, refresh: refresh);
      if (!mounted) return;
      setState(() {
        _tree = tree;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Não foi possível carregar as categorias.');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _load(refresh: true);
      if (success != null) _toast(success);
    } on CategoryException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('Não foi possível salvar a categoria.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askName({
    required String title,
    CategoryNode? parent,
    CategoryNode? editing,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => _CategoryNameDialog(title: title, parent: parent, editing: editing),
    );
  }

  Future<void> _addRoot() async {
    final tree = _tree;
    if (tree == null) return;
    final nome = await _askName(title: 'Nova categoria');
    if (nome == null) return;
    await _run(
      () => CategoryService.create(lojaId: widget.lojaId, tree: tree, parent: null, nome: nome),
      success: 'Categoria criada.',
    );
  }

  Future<void> _addChild(CategoryNode parent) async {
    final tree = _tree;
    if (tree == null) return;
    final blocked = tree.validateNewChild(parent);
    if (blocked != null) {
      _toast(blocked);
      return;
    }
    final nome = await _askName(title: 'Adicionar subcategoria', parent: parent);
    if (nome == null) return;
    _expanded.addAll(parent.pathIds);
    await _run(
      () => CategoryService.create(lojaId: widget.lojaId, tree: tree, parent: parent, nome: nome),
      success: 'Subcategoria criada.',
    );
  }

  Future<void> _rename(CategoryNode node) async {
    final nome = await _askName(title: 'Editar categoria', editing: node);
    if (nome == null || nome == node.nome) return;
    await _run(
      () => CategoryService.rename(lojaId: widget.lojaId, node: node, nome: nome),
      success: 'Categoria renomeada.',
    );
  }

  Future<void> _archive(CategoryNode node) async {
    final tree = _tree;
    if (tree == null) return;
    final blocker = tree.archiveBlocker(node);
    if (blocker != null) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          key: const ValueKey('category_blocked_dialog'),
          title: const Text('Não é possível excluir'),
          content: Text(blocker),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Entendi')),
          ],
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Excluir “${node.nome}”?'),
        content: const Text('A categoria será arquivada e deixará de aparecer nas listas.'),
        actions: [
          TextButton(
            key: const ValueKey('category_archive_cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const ValueKey('category_archive_confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(
      () => CategoryService.archive(lojaId: widget.lojaId, tree: tree, node: node),
      success: 'Categoria excluída.',
    );
  }

  Future<void> _move(CategoryNode node, int delta) async {
    final tree = _tree;
    if (tree == null) return;
    final siblings = [...tree.childrenOf(node.parentId)];
    final i = siblings.indexWhere((n) => n.id == node.id);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= siblings.length) return;
    siblings.insert(j, siblings.removeAt(i));
    await _run(() => CategoryService.reorder(
          lojaId: widget.lojaId,
          parent: tree.node(node.parentId),
          orderedChildren: siblings,
        ));
  }

  void _reveal(CategoryNode node) {
    setState(() {
      _expanded.addAll(node.pathIds.take(node.pathIds.length - 1));
      _search.clear();
    });
  }

  List<CategoryNode> _visibleRows(CategoryTree tree) {
    final out = <CategoryNode>[];
    void walk(String? parentId) {
      for (final n in tree.childrenOf(parentId)) {
        out.add(n);
        if (_expanded.contains(n.id)) walk(n.id);
      }
    }

    walk(null);
    return out;
  }

  Widget _row(CategoryTree tree, CategoryNode n, double step) {
    final theme = Theme.of(context);
    final hasChildren = tree.hasChildren(n.id);
    final expanded = _expanded.contains(n.id);
    final siblings = tree.childrenOf(n.parentId);
    final pos = siblings.indexWhere((s) => s.id == n.id);
    final count = tree.productCount(n.id);
    return Padding(
      key: ValueKey('category_row_${n.id}'),
      padding: EdgeInsets.only(left: (n.depth - 1) * step),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: hasChildren
                ? IconButton(
                    key: ValueKey('category_expand_${n.id}'),
                    tooltip: expanded ? 'Recolher' : 'Expandir',
                    icon: Icon(expanded ? Icons.expand_more : Icons.chevron_right),
                    onPressed: () => setState(() => expanded ? _expanded.remove(n.id) : _expanded.add(n.id)),
                  )
                : null,
          ),
          Expanded(
            child: InkWell(
              onTap: hasChildren
                  ? () => setState(() => expanded ? _expanded.remove(n.id) : _expanded.add(n.id))
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      n.nome,
                      key: ValueKey('category_name_${n.id}'),
                      softWrap: true,
                      style: n.depth == 1
                          ? theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)
                          : theme.textTheme.bodyLarge,
                    ),
                    if (count > 0)
                      Text('$count produto(s)', style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            key: ValueKey('category_menu_${n.id}'),
            tooltip: 'Ações',
            enabled: !_busy,
            onSelected: (v) {
              switch (v) {
                case 'edit':
                  _rename(n);
                case 'add':
                  _addChild(n);
                case 'up':
                  _move(n, -1);
                case 'down':
                  _move(n, 1);
                case 'archive':
                  _archive(n);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Editar')),
              PopupMenuItem(
                value: 'add',
                enabled: n.canAddChild,
                child: Text(n.canAddChild ? 'Adicionar subcategoria' : 'Limite de 6 níveis'),
              ),
              if (pos > 0) const PopupMenuItem(value: 'up', child: Text('Mover para cima')),
              if (pos >= 0 && pos < siblings.length - 1)
                const PopupMenuItem(value: 'down', child: Text('Mover para baixo')),
              const PopupMenuItem(value: 'archive', child: Text('Excluir/Arquivar')),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tree = _tree;
    final width = MediaQuery.sizeOf(context).width;
    final step = width < 420 ? 14.0 : 24.0;
    final query = _search.text.trim();
    Widget body;
    if (_error != null) {
      body = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!),
          TextButton(onPressed: () => _load(refresh: true), child: const Text('Tentar novamente')),
        ]),
      );
    } else if (tree == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (query.isNotEmpty) {
      final results = tree.search(query);
      body = results.isEmpty
          ? const Center(child: Text('Nenhuma categoria encontrada.'))
          : ListView(
              children: [
                for (final n in results)
                  ListTile(
                    key: ValueKey('category_search_result_${n.id}'),
                    leading: const Icon(Icons.label_outline),
                    title: Text(n.nome, softWrap: true),
                    subtitle: Text(n.breadcrumb, softWrap: true),
                    onTap: () => _reveal(n),
                  ),
              ],
            );
    } else {
      final rows = _visibleRows(tree);
      body = rows.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Nenhuma categoria ainda. Toque em “Nova categoria”.', textAlign: TextAlign.center),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: rows.length,
              separatorBuilder: (_, i) => rows.length > i + 1 && rows[i + 1].depth == 1
                  ? const Divider(height: 1)
                  : const SizedBox.shrink(),
              itemBuilder: (_, i) => _row(tree, rows[i], step),
            );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Categorias')),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('category_add_root'),
        onPressed: _busy || tree == null ? null : _addRoot,
        icon: const Icon(Icons.add),
        label: const Text('Nova categoria'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: TextField(
                  key: const ValueKey('category_search'),
                  controller: _search,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Buscar categoria',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                  'Até 6 níveis. Para mudar uma categoria de nível, crie-a no novo lugar.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              if (_busy) const LinearProgressIndicator(minHeight: 2),
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
  }
}
