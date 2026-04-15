// lib/screens/public_catalog/catalog_dicas_screen.dart
// Página de Dicas, Cuidados, Garantias e Informações – layout estilo blog (ex.: Zellora).
// Rodapé com: Ir para o catálogo, WhatsApp, Instagram, Facebook.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../utils/safe_parse.dart';
import '../../widgets/smart_image.dart';
import '../../utils/instagram_launcher.dart';

/// Tipos de dica exibidos no catálogo (labels amigáveis).
const Map<String, String> kTiposDicaLabels = {
  'garantias': 'Garantias',
  'cuidados': 'Cuidados com o produto',
  'qualidade': 'Informações de qualidade',
  'informacoes': 'Informações gerais',
  'outros': 'Outras informações',
};

String labelForTipo(String tipo) {
  final fromMap = kTiposDicaLabels[tipo];
  if (fromMap != null) return fromMap;
  return tipo.trim().isNotEmpty ? tipo : 'Informação';
}

/// Uma dica (item da lista) – campos vindos do Firestore/config.
class DicaItem {
  final String id;
  final String titulo;
  final String tipo;
  final String conteudo;
  final String? bannerUrl;
  final int ordem;
  final bool ativo;

  DicaItem({
    required this.id,
    required this.titulo,
    required this.tipo,
    required this.conteudo,
    this.bannerUrl,
    this.ordem = 0,
    this.ativo = true,
  });

  static DicaItem fromMap(Map<String, dynamic> m) {
    return DicaItem(
      id: (m['id'] ?? '').toString().trim().isEmpty ? DateTime.now().millisecondsSinceEpoch.toString() : (m['id'] ?? '').toString(),
      titulo: (m['titulo'] ?? '').toString().trim(),
      tipo: (m['tipo'] ?? 'informacoes').toString().trim().isEmpty ? 'informacoes' : (m['tipo'] ?? 'informacoes').toString(),
      conteudo: (m['conteudo'] ?? '').toString().trim(),
      bannerUrl: (m['bannerUrl'] ?? m['banner_url'] ?? '').toString().trim().isEmpty ? null : (m['bannerUrl'] ?? m['banner_url']).toString().trim(),
      ordem: safeInt(m['ordem'], 0),
      ativo: safeBool(m['ativo'], true),
    );
  }
}

/// Dados de contato para o rodapé (WhatsApp, Instagram, Facebook).
class DicasContactInfo {
  final String? whatsappNumber;
  final String? instagramUrl;
  final String? facebookUrl;

  const DicasContactInfo({
    this.whatsappNumber,
    this.instagramUrl,
    this.facebookUrl,
  });
}

/// Cores editáveis da tela Dicas (Loja Config > Cores e temas).
class CatalogDicasColors {
  final Color background;
  final Color footerBackground;
  final Color footerText;
  final Color buttonBackground;
  final Color buttonText;
  final Color topicPrimary;

  const CatalogDicasColors({
    this.background = const Color(0xFFF8F9FA),
    this.footerBackground = Colors.white,
    this.footerText = Colors.black87,
    this.buttonBackground = const Color(0xFF22C55E),
    this.buttonText = Colors.white,
    this.topicPrimary = const Color(0xFF22C55E),
  });
}

/// Tela pública: lista de dicas em layout blog + rodapé com catálogo e contato.
class CatalogDicasScreen extends StatelessWidget {
  final String lojaId;
  final String lojaNome;
  final List<DicaItem> dicas;
  final Color? primaryColor;
  final DicasContactInfo? contactInfo;
  /// Logo do catálogo (um pouco maior na tela de dicas)
  final String? logoUrl;
  /// Altura da logo (ex.: 80 mobile, 90 desktop vs 60/72 do catálogo)
  final double logoHeight;
  /// Altura dos banners das dicas (mesmas proporções do catálogo)
  final double bannerHeightCard;
  final double bannerHeightDetail;
  /// Cores editáveis em Loja Config
  final CatalogDicasColors? dicasColors;

