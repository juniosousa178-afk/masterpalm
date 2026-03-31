// Página pública "Sobre a loja" — conteúdo vindo de Loja Config (sobreLojaCatalogo).

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/catalog_sobre_loja_config.dart';
import '../../utils/image_provider.dart';
import '../../utils/instagram_launcher.dart';
import 'catalog_dicas_screen.dart';

class CatalogSobreLojaScreen extends StatelessWidget {
  final String lojaNome;
  final CatalogSobreLojaConfig config;
  final Color? primaryColor;
  final CatalogDicasColors? dicasColors;
  final String? logoUrl;
  final double logoHeight;
  final double bannerHeightHero;
  final DicasContactInfo? contactInfo;
  final String empresaRazao;
  final String empresaCnpj;
  final void Function(String url) onOpenUrl;

  const CatalogSobreLojaScreen({
    super.key,
    required this.lojaNome,
    required this.config,
    this.primaryColor,
    this.dicasColors,
    this.logoUrl,
    this.logoHeight = 80,
    this.bannerHeightHero = 220,
    this.contactInfo,
    this.empresaRazao = '',
    this.empresaCnpj = '',
    required this.onOpenUrl,
  });

  String get _tituloExibicao =>
      config.titulo.trim().isNotEmpty ? config.titulo.trim() : 'Sobre a loja';

  bool get _hasValidBannerUrl => _isHttpUrl(config.bannerUrl);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = dicasColors ?? const CatalogDicasColors();
    final primary = primaryColor ?? theme.colorScheme.primary;
    final btnBg = colors.buttonBackground;
    final btnText = colors.buttonText;
    final topic = colors.topicPrimary;
    final bgPage = theme.brightness == Brightness.dark
        ? theme.scaffoldBackgroundColor
        : colors.background;

    final showLogo = logoUrl != null && logoUrl!.trim().isNotEmpty;
    final heroHeight = bannerHeightHero.clamp(180.0, 320.0).toDouble();

