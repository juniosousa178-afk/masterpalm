import 'package:flutter/material.dart';

import '../../design_system/mp_tokens.dart';
import 'consignment_eligibility.dart';
import 'consignment_models.dart';
import 'consignment_service.dart';
import 'consignment_ui.dart';

/// Resolve search/list row back to the canonical loaded catalog item by immutable id.
/// Search is a filter over [catalog]; never use filtered index into another list.
ConsignmentPickerItem resolveConsignmentPickerSelection({
  required List<ConsignmentPickerItem> catalog,
  required ConsignmentPickerItem selected,
}) {
  for (final item in catalog) {
    if (item.productId == selected.productId) return item;
  }
  return selected;
}

/// Shared professional picker used by create + add-items flows.
Future<ConsignmentDraftLine?> pickConsignmentProductLine({
  required BuildContext context,
  required String lojaId,
}) async {
  List<ConsignmentPickerItem> catalog;
  try {
    catalog = await ConsignmentService.loadPickerProducts(lojaId);
  } catch (_) {
    catalog = const [];
  }
  if (!context.mounted) return null;
  if (catalog.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Nenhum produto disponível para consignação.')),
    );
    return null;
  }
  final selected = await showModalBottomSheet<ConsignmentPickerItem>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      var q = '';
      return StatefulBuilder(
        builder: (ctx, setModal) {
          final filtered = consignmentPickerVisibleItems(catalog, query: q);
          return SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.75,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Disponíveis para consignação', style: MpType.section),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    key: const Key('consignment_product_search'),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Buscar produto',
                    ),
                    onChanged: (v) => setModal(() => q = v),
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(child: Text('Nenhum produto disponível para consignação.'))
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final p = filtered[i];
                            final codeLabel = p.productCode.trim();
                            final availability = p.eligible
                                ? '${p.availableQty} disponíveis · ${consignmentMoney.format(p.price)}'
                                : p.unavailableReason;
                            return ListTile(
                              key: ValueKey('picker_${p.productId}'),
                              // Keep taps receivable when searching (incl. disabled/zero-stock rows)
                              // so operators get feedback instead of a silent no-op.
                              enabled: true,
                              textColor: p.eligible ? null : Theme.of(ctx).disabledColor,
                              title: Text(p.name),
                              subtitle: Text(
                                codeLabel.isEmpty
                                    ? availability
                                    : '$codeLabel · $availability',
                              ),
                              onTap: () {
                                if (!p.eligible) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        p.unavailableReason.isEmpty
                                            ? 'Produto indisponível para consignação.'
                                            : p.unavailableReason,
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                // Web: dismiss keyboard before pop so the gesture is not cancelled.
                                FocusManager.instance.primaryFocus?.unfocus();
                                final canonical = resolveConsignmentPickerSelection(
                                  catalog: catalog,
                                  selected: p,
                                );
                                Navigator.pop(ctx, canonical);
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
  if (selected == null || !context.mounted) return null;
  final canonical = resolveConsignmentPickerSelection(
    catalog: catalog,
    selected: selected,
  );
  if (!canonical.eligible) return null;
  var type = canonical.stockKind == 'variation' || canonical.stockKind == 'grade'
      ? canonical.stockKind
      : 'simple';
  var variation = const ConsignmentVariationKey();
  if (type == 'variation' || type == 'grade') {
    final picked = await pickConsignmentVariation(
      context: context,
      variacoes: canonical.variacoes,
      title: type == 'grade' ? 'Grade' : 'Variação',
    );
    if (picked == null) return null;
    variation = picked;
  }
  return ConsignmentDraftLine(
    productId: canonical.productId,
    productName: canonical.name,
    productType: type,
    qtySent: 1,
    unitSalePrice: canonical.price,
    variationKey: variation,
    expectedStockRevision: canonical.stockRevision,
  );
}

Future<ConsignmentVariationKey?> pickConsignmentVariation({
  required BuildContext context,
  required Map<String, dynamic> variacoes,
  String title = 'Variação',
}) async {
  int cellQty(dynamic value) {
    if (value is int) return value < 0 ? 0 : value;
    if (value is num) {
      final n = value.toInt();
      return n < 0 ? 0 : n;
    }
    if (value is Map) {
      var sum = 0;
      for (final e in value.entries) {
        final k = e.key.toString();
        if (k == 'custo' || k == '__custoUnitario') continue;
        if (e.value is num) {
          final n = (e.value as num).toInt();
          if (n > 0) sum += n;
        }
      }
      return sum;
    }
    return int.tryParse('$value') ?? 0;
  }

  int sizeQty(String s) {
    final cells = variacoes[s];
    if (cells is! Map) return 0;
    var sum = 0;
    for (final e in cells.entries) {
      final k = e.key.toString();
      if (k == 'custo' || k == '__custoUnitario') continue;
      sum += cellQty(e.value);
    }
    return sum;
  }

  final sizes = variacoes.keys
      .map((e) => e.toString())
      .where((s) => sizeQty(s) > 0)
      .toList();
  if (sizes.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Nenhuma variação com estoque disponível.')),
    );
    return null;
  }
  String? size = sizes.length == 1 ? sizes.first : null;
  String? color;
  List<String> colorsOf(String? s) {
    if (s == null) return const [];
    final cells = variacoes[s];
    if (cells is! Map) return const [];
    return cells.keys
        .map((e) => e.toString())
        .where((k) => k != 'custo' && k != '__custoUnitario' && cellQty(cells[k]) > 0)
        .toList();
  }

  if (size != null) {
    final colors = colorsOf(size);
    color = colors.length == 1 ? colors.first : null;
  }
  return showDialog<ConsignmentVariationKey>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: Text(title),
        content: StatefulBuilder(
          builder: (ctx, setLocal) {
            final colorKeys = colorsOf(size);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: size,
                  decoration: const InputDecoration(labelText: 'Tamanho'),
                  items: sizes
                      .map(
                        (s) => DropdownMenuItem(
                          value: s,
                          child: Text('$s (${sizeQty(s)})'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setLocal(() {
                    size = v;
                    color = null;
                    final colors = colorsOf(size);
                    if (colors.length == 1) color = colors.first;
                  }),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: colorKeys.contains(color) ? color : null,
                  decoration: InputDecoration(
                    labelText: title == 'Grade' ? 'Cor / opção' : 'Cor',
                  ),
                  items: colorKeys
                      .map(
                        (c) => DropdownMenuItem(
                          value: c,
                          child: Text('$c (${cellQty(variacoes[size]?[c])})'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setLocal(() => color = v),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              if (size == null || color == null) return;
              Navigator.pop(
                ctx,
                ConsignmentVariationKey(size: size!, color: color!),
              );
            },
            child: const Text('Usar'),
          ),
        ],
      );
    },
  );
}