  const CatalogDicasScreen({
    super.key,
    required this.lojaId,
    this.lojaNome = 'Dicas e informações',
    required this.dicas,
    this.primaryColor,
    this.contactInfo,
    this.logoUrl,
    this.logoHeight = 80,
    this.bannerHeightCard = 160,
    this.bannerHeightDetail = 200,
    this.dicasColors,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = dicasColors ?? const CatalogDicasColors();
    final primary = primaryColor ?? theme.colorScheme.primary;
    final btnBg = colors.buttonBackground;
    final btnText = colors.buttonText;
    final list = dicas.where((d) => d.ativo && d.titulo.isNotEmpty).toList()
      ..sort((a, b) => a.ordem.compareTo(b.ordem));

    final showLogo = logoUrl != null && logoUrl!.isNotEmpty;
    return Scaffold(
      backgroundColor: theme.brightness == Brightness.dark ? theme.scaffoldBackgroundColor : colors.background,
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
                  fontSize: 18,
                  color: btnText,
                ),
              ),
        backgroundColor: btnBg,
        foregroundColor: btnText,
        elevation: 0,
        centerTitle: true,
      ),
      body: list.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lightbulb_outline, size: 64, color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5)),
                    const SizedBox(height: 16),
                    Text(
                      'Nenhuma dica ou informação publicada no momento.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 24),
                    _DicasFooter(
                      buttonBg: btnBg,
                      buttonText: btnText,
                      footerBg: colors.footerBackground,
                      footerText: colors.footerText,
                      contactInfo: contactInfo,
                      onIrParaCatalogo: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                    itemCount: list.length,
                    itemBuilder: (context, index) {
                      final d = list[index];
                      return _DicaCard(
                        dica: d,
                        topicColor: colors.topicPrimary,
                        bannerHeight: bannerHeightCard,
                        onTap: () => _openDetail(context, d, primary),
                      );
                    },
                  ),
                ),
                _DicasFooter(
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

  void _openDetail(BuildContext context, DicaItem dica, Color primary) {
    final colors = dicasColors ?? const CatalogDicasColors();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => _DicaDetailScreen(
          dica: dica,
          lojaNome: lojaNome,
          primaryColor: primary,
          topicColor: colors.topicPrimary,
          bannerHeight: bannerHeightDetail,
          buttonBg: colors.buttonBackground,
          buttonText: colors.buttonText,
          footerBg: colors.footerBackground,
          footerText: colors.footerText,
          contactInfo: contactInfo,
        ),
      ),
    );
  }
}

/// Rodapé fixo: Ir para o catálogo, WhatsApp, Instagram, Facebook.
class _DicasFooter extends StatelessWidget {
  final Color buttonBg;
  final Color buttonText;
  final Color footerBg;
  final Color footerText;
  final DicasContactInfo? contactInfo;
  final VoidCallback onIrParaCatalogo;

