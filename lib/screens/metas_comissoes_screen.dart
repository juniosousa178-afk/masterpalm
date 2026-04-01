// lib/screens/metas_comissoes_screen.dart
// Tela de Metas e Comissões para vendedores e admin

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/comissao_config.dart';
import '../models/meta.dart';
import '../models/venda_tracking.dart';
import '../services/store_resolver_facade.dart';
import '../services/comissao_service.dart';
import '../services/comissao_config_service.dart';
import '../services/meta_firestore_service.dart';
import '../widgets/compartilhar_catalogo_widget.dart';
import '../utils/responsive.dart';
import '../services/ai_loja_service.dart';
import '../services/ia_uso_limite_service.dart';
import '../services/public_store_link_helper.dart';
import '../services/loja_id_service.dart';
import '../services/financeiro_hive_store.dart';
import '../services/financeiro_service.dart';

class MetasComissoesScreen extends StatefulWidget {
  const MetasComissoesScreen({super.key});

  @override
  State<MetasComissoesScreen> createState() => _MetasComissoesScreenState();
}

class _MetasComissoesScreenState extends State<MetasComissoesScreen>
    with SingleTickerProviderStateMixin {
  // Cores do tema (padrão do app)
  static const _primaryColor = Color(0xFF00A8FF);
  static const _bgColor = Color(0xFF0A0A0F);
  static const _cardColor = Color(0xFF12121A);
  static const _successColor = Color(0xFF4ADE80);
  static const _warningColor = Color(0xFFFBBF24);
  static const _dangerColor = Color(0xFFEF4444);

  late TabController _tabController;

  String? _lojaId;
  String _usuarioLogado = '';
  bool _isAdmin = false;
  bool _carregando = true;
  String? _erro;

  // Metas (vendedor)
  Meta? _metaAtual;
  Box<Meta>? _metasBox;

  // Período selecionado
  DateTime _inicioMes = DateTime.now();
  DateTime _fimMes = DateTime.now();
  String _periodoSelecionado = 'mes';

  // Dados
  ComissaoConfig? _config;
  List<ResumoComissaoVendedor> _resumosVendedores = [];
  ResumoComissaoVendedor? _meuResumo;
  List<ComissaoVenda> _minhasComissoes = [];

  /// Complemento informativo (admin): lancamentos do modulo financeiro no periodo.
  ResumoFinanceiroModulo? _moduloFinanceiroComplemento;

  // UI
  final _formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _trackingDiasController = TextEditingController(text: '7');
  final _buscaVendedorController = TextEditingController();
  bool _isOffline = false;
  bool _salvando = false;
  bool _sincronizando = false;
  String _ordenacaoVendedores = 'vendas';
  bool _ordenacaoDescendente = true;
  String _buscaVendedor = '';
  String _filtroStatusComissao = 'todas'; // todas | pendentes | pagas | estornadas
  String? _erroTrackingDias;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _buscaVendedorController.addListener(() => setState(() {
      _buscaVendedor = _buscaVendedorController.text;
    }));
    Connectivity().onConnectivityChanged.listen((r) {
      if (mounted) setState(() => _isOffline = r.length == 1 && r.first == ConnectivityResult.none);
    });
    _definirPeriodo('mes');
  }

  @override
  void dispose() {
    _trackingDiasController.dispose();
    _buscaVendedorController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _definirPeriodo(String periodo) {
    final agora = DateTime.now();
    setState(() {
      _periodoSelecionado = periodo;
      switch (periodo) {
        case 'hoje':
          _inicioMes = DateTime(agora.year, agora.month, agora.day);
          _fimMes = DateTime(agora.year, agora.month, agora.day, 23, 59, 59);
          break;
        case 'semana':
          final inicioSemana = agora.subtract(Duration(days: agora.weekday - 1));
          _inicioMes = DateTime(inicioSemana.year, inicioSemana.month, inicioSemana.day);
          _fimMes = _inicioMes.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));
          break;
        case 'mes':
        default:
          _inicioMes = DateTime(agora.year, agora.month, 1);
          _fimMes = DateTime(agora.year, agora.month + 1, 0, 23, 59, 59);
          break;
      }
    });
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      // Resolver loja
      _lojaId = await StoreResolverFacade.resolveForAdminApp();
      if (_lojaId == null) {
        throw Exception('Loja não encontrada');
      }

      // Buscar usuário atual
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('Usuário não autenticado');
      }

      // Buscar dados do usuário
      final sessaoBox = await Hive.openBox('sessao');
      final tipoUsuario = sessaoBox.get('tipo_usuario') as String? ?? 'vendedor';
      _usuarioLogado = (sessaoBox.get('usuario_logado') ?? '').toString().trim().toLowerCase();
      _isAdmin = tipoUsuario == 'admin' || tipoUsuario == 'programador';

      // Buscar metas (vendedor): abrir box e sincronizar do Firestore para aparecer em qualquer dispositivo
      if (!_isAdmin) {
        try {
          _metasBox = await Hive.openBox<Meta>('metas_$_lojaId');
          final metasRemotas = await MetaFirestoreService.getMetas(lojaId: _lojaId!);
          for (final meta in metasRemotas) {
            final key = meta.hiveKey;
            final local = _metasBox!.get(key);
            if (local == null || (meta.atualizadoEm.isAfter(local.atualizadoEm))) {
              await _metasBox!.put(key, meta);
            }
          }
          final mesRef = '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';
          _metaAtual = _metasBox!.get('${mesRef}_$_usuarioLogado') ?? _metasBox!.get('${mesRef}_GERAL');
        } catch (_) {
          _metaAtual = null;
        }
      }

      // Buscar configuração (com fallback para padrão)
      _config = await ComissaoConfigService.getConfig(_lojaId!);
      _config ??= ComissaoConfig(lojaId: _lojaId!);
      _trackingDiasController.text = '${_config!.trackingExpiracaoDias}';
      _erroTrackingDias = null;

      final connectivity = await Connectivity().checkConnectivity();
      if (mounted) setState(() => _isOffline = connectivity.length == 1 && connectivity.first == ConnectivityResult.none);

      if (_isAdmin) {
        // Admin: buscar resumo de todos os vendedores
        _resumosVendedores = await ComissaoService.calcularResumoTodosVendedores(
          lojaId: _lojaId!,
          inicio: _inicioMes,
          fim: _fimMes,
        );
      } else {
        // Vendedor: buscar apenas seus dados
        _meuResumo = await ComissaoService.calcularResumoVendedor(
          lojaId: _lojaId!,
          vendedorUid: user.uid,
          inicio: _inicioMes,
          fim: _fimMes,
        );

        _minhasComissoes = await ComissaoService.listarComissoesVendedor(
          lojaId: _lojaId!,
          vendedorUid: user.uid,
          inicio: _inicioMes,
          fim: _fimMes,
        );
      }

      _moduloFinanceiroComplemento = null;
      if (_isAdmin) {
        final box = await FinanceiroHiveStore.openLancamentosBox(_lojaId!);
        if (box != null) {
          _moduloFinanceiroComplemento = FinanceiroService.resumoPeriodo(
            box: box,
            lojaId: _lojaId!,
            inicio: _inicioMes,
            fim: _fimMes,
          );
        }
      }

      setState(() => _carregando = false);
    } catch (e) {
      debugPrint('❌ [COMISSOES] Erro (type=${e.runtimeType})');
      setState(() {
        _carregando = false;
        _erro = e.toString();
      });
    }
  }

  void _abrirSugestoesIa() {
    final meta = _metaAtual?.metaMensal ?? 0;
    final realizado = _meuResumo?.totalVendas ?? 0;
    final falta = (meta - realizado).clamp(0.0, double.infinity);
    final periodo = '${_inicioMes.day}/${_inicioMes.month}/${_inicioMes.year} a ${_fimMes.day}/${_fimMes.month}/${_fimMes.year}';
    final resumo = 'Período: $periodo. Meta do mês: ${_formatoMoeda.format(meta)}. '
        'Realizado (vendas): ${_formatoMoeda.format(realizado)}. '
        'Falta para bater a meta: ${_formatoMoeda.format(falta)}.';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => _SugestoesIaMetasScreen(resumoInicial: resumo),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _cardColor,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Metas & Comissões'),
            Text(
              _getPeriodoTexto(),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        bottom: _isAdmin
            ? TabBar(
                controller: _tabController,
                indicatorColor: _primaryColor,
                labelColor: _primaryColor,
                unselectedLabelColor: Colors.grey,
                tabs: const [
                  Tab(text: 'Visão Geral', icon: Icon(Icons.dashboard)),
                  Tab(text: 'Configurações', icon: Icon(Icons.settings)),
                ],
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            onPressed: _carregando ? null : _abrirSugestoesIa,
            tooltip: 'Sugestões com IA',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _carregando ? null : _carregarDados,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isOffline && !_carregando)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              color: _warningColor.withValues(alpha:0.2),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.wifi_off, size: 18, color: _warningColor),
                  SizedBox(width: 8),
                  Text('Sem conexão', style: TextStyle(color: _warningColor, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
                child: _carregando
                    ? _buildSkeletonLoading()
                    : _erro != null
                        ? _buildErroWidget()
                        : _isAdmin
                            ? TabBarView(
                                controller: _tabController,
                                children: [
                                  _buildVisaoGeralAdmin(),
                                  _buildConfiguracoes(),
                                ],
                              )
                            : _buildVisaoVendedor(),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'fab_ia_metas',
            onPressed: _abrirSugestoesIa,
            tooltip: 'Sugestões com IA (meta, vendas)',
            backgroundColor: Colors.amber,
            mini: true,
            child: const Icon(Icons.auto_awesome, color: Colors.black87),
          ),
          if (!_isAdmin) ...[
            const SizedBox(height: 12),
            FloatingActionButton.extended(
              heroTag: 'fab_compartilhar_metas',
              onPressed: () => CompartilharCatalogoDialog.show(context),
              icon: const Icon(Icons.share),
              label: const Text('Enviar Catálogo'),
              backgroundColor: const Color(0xFF25D366),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPeriodoChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('Hoje'),
            selected: _periodoSelecionado == 'hoje',
            onSelected: (_) => _definirPeriodo('hoje'),
            selectedColor: _primaryColor.withValues(alpha:0.3),
            labelStyle: TextStyle(color: _periodoSelecionado == 'hoje' ? _primaryColor : Colors.white),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('Semana'),
            selected: _periodoSelecionado == 'semana',
            onSelected: (_) => _definirPeriodo('semana'),
            selectedColor: _primaryColor.withValues(alpha:0.3),
            labelStyle: TextStyle(color: _periodoSelecionado == 'semana' ? _primaryColor : Colors.white),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('Mês'),
            selected: _periodoSelecionado == 'mes',
            onSelected: (_) => _definirPeriodo('mes'),
            selectedColor: _primaryColor.withValues(alpha:0.3),
            labelStyle: TextStyle(color: _periodoSelecionado == 'mes' ? _primaryColor : Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonLoading() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: List.generate(4, (_) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        height: 100,
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.withValues(alpha:0.1)),
        ),
      )),
    );
  }

  Widget _buildErroWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: _dangerColor),
            const SizedBox(height: 16),
            Text(
              'Erro ao carregar dados',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade300),
            ),
            const SizedBox(height: 8),
            Text(
              _erro ?? 'Erro desconhecido',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade500),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _carregarDados,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // VISÃO DO VENDEDOR

  Widget _buildLinkIndicacaoCard() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final baseUrl = buildPublicCatalogUrl(_lojaId);
    if (baseUrl == null || uid == null) return const SizedBox.shrink();
    final link = '$baseUrl?ref=$uid';
    return _buildCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.link, color: _primaryColor, size: 20),
                SizedBox(width: 8),
                Text('Seu link de indicação', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Compartilhe este link. Pedidos feitos por quem acessar serão atribuídos a você.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(link, style: TextStyle(fontSize: 12, color: Colors.grey.shade300)),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: link));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Link copiado!'), duration: Duration(seconds: 2)),
                  );
                },
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copiar link'),
                style: OutlinedButton.styleFrom(foregroundColor: _primaryColor, side: const BorderSide(color: _primaryColor)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================

  Widget _buildVisaoVendedor() {
    return RefreshIndicator(
      onRefresh: _carregarDados,
      color: _primaryColor,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPeriodoChips(),
            const SizedBox(height: 16),
            const CompartilharCatalogoButton(expandido: true),
            const SizedBox(height: 16),
            _buildLinkIndicacaoCard(),
            const SizedBox(height: 16),
            if (_metaAtual != null && _metaAtual!.metaMensal > 0 && _periodoSelecionado == 'mes')
              _buildMetaCard(),
            if (_metaAtual != null && _metaAtual!.metaMensal > 0 && _periodoSelecionado == 'mes')
              const SizedBox(height: 16),
            _buildResumoCard(),
            const SizedBox(height: 16),

            // Filtro por status
            _buildFiltroStatusChips(),
            const SizedBox(height: 12),

            // Lista de comissões
            _buildListaComissoes(),
          ],
        ),
      ),
    );
  }

  Widget _buildMetaCard() {
    final meta = _metaAtual!.metaMensal;
    final realizado = _meuResumo?.totalVendas ?? 0;
    final percentual = meta > 0 ? (realizado / meta * 100).clamp(0.0, 200.0) : 0.0;

    return _buildCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.flag, color: _primaryColor, size: 20),
                    SizedBox(width: 8),
                    Text('Meta do Mês', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
                Text(
                  '${percentual.toStringAsFixed(0)}%',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: percentual >= 100 ? _successColor : _warningColor),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: (percentual / 100).clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: Colors.grey.shade800,
                color: percentual >= 100 ? _successColor : _primaryColor,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Realizado: ${_formatoMoeda.format(realizado)}', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                Text('Meta: ${_formatoMoeda.format(meta)}', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResumoCard() {
    final resumo = _meuResumo;
    if (resumo == null) {
      return _buildCard(
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Sem dados para o período selecionado', style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    return _buildCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Seu Resumo',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: _primaryColor.withValues(alpha:0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(_getPeriodoTexto(), style: const TextStyle(color: _primaryColor, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Grid de métricas
            Row(
              children: [
                Expanded(child: _buildMetricaCard('Total Vendido', _formatoMoeda.format(resumo.totalVendas), Icons.shopping_cart, _primaryColor)),
                const SizedBox(width: 12),
                Expanded(child: _buildMetricaCard('Vendas', '${resumo.qtdVendas}', Icons.receipt, _successColor)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildMetricaCard('Comissão a Receber', _formatoMoeda.format(resumo.comissaoAAReceber), Icons.payments, _warningColor)),
                const SizedBox(width: 12),
                Expanded(child: _buildMetricaCard('Vendas Catálogo', '${resumo.qtdVendasCatalogo}', Icons.link, Colors.purple)),
              ],
            ),

            if (resumo.totalComissoesPagas > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _successColor.withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _successColor.withValues(alpha:0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: _successColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Comissões pagas: ${_formatoMoeda.format(resumo.totalComissoesPagas)}',
                        style: const TextStyle(color: _successColor),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha:0.1)),
      ),
      child: child,
    );
  }

  Widget _buildMetricaCard(String titulo, String valor, IconData icone, Color cor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cor.withValues(alpha:0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cor.withValues(alpha:0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icone, size: 16, color: cor),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  titulo,
                  style: TextStyle(fontSize: 11, color: cor),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            valor,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cor),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltroStatusChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('Todas'),
            selected: _filtroStatusComissao == 'todas',
            onSelected: (_) => setState(() => _filtroStatusComissao = 'todas'),
            selectedColor: _primaryColor.withValues(alpha:0.3),
            labelStyle: TextStyle(color: _filtroStatusComissao == 'todas' ? _primaryColor : Colors.grey.shade400),
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            label: const Text('Pendentes'),
            selected: _filtroStatusComissao == 'pendentes',
            onSelected: (_) => setState(() => _filtroStatusComissao = 'pendentes'),
            selectedColor: _primaryColor.withValues(alpha:0.3),
            labelStyle: TextStyle(color: _filtroStatusComissao == 'pendentes' ? _primaryColor : Colors.grey.shade400),
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            label: const Text('Pagas'),
            selected: _filtroStatusComissao == 'pagas',
            onSelected: (_) => setState(() => _filtroStatusComissao = 'pagas'),
            selectedColor: _primaryColor.withValues(alpha:0.3),
            labelStyle: TextStyle(color: _filtroStatusComissao == 'pagas' ? _primaryColor : Colors.grey.shade400),
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            label: const Text('Estornadas'),
            selected: _filtroStatusComissao == 'estornadas',
            onSelected: (_) => setState(() => _filtroStatusComissao = 'estornadas'),
            selectedColor: _primaryColor.withValues(alpha:0.3),
            labelStyle: TextStyle(color: _filtroStatusComissao == 'estornadas' ? _primaryColor : Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  List<ComissaoVenda> get _minhasComissoesFiltradas {
    if (_filtroStatusComissao == 'todas') return _minhasComissoes;
    switch (_filtroStatusComissao) {
      case 'pendentes':
        return _minhasComissoes.where((c) => c.status == 'confirmado').toList();
      case 'pagas':
        return _minhasComissoes.where((c) => c.status == 'pago').toList();
      case 'estornadas':
        return _minhasComissoes.where((c) => c.status == 'estornado').toList();
      default:
        return _minhasComissoes;
    }
  }

  String _getEmptyStateMensagem() {
    if (_filtroStatusComissao == 'todas') return 'Nenhuma comissão no período';
    if (_filtroStatusComissao == 'pendentes') return 'Nenhuma comissão pendente';
    if (_filtroStatusComissao == 'pagas') return 'Nenhuma comissão paga';
    return 'Nenhuma comissão estornada';
  }

  Widget _buildListaComissoes() {
    final comissoes = _minhasComissoesFiltradas;
    if (comissoes.isEmpty) {
      return _buildCard(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey.shade500),
                const SizedBox(height: 16),
                Text(
                  _getEmptyStateMensagem(),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _filtroStatusComissao == 'todas'
                      ? 'Compartilhe o catálogo com clientes para começar a ganhar comissões nas vendas.'
                      : 'Tente outro filtro ou período.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Suas Comissões', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
          Divider(height: 1, color: Colors.grey.withValues(alpha:0.2)),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: comissoes.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.withValues(alpha:0.2)),
            itemBuilder: (context, index) => _buildComissaoTile(comissoes[index]),
          ),
        ],
      ),
    );
  }

  Widget _buildComissaoTile(ComissaoVenda comissao) {
    Color statusColor;
    IconData statusIcon;

    switch (comissao.status) {
      case 'confirmado':
        statusColor = _warningColor;
        statusIcon = Icons.pending;
        break;
      case 'pago':
        statusColor = _successColor;
        statusIcon = Icons.check_circle;
        break;
      case 'estornado':
        statusColor = _dangerColor;
        statusIcon = Icons.cancel;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.hourglass_empty;
    }

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: statusColor.withValues(alpha:0.2),
        child: Icon(statusIcon, color: statusColor, size: 20),
      ),
      title: Text(
        _formatoMoeda.format(comissao.comissaoValor),
        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Venda: ${_formatoMoeda.format(comissao.totalVenda)} (${comissao.comissaoPercentual.toStringAsFixed(1)}%)',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
          ),
          Text(
            DateFormat('dd/MM/yyyy HH:mm').format(comissao.dataVenda),
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha:0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              comissao.status.toUpperCase(),
              style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.bold),
            ),
          ),
          if (comissao.origem == 'catalogo')
            const Text('via catálogo', style: TextStyle(fontSize: 10, color: Colors.purple)),
        ],
      ),
    );
  }

  // ============================================================
  // VISÃO DO ADMIN
  // ============================================================

  Widget _buildVisaoGeralAdmin() {
    return RefreshIndicator(
      onRefresh: _carregarDados,
      color: _primaryColor,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPeriodoChips(),
            const SizedBox(height: 16),
            _buildResumoGeralAdmin(),
            const SizedBox(height: 16),
            _buildListaVendedoresAdmin(),
          ],
        ),
      ),
    );
  }

  Widget _buildResumoGeralAdmin() {
    double totalVendas = 0;
    double totalComissoes = 0;
    int totalQtdVendas = 0;

    for (final resumo in _resumosVendedores) {
      totalVendas += resumo.totalVendas;
      totalComissoes += resumo.totalComissoes;
      totalQtdVendas += resumo.qtdVendas;
    }

    return _buildCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Resumo Geral', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.picture_as_pdf, color: _primaryColor),
                      onPressed: _exportarRelatorio,
                      tooltip: 'Exportar relatório em PDF',
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: _primaryColor.withValues(alpha:0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(_getPeriodoTexto(), style: const TextStyle(color: _primaryColor, fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildMetricaCard('Total Vendido', _formatoMoeda.format(totalVendas), Icons.shopping_cart, _primaryColor)),
                const SizedBox(width: 12),
                Expanded(child: _buildMetricaCard('Total Comissões', _formatoMoeda.format(totalComissoes), Icons.payments, _warningColor)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildMetricaCard('Vendas', '$totalQtdVendas', Icons.receipt, _successColor)),
                const SizedBox(width: 12),
                Expanded(child: _buildMetricaCard('Vendedores', '${_resumosVendedores.length}', Icons.people, Colors.purple)),
              ],
            ),
            if (_moduloFinanceiroComplemento?.temAlgumDado == true) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _primaryColor.withValues(alpha: 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.account_balance, color: _primaryColor, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Módulo financeiro · complemento gerencial',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Lançamentos reais no período: despesas operacionais ${_formatoMoeda.format(_moduloFinanceiroComplemento!.totalDespesasOperacionais)}, '
                      'compras ${_formatoMoeda.format(_moduloFinanceiroComplemento!.totalCompraMercadoria)}, '
                      'investimentos ${_formatoMoeda.format(_moduloFinanceiroComplemento!.totalInvestimentos)}, '
                      'equipe ${_formatoMoeda.format(_moduloFinanceiroComplemento!.totalPagamentosEquipe)}. '
                      'Metas e comissões acima: só vendas. '
                      'Não substitui o lucro de vendas; coexiste com taxas da Loja Config — evite somar a mesma despesa duas vezes.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildListaVendedoresAdmin() {
    if (_resumosVendedores.isEmpty) {
      return _buildCard(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.people_outline, size: 64, color: Colors.grey.shade500),
                const SizedBox(height: 16),
                const Text(
                  'Nenhum vendedor com comissões',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Sincronize os vendedores para visualizar o resumo de comissões do período.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _sincronizarVendedores,
                  icon: const Icon(Icons.sync),
                  label: const Text('Sincronizar vendedores'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryColor,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Vendedores', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    TextButton.icon(
                      onPressed: _sincronizando ? null : _sincronizarVendedores,
                      icon: _sincronizando
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _primaryColor))
                          : const Icon(Icons.sync, size: 18, color: _primaryColor),
                      label: Text(_sincronizando ? 'Sincronizando...' : 'Sincronizar', style: const TextStyle(color: _primaryColor)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _buscaVendedorController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Buscar vendedor...',
                    hintStyle: TextStyle(color: Colors.grey.shade500),
                    prefixIcon: Icon(Icons.search, color: Colors.grey.shade500),
                    suffixIcon: _buscaVendedor.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            onPressed: () {
                              _buscaVendedorController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(label: const Text('Por vendas'), selected: _ordenacaoVendedores == 'vendas', onSelected: (_) => setState(() => _ordenacaoVendedores = 'vendas'), selectedColor: _primaryColor.withValues(alpha:0.3)),
                      const SizedBox(width: 6),
                      ChoiceChip(label: const Text('Por nome'), selected: _ordenacaoVendedores == 'nome', onSelected: (_) => setState(() => _ordenacaoVendedores = 'nome'), selectedColor: _primaryColor.withValues(alpha:0.3)),
                      const SizedBox(width: 6),
                      ChoiceChip(label: const Text('Por comissão'), selected: _ordenacaoVendedores == 'comissao', onSelected: (_) => setState(() => _ordenacaoVendedores = 'comissao'), selectedColor: _primaryColor.withValues(alpha:0.3)),
                      const SizedBox(width: 6),
                      Tooltip(
                        message: _ordenacaoDescendente ? 'Maior primeiro (clique para inverter)' : 'Menor primeiro (clique para inverter)',
                        child: IconButton(
                          icon: Icon(_ordenacaoDescendente ? Icons.arrow_downward : Icons.arrow_upward, color: _primaryColor, size: 20),
                          onPressed: () => setState(() => _ordenacaoDescendente = !_ordenacaoDescendente),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey.withValues(alpha:0.2)),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _resumosVendedoresFiltrados.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.withValues(alpha:0.2)),
            itemBuilder: (context, index) => _buildVendedorTileAdmin(_resumosVendedoresFiltrados[index]),
          ),
        ],
      ),
    );
  }

  Widget _buildVendedorTileAdmin(ResumoComissaoVendedor resumo) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: _primaryColor.withValues(alpha:0.2),
          child: Text(
            (resumo.vendedorNome ?? 'V')[0].toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.bold, color: _primaryColor),
          ),
        ),
        title: Text(
          resumo.vendedorNome ?? 'Vendedor',
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        subtitle: Text(resumo.vendedorEmail ?? '', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _formatoMoeda.format(resumo.totalVendas),
              style: const TextStyle(fontWeight: FontWeight.bold, color: _successColor),
            ),
            Text(
              '${resumo.percentualComissao?.toStringAsFixed(1) ?? _config?.comissaoGlobalPercent.toStringAsFixed(1) ?? "5.0"}%',
              style: const TextStyle(fontSize: 12, color: _warningColor),
            ),
          ],
        ),
        iconColor: Colors.grey,
        collapsedIconColor: Colors.grey,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.black.withValues(alpha:0.2),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildMiniMetrica('Vendas', '${resumo.qtdVendas}'),
                    _buildMiniMetrica('Via Catálogo', '${resumo.qtdVendasCatalogo}'),
                    _buildMiniMetrica('Comissão', _formatoMoeda.format(resumo.totalComissoes)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _editarComissaoVendedor(resumo),
                        icon: const Icon(Icons.edit, size: 18),
                        label: const Text('Editar %'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _primaryColor,
                          side: const BorderSide(color: _primaryColor),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _verDetalhesVendedor(resumo),
                        icon: const Icon(Icons.visibility, size: 18),
                        label: const Text('Detalhes'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey,
                          side: const BorderSide(color: Colors.grey),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniMetrica(String titulo, String valor) {
    return Column(
      children: [
        Text(titulo, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        const SizedBox(height: 2),
        Text(valor, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
      ],
    );
  }

  // ============================================================
  // CONFIGURAÇÕES (ADMIN)
  // ============================================================

  Widget _buildConfiguracoes() {
    if (_config == null) {
      return const Center(child: CircularProgressIndicator(color: _primaryColor));
    }

    return RefreshIndicator(
      onRefresh: _carregarDados,
      color: _primaryColor,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Comissão global
          _buildCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Comissão Global', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: _primaryColor,
                            inactiveTrackColor: Colors.grey.shade800,
                            thumbColor: _primaryColor,
                            overlayColor: _primaryColor.withValues(alpha:0.2),
                          ),
                          child: Slider(
                            value: _config!.comissaoGlobalPercent,
                            min: 0,
                            max: 30,
                            divisions: 60,
                            label: '${_config!.comissaoGlobalPercent.toStringAsFixed(1)}%',
                            onChanged: (value) {
                              setState(() {
                                _config = _config!.copyWith(comissaoGlobalPercent: value);
                              });
                            },
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: _primaryColor.withValues(alpha:0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${_config!.comissaoGlobalPercent.toStringAsFixed(1)}%',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: _primaryColor, fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Regras de cálculo
          _buildCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Regras de Cálculo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 8),
                  _buildSwitchTile(
                    'Excluir frete da base',
                    'Comissão calculada apenas sobre produtos',
                    _config!.excluirFreteDaBase,
                    (value) => setState(() => _config = _config!.copyWith(excluirFreteDaBase: value)),
                    tooltip: 'Quando ativado, o valor do frete não entra na base de cálculo da comissão.',
                  ),
                  _buildSwitchTile(
                    'Desconto reduz base',
                    'Descontos são subtraídos da base de cálculo',
                    _config!.descontoReduzBase,
                    (value) => setState(() => _config = _config!.copyWith(descontoReduzBase: value)),
                    tooltip: 'Descontos aplicados na venda reduzem o valor sobre o qual a comissão é calculada.',
                  ),
                  _buildSwitchTile(
                    'Apenas após pagamento',
                    'Comissão só é confirmada após pagamento',
                    _config!.apenasAposPagamentoConfirmado,
                    (value) => setState(() => _config = _config!.copyWith(apenasAposPagamentoConfirmado: value)),
                    tooltip: 'A comissão só passa a ser considerada quando o pagamento da venda for confirmado.',
                  ),
                  _buildSwitchTile(
                    'Estorno automático',
                    'Estorna comissão se venda for cancelada',
                    _config!.estornoAutomaticoEmCancelamento,
                    (value) => setState(() => _config = _config!.copyWith(estornoAutomaticoEmCancelamento: value)),
                    tooltip: 'Se uma venda for cancelada, a comissão correspondente é automaticamente estornada.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Tracking
          _buildCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Tracking de Links', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 16),
                  _buildConfigRow(
                    Icons.timer,
                    'Expiração do tracking',
                    '${_config!.trackingExpiracaoDias} dias',
                    TextField(
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        suffixText: 'd',
                        suffixStyle: TextStyle(color: Colors.grey.shade500),
                        isDense: true,
                        errorText: _erroTrackingDias,
                        errorStyle: const TextStyle(fontSize: 11, color: _dangerColor),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade700)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _primaryColor)),
                      ),
                      controller: _trackingDiasController,
                      onChanged: (value) {
                        final parsed = int.tryParse(value);
                        String? erro;
                        if (parsed == null || parsed < 1 || parsed > 365) {
                          erro = parsed == null || value.isEmpty
                              ? null
                              : 'Informe entre 1 e 365 dias';
                        }
                        setState(() {
                          _erroTrackingDias = erro;
                          if (parsed != null && parsed >= 1 && parsed <= 365) {
                            _config = _config!.copyWith(trackingExpiracaoDias: parsed);
                          }
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Botão salvar
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _salvando ? null : _salvarConfiguracoes,
              icon: _salvando ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save),
              label: Text(_salvando ? 'Salvando...' : 'Salvar Configurações'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
        ),
      ),
    );
  }

  Widget _buildSwitchTile(String title, String subtitle, bool value, ValueChanged<bool> onChanged, {String? tooltip}) {
    final tile = SwitchListTile(
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
    );
    if (tooltip != null && tooltip.isNotEmpty) {
      return Tooltip(
        message: tooltip,
        child: tile,
      );
    }
    return tile;
  }

  Widget _buildConfigRow(IconData icon, String title, String subtitle, Widget trailing) {
    return Row(
      children: [
        Icon(icon, color: Colors.grey.shade500),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white)),
              Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
            ],
          ),
        ),
        SizedBox(width: 80, child: trailing),
      ],
    );
  }

  // ============================================================
  // AÇÕES
  // ============================================================

  List<ResumoComissaoVendedor> get _resumosVendedoresFiltrados {
    var list = _resumosVendedores.where((r) {
      if (_buscaVendedor.isEmpty) return true;
      final nome = (r.vendedorNome ?? '').toLowerCase();
      final email = (r.vendedorEmail ?? '').toLowerCase();
      final busca = _buscaVendedor.toLowerCase();
      return nome.contains(busca) || email.contains(busca);
    }).toList();
    final mult = _ordenacaoDescendente ? 1 : -1;
    list = List.from(list)
      ..sort((a, b) {
        int cmp;
        if (_ordenacaoVendedores == 'nome') {
          cmp = (a.vendedorNome ?? '').compareTo(b.vendedorNome ?? '');
        } else if (_ordenacaoVendedores == 'comissao') {
          cmp = b.totalComissoes.compareTo(a.totalComissoes);
        } else {
          cmp = b.totalVendas.compareTo(a.totalVendas);
        }
        return mult * cmp;
      });
    return list;
  }

  String _getPeriodoTexto() {
    switch (_periodoSelecionado) {
      case 'hoje':
        return 'Hoje';
      case 'semana':
        return 'Esta semana';
      case 'mes':
      default:
        return DateFormat('MMM/yyyy').format(_inicioMes);
    }
  }

  Future<void> _exportarRelatorio() async {
    try {
      double totalVendas = 0;
      double totalComissoes = 0;
      int totalQtdVendas = 0;
      for (final r in _resumosVendedores) {
        totalVendas += r.totalVendas;
        totalComissoes += r.totalComissoes;
        totalQtdVendas += r.qtdVendas;
      }

      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (pw.Context ctx) => [
            pw.Center(
              child: pw.Text(
                'Relatório de Comissões',
                style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text(
                'Período: ${_getPeriodoTexto()} | Gerado em ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 10),
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Resumo Geral', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 8),
                  pw.Text('Total Vendido: ${_formatoMoeda.format(totalVendas)}'),
                  pw.Text('Total Comissões: ${_formatoMoeda.format(totalComissoes)}'),
                  pw.Text('Quantidade de Vendas: $totalQtdVendas'),
                  pw.Text('Vendedores: ${_resumosVendedores.length}'),
                ],
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Text('Detalhamento por Vendedor', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            ..._resumosVendedoresFiltrados.map((r) => pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 8),
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(r.vendedorNome ?? 'Vendedor', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        pw.Text(r.vendedorEmail ?? '', style: const pw.TextStyle(fontSize: 9)),
                      ],
                    ),
                  ),
                  pw.Text(_formatoMoeda.format(r.totalVendas), style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(width: 12),
                  pw.Text(_formatoMoeda.format(r.totalComissoes)),
                ],
              ),
            )),
          ],
        ),
      );

      await Printing.layoutPdf(
        onLayout: (_) => pdf.save(),
        name: 'Comissoes_${_getPeriodoTexto().replaceAll(' ', '_')}_${DateFormat('ddMMyyyy').format(DateTime.now())}.pdf',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Relatório exportado!'), backgroundColor: _successColor),
        );
      }
    } catch (e) {
      debugPrint('❌ [COMISSOES] Erro ao exportar PDF (type=${e.runtimeType})');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao exportar: $e'), backgroundColor: _dangerColor),
        );
      }
    }
  }

  Future<void> _sincronizarVendedores() async {
    if (_lojaId == null || _sincronizando) return;
    setState(() => _sincronizando = true);

    try {
      await ComissaoConfigService.sincronizarVendedores(_lojaId!);
      await _carregarDados();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vendedores sincronizados!'), backgroundColor: _successColor),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sincronizando = false);
      }
    }
  }

  Future<void> _salvarConfiguracoes() async {
    if (_config == null || _lojaId == null || _salvando) return;
    final dias = int.tryParse(_trackingDiasController.text);
    if (dias == null || dias < 1 || dias > 365) {
      setState(() => _erroTrackingDias = 'Informe entre 1 e 365 dias');
      return;
    }
    setState(() => _salvando = true);

    try {
      final sucesso = await ComissaoConfigService.salvarConfig(_config!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(sucesso ? 'Configurações salvas!' : 'Erro ao salvar configurações'),
            backgroundColor: sucesso ? _successColor : _dangerColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _salvando = false);
      }
    }
  }

  Future<void> _editarComissaoVendedor(ResumoComissaoVendedor resumo) async {
    final controller = TextEditingController(
      text: (resumo.percentualComissao ?? _config?.comissaoGlobalPercent ?? 5).toStringAsFixed(1),
    );

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardColor,
        title: Text('Alterar comissão de ${resumo.vendedorNome}', style: const TextStyle(color: Colors.white)),
        content: const Text(
          'Ao alterar o percentual, as comissões futuras serão calculadas com o novo valor. Deseja continuar?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancelar', style: TextStyle(color: Colors.grey.shade500)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: _primaryColor),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );

    if (confirmado != true || !mounted) return;

    final valorFinal = await showDialog<double?>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardColor,
        title: Text('Comissão de ${resumo.vendedorNome}', style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Deixe vazio para usar a comissão global', style: TextStyle(color: Colors.grey.shade500)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Percentual de comissão',
                labelStyle: TextStyle(color: Colors.grey.shade500),
                suffixText: '%',
                border: const OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey.shade700)),
                focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: _primaryColor)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancelar', style: TextStyle(color: Colors.grey.shade500)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, -1.0),
            child: const Text('Usar global', style: TextStyle(color: _warningColor)),
          ),
          ElevatedButton(
            onPressed: () {
              final valor = double.tryParse(controller.text);
              Navigator.pop(context, valor);
            },
            style: ElevatedButton.styleFrom(backgroundColor: _primaryColor),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );

    if (valorFinal != null && _lojaId != null) {
      if (!mounted) return;
      await ComissaoConfigService.atualizarPercentualVendedor(
        lojaId: _lojaId!,
        vendedorUid: resumo.vendedorUid,
        comissaoPercentual: valorFinal == -1.0 ? null : valorFinal,
      );
      await _carregarDados();
    }
  }

  void _verDetalhesVendedor(ResumoComissaoVendedor resumo) async {
    if (_lojaId == null) return;
    final comissoes = await ComissaoService.listarComissoesVendedor(
      lojaId: _lojaId!,
      vendedorUid: resumo.vendedorUid,
      inicio: _inicioMes,
      fim: _fimMes,
    );
    if (!mounted) return;
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
            color: _cardColor,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade600, borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '${resumo.vendedorNome} - ${comissoes.length} comissão(ões)',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: ctrl,
                  itemCount: comissoes.length,
                  itemBuilder: (_, i) => _buildComissaoTile(comissoes[i]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tela cheia de sugestões com IA – Metas & Comissões.
class _SugestoesIaMetasScreen extends StatefulWidget {
  final String resumoInicial;

  const _SugestoesIaMetasScreen({required this.resumoInicial});

  @override
  State<_SugestoesIaMetasScreen> createState() => _SugestoesIaMetasScreenState();
}

class _SugestoesIaMetasScreenState extends State<_SugestoesIaMetasScreen> {
  final _perguntaCtrl = TextEditingController();
  String? _resposta;
  bool _enviando = false;
  static const _primaryColor = Color(0xFF00A8FF);
  static const _cardColor = Color(0xFF12121A);

  @override
  void dispose() {
    _perguntaCtrl.dispose();
    super.dispose();
  }

  Future<void> _enviar(String? perguntaFixa) async {
    final pergunta = perguntaFixa ?? _perguntaCtrl.text.trim();
    if (pergunta.isEmpty || _enviando) return;
    final lojaId = await LojaIdService.get();
    if (!await IaUsoLimiteService.canUse(lojaId, TipoUsoIa.perguntas)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(IaUsoLimiteService.messageLimitExcedido(TipoUsoIa.perguntas)), backgroundColor: Colors.orange.shade700),
      );
      return;
    }
    setState(() { _enviando = true; _resposta = null; });
    try {
      final resposta = await AiLojaService.analiseVendasNatural(
        pergunta: pergunta,
        resumoVendas: widget.resumoInicial,
      );
      if (mounted) {
        IaUsoLimiteService.recordUse(lojaId, TipoUsoIa.perguntas);
        setState(() { _resposta = resposta; _enviando = false; });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _enviando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AiLojaService.messageForUser(e)), backgroundColor: Colors.red.shade700),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _cardColor,
      appBar: AppBar(
        backgroundColor: _cardColor,
        title: const Text('Sugestões com IA – Metas', style: TextStyle(color: Colors.white)),
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _enviando ? null : () => _enviar(null),
        tooltip: 'Enviar pergunta',
        backgroundColor: _primaryColor,
        child: _enviando
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.send, color: Colors.white),
      ),
      body: Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: 20 + MediaQuery.of(context).padding.bottom + 100,
          ),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.tonalIcon(
              onPressed: _enviando ? null : () => _enviar('O que fazer para bater a meta? Dê sugestões práticas.'),
              icon: const Icon(Icons.flag),
              label: const Text('O que fazer para bater a meta?'),
              style: FilledButton.styleFrom(backgroundColor: _primaryColor.withValues(alpha:0.2)),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _perguntaCtrl,
              decoration: InputDecoration(
                hintText: 'Ou digite sua pergunta...',
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white.withValues(alpha:0.05),
              ),
              maxLines: 2,
              enabled: !_enviando,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _enviando ? null : () => _enviar(null),
              icon: _enviando ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send),
              label: Text(_enviando ? 'Analisando…' : 'Enviar'),
              style: FilledButton.styleFrom(backgroundColor: _primaryColor),
            ),
            if (_resposta != null) ...[
              const SizedBox(height: 24),
              const Text('Resposta:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _primaryColor.withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Scrollbar(
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    child: SelectableText(_resposta!, style: const TextStyle(color: Colors.white, height: 1.5, fontSize: 15)),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 120),
          ],
        ),
        ),
      ),
    );
  }
}

