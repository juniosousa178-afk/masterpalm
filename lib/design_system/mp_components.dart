// M3.8 Sprint 2 — componentes reutilizáveis do Design System.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'mp_tokens.dart';

class MpCard extends StatelessWidget {
  const MpCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(MpSpacing.lg),
    this.onTap,
    this.color = MpColors.surface,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(MpRadius.md),
        border: Border.all(color: borderColor ?? MpColors.border),
        boxShadow: [
          BoxShadow(
            color: MpColors.ink.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(MpRadius.md),
        child: card,
      ),
    );
  }
}

class MpSectionHeader extends StatelessWidget {
  const MpSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: MpSpacing.sm, top: MpSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title.toUpperCase(), style: MpType.section),
                if (subtitle != null && subtitle!.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, style: MpType.caption),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class MpStatCard extends StatelessWidget {
  const MpStatCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.accent = MpColors.primary,
    this.subtitle,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color accent;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return MpCard(
      padding: const EdgeInsets.all(MpSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(MpRadius.sm),
                  ),
                  child: Icon(icon, size: 18, color: accent),
                ),
                const SizedBox(width: MpSpacing.sm),
              ],
              Expanded(child: Text(label, style: MpType.kpiLabel)),
            ],
          ),
          const SizedBox(height: MpSpacing.sm),
          Text(value, style: MpType.kpiValue),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: MpType.caption),
          ],
        ],
      ),
    );
  }
}

enum MpBadgeTone { neutral, success, warning, danger, info, marketing }

class MpBadge extends StatelessWidget {
  const MpBadge({
    super.key,
    required this.label,
    this.tone = MpBadgeTone.neutral,
  });

  final String label;
  final MpBadgeTone tone;

  Color get _fg {
    switch (tone) {
      case MpBadgeTone.success:
        return MpColors.success;
      case MpBadgeTone.warning:
        return MpColors.warning;
      case MpBadgeTone.danger:
        return MpColors.danger;
      case MpBadgeTone.info:
        return MpColors.info;
      case MpBadgeTone.marketing:
        return MpColors.marketing;
      case MpBadgeTone.neutral:
        return MpColors.inkMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fg = _fg;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: fg.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

class MpPrimaryButton extends StatelessWidget {
  const MpPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expanded = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final child = icon == null
        ? Text(label)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Text(label),
            ],
          );
    final btn = FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: MpColors.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MpRadius.sm),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      child: child,
    );
    return expanded ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

class MpSecondaryButton extends StatelessWidget {
  const MpSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon ?? Icons.chevron_right, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: MpColors.ink,
        side: const BorderSide(color: MpColors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MpRadius.sm),
        ),
      ),
    );
  }
}

class MpSearchField extends StatelessWidget {
  const MpSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.hintText = 'Pesquisar…',
    this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        isDense: true,
        hintText: hintText,
        filled: true,
        fillColor: MpColors.surface,
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () {
                  controller.clear();
                  onClear?.call();
                  onChanged('');
                },
              ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MpRadius.md),
          borderSide: const BorderSide(color: MpColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MpRadius.md),
          borderSide: const BorderSide(color: MpColors.border),
        ),
      ),
    );
  }
}

class MpFilterChips<T> extends StatelessWidget {
  const MpFilterChips({
    super.key,
    required this.options,
    required this.value,
    required this.labelOf,
    required this.onChanged,
  });

  final List<T> options;
  final T value;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final o in options) ...[
            Padding(
              padding: const EdgeInsets.only(right: MpSpacing.sm),
              child: ChoiceChip(
                label: Text(labelOf(o)),
                selected: o == value,
                onSelected: (_) => onChanged(o),
                selectedColor: MpColors.primary.withOpacity(0.18),
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: o == value ? MpColors.primary : MpColors.inkMuted,
                ),
                side: BorderSide(
                  color: o == value ? MpColors.primary : MpColors.border,
                ),
                backgroundColor: MpColors.chipBg,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class MpLoadingState extends StatelessWidget {
  const MpLoadingState({super.key, this.message = 'Carregando…'});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: MpColors.primary),
          const SizedBox(height: MpSpacing.md),
          Text(message, style: MpType.caption),
        ],
      ),
    );
  }
}

