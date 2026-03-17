// lib/screens/public_catalog/widgets/catalog_search_filters_bar.dart
// Barra de busca, filtros de categoria/subcategoria, ordena��o e chips (UI extra�da de public_catalog_screen.dart)

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Barra de pesquisa do cat�logo (TextField).
class CatalogSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final Color headerSearchText;
  final Color headerSearchHint;
  final Color headerSearchBg;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const CatalogSearchBar({
    super.key,
    required this.controller,
    required this.headerSearchText,
    required this.headerSearchHint,
    required this.headerSearchBg,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SizedBox(
        height: 40,
        child: TextField(
          style: TextStyle(color: headerSearchText),
          textAlignVertical: TextAlignVertical.center,
          controller: controller,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 0,
            ),
            hintText: 'Buscar produtos...',
            hintStyle: TextStyle(color: headerSearchHint),
            filled: true,
            fillColor: headerSearchBg,
            prefixIcon: Icon(
              Icons.search,
              color: headerSearchHint,
            ),
            suffixIcon: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                if (value.text.isEmpty) {
                  return const SizedBox.shrink();
                }
                return IconButton(
                  icon: Icon(Icons.clear, size: 20, color: headerSearchHint),
                  onPressed: onClear,
                );
              },
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 36,
              minHeight: 36,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// Chips de categoria e subcategoria.
/// [verticalLayout] true = uma categoria por linha (sidebar desktop).
class CatalogCategorySubcategoryFilters extends StatelessWidget {
  final List<String> categoriasMenu;
  final String? selectedCategory;
  final String? selectedSubcategory;
  final List<Map<String, dynamic>> produtos;
  final Color textColor;
  final Color cardColor;
  final Color primaryColor;
  final VoidCallback onCategorySelectedNull;
  final void Function(String) onCategorySelected;
  final VoidCallback onSubcategorySelectedNull;
  final void Function(String) onSubcategorySelected;
  final bool verticalLayout;

  const CatalogCategorySubcategoryFilters({
    super.key,
    required this.categoriasMenu,
    required this.selectedCategory,
    required this.selectedSubcategory,
    required this.produtos,
    required this.textColor,
    required this.cardColor,
    required this.primaryColor,
    required this.onCategorySelectedNull,
    required this.onCategorySelected,
    required this.onSubcategorySelectedNull,
    required this.onSubcategorySelected,
    this.verticalLayout = false,
  });

  @override
  Widget build(BuildContext context) {
    if (categoriasMenu.isEmpty) return const SizedBox.shrink();

    if (verticalLayout) {
      return _buildVerticalLayout(context);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          const SizedBox(height: 10),
          SizedBox(
            height: 36,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: categoriasMenu.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  final isSelected = selectedCategory == null;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      selected: isSelected,
                      label: Text(
                        'Todos',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: isSelected ? Colors.white : textColor,
                        ),
                      ),
                      backgroundColor: cardColor.withValues(alpha:0.5),
                      selectedColor: primaryColor,
                      checkmarkColor: Colors.white,
                      showCheckmark: false,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: isSelected
                              ? primaryColor
                              : Colors.transparent,
                        ),
                      ),
                      onSelected: (_) => onCategorySelectedNull(),
                    ),
                  );
                }
                final cat = categoriasMenu[index - 1];
                final isSelected = selectedCategory == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    selected: isSelected,
                    label: Text(
                      cat,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isSelected ? Colors.white : textColor,
                      ),
                    ),
                    backgroundColor: cardColor.withValues(alpha:0.5),
                    selectedColor: primaryColor,
                    checkmarkColor: Colors.white,
                    showCheckmark: false,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: isSelected ? primaryColor : Colors.transparent,
                      ),
                    ),
                    onSelected: (_) => onCategorySelected(cat),
                  ),
                );
              },
            ),
          ),
          Builder(
            builder: (context) {
              if (selectedCategory == null) {
                return const SizedBox.shrink();
              }
              final subcategoriasSet = <String>{};
              for (final p in produtos) {
                final cat = (p['categoria'] ?? p['categoriaId'] ?? '')
                    .toString()
                    .trim();
                final subcat = (p['subcategoria'] ?? p['subcategoriaId'] ?? '')
                    .toString()
                    .trim();
                if (cat == selectedCategory && subcat.isNotEmpty) {
                  subcategoriasSet.add(subcat);
                }
              }
              final subcategorias = subcategoriasSet.toList()..sort();
              if (subcategorias.isEmpty) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SizedBox(
                  height: 48,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: subcategorias.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        final isSelected = selectedSubcategory == null;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            selected: isSelected,
                            label: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  selectedCategory!,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: isSelected
                                        ? Colors.white70
                                        : textColor,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  'Todas',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected
                                        ? Colors.white
                                        : textColor,
                                  ),
                                ),
                              ],
                            ),
                            backgroundColor: isSelected
                                ? null
                                : cardColor.withValues(alpha:0.85),
                            selectedColor:
                                primaryColor.withValues(alpha:0.7),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: isSelected
                                    ? primaryColor
                                    : textColor.withValues(alpha:0.4),
                              ),
                            ),
                            onSelected: (_) => onSubcategorySelectedNull(),
                          ),
                        );
                      }
                      final subcat = subcategorias[index - 1];
                      final isSelected = selectedSubcategory == subcat;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          selected: isSelected,
                          label: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                selectedCategory!,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isSelected
                                      ? Colors.white70
                                      : textColor,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                subcat,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected ? Colors.white : textColor,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                          backgroundColor: isSelected
                              ? null
                              : cardColor.withValues(alpha:0.85),
                          selectedColor:
                              primaryColor.withValues(alpha:0.7),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: isSelected
                                  ? primaryColor
                                  : textColor.withValues(alpha:0.4),
                            ),
                          ),
                          onSelected: (_) => onSubcategorySelected(subcat),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ],
    );
  }

  Widget _buildVerticalLayout(BuildContext context) {
    final items = <Widget>[];
    // "Todos" � sem bal�o, s� texto clic�vel
    items.add(_buildSidebarItem(
      label: 'Todos',
      isSelected: selectedCategory == null,
      onTap: onCategorySelectedNull,
    ));
    items.add(const SizedBox(height: 4));

    for (final cat in categoriasMenu) {
      final isSelected = selectedCategory == cat;
      items.add(_buildSidebarItem(
        label: cat,
        isSelected: isSelected,
        onTap: () => onCategorySelected(cat),
      ));
      // Subcategorias logo abaixo da categoria quando ela est� selecionada
      if (isSelected) {
        final subcategoriasSet = <String>{};
        for (final p in produtos) {
          final c = (p['categoria'] ?? p['categoriaId'] ?? '').toString().trim();
          final sub = (p['subcategoria'] ?? p['subcategoriaId'] ?? '').toString().trim();
          if (c == cat && sub.isNotEmpty) subcategoriasSet.add(sub);
        }
        final subcategorias = subcategoriasSet.toList()..sort();
        if (subcategorias.isNotEmpty) {
          items.add(const SizedBox(height: 8));
          items.add(_buildSidebarItem(
            label: 'Todas',
            isSelected: selectedSubcategory == null,
            onTap: onSubcategorySelectedNull,
            isSubcategory: true,
          ));
          for (final subcat in subcategorias) {
            items.add(_buildSidebarItem(
              label: subcat,
              isSelected: selectedSubcategory == subcat,
              onTap: () => onSubcategorySelected(subcat),
              isSubcategory: true,
            ));
          }
          items.add(const SizedBox(height: 8));
        }
      }
      items.add(const SizedBox(height: 4));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: items,
      ),
    );
  }

  Widget _buildSidebarItem({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    bool isSubcategory = false,
  }) {
    return Material(
      color: isSelected
          ? primaryColor.withValues(alpha:0.2)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: EdgeInsets.fromLTRB(isSubcategory ? 16 : 12, 10, 12, 10),
          decoration: BoxDecoration(
            border: isSelected
                ? Border(
                    left: BorderSide(color: primaryColor, width: 3),
                  )
                : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: isSubcategory ? 12 : 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: isSelected ? primaryColor : textColor,
            ),
          ),
        ),
      ),
    );
  }
}

