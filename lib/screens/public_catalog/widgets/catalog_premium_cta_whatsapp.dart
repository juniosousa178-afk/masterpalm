// lib/screens/public_catalog/widgets/catalog_premium_cta_whatsapp.dart
// CTA flutuante "Fale conosco" – layout premium. Só exibe quando há WhatsApp.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Botão flutuante "Fale conosco" (WhatsApp) para layout premium.
class CatalogPremiumCtaWhatsapp extends StatelessWidget {
  final String whatsappUrl;
  final Color primaryColor;

  const CatalogPremiumCtaWhatsapp({
    super.key,
    required this.whatsappUrl,
    required this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    if (whatsappUrl.trim().isEmpty) return const SizedBox.shrink();

    // Acima do botão IA (bottom 100) e do FAB do carrinho
    const bottomOffset = 170.0;

    return Positioned(
      right: 16,
      bottom: bottomOffset,
      child: Material(
        elevation: 4,
        color: const Color(0xFF25D366),
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          onTap: () async {
            var url = whatsappUrl.trim();
            if (!url.startsWith('http') && !url.startsWith('wa.me')) {
              final digits = url.replaceAll(RegExp(r'\D'), '');
              if (digits.isNotEmpty) {
                url = 'https://wa.me/55$digits';
              }
            }
            final uri = Uri.tryParse(url);
            if (uri != null && await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
          borderRadius: BorderRadius.circular(28),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chat, color: Colors.white, size: 22),
                SizedBox(width: 8),
                Text(
                  'Fale conosco',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
