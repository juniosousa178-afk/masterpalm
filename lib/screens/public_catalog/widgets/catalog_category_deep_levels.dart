import 'package:flutter/material.dart';

/// Níveis 3–6 da árvore de categorias no catálogo: uma linha de chips por nível (quebra linha, não corta).
/// [levels][i] = opções do nível; [selected][i] = escolha atual (ausente = "Todas").
class CatalogCategoryDeepLevels extends StatelessWidget {
  const CatalogCategoryDeepLevels({
    super.key,
    required this.parentNames,
    required this.levels,
    required this.selected,
    required this.onSelect,
    required this.textColor,
    required this.primaryColor,
    required this.surfaceColor,
  });

  /// Nome do nó pai de cada nível (rótulo do chip "Todas").
  final List<String> parentNames;
  final List<List<String>> levels;
  final List<String> selected;

  /// [name] null = "Todas" naquele nível.
  final void Function(int level, String? name) onSelect;
  final Color textColor;
  final Color primaryColor;
  final Color surfaceColor;

  Widget _chip({
    required Key key,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return ChoiceChip(
      key: key,
      selected: isSelected,
      showCheckmark: false,
      label: Text(
        label,
        softWrap: true,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          color: isSelected ? Colors.white : textColor,
        ),
      ),
      backgroundColor: surfaceColor.withValues(alpha: 0.85),
      selectedColor: primaryColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected ? primaryColor : textColor.withValues(alpha: 0.35),
        ),
      ),
      onSelected: (_) => onTap(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (levels.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var level = 0; level < levels.length; level++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Wrap(
                key: ValueKey('catalog_category_level_$level'),
                spacing: 6,
                runSpacing: 6,
                children: [
                  _chip(
                    key: ValueKey('catalog_category_level_${level}_all'),
                    label: level < parentNames.length
                        ? 'Todas em ${parentNames[level]}'
                        : 'Todas',
                    isSelected: selected.length <= level,
                    onTap: () => onSelect(level, null),
                  ),
                  for (final name in levels[level])
                    _chip(
                      key: ValueKey('catalog_category_level_${level}_$name'),
                      label: name,
                      isSelected:
                          selected.length > level && selected[level] == name,
                      onTap: () => onSelect(level, name),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
