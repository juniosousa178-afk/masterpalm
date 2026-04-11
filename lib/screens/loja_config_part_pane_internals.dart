// Textos introdutórios muted, faixa offline e peças visuais repetidas nos painéis.
// Etapa 6 blast-radius: só UI; callbacks explícitos.

part of 'loja_config_screen.dart';

/// Parágrafo introdutório cinza (padrão dos painéis Menu, Dicas, Financeiro, etc.).
class _PaneMutedIntroText extends StatelessWidget {
  const _PaneMutedIntroText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(color: Colors.black54),
    );
  }
}

/// Faixa “sem conexão” (hub e vista de módulo fullscreen).
class _LojaConfigOfflineConnectivityStripe extends StatelessWidget {
  const _LojaConfigOfflineConnectivityStripe({required this.onVerificar});

  final VoidCallback onVerificar;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: _LojaConfigScreenState._warningColor.withValues(alpha: 0.15),
      child: Row(
        children: [
          const Icon(Icons.wifi_off,
              color: _LojaConfigScreenState._warningColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Sem conexão. As alterações serão salvas localmente e sincronizadas quando a conexão voltar.',
              style: TextStyle(fontSize: 13, color: Colors.grey[800]),
            ),
          ),
          TextButton(
            onPressed: onVerificar,
            child: const Text('Verificar'),
          ),
        ],
      ),
    );
  }
}
