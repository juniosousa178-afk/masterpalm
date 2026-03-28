import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import '../utils/catalog_color_hex.dart';

String _catalogGroupTitlePt(String key) {
  switch (key) {
    case 'principal':
      return 'Ações e botões';
    case 'destaque':
      return 'Preço e chamadas';
    case 'texto':
      return 'Textos';
    case 'fundo':
      return 'Fundos e superfícies';
    default:
      return 'Outras';
  }
}

/// Cor sugerida com rótulo de origem (ex.: "Botão Comprar – fundo · Preço").
/// [group] opcional: `principal` | `destaque` | `texto` | `fundo` | `outro` (agrupamento só de UX).
@immutable
class CatalogColorSuggestion {
  const CatalogColorSuggestion({
    required this.color,
    required this.originLabel,
    this.group,
  });

  final Color color;
  final String originLabel;

  /// Chave de agrupamento para o editor (sugestões). Null = tratado como `outro`.
  final String? group;
}

/// Editor de cor reutilizável: preview, hex manual, picker e sugestões do catálogo.
class CatalogColorFieldEditor extends StatefulWidget {
  const CatalogColorFieldEditor({
    super.key,
    required this.label,
    this.description,
    required this.color,
    required this.onColorChanged,
    this.suggestions = const [],
    this.maxSuggestions = 16,
  });

  final String label;
  final String? description;
  final Color color;
  final ValueChanged<Color> onColorChanged;
  final List<CatalogColorSuggestion> suggestions;
  final int maxSuggestions;

  @override
  State<CatalogColorFieldEditor> createState() => _CatalogColorFieldEditorState();
}

class _CatalogColorFieldEditorState extends State<CatalogColorFieldEditor> {
  late final TextEditingController _hexCtrl;
  String? _hexError;

  @override
  void initState() {
    super.initState();
    _hexCtrl = TextEditingController(text: formatCatalogHexRgb(widget.color));
  }

  @override
  void didUpdateWidget(covariant CatalogColorFieldEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.color != widget.color) {
      final next = formatCatalogHexRgb(widget.color);
      if (_hexError == null || tryParseCatalogHex(_hexCtrl.text) == widget.color) {
        _hexCtrl.text = next;
        _hexCtrl.selection = TextSelection.collapsed(offset: next.length);
      }
    }
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  void _applyHexInput() {
    final parsed = tryParseCatalogHex(_hexCtrl.text);
    setState(() {
      if (parsed == null) {
        _hexError = 'Hex inválido. Use #RRGGBB ou #AARRGGBB.';
      } else {
        _hexError = null;
        widget.onColorChanged(parsed);
        _hexCtrl.text = formatCatalogHexRgb(parsed);
        _hexCtrl.selection = TextSelection.collapsed(offset: _hexCtrl.text.length);
      }
    });
  }

