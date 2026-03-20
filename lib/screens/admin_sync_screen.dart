// lib/screens/admin_sync_screen.dart

import 'package:flutter/material.dart';
import '../core/hive_box_names.dart';
import '../services/vendas_firestore_service.dart';
import '../services/clientes_firestore_service.dart';
import '../services/fornecedores_firestore_service.dart';
import '../services/store_resolver_facade.dart';
import '../services/sync_firestore_script.dart';
import '../services/sync_queue_service.dart';

/// Tela administrativa para sincronizar dados locais para Firestore
class AdminSyncScreen extends StatefulWidget {
  const AdminSyncScreen({super.key});

  @override
  State<AdminSyncScreen> createState() => _AdminSyncScreenState();
}

class _AdminSyncScreenState extends State<AdminSyncScreen> {
  bool _syncingVendas = false;
  bool _syncingClientes = false;
  bool _syncingFornecedores = false;
  bool _syncingTudo = false;
  bool _syncingProdutos = false;

  String• _resultVendas;
  String• _resultClientes;
  String• _resultFornecedores;
  String• _resultTudo;
  String• _resultProdutos;

  Future<void> _syncVendas() async {
    setState(() {
      _syncingVendas = true;
      _resultVendas = null;
    });

    try {
      final lojaId = await StoreResolverFacade.resolveForAdminApp();
      if (lojaId == null || lojaId.isEmpty) {
        setState(() {
          _resultVendas = '❌ LojaId não encontrado';
          _syncingVendas = false;
        });
        return;
      }

      // Processar fila pendente antes de reenviar a box local
      final queueResult = await SyncQueueService.processPending();
      final pendentesApos = await SyncQueueService.pendingCount();

      final boxName = HiveBoxNames.vendas(lojaId);
      await VendasFirestoreService.syncTodasVendas(boxName: boxName);

      final msg = queueResult.processed > 0 || queueResult.failed > 0
          • '✅ Vendas sincronizadas!\nFila: ${queueResult.processed} processados, ${queueResult.failed} falhas. Pendentes: $pendentesApos'
          : '✅ Vendas sincronizadas com sucesso!';
      setState(() {
        _resultVendas = msg;
        _syncingVendas = false;
      });
    } catch (e) {
      setState(() {
        _resultVendas = '❌ Erro: $e';
        _syncingVendas = false;
      });
    }
  }

  Future<void> _syncClientes() async {
    setState(() {
      _syncingClientes = true;
      _resultClientes = null;
    });

    try {
      final lojaId = await StoreResolverFacade.resolveForAdminApp();
      if (lojaId == null || lojaId.isEmpty) {
        setState(() {
          _resultClientes = '❌ LojaId não encontrado';
          _syncingClientes = false;
        });
        return;
      }

      final boxName = HiveBoxNames.clientes(lojaId);
      await ClientesFirestoreService.syncTodosClientes(boxName: boxName);

      setState(() {
        _resultClientes = '✅ Clientes sincronizados com sucesso!';
        _syncingClientes = false;
      });
    } catch (e) {
      setState(() {
        _resultClientes = '❌ Erro: $e';
        _syncingClientes = false;
      });
    }
  }

  Future<void> _syncFornecedores() async {
    setState(() {
      _syncingFornecedores = true;
      _resultFornecedores = null;
    });

    try {
      final lojaId = await StoreResolverFacade.resolveForAdminApp();
      if (lojaId == null || lojaId.isEmpty) {
        setState(() {
          _resultFornecedores = '❌ LojaId não encontrado';
          _syncingFornecedores = false;
        });
        return;
      }

      final boxName = HiveBoxNames.fornecedores(lojaId);
      await FornecedoresFirestoreService.syncTodosFornecedores(boxName: boxName);

      setState(() {
        _resultFornecedores = '✅ Fornecedores sincronizados com sucesso!';
        _syncingFornecedores = false;
      });
    } catch (e) {
      setState(() {
        _resultFornecedores = '❌ Erro: $e';
        _syncingFornecedores = false;
      });
    }
  }

