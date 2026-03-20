// lib/screens/relatorio_ranking_clientes_screen.dart
// Ranking de clientes por total comprado e quantidade de pedidos. Melhoria de dashboard.

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';

import '../core/hive_box_names.dart';
import '../core/loja_id_adapter.dart';
import '../services/loja_id_service.dart';
import '../models/venda.dart';

const Color _primaryColor = Color(0xFF6366F1);
const Color _successColor = Color(0xFF22C55E);
const Color _cardColor = Color(0xFFFFFFFF);
const Color _backgroundColor = Color(0xFFF8FAFC);

class _ClienteRank {
  final String nome;
  final String? clienteId;
  double total;
  int qtdPedidos;

  _ClienteRank({
    required this.nome,
    this.clienteId,
    required this.total,
    required this.qtdPedidos,
  });

  double get ticketMedio => qtdPedidos > 0 ? total / qtdPedidos : 0;
}

class RelatorioRankingClientesScreen extends StatefulWidget {
  final String lojaId;

  const RelatorioRankingClientesScreen({super.key, required this.lojaId});

  @override
  State<RelatorioRankingClientesScreen> createState() =>
      _RelatorioRankingClientesScreenState();
}

class _RelatorioRankingClientesScreenState
    extends State<RelatorioRankingClientesScreen> {
  bool _loading = true;
  List<_ClienteRank> _ranking = [];
  String _ordenacao = 'total'; // 'total' | 'pedidos' | 'ticket'
  final NumberFormat _currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  DateTime? _dataInicio;
  DateTime? _dataFim;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    String? lojaId = widget.lojaId.trim().isEmpty ? null : widget.lojaId.trim();
    if (lojaId == null || lojaId.isEmpty) {
      lojaId = await LojaIdService.getWithTimeout(timeout: const Duration(seconds: 10));
      if (lojaId == null || lojaId.isEmpty) {
        try {
          final sessao = await Hive.openBox('sessao');
          lojaId = normalizeFromBox(sessao);
        } catch (_) {}
      }
    }
    if (lojaId == null || lojaId.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final now = DateTime.now();
    final inicio = _dataInicio ?? DateTime(now.year, now.month, 1);
    final fim = _dataFim ?? DateTime(now.year, now.month + 1, 0, 23, 59, 59);

    try {
      final boxName = HiveBoxNames.vendas(lojaId);
      Box<Venda> box;
      if (Hive.isBoxOpen(boxName)) {
        box = Hive.box<Venda>(boxName);
      } else {
        box = await Hive.openBox<Venda>(boxName);
      }

      final Map<String, _ClienteRank> porCliente = {};

      for (final v in box.values) {
        if (v.lojaId != null && v.lojaId != lojaId) continue;
        if (v.data.isBefore(inicio) || v.data.isAfter(fim)) continue;

        final key = v.clienteId?.trim().isNotEmpty == true
            ? v.clienteId!
            : v.clienteNome.trim();
        if (key.isEmpty) continue;

        porCliente.putIfAbsent(
          key,
          () => _ClienteRank(
            nome: v.clienteNome.trim().isEmpty ? '(Sem nome)' : v.clienteNome.trim(),
            clienteId: v.clienteId,
            total: 0,
            qtdPedidos: 0,
          ),
        );
        final r = porCliente[key]!;
        r.total += v.total;
        r.qtdPedidos += 1;
      }

      List<_ClienteRank> list = porCliente.values.toList();
      _aplicarOrdenacao(list);
      if (mounted) setState(() => _ranking = list);
    } catch (e) {
      debugPrint('RelatorioRankingClientes erro: $e');
      if (mounted) setState(() => _ranking = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _aplicarOrdenacao(List<_ClienteRank> list) {
    switch (_ordenacao) {
      case 'total':
        list.sort((a, b) => b.total.compareTo(a.total));
        break;
      case 'pedidos':
        list.sort((a, b) => b.qtdPedidos.compareTo(a.qtdPedidos));
        break;
      case 'ticket':
        list.sort((a, b) => b.ticketMedio.compareTo(a.ticketMedio));
        break;
    }
  }

  Future<void> _escolherPeriodo() async {
    final now = DateTime.now();
    final ini = await showDatePicker(
      context: context,
      initialDate: _dataInicio ?? DateTime(now.year, now.month, 1),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (ini == null || !mounted) return;
    final fim = await showDatePicker(
      context: context,
      initialDate: _dataFim ?? DateTime(now.year, now.month + 1, 0),
      firstDate: ini,
      lastDate: DateTime(2100),
    );
    if (fim == null || !mounted) return;
    setState(() {
      _dataInicio = ini;
      _dataFim = fim;
    });
    await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        title: const Text('Ranking de clientes'),
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            onPressed: _escolherPeriodo,
            tooltip: 'Filtrar período',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            tooltip: 'Ordenar por',
            onSelected: (v) {
              setState(() {
                _ordenacao = v;
                _aplicarOrdenacao(_ranking);
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'total', child: Text('Maior total')),
              const PopupMenuItem(value: 'pedidos', child: Text('Mais pedidos')),
              const PopupMenuItem(value: 'ticket', child: Text('Maior ticket médio')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _primaryColor))
          : _ranking.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_outline, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        'Nenhuma venda no período.',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                      if (_dataInicio != null || _dataFim != null)
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _dataInicio = null;
                              _dataFim = null;
                            });
                            _carregar();
                          },
                          child: const Text('Limpar filtro'),
                        ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _ranking.length,
                  itemBuilder: (context, i) {
                    final r = _ranking[i];
                    final pos = i + 1;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      color: _cardColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _primaryColor.withValues(alpha:0.2),
                          child: Text(
                            '$pos',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _primaryColor,
                            ),
                          ),
                        ),
                        title: Text(
                          r.nome,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${r.qtdPedidos} pedido(s) · Ticket médio ${_currency.format(r.ticketMedio)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        trailing: Text(
                          _currency.format(r.total),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _successColor,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

