// lib/screens/public_catalog/catalog_card_variation_preview_data.dart
// Prévia (somente leitura) das variações vendáveis exibida no card do catálogo.
// Mesma regra de disponibilidade do sheet de seleção: só células com qtd > 0.

import '../../core/produto_variacao_extra.dart';

enum CatalogCardVariationKind { sizes, colors, combined }

class CatalogCardVariationPreviewData {
  const CatalogCardVariationPreviewData._(this.kind, this.labels);

  final CatalogCardVariationKind kind;

  /// Rótulos já ordenados; em [CatalogCardVariationKind.combined] cada rótulo
  /// é uma combinação real existente na grade (ex.: `16 · Prata`).
  final List<String> labels;

  static const int maxVisibleChips = 6;
  static const String semTamanhoKey = 'sem-tamanho';
  static const String semCorKey = 'sem-cor';
  static const String comboSeparator = ' · ';

  String get title {
    switch (kind) {
      case CatalogCardVariationKind.sizes:
        return 'Tamanhos';
      case CatalogCardVariationKind.colors:
        return 'Cores';
      case CatalogCardVariationKind.combined:
        return 'Variações';
    }
  }

  String get semanticsLabel {
    final itens =
        labels.map((l) => l.replaceAll(comboSeparator, ' ')).join(', ');
    return '$title disponíveis: $itens';
  }

  /// [variacoes]: grade pública `tamanho → cor → qtd|extras` (`sem-tamanho` / `sem-cor` como sentinelas).
  /// [estoquePorTamanho] / [estoquePorCor]: mapas agregados (legado ou sem grade).
  /// [tamanhosOrdem] / [coresOrdem]: listas editoriais do produto, usadas só para ordenar.
  static CatalogCardVariationPreviewData? fromCardInputs({
    Map<String, dynamic>? variacoes,
    Map<String, int>? estoquePorTamanho,
    Map<String, int>? estoquePorCor,
    Object? tamanhosOrdem,
    Object? coresOrdem,
  }) {
    final sizeOrder = _orderList(tamanhosOrdem);
    final colorOrder = _orderList(coresOrdem);

    if (variacoes != null && variacoes.isNotEmpty) {
      final sizes = <String>[];
      final combos = <(String, String)>[];
      final realColors = <String>{};
      variacoes.forEach((rawSize, cells) {
        final size = rawSize.toString();
        if (size == semTamanhoKey || !_isRealKey(size) || cells is! Map) return;
        final positive = <String>[];
        cells.forEach((rawColor, cell) {
          final color = rawColor.toString();
          if (ProdutoVariacaoExtra.isMetaKey(color)) return;
          if (ProdutoVariacaoExtra.somarCelula(cell) > 0) positive.add(color);
        });
        if (positive.isEmpty) return;
        sizes.add(size);
        for (final color in positive) {
          combos.add((size, color));
          if (_isRealColor(color)) realColors.add(color);
        }
      });

      if (sizes.isNotEmpty) {
        final orderedSizes = _sortSizes(sizes, sizeOrder);
        if (realColors.length <= 1) {
          return CatalogCardVariationPreviewData._(
            CatalogCardVariationKind.sizes,
            orderedSizes,
          );
        }
        final allReal = combos.every((c) => _isRealColor(c.$2));
        if (orderedSizes.length == 1 && allReal) {
          return CatalogCardVariationPreviewData._(
            CatalogCardVariationKind.colors,
            _sortByOrder(combos.map((c) => c.$2).toList(), colorOrder),
          );
        }
        final sizeRank = {
          for (var i = 0; i < orderedSizes.length; i++) orderedSizes[i]: i,
        };
        final colorsInOrder =
            _sortByOrder(combos.map((c) => c.$2).toSet().toList(), colorOrder);
        final colorRank = {
          for (var i = 0; i < colorsInOrder.length; i++) colorsInOrder[i]: i,
        };
        final sorted = [...combos]..sort((a, b) {
            final s = sizeRank[a.$1]!.compareTo(sizeRank[b.$1]!);
            if (s != 0) return s;
            return colorRank[a.$2]!.compareTo(colorRank[b.$2]!);
          });
        final labels = <String>[];
        for (final c in sorted) {
          final label =
              _isRealColor(c.$2) ? '${c.$1}$comboSeparator${c.$2}' : c.$1;
          if (!labels.contains(label)) labels.add(label);
        }
        return CatalogCardVariationPreviewData._(
          CatalogCardVariationKind.combined,
          labels,
        );
      }

      final semTam = variacoes[semTamanhoKey];
      if (semTam is Map) {
        final colors = <String>[];
        semTam.forEach((rawColor, cell) {
          final color = rawColor.toString();
          if (!_isRealColor(color)) return;
          if (ProdutoVariacaoExtra.somarCelula(cell) > 0) colors.add(color);
        });
        if (colors.isNotEmpty) {
          return CatalogCardVariationPreviewData._(
            CatalogCardVariationKind.colors,
            _sortByOrder(colors, colorOrder),
          );
        }
      }
    }

    final sizes = <String>[
      for (final e in (estoquePorTamanho ?? const <String, int>{}).entries)
        if (e.value > 0 && e.key != semTamanhoKey && _isRealKey(e.key)) e.key,
    ];
    if (sizes.isNotEmpty) {
      return CatalogCardVariationPreviewData._(
        CatalogCardVariationKind.sizes,
        _sortSizes(sizes, sizeOrder),
      );
    }
    final colors = <String>[
      for (final e in (estoquePorCor ?? const <String, int>{}).entries)
        if (e.value > 0 && _isRealColor(e.key)) e.key,
    ];
    if (colors.isNotEmpty) {
      return CatalogCardVariationPreviewData._(
        CatalogCardVariationKind.colors,
        _sortByOrder(colors, colorOrder),
      );
    }
    return null;
  }

