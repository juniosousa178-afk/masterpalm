// lib/screens/relatorio_lucratividade_produto_screen.dart
// Margem bruta por produto (SKU): receita − custo; não é o lucro operacional da loja.

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';

import '../core/hive_box_names.dart';
import '../core/relatorio_margem_bruta_custo.dart';
import '../core/venda_metrics_filter.dart';
import '../models/venda.dart';

const Color _primaryColor = Color(0xFF6366F1);
const Color _successColor = Color(0xFF22C55E);
const Color _errorColor = Color(0xFFEF4444);
const Color _cardColor = Color(0xFFFFFFFF);
const Color _backgroundColor = Color(0xFFF8FAFC);

class _ProdutoLucro {
  final String nome;
  int qtdVendida;
  double receita;
  double custo;

  _ProdutoLucro({
    required this.nome,
    required this.qtdVendida,
    required this.receita,
    required this.custo,
  });

  double get lucro => receita - custo;
  double get margemPct => receita > 0 ? (lucro / receita * 100) : 0;
}

class RelatorioLucratividadeProdutoScreen extends StatefulWidget {
  final String lojaId;

  const RelatorioLucratividadeProdutoScreen({required this.lojaId, super.key});

  @override
  State<RelatorioLucratividadeProdutoScreen> createState() =>
      _RelatorioLucratividadeProdutoScreenState();
}

class _RelatorioLucratividadeProdutoScreenState
    extends State<RelatorioLucratividadeProdutoScreen> {
  bool _loading = true;
  List<_ProdutoLucro> _lista = [];
  String _ordenacao = 'lucro'; // lucro | receita | margem | qtd
  DateTime? _dataInicio;
  DateTime? _dataFim;
  final _currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dataInicio = DateTime(now.year, now.month, 1);
    _dataFim = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    try {
      // Tenta vendas_lojaId primeiro; fallback para box global 'vendas'
      final boxName = HiveBoxNames.vendas(widget.lojaId);
      Box<Venda> vendasBox;
      if (Hive.isBoxOpen(boxName)) {
        vendasBox = Hive.box<Venda>(boxName);
      } else {
        vendasBox = await Hive.openBox<Venda>(boxName);
      }
      final inicio = _dataInicio ?? DateTime(2020);
      final fim = _dataFim ?? DateTime.now().add(const Duration(days: 365));

      final vendas = vendasBox.values.where((v) {
        if (v.lojaId != widget.lojaId) return false;
        if (!incluirVendaEmMetricas(v)) return false;
        return !v.data.isBefore(inicio) && !v.data.isAfter(fim);
      }).toList();

      final map = <String, _ProdutoLucro>{};
      for (final venda in vendas) {
        final itens = venda.itens ?? [];
        if (itens.isEmpty) continue;
        final custoPorLinha = custoRelatorioPorLinhasVenda(
          venda,
          itens,
        );
        for (var i = 0; i < itens.length; i++) {
          final item = itens[i];
          final key = item.produtoNome.trim().toLowerCase();
          if (key.isEmpty) continue;
          final receita = item.quantidade * item.precoUnitario;
          final custoLinha =
              i < custoPorLinha.length ? custoPorLinha[i] : 0.0;
          final p = map[key];
          if (p == null) {
            map[key] = _ProdutoLucro(
              nome: item.produtoNome.trim(),
              qtdVendida: item.quantidade,
              receita: receita,
              custo: custoLinha,
            );
          } else {
            p.qtdVendida += item.quantidade;
            p.receita += receita;
            p.custo += custoLinha;
          }
        }
      }

      var lista = map.values.toList();
      switch (_ordenacao) {
        case 'receita':
          lista.sort((a, b) => b.receita.compareTo(a.receita));
          break;
        case 'margem':
          lista.sort((a, b) => b.margemPct.compareTo(a.margemPct));
          break;
        case 'qtd':
          lista.sort((a, b) => b.qtdVendida.compareTo(a.qtdVendida));
          break;
        default:
          lista.sort((a, b) => b.lucro.compareTo(a.lucro));
      }

      if (mounted) {
        setState(() {
        _lista = lista;
        _loading = false;
      });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
        _lista = [];
        _loading = false;
      });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        title: const Text('Margem bruta por produto', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              setState(() {
                _ordenacao = v;
                _carregar();
              });
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'lucro', child: Text('Ordenar por margem bruta (R\$)')),
              const PopupMenuItem(value: 'receita', child: Text('Ordenar por receita')),
              const PopupMenuItem(value: 'margem', child: Text('Ordenar por margem %')),
              const PopupMenuItem(value: 'qtd', child: Text('Ordenar por qtd vendida')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: const Color(0xFFEFF6FF),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                'Por SKU: margem bruta (receita − custo). Não é o lucro operacional total da loja.',
                style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade800),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _dataInicio ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (d != null) setState(() => _dataInicio = d);
                      _carregar();
                    },
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(DateFormat('dd/MM/yy').format(_dataInicio ?? DateTime.now())),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _dataFim ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (d != null) setState(() => _dataFim = d);
                      _carregar();
                    },
                    icon: const Icon(Icons.event, size: 18),
                    label: Text(DateFormat('dd/MM/yy').format(_dataFim ?? DateTime.now())),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _loading ? null : _carregar,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _primaryColor))
                : _lista.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text(
                              'Nenhuma venda no período.',
                              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: _lista.length,
                        itemBuilder: (_, i) {
                          final p = _lista[i];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              title: Text(
                                p.nome,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${p.qtdVendida} un. · Receita: ${_currency.format(p.receita)} · Custo: ${_currency.format(p.custo)}',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'Margem bruta',
                                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                                  ),
                                  Text(
                                    _currency.format(p.lucro),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: p.lucro >= 0 ? _successColor : _errorColor,
                                    ),
                                  ),
                                  Text(
                                    '${p.margemPct.toStringAsFixed(0)}%',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: p.margemPct >= 0 ? _successColor : _errorColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          if (_lista.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              color: _cardColor,
              child: SafeArea(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildResumo('Margem bruta total', _lista.fold(0.0, (s, p) => s + p.lucro)),
                    _buildResumo('Receita', _lista.fold(0.0, (s, p) => s + p.receita)),
                    _buildResumo('Custo', _lista.fold(0.0, (s, p) => s + p.custo)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildResumo(String label, double value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        Text(
          _currency.format(value),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: label == 'Margem bruta total' ? (value >= 0 ? _successColor : _errorColor) : Colors.black87,
          ),
        ),
      ],
    );
  }
}
