import 'package:flutter/material.dart';

enum MasterButtonVariant { filled, outlined, text }

/// Botão consistente com o kit (uso em ações secundárias na Home, ex.: retry).
class MasterButton extends StatelessWidget {
  const MasterButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.variant = MasterButtonVariant.filled,
  });

  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;
  final MasterButtonVariant variant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    switch (variant) {
      case MasterButtonVariant.filled:
        if (icon != null) {
          return FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 18),
            label: Text(label),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
        return FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(label),
        );
      case MasterButtonVariant.outlined:
        if (icon != null) {
          return OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 18, color: primary),
            label: Text(label),
            style: OutlinedButton.styleFrom(
              foregroundColor: primary,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
        return OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: primary,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(label),
        );
      case MasterButtonVariant.text:
        return TextButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 18, color: primary),
          label: Text(label),
        );
    }
  }
}
