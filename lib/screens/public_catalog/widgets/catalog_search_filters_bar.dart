// lib/screens/public_catalog/widgets/catalog_search_filters_bar.dart
// Barra de busca, filtros de categoria/subcategoria, ordenação e chips (UI extraída de public_catalog_screen.dart)

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../utils/platform_adaptive.dart';

/// Barra de pesquisa do catálogo (TextField).
class CatalogSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final Color headerSearchText;
  final Color headerSearchHint;
  final Color headerSearchBg;
  final String hintText;
  final bool iconOnRight;
  final Color? borderColor;
  final double borderRadius;
  final double height;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const CatalogSearchBar({
    super.key,
    required this.controller,
    required this.headerSearchText,
    required this.headerSearchHint,
    required this.headerSearchBg,
    this.hintText = 'Buscar produtos...',
    this.iconOnRight = false,
    this.borderColor,
    this.borderRadius = 12,
    this.height = 40,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SizedBox(
        height: height,
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
            hintText: hintText,
            hintStyle: TextStyle(color: headerSearchHint),
            filled: true,
            fillColor: headerSearchBg,
            prefixIcon: iconOnRight
                ? null
                : Icon(
                    Icons.search,
                    color: headerSearchHint,
                  ),
            suffixIcon: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                if (value.text.isNotEmpty) {
                  return IconButton(
                    icon: Icon(Icons.clear, size: 20, color: headerSearchHint),
                    onPressed: onClear,
                  );
                }
                if (iconOnRight) {
                  return Icon(Icons.search, color: headerSearchHint, size: 20);
                }
                return const SizedBox.shrink();
              },
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 36,
              minHeight: 36,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(borderRadius),
              borderSide: borderColor == null
                  ? BorderSide.none
                  : BorderSide(color: borderColor!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(borderRadius),
              borderSide: borderColor == null
                  ? BorderSide.none
                  : BorderSide(color: borderColor!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(borderRadius),
              borderSide: borderColor == null
                  ? BorderSide.none
                  : BorderSide(color: borderColor!),
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
            height: 38,
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
                          fontSize: 13,
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
                        fontSize: 13,
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
                  height: 52,
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
                                  fontSize: 11,
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
                                  fontSize: 13,
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
    // "Todos" ? sem balão, só texto clicável
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
      // Subcategorias logo abaixo da categoria quando ela está selecionada
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
              fontSize: isSubcategory ? 13 : 14,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: isSelected ? primaryColor : textColor,
            ),
          ),
        ),
      ),
    );
  }
}

