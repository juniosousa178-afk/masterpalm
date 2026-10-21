import 'package:flutter/material.dart';

import '../category_tree.dart';
import '../product_category_fields.dart';
import 'category_breadcrumb.dart';

/// "Categorias do produto": um card por caminho (com [X] para remover só o vínculo) e
/// "+ Adicionar categoria". Cards ocupam a largura e o caminho quebra linha (sem rolagem horizontal).
class ProductCategoryAssignmentsEditor extends StatelessWidget {
  const ProductCategoryAssignmentsEditor({
    super.key,
    required this.assignments,
    required this.tree,
    required this.primaryLinked,
    required this.onAdd,
    required this.onRemove,
    required this.onManage,
    this.legacyTextPath = const [],
    this.loading = false,
    this.awaitingTree = false,
  });

  final List<ProductCategoryAssignment> assignments;
  final CategoryTree? tree;

  /// O primeiro caminho acompanha Categoria/Subcategoria (texto); se não, sai ao salvar.
  final bool primaryLinked;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;
  final VoidCallback onManage;

  /// Categoria/Subcategoria por texto, exibida quando nenhum caminho da árvore está escolhido.
  final List<String> legacyTextPath;
  final bool loading;
  final bool awaitingTree;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final full = assignments.length >= kMaxCategoryAssignments;
    return Container(
      key: const ValueKey('produto_category_tile'),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.account_tree_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Categorias do produto',
                    style: theme.textTheme.titleSmall),
              ),
              if (loading)
                const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'O produto aparece em todas as categorias escolhidas, com o mesmo estoque e preço.',
            style: theme.textTheme.bodySmall,
            softWrap: true,
          ),
          const SizedBox(height: 8),
          if (awaitingTree)
            Text('Carregando categorias…', style: theme.textTheme.bodySmall)
          else if (assignments.isEmpty && legacyTextPath.isNotEmpty)
            CategoryBreadcrumb(
              key: const ValueKey('produto_category_legacy_text'),
              names: legacyTextPath,
              rootLabel: null,
            )
          else if (assignments.isEmpty)
            Text('Nenhuma categoria escolhida.',
                style: theme.textTheme.bodySmall)
          else
            for (var i = 0; i < assignments.length; i++)
              _AssignmentCard(
                assignment: assignments[i].refreshedFrom(tree),
                primary: i == 0,
                unlinked: i == 0 && !primaryLinked,
                onRemove: () => onRemove(assignments[i].categoryId),
              ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton.icon(
                key: const ValueKey('produto_category_add'),
                onPressed: loading || full ? null : onAdd,
                icon: const Icon(Icons.add),
                label: const Text('Adicionar categoria'),
              ),
              TextButton.icon(
                key: const ValueKey('produto_category_manage'),
                onPressed: loading ? null : onManage,
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Gerenciar categorias'),
              ),
              if (assignments.length > 1 || full)
                Text(
                  full
                      ? kCategoryAssignmentsLimitMessage
                      : '${assignments.length} de $kMaxCategoryAssignments',
                  key: const ValueKey('produto_category_count'),
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AssignmentCard extends StatelessWidget {
  const _AssignmentCard({
    required this.assignment,
    required this.primary,
    required this.unlinked,
    required this.onRemove,
  });

  final ProductCategoryAssignment assignment;
  final bool primary;
  final bool unlinked;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: ValueKey('produto_category_assignment_${assignment.categoryId}'),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 4, 0, 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CategoryBreadcrumb(names: assignment.pathNames, rootLabel: null),
                if (unlinked)
                  Text(
                    'Categoria/Subcategoria foi alterada: este caminho sai ao salvar.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                    softWrap: true,
                  )
                else if (primary)
                  Text('Principal', style: theme.textTheme.labelSmall),
              ],
            ),
          ),
          IconButton(
            key: ValueKey('produto_category_remove_${assignment.categoryId}'),
            tooltip: 'Remover desta categoria',
            icon: const Icon(Icons.close),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
