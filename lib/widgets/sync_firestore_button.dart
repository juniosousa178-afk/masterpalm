// lib/widgets/sync_firestore_button.dart

import 'package:flutter/material.dart';
import '../services/sync_firestore_script.dart';

/// Botão de Admin para sincronizar TUDO com o Firestore
class SyncFirestoreButton extends StatefulWidget {
  const SyncFirestoreButton({super.key});

  @override
  State<SyncFirestoreButton> createState() => _SyncFirestoreButtonState();
}

class _SyncFirestoreButtonState extends State<SyncFirestoreButton> {
  bool _syncing = false;
  String _status = '';

  Future<void> _executarSync() async {
    setState(() {
      _syncing = true;
      _status = 'Sincronizando...';
    });

    try {
      final results = await SyncFirestoreScript.syncTudo();

      if (results['success'] == true) {
        final produtos = results['produtos'] as Map<String, int>;
        final clientes = results['clientes'] as Map<String, int>;
        final vendas = results['vendas'] as Map<String, int>;
        final categorias = results['categorias'] as Map<String, int>;

        setState(() {
          _status = '''
✅ Sincronização Completa!

Loja: ${results['lojaId']}

📦 Produtos: ${produtos['synced']} sincronizados
👥 Clientes: ${clientes['synced']} sincronizados
💰 Vendas: ${vendas['synced']} sincronizadas
🏷️ Categorias: ${categorias['synced']} sincronizadas
''';
          _syncing = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Dados sincronizados com sucesso!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        }

      } else {
        setState(() {
          _status = '❌ Erro na sincronização';
          _syncing = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Erro na sincronização'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }

    } catch (e) {
      setState(() {
        _status = '❌ Erro: $e';
        _syncing = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Row(
              children: [
                Icon(Icons.cloud_sync, size: 32, color: Colors.blue),
                SizedBox(width: 12),
                Text(
                  'Sincronizar dados',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Envia todos os dados do celular para a nuvem.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),

            if (_status.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _status,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(height: 16),
            ],

            ElevatedButton.icon(
              onPressed: _syncing ? null : _executarSync,
              icon: _syncing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              label: Text(_syncing ? 'Sincronizando...' : 'Sincronizar tudo'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),

            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _syncing ? null : () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await SyncFirestoreScript.syncApenasProdutos();
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('✅ Produtos sincronizados'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    },
                    icon: const Icon(Icons.inventory),
                    label: const Text('Só Produtos'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _syncing ? null : () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await SyncFirestoreScript.syncApenasVendas();
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('✅ Vendas sincronizadas'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    },
                    icon: const Icon(Icons.attach_money),
                    label: const Text('Só Vendas'),
                  ),
                ),
              ],
            ),

            const Divider(height: 32),

            const Text(
              '⚠️ ATENÇÃO',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
            ),
            const SizedBox(height: 8),
            const Text(
              '• Os dados do celular substituirão os dados na nuvem\n'
              '• Garanta que os dados locais estão corretos antes de sincronizar\n'
              '• A sincronização pode demorar alguns minutos se houver muitos dados',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
