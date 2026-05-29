// lib/screens/contas_pagar_screen.dart
// Contas a pagar — parcelas de compras de fornecedor.

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';

import '../models/conta_pagar.dart';
import '../models/conta_pagar_constants.dart';
import '../services/conta_pagar_hive_store.dart';
import '../services/conta_pagar_migracao_diagnostico_service.dart';
import '../services/conta_pagar_service.dart';
import '../services/loja_id_service.dart';
import '../widgets/app_help_icon_button.dart';

const Color _primaryColor = Color(0xFF6366F1);
const Color _successColor = Color(0xFF22C55E);
const Color _warningColor = Color(0xFFF59E0B);
const Color _errorColor = Color(0xFFEF4444);
const Color _backgroundColor = Color(0xFFF8FAFC);

class ContasPagarScreen extends StatefulWidget {
  const ContasPagarScreen({
    super.key,
    this.compraId,
    this.fornecedorId,
    this.tituloContextual,
  });

  /// Quando preenchido, abre já filtrado às parcelas desta compra.
  final String? compraId;
  final int? fornecedorId;
  final String? tituloContextual;

  @override
  State<ContasPagarScreen> createState() => _ContasPagarScreenState();
}

class _ContasPagarScreenState extends State<ContasPagarScreen> {
  bool _loading = true;
  bool _erroResolucaoLoja = false;
  String? _lojaId;
  Box<ContaPagar>? _box;

  String _filtro = 'pendentes';
  String? _filtroFornecedor;
  String? _filtroCompraId;
  DateTime _mesRef = DateTime(DateTime.now().year, DateTime.now().month);

  final _currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _fmtData = DateFormat('dd/MM/yyyy');

