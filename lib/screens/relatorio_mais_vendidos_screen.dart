// lib/screens/relatorio_mais_vendidos_screen.dart
// Relat�rio Mais vendidos + comparativo Este m�s vs M�s passado. Sempre por [lojaId].

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';

import '../core/hive_box_names.dart';
import '../models/venda.dart';

const Color _primaryColor = Color(0xFF6366F1);
const Color _successColor = Color(0xFF22C55E);

class RelatorioMaisVendidosScreen extends StatefulWidget {
  final String lojaId;

  const RelatorioMaisVendidosScreen({super.key, required this.lojaId});

  @override
  State<RelatorioMaisVendidosScreen> createState() => _RelatorioMaisVendidosScreenState();
}

class _RelatorioMaisVendidosScreenState extends State<RelatorioMaisVendidosScreen> {
  bool _loading = true;
  double _totalEsteMes = 0;
  double _totalMesPassado = 0;
  List<MapEntry<String, _ProdutoVendas>> _topProdutos = [];
  final NumberFormat _currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    final lojaId = widget.lojaId;
    if (lojaId.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    double totalEsteMes = 0;
    double totalMesPassado = 0;
    final Map<String, _ProdutoVendas> porProduto = {};

    final now = DateTime.now();
    final inicioEsteMes = DateTime(now.year, now.month, 1);
    final fimEsteMes = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    final inicioMesPassado = DateTime(now.year, now.month - 1, 1);
    final fimMesPassado = DateTime(now.year, now.month, 0, 23, 59, 59);

    try {
      final boxName = HiveBoxNames.vendas(lojaId);
      Box<Venda> box;
      if (Hive.isBoxOpen(boxName)) {
        box = Hive.box<Venda>(boxName);
      } else {
        box = await Hive.openBox<Venda>(boxName);
      }

      for (final v in box.values) {
        if (v.lojaId != null && v.lojaId != lojaId) continue;
        final dt = v.data;

        if (!dt.isBefore(inicioEsteMes) && !dt.isAfter(fimEsteMes)) {
          totalEsteMes += v.total;
        } else if (!dt.isBefore(inicioMesPassado) && !dt.isAfter(fimMesPassado)) {
          totalMesPassado += v.total;
        }

        for (final item in v.itensOuVazio) {
          final key = item.tamanho.trim().isEmpty
              ? item.produtoNome
              : '${item.produtoNome} (${item.tamanho})';
          porProduto.putIfAbsent(key, () => _ProdutoVendas(key));
          final p = porProduto[key]!;
          p.quantidade += item.quantidade;
          p.valorTotal += item.precoUnitario * item.quantidade;
          if (!dt.isBefore(inicioEsteMes) && !dt.isAfter(fimEsteMes)) {
            p.qtdEsteMes += item.quantidade;
          } else if (!dt.isBefore(inicioMesPassado) && !dt.isAfter(fimMesPassado)) {
            p.qtdMesPassado += item.quantidade;
          }
        }
        if (v.itensOuVazio.isEmpty && v.produtosDescricao.isNotEmpty) {
          final key = v.produtosDescricao;
          porProduto.putIfAbsent(key, () => _ProdutoVendas(key));
          final p = porProduto[key]!;
          p.quantidade += v.quantidade;
          p.valorTotal += v.total;
          if (!dt.isBefore(inicioEsteMes) && !dt.isAfter(fimEsteMes)) {
            p.qtdEsteMes += v.quantidade;
          } else if (!dt.isBefore(inicioMesPassado) && !dt.isAfter(fimMesPassado)) {
            p.qtdMesPassado += v.quantidade;
          }
        }
      }

      final list = porProduto.entries.toList()
        ..sort((a, b) => b.value.quantidade.compareTo(a.value.quantidade));
      final top = list.take(30).toList();

      if (mounted) {
        setState(() {
          _totalEsteMes = totalEsteMes;
          _totalMesPassado = totalMesPassado;
          _topProdutos = top;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mesAtual = DateFormat('MMMM', 'pt_BR').format(DateTime.now());
    final mesPassado = DateFormat('MMMM', 'pt_BR').format(DateTime(DateTime.now().year, DateTime.now().month - 1));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mais vendidos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : () => _carregar(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _primaryColor))
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Comparativo de valor',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _ComparativoCard(
                          label: mesAtual,
                          value: _totalEsteMes,
                          format: _currency,
                          color: _primaryColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ComparativoCard(
                          label: mesPassado,
                          value: _totalMesPassado,
                          format: _currency,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  if (_totalMesPassado > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      _totalEsteMes >= _totalMesPassado
                          ? '? ${((_totalEsteMes / _totalMesPassado - 1) * 100).toStringAsFixed(0)}% em rela��o ao m�s passado'
                          : '? ${((1 - _totalEsteMes / _totalMesPassado) * 100).toStringAsFixed(0)}% em rela��o ao m�s passado',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _totalEsteMes >= _totalMesPassado ? _successColor : Colors.orange,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    'Produtos mais vendidos',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_topProdutos.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'Nenhuma venda com itens nesta loja.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha:0.6),
                          ),
                        ),
                      ),
                    )
                  else
                    ..._topProdutos.asMap().entries.map((e) {
                      final i = e.key + 1;
                      final p = e.value.value;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _primaryColor.withValues(alpha:0.2),
                            child: Text(
                              '$i',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _primaryColor,
                              ),
                            ),
                          ),
                          title: Text(
                            p.nome,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${p.quantidade} un. � ${_currency.format(p.valorTotal)}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}

class _ProdutoVendas {
  final String nome;
  int quantidade = 0;
  double valorTotal = 0;
  int qtdEsteMes = 0;
  int qtdMesPassado = 0;
  _ProdutoVendas(this.nome);
}

class _ComparativoCard extends StatelessWidget {
  final String label;
  final double value;
  final NumberFormat format;
  final Color color;

  const _ComparativoCard({
    required this.label,
    required this.value,
    required this.format,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha:0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha:0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha:0.8),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            format.format(value),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