    return Scaffold(
      backgroundColor: bgPage,
      appBar: AppBar(
        toolbarHeight: showLogo ? logoHeight + 32 : null,
        titleSpacing: 0,
        title: showLogo
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: SizedBox(
                  height: logoHeight,
                  child: Image(
                    image: mpImageProvider(logoUrl!),
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              )
            : Text(
                lojaNome,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 17,
                  color: btnText,
                ),
              ),
        backgroundColor: btnBg,
        foregroundColor: btnText,
        elevation: 0,
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Stack(
                        alignment: Alignment.bottomLeft,
                        children: [
                          SizedBox(
                            height: heroHeight,
                            width: double.infinity,
                            child: _hasValidBannerUrl
                                ? Image(
                                    image: mpImageProvider(config.bannerUrl),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        _BannerPlaceholder(topic: topic),
                                  )
                                : _BannerPlaceholder(topic: topic),
                          ),
                          Container(
                            height: heroHeight,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.14),
                                  Colors.black.withValues(alpha: 0.62),
                                ],
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _tituloExibicao,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 26,
                                    fontWeight: FontWeight.w800,
                                    height: 1.16,
                                    shadows: [
                                      Shadow(
                                        blurRadius: 14,
                                        color: Colors.black54,
                                      ),
                                    ],
                                  ),
                                ),
                                if (config.subtitulo.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    config.subtitulo,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.96),
                                      fontSize: 15,
                                      height: 1.35,
                                      shadows: const [
                                        Shadow(
                                          blurRadius: 10,
                                          color: Colors.black54,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!config.temConteudoBasico &&
                                config.subtitulo.isEmpty &&
                                config.bannerUrl.isEmpty)
                              _EmptyHint(
                                lojaNome: lojaNome,
                                topic: topic,
                                theme: theme,
                              )
                            else ...[
                              if (config.introducao.isNotEmpty)
                                ..._paragraphs(config.introducao, theme),
                              if (config.destaques.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Por que comprar conosco',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: config.destaques
                                      .map(
                                        (t) => Chip(
                                          avatar: Icon(Icons.check_circle,
                                              size: 18, color: primary),
                                          label: Text(t),
                                          backgroundColor: primary
                                              .withValues(alpha: 0.08),
                                          side: BorderSide.none,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 4, vertical: 2),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ],
                              if (config.missao.isNotEmpty ||
                                  config.visao.isNotEmpty ||
                                  config.valores.isNotEmpty) ...[
                                const SizedBox(height: 28),
                                LayoutBuilder(
                                  builder: (context, c) {
                                    final narrow = c.maxWidth < 560;
                                    final cards = <Widget>[
                                      if (config.missao.isNotEmpty)
                                        _InfoCard(
                                          icon: Icons.flag_outlined,
                                          title: 'Missão',
                                          body: config.missao,
                                          primary: primary,
                                          theme: theme,
                                        ),
                                      if (config.visao.isNotEmpty)
                                        _InfoCard(
                                          icon: Icons.visibility_outlined,
                                          title: 'Visão',
                                          body: config.visao,
                                          primary: primary,
                                          theme: theme,
                                        ),
                                      if (config.valores.isNotEmpty)
                                        _InfoCard(
                                          icon: Icons.favorite_outline,
                                          title: 'Valores',
                                          body: config.valores,
                                          primary: primary,
                                          theme: theme,
                                        ),
                                    ];
                                    if (narrow) {
                                      return Column(
                                        children: [
                                          for (var i = 0; i < cards.length; i++)
                                            Padding(
                                              padding: EdgeInsets.only(
                                                  bottom:
                                                      i < cards.length - 1
                                                          ? 14
                                                          : 0),
                                              child: cards[i],
                                            ),
                                        ],
                                      );
                                    }
                                    return Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        for (var i = 0; i < cards.length; i++)
                                          Expanded(
                                            child: Padding(
                                              padding: EdgeInsets.only(
                                                right: i < cards.length - 1
                                                    ? 12
                                                    : 0,
                                              ),
                                              child: cards[i],
                                            ),
                                          ),
                                      ],
                                    );
                                  },
                                ),
                              ],
                              if (config.endereco.isNotEmpty ||
                                  config.horarioAtendimento.isNotEmpty ||
                                  config.emailContato.isNotEmpty) ...[
                                const SizedBox(height: 28),
                                Text(
                                  'Onde nos encontrar',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Card(
                                  elevation: 0,
                                  color: theme.colorScheme.surfaceContainerHighest
                                      .withValues(alpha: 0.35),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(18),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (config.endereco.isNotEmpty)
                                          _ContactRow(
                                            icon: Icons.location_on_outlined,
                                            text: config.endereco,
                                            theme: theme,
                                          ),
                                        if (config.horarioAtendimento
                                            .isNotEmpty) ...[
                                          const SizedBox(height: 12),
                                          _ContactRow(
                                            icon: Icons.schedule_outlined,
                                            text: config.horarioAtendimento,
                                            theme: theme,
                                          ),
                                        ],
                                        if (config.emailContato.isNotEmpty) ...[
                                          const SizedBox(height: 12),
                                          _ContactRow(
                                            icon: Icons.email_outlined,
                                            text: config.emailContato,
                                            theme: theme,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                              if (config.mostrarDadosLegais &&
                                  (empresaRazao.trim().isNotEmpty ||
                                      empresaCnpj.trim().isNotEmpty)) ...[
                                const SizedBox(height: 28),
                                Text(
                                  'Dados da empresa',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                if (empresaRazao.trim().isNotEmpty)
                                  Text(
                                    empresaRazao.trim(),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      height: 1.4,
                                    ),
                                  ),
                                if (empresaCnpj.trim().isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'CNPJ: ${empresaCnpj.trim()}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ],
                              if (_isHttpUrl(config.linkExternoUrl)) ...[
                                const SizedBox(height: 24),
                                OutlinedButton.icon(
                                  onPressed: () =>
                                      onOpenUrl(config.linkExternoUrl.trim()),
                                  icon: const Icon(Icons.open_in_new, size: 20),
                                  label: const Text('Visitar site ou página externa'),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _SobreLojaFooterBar(
            buttonBg: btnBg,
            buttonText: btnText,
            footerBg: colors.footerBackground,
            footerText: colors.footerText,
            contactInfo: contactInfo,
            onIrParaCatalogo: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  static bool _isHttpUrl(String s) {
    final t = s.trim().toLowerCase();
    return t.startsWith('http://') || t.startsWith('https://');
  }

  static Iterable<Widget> _paragraphs(String text, ThemeData theme) sync* {
    for (final p in text.split(RegExp(r'\n\n+'))) {
      final para = p.trim();
      if (para.isEmpty) continue;
      yield Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(
          para,
          style: theme.textTheme.bodyLarge?.copyWith(height: 1.65),
        ),
      );
    }
  }
}

class _BannerPlaceholder extends StatelessWidget {
  final Color topic;

  const _BannerPlaceholder({required this.topic});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            topic.withValues(alpha: 0.16),
            topic.withValues(alpha: 0.08),
            Colors.black.withValues(alpha: 0.06),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -18,
            top: -12,
            child: Icon(
              Icons.auto_awesome_rounded,
              size: 86,
              color: topic.withValues(alpha: 0.15),
            ),
          ),
          Positioned(
            left: 16,
            bottom: 14,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.image_outlined,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.95),
                ),
                const SizedBox(width: 8),
                Text(
                  'Banner da loja',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.95),
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                    shadows: const [
                      Shadow(blurRadius: 8, color: Colors.black45),
                    ],
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

class _EmptyHint extends StatelessWidget {
  final String lojaNome;
  final Color topic;
  final ThemeData theme;

  const _EmptyHint({
    required this.lojaNome,
    required this.topic,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: topic.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: topic.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit_note_rounded, color: topic, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Conteúdo em construção',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'A loja $lojaNome ainda está montando esta página. '
            'Em Loja Config → Menu e páginas → “Sobre a loja no catálogo”, '
            'é possível adicionar texto, banner, missão, valores e contato.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Color primary;
  final ThemeData theme;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.primary,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: primary, size: 28),
            const SizedBox(height: 12),
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              body,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final ThemeData theme;

  const _ContactRow({
    required this.icon,
    required this.text,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
          ),
        ),
      ],
    );
  }
}

/// Rodapé alinhado à tela Dicas (voltar + contatos).
class _SobreLojaFooterBar extends StatelessWidget {
  final Color buttonBg;
  final Color buttonText;
  final Color footerBg;
  final Color footerText;
  final DicasContactInfo? contactInfo;
  final VoidCallback onIrParaCatalogo;

  const _SobreLojaFooterBar({
    required this.buttonBg,
    required this.buttonText,
    required this.footerBg,
    required this.footerText,
    required this.contactInfo,
    required this.onIrParaCatalogo,
  });

  static String _digitsOnly(String? v) {
    if (v == null || v.isEmpty) return '';
    return v.replaceAll(RegExp(r'[^0-9]'), '');
  }

  Future<void> _openWhatsApp(BuildContext context, String? number) async {
    final digits = _digitsOnly(number);
    if (digits.isEmpty) return;
    final url = Uri.parse('https://wa.me/$digits');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openInstagram(BuildContext context, String? url) async {
    final u = (url ?? '').trim();
    if (u.isEmpty) return;
    final opened = await openInstagramInApp(u);
    if (!opened && context.mounted) {
      final uri = Uri.parse(u.contains('://') ? u : 'https://instagram.com/$u');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  Future<void> _openFacebook(BuildContext context, String? url) async {
    final u = (url ?? '').trim();
    if (u.isEmpty) return;
    final uri = Uri.parse(u.contains('://') ? u : 'https://facebook.com/$u');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasContact = contactInfo != null &&
        ((contactInfo!.whatsappNumber ?? '').trim().isNotEmpty ||
            (contactInfo!.instagramUrl ?? '').trim().isNotEmpty ||
            (contactInfo!.facebookUrl ?? '').trim().isNotEmpty);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark ? theme.cardColor : footerBg,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton.icon(
              onPressed: onIrParaCatalogo,
              icon: const Icon(Icons.storefront_outlined, size: 22),
              label: const Text('Voltar ao catálogo'),
              style: FilledButton.styleFrom(
                backgroundColor: buttonBg,
                foregroundColor: buttonText,
                padding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
            if (hasContact) ...[
              const SizedBox(height: 16),
              Text(
                'Contato',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: footerText,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if ((contactInfo!.whatsappNumber ?? '').trim().isNotEmpty)
                    IconButton.filled(
                      onPressed: () => _openWhatsApp(
                          context, contactInfo!.whatsappNumber),
                      icon: const Icon(Icons.chat, color: Colors.white, size: 22),
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366),
                        padding: const EdgeInsets.all(12),
                      ),
                    ),
                  if ((contactInfo!.whatsappNumber ?? '').trim().isNotEmpty &&
                      (contactInfo!.instagramUrl ?? '').trim().isNotEmpty)
                    const SizedBox(width: 12),
                  if ((contactInfo!.instagramUrl ?? '').trim().isNotEmpty)
                    IconButton.filled(
                      onPressed: () =>
                          _openInstagram(context, contactInfo!.instagramUrl),
                      icon: const Icon(Icons.camera_alt,
                          color: Colors.white, size: 22),
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFE4405F),
                        padding: const EdgeInsets.all(12),
                      ),
                    ),
                  if ((contactInfo!.instagramUrl ?? '').trim().isNotEmpty &&
                      (contactInfo!.facebookUrl ?? '').trim().isNotEmpty)
                    const SizedBox(width: 12),
                  if ((contactInfo!.facebookUrl ?? '').trim().isNotEmpty)
                    IconButton.filled(
                      onPressed: () =>
                          _openFacebook(context, contactInfo!.facebookUrl),
                      icon: const Icon(Icons.facebook,
                          color: Colors.white, size: 22),
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFF1877F2),
                        padding: const EdgeInsets.all(12),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