/// Linha de chips de ordenação e filtros (nome, novidade, preço, em estoque, faixa de preço) + paginação.
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
    final hasFilterAtivo = apenasEmEstoque || precoMin != null || precoMax != null;
    final isSortPadrao = ordenacaoProdutos == 'nome';
    final hasAlgoAtivo = hasFilterAtivo || !isSortPadrao;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => _showFilterMenu(context),
                icon: Icon(
                  Icons.tune,
                  size: 18,
                  color: hasAlgoAtivo ? Colors.white : textColor,
                ),
                label: Text(
                  hasAlgoAtivo ? 'Filtro ativo' : 'Filtro',
                  style: TextStyle(
                    color: hasAlgoAtivo ? Colors.white : textColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  backgroundColor: hasAlgoAtivo ? primaryColor : cardColor,
                  side: BorderSide(
                    color: hasAlgoAtivo
                        ? primaryColor
                        : textColor.withValues(alpha: 0.12),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _labelResumoSelecionado(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor.withValues(alpha: 0.72),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          if (totalPaginas > 1 && usePointerFirstChrome(context)) ...[
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

  String _labelResumoSelecionado() {
    final sortLabel = switch (ordenacaoProdutos) {
      'novidade' => 'Novidade',
      'preco_asc' => 'Menor preço',
      'preco_desc' => 'Maior preço',
      _ => 'Nome',
    };
    final parts = <String>['Ordenar: $sortLabel'];
    if (apenasEmEstoque) parts.add('Em estoque');
    if (precoMin != null || precoMax != null) {
      parts.add('Preço');
    }
    return parts.join(' ? ');
  }

  Future<void> _showFilterMenu(BuildContext context) async {
    if (!context.mounted) return;
    final wideChrome = usePointerFirstChrome(context);

    Widget filterMenuBody(BuildContext sheetContext) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: textColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Filtro',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _FilterActionTile(
                label: 'Nome',
                selected: ordenacaoProdutos == 'nome',
                textColor: textColor,
                primaryColor: primaryColor,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onSortChanged('nome');
                },
              ),
              _FilterActionTile(
                label: 'Novidade',
                selected: ordenacaoProdutos == 'novidade',
                textColor: textColor,
                primaryColor: primaryColor,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onSortChanged('novidade');
                },
              ),
              _FilterActionTile(
                label: 'Menor preço',
                selected: ordenacaoProdutos == 'preco_asc',
                textColor: textColor,
                primaryColor: primaryColor,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onSortChanged('preco_asc');
                },
              ),
              _FilterActionTile(
                label: 'Maior preço',
                selected: ordenacaoProdutos == 'preco_desc',
                textColor: textColor,
                primaryColor: primaryColor,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onSortChanged('preco_desc');
                },
              ),
              const SizedBox(height: 6),
              _FilterSwitchTile(
                label: 'Apenas em estoque',
                value: apenasEmEstoque,
                textColor: textColor,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onFilterEmEstoqueToggled();
                },
              ),
              _FilterActionTile(
                label: (precoMin != null || precoMax != null)
                    ? 'Faixa de preço (ativo)'
                    : 'Faixa de preço',
                selected: precoMin != null || precoMax != null,
                textColor: textColor,
                primaryColor: primaryColor,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onFilterPrecoTap();
                },
              ),
            ],
          ),
        ),
      );
    }

    if (wideChrome) {
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (sheetContext) {
          final mq = MediaQuery.of(sheetContext);
          final maxW = math.min(kMaxContentWidth, mq.size.width - 40);
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxW,
                maxHeight: mq.size.height * 0.65,
              ),
              child: Material(
                color: cardColor,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: filterMenuBody(sheetContext),
              ),
            ),
          );
        },
      );
    } else {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: false,
        backgroundColor: cardColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        builder: (sheetContext) => filterMenuBody(sheetContext),
      );
    }
  }
}

class _FilterActionTile extends StatelessWidget {
  final String label;
  final bool selected;
  final Color textColor;
  final Color primaryColor;
  final VoidCallback onTap;

  const _FilterActionTile({
    required this.label,
    required this.selected,
    required this.textColor,
    required this.primaryColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      tileColor: selected ? primaryColor.withValues(alpha: 0.12) : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
      title: Text(
        label,
        style: TextStyle(
          color: selected ? primaryColor : textColor,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          fontSize: 14,
        ),
      ),
      trailing: selected
          ? Icon(Icons.check_circle, color: primaryColor, size: 18)
          : null,
      onTap: onTap,
    );
  }
}

class _FilterSwitchTile extends StatelessWidget {
  final String label;
  final bool value;
  final Color textColor;
  final VoidCallback onTap;

  const _FilterSwitchTile({
    required this.label,
    required this.value,
    required this.textColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
      title: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontWeight: value ? FontWeight.w700 : FontWeight.w500,
          fontSize: 14,
        ),
      ),
      trailing: Icon(
        value ? Icons.check_box : Icons.check_box_outline_blank,
        size: 20,
        color: value ? Colors.green : textColor.withValues(alpha: 0.6),
      ),
      onTap: onTap,
    );
  }
}

/// Linha de paginação (Anterior | Página X de Y | Próxima).
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
                'Página ${paginaAtual + 1} de $totalPaginas',
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

