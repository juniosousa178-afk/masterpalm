// lib/screens/public_catalog/widgets/catalog_premium_categories_section.dart
// Seção "Explorar por categoria" – layout premium. Só exibe quando categoriasMenu não vazio.

import 'package:flutter/material.dart';

/// Seção horizontal de categorias em destaque (layout premium).
class CatalogPremiumCategoriesSection extends StatelessWidget {
  final List<String> categorias;
  final String? selectedCategory;
  final Color textColor;
  final Color primaryColor;
  final Color cardColor;
  final void Function(String) onCategoryTap;
  final VoidCallback onClearCategory;

  const CatalogPremiumCategoriesSection({
    super.key,
    required this.categorias,
    this.selectedCategory,
    required this.textColor,
    required this.primaryColor,
    required this.cardColor,
    required this.onCategoryTap,
    required this.onClearCategory,
  });

  @override
  Widget build(BuildContext context) {
    if (categorias.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Explorar por categoria',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                if (selectedCategory != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _CategoryChip(
                      label: 'Todos',
                      selected: false,
                      textColor: textColor,
                      primaryColor: primaryColor,
                      cardColor: cardColor,
                      onTap: onClearCategory,
                    ),
                  ),
                ...categorias.map((cat) {
                  final selected = selectedCategory == cat;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _CategoryChip(
                      label: cat,
                      selected: selected,
                      textColor: textColor,
                      primaryColor: primaryColor,
                      cardColor: cardColor,
                      onTap: () => onCategoryTap(cat),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color textColor;
  final Color primaryColor;
  final Color cardColor;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.textColor,
    required this.primaryColor,
    required this.cardColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? primaryColor : cardColor,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? Colors.white : textColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