class MpEmptyState extends StatelessWidget {
  const MpEmptyState({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(MpSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: MpColors.inkMuted.withOpacity(0.5)),
            const SizedBox(height: MpSpacing.md),
            Text(title, style: MpType.title, textAlign: TextAlign.center),
            if (subtitle != null) ...[
              const SizedBox(height: MpSpacing.sm),
              Text(subtitle!, style: MpType.caption, textAlign: TextAlign.center),
            ],
            if (action != null) ...[
              const SizedBox(height: MpSpacing.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class MpErrorState extends StatelessWidget {
  const MpErrorState({
    super.key,
    required this.message,
    this.onRetry,
  });

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(MpSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: MpColors.danger),
            const SizedBox(height: MpSpacing.md),
            Text(message, style: MpType.body, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: MpSpacing.lg),
              MpPrimaryButton(
                label: 'Tentar novamente',
                icon: Icons.refresh,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class MpRestrictedAccessState extends StatelessWidget {
  const MpRestrictedAccessState({
    super.key,
    required this.title,
    required this.subtitle,
    this.onBack,
    this.onRetry,
    this.onUnderstand,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onBack;
  final VoidCallback? onRetry;
  final VoidCallback? onUnderstand;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(MpSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline,
                size: 56, color: MpColors.warning.withOpacity(0.8)),
            const SizedBox(height: MpSpacing.md),
            Text(title, style: MpType.title, textAlign: TextAlign.center),
            const SizedBox(height: MpSpacing.sm),
            Text(subtitle, style: MpType.caption, textAlign: TextAlign.center),
            const SizedBox(height: MpSpacing.lg),
            Wrap(
              spacing: MpSpacing.sm,
              runSpacing: MpSpacing.sm,
              alignment: WrapAlignment.center,
              children: [
                if (onBack != null)
                  MpSecondaryButton(
                    label: 'Voltar',
                    icon: Icons.arrow_back,
                    onPressed: onBack,
                  ),
                if (onRetry != null)
                  MpPrimaryButton(
                    label: 'Tentar novamente',
                    icon: Icons.refresh,
                    onPressed: onRetry,
                  ),
                if (onUnderstand != null)
                  MpSecondaryButton(
                    label: 'Entenda',
                    icon: Icons.info_outline,
                    onPressed: onUnderstand,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class MpInfoBanner extends StatelessWidget {
  const MpInfoBanner({
    super.key,
    required this.message,
    this.onAction,
    this.actionLabel = 'Entenda',
  });

  final String message;
  final VoidCallback? onAction;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    return MpCard(
      borderColor: MpColors.warning.withOpacity(0.4),
      color: MpColors.warning.withOpacity(0.08),
      padding: const EdgeInsets.symmetric(
        horizontal: MpSpacing.md,
        vertical: MpSpacing.sm,
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: MpColors.warning, size: 20),
          const SizedBox(width: MpSpacing.sm),
          Expanded(child: Text(message, style: MpType.caption)),
          if (onAction != null)
            TextButton(
              onPressed: onAction,
              child: Text(actionLabel),
            ),
        ],
      ),
    );
  }
}


class MpSuccessSnack {
  static void show(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: MpColors.success,
      ),
    );
  }
}

Future<void> mpCopyToClipboard(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) {
    MpSuccessSnack.show(context, 'Copiado');
  }
}

class MpModuleTile extends StatelessWidget {
  const MpModuleTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MpCard(
      onTap: onTap,
      padding: const EdgeInsets.all(MpSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withOpacity(0.14),
              borderRadius: BorderRadius.circular(MpRadius.sm),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const Spacer(),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: MpColors.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: MpType.caption,
          ),
        ],
      ),
    );
  }
}

class MpDataTableShell extends StatelessWidget {
  const MpDataTableShell({
    super.key,
    required this.columns,
    required this.rows,
  });

  final List<DataColumn> columns;
  final List<DataRow> rows;

  @override
  Widget build(BuildContext context) {
    return MpCard(
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(MpColors.chipBg),
          columns: columns,
          rows: rows,
        ),
      ),
    );
  }
}
