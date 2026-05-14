import 'package:flutter/material.dart';

/// Cartão visual leve (MasterPalm UI Kit). Só apresentação — [onTap] é opcional.
class MasterCard extends StatelessWidget {
  const MasterCard({
    super.key,
    required this.child,
    this.onTap,
    this.backgroundColor,
    this.borderColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    this.borderRadius = 14,
  });

  final Widget child;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final Color? borderColor;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = backgroundColor ?? theme.colorScheme.surface;
    final radius = BorderRadius.circular(borderRadius);
    final decoration = BoxDecoration(
      color: bg,
      borderRadius: radius,
      border: borderColor != null
          ? Border.all(color: borderColor!, width: 1)
          : Border.all(
              color: theme.dividerColor.withOpacity(0.12),
              width: 1,
            ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.06),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ],
    );

    final content = Padding(
      padding: padding,
      child: child,
    );

    if (onTap == null) {
      return DecoratedBox(decoration: decoration, child: content);
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Ink(
          decoration: decoration,
          child: content,
        ),
      ),
    );
  }
}
