import 'package:flutter/material.dart';

import '../catalog/domain/catalog_custom_domain.dart';

/// Decoração de campo alinhada à LojaConfigScreen.
typedef CatalogDomainInputDecorationFn = InputDecoration Function(
  BuildContext context, {
  required String labelText,
  String? helperText,
  int? helperMaxLines,
  Widget? prefixIcon,
});

/// Seção “Domínio próprio” na configuração de identidade / catálogo.
class CatalogDomainSection extends StatelessWidget {
  const CatalogDomainSection({
    super.key,
    required this.colorScheme,
    required this.textTheme,
    required this.domainController,
    required this.statusKey,
    this.expectedTarget,
    this.lastCheckLabel,
    this.dnsObserved,
    this.friendlyError,
    required this.fieldStyle,
    required this.decorate,
    required this.primaryColor,
    required this.onAddDomain,
    required this.onOpenGuide,
  });

  final ColorScheme colorScheme;
  final TextTheme textTheme;
  final TextEditingController domainController;
  final String statusKey;
  /// Alvo CNAME esperado (quando conhecido).
  final String? expectedTarget;
  final String? lastCheckLabel;
  final String? dnsObserved;
  final String? friendlyError;
  final TextStyle Function(BuildContext context) fieldStyle;
  final CatalogDomainInputDecorationFn decorate;
  final Color primaryColor;
  final Future<void> Function() onAddDomain;
  final Future<void> Function() onOpenGuide;

  (Color bg, Color fg) _statusColors() {
    final cs = colorScheme;
    return switch (statusKey) {
      kDominioStatusAtivo => (
          Colors.green.withOpacity(0.14),
          Colors.green.shade800,
        ),
      kDominioStatusDnsOk => (
          Colors.teal.withOpacity(0.14),
          Colors.teal.shade800,
        ),
      kDominioStatusEmVerificacao => (
          cs.primary.withOpacity(0.14),
          cs.primary,
        ),
      kDominioStatusPendenteDns => (
          cs.tertiary.withOpacity(0.16),
          cs.tertiary,
        ),
      kDominioStatusSolicitado => (
          cs.secondary.withOpacity(0.16),
          cs.secondary,
        ),
      kDominioStatusPendente => (
          cs.tertiary.withOpacity(0.16),
          cs.tertiary,
        ),
      kDominioStatusErro => (
          cs.error.withOpacity(0.14),
          cs.error,
        ),
      _ => (
          cs.surfaceContainerHighest.withOpacity(0.9),
          cs.onSurfaceVariant,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _statusColors();
    final statusLabel = dominioStatusLabelPt(statusKey);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.language_rounded, color: primaryColor, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Status do domínio',
                style: textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: fg.withOpacity(0.35)),
              ),
              child: Text(
                statusLabel,
                style: textTheme.labelLarge?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        TextField(
          controller: domainController,
          style: fieldStyle(context),
          decoration: decorate(
            context,
            labelText: 'Domínio desejado para o catálogo',
            helperText:
                'Ex.: nathypratasefolheados.com.br ou catalogo.sualoja.com.br — sem https://',
            helperMaxLines: 2,
            prefixIcon: const Icon(Icons.link_rounded),
          ),
          textInputAction: TextInputAction.done,
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: () => onAddDomain(),
              icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
              label: const Text('Adicionar domínio'),
              style: FilledButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            TextButton.icon(
              onPressed: () => onOpenGuide(),
              icon: Icon(Icons.menu_book_outlined, color: primaryColor, size: 20),
              label: Text(
                'Ver passo a passo',
                style: TextStyle(
                  color: primaryColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (expectedTarget != null && expectedTarget!.trim().isNotEmpty) ...[
          Text(
            'Alvo esperado (CNAME): ${expectedTarget!.trim()}',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.35,
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
        ],
        if (lastCheckLabel != null && lastCheckLabel!.trim().isNotEmpty) ...[
          Text(
            'Última verificação: ${lastCheckLabel!.trim()}',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 6),
        ],
        if (dnsObserved != null && dnsObserved!.trim().isNotEmpty) ...[
          Text(
            'DNS observado: ${dnsObserved!.trim()}',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.35,
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
        ],
        if (friendlyError != null && friendlyError!.trim().isNotEmpty) ...[
          Text(
            friendlyError!.trim(),
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.error,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 6),
        ],
        Text(
          'O host final do catálogo será catalogo.seudominio quando você informar só o domínio raiz. '
          'O registro DNS continua manual no provedor; a verificação e a ativação do catálogo são feitas com segurança no servidor.',
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
