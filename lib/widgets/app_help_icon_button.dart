import 'package:flutter/material.dart';

/// Abre a tela de ajuda do app (`/ajuda`). Use nas `actions` do [AppBar].
class AppHelpIconButton extends StatelessWidget {
  const AppHelpIconButton({
    super.key,
    this.color,
    this.iconColor,
    this.tooltip = 'Ajuda',
  });

  final Color? color;
  final Color? iconColor;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = iconColor ?? color ?? cs.onSurface;
    return IconButton(
      icon: Icon(Icons.help_outline, color: fg),
      tooltip: tooltip,
      onPressed: () => Navigator.pushNamed(context, '/ajuda'),
    );
  }
}
