// lib/screens/compras/compra_pipeline_pendentes_estoque_screen.dart
// Itens precificados aguardando cadastro final no estoque (sem criar produto antes).

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';

import '../../core/compra_item_pipeline_constants.dart';
import '../../core/hive_box_names.dart';
import '../../models/compra_item_pipeline.dart';
import '../../models/produto.dart';
import '../../services/compra_item_pipeline_store.dart';
import '../../services/store_resolver_facade.dart';
import '../produto_form_screen.dart';

class CompraPipelinePendentesEstoqueScreen extends StatefulWidget {
  const CompraPipelinePendentesEstoqueScreen({super.key});

  @override
  State<CompraPipelinePendentesEstoqueScreen> createState() =>
      _CompraPipelinePendentesEstoqueScreenState();
}

class _CompraPipelinePendentesEstoqueScreenState
    extends State<CompraPipelinePendentesEstoqueScreen> {
  static const Color _primary = Color(0xFF6366F1);
  bool _carregando = true;
  String? _lojaId;
  List<CompraItemPipeline> _lista = const [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    final lojaId = await StoreResolverFacade.resolveForAdminApp();
    if (!mounted) return;
    if (lojaId == null || lojaId.isEmpty) {
      setState(() {
        _lojaId = null;
        _lista = [];
        _carregando = false;
      });
      return;
    }
    _lojaId = lojaId;
    final box = await CompraItemPipelineStore.openBox(lojaId);
    final list = <CompraItemPipeline>[];
    if (box != null) {
      for (final p in box.values) {
        if (p.lojaId == lojaId &&
            p.estado == CompraItemPipelineEstado.precificadoPendenteEstoque) {
          list.add(p);
        }
      }
      list.sort((a, b) => b.atualizadoEm.compareTo(a.atualizadoEm));
    }
    setState(() {
      _lista = list;
      _carregando = false;
    });
  }

  String _fmtMoney(double v) =>
      NumberFormat.currency(locale: 'pt_BR', symbol: r'R$').format(v);

  Produto? _produtoPorIdFirebase(Box<Produto> box, String fid) {
    final f = fid.trim();
    if (f.isEmpty) return null;
    for (final k in box.keys) {
      final p = box.get(k);
      if (p != null && p.idFirebase.trim() == f) return p;
    }
    return null;
  }

  Future<void> _abrirFinalizacao(CompraItemPipeline row) async {
    final lid = _lojaId;
    if (lid == null) return;
    final name = HiveBoxNames.produtos(lid);
    final Box<Produto> pBox = Hive.isBoxOpen(name)
        ? Hive.box<Produto>(name)
        : await Hive.openBox<Produto>(name);

    final fid = row.productIdFirebase?.trim() ?? '';
    final existente =
        fid.isNotEmpty ? _produtoPorIdFirebase(pBox, fid) : null;

    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ProdutoFormScreen(
          produto: existente,
          compraPipelineDocId: row.id,
        ),
      ),
    );
    if (mounted) await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Finalizar compras no estoque'),
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _carregando ? null : _carregar,
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _lojaId == null
              ? const Center(child: Text('Loja não encontrada.'))
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: _lista.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 80),
                            Icon(Icons.inventory_2_outlined,
                                size: 56, color: Colors.grey),
                            SizedBox(height: 16),
                            Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 24),
                                child: Text(
                                  'Nenhum item precificado pendente de cadastro.\n'
                                  'Confirme a compra → precifique na Precificação Universal → volte aqui.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _lista.length,
                          itemBuilder: (_, i) {
                            final row = _lista[i];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: ListTile(
                                title: Text(
                                  row.nomeProdutoProvisorio,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  '${row.fornecedorNome}\n'
                                  'Qtd ${row.quantidade} · Custo ${_fmtMoney(row.custoUnitario)} · '
                                  'Venda ${_fmtMoney(row.precoFinal)}',
                                ),
                                isThreeLine: true,
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _abrirFinalizacao(row),
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}