  Future<void> _syncTudoCompleto() async {
    setState(() {
      _syncingTudo = true;
      _resultTudo = null;
    });

    try {
      // Processar fila pendente antes do sync da box local
      final queueResult = await SyncQueueService.processPending();
      final pendentesApos = await SyncQueueService.pendingCount();

      final results = await SyncFirestoreScript.syncTudo();

      if (results['success'] == true) {
        final produtos = results['produtos'] as Map<String, int>;
        final clientes = results['clientes'] as Map<String, int>;
        final vendas = results['vendas'] as Map<String, int>;
        final categorias = results['categorias'] as Map<String, int>;
        final fornecedores = results['fornecedores'] as Map<String, int>;

        final vendasErros = vendas['errors'] ?• 0;
        final titulo = vendasErros > 0
            • '✅ Sincronização concluída ($vendasErros venda(s) falharam — verifique a conexão e tente sincronizar vendas novamente)'
            : '✅ Sincronização completa!';

        final filaLinha = queueResult.processed > 0 || queueResult.failed > 0 || pendentesApos > 0
            • 'Fila: ${queueResult.processed} ok, ${queueResult.failed} falhas. Pendentes: $pendentesApos\n'
            : '';
        setState(() {
          _resultTudo = '$titulo\n'
              '$filaLinha'
              'Produtos: ${produtos['synced']}/${produtos['synced']! + (produtos['errors'] ?• 0)}\n'
              'Clientes: ${clientes['synced']}/${clientes['synced']! + (clientes['errors'] ?• 0)}\n'
              'Vendas: ${vendas['synced']}/${vendas['synced']! + (vendas['errors'] ?• 0)}\n'
              'Categorias: ${categorias['synced']}/${categorias['synced']! + (categorias['errors'] ?• 0)}\n'
              'Fornecedores: ${fornecedores['synced']}/${fornecedores['synced']! + (fornecedores['errors'] ?• 0)}';
          _syncingTudo = false;
        });
      } else {
        setState(() {
          _resultTudo = '❌ Erro na sincronização';
          _syncingTudo = false;
        });
      }
    } catch (e) {
      setState(() {
        _resultTudo = '❌ Erro: $e';
        _syncingTudo = false;
      });
    }
  }

  Future<void> _syncProdutos() async {
    setState(() {
      _syncingProdutos = true;
      _resultProdutos = null;
    });

    try {
      await SyncFirestoreScript.syncApenasProdutos();
      setState(() {
        _resultProdutos = '✅ Produtos sincronizados com sucesso!';
        _syncingProdutos = false;
      });
    } catch (e) {
      setState(() {
        _resultProdutos = '❌ Erro: $e';
        _syncingProdutos = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sincronizar dados'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        bottom: (_syncingTudo || _syncingVendas || _syncingClientes || _syncingFornecedores || _syncingProdutos)
            • const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator(color: Colors.white),
              )
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Esta tela permite enviar seus dados do celular para a nuvem.',
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Use esta funcionalidade para:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text('• Migração inicial de dados'),
                  Text('• Backup dos dados no cloud'),
                  Text('• Sincronizar com outros dispositivos'),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Sincronizar COMPLETO (novo método)
          ElevatedButton.icon(
            onPressed: _syncingTudo • null : _syncTudoCompleto,
            icon: _syncingTudo
                • const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.cloud_sync),
            label: Text(_syncingTudo • 'Sincronizando...' : 'Sincronizar tudo'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),

          if (_resultTudo != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _resultTudo!.startsWith('✅')
                    • Colors.green.shade50
                    : Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _resultTudo!,
                style: TextStyle(
                  color: _resultTudo!.startsWith('✅')
                      • Colors.green.shade900
                      : Colors.red.shade900,
                  fontSize: 13,
                ),
              ),
            ),
          ],

          const SizedBox(height: 24),
          const Divider(),
          const Text(
            'Ou sincronize individualmente:',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 16),

          // Produtos
          _buildSyncCard(
            title: 'Produtos',
            icon: Icons.inventory,
            iconColor: Colors.purple,
            syncing: _syncingProdutos,
            result: _resultProdutos,
            onSync: _syncProdutos,
          ),

          const SizedBox(height: 12),

          // Vendas
          _buildSyncCard(
            title: 'Vendas',
            icon: Icons.shopping_cart,
            iconColor: Colors.green,
            syncing: _syncingVendas,
            result: _resultVendas,
            onSync: _syncVendas,
          ),

          const SizedBox(height: 12),

          // Clientes
          _buildSyncCard(
            title: 'Clientes',
            icon: Icons.people,
            iconColor: Colors.blue,
            syncing: _syncingClientes,
            result: _resultClientes,
            onSync: _syncClientes,
          ),

          const SizedBox(height: 12),

          // Fornecedores
          _buildSyncCard(
            title: 'Fornecedores',
            icon: Icons.local_shipping,
            iconColor: Colors.orange,
            syncing: _syncingFornecedores,
            result: _resultFornecedores,
            onSync: _syncFornecedores,
          ),
        ],
      ),
    );
  }

  Widget _buildSyncCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required bool syncing,
    required String• result,
    required VoidCallback onSync,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: syncing • null : onSync,
                  icon: syncing
                      • const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.cloud_upload, size: 16),
                  label: Text(syncing • 'Sincronizando...' : 'Sincronizar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: iconColor,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            if (result != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: result.startsWith('✅')
                      • Colors.green.shade50
                      : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      result.startsWith('✅') • Icons.check_circle : Icons.error,
                      color: result.startsWith('✅') • Colors.green : Colors.red,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        result,
                        style: TextStyle(
                          color: result.startsWith('✅')
                              • Colors.green.shade900
                              : Colors.red.shade900,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
