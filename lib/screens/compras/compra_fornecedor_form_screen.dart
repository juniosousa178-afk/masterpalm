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
import '../../services/conta_pagar_service.dart';
import 'compra_detalhar_produtos_screen.dart';
import '../../services/conta_pagar_hive_store.dart';
import '../../utils/compra_fornecedor_rateio.dart';
import '../contas_pagar_screen.dart';
import '../produto_form_screen.dart';

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
  /// Retorno do bottom sheet de escolha de produto (cadastro completo na tela de produto).
  static final Object _sheetCadastrarProduto = Object();

  final _refCtrl = TextEditingController();
  final _obsCtrl = TextEditingController();
  final _freteCtrl = TextEditingController();
  final _outrasCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _valorPagoCtrl = TextEditingController();
  final _valorInformadoCtrl = TextEditingController();
  final _parcelasCtrl = TextEditingController(text: '3');
  final _intervaloMesesCtrl = TextEditingController(text: '1');

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

  bool _pagamentoParcelado = false;
  int _numeroParcelas = 3;
  DateTime _primeiroVencimento = DateTime.now();
  int _intervaloMensal = 1;

  String _tipoCompra = CompraFornecedorTipo.produtosEstoque;

  bool get _ehFinanceira =>
      _tipoCompra == CompraFornecedorTipo.financeira;

  bool get _ehRevendaDetalharDepois =>
      _tipoCompra == CompraFornecedorTipo.revendaDetalharDepois;

  bool get _usaValorInformado => _ehFinanceira || _ehRevendaDetalharDepois;

  bool get _tipoFixo =>
      _statusCompra == CompraFornecedorStatusCompra.confirmada;

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
      _tipoCompra = CompraFornecedorTipo.ouPadrao(e.tipoCompra);
      _valorInformadoCtrl.text = _fmtNum(e.valorInformado);
    }
  }

  Future<void> _pickPrimeiroVencimento() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _primeiroVencimento,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _primeiroVencimento = d);
  }

  void _syncNumeroParcelasFromController() {
    final n = int.tryParse(_parcelasCtrl.text.trim());
    if (n != null) {
      _numeroParcelas = n.clamp(1, 48);
    }
  }

  Future<GeracaoParcelasCompraResultado?> _gerarContasPagarSeParcelado(
    CompraFornecedor compra,
  ) async {
    if (!_pagamentoParcelado) return null;

    _syncNumeroParcelasFromController();

    debugPrint('[CP_COMPRA][parcelado] $_pagamentoParcelado');
    debugPrint('[CP_COMPRA][numeroParcelas] $_numeroParcelas');
    debugPrint('[CP_COMPRA][primeiroVencimento] $_primeiroVencimento');
    debugPrint('[CP_COMPRA][compraId] ${compra.id}');
    debugPrint('[CP_COMPRA][valorInformado] ${compra.valorInformado}');
    debugPrint('[CP_COMPRA][valorTotalFinanceiro] ${compra.valorTotalFinanceiro}');

    if (compra.valorTotalFinanceiro <= 1e-9) {
      return GeracaoParcelasCompraResultado(
        criadas: 0,
        jaExistiam: false,
        erro: 'valor_invalido',
      );
    }
    if (compra.id.trim().isEmpty) {
      return GeracaoParcelasCompraResultado(
        criadas: 0,
        jaExistiam: false,
        erro: 'compra_id_vazio',
      );
    }
    if (_numeroParcelas < 1) {
      return GeracaoParcelasCompraResultado(
        criadas: 0,
        jaExistiam: false,
        erro: 'numero_parcelas_invalido',
      );
    }

    try {
      debugPrint('[CP_COMPRA][antes_gerar_parcelas]');
      final r = await ContaPagarService.gerarParcelasCompra(
        lojaId: widget.lojaId,
        compra: compra,
        numeroParcelas: _numeroParcelas,
        primeiroVencimento: _primeiroVencimento,
        intervaloMeses: _intervaloMensal,
      );
      debugPrint('[CP_COMPRA][parcelas_criadas] ${r.criadas}');
      if (r.jaExistiam) {
        debugPrint('[CP_COMPRA][parcelas_existentes] compraId=${compra.id}');
      }
      if (r.erro != null) {
        debugPrint('[CP_COMPRA][erro_gerar_parcelas] ${r.erro}');
      }
      return r;
    } catch (e, st) {
      debugPrint('[CP_COMPRA][erro_gerar_parcelas] $e\n$st');
      return GeracaoParcelasCompraResultado(
        criadas: 0,
        jaExistiam: false,
        erro: 'excecao',
      );
    }
  }

  Future<void> _oferecerVerParcelasGeradas({
    required CompraFornecedor compra,
    required int quantidade,
    bool jaExistiam = false,
  }) async {
    final ver = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          jaExistiam ? 'Contas a pagar existentes' : 'Contas a pagar geradas',
        ),
        content: Text(
          jaExistiam
              ? 'Esta compra já possui $quantidade parcela(s) em Contas a pagar.'
              : '$quantidade parcela(s) criada(s) para esta compra. '
                  'Você pode registrar os pagamentos em Contas a pagar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Fechar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ver parcelas'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (ver == true) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ContasPagarScreen(
            compraId: compra.id,
            fornecedorId: widget.fornecedorHiveKey,
            tituloContextual: 'Parcelas desta compra',
          ),
        ),
      );
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
    _valorInformadoCtrl.dispose();
    _parcelasCtrl.dispose();
    _intervaloMesesCtrl.dispose();
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

  double get _valorTotal {
    final base = _usaValorInformado
        ? _parseMoney(_valorInformadoCtrl.text)
        : _subtotalItens;
    return (base + _frete + _outrasDespesas - _desconto).clamp(0.0, 1e15);
  }

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
      final sheetResult = await showModalBottomSheet<Object?>(
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
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  Navigator.pop(ctx, _sheetCadastrarProduto),
                              icon: const Icon(Icons.add_business_outlined),
                              label: const Text('Cadastrar produto novo'),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
                                    Navigator.pop(
                                      ctx,
                                      CompraFornecedorItem(
                                        produtoNome: p.nome,
                                        quantidade: 1,
                                        custoUnitario: p.custoReal,
                                        productId: p.idFirebase.trim().isEmpty
                                            ? null
                                            : p.idFirebase.trim(),
                                        itemCompraId: _uuid.v4(),
                                        codigoBarras: p.codigoBarras.trim(),
                                      ),
                                    );
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

      if (!mounted) return;

      if (identical(sheetResult, _sheetCadastrarProduto)) {
        final salvo = await Navigator.of(context).push<Produto>(
          MaterialPageRoute(
            settings: RouteSettings(
              arguments: {'prefillFornecedor': widget.fornecedorNome},
            ),
            builder: (_) => const ProdutoFormScreen(
              produto: null,
              returnProductOnSave: true,
            ),
          ),
        );
        if (!mounted || salvo == null) return;
        escolhido = CompraFornecedorItem(
          produtoNome: salvo.nome,
          quantidade: 1,
          custoUnitario: salvo.custoReal,
          productId: salvo.idFirebase.trim().isEmpty
              ? null
              : salvo.idFirebase.trim(),
          itemCompraId: _uuid.v4(),
          codigoBarras: salvo.codigoBarras.trim(),
        );
      } else if (sheetResult is CompraFornecedorItem) {
        escolhido = sheetResult;
      }
    } finally {
      qBusca.dispose();
    }

    if (escolhido == null || !mounted) return;
    final base = escolhido;
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
    if (!c.movimentaEstoque) return;
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
      itens: _usaValorInformado
          ? const <CompraFornecedorItem>[]
          : List<CompraFornecedorItem>.from(_itens),
      estoqueIntegrado: _estoqueIntegrado,
      idLancamentoFinanceiro: _idLancamentoFinanceiro,
      confirmadoEm: conf,
      criadoEm: widget.compraExistente?.criadoEm ?? agora,
      atualizadoEm: agora,
      tipoCompra: CompraFornecedorTipo.ouPadrao(_tipoCompra),
      valorInformado:
          _usaValorInformado ? _parseMoney(_valorInformadoCtrl.text) : 0,
      statusDetalhamentoProdutos: _ehRevendaDetalharDepois
          ? CompraFornecedorStatusDetalhamento.aguardandoDetalhamento
          : (_ehFinanceira
              ? CompraFornecedorStatusDetalhamento.naoAplicavel
              : (widget.compraExistente?.statusDetalhamentoProdutos ??
                  CompraFornecedorStatusDetalhamento.naoAplicavel)),
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

  /// Confirmar só se não cancelada; produtos exigem itens; financeira exige valor.
  bool get _podeConfirmarCompra {
    if (_statusCompra == CompraFornecedorStatusCompra.cancelada) return false;
    if (_statusCompra == CompraFornecedorStatusCompra.confirmada) return true;
    if (_usaValorInformado) return _valorTotal > 1e-9;
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

    debugPrint('[CP_COMPRA][confirm_start]');
    debugPrint('[CP_COMPRA][tipoCompra] $_tipoCompra');
    debugPrint('[CP_COMPRA][movimentaEstoque] ${CompraFornecedorTipo.movimentaEstoque(_tipoCompra)}');

    if (_statusCompra == CompraFornecedorStatusCompra.cancelada) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Compra cancelada não pode ser confirmada.')),
      );
      return;
    }

    final jaConfirmada =
        _statusCompra == CompraFornecedorStatusCompra.confirmada;
    if (!jaConfirmada) {
      if (_usaValorInformado) {
        if (_valorTotal <= 1e-9) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Informe o valor da compra para confirmar.',
              ),
            ),
          );
          return;
        }
      } else if (_itens.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Adicione pelo menos um item para confirmar a compra.'),
          ),
        );
        return;
      }
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
      GeracaoParcelasCompraResultado? parcelasGeradas;
      if (_pagamentoParcelado) {
        parcelasGeradas = await _gerarContasPagarSeParcelado(finalModel);
      }
      if (!jaConfirmada) {
        setState(() {
          _confirmadoEm = confEm;
          _statusCompra = novoStatus;
        });
      }
      await _sincronizarPipelineSeConfirmada(finalModel);
      if (!mounted) return;

      if (parcelasGeradas != null) {
        if (parcelasGeradas.criadas > 0) {
          await _oferecerVerParcelasGeradas(
            compra: finalModel,
            quantidade: parcelasGeradas.criadas,
          );
        } else if (parcelasGeradas.jaExistiam) {
          final box = await ContaPagarHiveStore.openBox(widget.lojaId);
          final qtd = box != null
              ? ContaPagarService.contarParcelasParaCompra(box, finalModel.id)
              : 0;
          if (!mounted) return;
          if (qtd > 0) {
            await _oferecerVerParcelasGeradas(
              compra: finalModel,
              quantidade: qtd,
              jaExistiam: true,
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Contas a pagar já existiam para esta compra (sem duplicar).',
                ),
              ),
            );
          }
        } else if (parcelasGeradas.erro == 'valor_invalido') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Informe um valor válido para gerar as parcelas.',
              ),
            ),
          );
        } else if (parcelasGeradas.erro == 'box_indisponivel') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Não foi possível abrir Contas a Pagar localmente. '
                'Tente recarregar o app.',
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(jaConfirmada
                  ? 'Compra confirmada, mas não foi possível gerar parcelas.'
                  : 'Compra confirmada, mas não foi possível gerar parcelas.'),
            ),
          );
        }
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(jaConfirmada
                ? 'Compra já estava confirmada (sem duplicar efeitos).'
                : 'Compra confirmada.'),
          ),
        );
      }
      if (!mounted) return;
      if (finalModel.ehCompraRevendaDetalharDepois &&
          finalModel.aguardaDetalhamentoProdutos) {
        final detalhar = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Detalhar produtos agora?'),
            content: const Text(
              'A compra foi confirmada. Você pode vincular produtos existentes ou '
              'novos agora, sem gerar novo financeiro.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Depois'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Detalhar produtos'),
              ),
            ],
          ),
        );
        if (detalhar == true && mounted) {
          await _abrirDetalharProdutos(finalModel);
        }
      }
      if (!mounted) return;
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
        actions: const [],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _secao('Tipo de compra', [
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              title: const Text('Compra com produtos agora'),
              subtitle: const Text(
                'Use quando já quer informar produtos, quantidades e custos '
                'para entrada no estoque.',
              ),
              value: CompraFornecedorTipo.produtosEstoque,
              groupValue: _tipoCompra,
              onChanged: _tipoFixo || _gravando
                  ? null
                  : (v) {
                      if (v == null) return;
                      setState(() => _tipoCompra = v);
                    },
            ),
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              title: const Text('Compra para revenda — detalhar produtos depois'),
              subtitle: const Text(
                'Use quando quer lançar primeiro o valor total da compra e depois '
                'vincular produtos existentes ou novos sem duplicar financeiro.',
              ),
              value: CompraFornecedorTipo.revendaDetalharDepois,
              groupValue: _tipoCompra,
              onChanged: _tipoFixo || _gravando
                  ? null
                  : (v) {
                      if (v == null) return;
                      setState(() => _tipoCompra = v);
                    },
            ),
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              title: const Text('Compra apenas financeira'),
              subtitle: const Text(
                'Use para registrar um valor a pagar sem movimentar estoque, '
                'como serviço, frete, embalagem, manutenção ou compra sem '
                'detalhar produtos.',
              ),
              value: CompraFornecedorTipo.financeira,
              groupValue: _tipoCompra,
              onChanged: _tipoFixo || _gravando
                  ? null
                  : (v) {
                      if (v == null) return;
                      setState(() => _tipoCompra = v);
                    },
            ),
            if (_tipoFixo)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Tipo definido na confirmação e não pode ser alterado.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
          ]),
          const SizedBox(height: 12),
          _buildAvisoTipo(),
          const SizedBox(height: 16),
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
          if (!_usaValorInformado) ...[
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
                  'Adicione pelo menos um item para confirmar esta compra.',
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
          ],
          const SizedBox(height: 20),
          _secao('Totais', [
            if (_usaValorInformado) ...[
              TextField(
                controller: _valorInformadoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Valor da compra *',
                  hintText: 'Serviço, frete avulso, manutenção…',
                  border: OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
            ],
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
          _secao('Pagamento parcelado', [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Pagamento parcelado'),
              subtitle: const Text(
                'Gera contas a pagar ao confirmar. '
                'Não lança saída no financeiro até marcar cada parcela como paga.',
              ),
              value: _pagamentoParcelado,
              onChanged: _gravando
                  ? null
                  : (v) => setState(() {
                        _pagamentoParcelado = v;
                        if (v) {
                          _valorPagoCtrl.text = '0';
                          _statusPagamento =
                              CompraFornecedorStatusPagamento.pendente;
                        }
                      }),
            ),
            if (_pagamentoParcelado) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade700),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 18, color: Colors.amber.shade900),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _ehFinanceira
                            ? 'Se esta compra gerar Contas a Pagar, não lance o mesmo valor '
                                'manualmente no Financeiro para evitar duplicidade. '
                                'O lançamento financeiro será criado automaticamente quando '
                                'você pagar cada parcela.'
                            : 'Não lance essa mesma compra manualmente no Financeiro, '
                                'para evitar duplicidade. O lançamento financeiro será criado '
                                'automaticamente quando você pagar cada parcela.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: Colors.amber.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _parcelasCtrl,
                decoration: const InputDecoration(
                  labelText: 'Número de parcelas',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (v) {
                  final n = int.tryParse(v) ?? 1;
                  setState(() => _numeroParcelas = n.clamp(1, 48));
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Primeiro vencimento'),
                subtitle: Text(DateFormat('dd/MM/yyyy').format(_primeiroVencimento)),
                trailing: const Icon(Icons.calendar_today),
                onTap: _gravando ? null : _pickPrimeiroVencimento,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _intervaloMesesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Intervalo entre parcelas (meses)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (v) {
                  final n = int.tryParse(v) ?? 1;
                  setState(() => _intervaloMensal = n.clamp(1, 24));
                },
              ),
              if (_valorTotal > 0 && _numeroParcelas > 0) ...[
                const SizedBox(height: 8),
                Text(
                  'Prévia: ${ContaPagarService.parcelarValores(_valorTotal, _numeroParcelas).map((p) => _fmtBrl(p)).join(' · ')}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ],
            ],
          ]),
          const SizedBox(height: 20),
          _secao('Status', [
            DropdownButtonFormField<String>(
              key: ValueKey<String>('stc_$_statusCompra'),
              value: _statusCompra,
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
              value: _statusPagamento,
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
          if (widget.compraExistente != null &&
              widget.compraExistente!.ehCompraRevendaDetalharDepois &&
              widget.compraExistente!.statusCompra ==
                  CompraFornecedorStatusCompra.confirmada &&
              widget.compraExistente!.aguardaDetalhamentoProdutos) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed:
                    _gravando ? null : () => _abrirDetalharProdutos(widget.compraExistente!),
                icon: const Icon(Icons.playlist_add_check),
                label: const Text('Detalhar produtos'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.amber.shade800,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
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

  Widget _buildAvisoTipo() {
    final financeira = _ehFinanceira;
    final revenda = _ehRevendaDetalharDepois;
    final corFundo = financeira
        ? Colors.teal.shade50
        : revenda
            ? Colors.amber.shade50
            : Colors.blue.shade50;
    final corBorda = financeira
        ? Colors.teal.shade100
        : revenda
            ? Colors.amber.shade200
            : Colors.blue.shade100;
    final texto = financeira
        ? 'Esta compra não movimenta estoque. Controle o valor a pagar e os pagamentos; '
            'se gerar Contas a Pagar, não lance o mesmo valor manualmente no Financeiro.'
        : revenda
            ? 'Lance o valor total agora. Depois use “Detalhar produtos” para vincular '
                'produtos ao estoque — isso não cria nova Conta a Pagar nem lançamento financeiro.'
            : 'Informe os produtos agora para o fluxo de precificação/estoque. '
                'O financeiro entra quando as parcelas forem pagas.';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: corFundo,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: corBorda),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            financeira
                ? Icons.account_balance_wallet_outlined
                : revenda
                    ? Icons.inventory_2_outlined
                    : Icons.info_outline,
            size: 18,
            color: financeira
                ? Colors.teal.shade800
                : revenda
                    ? Colors.amber.shade900
                    : Colors.blue.shade700,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: financeira
                    ? Colors.teal.shade900
                    : revenda
                        ? Colors.amber.shade900
                        : Colors.blue.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _abrirDetalharProdutos(CompraFornecedor compra) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CompraDetalharProdutosScreen(
          lojaId: widget.lojaId,
          compraId: compra.id,
        ),
      ),
    );
    if (mounted) setState(() {});
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
