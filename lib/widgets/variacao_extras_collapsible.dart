// Lista longa de opções extras (letras, estampas): colapsa visual + lista com busca.

import 'package:flutter/material.dart';

import '../core/produto_variacao_extra.dart';

/// Quantidade padrão de chips visíveis antes de "Mostrar mais".
const int kVariacaoExtrasVisiveisInicial = 12;

/// Wrap de opções com limite visual e ações "Mostrar mais" / lista completa com busca.
class VariacaoExtrasCollapsible extends StatefulWidget {
  const VariacaoExtrasCollapsible({
    super.key,
    required this.options,
    required this.itemBuilder,
    required this.onOptionChosen,
    this.selectedValue,
    this.maxInitiallyVisible = kVariacaoExtrasVisiveisInicial,
    this.spacing = 10,
    this.runSpacing = 10,
    this.showListButtonWhenLong = true,
  });

  final List<String> options;
  final Widget Function(BuildContext context, String option, int index) itemBuilder;
  final ValueChanged<String> onOptionChosen;
  final String? selectedValue;
  final int maxInitiallyVisible;
  final double spacing;
  final double runSpacing;
  final bool showListButtonWhenLong;

  @override
  State<VariacaoExtrasCollapsible> createState() =>
      _VariacaoExtrasCollapsibleState();
}

class _VariacaoExtrasCollapsibleState extends State<VariacaoExtrasCollapsible> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = _shouldStartExpanded();
  }

  @override
  void didUpdateWidget(VariacaoExtrasCollapsible oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.options != widget.options ||
        oldWidget.selectedValue != widget.selectedValue ||
        oldWidget.maxInitiallyVisible != widget.maxInitiallyVisible) {
      _expanded = _shouldStartExpanded();
    }
  }

  int _indexOfSelection() {
    final sel = widget.selectedValue?.trim() ?? '';
    if (sel.isEmpty) return -1;
    final i = widget.options.indexWhere((o) => o == sel);
    if (i >= 0) return i;
    return widget.options.indexWhere((o) => ProdutoVariacaoExtra.keysMatch(o, sel));
  }

  bool _shouldStartExpanded() {
    final idx = _indexOfSelection();
    return idx >= widget.maxInitiallyVisible && idx >= 0;
  }

  Future<void> _abrirListaCompleta(BuildContext context) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _VariacaoExtraSearchSheet(
        options: widget.options,
        selected: widget.selectedValue,
      ),
    );
    if (picked != null && picked.isNotEmpty) {
      widget.onOptionChosen(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.options.length;
    final max = widget.maxInitiallyVisible;
    if (n == 0) return const SizedBox.shrink();

    if (n <= max) {
      return Wrap(
        spacing: widget.spacing,
        runSpacing: widget.runSpacing,
        children: [
          for (var i = 0; i < n; i++)
            widget.itemBuilder(context, widget.options[i], i),
        ],
      );
    }

    final visible = _expanded ? n : max;
    final restantes = n - max;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: widget.spacing,
          runSpacing: widget.runSpacing,
          children: [
            for (var i = 0; i < visible; i++)
              widget.itemBuilder(context, widget.options[i], i),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton.icon(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                size: 20,
              ),
              label: Text(
                _expanded
                    ? 'Mostrar menos'
                    : 'Mostrar mais ($restantes)',
              ),
            ),
            if (widget.showListButtonWhenLong)
              OutlinedButton.icon(
                onPressed: () => _abrirListaCompleta(context),
                icon: const Icon(Icons.list_alt, size: 18),
                label: const Text('Lista completa'),
              ),
          ],
        ),
      ],
    );
  }
}

class _VariacaoExtraSearchSheet extends StatefulWidget {
  const _VariacaoExtraSearchSheet({
    required this.options,
    this.selected,
  });

  final List<String> options;
  final String? selected;

  @override
  State<_VariacaoExtraSearchSheet> createState() =>
      _VariacaoExtraSearchSheetState();
}

class _VariacaoExtraSearchSheetState extends State<_VariacaoExtraSearchSheet> {
  final _controller = TextEditingController();
  late List<String> _filtered;

  @override
  void initState() {
    super.initState();
    _filtered = List<String>.from(widget.options);
    _controller.addListener(_filtrar);
  }

  @override
  void dispose() {
    _controller.removeListener(_filtrar);
    _controller.dispose();
    super.dispose();
  }

  void _filtrar() {
    final q = _controller.text.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filtered = List<String>.from(widget.options);
      } else {
        _filtered = widget.options
            .where((o) => o.toLowerCase().contains(q))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final h = MediaQuery.sizeOf(context).height;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: (h * 0.62).clamp(320.0, 560.0),
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Buscar variação…',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      isDense: true,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _filtered.length,
                    itemBuilder: (context, i) {
                      final op = _filtered[i];
                      final sel = widget.selected != null &&
                          ProdutoVariacaoExtra.keysMatch(
                              op, widget.selected!);
                      return ListTile(
                        title: Text(
                          op,
                          style: TextStyle(
                            fontWeight:
                                sel ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                        trailing: sel
                            ? Icon(Icons.check, color: theme.colorScheme.primary)
                            : null,
                        onTap: () => Navigator.pop(context, op),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
