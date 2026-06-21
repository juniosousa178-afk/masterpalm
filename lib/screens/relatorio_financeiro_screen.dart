// lib/screens/relatorio_financeiro_screen.dart
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/hive_box_names.dart';
import '../models/venda.dart';
import '../models/conta_receber.dart';
import '../models/fechamento_mensal.dart';
import '../models/lancamento_financeiro.dart';
import '../financeiro/financeiro_constants.dart';
import '../financeiro/lancamento_financeiro_origem_ui.dart';
import '../services/fechamento_service.dart';
import '../services/financeiro_firestore_service.dart';
import '../services/financeiro_hive_store.dart';
import '../services/financeiro_lancamento_exclusao_service.dart';
import '../services/conta_receber_service.dart';
import '../services/financeiro_service.dart';
import '../services/loja_id_service.dart';
import '../services/vendas_firestore_service.dart';
import '../core/venda_metrics_filter.dart';
import '../core/financeiro_lancamento_legacy_resolver.dart';
import '../core/financeiro_relatorio_taxas.dart';

class RelatorioFinanceiroScreen extends StatefulWidget {
  const RelatorioFinanceiroScreen({super.key});

  @override
  State<RelatorioFinanceiroScreen> createState() =>
      _RelatorioFinanceiroScreenState();
}

