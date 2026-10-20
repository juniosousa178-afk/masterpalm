import 'package:flutter/material.dart';

import '../category_tree.dart';
import 'category_breadcrumb.dart';

/// Resultado do seletor: [node] escolhido, ou [cleared] para "Sem categoria".
class CategoryPickResult {
  const CategoryPickResult.node(CategoryNode this.node) : cleared = false;
  const CategoryPickResult.cleared()
      : node = null,
        cleared = true;

  final CategoryNode? node;
  final bool cleared;
}

/// Navegação na árvore para escolher a categoria (qualquer nível pode ser escolhido).
Future<CategoryPickResult?> showCategoryPicker(
  BuildContext context, {
  required CategoryTree tree,
  String? selectedId,
  bool allowClear = true,
  String title = 'Escolher categoria',
  VoidCallback? onManage,
}) {
  final wide = MediaQuery.sizeOf(context).width >= 700;
  final body = CategoryPickerPanel(
    tree: tree,
    selectedId: selectedId,
    allowClear: allowClear,
    title: title,
    onManage: onManage,
  );
  if (wide) {
    return showDialog<CategoryPickResult>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
          child: body,
        ),
      ),
    );
  }
  return showModalBottomSheet<CategoryPickResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => FractionallySizedBox(heightFactor: 0.88, child: body),
  );
}

class CategoryPickerPanel extends StatefulWidget {
  const CategoryPickerPanel({
    super.key,
    required this.tree,
    this.selectedId,
    this.allowClear = true,
    this.title = 'Escolher categoria',
    this.onManage,
  });

  final CategoryTree tree;
  final String? selectedId;
  final bool allowClear;
  final String title;
  final VoidCallback? onManage;

  @override
  State<CategoryPickerPanel> createState() => _CategoryPickerPanelState();
}

class _CategoryPickerPanelState extends State<CategoryPickerPanel> {
  final _search = TextEditingController();
  CategoryNode? _current;

  @override
  void initState() {
    super.initState();
    final selected = widget.tree.node(widget.selectedId);
    if (selected != null && selected.parentId != null) {
      _current = widget.tree.node(selected.parentId);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _open(CategoryNode? node) => setState(() => _current = node);

  void _pick(CategoryNode node) =>
      Navigator.of(context).pop(CategoryPickResult.node(node));

  Widget _tile(CategoryNode n, {bool showPath = false}) {
    final hasChildren = widget.tree.hasChildren(n.id);
    final selected = n.id == widget.selectedId;
    final count = widget.tree.productCount(n.id);
    return ListTile(
      key: ValueKey('category_picker_item_${n.id}'),
      selected: selected,
      title: Text(n.nome, softWrap: true),
      subtitle: showPath
          ? Text(n.breadcrumb, softWrap: true)
          : (count > 0 ? Text('$count produto(s)') : null),
      leading: Icon(selected ? Icons.check_circle : Icons.label_outline),
      trailing: hasChildren && !showPath
          ? IconButton(
              key: ValueKey('category_picker_open_${n.id}'),
              tooltip: 'Ver subcategorias',
              icon: const Icon(Icons.chevron_right),
              onPressed: () => _open(n),
            )
          : null,
      onTap: () => hasChildren && !showPath ? _open(n) : _pick(n),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _search.text.trim();
    final children = widget.tree.childrenOf(_current?.id);
    final results = query.isEmpty ? const <CategoryNode>[] : widget.tree.search(query);
    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
            child: Row(
              children: [
                Expanded(child: Text(widget.title, style: theme.textTheme.titleMedium)),
                if (widget.onManage != null)
                  TextButton(
                    key: const ValueKey('category_picker_manage'),
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onManage!();
                    },
                    child: const Text('Gerenciar'),
                  ),
                IconButton(
                  tooltip: 'Fechar',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              key: const ValueKey('category_picker_search'),
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
          if (query.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
              child: CategoryBreadcrumb(
                key: const ValueKey('category_picker_breadcrumb'),
                names: _current?.pathNames ?? const [],
                onTapLevel: (level) => _open(level < 0
                    ? null
                    : widget.tree.node(_current!.pathIds[level])),
              ),
            ),
          if (query.isEmpty && _current != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: FilledButton.tonalIcon(
                key: const ValueKey('category_picker_use_current'),
                onPressed: () => _pick(_current!),
                icon: const Icon(Icons.check),
                label: Text('Usar “${_current!.nome}”', softWrap: true),
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: query.isNotEmpty
                ? (results.isEmpty
                    ? const Center(child: Text('Nenhuma categoria encontrada.'))
                    : ListView(children: [for (final n in results) _tile(n, showPath: true)]))
                : (children.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _current == null
                                ? 'Nenhuma categoria cadastrada.'
                                : 'Sem subcategorias.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView(children: [for (final n in children) _tile(n)])),
          ),
          if (widget.allowClear)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('category_picker_clear'),
                  onPressed: () => Navigator.of(context).pop(const CategoryPickResult.cleared()),
                  icon: const Icon(Icons.block),
                  label: const Text('Sem categoria'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
