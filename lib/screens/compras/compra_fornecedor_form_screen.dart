// lib/screens/compras/compra_fornecedor_form_screen.dart
// Cadastro/edição local; política compra↔financeiro: CompraFinanceiroIntegracaoService.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/hive_box_names.dart';
import '../../models/compra_fornecedor.dart';
import '../../models/compra_fornecedor_constants.dart';
import '../../models/compra_fornecedor_item.dart';
import '../../models/produto.dart';
import '../../services/compra_financeiro_integracao_service.dart';
import '../../services/compra_fornecedor_hive_store.dart';
import '../../services/compra_fornecedor_sync_service.dart';
import '../../services/compra_para_pipeline_service.dart';
import '../../utils/compra_fornecedor_rateio.dart';

class CompraFornecedorFormScreen extends StatefulWidget {
  const CompraFornecedorFormScreen({
    super.key,
    required this.lojaId,
    required this.fornecedorHiveKey,
    required this.fornecedorNome,
    this.compraExistente,
  });

  final String lojaId;
  final int fornecedorHiveKey;
  final String fornecedorNome;
  final CompraFornecedor? compraExistente;

  @override
  State<CompraFornecedorFormScreen> createState() =>
      _CompraFornecedorFormScreenState();
}

class _CompraFornecedorFormScreenState extends State<CompraFornecedorFormScreen> {
  static const Color _primary = Color(0xFF6366F1);
  static const _uuid = Uuid();

  final _refCtrl = TextEditingController();
  final _obsCtrl = TextEditingController();
  final _freteCtrl = TextEditingController();
  final _outrasCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _valorPagoCtrl = TextEditingController();

  DateTime _dataCompra = DateTime.now();
  DateTime? _dataVencimento;
  String _statusCompra = CompraFornecedorStatusCompra.rascunho;
  String _statusPagamento = CompraFornecedorStatusPagamento.pendente;

  final List<CompraFornecedorItem> _itens = [];
  bool _gravando = false;

  String? _compraId;
  DateTime? _confirmadoEm;
  bool _estoqueIntegrado = false;
  String _idLancamentoFinanceiro = '';

  @override
  void initState() {
    super.initState();
    final e = widget.compraExistente;
    if (e != null) {
      _compraId = e.id;
      _refCtrl.text = e.referenciaInterna;
      _obsCtrl.text = e.observacao;
      _freteCtrl.text = _fmtNum(e.frete);
      _outrasCtrl.text = _fmtNum(e.outrasDespesas);
      _descCtrl.text = _fmtNum(e.desconto);
      _valorPagoCtrl.text = _fmtNum(e.valorPago);
      _dataCompra = e.dataCompra;
      _dataVencimento = e.dataVencimento;
      _statusCompra = CompraFornecedorStatusCompra.ouPadrao(e.statusCompra);
      _statusPagamento =
          CompraFornecedorStatusPagamento.ouPadrao(e.statusPagamento);
      _itens.addAll(e.itensOuVazio.map((x) => CompraFornecedorItem(
            produtoNome: x.produtoNome,
            quantidade: x.quantidade,
            custoUnitario: x.custoUnitario,
            productId: x.productId,
            itemCompraId: x.itemCompraId.trim().isEmpty
                ? _uuid.v4()
                : x.itemCompraId,
            codigoInterno: x.codigoInterno,
            codigoBarras: x.codigoBarras,
            observacaoItem: x.observacaoItem,
            unidade: x.unidade,
            subtotalBase: x.subtotalBase,
            percentualParticipacao: x.percentualParticipacao,
            freteRateado: x.freteRateado,
            descontoRateado: x.descontoRateado,
            outrasDespesasRateadas: x.outrasDespesasRateadas,
            custoUnitarioFinal: x.custoUnitarioFinal,
            subtotalFinal: x.subtotalFinal,
          )));
      _confirmadoEm = e.confirmadoEm;
      _estoqueIntegrado = e.estoqueIntegrado;
      _idLancamentoFinanceiro = e.idLancamentoFinanceiro;
    }
  }

  @override
  void dispose() {
    _refCtrl.dispose();
    _obsCtrl.dispose();
    _freteCtrl.dispose();
    _outrasCtrl.dispose();
    _descCtrl.dispose();
    _valorPagoCtrl.dispose();
    super.dispose();
  }

