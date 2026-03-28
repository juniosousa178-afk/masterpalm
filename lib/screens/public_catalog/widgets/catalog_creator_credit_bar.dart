import 'package:flutter/material.dart';

/// Crédito ao sistema MasterPalm no rodapé do catálogo (texto fixo no código — a loja não edita).
/// Rolagem junto com a página; toque abre o site oficial no navegador/app.
class CatalogCreatorCreditBar extends StatelessWidget {
  final Color backgroundColor;
  final Color textColor;
  final Color accentColor;
  final void Function(String url) onOpenUrl;

  static const String siteUrl = 'https://mastepalm.com.br';

  const CatalogCreatorCreditBar({
    super.key,
    required this.backgroundColor,
    required this.textColor,
    required this.accentColor,
    required this.onOpenUrl,
  });

  void _openSite() => onOpenUrl(siteUrl);

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
              color: textColor.withValues(alpha: 0.12),
              width: 1,
            ),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _openSite,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
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
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.15,
                        ),
                      ),
                      Text(
                        'MasterPalm',
                        style: TextStyle(
                          color: accentColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Icon(
                          Icons.open_in_new_rounded,
                          size: 14,
                          color: accentColor.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
