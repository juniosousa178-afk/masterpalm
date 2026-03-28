import 'package:flutter/material.dart';

/// Rodapé fixo com crédito ao criador da plataforma (sempre visível na base da tela).
class CatalogCreatorCreditBar extends StatelessWidget {
  final Color backgroundColor;
  final Color textColor;
  final Color accentColor;
  final void Function(String url) onOpenUrl;

  static const String siteUrl = 'https://mastepalm.com.br';
  static const String displayEmail = 'contato@mastepalm.com.br';

  const CatalogCreatorCreditBar({
    super.key,
    required this.backgroundColor,
    required this.textColor,
    required this.accentColor,
    required this.onOpenUrl,
  });

  @override
  Widget build(BuildContext context) {
    final muted = textColor.withValues(alpha: 0.72);
    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: backgroundColor,
          border: Border(
            top: BorderSide(
              color: textColor.withValues(alpha: 0.08),
              width: 1,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Criado por ',
                      style: TextStyle(
                        color: muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0.2,
                      ),
                    ),
                    Text(
                      'Master Palm',
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        '·',
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                    ),
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => onOpenUrl(siteUrl),
                        child: Text(
                          displayEmail,
                          style: TextStyle(
                            color: accentColor.withValues(alpha: 0.92),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            decoration: TextDecoration.underline,
                            decorationColor:
                                accentColor.withValues(alpha: 0.45),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Altura aproximada da barra + SafeArea inferior (para posicionar FAB / overlays).
double catalogCreatorCreditBarReserveHeight(BuildContext context) {
  final pad = MediaQuery.paddingOf(context).bottom;
  return 44 + pad;
}