  String _fmtNum(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2).replaceAll('.', ',');
  }

  double _parseMoney(String s) {
    var t = s.trim().replaceAll(RegExp(r'\s'), '');
    if (t.contains(',')) {
      t = t.replaceAll('.', '').replaceAll(',', '.');
    }
    return double.tryParse(t.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
  }

  double get _frete => _parseMoney(_freteCtrl.text);
  double get _outrasDespesas => _parseMoney(_outrasCtrl.text);
  double get _desconto => _parseMoney(_descCtrl.text);
  double get _valorPago => _parseMoney(_valorPagoCtrl.text);

  double get _subtotalItens {
    var t = 0.0;
    for (final it in _itens) {
      t += it.subtotal;
    }
    return t;
  }

  double get _valorTotal =>
      (_subtotalItens + _frete + _outrasDespesas - _desconto).clamp(0.0, 1e15);

  double get _valorEmAberto => (_valorTotal - _valorPago).clamp(0.0, 1e15);

  String _fmtBrl(double v) =>
      NumberFormat.currency(locale: 'pt_BR', symbol: r'R$').format(v);

  Future<void> _pickDataCompra() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _dataCompra,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _dataCompra = d);
  }

  Future<void> _pickVencimento() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _dataVencimento ?? _dataCompra,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _dataVencimento = d);
  }

  Future<void> _adicionarItem() async {
    final name = HiveBoxNames.produtos(widget.lojaId);
    final Box<Produto> box = Hive.isBoxOpen(name)
        ? Hive.box<Produto>(name)
        : await Hive.openBox<Produto>(name);
    if (!mounted) return;
    final produtos = box.values
        .where((p) => p.lojaId.isEmpty || p.lojaId == widget.lojaId)
        .toList()
      ..sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));

    final qBusca = ValueNotifier<String>('');
    CompraFornecedorItem? escolhido;
    try {
      await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: StatefulBuilder(
            builder: (ctx, setM) {
              return DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.65,
                minChildSize: 0.35,
                maxChildSize: 0.92,
                builder: (_, scroll) {
                  return ValueListenableBuilder<String>(
                    valueListenable: qBusca,
                    builder: (_, q, __) {
                      final filtrados = produtos
                          .where((p) => q.isEmpty ||
                              p.nome.toLowerCase().contains(q.toLowerCase()))
                          .take(200)
                          .toList();
                      return Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: TextField(
                              decoration: const InputDecoration(
                                labelText: 'Buscar produto',
                                prefixIcon: Icon(Icons.search),
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) => qBusca.value = v,
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                              controller: scroll,
                              itemCount: filtrados.length,
                              itemBuilder: (_, i) {
                                final p = filtrados[i];
                                return ListTile(
                                  title: Text(p.nome),
                                  subtitle: Text(
                                    'Custo: ${_fmtBrl(p.custoReal)} · Est: ${p.quantidade}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  onTap: () {
                                    escolhido = CompraFornecedorItem(
                                      produtoNome: p.nome,
                                      quantidade: 1,
                                      custoUnitario: p.custoReal,
                                      productId: p.idFirebase.trim().isEmpty
                                          ? null
                                          : p.idFirebase.trim(),
                                      itemCompraId: _uuid.v4(),
                                      codigoBarras: p.codigoBarras.trim(),
                                    );
                                    Navigator.pop(ctx);
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              );
            },
          ),
        );
      },
    );
    } finally {
      qBusca.dispose();
    }

    if (escolhido == null || !mounted) return;
    final base = escolhido!;
    final qtdCtrl = TextEditingController(text: '${base.quantidade}');
    final custoCtrl = TextEditingController(text: _fmtNum(base.custoUnitario));
    final ciCtrl = TextEditingController(text: base.codigoInterno);
    final eanCtrl = TextEditingController(text: base.codigoBarras);
    final obsCtrl = TextEditingController(text: base.observacaoItem);
    final unidadeCtrl = TextEditingController(text: base.unidade);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quantidade e custo'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(base.produtoNome,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              TextField(
                controller: qtdCtrl,
                decoration: const InputDecoration(labelText: 'Quantidade'),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: custoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Custo unitário',
                  hintText: '0,00',
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: ciCtrl,
                decoration: const InputDecoration(
                  labelText: 'Código interno (opcional)',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: eanCtrl,
                decoration: const InputDecoration(
                  labelText: 'Código de barras (opcional)',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: unidadeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Unidade (opcional)',
                  hintText: 'Ex: UN, KG',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: obsCtrl,
                decoration: const InputDecoration(
                  labelText: 'Observação do item (opcional)',
                ),
                maxLines: 2,
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
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;
    final qtd = int.tryParse(qtdCtrl.text.trim()) ?? 0;
    final custo = _parseMoney(custoCtrl.text);
    qtdCtrl.dispose();
    custoCtrl.dispose();
    final codInt = ciCtrl.text.trim();
    final ean = eanCtrl.text.trim();
    final obs = obsCtrl.text.trim();
    final un = unidadeCtrl.text.trim();
    ciCtrl.dispose();
    eanCtrl.dispose();
    obsCtrl.dispose();
    unidadeCtrl.dispose();
    if (qtd <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quantidade inválida')),
      );
      return;
    }
    setState(() {
      _itens.add(CompraFornecedorItem(
        produtoNome: base.produtoNome,
        quantidade: qtd,
        custoUnitario: custo,
        productId: base.productId,
        itemCompraId: base.itemCompraId.trim().isEmpty
            ? _uuid.v4()
            : base.itemCompraId,
        codigoInterno: codInt,
        codigoBarras: ean,
        observacaoItem: obs,
        unidade: un,
      ));
    });
  }

  void _removerItem(int i) {
    setState(() => _itens.removeAt(i));
  }

  void _ensureItemCompraIds() {
    for (var i = 0; i < _itens.length; i++) {
      if (_itens[i].itemCompraId.trim().isEmpty) {
        _itens[i] = _itens[i].copyWith(itemCompraId: _uuid.v4());
      }
    }
  }

  Future<void> _sincronizarPipelineSeConfirmada(CompraFornecedor c) async {
    if (c.statusCompra == CompraFornecedorStatusCompra.confirmada) {
      await CompraParaPipelineService.sincronizarItensCompraConfirmada(c);
    }
  }

  Future<void> _sincronizarPipelineSeCancelada(CompraFornecedor c) async {
    if (c.statusCompra == CompraFornecedorStatusCompra.cancelada) {
      await CompraParaPipelineService.sincronizarCancelamentoCompraNoPipeline(c);
    }
  }

  CompraFornecedor _montarModelo({
    required String statusCompra,
    required String statusPagamento,
  }) {
    _ensureItemCompraIds();
    final id = _compraId ?? _uuid.v4();
    final agora = DateTime.now();
    DateTime? conf = _confirmadoEm;
    if (statusCompra == CompraFornecedorStatusCompra.confirmada) {
      conf ??= widget.compraExistente?.confirmadoEm ?? agora;
    }
    return CompraFornecedor(
      id: id,
      lojaId: widget.lojaId.trim(),
      fornecedorHiveKey: widget.fornecedorHiveKey,
      fornecedorNome: widget.fornecedorNome,
      referenciaInterna: _refCtrl.text.trim(),
      dataCompra: _dataCompra,
      dataVencimento: _dataVencimento,
      statusCompra: statusCompra,
      statusPagamento: statusPagamento,
      observacao: _obsCtrl.text.trim(),
      frete: _frete,
      outrasDespesas: _outrasDespesas,
      desconto: _desconto,
      valorPago: _valorPago,
      itens: List<CompraFornecedorItem>.from(_itens),
      estoqueIntegrado: _estoqueIntegrado,
      idLancamentoFinanceiro: _idLancamentoFinanceiro,
      confirmadoEm: conf,
      criadoEm: widget.compraExistente?.criadoEm ?? agora,
      atualizadoEm: agora,
    );
  }

  /// Rateio + flags de sync antes de gravar no Hive.
  CompraFornecedor _prepararParaGravacao({
    required String statusCompra,
    required String statusPagamento,
  }) {
    final raw = _montarModelo(
      statusCompra: statusCompra,
      statusPagamento: statusPagamento,
    );
    final r = CompraFornecedorRateio.aplicar(raw);
    return r.copyWith(syncPendente: true, syncStatus: 'pendente');
  }

  static const _msgHiveIndisponivel =
      'Não foi possível salvar. Verifique o armazenamento local.';

  /// Grava no Hive e tenta sync. Retorna `false` se a box não abriu (nada persistido).
  Future<bool> _gravarNoHiveEsyncFirestore(CompraFornecedor c) async {
    final box = await CompraFornecedorHiveStore.openBox(widget.lojaId);
    if (box == null) return false;
    await box.put(c.id, c);
    final ok = await CompraFornecedorSyncService.sincronizar(c);
    await box.put(
      c.id,
      c.copyWith(syncPendente: !ok, syncStatus: ok ? 'ok' : 'erro'),
    );
    return true;
  }

  void _snackHiveIndisponivel() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(_msgHiveIndisponivel)),
    );
  }

  /// Confirmar só se não cancelada; primeira confirmação exige pelo menos um item.
  bool get _podeConfirmarCompra {
    if (_statusCompra == CompraFornecedorStatusCompra.cancelada) return false;
    if (_statusCompra == CompraFornecedorStatusCompra.confirmada) return true;
    return _itens.isNotEmpty;
  }

  Future<void> _salvarRascunho() async {
    if (_gravando) return;
    if (_statusCompra != CompraFornecedorStatusCompra.rascunho) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Esta compra não está em rascunho. Use “Salvar” para gravar as alterações.',
          ),
        ),
      );
      return;
    }
    setState(() => _gravando = true);
    try {
      if (!mounted) return;
      final c = _prepararParaGravacao(
        statusCompra: CompraFornecedorStatusCompra.rascunho,
        statusPagamento: _statusPagamento,
      );
      _compraId = c.id;
      final gravou = await _gravarNoHiveEsyncFirestore(c);
      if (!mounted) return;
      if (!gravou) {
        _snackHiveIndisponivel();
        return;
      }
      CompraFinanceiroIntegracaoService.aplicarAposPersistenciaLocal(c);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rascunho salvo')),
      );
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _gravando = false);
    }
  }

  Future<void> _salvarGeral() async {
    if (_gravando) return;
    setState(() => _gravando = true);
    try {
      if (!mounted) return;
      final c = _prepararParaGravacao(
        statusCompra: _statusCompra,
        statusPagamento: _statusPagamento,
      );
      _compraId = c.id;
      final gravou = await _gravarNoHiveEsyncFirestore(c);
      if (!mounted) return;
      if (!gravou) {
        _snackHiveIndisponivel();
        return;
      }
      CompraFinanceiroIntegracaoService.aplicarAposPersistenciaLocal(c);
      if (c.statusCompra == CompraFornecedorStatusCompra.cancelada) {
        await _sincronizarPipelineSeCancelada(c);
        CompraFinanceiroIntegracaoService.aplicarEfeitosCancelamento(c);
      } else {
        await _sincronizarPipelineSeConfirmada(c);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Compra atualizada')),
      );
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _gravando = false);
    }
  }

  Future<void> _confirmarCompra() async {
    if (_gravando) return;

    if (_statusCompra == CompraFornecedorStatusCompra.cancelada) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Compra cancelada não pode ser confirmada.')),
      );
      return;
    }

    final jaConfirmada =
        _statusCompra == CompraFornecedorStatusCompra.confirmada;
    if (!jaConfirmada && _itens.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Adicione pelo menos um item para confirmar a compra.'),
        ),
      );
      return;
    }

    setState(() => _gravando = true);
    try {
      if (!mounted) return;

      const novoStatus = CompraFornecedorStatusCompra.confirmada;
      final confEm = jaConfirmada
          ? (_confirmadoEm ?? widget.compraExistente?.confirmadoEm ?? DateTime.now())
          : DateTime.now();

      final cFix = _montarModelo(
        statusCompra: novoStatus,
        statusPagamento: _statusPagamento,
      );
      final merged = cFix.copyWith(
        confirmadoEm: confEm,
        estoqueIntegrado: _estoqueIntegrado,
        idLancamentoFinanceiro: _idLancamentoFinanceiro,
        criadoEm: widget.compraExistente?.criadoEm ?? cFix.criadoEm,
      );
      final comRateio = CompraFornecedorRateio.aplicar(merged);
      final finalModel =
          comRateio.copyWith(syncPendente: true, syncStatus: 'pendente');

      _compraId = finalModel.id;
      final gravou = await _gravarNoHiveEsyncFirestore(finalModel);
      if (!mounted) return;
      if (!gravou) {
        _snackHiveIndisponivel();
        return;
      }
      CompraFinanceiroIntegracaoService.aplicarAposPersistenciaLocal(finalModel);
      if (!jaConfirmada) {
        setState(() {
          _confirmadoEm = confEm;
          _statusCompra = novoStatus;
        });
      }
      await _sincronizarPipelineSeConfirmada(finalModel);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(jaConfirmada
              ? 'Compra já estava confirmada (sem duplicar efeitos).'
              : 'Compra confirmada.'),
        ),
      );
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _gravando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy');

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.compraExistente == null
            ? 'Nova compra'
            : 'Lançamento de compra'),
        backgroundColor: _primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _secao('Fornecedor e dados gerais', [
            Text(widget.fornecedorNome,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: _refCtrl,
              decoration: const InputDecoration(
                labelText: 'Referência / número interno',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Data da compra'),
              subtitle: Text(fmt.format(_dataCompra)),
              trailing: const Icon(Icons.calendar_today),
              onTap: _pickDataCompra,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Vencimento (opcional)'),
              subtitle: Text(
                  _dataVencimento != null ? fmt.format(_dataVencimento!) : '—'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_dataVencimento != null)
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _dataVencimento = null),
                    ),
                  IconButton(
                    icon: const Icon(Icons.event),
                    onPressed: _pickVencimento,
                  ),
                ],
              ),
            ),
            TextField(
              controller: _obsCtrl,
              decoration: const InputDecoration(
                labelText: 'Observação',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ]),
          const SizedBox(height: 20),
          _secao('Itens', [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _gravando ? null : _adicionarItem,
                    icon: const Icon(Icons.add),
                    label: const Text('Adicionar item'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_itens.isEmpty)
              Text(
                'Nenhum item. Compras sem itens ainda podem ser salvas como rascunho.',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              )
            else
              ...List.generate(_itens.length, (i) {
                final it = _itens[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(it.produtoNome),
                    subtitle: Text(
                      it.subtotalFinal > 0
                          ? '${it.quantidade} × ${_fmtBrl(it.custoUnitario)} (base) · '
                              'custo final ${_fmtBrl(it.custoUnitarioParaEstoquePrecificacao)} · '
                              'subtotal ${_fmtBrl(it.subtotalFinal)}'
                          : '${it.quantidade} × ${_fmtBrl(it.custoUnitario)} = ${_fmtBrl(it.subtotal)}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _removerItem(i),
                    ),
                  ),
                );
              }),
            const SizedBox(height: 8),
            Text('Subtotal itens: ${_fmtBrl(_subtotalItens)}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 20),
          _secao('Totais', [
            TextField(
              controller: _freteCtrl,
              decoration: const InputDecoration(
                labelText: 'Frete',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _outrasCtrl,
              decoration: const InputDecoration(
                labelText: 'Outras despesas (R\$)',
                hintText: 'Seguros, taxas, etc.',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: 'Desconto (R\$)',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Text('Valor total: ${_fmtBrl(_valorTotal)}',
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold, color: _primary)),
            const SizedBox(height: 8),
            TextField(
              controller: _valorPagoCtrl,
              decoration: const InputDecoration(
                labelText: 'Valor pago',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Text('Valor em aberto: ${_fmtBrl(_valorEmAberto)}',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: _valorEmAberto > 0.009
                      ? Colors.orange.shade800
                      : Colors.green.shade700,
                )),
          ]),
          const SizedBox(height: 20),
          _secao('Status', [
            DropdownButtonFormField<String>(
              key: ValueKey<String>('stc_$_statusCompra'),
              initialValue: _statusCompra,
              decoration: const InputDecoration(
                labelText: 'Status da compra',
                border: OutlineInputBorder(),
              ),
              items: CompraFornecedorStatusCompra.todos
                  .map((s) => DropdownMenuItem(
                        value: s,
                        child: Text(CompraFornecedorStatusCompra.legivel(s)),
                      ))
                  .toList(),
              onChanged: _gravando
                  ? null
                  : (v) {
                      if (v == null) return;
                      setState(() => _statusCompra = v);
                    },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey<String>('stp_$_statusPagamento'),
              initialValue: _statusPagamento,
              decoration: const InputDecoration(
                labelText: 'Status do pagamento',
                border: OutlineInputBorder(),
              ),
              items: CompraFornecedorStatusPagamento.todos
                  .map((s) => DropdownMenuItem(
                        value: s,
                        child:
                            Text(CompraFornecedorStatusPagamento.legivel(s)),
                      ))
                  .toList(),
              onChanged: _gravando
                  ? null
                  : (v) {
                      if (v == null) return;
                      setState(() => _statusPagamento = v);
                    },
            ),
          ]),
          const SizedBox(height: 24),
          if (_estoqueIntegrado)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Esta compra já teve estoque integrado (Fase 2). Edite com cuidado.',
                style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _gravando ? null : () => Navigator.pop(context),
                  child: const Text('Fechar'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _gravando ? null : _salvarGeral,
                  child: const Text('Salvar'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: (_gravando ||
                          _statusCompra !=
                              CompraFornecedorStatusCompra.rascunho)
                      ? null
                      : _salvarRascunho,
                  style: FilledButton.styleFrom(backgroundColor: Colors.blueGrey),
                  child: const Text('Salvar rascunho'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: (_gravando || !_podeConfirmarCompra)
                  ? null
                  : _confirmarCompra,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _gravando
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Confirmar compra'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _secao(String titulo, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          titulo,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }
}
