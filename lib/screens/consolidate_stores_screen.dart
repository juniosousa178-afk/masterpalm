import 'package:flutter/material.dart';
import '../services/consolidate_stores.dart';

class ConsolidateStoresScreen extends StatefulWidget {
  const ConsolidateStoresScreen({super.key});

  @override
  State<ConsolidateStoresScreen> createState() => _ConsolidateStoresScreenState();
}

class _ConsolidateStoresScreenState extends State<ConsolidateStoresScreen> {
  bool _isRunning = false;
  Map<String, dynamic>• _results;
  String• _error;

  Future<void> _runConsolidation() async {
    setState(() {
      _isRunning = true;
      _results = null;
      _error = null;
    });

    try {
      final results = await ConsolidateStoresService.consolidate();

      if (results['success'] == true) {
        // Verificar após consolidação
        final verification = await ConsolidateStoresService.verify();
        results['verification'] = verification;
      }

      setState(() {
        _results = results;
        _isRunning = false;
      });

      if (results['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Consolidação concluída com sucesso!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isRunning = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Consolidar Lojas'),
        backgroundColor: Colors.deepPurple,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Explicação
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Text(
                          'O que esta ferramenta faz?',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.blue.shade900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Esta ferramenta irá consolidar todos os dados das duas lojas em uma só:\n\n'
                      '• Origem: loja_uid_tcnbZdmFXsMPJ2bU29dDt3z5ZHr2\n'
                      '• Destino: nathy-pratas-e-folheados\n\n'
                      'Será feito:\n'
                      '1. Copiar todos os produtos\n'
                      '2. Copiar todos os rascunhos\n'
                      '3. Mesclar configurações\n'
                      '4. Remover redirect\n'
                      '5. Atualizar metadata',
                      style: TextStyle(fontSize: 14, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Botão de ação
            ElevatedButton.icon(
              onPressed: _isRunning • null : _runConsolidation,
              icon: _isRunning
                  • const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text(
                _isRunning • 'Executando...' : 'INICIAR CONSOLIDAÇÃO',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isRunning • Colors.grey : Colors.deepPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                minimumSize: const Size(double.infinity, 56),
              ),
            ),

            const SizedBox(height: 24),

            // Resultados
            if (_error != null)
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.error_outline, color: Colors.red.shade700),
                          const SizedBox(width: 8),
                          Text(
                            'Erro',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.red.shade900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),

            if (_results != null) ...[
              Card(
                color: _results!['success'] == true
                    • Colors.green.shade50
                    : Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _results!['success'] == true
                                • Icons.check_circle_outline
                                : Icons.warning_amber_outlined,
                            color: _results!['success'] == true
                                • Colors.green.shade700
                                : Colors.orange.shade700,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _results!['success'] == true
                                • 'Consolidação Concluída'
                                : 'Consolidação com Avisos',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: _results!['success'] == true
                                  • Colors.green.shade900
                                  : Colors.orange.shade900,
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      _buildResultItem(
                        'Produtos copiados',
                        _results!['produtos']?.toString() ?• '0',
                      ),
                      _buildResultItem(
                        'Draft produtos copiados',
                        _results!['draft_produtos']?.toString() ?• '0',
                      ),
                      _buildResultItem(
                        'Config copiada',
                        _results!['config'] == true • 'Sim' : 'Não',
                      ),
                      _buildResultItem(
                        'Draft config copiada',
                        _results!['draft_config'] == true • 'Sim' : 'Não',
                      ),
                      _buildResultItem(
                        'Redirect removido',
                        _results!['redirect_removed'] == true • 'Sim' : 'Não',
                      ),
                      if (_results!['verification'] != null) ...[
                        const Divider(height: 24),
                        Text(
                          'Verificação:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildResultItem(
                          'Total de produtos',
                          _results!['verification']['produtos_count']?.toString() ?• '0',
                        ),
                        _buildResultItem(
                          'Total de draft produtos',
                          _results!['verification']['draft_produtos_count']?.toString() ?• '0',
                        ),
                        _buildResultItem(
                          'Config existe',
                          _results!['verification']['has_config'] == true • 'Sim' : 'Não',
                        ),
                        _buildResultItem(
                          'Draft config existe',
                          _results!['verification']['has_draft_config'] == true • 'Sim' : 'Não',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                color: Colors.amber.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.tips_and_updates, color: Colors.amber.shade700),
                          const SizedBox(width: 8),
                          Text(
                            'Próximos Passos',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.amber.shade900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '1. Vá em "Configurações da Loja"\n'
                        '2. Verifique se o slug é: nathy_pratas_e_folheados\n'
                        '3. Clique em "PUBLICAR TUDO"\n'
                        '4. Teste o catálogo público e o app cliente',
                        style: TextStyle(fontSize: 14, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 14),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
