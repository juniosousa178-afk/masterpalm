// lib/screens/public_catalog/widgets/catalog_error_loja_state.dart
// Estado de erro quando não foi possível carregar o catálogo (extraído de public_catalog_screen.dart)

import 'package:flutter/material.dart';

/// UI quando a loja não pôde ser carregada (link inválido, etc).
class CatalogErrorLojaState extends StatelessWidget {
  final ThemeData themeData;

  /// Motivo técnico ou de negócio (ex.: resolução de loja), sem expor dados sensíveis.
  final String? detailMessage;

  /// Se não nulo, substitui o título padrão (ex.: falha de render com loja já resolvida).
  final String? titleOverride;

  /// Quando falso, omite o rodapé com o exemplo de link (não se aplica a falha de resolução por URL).
  final bool showUrlHint;

  /// Texto técnico (ex. `?diag=1&traceCatalog=1`): contagens, fallback.reason, eventos.
  final String? diagnosticText;

  const CatalogErrorLojaState({
    super.key,
    required this.themeData,
    this.detailMessage,
    this.titleOverride,
    this.showUrlHint = true,
    this.diagnosticText,
  });

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: themeData,
      child: Scaffold(
        backgroundColor: themeData.scaffoldBackgroundColor,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.storefront_outlined,
                  size: 64,
                  color: themeData.colorScheme.onSurface.withOpacity(0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  titleOverride ?? 'Não foi possível carregar o catálogo.',
                  style: themeData.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                if (detailMessage != null && detailMessage!.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    detailMessage!.trim(),
                    style: themeData.textTheme.bodyMedium?.copyWith(
                      color: themeData.colorScheme.onSurface.withOpacity(0.85),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (diagnosticText != null && diagnosticText!.trim().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: Scrollbar(
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        child: SelectableText(
                          diagnosticText!.trim(),
                          style: themeData.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                if (showUrlHint) const SizedBox(height: 8),
                if (showUrlHint)
                  Text(
                    'Verifique se o link está correto e completo (ex: app.mastepalm.com.br/loja/nome-da-loja).',
                    style: themeData.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