class _RelatorioFinanceiroScreenState extends State<RelatorioFinanceiroScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // Cores do tema moderno
  static const Color _primaryColor = Color(0xFF6366F1);
  static const Color _secondaryColor = Color(0xFF8B5CF6);
  static const Color _successColor = Color(0xFF22C55E);
  static const Color _warningColor = Color(0xFFF59E0B);
  static const Color _errorColor = Color(0xFFEF4444);
  static const Color _surfaceColor = Color(0xFFF8FAFC);

  late TabController _tabController;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  late String lojaId;
  late Box<Venda> vendasBox;
  late Box<FechamentoMensal> fechamentosBox;
  Box<LancamentoFinanceiro>? _lancamentosFinanceiroBox;

  DateTime hoje = DateTime.now();
  final TextEditingController _filtroFechController = TextEditingController();
  void _onFiltroChanged() => setState(() {});
  bool _carregando = true;
  bool _isOffline = false;
  bool _fechandoMes = false;
  bool _exportandoPdf = false;
  String? _ultimoErroSync;
  bool _erroSyncDispensado = false;
  String _ordenacaoFech = 'recente'; // recente | antigo | valor_maior | valor_menor
  DateTime? _periodoInicio;
  DateTime? _periodoFim;
  String _motivoAcaoLancamento = '';
  List<ContaReceber> _contasReceberCache = [];

  /// Mesmas regras que Relatórios Financeiros + Metas e fechamento mensal.
  RelatorioTaxasConfig _taxasRelatorio = RelatorioTaxasConfig.defaults;

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: 2, vsync: this);
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _filtroFechController.addListener(_onFiltroChanged);

    Connectivity().onConnectivityChanged.listen((result) {
      if (mounted) {
        setState(() => _isOffline = result.length == 1 && result.first == ConnectivityResult.none);
      }
    });
    WidgetsBinding.instance.addObserver(this);
    _initData();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() => hoje = DateTime.now());
    }
  }

  Future<void> _initData() async {
    final resolvedId =
        (await LojaIdService.getWithTimeoutThenSessionFallback(
            timeout: const Duration(seconds: 10)))
            ?.trim();

    if (resolvedId == null || resolvedId.isEmpty) {
      debugPrint(
        '[FINANCEIRO_READ] [LOJA_ID] lojaId ausente ao carregar RelatorioFinanceiroScreen; relatório não será exibido.',
      );
      if (mounted) {
        setState(() {
          _ultimoErroSync = 'Nenhuma loja ativa encontrada. Faça login novamente ou selecione uma loja.';
          _carregando = false;
        });
      }
      return;
    }

    lojaId = resolvedId.trim();
    _taxasRelatorio = await RelatorioTaxasConfig.loadForLoja(lojaId);
    final vendasBoxName = HiveBoxNames.vendas(lojaId);

    if (Hive.isBoxOpen(vendasBoxName)) {
      vendasBox = Hive.box<Venda>(vendasBoxName);
    } else {
      vendasBox = await Hive.openBox<Venda>(vendasBoxName);
    }

    try {
      if (Hive.isBoxOpen('fechamentos_mensais')) {
        fechamentosBox = Hive.box<FechamentoMensal>('fechamentos_mensais');
      } else {
        fechamentosBox = await Hive.openBox<FechamentoMensal>('fechamentos_mensais');
      }
    } catch (e) {
      fechamentosBox = await Hive.openBox<FechamentoMensal>('fechamentos_mensais');
    }

    _lancamentosFinanceiroBox =
        await FinanceiroHiveStore.openLancamentosBox(lojaId);

    try {
      final crBox = await ContaReceberService.openBoxLoja(lojaId);
      _contasReceberCache = crBox.values.toList();
    } catch (e) {
      debugPrint(
        '[FIN-UI] CR cache indisponível (type=${e.runtimeType})',
      );
      _contasReceberCache = [];
    }

    _ultimoErroSync = null;
    final connectivity = await Connectivity().checkConnectivity();
    _isOffline = connectivity.length == 1 && connectivity.first == ConnectivityResult.none;

    if (!_isOffline) {
      try {
        await FinanceiroFirestoreService.pullLojaFirestoreParaHiveFase2d(lojaId);
        await FinanceiroFirestoreService.sincronizarTombstonesLancamentos(lojaId);
      } catch (e) {
        debugPrint(
          '[FINANCEIRO_READ] Pull lançamentos (type=${e.runtimeType}) | lojaId=$lojaId',
        );
      }
    }

    if (!_isOffline) {
      try {
        await VendasFirestoreService.syncFirestoreToHive(
          lojaId: lojaId,
          vendasBox: vendasBox,
        );
      } catch (e) {
        _ultimoErroSync = e.toString();
        debugPrint(
          '[FINANCEIRO_READ] Erro ao sincronizar vendas do Firestore (type=${e.runtimeType}) | lojaId=$lojaId',
        );
      }
    }

    // Fechamento automático: mês anterior só é calculado se ainda não existir registro.
    // Meses passados já salvos ficam congelados em [FechamentoService.fecharMes] (não sobrescreve).
    // Mês atual continua sendo atualizado aqui (vendas + taxas da config).
    try {
      final now = DateTime.now();
      final mesAnterior = now.month == 1
          ? DateTime(now.year - 1, 12)
          : DateTime(now.year, now.month - 1);
      final anoAnt = mesAnterior.year;
      final mesAnt = mesAnterior.month;
      final jaFechouAnterior = fechamentosBox.values.any(
        (f) => f.lojaId == lojaId && f.ano == anoAnt && f.mes == mesAnt,
      );
      if (!jaFechouAnterior) {
        await FechamentoService.fecharMes(
          ano: anoAnt,
          mes: mesAnt,
          lojaId: lojaId,
          vendasBox: vendasBox,
          fechamentosBox: fechamentosBox,
        );
      }
      // Atualiza também o mês atual para a lista ficar sempre em dia
      await FechamentoService.fecharMes(
        ano: now.year,
        mes: now.month,
        lojaId: lojaId,
        vendasBox: vendasBox,
        fechamentosBox: fechamentosBox,
      );
    } catch (e) {
      debugPrint('Fechamento automático (type=${e.runtimeType})');
    }

    if (mounted) {
      setState(() => _carregando = false);
      _animationController.forward();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _filtroFechController.removeListener(_onFiltroChanged);
    _filtroFechController.dispose();
    _tabController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _showModernSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? _errorColor : _successColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  bool _isSameMonth(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;
  bool _isSameYear(DateTime a, DateTime b) => a.year == b.year;

  ({double dinheiro, double pix, double cartao, double recebido}) _pagamentos(Venda v) {
    double dinheiro = v.pagamentoDinheiro;
    double pix = v.pagamentoPix;
    double cartao = v.pagamentoCartao;
    final recebido = dinheiro + pix + cartao;
    return (dinheiro: dinheiro, pix: pix, cartao: cartao, recebido: recebido);
  }

  double _custo(Venda v) => v.custoProdutos;

  Iterable<Venda> _vendasFiltradasPor(bool Function(Venda v) filtro) {
    return vendasBox.values
        .where((v) =>
            v.lojaId == lojaId && incluirVendaEmMetricas(v) && filtro(v))
        .toList();
  }

  ({double venda, double custo, double taxas, double lucro}) _agregarPeriodo(
      bool Function(Venda v) filtro) {
    double venda = 0, custo = 0, taxas = 0, lucro = 0;

    for (final v in _vendasFiltradasPor(filtro)) {
      venda += v.total;
      custo += _custo(v);
      final tv = FinanceiroRelatorioTaxas.taxasParaVenda(v, _taxasRelatorio);
      taxas += tv;
      lucro += v.total - v.custoProdutos - tv;
    }

    return (venda: venda, custo: custo, taxas: taxas, lucro: lucro);
  }

  /// Mês civil. Se for passado e existir [FechamentoMensal] salvo, usa o snapshot (igual ao card).
  ({double venda, double custo, double taxas, double lucro})
      _resumoMesCalendarioPreferSnapshot(int ano, int mes) {
    if (FechamentoService.mesEhAnteriorAoCorrente(ano, mes)) {
      final f = FechamentoService.obterFechamentoSalvoParaMes(
        fechamentosBox,
        lojaId,
        ano,
        mes,
      );
      if (f != null && f.isInBox) {
        return (
          venda: f.vendaTotal,
          custo: f.custoTotal,
          taxas: f.taxasTotal,
          lucro: f.lucroTotal,
        );
      }
    }
    return _agregarPeriodo((v) => v.data.year == ano && v.data.month == mes);
  }

  ({double dinheiro, double pix, double cartao}) _pagamentosDoMesAtual() {
    double dinheiro = 0, pix = 0, cartao = 0;

    for (final v in _vendasFiltradasPor((x) => _isSameMonth(x.data, hoje))) {
      final p = _pagamentos(v);
      dinheiro += p.dinheiro;
      pix += p.pix;
      cartao += p.cartao;
    }

    return (dinheiro: dinheiro, pix: pix, cartao: cartao);
  }

  String _fmt(double v) => v.toStringAsFixed(2).replaceAll('.', ',');

  List<FechamentoMensal> get _fechamentosFiltrados {
    var all = fechamentosBox.values.where((f) => f.lojaId == lojaId).toList();
    all = List.from(all)
      ..sort((a, b) {
        if (_ordenacaoFech == 'antigo') {
          return DateTime(a.ano, a.mes).compareTo(DateTime(b.ano, b.mes));
        }
        if (_ordenacaoFech == 'valor_maior') {
          return b.vendaTotal.compareTo(a.vendaTotal);
        }
        if (_ordenacaoFech == 'valor_menor') {
          return a.vendaTotal.compareTo(b.vendaTotal);
        }
        return DateTime(b.ano, b.mes).compareTo(DateTime(a.ano, a.mes));
      });

    if (_filtroFechController.text.trim().isEmpty) return all;
    final f = _filtroFechController.text.trim();

    return all
        .where((x) =>
            DateFormat('MM/yyyy').format(DateTime(x.ano, x.mes)).contains(f))
        .toList();
  }

  Future<void> _exportarPdf() async {
    if (_exportandoPdf) return;
    setState(() => _exportandoPdf = true);
    try {
      final dia = _agregarPeriodo((v) => _isSameDay(v.data, hoje));
      final mes = _agregarPeriodo((v) => _isSameMonth(v.data, hoje));
      final ano = _agregarPeriodo((v) => _isSameYear(v.data, hoje));
      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (pw.Context ctx) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Center(
                  child: pw.Text(
                    'Relatório Financeiro',
                    style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Center(
                  child: pw.Text(
                    'Gerado em ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                ),
                pw.SizedBox(height: 24),
                _pdfRow('Hoje (${DateFormat('dd/MM/yyyy').format(hoje)})', dia),
                pw.SizedBox(height: 12),
                _pdfRow('Este Mês', mes),
                pw.SizedBox(height: 12),
                _pdfRow('Este Ano', ano),
              ],
            );
          },
        ),
      );
      await Printing.layoutPdf(onLayout: (_) => pdf.save());
      if (mounted) _showModernSnackBar('PDF exportado com sucesso!');
    } catch (e) {
      if (mounted) _showModernSnackBar('Erro ao exportar: $e', isError: true);
    } finally {
      if (mounted) setState(() => _exportandoPdf = false);
    }
  }

  pw.Widget _pdfRow(String titulo, ({double venda, double custo, double taxas, double lucro}) d) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(titulo, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Text('Vendas: R\$ ${_fmt(d.venda)}'),
          pw.Text('Custo: R\$ ${_fmt(d.custo)}'),
          pw.Text('Taxas operacionais (config/gravadas): R\$ ${_fmt(d.taxas)}'),
          pw.Text('Lucro operacional de vendas: R\$ ${_fmt(d.lucro)}'),
        ],
      ),
    );
  }

  Future<void> _selecionarPeriodo() async {
    final now = DateTime.now();
    final ini = await showDatePicker(
      context: context,
      initialDate: _periodoInicio ?? now,
      firstDate: DateTime(2020),
      lastDate: now,
    );
    if (ini == null || !mounted) return;
    final fim = await showDatePicker(
      context: context,
      initialDate: _periodoFim ?? ini,
      firstDate: ini,
      lastDate: now,
    );
    if (fim != null && mounted) {
      setState(() {
        _periodoInicio = ini;
        _periodoFim = fim.isBefore(ini) ? ini : fim;
      });
    }
  }

  void _mostrarDetalhesVendas(bool Function(Venda v) filtro) {
    final vendas = _vendasFiltradasPor(filtro).toList();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        builder: (_, ctrl) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '${vendas.length} venda(s)',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: ctrl,
                  itemCount: vendas.length,
                  itemBuilder: (_, i) {
                    final v = vendas[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _primaryColor.withOpacity(0.2),
                        child: const Icon(Icons.receipt, color: _primaryColor, size: 20),
                      ),
                      title: Text(v.clienteNome),
                      subtitle: Text(DateFormat('dd/MM/yyyy HH:mm').format(v.data)),
                      trailing: Text(
                        'R\$ ${_fmt(v.total)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _fecharMesAtual() async {
    if (_fechandoMes) return;
    if (!mounted) return;
    setState(() => _fechandoMes = true);

    try {
      final now = DateTime.now();
      await FechamentoService.fecharMes(
        ano: now.year,
        mes: now.month,
        lojaId: lojaId,
        vendasBox: vendasBox,
        fechamentosBox: fechamentosBox,
      );
      if (!mounted) return;
      setState(() => _fechandoMes = false);
      _showModernSnackBar('Fechamento mensal atualizado!');
    } catch (e) {
      if (mounted) {
        setState(() => _fechandoMes = false);
        _showModernSnackBar('Erro ao fechar mês: $e', isError: true);
      }
    }
  }

  Widget _buildSkeletonLoading() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: List.generate(4, (_) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 16,
                        width: 120,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 12,
                        width: 80,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              height: 12,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 12,
              width: 180,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return Scaffold(
        backgroundColor: _surfaceColor,
        body: _buildSkeletonLoading(),
      );
    }

    return Scaffold(
      backgroundColor: _surfaceColor,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            if (_isOffline)
              SliverToBoxAdapter(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  color: _warningColor.withOpacity(0.2),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.wifi_off, size: 18, color: _warningColor),
                      SizedBox(width: 8),
                      Text(
                        'Sem conexão - dados locais',
                        style: TextStyle(color: _warningColor, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            if (_ultimoErroSync != null && !_erroSyncDispensado)
              SliverToBoxAdapter(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  color: _errorColor.withOpacity(0.15),
                  child: Row(
                    children: [
                      const Icon(Icons.sync_problem, size: 18, color: _errorColor),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Falha ao sincronizar. Dados locais.',
                          style: TextStyle(color: _errorColor, fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => setState(() => _erroSyncDispensado = true),
                        color: _errorColor,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                    ],
                  ),
                ),
              ),
            SliverAppBar(
              expandedHeight: 140,
              floating: false,
              pinned: true,
              backgroundColor: _primaryColor,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [_primaryColor, _secondaryColor],
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        right: -50,
                        top: -50,
                        child: Container(
                          width: 200,
                          height: 200,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.1),
                          ),
                        ),
                      ),
                      Positioned(
                        left: -30,
                        bottom: -30,
                        child: Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.1),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 20,
                        right: 20,
                        bottom: 60,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Relatório Financeiro',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Lucro operacional de vendas = total − custo da mercadoria − taxas operacionais. '
                              'Taxas: config da loja ou valor já gravado na venda. Totais conforme período selecionado: cálculo ao vivo.',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicatorColor: Colors.white,
                    indicatorWeight: 3,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white70,
                    labelStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                    tabs: const [
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.analytics, size: 18),
                            SizedBox(width: 8),
                            Text('Resumo'),
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.calendar_month, size: 18),
                            SizedBox(width: 8),
                            Text('Fechamentos'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          body: TabBarView(
            controller: _tabController,
            children: [
              RefreshIndicator(
                onRefresh: () async {
                  _ultimoErroSync = null;
                  _erroSyncDispensado = false;
                  final connectivity = await Connectivity().checkConnectivity();
                  if (mounted) setState(() => _isOffline = connectivity.length == 1 && connectivity.first == ConnectivityResult.none);
                  if (!_isOffline) {
                    try {
                      await VendasFirestoreService.syncFirestoreToHive(lojaId: lojaId, vendasBox: vendasBox);
                    } catch (e) {
                      if (mounted) setState(() => _ultimoErroSync = e.toString());
                    }
                  }
                  if (mounted) setState(() {});
                },
                child: _buildResumoTab(),
              ),
              RefreshIndicator(
                onRefresh: () async {
                  _ultimoErroSync = null;
                  _erroSyncDispensado = false;
                  final connectivity = await Connectivity().checkConnectivity();
                  if (mounted) setState(() => _isOffline = connectivity.length == 1 && connectivity.first == ConnectivityResult.none);
                  if (!_isOffline) {
                    try {
                      await VendasFirestoreService.syncFirestoreToHive(lojaId: lojaId, vendasBox: vendasBox);
                    } catch (e) {
                      if (mounted) setState(() => _ultimoErroSync = e.toString());
                    }
                  }
                  if (mounted) setState(() {});
                },
                child: _buildFechamentosTab(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResumoTab() {
    final dia = _agregarPeriodo((v) => _isSameDay(v.data, hoje));
    final mes = _agregarPeriodo((v) => _isSameMonth(v.data, hoje));
    final ano = _agregarPeriodo((v) => _isSameYear(v.data, hoje));
    final mesAntCal = DateTime(hoje.year, hoje.month - 1);
    final mesAnterior =
        _resumoMesCalendarioPreferSnapshot(mesAntCal.year, mesAntCal.month);
    final mesPorForma = _pagamentosDoMesAtual();
    final temVendasDia = dia.venda > 0 || dia.custo > 0 || dia.taxas > 0;
    final temVendasMes = mes.venda > 0 || mes.custo > 0 || mes.taxas > 0;
    final temVendasAno = ano.venda > 0 || ano.custo > 0 || ano.taxas > 0;

    final periodoCustom = _periodoInicio != null && _periodoFim != null
        ? _agregarPeriodo((v) => !v.data.isBefore(_periodoInicio!) && !v.data.isAfter(_periodoFim!))
        : null;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Botões de ação
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _exportandoPdf ? null : _exportarPdf,
                icon: _exportandoPdf
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.picture_as_pdf, size: 18),
                label: Text(_exportandoPdf ? 'Exportando...' : 'Exportar PDF'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _primaryColor,
                  side: const BorderSide(color: _primaryColor),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _periodoInicio != null ? () => setState(() { _periodoInicio = null; _periodoFim = null; }) : _selecionarPeriodo,
                icon: Icon(_periodoInicio != null ? Icons.clear : Icons.date_range, size: 18),
                label: Text(_periodoInicio == null ? 'Período' : 'Limpar período'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _primaryColor,
                  side: const BorderSide(color: _primaryColor),
                ),
              ),
            ),
          ],
        ),
        if (_periodoInicio != null && _periodoFim != null) ...[
          const SizedBox(height: 12),
          _buildSectionTitle(
            Icons.date_range,
            'Período Customizado',
            subtitle:
                '${DateFormat('dd/MM/yyyy').format(_periodoInicio!)} - ${DateFormat('dd/MM/yyyy').format(_periodoFim!)} · cálculo ao vivo',
          ),
          const SizedBox(height: 12),
          periodoCustom != null && (periodoCustom.venda > 0 || periodoCustom.custo > 0)
              ? _buildResumoCard(
                  venda: periodoCustom.venda,
                  custo: periodoCustom.custo,
                  taxas: periodoCustom.taxas,
                  lucro: periodoCustom.lucro,
                  color: _primaryColor,
                  comparacao: null,
                  onTap: () => _mostrarDetalhesVendas((v) =>
                      !v.data.isBefore(_periodoInicio!) && !v.data.isAfter(_periodoFim!)),
                )
              : _buildEmptyPeriodCard('Nenhuma venda no período', _primaryColor),
          const SizedBox(height: 24),
        ],

        // Card de formas de pagamento do mês
        _buildSectionTitle(
          Icons.payment,
          'Formas de Pagamento',
          subtitle:
              '${DateFormat('MMMM yyyy', 'pt_BR').format(hoje)} · mês em aberto · ao vivo',
        ),
        const SizedBox(height: 12),
        _buildPaymentCard(mesPorForma),

        const SizedBox(height: 24),

        // Card do dia
        _buildSectionTitle(
          Icons.today,
          'Hoje',
          subtitle: '${DateFormat('dd/MM/yyyy').format(hoje)} · cálculo ao vivo',
        ),
        const SizedBox(height: 12),
        temVendasDia
            ? _buildResumoCard(
                venda: dia.venda,
                custo: dia.custo,
                taxas: dia.taxas,
                lucro: dia.lucro,
                color: _primaryColor,
                comparacao: null,
                onTap: () => _mostrarDetalhesVendas((v) => _isSameDay(v.data, hoje)),
              )
            : _buildEmptyPeriodCard('Nenhuma venda hoje', _primaryColor),

        const SizedBox(height: 24),

        // Card do mês
        _buildSectionTitle(
          Icons.calendar_today,
          'Este Mês',
          subtitle: 'Mês em aberto · valores sujeitos a atualização',
        ),
        const SizedBox(height: 12),
        temVendasMes
            ? _buildResumoCard(
                venda: mes.venda,
                custo: mes.custo,
                taxas: mes.taxas,
                lucro: mes.lucro,
                color: _secondaryColor,
                comparacao: mesAnterior.venda > 0 ? ((mes.venda - mesAnterior.venda) / mesAnterior.venda * 100) : null,
                onTap: () => _mostrarDetalhesVendas((v) => _isSameMonth(v.data, hoje)),
              )
            : _buildEmptyPeriodCard('Nenhuma venda este mês', _secondaryColor),

        const SizedBox(height: 24),

        // Card do ano
        _buildSectionTitle(
          Icons.calendar_month,
          'Este Ano',
          subtitle: 'Acumulado no ano · cálculo ao vivo',
        ),
        const SizedBox(height: 12),
        temVendasAno
            ? _buildResumoCard(
                venda: ano.venda,
                custo: ano.custo,
                taxas: ano.taxas,
                lucro: ano.lucro,
                color: _successColor,
                comparacao: null,
                onTap: () => _mostrarDetalhesVendas((v) => _isSameYear(v.data, hoje)),
              )
            : _buildEmptyPeriodCard('Nenhuma venda este ano', _successColor),

        const SizedBox(height: 24),
        _buildLancamentosFinanceirosSection(),

        SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
      ],
    );
  }

  List<LancamentoFinanceiro> _lancamentosMesAtualOrdenados() {
    final box = _lancamentosFinanceiroBox;
    if (box == null || lojaId.isEmpty) return [];
    final list = FinanceiroLancamentoExclusaoService.lancamentosRelatorioMesAtual(
      box: box,
      lojaId: lojaId,
      referencia: hoje,
    )..sort(
        (a, b) => b.dataEfetivaPagamentoOuLancamento
            .compareTo(a.dataEfetivaPagamentoOuLancamento),
      );
    return list;
  }

  Future<void> _recarregarLancamentosFinanceiros() async {
    _lancamentosFinanceiroBox =
        await FinanceiroHiveStore.openLancamentosBox(lojaId);
    try {
      final crBox = await ContaReceberService.openBoxLoja(lojaId);
      _contasReceberCache = crBox.values.toList();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _confirmarAcaoLancamento(LancamentoFinanceiro l) async {
    debugPrint(
      '[FIN-UI][ACAO-CLICK] id=${l.id} key=${l.key} origem=${l.origem} '
      'ref=${l.referenciaExterna} desc=${l.descricao}',
    );

    Iterable<ContaReceber> contasCr = _contasReceberCache;
    if (contasCr.isEmpty) {
      try {
        final crBox = await ContaReceberService.openBoxLoja(lojaId);
        contasCr = crBox.values;
        _contasReceberCache = crBox.values.toList();
      } catch (_) {}
    }

    final acao = FinanceiroLancamentoExclusaoService.acaoParaUi(
      l,
      contas: contasCr,
      lojaId: lojaId,
      lancamentosLoja: _lancamentosFinanceiroBox?.values ?? const [],
    );

    if (acao.mostrarExcluirDuplicado) {
      if (!mounted) return;
      final okDup = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Excluir lançamento duplicado?'),
          content: SingleChildScrollView(
            child: Text(
              FinanceiroLancamentoExclusaoService.msgModalExcluirDuplicadoBaixaCr,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _errorColor),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Excluir duplicado'),
            ),
          ],
        ),
      );
      if (okDup != true || !mounted) return;

      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Processando...'),
                ],
              ),
            ),
          ),
        ),
      );

      FinanceiroLancamentoExclusaoResultado resultado;
      try {
        resultado = await FinanceiroLancamentoExclusaoService
            .excluirLancamentoFinanceiroDuplicadoDeBaixa(
          lojaId: lojaId,
          lancamento: l,
          lancamentosLoja: _lancamentosFinanceiroBox?.values,
        );
      } catch (e, st) {
        debugPrint('[FIN-UI][RESULTADO] exceção dup id=${l.id} $e\n$st');
        resultado = FinanceiroLancamentoExclusaoResultado(
          sucesso: false,
          mensagemErro: 'Erro inesperado: $e',
        );
      }

      await _recarregarLancamentosFinanceiros();
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _showModernSnackBar(
        resultado.sucesso
            ? FinanceiroLancamentoExclusaoService.msgSucessoExcluirDuplicado
            : (resultado.mensagemErro ?? 'Não foi possível excluir.'),
        isError: !resultado.sucesso,
      );
      return;
    }

    final info = FinanceiroLancamentoExclusaoService.infoLegado(
      l,
      contas: contasCr,
      lojaId: lojaId,
    );
    final ehBaixaCr = info.ehBaixaCr;
    final chipOrigem = chipOrigemAutomaticaLancamento(l);

    String titulo;
    String corpo;
    final semVinculoCr = ehBaixaCr && !info.vinculoCrSeguro;
    if (semVinculoCr) {
      titulo = 'Estorno não disponível';
      corpo = FinanceiroLancamentoExclusaoService.msgModalExcluirSomenteFinanceiroCr;
    } else if (ehBaixaCr && info.legado) {
      titulo = 'Estornar baixa antiga?';
      corpo =
          'Deseja estornar esta baixa antiga?\n'
          'A parcela vinculada será reaberta com o saldo atualizado.';
    } else if (ehBaixaCr) {
      titulo = 'Estornar baixa?';
      corpo =
          'Deseja estornar esta baixa?\n'
          'O lançamento financeiro será estornado e a parcela em Contas a Receber voltará a ficar em aberto com o saldo atualizado.';
    } else if (info.legado) {
      titulo = 'Excluir lançamento antigo?';
      corpo =
          'Deseja excluir este lançamento financeiro antigo?\n'
          'Ele será removido da listagem por exclusão segura, sem afetar vendas, estoque ou contas a receber.';
    } else {
      titulo = 'Excluir lançamento?';
      corpo =
          'Deseja excluir este lançamento financeiro?\n'
          'Essa ação removerá o lançamento dos relatórios, mas manterá o registro interno de auditoria.';
    }

    if (semVinculoCr) {
      if (!mounted) return;
      final okExcluir = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(titulo),
          content: SingleChildScrollView(child: Text(corpo)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _errorColor),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Excluir somente lançamento'),
            ),
          ],
        ),
      );
      if (okExcluir != true || !mounted) return;

      debugPrint('[FIN-UI][CONFIRMOU] id=${l.id} financeiro-only');

      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Processando...'),
                ],
              ),
            ),
          ),
        ),
      );

      FinanceiroLancamentoExclusaoResultado resultado;
      try {
        resultado =
            await FinanceiroLancamentoExclusaoService
                .excluirSomenteLancamentoFinanceiroLegado(
          lojaId: lojaId,
          lancamento: l,
        );
      } catch (e, st) {
        debugPrint('[FIN-UI][RESULTADO] exceção id=${l.id} $e\n$st');
        resultado = FinanceiroLancamentoExclusaoResultado(
          sucesso: false,
          mensagemErro: 'Erro inesperado: $e',
        );
      }

      await _recarregarLancamentosFinanceiros();
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _showModernSnackBar(
        resultado.sucesso
            ? FinanceiroLancamentoExclusaoService.msgSucessoExcluirSomenteFinanceiro
            : (resultado.mensagemErro ?? 'Não foi possível excluir.'),
        isError: !resultado.sucesso,
      );
      return;
    }

    if (!mounted) return;
    final df = DateFormat('dd/MM/yyyy');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(corpo),
              const SizedBox(height: 12),
              Text('Data: ${df.format(l.dataEfetivaPagamentoOuLancamento)}'),
              Text('Descrição: ${l.descricao.isEmpty ? '(sem descrição)' : l.descricao}'),
              Text('Valor: R\$ ${_fmt(l.valor)}'),
              if (l.formaPagamento.trim().isNotEmpty)
                Text('Forma: ${l.formaPagamento}'),
              if (chipOrigem != null) Text('Origem: $chipOrigem'),
              const SizedBox(height: 12),
              TextField(
                key: ValueKey('motivo_${l.id}_${l.key}'),
                onChanged: (v) => _motivoAcaoLancamento = v,
                decoration: InputDecoration(
                  labelText: ehBaixaCr ? 'Motivo do estorno (opcional)' : 'Motivo (opcional)',
                  border: const OutlineInputBorder(),
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
            style: FilledButton.styleFrom(
              backgroundColor: ehBaixaCr ? _warningColor : _errorColor,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ehBaixaCr ? 'Estornar baixa' : 'Excluir'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    debugPrint(
      '[FIN-UI][CONFIRMOU] id=${l.id} key=${l.key} baixaCr=$ehBaixaCr',
    );

    final motivo = _motivoAcaoLancamento.trim();
    _motivoAcaoLancamento = '';

    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Processando...'),
              ],
            ),
          ),
        ),
      ),
    );

    FinanceiroLancamentoExclusaoResultado resultado;
    try {
      resultado = ehBaixaCr
          ? await FinanceiroLancamentoExclusaoService.estornarBaixaContaReceber(
              lojaId: lojaId,
              lancamento: l,
              motivoEstorno: motivo,
            )
          : await FinanceiroLancamentoExclusaoService.excluirLancamentoManual(
              lojaId: lojaId,
              lancamento: l,
              motivoExclusao: motivo,
            );
    } catch (e, st) {
      debugPrint('[FIN-UI][RESULTADO] exceção id=${l.id} $e\n$st');
      resultado = FinanceiroLancamentoExclusaoResultado(
        sucesso: false,
        mensagemErro: 'Erro inesperado: $e',
      );
    }

    debugPrint(
      '[FIN-UI][RESULTADO] id=${l.id} sucesso=${resultado.sucesso} '
      'bloqueado=${resultado.bloqueado} legado=${resultado.legado} '
      'erro=${resultado.mensagemErro}',
    );

    await _recarregarLancamentosFinanceiros();
    final restantes = _lancamentosMesAtualOrdenados().length;
    debugPrint('[FIN-UI][REFRESH-LISTA] itens=$restantes');

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    String mensagem;
    var isError = !resultado.sucesso;
    if (resultado.sucesso) {
      mensagem = ehBaixaCr
          ? 'Baixa estornada. A parcela foi reaberta.'
          : (resultado.apenasLocal
              ? 'Lançamento excluído localmente.'
              : 'Lançamento excluído dos relatórios.');
      isError = false;
    } else if (resultado.bloqueado) {
      mensagem = resultado.mensagemErro ??
          FinanceiroLancamentoLegacyResolver.msgEstornoLegadoSemVinculo;
      isError = true;
    } else {
      mensagem = resultado.mensagemErro ?? 'Não foi possível concluir a operação.';
    }
    _showModernSnackBar(mensagem, isError: isError);
  }

  Widget _buildLancamentosFinanceirosSection() {
    final lancamentos = _lancamentosMesAtualOrdenados();
    final df = DateFormat('dd/MM/yyyy');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(
          Icons.receipt_long,
          'Lançamentos financeiros',
          subtitle:
              '${DateFormat('MMMM yyyy', 'pt_BR').format(hoje)} · toque no ícone para excluir ou estornar',
        ),
        const SizedBox(height: 12),
        if (lancamentos.isEmpty)
          _buildEmptyPeriodCard(
            'Nenhum lançamento manual ou de baixa neste mês',
            _primaryColor,
          )
        else
          ...lancamentos.map((l) {
            final acao = FinanceiroLancamentoExclusaoService.acaoParaUi(
              l,
              contas: _contasReceberCache,
              lojaId: lojaId,
              lancamentosLoja: _lancamentosFinanceiroBox?.values ?? const [],
            );
            final ehBaixaCr = acao.ehBaixaCr;
            final chipOrigem = chipOrigemAutomaticaLancamento(l);
            final excluirDuplicado = acao.mostrarExcluirDuplicado;
            final excluirSomenteFinanceiro = acao.mostrarExcluirSomenteFinanceiro;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ListTile(
                title: Text(
                  l.descricao.isEmpty ? '(sem descrição)' : l.descricao,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (chipOrigem != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Chip(
                          label: Text(chipOrigem, style: const TextStyle(fontSize: 10)),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    Text(
                      '${FinanceiroTipoLancamento.legivel(l.tipo)} · ${df.format(l.dataEfetivaPagamentoOuLancamento)}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'R\$ ${_fmt(l.valor)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: excluirDuplicado
                          ? 'Excluir lançamento duplicado'
                          : (excluirSomenteFinanceiro
                              ? 'Excluir somente lançamento'
                              : (ehBaixaCr ? 'Estornar baixa' : 'Excluir')),
                      icon: Icon(
                        excluirDuplicado
                            ? Icons.delete_outline
                            : (excluirSomenteFinanceiro
                                ? Icons.delete_outline
                                : (ehBaixaCr ? Icons.undo : Icons.delete_outline)),
                        color: excluirDuplicado || excluirSomenteFinanceiro
                            ? _errorColor
                            : (ehBaixaCr ? _warningColor : _errorColor),
                      ),
                      onPressed: () => _confirmarAcaoLancamento(l),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildEmptyPeriodCard(String message, Color color) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.inbox_outlined, size: 40, color: color.withOpacity(0.5)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(IconData icon, String title, {String? subtitle}) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: _primaryColor, size: 20),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildPaymentCard(({double dinheiro, double pix, double cartao}) data) {
    final total = data.dinheiro + data.pix + data.cartao;
    final hasData = total > 0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          if (hasData) ...[
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: SizedBox(
                height: 120,
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 28,
                    sections: [
                      if (data.dinheiro > 0)
                        PieChartSectionData(
                          value: data.dinheiro,
                          title: '${(data.dinheiro / total * 100).toStringAsFixed(0)}%',
                          color: _successColor,
                          radius: 32,
                          titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      if (data.pix > 0)
                        PieChartSectionData(
                          value: data.pix,
                          title: '${(data.pix / total * 100).toStringAsFixed(0)}%',
                          color: const Color(0xFF00D1A8),
                          radius: 32,
                          titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      if (data.cartao > 0)
                        PieChartSectionData(
                          value: data.cartao,
                          title: '${(data.cartao / total * 100).toStringAsFixed(0)}%',
                          color: _primaryColor,
                          radius: 32,
                          titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          _buildPaymentRow(
            icon: Icons.attach_money,
            label: 'Dinheiro',
            value: data.dinheiro,
            color: _successColor,
            total: total,
          ),
          Divider(height: 1, color: Colors.grey.shade200),
          _buildPaymentRow(
            icon: Icons.pix,
            label: 'Pix',
            value: data.pix,
            color: const Color(0xFF00D1A8),
            total: total,
          ),
          Divider(height: 1, color: Colors.grey.shade200),
          _buildPaymentRow(
            icon: Icons.credit_card,
            label: 'Cartão',
            value: data.cartao,
            color: _primaryColor,
            total: total,
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _primaryColor.withOpacity(0.05),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total Recebido',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  'R\$ ${_fmt(total)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: _primaryColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentRow({
    required IconData icon,
    required String label,
    required double value,
    required Color color,
    required double total,
  }) {
    final percentage = total > 0 ? (value / total * 100) : 0.0;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: percentage / 100,
                    backgroundColor: Colors.grey.shade200,
                    color: color,
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'R\$ ${_fmt(value)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              Text(
                '${percentage.toStringAsFixed(1)}%',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResumoCard({
    required double venda,
    required double custo,
    required double taxas,
    required double lucro,
    required Color color,
    double? comparacao,
    VoidCallback? onTap,
  }) {
    final margem = venda > 0 ? (lucro / venda * 100) : 0.0;
    final child = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header com total de vendas
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.shopping_cart, color: color, size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Total Vendas',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                Text(
                  'R\$ ${_fmt(venda)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: color,
                  ),
                ),
              ],
            ),
          ),

          // Detalhes
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildDetailRow('Custo da mercadoria', custo, Icons.inventory_2, Colors.grey.shade700),
                const SizedBox(height: 12),
                _buildDetailRow('Taxas operacionais (config/gravadas)', taxas, Icons.receipt_long, _warningColor),
              ],
            ),
          ),

          // Lucro + Margem
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: lucro >= 0 ? _successColor.withOpacity(0.1) : _errorColor.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          lucro >= 0 ? Icons.trending_up : Icons.trending_down,
                          color: lucro >= 0 ? _successColor : _errorColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Lucro operacional de vendas',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: lucro >= 0 ? _successColor : _errorColor,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'R\$ ${_fmt(lucro)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                        color: lucro >= 0 ? _successColor : _errorColor,
                      ),
                    ),
                  ],
                ),
                if (venda > 0) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Margem sobre vendas',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                      Text(
                        '${margem.toStringAsFixed(1)}%',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
                      ),
                    ],
                  ),
                ],
                if (comparacao != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        comparacao >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                        size: 14,
                        color: comparacao >= 0 ? _successColor : _errorColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${comparacao >= 0 ? '+' : ''}${comparacao.toStringAsFixed(1)}% vs mês anterior',
                        style: TextStyle(
                          fontSize: 12,
                          color: comparacao >= 0 ? _successColor : _errorColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: child,
      ),
    );
  }

  Widget _buildDetailRow(String label, double value, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ),
        Text(
          'R\$ ${_fmt(value)}',
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildFechamentosTab() {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Container(
            padding: const EdgeInsets.all(16),
            child: Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _filtroFechController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Pesquisar (MM/AAAA)',
                      prefixIcon: const Icon(Icons.search, color: _primaryColor),
                      suffixIcon: _filtroFechController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: () {
                                _filtroFechController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: _ordenacaoFech,
                isExpanded: false,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 'recente', child: Text('Mais recentes')),
                  DropdownMenuItem(value: 'antigo', child: Text('Mais antigos')),
                  DropdownMenuItem(value: 'valor_maior', child: Text('Maior valor')),
                  DropdownMenuItem(value: 'valor_menor', child: Text('Menor valor')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _ordenacaoFech = v);
                },
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _fechandoMes ? null : _fecharMesAtual,
                icon: _fechandoMes
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.refresh, size: 20),
                label: Text(_fechandoMes ? 'Fechando...' : 'Fechar Mês'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _successColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
        ),

        // Lista de fechamentos
        if (_fechamentosFiltrados.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: _primaryColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.calendar_month,
                      size: 64,
                      color: _primaryColor,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Nenhum fechamento encontrado',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Clique em "Fechar Mês" para gerar',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => _buildFechamentoCard(_fechamentosFiltrados[i]),
                childCount: _fechamentosFiltrados.length,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFechamentoCard(FechamentoMensal f) {
    final rotulo = DateFormat('MMMM yyyy', 'pt_BR').format(DateTime(f.ano, f.mes));

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_primaryColor.withOpacity(0.1), _secondaryColor.withOpacity(0.05)],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _primaryColor.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.calendar_today, color: _primaryColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rotulo.substring(0, 1).toUpperCase() + rotulo.substring(1),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Fechado em ${DateFormat('dd/MM/yyyy HH:mm').format(f.fechadoEm)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      if (FechamentoService.mesEhAnteriorAoCorrente(f.ano, f.mes))
                        Text(
                          'Snapshot histórico · fechamento salvo · valores preservados.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.teal.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        )
                      else
                        Text(
                          'Mês em aberto · cálculo ao vivo ao abrir (vendas + taxas operacionais: config ou gravadas).',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blueGrey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Valores
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _buildValueTile('Vendas', f.vendaTotal, _primaryColor)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildValueTile('Custo', f.custoTotal, Colors.grey.shade700)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _buildValueTile('Taxas operacionais', f.taxasTotal, _warningColor)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _buildValueTile(
                            'Lucro operacional de vendas', f.lucroTotal, _successColor,
                            isHighlight: true)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  FechamentoService.mesEhAnteriorAoCorrente(f.ano, f.mes)
                      ? 'Lucro operacional = snapshot do fechamento (totais na gravação do mês).'
                      : 'Lucro operacional ao vivo: total − custo da mercadoria − taxas (config da loja ou valor gravado na venda).',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),

          _buildComplementoModuloFinanceiro(f),

          // Formas de pagamento
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: _surfaceColor,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildPaymentChip(Icons.attach_money, 'Dinheiro', f.totalDinheiro),
                _buildPaymentChip(Icons.pix, 'Pix', f.totalPix),
                _buildPaymentChip(Icons.credit_card, 'Cartão', f.totalCartao),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Complemento opcional: nao altera [FechamentoMensal] persistido; so exibicao.
  Widget _buildComplementoModuloFinanceiro(FechamentoMensal f) {
    final box = _lancamentosFinanceiroBox;
    if (box == null) return const SizedBox.shrink();
    final r = FinanceiroService.resumoMesCalendario(
      box: box,
      lojaId: lojaId,
      ano: f.ano,
      mes: f.mes,
    );
    if (!r.temAlgumDado) return const SizedBox.shrink();

    final resultadoGerencial = FinanceiroService.resultadoGerencialComModulo(
      lucroOperacionalVendas: f.lucroTotal,
      modulo: r,
    );
    final fluxoCaixa = FinanceiroService.fluxoCaixaComVendas(
      somaFormasPagamentoVendas: f.totalDinheiro + f.totalPix + f.totalCartao,
      modulo: r,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.indigo.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.indigo.shade100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_balance_wallet_outlined,
                    size: 18, color: Colors.indigo.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Complemento gerencial · módulo financeiro',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: Colors.indigo.shade900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Gastos fixos: R\$ ${_fmt(r.totalGastosFixos)} · '
              'variáveis: R\$ ${_fmt(r.totalGastosVariaveis)} · '
              'legado: R\$ ${_fmt(r.totalDespesasOperacionais)} · '
              'Compras mercadoria: R\$ ${_fmt(r.totalCompraMercadoria)} · '
              'Investimentos: R\$ ${_fmt(r.totalInvestimentos)} · '
              'Retiradas: R\$ ${_fmt(r.totalRetiradas)} · '
              'Equipe/pró-labore: R\$ ${_fmt(r.totalPagamentosEquipe)}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade800),
            ),
            if (r.totalEntradasExtras.abs() > 1e-9 || r.totalAjustes.abs() > 1e-9) ...[
              const SizedBox(height: 4),
              Text(
                'Entradas extras: R\$ ${_fmt(r.totalEntradasExtras)} · '
                'Ajustes: R\$ ${_fmt(r.totalAjustes)}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade800),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Lucro operacional de vendas: R\$ ${_fmt(f.lucroTotal)} · '
              'Resultado gerencial: R\$ ${_fmt(resultadoGerencial)} · '
              'Fluxo de caixa (formas + módulo): R\$ ${_fmt(fluxoCaixa)}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.indigo.shade800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Resultado gerencial = lucro de vendas − despesas operacionais e equipe + ajustes; '
              'compra de mercadoria e investimento/retirada não duplicam CMV nem misturam com lucro de venda. '
              'Fluxo de caixa inclui todas as saídas pagas (compra, invest., retirada, etc.). '
              'Evite lançar a mesma despesa que já está nas taxas de venda.',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildValueTile(String label, double value, Color color, {bool isHighlight = false}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isHighlight ? color.withOpacity(0.1) : _surfaceColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'R\$ ${_fmt(value)}',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isHighlight ? color : Colors.grey.shade800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentChip(IconData icon, String label, double value) {
    return Column(
      children: [
        Icon(icon, size: 20, color: _primaryColor),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
        ),
        Text(
          'R\$ ${_fmt(value)}',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

