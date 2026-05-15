// lib/screens/public_catalog/widgets/catalog_vitrine_visual_states.dart
// Estados visuais leves da vitrine (loading / vazio / erro) — só apresentação.

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

/// Carregamento inicial (resolução de loja).
class CatalogVitrineLoadingState extends StatelessWidget {
  const CatalogVitrineLoadingState({super.key, required this.themeData});

  final ThemeData themeData;

  @override
  Widget build(BuildContext context) {
    final c = themeData.colorScheme;
    return Theme(
      data: themeData,
      child: Scaffold(
        backgroundColor: themeData.scaffoldBackgroundColor,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.storefront_outlined, size: 48, color: c.primary),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: 52,
                    height: 52,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: c.primary,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Carregando loja',
                    textAlign: TextAlign.center,
                    style: themeData.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: c.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Estamos preparando a vitrine para você.',
                    textAlign: TextAlign.center,
                    style: themeData.textTheme.bodyMedium?.copyWith(
                      color: c.onSurface.withOpacity(0.72),
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Aguardando configuração (stream de config).
class CatalogVitrineConfigLoadingState extends StatelessWidget {
  const CatalogVitrineConfigLoadingState({super.key, this.themeData});

  final ThemeData? themeData;

  @override
  Widget build(BuildContext context) {
    final theme = themeData ?? Theme.of(context);
    final c = theme.colorScheme;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  minHeight: 3,
                  borderRadius: BorderRadius.circular(2),
                  color: c.primary,
                  backgroundColor: c.primary.withOpacity(0.12),
                ),
                const SizedBox(height: 28),
                Text(
                  'Carregando vitrine',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: c.onSurface,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Buscando configurações e produtos da loja…',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: c.onSurface.withOpacity(0.72),
                    height: 1.45,
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

/// Config da loja ausente ou vazia.
class CatalogVitrineConfigErrorState extends StatelessWidget {
  const CatalogVitrineConfigErrorState({super.key, this.themeData});

  final ThemeData? themeData;

  @override
  Widget build(BuildContext context) {
    final theme = themeData ?? Theme.of(context);
    final c = theme.colorScheme;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.inventory_2_outlined,
                    size: 56, color: c.error.withOpacity(0.85)),
                const SizedBox(height: 20),
                Text(
                  'Loja ainda sem vitrine',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: c.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Não encontramos a configuração publicada desta loja. '
                  'Se você é o dono, publique o catálogo no painel MasterPalm.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: c.onSurface.withOpacity(0.78),
                    height: 1.45,
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

/// Lista de produtos vazia (sliver).
class CatalogVitrineEmptyProductsSliver extends StatelessWidget {
  const CatalogVitrineEmptyProductsSliver({
    super.key,
    this.message,
    this.textColor,
  });

  final String? message;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = theme.colorScheme;
    final title = message?.trim().isNotEmpty == true
        ? message!.trim()
        : 'Nenhum produto disponível no momento.';
    const subtitle =
        'Tente outra categoria, limpe a busca ou volte mais tarde.';
    final titleColor = textColor ?? c.onSurface;
    final subColor = textColor != null
        ? titleColor.withOpacity(0.75)
        : c.onSurface.withOpacity(0.65);

    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shopping_bag_outlined,
                  size: 52, color: c.primary.withOpacity(0.55)),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: titleColor,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: subColor,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Loja não carregou / link inválido / falha de render (mesma API que [CatalogErrorLojaState]).
class CatalogVitrineErrorLojaState extends StatelessWidget {
  const CatalogVitrineErrorLojaState({
    super.key,
    required this.themeData,
    this.detailMessage,
    this.titleOverride,
    this.showUrlHint = true,
    this.diagnosticText,
  });

  final ThemeData themeData;
  final String? detailMessage;
  final String? titleOverride;
  final bool showUrlHint;
  final String? diagnosticText;

  @override
  Widget build(BuildContext context) {
    final c = themeData.colorScheme;
    return Theme(
      data: themeData,
      child: Scaffold(
        backgroundColor: themeData.scaffoldBackgroundColor,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.travel_explore_outlined,
                        size: 56, color: c.error.withOpacity(0.88)),
                    const SizedBox(height: 20),
                    Text(
                      titleOverride ?? 'Não foi possível carregar o catálogo.',
                      style: themeData.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: c.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (detailMessage != null &&
                        detailMessage!.trim().isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        detailMessage!.trim(),
                        style: themeData.textTheme.bodyMedium?.copyWith(
                          color: c.onSurface.withOpacity(0.88),
                          height: 1.45,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    if (diagnosticText != null &&
                        diagnosticText!.trim().isNotEmpty) ...[
                      const SizedBox(height: 18),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 260),
                        child: Scrollbar(
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            child: SelectableText(
                              diagnosticText!.trim(),
                              style: themeData.textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                height: 1.35,
                                color: c.onSurface.withOpacity(0.75),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (showUrlHint) ...[
                      const SizedBox(height: 18),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: c.surfaceContainerHighest.withOpacity(0.35),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: c.outline.withOpacity(0.25),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Text(
                            'Verifique se o link está correto e completo '
                            '(ex.: app.mastepalm.com.br/loja/nome-da-loja).',
                            style: themeData.textTheme.bodySmall?.copyWith(
                              color: c.onSurface.withOpacity(0.8),
                              height: 1.4,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ],
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

/// Erro ao carregar stream de produtos (com retry).
class CatalogVitrineProductsStreamError extends StatelessWidget {
  const CatalogVitrineProductsStreamError({
    super.key,
    required this.onRetry,
    this.error,
  });

  final VoidCallback onRetry;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = theme.colorScheme;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi_find_rounded,
                    size: 56, color: c.error.withOpacity(0.9)),
                const SizedBox(height: 20),
                Text(
                  'Não conseguimos carregar os produtos',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: c.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  kDebugMode && error != null
                      ? error.toString()
                      : 'Pode ser uma instabilidade na rede ou nos servidores. '
                          'Toque abaixo para tentar de novo.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: c.onSurface.withOpacity(0.78),
                    height: 1.45,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: kDebugMode ? 8 : 5,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 26),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 20),
                  label: const Text('Tentar novamente'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