  static bool _isRealKey(String key) =>
      key.trim().isNotEmpty && !ProdutoVariacaoExtra.isMetaKey(key);

  static bool _isRealColor(String color) =>
      _isRealKey(color) &&
      color != semCorKey &&
      !ProdutoVariacaoExtra.isSemExtraMapKey(color);

  static final RegExp _numeric = RegExp(r'^\d+([.,]\d+)?$');

  static double? _numericValue(String s) {
    final t = s.trim();
    if (!_numeric.hasMatch(t)) return null;
    return double.tryParse(t.replaceAll(',', '.'));
  }

  static List<String> _orderList(Object? raw) {
    if (raw is List) {
      return [
        for (final e in raw)
          if (e != null && e.toString().trim().isNotEmpty) e.toString().trim(),
      ];
    }
    if (raw is String && raw.trim().isNotEmpty) {
      return raw
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const [];
  }

  /// Tamanhos todos numéricos: ordem numérica. Caso contrário: ordem editorial
  /// do produto (se houver) ou a ordem recebida.
  static List<String> _sortSizes(List<String> sizes, List<String> order) {
    final values = sizes.map(_numericValue).toList();
    if (values.every((v) => v != null)) {
      final indexed = List.generate(sizes.length, (i) => i)
        ..sort((a, b) {
          final c = values[a]!.compareTo(values[b]!);
          return c != 0 ? c : a.compareTo(b);
        });
      return [for (final i in indexed) sizes[i]];
    }
    return _sortByOrder(sizes, order);
  }

  static List<String> _sortByOrder(List<String> items, List<String> order) {
    if (order.isEmpty) return List<String>.of(items);
    final rank = <String, int>{};
    for (var i = 0; i < order.length; i++) {
      rank.putIfAbsent(order[i].toLowerCase(), () => i);
    }
    final indexed = List.generate(items.length, (i) => i)
      ..sort((a, b) {
        final ra = rank[items[a].trim().toLowerCase()] ?? order.length;
        final rb = rank[items[b].trim().toLowerCase()] ?? order.length;
        final c = ra.compareTo(rb);
        return c != 0 ? c : a.compareTo(b);
      });
    return [for (final i in indexed) items[i]];
  }
}