  void _copyHexAndFeedback(String hex) {
    Clipboard.setData(ClipboardData(text: hex));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('HEX copiado'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
        margin: EdgeInsets.all(12),
      ),
    );
  }

  /// Copia o hex do campo se válido; senão o valor atual aplicado do widget.
  void _copyCurrentHexFromFieldOrWidget() {
    final parsed = tryParseCatalogHex(_hexCtrl.text);
    final c = parsed ?? widget.color;
    _copyHexAndFeedback(formatCatalogHexRgb(c));
  }

  void _showSuggestionUsesDialog(CatalogColorSuggestion s) {
    final hex = formatCatalogHexRgb(s.color);
    final uses = s.originLabel
        .split('·')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Onde esta cor é usada'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: s.color,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Theme.of(ctx).colorScheme.outline.withValues(alpha: 0.35)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SelectableText(
                      hex,
                      style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Usada em:',
                style: Theme.of(ctx).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              for (final u in uses)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('• ', style: TextStyle(color: Theme.of(ctx).colorScheme.primary)),
                      Expanded(child: Text(u)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
          TextButton(
            onPressed: () {
              _copyHexAndFeedback(hex);
            },
            child: const Text('Copiar HEX'),
          ),
          FilledButton(
            onPressed: () {
              widget.onColorChanged(s.color);
              setState(() {
                _hexError = null;
                _hexCtrl.text = hex;
              });
              Navigator.pop(ctx);
            },
            child: const Text('Usar neste campo'),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSuggestionGroups(
    List<CatalogColorSuggestion> suggestions,
    ColorScheme cs,
    TextTheme tt,
    Color accentRose,
  ) {
    if (suggestions.isEmpty) return [];

    Widget chipRow(CatalogColorSuggestion s) {
      final hex = formatCatalogHexRgb(s.color);
      return Padding(
        padding: const EdgeInsets.only(right: 2, bottom: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: s.originLabel,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    widget.onColorChanged(s.color);
                    setState(() {
                      _hexError = null;
                      _hexCtrl.text = hex;
                    });
                  },
                  onLongPress: () => _showSuggestionUsesDialog(s),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: s.color,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: cs.outline.withValues(alpha: 0.4)),
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Copiar HEX',
              icon: Icon(Icons.content_copy_outlined, size: 17, color: cs.onSurfaceVariant),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: () => _copyHexAndFeedback(hex),
            ),
            IconButton(
              tooltip: 'Onde é usada',
              icon: Icon(Icons.info_outline, size: 18, color: accentRose.withValues(alpha: 0.95)),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: () => _showSuggestionUsesDialog(s),
            ),
          ],
        ),
      );
    }

    final hasGroup = suggestions.any((s) => s.group != null && s.group!.isNotEmpty);
    if (!hasGroup) {
      return [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [for (final s in suggestions) chipRow(s)],
        ),
      ];
    }

    const order = ['principal', 'destaque', 'texto', 'fundo', 'outro'];
    final map = <String, List<CatalogColorSuggestion>>{};
    for (final s in suggestions) {
      final g = s.group ?? 'outro';
      map.putIfAbsent(g, () => []).add(s);
    }

    final out = <Widget>[];
    for (final key in order) {
      if (!map.containsKey(key)) continue;
      out.add(
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: Row(
            children: [
              Icon(Icons.label_outline, size: 14, color: accentRose.withValues(alpha: 0.9)),
              const SizedBox(width: 6),
              Text(
                _catalogGroupTitlePt(key),
                style: tt.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface.withValues(alpha: 0.88),
                ),
              ),
            ],
          ),
        ),
      );
      out.add(
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [for (final s in map[key]!) chipRow(s)],
        ),
      );
    }
    return out;
  }

  void _openPicker() {
    var temp = widget.color;
    final hexPickerCtrl = TextEditingController(text: formatCatalogHexRgb(temp));

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          widget.label,
          style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ColorPicker(
                pickerColor: temp,
                onColorChanged: (c) => temp = c,
                labelTypes: const [],
                pickerAreaHeightPercent: 0.72,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: hexPickerCtrl,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Hex',
                  hintText: '#RRGGBB',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  isDense: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]*')),
                  LengthLimitingTextInputFormatter(10),
                ],
                onChanged: (t) {
                  final p = tryParseCatalogHex(t);
                  if (p != null) temp = p;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final fromField = tryParseCatalogHex(hexPickerCtrl.text);
              final chosen = fromField ?? temp;
              widget.onColorChanged(chosen);
              setState(() {
                _hexError = null;
                _hexCtrl.text = formatCatalogHexRgb(chosen);
              });
              Navigator.of(ctx).pop();
            },
            child: const Text('Aplicar'),
          ),
        ],
      ),
    ).then((_) => hexPickerCtrl.dispose());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final borderColor = cs.outlineVariant.withValues(alpha: 0.65);
    const accentRose = Color(0xFFC9A4A8);
    final suggestions = widget.suggestions.take(widget.maxSuggestions).toList();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Tooltip(
                  message: formatCatalogHexRgb(widget.color),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: widget.color,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: cs.outline.withValues(alpha: 0.35), width: 1.2),
                      boxShadow: [
                        BoxShadow(
                          color: widget.color.withValues(alpha: 0.35),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.label,
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.15,
                          color: cs.onSurface,
                        ),
                      ),
                      if (widget.description != null && widget.description!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          widget.description!,
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant.withValues(alpha: 0.92),
                            height: 1.35,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              formatCatalogHexRgb(widget.color),
                              style: tt.labelSmall?.copyWith(
                                fontFamily: 'monospace',
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Copiar HEX',
                            icon: Icon(Icons.content_copy_outlined, size: 18, color: cs.onSurfaceVariant),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            onPressed: () => _copyHexAndFeedback(formatCatalogHexRgb(widget.color)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: _openPicker,
                  tooltip: 'Seletor visual',
                  style: IconButton.styleFrom(
                    backgroundColor: accentRose.withValues(alpha: 0.22),
                    foregroundColor: cs.onSurface,
                  ),
                  icon: const Icon(Icons.palette_outlined, size: 22),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _hexCtrl,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
                color: cs.onSurface,
              ),
              decoration: InputDecoration(
                labelText: 'Código da cor',
                hintText: '#RRGGBB ou #AARRGGBB',
                errorText: _hexError,
                isDense: true,
                prefixIcon: Icon(Icons.tag, size: 20, color: cs.onSurfaceVariant),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Copiar HEX do campo',
                      icon: Icon(Icons.content_copy_outlined, size: 20, color: cs.onSurfaceVariant),
                      onPressed: _copyCurrentHexFromFieldOrWidget,
                    ),
                    IconButton(
                      tooltip: 'Aplicar hex',
                      icon: Icon(Icons.check_rounded, color: cs.primary),
                      onPressed: _applyHexInput,
                    ),
                  ],
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: borderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: cs.primary.withValues(alpha: 0.85), width: 1.5),
                ),
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]*')),
                LengthLimitingTextInputFormatter(10),
              ],
              onSubmitted: (_) => _applyHexInput,
            ),
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(Icons.auto_awesome_outlined, size: 16, color: accentRose.withValues(alpha: 0.95)),
                  const SizedBox(width: 6),
                  Text(
                    'Cores já usadas no catálogo',
                    style: tt.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface.withValues(alpha: 0.88),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Quadrado: aplicar no campo · ícones: copiar HEX ou ver onde é usada.',
                style: tt.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.85),
                  fontSize: 11.5,
                ),
              ),
              const SizedBox(height: 8),
              ..._buildSuggestionGroups(suggestions, cs, tt, accentRose),
            ],
          ],
        ),
      ),
    );
  }
}
