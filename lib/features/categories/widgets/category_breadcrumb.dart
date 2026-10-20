import 'package:flutter/material.dart';

/// "Início > Feminino > Religioso > Anéis" com quebra de linha (nunca corta em telas estreitas).
/// [onTapLevel]: -1 = início; 0..n-1 = nível do caminho.
class CategoryBreadcrumb extends StatelessWidget {
  const CategoryBreadcrumb({
    super.key,
    required this.names,
    this.rootLabel = 'Início',
    this.onTapLevel,
    this.trailing,
    this.style,
    this.activeColor,
  });

  final List<String> names;
  final String? rootLabel;
  final ValueChanged<int>? onTapLevel;

  /// Segmento extra no fim (ex.: "+" indicando onde a nova categoria será criada).
  final String? trailing;
  final TextStyle? style;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = style ?? theme.textTheme.bodyMedium ?? const TextStyle();
    final muted = base.copyWith(color: (base.color ?? theme.colorScheme.onSurface).withValues(alpha: 0.72));
    final strong = base.copyWith(
      fontWeight: FontWeight.w700,
      color: activeColor ?? base.color ?? theme.colorScheme.onSurface,
    );
    final segments = <(String, int)>[
      if (rootLabel != null) (rootLabel!, -1),
      for (var i = 0; i < names.length; i++) (names[i], i),
    ];
    final children = <Widget>[];
    for (var i = 0; i < segments.length; i++) {
      final (label, level) = segments[i];
      final isLast = i == segments.length - 1 && trailing == null;
      final text = Text(label, style: isLast ? strong : muted, softWrap: true);
      children.add(onTapLevel != null && !isLast
          ? InkWell(
              key: ValueKey('category_breadcrumb_$level'),
              borderRadius: BorderRadius.circular(6),
              onTap: () => onTapLevel!(level),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                child: text,
              ),
            )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              child: text,
            ));
      if (i < segments.length - 1 || trailing != null) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text('>', style: muted),
        ));
      }
    }
    if (trailing != null) {
      children.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Text(trailing!, style: strong),
      ));
    }
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 2,
      children: children,
    );
  }
}
