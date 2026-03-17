// lib/screens/configure_loja_placeholder_screen.dart
// Exibido quando o usuário ainda não tem loja configurada.
// Nunca abre "Minha Loja" ou outra loja; direciona para configuração.

import 'package:flutter/material.dart';

/// Tela exibida quando o usuário não tem loja. Botão central direciona para /loja_config.
class ConfigureLojaPlaceholderScreen extends StatelessWidget {
  const ConfigureLojaPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final surfaceColor = theme.colorScheme.surface;
    final onSurface = theme.colorScheme.onSurface;

    return Scaffold(
      backgroundColor: surfaceColor,
      appBar: AppBar(
        title: const Text('Catálogo'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.store_outlined,
                size: 80,
                color: primaryColor.withValues(alpha:0.5),
              ),
              const SizedBox(height: 24),
              Text(
                'Configure sua loja online',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: onSurface,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Personalize seu catálogo, identidade e layout para começar a vender.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: onSurface.withValues(alpha:0.7),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pushReplacementNamed(
                    context,
                    '/configuracoes_catalogo',
                  ),
                  icon: const Icon(Icons.settings, size: 22),
                  label: const Text('Configure sua loja online'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: theme.colorScheme.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