  bool get _filtrandoPorCompra =>
      _filtroCompraId != null && _filtroCompraId!.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    final cid = widget.compraId?.trim();
    if (cid != null && cid.isNotEmpty) {
      _filtroCompraId = cid;
      _filtro = 'todas';
    }
    _init();
  }

  void _limparFiltroCompra() {
    setState(() => _filtroCompraId = null);
  }

  Future<void> _init() async {
    _lojaId = await LojaIdService.getWithTimeoutThenSessionFallback(
        timeout: const Duration(seconds: 10));
    if (!mounted) return;
    if (_lojaId == null || _lojaId!.trim().isEmpty) {
      setState(() {
        _loading = false;
        _erroResolucaoLoja = true;
      });
      return;
    }
    _box = await ContaPagarHiveStore.openBox(_lojaId!);
    if (mounted) setState(() => _loading = false);
  }

  DateTime get _inicioMes =>
      DateTime(_mesRef.year, _mesRef.month, 1);
  DateTime get _fimMes => DateTime(
        _mesRef.year,
        _mesRef.month + 1,
        0,
        23,
        59,
        59,
        999,
      );

  List<String> get _fornecedoresDisponiveis {
    if (_box == null || _lojaId == null) return [];
    final set = <String>{};
    for (final c in _box!.values) {
      if (c.lojaId != _lojaId) continue;
      final n = c.fornecedorNome.trim();
      if (n.isNotEmpty) set.add(n);
    }
    final list = set.toList()..sort();
    return list;
  }

  Iterable<ContaPagar> get _contasBaseFiltradas {
    if (_box == null || _lojaId == null) return const [];
    return ContaPagarService.listar(
      _box!,
      _lojaId!,
      filtroStatus: _filtro,
      fornecedorNome: _filtrandoPorCompra ? null : _filtroFornecedor,
      fornecedorId: _filtrandoPorCompra ? widget.fornecedorId : null,
      compraId: _filtroCompraId,
      vencimentoDe: _filtrandoPorCompra ? null : _inicioMes,
      vencimentoAte: _filtrandoPorCompra ? null : _fimMes,
    );
  }

  List<ContaPagar> get _lista {
    final list = _contasBaseFiltradas.toList()
      ..sort((a, b) => a.dataVencimento.compareTo(b.dataVencimento));
    return list;
  }

  ResumoContasPagar get _resumo {
    if (_box == null || _lojaId == null) {
      return const ResumoContasPagar();
    }
    final base = _filtrandoPorCompra
        ? _contasBaseFiltradas.toList()
        : _box!.values.where((c) => c.lojaId == _lojaId).toList();
    return ContaPagarService.resumo(
      contas: base,
      ano: _mesRef.year,
      mes: _mesRef.month,
    );
  }

  Future<void> _marcarPago(ContaPagar c) async {
    if (_lojaId == null) return;
    final formaCtrl = TextEditingController(text: c.formaPagamento);
    var dataPgto = DateTime.now();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Registrar pagamento'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${c.descricao}\nValor: ${_currency.format(c.valorParcela)}',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: formaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Forma de pagamento',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Data do pagamento'),
                  subtitle: Text(_fmtData.format(dataPgto)),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: dataPgto,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (d != null) setLocal(() => dataPgto = d);
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  'Será criado um lançamento financeiro (compra de mercadoria) '
                  'no valor da parcela. O estoque não é alterado.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
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
              child: const Text('Confirmar pagamento'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;

    final sucesso = await ContaPagarService.marcarComoPago(
      lojaId: _lojaId!,
      conta: c,
      formaPagamento: formaCtrl.text.trim().isEmpty
          ? 'Não informado'
          : formaCtrl.text.trim(),
      dataPagamento: dataPgto,
    );
    formaCtrl.dispose();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(sucesso
            ? 'Parcela marcada como paga.'
            : 'Não foi possível registrar o pagamento.'),
        backgroundColor: sucesso ? _successColor : _errorColor,
      ),
    );
  }

  Future<void> _cancelar(ContaPagar c) async {
    if (_lojaId == null) return;
    final paga = c.status == ContaPagarStatus.pago;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover parcela'),
        content: Text(
          paga
              ? 'Esta parcela e o lançamento financeiro vinculado serão removidos. '
                  'A parcela deixará de aparecer em Contas a Pagar e o pagamento '
                  'sairá do Financeiro e dos relatórios.'
              : 'Esta parcela será removida das Contas a Pagar e não entrará mais '
                  'nos totais em aberto.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final r = await ContaPagarService.cancelar(lojaId: _lojaId!, conta: c);
    if (!mounted) return;
    setState(() {});
    if (r.lancamentoNaoEncontrado) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Parcela removida. O lançamento financeiro vinculado não foi '
            'encontrado (pode já ter sido excluído).',
          ),
        ),
      );
    } else if (r.contaCancelada) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            paga && r.lancamentoExcluido
                ? 'Parcela e lançamento financeiro removidos.'
                : 'Parcela removida.',
          ),
        ),
      );
    }
  }

  Future<void> _editarVencimento(ContaPagar c) async {
    if (_lojaId == null) return;
    var nova = c.dataVencimento;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Alterar vencimento'),
          content: ListTile(
            title: const Text('Nova data'),
            subtitle: Text(_fmtData.format(nova)),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final d = await showDatePicker(
                context: ctx,
                initialDate: nova,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (d != null) setLocal(() => nova = d);
            },
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await ContaPagarService.atualizarVencimento(
      lojaId: _lojaId!,
      conta: c,
      novaData: nova,
    );
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _mostrarDiagnosticoMigracao() async {
    if (_lojaId == null) return;
    final list = await ContaPagarMigracaoDiagnosticoService
        .listarComprasSemParcelas(lojaId: _lojaId!);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Diagnóstico — compras sem parcelas'),
        content: SizedBox(
          width: double.maxFinite,
          child: list.isEmpty
              ? const Text(
                  'Nenhuma compra confirmada com saldo em aberto '
                  'sem contas a pagar geradas.',
                )
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${list.length} compra(s) candidata(s) à migração manual '
                        '(somente leitura — nada foi alterado):',
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      ...list.take(20).map(
                            (d) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                '• ${d.fornecedorNome}: '
                                '${_currency.format(d.valorEmAberto)} em aberto '
                                '(total ${_currency.format(d.valorTotal)}) · '
                                '${_fmtData.format(d.dataCompra)}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                      if (list.length > 20)
                        Text('… e mais ${list.length - 20}.'),
                    ],
                  ),
                ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Color _corStatus(String s) {
    switch (s) {
      case ContaPagarStatus.pago:
        return _successColor;
      case ContaPagarStatus.vencido:
        return _errorColor;
      case ContaPagarStatus.cancelado:
        return Colors.grey;
      default:
        return _warningColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_erroResolucaoLoja) {
      return Scaffold(
        appBar: AppBar(title: const Text('Contas a pagar')),
        body: Center(
          child: FilledButton.icon(
            onPressed: () {
              setState(() {
                _erroResolucaoLoja = false;
                _loading = true;
              });
              _init();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar novamente'),
          ),
        ),
      );
    }
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: _primaryColor)),
      );
    }

    final list = _lista;
    final r = _resumo;
    final mesLabel =
        DateFormat('MMMM/yyyy', 'pt_BR').format(_mesRef);
    final titulo = _filtrandoPorCompra
        ? (widget.tituloContextual?.trim().isNotEmpty == true
            ? widget.tituloContextual!.trim()
            : 'Parcelas desta compra')
        : 'Contas a pagar';

    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        title: Text(titulo),
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.troubleshoot_outlined),
            tooltip: 'Diagnóstico compras sem parcelas',
            onPressed: _mostrarDiagnosticoMigracao,
          ),
          const AppHelpIconButton(iconColor: Colors.white),
          PopupMenuButton<String>(
            initialValue: _filtro,
            onSelected: (v) => setState(() => _filtro = v),
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: 'pendentes', child: Text('Pendentes')),
              PopupMenuItem(value: 'vencidas', child: Text('Vencidas')),
              PopupMenuItem(value: 'pagas', child: Text('Pagas')),
              PopupMenuItem(value: 'todas', child: Text('Todas')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _init,
        color: _primaryColor,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (_filtrandoPorCompra)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Material(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.filter_alt_outlined,
                              size: 20, color: Colors.indigo.shade800),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Mostrando parcelas desta compra',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.indigo.shade900,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _limparFiltroCompra,
                            child: const Text('Ver todas'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (!_filtrandoPorCompra)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => setState(() {
                          _mesRef = DateTime(
                            _mesRef.year,
                            _mesRef.month - 1,
                          );
                        }),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Expanded(
                        child: Text(
                          mesLabel,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() {
                          _mesRef = DateTime(
                            _mesRef.year,
                            _mesRef.month + 1,
                          );
                        }),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _chipResumo('Em aberto', r.totalAberto, _warningColor),
                    _chipResumo('Vencido', r.totalVencido, _errorColor),
                    _chipResumo('Pago no mês', r.totalPagoNoMes, _successColor),
                    _chipResumo(
                        'Fluxo projetado', r.fluxoProjetado, _primaryColor),
                  ],
                ),
              ),
            ),
            if (!_filtrandoPorCompra && _fornecedoresDisponiveis.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: DropdownButtonFormField<String?>(
                    value: _filtroFornecedor,
                    decoration: const InputDecoration(
                      labelText: 'Fornecedor',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Todos'),
                      ),
                      ..._fornecedoresDisponiveis.map(
                        (f) => DropdownMenuItem(value: f, child: Text(f)),
                      ),
                    ],
                    onChanged: (v) => setState(() => _filtroFornecedor = v),
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: list.isEmpty
                  ? SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Text(
                          'Nenhuma conta neste filtro/período.',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ),
                    )
                  : SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (ctx, i) {
                          final c = list[i];
                          final st = c.statusEfetivo;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              title: Text(c.descricao),
                              subtitle: Text(
                                '${c.fornecedorNome}\n'
                                'Venc.: ${_fmtData.format(c.dataVencimento)} · '
                                '${ContaPagarStatus.legivel(st)}'
                                '${c.parcelaTotal > 1 ? ' · ${c.parcelaNumero}/${c.parcelaTotal}' : ''}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _currency.format(c.valorParcela),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: _corStatus(st),
                                    ),
                                  ),
                                  if (c.estaAberta)
                                    PopupMenuButton<String>(
                                      onSelected: (v) {
                                        if (v == 'pagar') {
                                          _marcarPago(c);
                                        } else if (v == 'venc') {
                                          _editarVencimento(c);
                                        } else if (v == 'cancelar') {
                                          _cancelar(c);
                                        }
                                      },
                                      itemBuilder: (ctx) => const [
                                        PopupMenuItem(
                                          value: 'pagar',
                                          child: Text('Marcar como paga'),
                                        ),
                                        PopupMenuItem(
                                          value: 'venc',
                                          child: Text('Editar vencimento'),
                                        ),
                                        PopupMenuItem(
                                          value: 'cancelar',
                                          child: Text('Cancelar'),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                              isThreeLine: true,
                              onTap: c.estaAberta
                                  ? () => _marcarPago(c)
                                  : null,
                            ),
                          );
                        },
                        childCount: list.length,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chipResumo(String label, double valor, Color cor) {
    return Chip(
      avatar: CircleAvatar(backgroundColor: cor, radius: 8),
      label: Text('$label: ${_currency.format(valor)}'),
    );
  }
}