/// Linha de chips de ordena��o e filtros (nome, novidade, pre�o, em estoque, faixa de pre�o) + pagina��o.
class CatalogSortFiltersSection extends StatelessWidget {
  final String ordenacaoProdutos;
  final bool apenasEmEstoque;
  final double? precoMin;
  final double? precoMax;
  final Color primaryColor;
  final Color cardColor;
  final Color textColor;
  final void Function(String) onSortChanged;
  final VoidCallback onFilterEmEstoqueToggled;
  final VoidCallback onFilterPrecoTap;
  final int paginaAtual;
  final int totalPaginas;
  final void Function(int) onPageChanged;

  const CatalogSortFiltersSection({
    super.key,
    required this.ordenacaoProdutos,
    required this.apenasEmEstoque,
    required this.precoMin,
    required this.precoMax,
    required this.primaryColor,
    required this.cardColor,
    required this.textColor,
    required this.onSortChanged,
    required this.onFilterEmEstoqueToggled,
    required this.onFilterPrecoTap,
    required this.paginaAtual,
    required this.totalPaginas,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _SortChip(
                  value: 'nome',
                  label: 'Nome',
                  selected: ordenacaoProdutos == 'nome',
                  primaryColor: primaryColor,
                  cardColor: cardColor,
                  textColor: textColor,
                  onTap: () => onSortChanged('nome'),
                ),
                const SizedBox(width: 8),
                _SortChip(
                  value: 'novidade',
                  label: 'Novidade',
                  selected: ordenacaoProdutos == 'novidade',
                  primaryColor: primaryColor,
                  cardColor: cardColor,
                  textColor: textColor,
                  onTap: () => onSortChanged('novidade'),
                ),
                const SizedBox(width: 8),
                _SortChip(
                  value: 'preco_asc',
                  label: 'Menor pre�o',
                  selected: ordenacaoProdutos == 'preco_asc',
                  primaryColor: primaryColor,
                  cardColor: cardColor,
                  textColor: textColor,
                  onTap: () => onSortChanged('preco_asc'),
                ),
                const SizedBox(width: 8),
                _SortChip(
                  value: 'preco_desc',
                  label: 'Maior pre�o',
                  selected: ordenacaoProdutos == 'preco_desc',
                  primaryColor: primaryColor,
                  cardColor: cardColor,
                  textColor: textColor,
                  onTap: () => onSortChanged('preco_desc'),
                ),
                const SizedBox(width: 8),
                _FilterEmEstoqueChip(
                  selected: apenasEmEstoque,
                  primaryColor: primaryColor,
                  cardColor: cardColor,
                  textColor: textColor,
                  onTap: onFilterEmEstoqueToggled,
                ),
                const SizedBox(width: 8),
                _FilterPrecoChip(
                  ativo: precoMin != null || precoMax != null,
                  primaryColor: primaryColor,
                  cardColor: cardColor,
                  textColor: textColor,
                  onTap: onFilterPrecoTap,
                ),
              ],
            ),
          ),
          if (totalPaginas > 1 && kIsWeb) ...[
            const SizedBox(height: 8),
            CatalogPaginacaoRow(
              paginaAtual: paginaAtual,
              totalPaginas: totalPaginas,
              primaryColor: primaryColor,
              cardColor: cardColor,
              textColor: textColor,
              onPagePrev: paginaAtual > 0 ? () => onPageChanged(paginaAtual - 1) : null,
              onPageNext: paginaAtual < totalPaginas - 1
                  ? () => onPageChanged(paginaAtual + 1)
                  : null,
            ),
          ],
        ],
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  final String value;
  final String label;
  final bool selected;
  final Color primaryColor;
  final Color cardColor;
  final Color textColor;
  final VoidCallback onTap;

  const _SortChip({
    required this.value,
    required this.label,
    required this.selected,
    required this.primaryColor,
    required this.cardColor,
    required this.textColor,
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : textColor,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterEmEstoqueChip extends StatelessWidget {
  final bool selected;
  final Color primaryColor;
  final Color cardColor;
  final Color textColor;
  final VoidCallback onTap;

  const _FilterEmEstoqueChip({
    required this.selected,
    required this.primaryColor,
    required this.cardColor,
    required this.textColor,
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? Icons.check_circle : Icons.inventory_2_outlined,
                size: 16,
                color: selected ? Colors.white : textColor,
              ),
              const SizedBox(width: 6),
              Text(
                'Em estoque',
                style: TextStyle(
                  color: selected ? Colors.white : textColor,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterPrecoChip extends StatelessWidget {
  final bool ativo;
  final Color primaryColor;
  final Color cardColor;
  final Color textColor;
  final VoidCallback onTap;

  const _FilterPrecoChip({
    required this.ativo,
    required this.primaryColor,
    required this.cardColor,
    required this.textColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ativo ? primaryColor : cardColor,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tune, size: 16, color: ativo ? Colors.white : textColor),
              const SizedBox(width: 6),
              Text(
                'Pre�o${ativo ? ' ?' : ''}',
                style: TextStyle(
                  color: ativo ? Colors.white : textColor,
                  fontSize: 13,
                  fontWeight: ativo ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Linha de pagina��o (Anterior | P�gina X de Y | Pr�xima).
class CatalogPaginacaoRow extends StatelessWidget {
  final int paginaAtual;
  final int totalPaginas;
  final Color primaryColor;
  final Color cardColor;
  final Color textColor;
  final VoidCallback? onPagePrev;
  final VoidCallback? onPageNext;

  const CatalogPaginacaoRow({
    super.key,
    required this.paginaAtual,
    required this.totalPaginas,
    required this.primaryColor,
    required this.cardColor,
    required this.textColor,
    required this.onPagePrev,
    required this.onPageNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: paginaAtual > 0
                ? primaryColor
                : cardColor.withValues(alpha:0.5),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: onPagePrev,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Icon(
                  Icons.arrow_back_ios_new,
                  size: 24,
                  color: paginaAtual > 0
                      ? Colors.white
                      : textColor.withValues(alpha:0.4),
                ),
              ),
            ),
          ),
          Flexible(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'P�gina ${paginaAtual + 1} de $totalPaginas',
                style: TextStyle(
                  color: textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ),
          Material(
            color: paginaAtual < totalPaginas - 1
                ? primaryColor
                : cardColor.withValues(alpha:0.5),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: onPageNext,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Icon(
                  Icons.arrow_forward_ios,
                  size: 24,
                  color: paginaAtual < totalPaginas - 1
                      ? Colors.white
                      : textColor.withValues(alpha:0.4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

