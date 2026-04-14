import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../catalog/domain/catalog_custom_domain.dart';
import '../../data/domain_provider_guides.dart';
import '../../models/domain_provider_guide.dart';
import 'catalog_domain_provider_screen.dart';

/// Retorno opcional ao fechar a tela de configuração guiada (status local / provedor visto).
class CatalogDomainSetupPopResult {
  const CatalogDomainSetupPopResult({
    this.status,
    this.dominioProvider,
  });

  final String? status;
  final String? dominioProvider;
}

/// Assistente de domínio próprio do catálogo (somente orientação — sem verificação DNS real).
class CatalogDomainSetupScreen extends StatefulWidget {
  const CatalogDomainSetupScreen({
    super.key,
    required this.dominioInformado,
    required this.statusInicial,
    this.dominioProviderAtual,
  });

  /// Host normalizado informado pelo lojista (pode ser raiz ou FQDN).
  final String dominioInformado;

  final String statusInicial;
  final String? dominioProviderAtual;

  @override
  State<CatalogDomainSetupScreen> createState() => _CatalogDomainSetupScreenState();
}

class _CatalogDomainSetupScreenState extends State<CatalogDomainSetupScreen> {
  late String _localStatus;
  String? _lastProviderId;

  @override
  void initState() {
    super.initState();
    _localStatus = dominioStatusFromStorage(
      widget.statusInicial,
      hasDomain: widget.dominioInformado.isNotEmpty,
    );
    final p = widget.dominioProviderAtual?.trim();
    _lastProviderId = (p != null && p.isNotEmpty) ? p : null;
  }

  String get _normalizedInput => normalizeCatalogDomainInput(widget.dominioInformado);

  String get _recommended => recommendedCatalogFqdn(_normalizedInput);

  Future<void> _copy(BuildContext context, String label, String value) async {
    if (value.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copiado.')),
    );
  }

