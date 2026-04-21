// Aviso para visitantes: compra sem cadastro; benefícios com conta (menu Entrar/Cadastrar).

import 'package:flutter/material.dart';

import '../../../services/cliente_auth_service.dart';

class CatalogGuestOptionalLoginBanner extends StatefulWidget {
  final int authRetryKey;
  final Color textColor;
  final Color cardColor;
  final Color primaryColor;

  const CatalogGuestOptionalLoginBanner({
    super.key,
    required this.authRetryKey,
    required this.textColor,
    required this.cardColor,
    required this.primaryColor,
  });

  @override
  State<CatalogGuestOptionalLoginBanner> createState() =>
      _CatalogGuestOptionalLoginBannerState();
}

class _CatalogGuestOptionalLoginBannerState
    extends State<CatalogGuestOptionalLoginBanner> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    return FutureBuilder<Map<String, dynamic>?>(
      key: ValueKey<int>(widget.authRetryKey),
      future: ClienteAuthService.getClienteLogado(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        if (snap.data != null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Material(
            color: Color.alphaBlend(
              widget.primaryColor.withOpacity(0.08),
              widget.cardColor,
            ),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    color: widget.primaryColor,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Você pode navegar e comprar sem cadastro. Para acompanhar '
                      'pedidos, cupons e sorteios quando a loja oferecer, use '
                      'Entrar ou Cadastrar no menu.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.38,
                        color: widget.textColor.withOpacity(0.9),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fechar',
                    onPressed: () => setState(() => _dismissed = true),
                    icon: Icon(
                      Icons.close,
                      size: 20,
                      color: widget.textColor.withOpacity(0.55),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
