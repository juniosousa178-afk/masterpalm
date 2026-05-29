// Compras revenda aguardando detalhamento de produtos.

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';

import '../../models/compra_fornecedor.dart';
import '../../models/compra_fornecedor_constants.dart';
import '../../services/compra_fornecedor_hive_store.dart';
import '../../services/compra_revenda_detalhamento_service.dart';
import 'compra_detalhar_produtos_screen.dart';

class ComprasRevendaPendentesScreen extends StatefulWidget {
  const ComprasRevendaPendentesScreen({
    super.key,
    required this.lojaId,
  });

  final String lojaId;

  @override
  State<ComprasRevendaPendentesScreen> createState() =>
      _ComprasRevendaPendentesScreenState();
}

class _ComprasRevendaPendentesScreenState extends State<ComprasRevendaPendentesScreen> {
  static const Color _primary = Color(0xFF6366F1);
  Box<CompraFornecedor>? _box;
  bool _loading = true;

  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  final _fmt = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    setState(() => _loading = true);
    _box = await CompraFornecedorHiveStore.openBox(widget.lojaId);
    if (mounted) setState(() => _loading = false);
  }

  List<CompraFornecedor> get _lista {
    final box = _box;
    if (box == null) return [];
    final list = CompraRevendaDetalhamentoService.listarPendentesDetalhamento(
      box,
      widget.lojaId,
    ).toList();
    list.sort((a, b) => b.dataCompra.compareTo(a.dataCompra));
    return list;
  }

  Future<void> _abrirDetalhar(CompraFornecedor c) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CompraDetalharProdutosScreen(
          lojaId: widget.lojaId,
          compraId: c.id,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Compras aguardando produtos'),
        backgroundColor: _primary,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _open,
              child: _lista.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 80),
                        Icon(Icons.check_circle_outline,
                            size: 56, color: Colors.grey),
                        SizedBox(height: 12),
                        Center(
                          child: Text(
                            'Nenhuma compra aguardando detalhamento.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _lista.length,
                      itemBuilder: (_, i) {
                        final c = _lista[i];
                        final diff = c.diferencaDetalhamento;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text(c.fornecedorNome),
                            subtitle: Text(
                              '${_fmt.format(c.dataCompra)} · '
                              'Total ${_moeda.format(c.valorTotalFinanceiro)}\n'
                              'Detalhado ${_moeda.format(c.valorProdutosDetalhados)} · '
                              'Dif. ${_moeda.format(diff)}\n'
                              '${CompraFornecedorStatusDetalhamento.legivel(c.statusDetalhamentoProdutos)}',
                            ),
                            isThreeLine: true,
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _abrirDetalhar(c),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
