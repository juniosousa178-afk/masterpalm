// lib/screens/financeiro/controle_compras_fornecedor_screen.dart
// Controle operacional de compras por fornecedor — não integra com lucro/relatórios.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/controle_compras_fornecedor_service.dart';
import '../../utils/moeda_input_formatter.dart';

class ControleComprasFornecedorScreen extends StatefulWidget {
  const ControleComprasFornecedorScreen({super.key, required this.lojaId});

  final String lojaId;

  @override
  State<ControleComprasFornecedorScreen> createState() =>
      _ControleComprasFornecedorScreenState();
}

class _ControleComprasFornecedorScreenState
    extends State<ControleComprasFornecedorScreen> {
  static const Color _primary = Color(0xFF6366F1);

  bool _loading = true;
  List<LinhaControleCompraFornecedor> _linhas = [];

  final _nf = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await ControleComprasFornecedorService.carregar(widget.lojaId);
    if (!mounted) return;
    setState(() {
      _linhas = list;
      _loading = false;
    });
  }

  Future<void> _abrirForm() async {
    final fornecedorCtrl = TextEditingController();
    final valorCtrl = TextEditingController();
    final freteCtrl = TextEditingController();
    final descontoCtrl = TextEditingController();
    var dataCompra = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            double totalPreview() {
              final v = MoedaInputFormatter.parse(valorCtrl.text);
              final f = MoedaInputFormatter.parse(freteCtrl.text);
              final d = MoedaInputFormatter.parse(descontoCtrl.text);
              return v + f - d;
            }

            return AlertDialog(
              title: const Text('Nova compra (controle)'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Estes dados são só para conferência. Não entram em lucro, metas nem relatórios financeiros do app.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: fornecedorCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Fornecedor',
                        border: OutlineInputBorder(),
                      ),
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: 8),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Data da compra'),
                      subtitle: Text(
                        DateFormat('dd/MM/yyyy').format(dataCompra),
                      ),
                      trailing: const Icon(Icons.calendar_today_outlined),
                      onTap: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: dataCompra,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (d != null) {
                          setLocal(() => dataCompra = d);
                        }
                      },
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Lançamento no controle: data/hora de agora (ao salvar).',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: valorCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Valor da compra',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [MoedaInputFormatter()],
                      onChanged: (_) => setLocal(() {}),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: freteCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Frete',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [MoedaInputFormatter()],
                      onChanged: (_) => setLocal(() {}),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: descontoCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Desconto',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [MoedaInputFormatter()],
                      onChanged: (_) => setLocal(() {}),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Total: ${_nf.format(totalPreview())}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    if (fornecedorCtrl.text.trim().isEmpty) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text('Informe o fornecedor.'),
                        ),
                      );
                      return;
                    }
                    Navigator.pop(ctx, true);
                  },
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true || !mounted) return;

    await ControleComprasFornecedorService.adicionar(
      lojaId: widget.lojaId,
      fornecedorNome: fornecedorCtrl.text,
      valor: MoedaInputFormatter.parse(valorCtrl.text),
      frete: MoedaInputFormatter.parse(freteCtrl.text),
      desconto: MoedaInputFormatter.parse(descontoCtrl.text),
      dataCompra: dataCompra,
    );
    await _load();
  }

  Future<void> _excluir(LinhaControleCompraFornecedor linha) async {
    final conf = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir registro?'),
        content: Text(linha.fornecedorNome),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (conf == true) {
      await ControleComprasFornecedorService.remover(widget.lojaId, linha.id);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final totais = ControleComprasFornecedorService.totaisPorFornecedor(_linhas);
    final chavesOrdenadas = totais.keys.toList()
      ..sort((a, b) => totais[b]!.compareTo(totais[a]!));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Controle por fornecedor'),
        backgroundColor: _primary,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _abrirForm,
        backgroundColor: _primary,
        icon: const Icon(Icons.add),
        label: const Text('Registrar compra'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Totais por fornecedor (somente conferência)',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (totais.isEmpty)
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  'Nenhuma compra registrada. Use o botão abaixo para lançar valores de controle.',
                                  style: TextStyle(color: Colors.grey.shade700),
                                ),
                              ),
                            )
                          else
                            ...chavesOrdenadas.map(
                              (k) => Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  title: Text(k),
                                  trailing: Text(
                                    _nf.format(totais[k] ?? 0),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 20),
                          Text(
                            'Histórico (${_linhas.length})',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_linhas.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: SizedBox.shrink(),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) {
                          final l = _linhas[i];
                          final dataCompraStr =
                              DateFormat('dd/MM/yyyy').format(l.dataCompra);
                          final dataLancamentoStr =
                              DateFormat('dd/MM/yyyy HH:mm').format(l.criadoEm);
                          return Dismissible(
                            key: ValueKey(l.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              color: Colors.red.shade100,
                              child: const Icon(Icons.delete_outline),
                            ),
                            onDismissed: (_) =>
                                ControleComprasFornecedorService.remover(
                                        widget.lojaId, l.id)
                                    .then((_) => _load()),
                            child: ListTile(
                              title: Text(l.fornecedorNome.isEmpty
                                  ? '(sem nome)'
                                  : l.fornecedorNome),
                              subtitle: Text(
                                'Compra: $dataCompraStr · Lançado: $dataLancamentoStr\n'
                                'valor ${_nf.format(l.valor)} + frete ${_nf.format(l.frete)} − desc. ${_nf.format(l.desconto)}',
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Text(
                                _nf.format(l.total),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              onLongPress: () => _excluir(l),
                            ),
                          );
                        },
                        childCount: _linhas.length,
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 88)),
                ],
              ),
            ),
    );
  }
}
