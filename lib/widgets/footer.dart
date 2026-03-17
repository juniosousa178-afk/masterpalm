// lib/widgets/footer.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../utils/instagram_launcher.dart';

class Footer extends StatelessWidget {
  final Color bg;
  final Color textColor;
  final String lojaNome;
  final String? instagramUrl;
  final String? facebookUrl;
  final String? atendimentoWhatsapp;
  final List<Map<String, String>> links;
  final List<String> paymentCodes;
  final Map<String, String> paymentAsset;
  final String badgeSSL;
  final String badgeGoogle;
  final String empresaRazao;
  final String empresaCnpj;
  final void Function(String url)? onOpenUrl;
  final VoidCallback? onOpenWhatsapp;

  const Footer({
    super.key,
    required this.bg,
    required this.textColor,
    required this.lojaNome,
    this.instagramUrl,
    this.facebookUrl,
    this.atendimentoWhatsapp,
    required this.links,
    required this.paymentCodes,
    required this.paymentAsset,
    required this.badgeSSL,
    required this.badgeGoogle,
    required this.empresaRazao,
    required this.empresaCnpj,
    this.onOpenUrl,
    this.onOpenWhatsapp,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            lojaNome,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '© ${DateTime.now().year} $lojaNome - Todos os direitos reservados',
            style: TextStyle(
                color: textColor.withValues(alpha:0.7), fontSize: 13),
          ),
          const SizedBox(height: 24),

          // --- REDES SOCIAIS ---
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              if ((instagramUrl ?? '').trim().isNotEmpty)
                _socialButton(
                  iconWidget:
                      const FaIcon(FontAwesomeIcons.instagram, size: 18),
                  label: 'Instagram',
                  url: instagramUrl!.trim(),
                  color: textColor,
                  onOpenUrl: onOpenUrl,
                  isInstagram: true,
                ),
              if ((facebookUrl ?? '').trim().isNotEmpty)
                _socialButton(
                  iconWidget: const FaIcon(FontAwesomeIcons.facebook, size: 18),
                  label: 'Facebook',
                  url: facebookUrl!.trim(),
                  color: textColor,
                  onOpenUrl: onOpenUrl,
                ),
              if ((atendimentoWhatsapp ?? '').trim().isNotEmpty)
                _socialButton(
                  iconWidget: const FaIcon(FontAwesomeIcons.whatsapp, size: 18),
                  label: 'WhatsApp',
                  url:
                      'https://wa.me/${atendimentoWhatsapp!.replaceAll(RegExp(r'\D'), '')}',
                  color: textColor,
                  onOpenUrl: onOpenWhatsapp != null
                      ? (_) => onOpenWhatsapp!()
                      : onOpenUrl,
                ),
            ],
          ),

          const SizedBox(height: 24),
          // Links (opcional)
          if (links.isNotEmpty) ...[
            SectionTitle(
                title: 'Links', color: textColor.withValues(alpha:0.8)),
            const SizedBox(height: 8),
            Column(
              children: links
                  .map((m) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: InkWell(
                          onTap: (m['url'] ?? '').isEmpty
                              ? null
                              : () async {
                                  final u = m['url']!;
                                  if (onOpenUrl != null) {
                                    onOpenUrl!(u);
                                  } else {
                                    await launchUrl(Uri.parse(u),
                                        mode: LaunchMode.externalApplication);
                                  }
                                },
                          child: Text(
                            m['label'] ?? '',
                            style: TextStyle(color: textColor, fontSize: 15),
                          ),
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 24),
          ],

          SectionTitle(title: 'Formas de Pagamento', color: textColor),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: paymentCodes.map((c) {
              final asset = paymentAsset[c];
              if (asset == null) return const SizedBox.shrink();
              return Image.asset(asset, height: 26, fit: BoxFit.contain);
            }).toList(),
          ),

          const SizedBox(height: 24),
          SectionTitle(title: 'Segurança', color: textColor),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            alignment: WrapAlignment.center,
            children: [
              Image.asset(badgeSSL, height: 32, fit: BoxFit.contain),
              Image.asset(badgeGoogle, height: 32, fit: BoxFit.contain),
            ],
          ),

          const SizedBox(height: 24),
          Text(
            empresaRazao,
            textAlign: TextAlign.center,
            style: TextStyle(color: textColor.withValues(alpha:0.8)),
          ),
          if (empresaCnpj.trim().isNotEmpty)
            Text(
              'CNPJ: $empresaCnpj',
              textAlign: TextAlign.center,
              style: TextStyle(color: textColor.withValues(alpha:0.8)),
            ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  static Widget _socialButton({
    required Widget iconWidget,
    required String label,
    required String url,
    required Color color,
    void Function(String)? onOpenUrl,
    bool isInstagram = false,
  }) {
    return InkWell(
      onTap: () async {
        if (onOpenUrl != null) {
          onOpenUrl(url);
        } else if (isInstagram && await openInstagramInApp(url)) {
          // Abre no app do Instagram no mobile
        } else {
          String finalUrl = url;
          if (isInstagram && !url.startsWith('http')) {
            final user = url.replaceFirst(RegExp(r'^@'), '').trim();
            finalUrl = 'https://www.instagram.com/$user/';
          }
          await launchUrl(Uri.parse(finalUrl), mode: LaunchMode.externalApplication);
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha:0.4)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            iconWidget,
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: color)),
          ],
        ),
      ),
    );
  }
}

// ===============================
// SectionTitle
// ===============================
class SectionTitle extends StatelessWidget {
  final String title;
  final Color color;

  const SectionTitle({
    super.key,
    required this.title,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        color: color,
        fontSize: 16,
        fontWeight: FontWeight.bold,
      ),
      textAlign: TextAlign.center,
    );
  }
}

