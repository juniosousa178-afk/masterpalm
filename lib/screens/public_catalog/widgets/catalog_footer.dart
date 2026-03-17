// lib/screens/public_catalog/widgets/catalog_footer.dart
// Rodapé do catálogo – extraído para reduzir tamanho do arquivo principal.

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
  /// FAQ: lista de {'pergunta': '', 'resposta': ''}
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
    this.faqItems = const [],
    this.politicaPrivacidadeUrl = '',
    this.termosUsoUrl = '',
  });

  @override
  Widget build(BuildContext context) {
    final muted = textSecondaryColor ?? textColor.withValues(alpha:0.6);
    final icons = iconColor ?? textColor;
    final links_ = linkColor ?? textColor;
    final divider = dividerColor ?? textColor.withValues(alpha:0.2);

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
            spacing: 20,
            children: [
              Opacity(
                opacity: instagramUrl.trim().isEmpty ? .35 : 1,
                child: IconButton(
                  icon: Icon(Icons.camera_alt_outlined, size: 28, color: icons),
                  onPressed: instagramUrl.trim().isEmpty
                      ? null
                      : () => onOpenUrl(instagramUrl),
                ),
              ),
              Opacity(
                opacity: facebookUrl.trim().isEmpty ? .35 : 1,
                child: IconButton(
                  icon: Icon(Icons.facebook_outlined, size: 28, color: icons),
                  onPressed: facebookUrl.trim().isEmpty
                      ? null
                      : () => onOpenUrl(facebookUrl),
                ),
              ),
              Opacity(
                opacity: tiktokUrl.trim().isEmpty ? .35 : 1,
                child: IconButton(
                  icon: Icon(Icons.music_note, size: 28, color: icons),
                  onPressed: tiktokUrl.trim().isEmpty
                      ? null
                      : () => onOpenUrl(tiktokUrl),
                ),
              ),
              Opacity(
                opacity: telegramUrl.trim().isEmpty ? .35 : 1,
                child: IconButton(
                  icon: Icon(Icons.send, size: 28, color: icons),
                  onPressed: telegramUrl.trim().isEmpty
                      ? null
                      : () => onOpenUrl(telegramUrl),
                ),
              ),
              Opacity(
                opacity: kwaiUrl.trim().isEmpty ? .35 : 1,
                child: IconButton(
                  icon: Icon(Icons.video_library, size: 28, color: icons),
                  onPressed: kwaiUrl.trim().isEmpty
                      ? null
                      : () => onOpenUrl(kwaiUrl),
                ),
              ),
              Opacity(
                opacity: linkedinUrl.trim().isEmpty ? .35 : 1,
                child: IconButton(
                  icon: Icon(Icons.business, size: 28, color: icons),
                  onPressed: linkedinUrl.trim().isEmpty
                      ? null
                      : () => onOpenUrl(linkedinUrl),
                ),
              ),
              Opacity(
                opacity: emailUrl.trim().isEmpty ? .35 : 1,
                child: IconButton(
                  icon: Icon(Icons.email_outlined, size: 28, color: icons),
                  onPressed: emailUrl.trim().isEmpty
                      ? null
                      : () {
                          if (emailUrl.contains('@')) {
                            onOpenUrl('mailto:$emailUrl');
                          } else {
                            onOpenUrl(emailUrl);
                          }
                        },
                ),
              ),
              Opacity(
                opacity: whatsappUrl.trim().isEmpty ? .35 : 1,
                child: IconButton(
                  icon: Icon(Icons.phone_outlined, size: 28, color: icons),
                  onPressed: whatsappUrl.trim().isEmpty
                      ? null
                      : () {
                          final cleanPhone =
                              whatsappUrl.replaceAll(RegExp(r'[^\d]'), '');
                          onOpenUrl('https://wa.me/$cleanPhone');
                        },
                ),
              ),
            ],
          ),
          Divider(color: divider, height: 24),
          CatalogSectionTitle('Links', color: muted),
          const SizedBox(height: 8),
          if (safeLinks.isEmpty)
            Text(
              'Nenhum link configurado.',
              style: TextStyle(color: muted, fontSize: 14),
              textAlign: TextAlign.center,
            )
          else
            Column(
              children: safeLinks
                  .map(
                    (m) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: InkWell(
                        onTap: () => onOpenUrl(m['url']!),
                        child: Text(
                          m['label']!,
                          style: TextStyle(color: links_, fontSize: 15),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          const SizedBox(height: 18),
          CatalogSectionTitle('Atendimento', color: muted),
          const SizedBox(height: 8),
          Opacity(
            opacity: atendimentoWhatsapp.trim().isEmpty ? .5 : 1,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.message, size: 22),
                const SizedBox(width: 8),
                Text(
                  atendimentoWhatsapp.isEmpty
                      ? '(WhatsApp não configurado)'
                      : atendimentoWhatsapp,
                  style: TextStyle(color: textColor, fontSize: 15),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed:
                atendimentoWhatsapp.trim().isEmpty ? null : onOpenWhatsapp,
            icon: const Icon(Icons.message),
            label: const Text('Conversar no WhatsApp'),
          ),
          const SizedBox(height: 22),
          CatalogSectionTitle('Formas de pagamento', color: muted),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: paymentCodes.map((code) {
              final asset = paymentAsset[code];
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.white.withValues(alpha:0.12),
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: asset == null
                    ? Text(
                        code.toUpperCase(),
                        style: TextStyle(color: muted),
                      )
                    : Image.asset(
                        asset,
                        height: 24,
                        fit: BoxFit.contain,
                      ),
              );
            }).toList(),
          ),
          if (faqItems.isNotEmpty) ...[
            const SizedBox(height: 22),
            CatalogSectionTitle('Perguntas frequentes', color: muted),
            const SizedBox(height: 12),
            ...faqItems.map((faq) {
              final pergunta = (faq['pergunta'] ?? '').trim();
              final resposta = (faq['resposta'] ?? '').trim();
              if (pergunta.isEmpty) return const SizedBox.shrink();
              return _FaqTile(
                pergunta: pergunta,
                resposta: resposta,
                textColor: textColor,
                muted: muted,
              );
            }),
          ],
          if (politicaPrivacidadeUrl.isNotEmpty || termosUsoUrl.isNotEmpty) ...[
            const SizedBox(height: 18),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (politicaPrivacidadeUrl.isNotEmpty)
                  InkWell(
                    onTap: () => onOpenUrl(politicaPrivacidadeUrl),
                    child: Text(
                      'Política de privacidade',
                      style: TextStyle(color: links_, fontSize: 13, decoration: TextDecoration.underline),
                    ),
                  ),
                if (termosUsoUrl.isNotEmpty)
                  InkWell(
                    onTap: () => onOpenUrl(termosUsoUrl),
                    child: Text(
                      'Termos de uso',
                      style: TextStyle(color: links_, fontSize: 13, decoration: TextDecoration.underline),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 22),
          CatalogSectionTitle('Selos de Confiança', color: muted),
          const SizedBox(height: 12),
          Wrap(
            spacing: 20,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              _TrustBadge(
                icon: Icons.verified_user_outlined,
                label: 'Compra segura',
                color: icons,
              ),
              _TrustBadge(
                icon: Icons.local_shipping_outlined,
                label: 'Entrega rápida',
                color: icons,
              ),
              _TrustBadge(
                icon: Icons.chat_outlined,
                label: 'Atendimento WhatsApp',
                color: icons,
              ),
            ],
          ),
          const SizedBox(height: 22),
          CatalogSectionTitle('Segurança', color: muted),
          const SizedBox(height: 12),
          Wrap(
            spacing: 22,
            children: [
              Image.asset(badgeSSL, height: 40, fit: BoxFit.contain),
              Image.asset(badgeGoogle, height: 40, fit: BoxFit.contain),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(color: Colors.white24),
          const SizedBox(height: 10),
          Text(
            '${(empresaRazao.isNotEmpty ? empresaRazao : lojaNome).toUpperCase()}'
            '${empresaCnpj.isNotEmpty ? '  •  CNPJ: $empresaCnpj' : ''}',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: muted,
              fontSize: 12.5,
              letterSpacing: .3,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrustBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _TrustBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: color, fontSize: 13)),
      ],
    );
  }
}

class _FaqTile extends StatefulWidget {
  final String pergunta;
  final String resposta;
  final Color textColor;
  final Color muted;

  const _FaqTile({
    required this.pergunta,
    required this.resposta,
    required this.textColor,
    required this.muted,
  });

  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.pergunta,
                        style: TextStyle(
                          color: widget.textColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      color: widget.muted,
                      size: 22,
                    ),
                  ],
                ),
                if (_expanded && widget.resposta.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    widget.resposta,
                    style: TextStyle(
                      color: widget.muted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

