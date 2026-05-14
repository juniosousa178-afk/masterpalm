import 'package:flutter/material.dart';

/// Indicador de carregamento alinhado ao kit (Home / listas assíncronas).
class MasterLoading extends StatelessWidget {
  const MasterLoading({
    super.key,
    this.message,
    this.compact = false,
    this.boxed = false,
  });

  final String? message;
  final bool compact;
  /// Quando true, envolve o indicador num círculo suave (ex.: splash inicial).
  final bool boxed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    Widget indicator = SizedBox(
      width: compact ? 28 : 36,
      height: compact ? 28 : 36,
      child: CircularProgressIndicator(
        strokeWidth: compact ? 2.5 : 3,
        color: primary,
      ),
    );

    if (boxed) {
      indicator = Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: primary.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: indicator,
      );
    }

    if (message == null || message!.isEmpty) {
      return Center(child: indicator);
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          indicator,
          SizedBox(height: boxed ? 24 : 16),
          Text(
            message!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.65),
            ),
          ),
        ],
      ),
    );
  }
}
