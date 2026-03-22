// lib/screens/relatorios_financeiros_screen.dart
// Tela UNIFICADA de Relatórios Financeiros + Metas
// Respeita hierarquia: programador > admin > vendedor

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../utils/moeda_input_formatter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../core/hive_box_names.dart';
import '../models/venda.dart';
import '../models/meta.dart';
import '../services/store_resolver_facade.dart';
import '../services/meta_firestore_service.dart';
import '../utils/chart_utils.dart';
import '../utils/responsive.dart';
import '../services/ai_loja_service.dart';
import '../services/ia_uso_limite_service.dart';
import '../services/loja_id_service.dart';
import '../core/venda_metrics_filter.dart';

class RelatoriosFinanceirosScreen extends StatefulWidget {
  const RelatoriosFinanceirosScreen({super.key});

  @override
  State<RelatoriosFinanceirosScreen> createState() =>
      _RelatoriosFinanceirosScreenState();
}

class _RelatoriosFinanceirosScreenState
    extends State<RelatoriosFinanceirosScreen> {
  // Estado
  bool _carregando = true;
  String _erro = '';

  // Sessão
  String _usuarioLogado = '';
  String _tipoUsuario = 'vendedor';
  String _lojaId = '';
  bool _isAdmin = false;

  // Filtros
  String _filtroTempo = 'mes';
  DateTime? _dataInicio;
  DateTime? _dataFim;
  String _filtroVendedor = 'GERAL';

  // Dados
  List<Venda> _todasVendas = [];
  List<Venda> _vendasFiltradas = [];
  List<String> _vendedoresDisponiveis = [];
  Box<Meta>? _metasBox;
  Meta? _metaAtual;

  // Taxas configuráveis
  double _taxaCartao = 5.0;
  double _taxaMEI = 3.5;
  double _custosFixos = 10.0;
  double _custoEmbalagem = 3.0;

  // Cores do tema
  static const _primaryColor = Color(0xFF00A8FF);
  static const _bgColor = Color(0xFF0A0A0F);
  static const _cardColor = Color(0xFF12121A);
  static const _successColor = Color(0xFF4ADE80);
  static const _warningColor = Color(0xFFFBBF24);
  static const _dangerColor = Color(0xFFEF4444);

  @override
  void initState() {
    super.initState();
    _inicializarFiltrosPadrao();
    _carregarDados();
  }

  void _inicializarFiltrosPadrao() {
    final agora = DateTime.now();
    _dataInicio = DateTime(agora.year, agora.month, 1);
    _dataFim = DateTime(agora.year, agora.month + 1, 0, 23, 59, 59);
  }

  Future<void> _carregarDados() async {
    setState(() {
      _carregando = true;
      _erro = '';
    });

    try {
      final sessao = await Hive.openBox('sessao');
      _usuarioLogado =
          (sessao.get('usuario_logado') ?? '').toString().trim().toLowerCase();
      _tipoUsuario = (sessao.get('tipo_usuario') ?? 'vendedor')
          .toString()
          .trim()
          .toLowerCase();
      _isAdmin = _tipoUsuario == 'programador' || _tipoUsuario == 'admin';

      _lojaId = (await StoreResolverFacade.resolveForAdminApp()) ?? '';
      if (_lojaId.isEmpty) {
        throw Exception('Loja não encontrada. Faça login novamente.');
      }

      final vendasBox = await Hive.openBox<Venda>(HiveBoxNames.vendas(_lojaId));
      _todasVendas = vendasBox.values.toList();

      _vendedoresDisponiveis = _todasVendas
          .map((v) => v.vendedor.trim().toLowerCase())
          .where((v) => v.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

      if (!_isAdmin) {
        _filtroVendedor = _usuarioLogado;
      }

      _metasBox = await Hive.openBox<Meta>('metas_$_lojaId');
      // Trazer metas do Firestore para persistir ao trocar de celular
      try {
        final metasRemotas =
            await MetaFirestoreService.getMetas(lojaId: _lojaId);
        for (final meta in metasRemotas) {
          final key = meta.hiveKey;
          final local = _metasBox!.get(key);
          if (local == null || meta.atualizadoEm.isAfter(local.atualizadoEm)) {
            await _metasBox!.put(key, meta);
          }
        }
      } catch (_) {}
      await _carregarTaxasConfig();
      _aplicarFiltros();
      _carregarMetaAtual();

      if (mounted) {
        setState(() => _carregando = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _carregando = false;
          _erro = e.toString();
        });
      }
    }
  }

  Future<void> _carregarTaxasConfig() async {
    try {
      final configBox =
          await Hive.openBox(HiveBoxNames.relatorioFinanceiro(_lojaId));
      // Lê draft_config (rascunho em Loja Config) com fallback para config (publicado)
      final config = configBox.get('draft_config') ?? configBox.get('config');
      if (config is Map) {
        final taxas = config['taxas'];
        if (taxas is Map) {
          _taxaCartao = (taxas['cartao'] ?? _taxaCartao).toDouble();
          _taxaMEI = (taxas['mei'] ?? _taxaMEI).toDouble();
          _custosFixos = (taxas['custosFixos'] ?? _custosFixos).toDouble();
          _custoEmbalagem = (taxas['embalagem'] ?? _custoEmbalagem).toDouble();
        }
      }
    } catch (_) {}
  }

  void _aplicarFiltros() {
    _vendasFiltradas = _todasVendas.where((v) {
      if (!incluirVendaEmMetricas(v)) return false;
      if (_filtroVendedor != 'GERAL') {
        final vendedor = v.vendedor.trim().toLowerCase();
        if (vendedor != _filtroVendedor.toLowerCase()) return false;
      }
      if (_dataInicio != null && v.data.isBefore(_dataInicio!)) return false;
      if (_dataFim != null && v.data.isAfter(_dataFim!)) return false;
      return true;
    }).toList();
  }

  void _carregarMetaAtual() {
    if (_metasBox == null) return;
    final agora = DateTime.now();
    final mesRef = '${agora.year}-${agora.month.toString().padLeft(2, '0')}';
    final chave = '${mesRef}_$_filtroVendedor';
    _metaAtual = _metasBox!.get(chave);
  }

  // =================== CÁLCULOS FINANCEIROS ===================

  double get _totalVendido =>
      _vendasFiltradas.fold(0.0, (s, v) => s + (v.total));

  double get _qtdVendas => _vendasFiltradas.length.toDouble();

  double get _ticketMedio => _qtdVendas > 0 ? _totalVendido / _qtdVendas : 0;

  double get _totalTaxas {
    double taxas = 0;
    for (final v in _vendasFiltradas) {
      if (v.taxas > 0) {
        taxas += v.taxas;
      } else {
        // pagamentoCartao é double (valor pago em cartão)
        final isCartao = v.pagamentoCartao > 0 ||
            v.formasPagamento.toLowerCase().contains('cart');
        if (isCartao) {
          taxas += v.total * (_taxaCartao / 100);
        }
        taxas += v.total * (_taxaMEI / 100);
        taxas += v.total * (_custosFixos / 100);
        final qtdItens = v.itens?.length ?? 1;
        taxas += qtdItens * _custoEmbalagem;
      }
    }
    return taxas;
  }

  double get _custoProdutos =>
      _vendasFiltradas.fold(0.0, (s, v) => s + (v.custoProdutos));

  double get _lucroEstimado => _totalVendido - _totalTaxas - _custoProdutos;

  /// Totais por forma de pagamento (Dinheiro, Pix, Cartão) – discriminados
  double get _totalDinheiro =>
      _vendasFiltradas.fold(0.0, (s, v) => s + _valorPorForma(v, 'dinheiro'));
  double get _totalPix =>
      _vendasFiltradas.fold(0.0, (s, v) => s + _valorPorForma(v, 'pix'));
  double get _totalCartao =>
      _vendasFiltradas.fold(0.0, (s, v) => s + _valorPorForma(v, 'cartao'));

  double _valorPorForma(Venda v, String forma) {
    if (forma == 'dinheiro') {
      if (v.pagamentoDinheiro > 0) return v.pagamentoDinheiro;
    } else if (forma == 'pix') {
      if (v.pagamentoPix > 0) return v.pagamentoPix;
    } else if (forma == 'cartao') {
      if (v.pagamentoCartao > 0) return v.pagamentoCartao;
    }
    final soma = v.pagamentoDinheiro + v.pagamentoPix + v.pagamentoCartao;
    if (soma > 0) return 0;
    // fallback: parsing formasPagamento para vendas antigas
    final linhas = (v.formasPagamento.isNotEmpty ? v.formasPagamento : '')
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty);
    for (final l in linhas) {
      final low = l.toLowerCase();
      final numStr = l
          .replaceAll(RegExp(r'[^0-9,.\-]'), '')
          .replaceAll('.', '')
          .replaceAll(',', '.');
      final val = double.tryParse(numStr) ?? 0.0;
      if (val <= 0) continue;
      if (forma == 'dinheiro' && low.contains('dinheiro')) return val;
      if (forma == 'pix' && low.contains('pix')) return val;
      if (forma == 'cartao' && (low.contains('cart') || low.contains('cartão'))) {
        return val;
      }
    }
    return 0;
  }

  // =================== METAS ===================

  double get _metaMensal => _metaAtual?.metaMensal ?? 0;

  double get _metaDiariaBase {
    if (_metaMensal <= 0) return 0;
    final agora = DateTime.now();
    final diasNoMes = DateTime(agora.year, agora.month + 1, 0).day;
    return _metaMensal / diasNoMes;
  }

  double get _vendidoHoje {
    final hoje = DateTime.now();
    return _todasVendas.where((v) {
      if (_filtroVendedor != 'GERAL' &&
          v.vendedor.trim().toLowerCase() != _filtroVendedor.toLowerCase()) {
        return false;
      }
      return v.data.year == hoje.year &&
          v.data.month == hoje.month &&
          v.data.day == hoje.day;
    }).fold(0.0, (s, v) => s + v.total);
  }

  double get _vendidoMesAtual {
    final agora = DateTime.now();
    return _todasVendas.where((v) {
      if (_filtroVendedor != 'GERAL' &&
          v.vendedor.trim().toLowerCase() != _filtroVendedor.toLowerCase()) {
        return false;
      }
      return v.data.year == agora.year && v.data.month == agora.month;
    }).fold(0.0, (s, v) => s + v.total);
  }

  double get _faltaParaMeta => max(0, _metaMensal - _vendidoMesAtual);

  double get _metaDiariaAjustada {
    if (_metaMensal <= 0) return 0;
    final agora = DateTime.now();
    final diasNoMes = DateTime(agora.year, agora.month + 1, 0).day;
    final diasRestantes = diasNoMes - agora.day + 1;
    if (diasRestantes <= 0) return 0;
    return _faltaParaMeta / diasRestantes;
  }

  double _calcularMetaSugerida() {
    final agora = DateTime.now();
    final mesAnterior = agora.month == 1
        ? DateTime(agora.year - 1, 12)
        : DateTime(agora.year, agora.month - 1);
    final vendasMesAnterior = _todasVendas.where((v) {
      if (_filtroVendedor != 'GERAL' &&
          v.vendedor.trim().toLowerCase() != _filtroVendedor.toLowerCase()) {
        return false;
      }
      return v.data.year == mesAnterior.year &&
          v.data.month == mesAnterior.month;
    }).fold(0.0, (s, v) => s + v.total);
    final crescimento = _metaAtual?.crescimentoPercent ?? 7.0;
    return vendasMesAnterior * (1 + crescimento / 100);
  }

  List<Map<String, dynamic>> _gerarDadosGraficoDiario() {
    final agora = DateTime.now();
    final diasNoMes = DateTime(agora.year, agora.month + 1, 0).day;
    final metaDiaria = _metaDiariaBase;
    final dados = <Map<String, dynamic>>[];

    for (int dia = 1; dia <= diasNoMes; dia++) {
      final dataRef = DateTime(agora.year, agora.month, dia);
      final vendidoDia = _todasVendas.where((v) {
        if (_filtroVendedor != 'GERAL' &&
            v.vendedor.trim().toLowerCase() != _filtroVendedor.toLowerCase()) {
          return false;
        }
        return v.data.year == dataRef.year &&
            v.data.month == dataRef.month &&
            v.data.day == dataRef.day;
      }).fold(0.0, (s, v) => s + v.total);

      dados.add({
        'dia': dia,
        'vendido': vendidoDia,
        'meta': metaDiaria,
      });
    }
    return dados;
  }

  // =================== FORMATAÇÃO ===================

  String _fmt(double valor) => NumberFormat('#,##0.00', 'pt_BR').format(valor);
  String _fmtData(DateTime data) => DateFormat('dd/MM/yyyy').format(data);

  // =================== BUILD ===================

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
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
        backgroundColor: isError ? _dangerColor : _successColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: _bgColor,
        appBar: AppBar(
          backgroundColor: _cardColor,
          title: const Text('Financeiro & Metas'),
          actions: [
            IconButton(
              icon: const Icon(Icons.auto_awesome),
              onPressed: _abrirSugestoesIa,
              tooltip: 'Sugestões com IA',
            ),
            IconButton(
              icon: const Icon(Icons.help_outline),
              onPressed: _mostrarComoCalculamos,
              tooltip: 'Como calculamos?',
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _carregarDados,
              tooltip: 'Atualizar',
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
            child: _carregando
                ? const Center(
                    child: CircularProgressIndicator(color: _primaryColor))
                : _erro.isNotEmpty
                    ? _buildErro()
                    : _buildConteudo(),
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _abrirSugestoesIa,
          tooltip: 'Sugestões com IA (DRE, metas, gastos, lucro)',
          backgroundColor: Colors.amber,
          child: const Icon(Icons.auto_awesome, color: Colors.black87),
        ),
      ),
    );
  }

  Widget _buildErro() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: _dangerColor, size: 64),
            const SizedBox(height: 16),
            Text(_erro,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _carregarDados,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
              style: ElevatedButton.styleFrom(backgroundColor: _primaryColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConteudo() {
    // ✅ VENDEDOR: Exibir apenas progresso percentual (SEM valores em R$)
    if (!_isAdmin) {
      return _buildConteudoVendedor();
    }

    // ✅ ADMIN/PROGRAMADOR: Exibir tudo normalmente
    return RefreshIndicator(
      onRefresh: _carregarDados,
      color: _primaryColor,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ========== FILTROS ==========
            _buildSecaoTitulo('Filtros', Icons.filter_list),
            const SizedBox(height: 12),
            _buildFiltros(),
            const SizedBox(height: 24),

            // ========== RESUMO FINANCEIRO ==========
            _buildSecaoTitulo('Resumo Financeiro', Icons.attach_money),
            const SizedBox(height: 12),
            if (_vendasFiltradas.isEmpty)
              _buildEmptyState()
            else
              _buildCardsFinanceiros(),
            const SizedBox(height: 24),

            // ========== METAS DO MÊS ==========
            _buildSecaoTitulo('Meta do Mês', Icons.flag),
            const SizedBox(height: 12),
            _buildSecaoMetas(),
            const SizedBox(height: 24),

            // ========== PROGRESSO ==========
            _buildSecaoTitulo('Progresso', Icons.trending_up),
            const SizedBox(height: 12),
            _buildCardsProgresso(),
            const SizedBox(height: 24),

            // ========== GRÁFICO DIÁRIO ==========
            _buildSecaoTitulo('Vendas Diárias vs Meta', Icons.bar_chart),
            const SizedBox(height: 12),
            _buildGrafico(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  /// ✅ CONTEÚDO EXCLUSIVO PARA VENDEDOR
  /// Mostra APENAS progresso percentual da meta - SEM valores em R$
  Widget _buildConteudoVendedor() {
    final progressoMeta = _metaMensal > 0
        ? ((_vendidoMesAtual / _metaMensal) * 100).clamp(0, 100)
        : 0.0;
    final progressoHoje = _metaDiariaAjustada > 0
        ? ((_vendidoHoje / _metaDiariaAjustada) * 100).clamp(0, 100)
        : 0.0;

    return RefreshIndicator(
      onRefresh: _carregarDados,
      color: _primaryColor,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ========== PROGRESSO DA META ==========
            _buildSecaoTitulo('Seu Progresso', Icons.trending_up),
            const SizedBox(height: 16),

            // Card principal de progresso do mês
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _cardColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: progressoMeta >= 100 ? _successColor : _primaryColor,
                  width: 2,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    'Meta do Mês',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha:0.7),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Círculo de progresso grande
                  SizedBox(
                    width: 160,
                    height: 160,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CircularProgressIndicator(
                          value: progressoMeta / 100,
                          strokeWidth: 12,
                          backgroundColor: Colors.white.withValues(alpha:0.1),
                          valueColor: AlwaysStoppedAnimation(
                            progressoMeta >= 100
                                ? _successColor
                                : _primaryColor,
                          ),
                        ),
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${progressoMeta.toStringAsFixed(1)}%',
                                style: TextStyle(
                                  color: progressoMeta >= 100
                                      ? _successColor
                                      : _primaryColor,
                                  fontSize: 36,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                progressoMeta >= 100
                                    ? 'Meta Batida!'
                                    : 'concluído',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha:0.6),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (progressoMeta >= 100)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: _successColor.withValues(alpha:0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.emoji_events,
                              color: _successColor, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Parabéns! Meta alcançada!',
                            style: TextStyle(
                              color: _successColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Progresso do dia
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _cardColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.today, color: _warningColor, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'Progresso de Hoje',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      Text(
                        '${progressoHoje.toStringAsFixed(1)}%',
                        style: TextStyle(
                          color: progressoHoje >= 100
                              ? _successColor
                              : _warningColor,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: (progressoHoje / 100).clamp(0, 1),
                      backgroundColor: Colors.white.withValues(alpha:0.1),
                      valueColor: AlwaysStoppedAnimation(
                        progressoHoje >= 100 ? _successColor : _warningColor,
                      ),
                      minHeight: 10,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Estatísticas do vendedor (sem valores em R$)
            _buildSecaoTitulo('Suas Estatísticas', Icons.bar_chart),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildCardEstatisticaVendedor(
                    'Vendas no Mês',
                    '${_vendasFiltradas.length}',
                    Icons.shopping_cart,
                    _primaryColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildCardEstatisticaVendedor(
                    'Vendas Hoje',
                    '${_todasVendas.where((v) {
                      final hoje = DateTime.now();
                      return v.data.year == hoje.year &&
                          v.data.month == hoje.month &&
                          v.data.day == hoje.day &&
                          v.vendedor.trim().toLowerCase() == _usuarioLogado;
                    }).length}',
                    Icons.today,
                    _successColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Aviso de restrição
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _warningColor.withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _warningColor.withValues(alpha:0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: _warningColor),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Valores detalhados disponíveis apenas para administradores.',
                      style: TextStyle(
                        color: _warningColor,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildCardEstatisticaVendedor(
      String titulo, String valor, IconData icon, Color cor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor.withValues(alpha:0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: cor, size: 28),
          const SizedBox(height: 8),
          Text(
            valor,
            style: TextStyle(
              color: cor,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            titulo,
            style: TextStyle(
              color: Colors.white.withValues(alpha:0.6),
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSecaoTitulo(String titulo, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _primaryColor.withValues(alpha:0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: _primaryColor, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            titulo,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  // =================== FILTROS ===================

  Widget _buildFiltros() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filtro de vendedor (só admin)
          if (_isAdmin) ...[
            const Text('Vendedor',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: _bgColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white24),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _filtroVendedor,
                  isExpanded: true,
                  dropdownColor: _cardColor,
                  style: const TextStyle(color: Colors.white),
                  items: [
                    const DropdownMenuItem(
                        value: 'GERAL', child: Text('Todos os vendedores')),
                    ..._vendedoresDisponiveis.map((v) => DropdownMenuItem(
                          value: v,
                          child: Text(v, overflow: TextOverflow.ellipsis),
                        )),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setState(() {
                        _filtroVendedor = v;
                        _aplicarFiltros();
                        _carregarMetaAtual();
                      });
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Filtro de período
          const Text('Período',
              style: TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildChipFiltro('Hoje', 'hoje'),
              _buildChipFiltro('Semana', 'semana'),
              _buildChipFiltro('Mês', 'mes'),
              _buildChipFiltro('Ano', 'ano'),
              _buildChipFiltro('Personalizado', 'personalizado'),
            ],
          ),

          if (_filtroTempo == 'personalizado') ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildBotaoData(
                      'De:',
                      _dataInicio,
                      (d) => setState(() {
                            _dataInicio = d;
                            _aplicarFiltros();
                          })),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildBotaoData(
                      'Até:',
                      _dataFim,
                      (d) => setState(() {
                            _dataFim = d;
                            _aplicarFiltros();
                          })),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChipFiltro(String label, String valor) {
    final selecionado = _filtroTempo == valor;
    return FilterChip(
      label: Text(label),
      selected: selecionado,
      onSelected: (_) => _selecionarFiltroTempo(valor),
      backgroundColor: _bgColor,
      selectedColor: _primaryColor.withValues(alpha:0.3),
      labelStyle: TextStyle(
        color: selecionado ? _primaryColor : Colors.white70,
        fontWeight: selecionado ? FontWeight.bold : FontWeight.normal,
      ),
      side: BorderSide(color: selecionado ? _primaryColor : Colors.white24),
      checkmarkColor: _primaryColor,
    );
  }

  void _selecionarFiltroTempo(String valor) {
    final agora = DateTime.now();
    setState(() {
      _filtroTempo = valor;
      switch (valor) {
        case 'hoje':
          _dataInicio = DateTime(agora.year, agora.month, agora.day);
          _dataFim = DateTime(agora.year, agora.month, agora.day, 23, 59, 59);
          break;
        case 'semana':
          final inicioSemana =
              agora.subtract(Duration(days: agora.weekday - 1));
          _dataInicio =
              DateTime(inicioSemana.year, inicioSemana.month, inicioSemana.day);
          _dataFim = DateTime(agora.year, agora.month, agora.day, 23, 59, 59);
          break;
        case 'mes':
          _dataInicio = DateTime(agora.year, agora.month, 1);
          _dataFim = DateTime(agora.year, agora.month + 1, 0, 23, 59, 59);
          break;
        case 'ano':
          _dataInicio = DateTime(agora.year, 1, 1);
          _dataFim = DateTime(agora.year, 12, 31, 23, 59, 59);
          break;
        case 'personalizado':
          break;
      }
      _aplicarFiltros();
    });
  }

  Widget _buildBotaoData(
      String label, DateTime? data, Function(DateTime) onSelect) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: data ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 365)),
          builder: (ctx, child) => Theme(
            data: ThemeData.dark().copyWith(
                colorScheme: const ColorScheme.dark(primary: _primaryColor)),
            child: child!,
          ),
        );
        if (picked != null) onSelect(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: _bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          children: [
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const Spacer(),
            Text(
              data != null ? _fmtData(data) : 'Selecionar',
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.calendar_today, color: Colors.white54, size: 16),
          ],
        ),
      ),
    );
  }

  // =================== EMPTY STATE ===================

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha:0.08)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined,
              size: 64, color: Colors.white.withValues(alpha:0.3)),
          const SizedBox(height: 16),
          Text(
            'Nenhuma venda no período',
            style: TextStyle(
                color: Colors.white.withValues(alpha:0.8),
                fontSize: 16,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Altere os filtros de data ou vendedor para ver resultados.',
            textAlign: TextAlign.center,
            style:
                TextStyle(color: Colors.white.withValues(alpha:0.5), fontSize: 13),
          ),
        ],
      ),
    );
  }

  // =================== CARDS FINANCEIROS ===================

  Widget _buildCardsFinanceiros() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
                child: _buildCardMetrica(
                    'Total Vendido',
                    'R\$ ${_fmt(_totalVendido)}',
                    Icons.shopping_cart,
                    _successColor)),
            const SizedBox(width: 12),
            Expanded(
                child: _buildCardMetrica('Taxas', 'R\$ ${_fmt(_totalTaxas)}',
                    Icons.receipt_long, _warningColor)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
                child: _buildCardMetrica(
                    'Custo Produtos',
                    'R\$ ${_fmt(_custoProdutos)}',
                    Icons.inventory_2,
                    Colors.orange)),
            const SizedBox(width: 12),
            Expanded(
                child: _buildCardMetrica(
                    'Lucro Est.',
                    'R\$ ${_fmt(_lucroEstimado)}',
                    Icons.trending_up,
                    _lucroEstimado >= 0 ? _successColor : _dangerColor)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
                child: _buildCardMetrica(
                    'Ticket Médio',
                    'R\$ ${_fmt(_ticketMedio)}',
                    Icons.confirmation_number,
                    _primaryColor)),
            const SizedBox(width: 12),
            Expanded(
                child: _buildCardMetrica(
                    'Qtd. Vendas',
                    _qtdVendas.toInt().toString(),
                    Icons.shopping_bag,
                    Colors.white70)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
                child: _buildCardMetrica(
                    'Dinheiro',
                    'R\$ ${_fmt(_totalDinheiro)}',
                    Icons.money,
                    const Color(0xFF22C55E))),
            const SizedBox(width: 12),
            Expanded(
                child: _buildCardMetrica('Pix', 'R\$ ${_fmt(_totalPix)}',
                    Icons.qr_code, const Color(0xFF32BCAD))),
            const SizedBox(width: 12),
            Expanded(
                child: _buildCardMetrica('Cartão', 'R\$ ${_fmt(_totalCartao)}',
                    Icons.credit_card, const Color(0xFF8B5CF6))),
          ],
        ),
      ],
    );
  }

  Widget _buildCardMetrica(
      String titulo, String valor, IconData icon, Color cor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor.withValues(alpha:0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: cor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(titulo,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha:0.7), fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            valor,
            style: TextStyle(
                color: cor, fontSize: 20, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // =================== METAS ===================

  Widget _buildSecaoMetas() {
    final metaSugerida = _calcularMetaSugerida();
    final agora = DateTime.now();
    final mesAtual = DateFormat('MMMM yyyy', 'pt_BR').format(agora);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Meta para ${mesAtual.substring(0, 1).toUpperCase()}${mesAtual.substring(1)}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16),
                    ),
                    if (_filtroVendedor != 'GERAL')
                      Text('Vendedor: $_filtroVendedor',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ),
              if (_isAdmin)
                IconButton(
                  icon: const Icon(Icons.edit, color: _primaryColor),
                  onPressed: () => _editarMeta(metaSugerida),
                  tooltip: 'Editar meta',
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (_metaMensal > 0) ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Meta Mensal',
                          style:
                              TextStyle(color: Colors.white54, fontSize: 12)),
                      Text('R\$ ${_fmt(_metaMensal)}',
                          style: const TextStyle(
                              color: _primaryColor,
                              fontSize: 24,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Meta Diária Ajustada',
                          style:
                              TextStyle(color: Colors.white54, fontSize: 12)),
                      Text('R\$ ${_fmt(_metaDiariaAjustada)}',
                          style: const TextStyle(
                              color: _warningColor,
                              fontSize: 24,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Barra de progresso
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Progresso do Mês',
                        style: TextStyle(color: Colors.white54, fontSize: 12)),
                    Text(
                      '${((_vendidoMesAtual / _metaMensal) * 100).clamp(0, 100).toStringAsFixed(1)}%',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (_vendidoMesAtual / _metaMensal).clamp(0, 1),
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation(
                      _vendidoMesAtual >= _metaMensal
                          ? _successColor
                          : _primaryColor,
                    ),
                    minHeight: 8,
                  ),
                ),
              ],
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _warningColor.withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _warningColor.withValues(alpha:0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: _warningColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Nenhuma meta definida',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text('Sugestão: R\$ ${_fmt(metaSugerida)}',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13)),
                        const Text('(baseado no mês anterior + 7%)',
                            style:
                                TextStyle(color: Colors.white54, fontSize: 11)),
                      ],
                    ),
                  ),
                  if (_isAdmin)
                    TextButton(
                      onPressed: () => _editarMeta(metaSugerida),
                      child: const Text('Definir',
                          style: TextStyle(color: _primaryColor)),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // =================== CARDS DE PROGRESSO ===================

  Widget _buildCardsProgresso() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildCardProgresso(
                'Vendido Hoje',
                'R\$ ${_fmt(_vendidoHoje)}',
                _vendidoHoje >= _metaDiariaAjustada,
                Icons.today,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildCardProgresso(
                'Falta Hoje',
                'R\$ ${_fmt(max(0, _metaDiariaAjustada - _vendidoHoje))}',
                _vendidoHoje >= _metaDiariaAjustada,
                Icons.hourglass_bottom,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildCardProgresso(
                'Vendido no Mês',
                'R\$ ${_fmt(_vendidoMesAtual)}',
                _vendidoMesAtual >= _metaMensal,
                Icons.calendar_month,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildCardProgresso(
                'Falta p/ Meta',
                'R\$ ${_fmt(_faltaParaMeta)}',
                _faltaParaMeta <= 0,
                Icons.flag,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCardProgresso(
      String titulo, String valor, bool positivo, IconData icon) {
    final cor = positivo ? _successColor : _warningColor;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor.withValues(alpha:0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: cor, size: 18),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(titulo,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12))),
            ],
          ),
          const SizedBox(height: 8),
          Text(valor,
              style: TextStyle(
                  color: cor, fontSize: 18, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  // =================== GRÁFICO ===================

  Widget _buildGrafico() {
    final dados = _gerarDadosGraficoDiario();
    if (dados.isEmpty) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
            color: _cardColor, borderRadius: BorderRadius.circular(16)),
        child: const Center(
            child: Text('Sem dados para exibir',
                style: TextStyle(color: Colors.white54))),
      );
    }

    final maxY = safeMaxY(
      dados
          .map((d) => max(d['vendido'] as double, d['meta'] as double))
          .toList(),
      marginPercent: 0.2,
      minValue: 100.0,
    );
    final hoje = DateTime.now().day;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: _cardColor, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildLegendaItem('Vendido', _primaryColor),
              const SizedBox(width: 16),
              _buildLegendaItem('Meta diária', _warningColor),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 250,
            child: BarChart(
              BarChartData(
                maxY: maxY,
                barGroups: dados.asMap().entries.map((e) {
                  final i = e.key;
                  final d = e.value;
                  final dia = d['dia'] as int;
                  final vendido = d['vendido'] as double;
                  final isHoje = dia == hoje;
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: vendido,
                        color: isHoje ? _successColor : _primaryColor,
                        width: 8,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4)),
                      ),
                    ],
                  );
                }).toList(),
                titlesData: FlTitlesData(
                  show: true,
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= dados.length) {
                          return const SizedBox.shrink();
                        }
                        final dia = dados[idx]['dia'] as int;
                        if (dia % 5 == 1 || dia == DateTime.now().day) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text('$dia',
                                style: TextStyle(
                                    color: dia == hoje
                                        ? _successColor
                                        : Colors.white54,
                                    fontSize: 10)),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 50,
                      getTitlesWidget: (value, meta) {
                        if (value == 0) return const SizedBox.shrink();
                        return Text('${(value / 1000).toStringAsFixed(1)}k',
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 10));
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval:
                      safeInterval(min: 0, max: maxY, targetLines: 4),
                  getDrawingHorizontalLine: (value) => FlLine(
                      color: Colors.white.withValues(alpha:0.1), strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    tooltipBgColor: _cardColor,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      if (groupIndex < 0 || groupIndex >= dados.length) {
                        return null;
                      }
                      final d = dados[groupIndex];
                      final dia = d['dia'] as int;
                      final vendido = d['vendido'] as double;
                      final meta = d['meta'] as double;
                      final diff = vendido - meta;
                      return BarTooltipItem(
                        'Dia $dia\n',
                        const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                        children: [
                          TextSpan(
                              text: 'Vendido: R\$ ${_fmt(vendido)}\n',
                              style: const TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.normal)),
                          TextSpan(
                              text: 'Meta: R\$ ${_fmt(meta)}\n',
                              style: const TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.normal)),
                          TextSpan(
                            text: diff >= 0
                                ? '+R\$ ${_fmt(diff)}'
                                : '-R\$ ${_fmt(diff.abs())}',
                            style: TextStyle(
                                color: diff >= 0 ? _successColor : _dangerColor,
                                fontWeight: FontWeight.bold),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                        y: _metaDiariaBase,
                        color: _warningColor,
                        strokeWidth: 2,
                        dashArray: [5, 5]),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendaItem(String label, Color cor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
                color: cor, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }

  // =================== MODAIS ===================

  Future<void> _editarMeta(double sugerida) async {
    final controller = TextEditingController(
      text:
          MoedaInputFormatter.format(_metaMensal > 0 ? _metaMensal : sugerida),
    );
    final crescimentoCtrl = TextEditingController(
        text: (_metaAtual?.crescimentoPercent ?? 7.0).toStringAsFixed(1));
    try {
      final result = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: _cardColor,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: _primaryColor.withValues(alpha:0.15),
                          borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.flag, color: _primaryColor),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(
                            'Definir Meta - ${_filtroVendedor == 'GERAL' ? 'Geral' : _filtroVendedor}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold))),
                    IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
                const SizedBox(height: 24),
                const Text('Meta Mensal (R\$)',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  inputFormatters: [MoedaInputFormatter()],
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    prefixText: 'R\$ ',
                    prefixStyle:
                        const TextStyle(color: _primaryColor, fontSize: 24),
                    filled: true,
                    fillColor: _bgColor,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Crescimento (%)',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                          const SizedBox(height: 8),
                          TextField(
                            controller: crescimentoCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              suffixText: '%',
                              filled: true,
                              fillColor: _bgColor,
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Sugestão',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: () => controller.text =
                                MoedaInputFormatter.format(sugerida),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 16, horizontal: 12),
                              decoration: BoxDecoration(
                                color: _successColor.withValues(alpha:0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: _successColor.withValues(alpha:0.3)),
                              ),
                              child: Text('R\$ ${_fmt(sugerida)}',
                                  style: const TextStyle(
                                      color: _successColor,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    child: const Text('Salvar Meta',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      if (result == true) {
        final valor = MoedaInputFormatter.parse(controller.text);
        final crescimento =
            double.tryParse(crescimentoCtrl.text.replaceAll(',', '.')) ?? 7.0;
        if (valor > 0) {
          final agora = DateTime.now();
          final mesRef =
              '${agora.year}-${agora.month.toString().padLeft(2, '0')}';
          final novaMeta = Meta(
              mesRef: mesRef,
              metaMensal: valor,
              crescimentoPercent: crescimento,
              vendedorId: _filtroVendedor,
              lojaId: _lojaId);
          await _metasBox?.put(novaMeta.hiveKey, novaMeta);
          try {
            await MetaFirestoreService.saveMeta(novaMeta, lojaId: _lojaId);
          } catch (_) {}
          _carregarMetaAtual();
          if (mounted) {
            setState(() {});
            _showSnackBar('Meta de R\$ ${_fmt(valor)} definida!');
          }
        } else if (mounted) {
          _showSnackBar('Informe um valor maior que zero', isError: true);
        }
      }
    } finally {
      controller.dispose();
      crescimentoCtrl.dispose();
    }
  }

  String _montarResumoParaIa() {
    final fmt =
        NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$', decimalDigits: 2);
    final periodo =
        '${_dataInicio?.day ?? 1}/${_dataInicio?.month ?? 0}/${_dataInicio?.year ?? 0} a ${_dataFim?.day ?? 0}/${_dataFim?.month ?? 0}/${_dataFim?.year ?? 0}';
    final sb = StringBuffer();
    sb.writeln('Período selecionado: $periodo.');
    sb.writeln('Quantidade de vendas: ${_vendasFiltradas.length}.');
    sb.writeln('Faturamento total (receita): ${fmt.format(_totalVendido)}.');
    sb.writeln('Ticket médio: ${fmt.format(_ticketMedio)}.');
    sb.writeln('Meta do mês: ${fmt.format(_metaMensal)}.');
    sb.writeln(
        'Faturamento realizado no mês (até hoje): ${fmt.format(_vendidoMesAtual)}.');
    sb.writeln('Falta para bater a meta: ${fmt.format(_faltaParaMeta)}.');
    sb.writeln('--- DRE (Demonstrativo de Resultados) ---');
    sb.writeln('Receita de vendas: ${fmt.format(_totalVendido)}.');
    sb.writeln('(-) Custos com produtos: ${fmt.format(_custoProdutos)}.');
    sb.writeln(
        '(-) Taxas (cartão, MEI, custos fixos, embalagem): ${fmt.format(_totalTaxas)}.');
    sb.writeln('(=) Lucro estimado: ${fmt.format(_lucroEstimado)}.');
    sb.writeln(
        'Formas de pagamento: Dinheiro ${fmt.format(_totalDinheiro)}, PIX ${fmt.format(_totalPix)}, Cartão ${fmt.format(_totalCartao)}.');
    return sb.toString();
  }

  void _abrirSugestoesIa() {
    final resumo = _montarResumoParaIa();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => _SugestoesIaFinanceiroScreen(resumoInicial: resumo),
      ),
    );
  }

  void _mostrarComoCalculamos() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
            color: _cardColor,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: _primaryColor.withValues(alpha:0.15),
                        borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.help_outline, color: _primaryColor),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                      child: Text('Como Calculamos?',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold))),
                  IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const Divider(color: Colors.white24),
              const SizedBox(height: 12),
              _buildCalculoItem(
                  'Taxa de Cartão',
                  '${_taxaCartao.toStringAsFixed(1)}%',
                  'Aplicada sobre pagamentos em cartão'),
              _buildCalculoItem('Taxa MEI', '${_taxaMEI.toStringAsFixed(1)}%',
                  'Imposto simplificado sobre o total'),
              _buildCalculoItem(
                  'Custos Fixos',
                  '${_custosFixos.toStringAsFixed(1)}%',
                  'Luz, internet, aluguel etc.'),
              _buildCalculoItem(
                  'Embalagem',
                  'R\$ ${_custoEmbalagem.toStringAsFixed(2)}/item',
                  'Custo por unidade vendida'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: _primaryColor.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Fórmula do Lucro Estimado:',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                    SizedBox(height: 8),
                    Text('Lucro = Total Vendido - Taxas - Custo dos Produtos',
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                    SizedBox(height: 4),
                    Text('Taxas = Taxa Cartão + MEI + Custos Fixos + Embalagem',
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text('As taxas podem ser configuradas na Loja Config.',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha:0.5), fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCalculoItem(String titulo, String valor, String descricao) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 6),
              decoration: const BoxDecoration(
                  color: _primaryColor, shape: BoxShape.circle)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                        child: Text(titulo,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500))),
                    Flexible(
                      child: Text(
                        valor,
                        style: const TextStyle(
                            color: _primaryColor, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(descricao,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha:0.6), fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tela cheia de sugestões com IA – Financeiro & Metas (DRE, metas, gastos).
class _SugestoesIaFinanceiroScreen extends StatefulWidget {
  final String resumoInicial;

  const _SugestoesIaFinanceiroScreen({required this.resumoInicial});

  @override
  State<_SugestoesIaFinanceiroScreen> createState() =>
      _SugestoesIaFinanceiroScreenState();
}

class _SugestoesIaFinanceiroScreenState
    extends State<_SugestoesIaFinanceiroScreen> {
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

  Future<void> _enviarPergunta(String? perguntaFixa) async {
    final pergunta = perguntaFixa ?? _perguntaCtrl.text.trim();
    if (pergunta.isEmpty || _enviando) return;
    final lojaId = await LojaIdService.get();
    if (!await IaUsoLimiteService.canUse(lojaId, TipoUsoIa.financeiro)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                IaUsoLimiteService.messageLimitExcedido(TipoUsoIa.financeiro)),
            backgroundColor: Colors.orange.shade700),
      );
      return;
    }
    setState(() {
      _enviando = true;
      _resposta = null;
    });
    try {
      final resposta = await AiLojaService.analiseVendasNatural(
        pergunta: pergunta,
        resumoVendas: widget.resumoInicial,
      );
      if (mounted) {
        IaUsoLimiteService.recordUse(lojaId, TipoUsoIa.financeiro);
        setState(() {
          _resposta = resposta;
          _enviando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _enviando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AiLojaService.messageForUser(e)),
            backgroundColor: Colors.red.shade700,
          ),
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
        title: const Text('Sugestões com IA – Financeiro',
            style: TextStyle(color: Colors.white)),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context)),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _enviando ? null : () => _enviarPergunta(null),
        tooltip: 'Enviar pergunta',
        backgroundColor: _primaryColor,
        child: _enviando
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.send, color: Colors.white),
      ),
      body: Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics()),
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: 20 + MediaQuery.of(context).padding.bottom + 100,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Financeiro: DRE, metas, gastos e lucratividade. Os dados do período já foram enviados para a IA.',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _enviando
                        ? null
                        : () => _enviarPergunta(
                            'Gere um DRE (Demonstrativo de Resultados) do faturamento mensal com os dados abaixo, formatado de forma clara.'),
                    icon: const Icon(Icons.receipt_long, size: 18),
                    label: const Text('Gerar DRE'),
                    style: FilledButton.styleFrom(
                        backgroundColor: _primaryColor.withValues(alpha:0.2)),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _enviando
                        ? null
                        : () => _enviarPergunta(
                            'O que fazer para bater a meta? Dê sugestões práticas.'),
                    icon: const Icon(Icons.flag, size: 18),
                    label: const Text('Bater a meta'),
                    style: FilledButton.styleFrom(
                        backgroundColor: _primaryColor.withValues(alpha:0.2)),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _enviando
                        ? null
                        : () => _enviarPergunta(
                            'Sugestões de corte de gastos com base nos dados abaixo. Onde posso reduzir custos sem prejudicar as vendas?'),
                    icon: const Icon(Icons.savings, size: 18),
                    label: const Text('Corte de gastos'),
                    style: FilledButton.styleFrom(
                        backgroundColor: _primaryColor.withValues(alpha:0.2)),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _enviando
                        ? null
                        : () => _enviarPergunta(
                            'Como melhorar a lucratividade com base nesses números? Dê sugestões práticas.'),
                    icon: const Icon(Icons.trending_up, size: 18),
                    label: const Text('Melhorar lucratividade'),
                    style: FilledButton.styleFrom(
                        backgroundColor: _primaryColor.withValues(alpha:0.2)),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _enviando
                        ? null
                        : () => _enviarPergunta(
                            'Estou com lucro alto. Onde posso reinvestir, dar desconto ou mexer nos preços para equilibrar? Sugestões.'),
                    icon: const Icon(Icons.balance, size: 18),
                    label: const Text('Lucro alto - onde mexer?'),
                    style: FilledButton.styleFrom(
                        backgroundColor: _primaryColor.withValues(alpha:0.2)),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _perguntaCtrl,
                decoration: InputDecoration(
                  hintText:
                      'Ex: Por que meu lucro caiu? Análise do PIX vs cartão?',
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha:0.05),
                ),
                maxLines: 2,
                enabled: !_enviando,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _enviando ? null : () => _enviarPergunta(null),
                icon: _enviando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send),
                label: Text(_enviando ? 'Analisando…' : 'Enviar pergunta'),
                style: FilledButton.styleFrom(backgroundColor: _primaryColor),
              ),
              if (_resposta != null) ...[
                const SizedBox(height: 24),
                const Text('Resposta:',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 16)),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.5),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _primaryColor.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Scrollbar(
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics()),
                      child: SelectableText(_resposta!,
                          style: const TextStyle(
                              color: Colors.white, height: 1.5, fontSize: 15)),
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