  const _DicasFooter({
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
    if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _openInstagram(BuildContext context, String? url) async {
    final u = (url ?? '').trim();
    if (u.isEmpty) return;
    final opened = await openInstagramInApp(u);
    if (!opened && context.mounted) {
      final uri = Uri.parse(u.contains('://') ? u : 'https://instagram.com/$u');
      if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openFacebook(BuildContext context, String? url) async {
    final u = (url ?? '').trim();
    if (u.isEmpty) return;
    final uri = Uri.parse(u.contains('://') ? u : 'https://facebook.com/$u');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
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
            color: Colors.black.withOpacity(0.06),
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
              label: const Text('Ir para o catálogo'),
              style: FilledButton.styleFrom(
                backgroundColor: buttonBg,
                foregroundColor: buttonText,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
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
                      onPressed: () => _openWhatsApp(context, contactInfo!.whatsappNumber),
                      icon: const Icon(Icons.chat, color: Colors.white, size: 22),
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366),
                        padding: const EdgeInsets.all(12),
                      ),
                    ),
                  if ((contactInfo!.whatsappNumber ?? '').trim().isNotEmpty && (contactInfo!.instagramUrl ?? '').trim().isNotEmpty) const SizedBox(width: 12),
                  if ((contactInfo!.instagramUrl ?? '').trim().isNotEmpty)
                    IconButton.filled(
                      onPressed: () => _openInstagram(context, contactInfo!.instagramUrl),
                      icon: const Icon(Icons.camera_alt, color: Colors.white, size: 22),
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFE4405F),
                        padding: const EdgeInsets.all(12),
                      ),
                    ),
                  if ((contactInfo!.instagramUrl ?? '').trim().isNotEmpty && (contactInfo!.facebookUrl ?? '').trim().isNotEmpty) const SizedBox(width: 12),
                  if ((contactInfo!.facebookUrl ?? '').trim().isNotEmpty)
                    IconButton.filled(
                      onPressed: () => _openFacebook(context, contactInfo!.facebookUrl),
                      icon: const Icon(Icons.facebook, color: Colors.white, size: 22),
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

class _DicaCard extends StatelessWidget {
  final DicaItem dica;
  final Color topicColor;
  final double bannerHeight;
  final VoidCallback onTap;

  const _DicaCard({
    required this.dica,
    required this.topicColor,
    this.bannerHeight = 200,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: theme.brightness == Brightness.dark ? theme.cardColor : Colors.white,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dica.bannerUrl != null && dica.bannerUrl!.isNotEmpty)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: SizedBox(
                  height: bannerHeight,
                  width: double.infinity,
                  child: Image(
                    image: mpImageProvider(dica.bannerUrl!),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: topicColor.withOpacity(0.08),
                      child: Icon(Icons.image_not_supported, size: 48, color: topicColor.withOpacity(0.4)),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: topicColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      labelForTipo(dica.tipo),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: topicColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    dica.titulo,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (dica.conteudo.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      dica.conteudo,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text(
                        'Leia mais',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: topicColor,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.arrow_forward_ios, size: 12, color: topicColor),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DicaDetailScreen extends StatelessWidget {
  final DicaItem dica;
  final String lojaNome;
  final Color primaryColor;
  final Color topicColor;
  final double bannerHeight;
  final Color buttonBg;
  final Color buttonText;
  final Color footerBg;
  final Color footerText;
  final DicasContactInfo? contactInfo;

  const _DicaDetailScreen({
    required this.dica,
    required this.lojaNome,
    required this.primaryColor,
    required this.topicColor,
    this.bannerHeight = 260,
    required this.buttonBg,
    required this.buttonText,
    required this.footerBg,
    required this.footerText,
    this.contactInfo,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = dica.conteudo.trim();

    return Scaffold(
      backgroundColor: theme.brightness == Brightness.dark ? theme.scaffoldBackgroundColor : const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(
          lojaNome,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
            color: buttonText,
          ),
        ),
        backgroundColor: buttonBg,
        foregroundColor: buttonText,
        elevation: 0,
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (dica.bannerUrl != null && dica.bannerUrl!.isNotEmpty)
                    SizedBox(
                      height: bannerHeight,
                      width: double.infinity,
                      child: Image(
                        image: mpImageProvider(dica.bannerUrl!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: topicColor.withOpacity(0.08),
                          child: Icon(Icons.image_not_supported, size: 64, color: topicColor.withOpacity(0.4)),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: topicColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            labelForTipo(dica.tipo),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: topicColor,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          dica.titulo,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (content.isNotEmpty)
                          ...content.split(RegExp(r'\n\n+')).map((p) {
                            final para = p.trim();
                            if (para.isEmpty) return const SizedBox(height: 16);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(
                                para,
                                style: theme.textTheme.bodyLarge?.copyWith(height: 1.65),
                              ),
                            );
                          })
                        else
                          Text(
                            'Conteúdo em breve.',
                            style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          _DicasFooter(
            buttonBg: buttonBg,
            buttonText: buttonText,
            footerBg: footerBg,
            footerText: footerText,
            contactInfo: contactInfo,
            onIrParaCatalogo: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

