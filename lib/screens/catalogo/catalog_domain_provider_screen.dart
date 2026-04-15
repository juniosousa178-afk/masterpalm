import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/domain_provider_guide.dart';

/// Tela de passo a passo específica de um provedor de DNS.
class CatalogDomainProviderScreen extends StatelessWidget {
  const CatalogDomainProviderScreen({
    super.key,
    required this.guide,
    required this.recommendedFqdn,
    required this.recordType,
    required this.recordName,
    required this.cnameTarget,
  });

  final DomainProviderGuide guide;
  final String recommendedFqdn;
  final String recordType;
  final String recordName;
  final String cnameTarget;

  Future<void> _copy(BuildContext context, String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copiado.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(guide.title),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text(
            guide.shortDescription,
            style: tt.bodyLarge?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 20),
          _DnsFillCard(
            cs: cs,
            tt: tt,
            recommendedFqdn: recommendedFqdn,
            recordType: recordType,
            recordName: recordName,
            cnameTarget: cnameTarget,
            onCopy: (l, v) => _copy(context, l, v),
          ),
          const SizedBox(height: 20),
          Text(
            'Passo a passo',
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < guide.steps.length; i++) ...[
            _NumberedStep(index: i + 1, text: guide.steps[i], cs: cs, tt: tt),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 8),
          _AlertCard(
            icon: Icons.info_outline_rounded,
            title: 'Observações importantes',
            lines: guide.notes,
            cs: cs,
            tt: tt,
            tone: _AlertTone.primary,
          ),
          const SizedBox(height: 14),
          _AlertCard(
            icon: Icons.schedule_rounded,
            title: 'Tempo de propagação',
            lines: [guide.propagationHint],
            cs: cs,
            tt: tt,
            tone: _AlertTone.neutral,
          ),
          const SizedBox(height: 14),
          _AlertCard(
            icon: Icons.save_alt_outlined,
            title: 'Antes de sair',
            lines: const [
              'Sempre salve ou confirme as alterações no painel do provedor. '
 'Sem salvar, o DNS não será atualizado.',
            ],
            cs: cs,
            tt: tt,
            tone: _AlertTone.warning,
          ),
        ],
      ),
    );
  }
}

enum _AlertTone { primary, neutral, warning }

class _DnsFillCard extends StatelessWidget {
  const _DnsFillCard({
    required this.cs,
    required this.tt,
    required this.recommendedFqdn,
    required this.recordType,
    required this.recordName,
    required this.cnameTarget,
    required this.onCopy,
  });

  final ColorScheme cs;
  final TextTheme tt;
  final String recommendedFqdn;
  final String recordType;
  final String recordName;
  final String cnameTarget;
  final void Function(String label, String value) onCopy;

  @override
  Widget build(BuildContext context) {
    final hasHost = recommendedFqdn.isNotEmpty;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest.withOpacity(0.65),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.dns_rounded, color: cs.primary, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Dados para preencher no provedor',
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _CopyRow(
              label: 'Subdomínio recomendado (FQDN)',
              value: hasHost ? recommendedFqdn : '—',
              onCopy: hasHost ? () => onCopy('Subdomínio', recommendedFqdn) : null,
              cs: cs,
              tt: tt,
              mono: true,
            ),
            _CopyRow(
              label: 'Tipo de registro',
              value: recordType,
              onCopy: () => onCopy('Tipo', recordType),
              cs: cs,
              tt: tt,
            ),
            _CopyRow(
              label: 'Nome do registro',
              value: recordName,
              onCopy: () => onCopy('Nome', recordName),
              cs: cs,
              tt: tt,
            ),
            _CopyRow(
              label: 'Destino (valor CNAME)',
              value: cnameTarget,
              onCopy: () => onCopy('Destino', cnameTarget),
              cs: cs,
              tt: tt,
              mono: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _CopyRow extends StatelessWidget {
  const _CopyRow({
    required this.label,
    required this.value,
    required this.cs,
    required this.tt,
    this.onCopy,
    this.mono = false,
  });

  final String label;
  final String value;
  final ColorScheme cs;
  final TextTheme tt;
  final VoidCallback? onCopy;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: tt.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  value,
                  style: (mono ? tt.bodyMedium?.copyWith(fontFamily: 'monospace', fontSize: 13) : tt.bodyMedium)
                      ?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          if (onCopy != null)
            IconButton(
              tooltip: 'Copiar',
              onPressed: onCopy,
              icon: const Icon(Icons.copy_rounded, size: 20),
            ),
        ],
      ),
    );
  }
}

class _NumberedStep extends StatelessWidget {
  const _NumberedStep({
    required this.index,
    required this.text,
    required this.cs,
    required this.tt,
  });

  final int index;
  final String text;
  final ColorScheme cs;
  final TextTheme tt;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: cs.primary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$index',
            style: tt.labelLarge?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              text,
              style: tt.bodyMedium?.copyWith(height: 1.42, color: cs.onSurface),
            ),
          ),
        ),
      ],
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({
    required this.icon,
    required this.title,
    required this.lines,
    required this.cs,
    required this.tt,
    required this.tone,
  });

  final IconData icon;
  final String title;
  final List<String> lines;
  final ColorScheme cs;
  final TextTheme tt;
  final _AlertTone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      _AlertTone.primary => (
          cs.primaryContainer.withOpacity(0.35),
          cs.onPrimaryContainer,
        ),
      _AlertTone.warning => (
          cs.tertiaryContainer.withOpacity(0.4),
          cs.onTertiaryContainer,
        ),
      _AlertTone.neutral => (
          cs.surfaceContainerHighest,
          cs.onSurfaceVariant,
        ),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg.withOpacity(0.9), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: tt.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
                const SizedBox(height: 6),
                for (final line in lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      line,
                      style: tt.bodySmall?.copyWith(
                        color: fg,
                        height: 1.4,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
