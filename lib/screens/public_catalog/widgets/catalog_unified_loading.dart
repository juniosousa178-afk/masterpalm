// Copy e layout únicos do carregamento do catálogo público (vitrine).

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Mensagens visíveis ao cliente (modo normal).
abstract final class CatalogUnifiedLoadingCopy {
  static const String title = 'Preparando sua loja...';
  static const String subtitle = 'Estamos carregando o catálogo para você.';
}

/// Corpo de loading alinhado ao `#initial-loader` do HTML (pill + título + subtítulo).
class CatalogUnifiedLoadingView extends StatelessWidget {
  const CatalogUnifiedLoadingView({
    super.key,
    this.nomeLoja,
    this.logoUrl,
    this.diagPhaseLabel,
    this.backgroundColor = const Color(0xFFF0F2F5),
  });

  final String? nomeLoja;
  final String? logoUrl;

  /// Só exibido com `?diag=1` (fase técnica; não altera copy principal).
  final String? diagPhaseLabel;

  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final nomeLojaSafe = (nomeLoja ?? '').trim();
    final logo = (logoUrl ?? '').trim();
    final hasLogo = logo.isNotEmpty;
    final showDiagPhase = kIsWeb &&
        Uri.base.queryParameters['diag'] == '1' &&
        (diagPhaseLabel ?? '').trim().isNotEmpty;

    Widget fallbackPill() {
      final label = nomeLojaSafe.isNotEmpty ? nomeLojaSafe : 'Catálogo';
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF9A4E6B),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      );
    }

    return ColoredBox(
      color: backgroundColor,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasLogo)
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxHeight: 72,
                      maxWidth: 220,
                    ),
                    child: Image.network(
                      logo,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (_, __, ___) => fallbackPill(),
                    ),
                  )
                else
                  fallbackPill(),
                const SizedBox(height: 36),
                Text(
                  CatalogUnifiedLoadingCopy.title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF111111),
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  CatalogUnifiedLoadingCopy.subtitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF666666),
                        height: 1.45,
                      ),
                ),
                if (showDiagPhase) ...[
                  const SizedBox(height: 10),
                  Text(
                    diagPhaseLabel!.trim(),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                          fontFamily: 'monospace',
                        ),
                  ),
                ],
                const SizedBox(height: 32),
                const SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Color(0xFF9A4E6B),
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
