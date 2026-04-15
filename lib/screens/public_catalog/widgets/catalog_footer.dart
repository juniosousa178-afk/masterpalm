import 'package:flutter/material.dart';

import 'catalog_section_title.dart';

class CatalogFooter extends StatelessWidget {
  final Color bg;
  final Color textColor;
  final Color? textSecondaryColor;
  final Color? iconColor;
  final Color? linkColor;
  final Color? dividerColor;
  final String lojaNome;
  final String instagramUrl;
  final String facebookUrl;
  final String tiktokUrl;
  final String telegramUrl;
  final String kwaiUrl;
  final String linkedinUrl;
  final String emailUrl;
  final String whatsappUrl;
  final String atendimentoWhatsapp;
  final List<Map<String, String>> links;
  final List<String> paymentCodes;
  final Map<String, String> paymentAsset;
  final String badgeSSL;
  final String badgeGoogle;
  final String empresaRazao;
  final String empresaCnpj;
  final VoidCallback onOpenWhatsapp;
  final void Function(String url) onOpenUrl;
  /// Abre a página interna "Sobre a loja" (catálogo). Se null, o link não aparece.
  final VoidCallback? onSobreLojaTap;
  final List<Map<String, String>> faqItems;
  final String politicaPrivacidadeUrl;
  final String termosUsoUrl;

  const CatalogFooter({
    super.key,
    required this.bg,
    required this.textColor,
    this.textSecondaryColor,
    this.iconColor,
    this.linkColor,
    this.dividerColor,
    required this.lojaNome,
    required this.instagramUrl,
    required this.facebookUrl,
    required this.tiktokUrl,
    required this.telegramUrl,
    required this.kwaiUrl,
    required this.linkedinUrl,
    required this.emailUrl,
    required this.whatsappUrl,
    required this.atendimentoWhatsapp,
    required this.links,
    required this.paymentCodes,
    required this.paymentAsset,
    required this.badgeSSL,
    required this.badgeGoogle,
    required this.empresaRazao,
    required this.empresaCnpj,
    required this.onOpenWhatsapp,
    required this.onOpenUrl,
    this.onSobreLojaTap,
    this.faqItems = const [],
    this.politicaPrivacidadeUrl = '',
    this.termosUsoUrl = '',
  });

  @override
  Widget build(BuildContext context) {
    final muted = textSecondaryColor ?? textColor.withOpacity(0.65);
    final icons = iconColor ?? textColor;
    final linksColor = linkColor ?? textColor;
    final divider = dividerColor ?? textColor.withOpacity(0.22);
    final safeLinks = links.where((m) {
      final label = (m['label'] ?? '').trim();
      final url = (m['url'] ?? '').trim();
      return label.isNotEmpty && url.isNotEmpty;
    }).toList();

    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              _icon(Icons.camera_alt_outlined, instagramUrl, icons),
              _icon(Icons.thumb_up_alt_outlined, facebookUrl, icons),
              _icon(Icons.play_circle_outline, tiktokUrl, icons),
              _icon(Icons.send_outlined, telegramUrl, icons),
              _icon(Icons.video_collection_outlined, kwaiUrl, icons),
              _icon(Icons.work_outline, linkedinUrl, icons),
              _icon(Icons.email_outlined, emailUrl, icons),
              _icon(Icons.phone_outlined, whatsappUrl, icons, isWhatsapp: true),
            ],
          ),
          Divider(color: divider, height: 24),
          CatalogSectionTitle('Links', color: muted),
          const SizedBox(height: 8),
          if (onSobreLojaTap != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InkWell(
                onTap: onSobreLojaTap,
                child: Text(
                  'Sobre a loja',
                  style: TextStyle(
                    color: linksColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          if (safeLinks.isEmpty && onSobreLojaTap == null)
            Text(
              'Nenhum link configurado.',
              style: TextStyle(color: muted, fontSize: 13),
            )
          else if (safeLinks.isNotEmpty)
            Column(
              children: safeLinks
                  .map(
                    (m) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: InkWell(
                        onTap: () => onOpenUrl(m['url']!),
                        child: Text(
                          m['label']!,
                          style: TextStyle(color: linksColor, fontSize: 14),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          const SizedBox(height: 14),
          CatalogSectionTitle('Atendimento', color: muted),
          const SizedBox(height: 8),
          Text(
            atendimentoWhatsapp.trim().isEmpty
                ? '(WhatsApp nao configurado)'
                : atendimentoWhatsapp,
            style: TextStyle(color: textColor, fontSize: 14),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed:
                atendimentoWhatsapp.trim().isEmpty ? null : onOpenWhatsapp,
            icon: const Icon(Icons.message_outlined),
            label: const Text('Conversar no WhatsApp'),
          ),
          const SizedBox(height: 18),
          CatalogSectionTitle('Formas de pagamento', color: muted),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: paymentCodes.map((code) {
              final asset = paymentAsset[code];
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: divider),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: asset == null
                    ? Text(code.toUpperCase(), style: TextStyle(color: muted))
                    : Image.asset(asset, height: 22, fit: BoxFit.contain),
              );
            }).toList(),
          ),
          if (faqItems.isNotEmpty) ...[
            const SizedBox(height: 18),
            CatalogSectionTitle('Perguntas frequentes', color: muted),
            const SizedBox(height: 8),
            ...faqItems.take(3).map((faq) {
              final pergunta = (faq['pergunta'] ?? '').trim();
              final resposta = (faq['resposta'] ?? '').trim();
              if (pergunta.isEmpty) return const SizedBox.shrink();
              return ExpansionTile(
                tilePadding: EdgeInsets.zero,
                iconColor: icons,
                collapsedIconColor: icons,
                title: Text(
                  pergunta,
                  style: TextStyle(color: textColor, fontSize: 13),
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        resposta,
                        style: TextStyle(color: muted, fontSize: 12.5),
                      ),
                    ),
                  ),
                ],
              );
            }),
          ],
          if (politicaPrivacidadeUrl.isNotEmpty || termosUsoUrl.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 14,
              runSpacing: 8,
              children: [
                if (politicaPrivacidadeUrl.isNotEmpty)
                  InkWell(
                    onTap: () => onOpenUrl(politicaPrivacidadeUrl),
                    child: Text(
                      'Politica de privacidade',
                      style: TextStyle(
                        color: linksColor,
                        fontSize: 12,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                if (termosUsoUrl.isNotEmpty)
                  InkWell(
                    onTap: () => onOpenUrl(termosUsoUrl),
                    child: Text(
                      'Termos de uso',
                      style: TextStyle(
                        color: linksColor,
                        fontSize: 12,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Text(
            '${(empresaRazao.isNotEmpty ? empresaRazao : lojaNome).toUpperCase()}'
            '${empresaCnpj.isNotEmpty ? ' - CNPJ: $empresaCnpj' : ''}',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _icon(IconData icon, String rawUrl, Color color, {bool isWhatsapp = false}) {
    final url = rawUrl.trim();
    return Opacity(
      opacity: url.isEmpty ? 0.35 : 1,
      child: IconButton(
        icon: Icon(icon, size: 24, color: color),
        onPressed: url.isEmpty
            ? null
            : () {
                if (isWhatsapp) {
                  final cleanPhone = url.replaceAll(RegExp(r'[^\d]'), '');
                  onOpenUrl('https://wa.me/$cleanPhone');
                  return;
                }
                if (icon == Icons.email_outlined && url.contains('@')) {
                  onOpenUrl('mailto:$url');
                  return;
                }
                onOpenUrl(url);
              },
      ),
    );
  }
}
