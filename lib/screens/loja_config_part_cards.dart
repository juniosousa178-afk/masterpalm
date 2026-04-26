// Cartões, banners e overlays visuais da Loja Config (part da mesma library).
// Etapa 2 blast-radius: UI pura com dados/callbacks vindos do State.

part of 'loja_config_screen.dart';

class _LojaConfigModulePaneErrorBanner extends StatelessWidget {
  const _LojaConfigModulePaneErrorBanner({
    required this.messages,
    required this.colorScheme,
  });

  final List<String> messages;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) return const SizedBox.shrink();

    final cs = colorScheme;
    final onErr = cs.onErrorContainer;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: cs.errorContainer.withOpacity(0.55),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.report_outlined,
                size: 22,
                color: onErr.withOpacity(0.88),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ajustes necessários',
                      style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: onErr,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (var i = 0; i < messages.length; i++) ...[
                      if (i > 0) const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '·',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: onErr.withOpacity(0.75),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              messages[i],
                              style: tt.bodyMedium?.copyWith(
                                fontSize: 13.5,
                                height: 1.38,
                                color: onErr.withOpacity(0.94),
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LojaConfigUrlCard extends StatelessWidget {
  const _LojaConfigUrlCard({
    required this.urlPublica,
    required this.primaryColor,
    required this.onCopy,
    this.label,
    this.subtitle,
  });

  final String urlPublica;
  final Color primaryColor;
  final Future<void> Function() onCopy;
  final String? label;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final displayLabel = label ?? 'URL pública da sua loja';
    final displaySubtitle = subtitle;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                displaySubtitle != null ? Icons.lightbulb_outline : Icons.link,
                color: primaryColor,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayLabel,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  if (displaySubtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      displaySubtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  SelectableText(
                    urlPublica,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copiar'),
              onPressed: () => onCopy(),
            ),
          ],
        ),
      ),
    );
  }
}

class _LojaConfigFreeLimitedPlanBanner extends StatelessWidget {
  const _LojaConfigFreeLimitedPlanBanner({
    required this.colorScheme,
    required this.onPlanos,
  });

  final ColorScheme colorScheme;
  final VoidCallback onPlanos;

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    return Material(
      color: cs.primaryContainer.withOpacity(0.4),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, color: cs.primary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Catálogo básico: pedidos pelo WhatsApp. Você pode editar identidade, mídias e publicar. '
                'Temas, layout avançado, fretes/cupons e checkout online exigem upgrade.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: cs.onSurface.withOpacity(0.88),
                ),
              ),
            ),
            TextButton(
              onPressed: onPlanos,
              child: const Text('Planos'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LojaConfigBasicPlanBanner extends StatelessWidget {
  const _LojaConfigBasicPlanBanner({
    required this.colorScheme,
    required this.onPlanos,
  });

  final ColorScheme colorScheme;
  final VoidCallback onPlanos;

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    return Material(
      color: cs.secondaryContainer.withOpacity(0.35),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.palette_outlined, color: cs.secondary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Plano Básico: personalize tema, layout e menu. Checkout online e taxas avançadas liberam no Intermediário.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: cs.onSurface.withOpacity(0.88),
                ),
              ),
            ),
            TextButton(
              onPressed: onPlanos,
              child: const Text('Planos'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LojaConfigFreeLimitedLockedPaneBody extends StatelessWidget {
  const _LojaConfigFreeLimitedLockedPaneBody({
    required this.colorScheme,
    required this.onPlanos,
    required this.onVoltarModulos,
  });

  final ColorScheme colorScheme;
  final VoidCallback onPlanos;
  final VoidCallback onVoltarModulos;

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline_rounded,
              size: 52, color: cs.primary.withOpacity(0.85)),
          const SizedBox(height: 16),
          Text(
            'Módulo indisponível no plano gratuito',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Text(
            'No plano gratuito limitado use Identidade, Mídias e Publicação do catálogo. '
            'O catálogo público recebe pedidos pelo WhatsApp.',
            textAlign: TextAlign.center,
            style:
                TextStyle(color: cs.onSurface.withOpacity(0.72), height: 1.35),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: onPlanos,
            icon: const Icon(Icons.workspace_premium_outlined),
            label: const Text('Ver planos'),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: onVoltarModulos,
            child: const Text('Voltar aos módulos'),
          ),
        ],
      ),
    );
  }
}

class _LojaConfigTutorialOverlay extends StatelessWidget {
  const _LojaConfigTutorialOverlay({
    required this.primaryColor,
    required this.title,
    required this.body,
    required this.icon,
    required this.stepIndex,
    required this.totalSteps,
    required this.onPular,
    required this.onProximo,
    required this.onConcluir,
  });

  final Color primaryColor;
  final String title;
  final String body;
  final IconData icon;
  final int stepIndex;
  final int totalSteps;
  final VoidCallback onPular;
  final VoidCallback onProximo;
  final VoidCallback onConcluir;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 24,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: primaryColor.withOpacity(0.3)),
            boxShadow: [
              BoxShadow(
                color: primaryColor.withOpacity(0.2),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: primaryColor, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '${stepIndex + 1} de $totalSteps',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                body,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: onPular,
                    child: const Text('Pular tutorial'),
                  ),
                  const SizedBox(width: 8),
                  if (stepIndex < totalSteps - 1)
                    FilledButton(
                      onPressed: onProximo,
                      child: const Text('Próximo'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: onConcluir,
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Entendi'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