  void _openProvider(DomainProviderGuide g) {
    setState(() => _lastProviderId = g.id);
    final host = _recommended;
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (ctx) => CatalogDomainProviderScreen(
          guide: g,
          recommendedFqdn: host,
          recordType: kCatalogDnsRecordType,
          recordName: kCatalogDnsRecordName,
          cnameTarget: kCatalogPublicCnameTarget,
        ),
      ),
    );
  }

  void _marcarConfigurado() {
    setState(() => _localStatus = kDominioStatusAtivo);
    Navigator.of(context).pop(CatalogDomainSetupPopResult(
      status: kDominioStatusAtivo,
      dominioProvider: _lastProviderId,
    ));
  }

  void _verificarNovamente() {
    setState(() => _localStatus = kDominioStatusEmVerificacao);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Registramos “Em verificação” apenas no app. '
          'A propagação DNS e a validação técnica final ainda dependem do seu provedor e da infraestrutura.',
        ),
        duration: Duration(seconds: 5),
      ),
    );
    Navigator.of(context).pop(CatalogDomainSetupPopResult(
      status: kDominioStatusEmVerificacao,
      dominioProvider: _lastProviderId,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final hasDomain = _normalizedInput.isNotEmpty;
    final rec = _recommended;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Domínio próprio'),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
        children: [
          Text(
            'Conecte um endereço da sua marca ao catálogo público usando um registro DNS seguro (CNAME). '
            'Nenhuma alteração é feita automaticamente no seu provedor.',
            style: tt.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          if (!hasDomain) ...[
            Card(
              elevation: 0,
              color: cs.secondaryContainer.withValues(alpha: 0.25),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.45)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lightbulb_outline_rounded, color: cs.secondary, size: 26),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Você ainda não informou um domínio. Volte em Identidade & Contato, '
                        'preencha o campo em “Domínio próprio” e toque em “Adicionar domínio” para ver os valores recomendados aqui.',
                        style: tt.bodyMedium?.copyWith(height: 1.42),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
          ],
          _StatusStrip(cs: cs, tt: tt, status: _localStatus),
          const SizedBox(height: 16),
          Text(
            'Seu domínio e DNS',
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          _SummaryCard(
            cs: cs,
            tt: tt,
            userDomain: hasDomain ? _normalizedInput : '—',
            recommendedFqdn: hasDomain ? rec : '—',
            recordType: kCatalogDnsRecordType,
            recordName: kCatalogDnsRecordName,
            cnameTarget: kCatalogPublicCnameTarget,
            onCopy: (a, b) => _copy(context, a, b),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: hasDomain ? () => _copy(context, 'Destino DNS', kCatalogPublicCnameTarget) : null,
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copiar destino'),
              ),
              OutlinedButton.icon(
                onPressed: hasDomain ? () => _copy(context, 'Nome do registro', kCatalogDnsRecordName) : null,
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copiar nome'),
              ),
              OutlinedButton.icon(
                onPressed: hasDomain && rec.isNotEmpty ? () => _copy(context, 'Subdomínio', rec) : null,
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copiar subdomínio'),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            'Como vincular seu domínio',
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          const _IntroSteps(),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.errorContainer.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.verified_user_outlined, color: cs.error, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'O MasterPalm não valida automaticamente o seu DNS nesta versão. '
                    'Os status são informativos para você acompanhar o processo na loja.',
                    style: tt.bodySmall?.copyWith(
                      color: cs.onSurface,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'Escolha seu provedor',
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Toque no provedor para ver o passo a passo com capturas conceituais em texto.',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.35),
          ),
          const SizedBox(height: 12),
          ...kDomainProviderGuides.map(
            (g) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: cs.surface,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  leading: CircleAvatar(
                    backgroundColor: cs.primary.withValues(alpha: 0.12),
                    child: Icon(Icons.dns_rounded, color: cs.primary, size: 22),
                  ),
                  title: Text(
                    g.title,
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    g.shortDescription,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.3),
                  ),
                  trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                  onTap: () => _openProvider(g),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Atualizar status na loja',
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Use os botões abaixo só como controle interno. Eles não disparam verificação técnica no ar.',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.35),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: hasDomain ? _marcarConfigurado : null,
                  child: const Text('Marcar como configurado'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: hasDomain ? _verificarNovamente : null,
                  child: const Text('Verificar novamente'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({
    required this.cs,
    required this.tt,
    required this.status,
  });

  final ColorScheme cs;
  final TextTheme tt;
  final String status;

  @override
  Widget build(BuildContext context) {
    final label = dominioStatusLabelPt(status);
    final color = switch (status) {
      kDominioStatusAtivo => Colors.green.shade700,
      kDominioStatusEmVerificacao => cs.primary,
      kDominioStatusPendente => cs.tertiary,
      _ => cs.onSurfaceVariant,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(Icons.flag_outlined, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Status no app',
                  style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
                ),
                Text(
                  label,
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.cs,
    required this.tt,
    required this.userDomain,
    required this.recommendedFqdn,
    required this.recordType,
    required this.recordName,
    required this.cnameTarget,
    required this.onCopy,
  });

  final ColorScheme cs;
  final TextTheme tt;
  final String userDomain;
  final String recommendedFqdn;
  final String recordType;
  final String recordName;
  final String cnameTarget;
  final void Function(String label, String value) onCopy;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: cs.primary.withValues(alpha: 0.22), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _kv(
              'Seu domínio (informado)',
              userDomain,
              highlight: true,
              onCopy: userDomain != '—' ? () => onCopy('Domínio', userDomain) : null,
            ),
            _kv(
              'Subdomínio recomendado',
              recommendedFqdn,
              highlight: true,
              mono: true,
              onCopy: recommendedFqdn != '—' ? () => onCopy('Subdomínio', recommendedFqdn) : null,
            ),
            _kv(
              'Tipo de registro',
              recordType,
              chip: true,
              onCopy: () => onCopy('Tipo', recordType),
            ),
            _kv(
              'Nome',
              recordName,
              chip: true,
              onCopy: () => onCopy('Nome', recordName),
            ),
            _kv(
              'Destino',
              cnameTarget,
              mono: true,
              onCopy: () => onCopy('Destino', cnameTarget),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(
    String k,
    String v, {
    bool highlight = false,
    bool mono = false,
    bool chip = false,
    VoidCallback? onCopy,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  k,
                  style: tt.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                if (chip)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      v,
                      style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: cs.primary,
                        letterSpacing: 0.2,
                      ),
                    ),
                  )
                else
                  SelectableText(
                    v,
                    style: (mono
                            ? tt.titleSmall?.copyWith(fontFamily: 'monospace', fontSize: 13.5)
                            : tt.titleSmall)
                        ?.copyWith(
                      fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
                      color: cs.onSurface,
                    ),
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

class _IntroSteps extends StatelessWidget {
  const _IntroSteps();

  @override
  Widget build(BuildContext context) {
    const steps = [
      'Adicione seu domínio na configuração da loja.',
      'Escolha abaixo o provedor onde você edita o DNS.',
      'Crie o apontamento CNAME com os valores indicados.',
      'Aguarde a propagação (pode levar horas).',
      'Volte aqui e atualize o status conforme o andamento.',
    ];
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${i + 1}.',
                  style: tt.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    steps[i],
                    style: tt.bodyMedium?.copyWith(height: 1.4),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
