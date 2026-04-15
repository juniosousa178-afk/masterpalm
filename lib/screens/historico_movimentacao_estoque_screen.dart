// lib/screens/historico_movimentacao_estoque_screen.dart
// Histórico de entradas e saídas de estoque.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/loja_id_service.dart';
import '../services/movimentacao_estoque_service.dart';

const Color _primaryColor = Color(0xFF6366F1);
const Color _successColor = Color(0xFF22C55E);
const Color _errorColor = Color(0xFFEF4444);
const Color _backgroundColor = Color(0xFFF8FAFC);

class HistoricoMovimentacaoEstoqueScreen extends StatefulWidget {
  final String lojaId;

  const HistoricoMovimentacaoEstoqueScreen({required this.lojaId, super.key});

  @override
  State<HistoricoMovimentacaoEstoqueScreen> createState() =>
      _HistoricoMovimentacaoEstoqueScreenState();
}

class _HistoricoMovimentacaoEstoqueScreenState
    extends State<HistoricoMovimentacaoEstoqueScreen> {
  bool _loading = true;
  bool _erroResolucaoLoja = false;
  String? _lojaId;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    String? id = widget.lojaId.trim().isNotEmpty ? widget.lojaId : null;
    id ??= await LojaIdService.getWithTimeout(timeout: const Duration(seconds: 10));
    if (!mounted) return;
    if (id == null || id.trim().isEmpty) {
      setState(() {
        _loading = false;
        _erroResolucaoLoja = true;
      });
      return;
    }
    setState(() {
      _lojaId = id;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_erroResolucaoLoja) {
      return Scaffold(
        backgroundColor: _backgroundColor,
        appBar: AppBar(
          backgroundColor: _primaryColor,
          foregroundColor: Colors.white,
          title: const Text('Histórico de movimentação', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.store_mall_directory_outlined, size: 64, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text(
                  'Não foi possível identificar a loja.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      _loading = true;
                      _erroResolucaoLoja = false;
                      _lojaId = null;
                    });
                    _init();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Tentar novamente'),
                  style: FilledButton.styleFrom(backgroundColor: _primaryColor),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_loading || _lojaId == null) {
      return Scaffold(
        backgroundColor: _backgroundColor,
        appBar: AppBar(
          backgroundColor: _primaryColor,
          foregroundColor: Colors.white,
          title: const Text('Histórico de movimentação', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        body: const Center(child: CircularProgressIndicator(color: _primaryColor)),
      );
    }
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        title: const Text(
          'Histórico de movimentação',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: MovimentacaoEstoqueService.streamMovimentacoes(
                lojaId: _lojaId!,
              ),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline, size: 64, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          Text(
                            'Erro ao carregar: ${snapshot.error}',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: _primaryColor));
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text(
                          'Nenhuma movimentação registrada ainda.',
                          style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Vendas e ajustes aparecerão aqui.',
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => setState(() {}),
                  color: _primaryColor,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: docs.length,
                    itemBuilder: (_, i) {
                      final d = docs[i].data();
                      final tipo = (d['tipo'] ?? 'saida').toString();
                      final produtoNome = (d['produtoNome'] ?? '').toString();
                      final qtd = (d['quantidade'] as num?)?.toInt() ?? 0;
                      final motivo = (d['motivo'] ?? '').toString();
                      final usuario = (d['usuario'] ?? 'App').toString();
                      final ts = d['data'];
                      final data = ts is Timestamp ? ts.toDate() : DateTime.now();
                      final isEntrada = tipo == 'entrada';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isEntrada
                                ? _successColor.withOpacity(0.2)
                                : _errorColor.withOpacity(0.2),
                            child: Icon(
                              isEntrada ? Icons.add : Icons.remove,
                              color: isEntrada ? _successColor : _errorColor,
                              size: 22,
                            ),
                          ),
                          title: Text(
                            produtoNome,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${isEntrada ? '+' : '-'}$qtd · ${motivo.isNotEmpty ? motivo : usuario} · ${DateFormat('dd/MM HH:mm').format(data)}',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                          trailing: Text(
                            '${isEntrada ? '+' : '-'}$qtd',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isEntrada ? _successColor : _errorColor,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}

