import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../src/file_saver.dart' as file_saver;
import 'package:fl_chart/fl_chart.dart';

import '../core/hive_box_names.dart';
import '../models/venda.dart';
import '../models/produto.dart';
import '../models/usuario.dart';
import '../services/hive_multi_store.dart';
import '../services/loja_id_service.dart';
import '../utils/chart_utils.dart';
import '../services/catalog_visitas_service.dart';
import '../core/venda_metrics_filter.dart';
import 'relatorio_ranking_clientes_screen.dart';
import 'relatorio_lucratividade_produto_screen.dart';
import 'carrinhos_abandonados_screen.dart';

class RelatoriosScreen extends StatefulWidget {
  const RelatoriosScreen({super.key});

  @override
  State<RelatoriosScreen> createState() => _RelatoriosScreenState();
}

class _RelatoriosScreenState extends State<RelatoriosScreen> {
  // Modern color scheme
  static const Color _primaryColor = Color(0xFF6366F1);
  static const Color _successColor = Color(0xFF22C55E);
  static const Color _warningColor = Color(0xFFF59E0B);
  static const Color _errorColor = Color(0xFFEF4444);
  static const Color _cardColor = Color(0xFFFFFFFF);
  static const Color _backgroundColor = Color(0xFFF8FAFC);
  static const Color _surfaceColor = Color(0xFF1E293B);

  DateTime? dataInicial;
  DateTime? dataFinal;
  bool _exportando = false;
  Box<Venda>? _vendasBox;
  final clientesBox = HiveMultiStore.clientes;

  String? lojaId;
  Box<Produto>? produtosBox;
  bool _lojaCarregando = true;

  final _currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadLoja());
  }

  Future<void> _loadLoja() async {
    final id = (await LojaIdService.getWithTimeout(timeout: const Duration(seconds: 10)))?.trim();

    if (id == null || id.isEmpty) {
      debugPrint(
        '[RELATORIO_READ] [LOJA_ID] lojaId ausente ao carregar RelatoriosScreen; nenhum dado será exibido.',
      );
      if (mounted) {
        setState(() {
          lojaId = null;
          produtosBox = null;
          _vendasBox = null;
          _lojaCarregando = false;
        });
      }
      return;
    }

    final boxName = HiveBoxNames.vendas(id);
    Box<Venda>? vendas;
    try {
      if (Hive.isBoxOpen(boxName)) {
        vendas = Hive.box<Venda>(boxName);
      } else {
        vendas = await Hive.openBox<Venda>(boxName);
      }
      debugPrint(
        '[RELATORIO_READ] [HIVE_BOX] Box de vendas carregada para lojaId=$id (name=$boxName, length=${vendas.length})',
      );
    } catch (e) {
      debugPrint(
        '[RELATORIO_READ] [HIVE_BOX] Erro ao abrir box de vendas (name=$boxName, type=${e.runtimeType}) para lojaId=$id',
      );
      vendas = null;
    }

    if (mounted) {
      setState(() {
        lojaId = id;
        produtosBox = Hive.isBoxOpen(HiveBoxNames.produtos(id))
            ? Hive.box<Produto>(HiveBoxNames.produtos(id))
            : null;
        _vendasBox = vendas;
        _lojaCarregando = false;
      });
    }
  }

  List<Venda> get vendasFiltradas {
    if (lojaId == null || _vendasBox == null) return [];
    return _vendasBox!.values.where((venda) {
      if (venda.lojaId != lojaId) return false;
      if (!incluirVendaEmMetricas(venda)) return false;
      if (dataInicial != null && venda.data.isBefore(dataInicial!)) {
        return false;
      }
      if (dataFinal != null && venda.data.isAfter(dataFinal!)) {
        return false;
      }
      return true;
    }).toList();
  }

  double get _totalVendas =>
      vendasFiltradas.fold(0.0, (sum, v) => sum + v.total);

  int get _quantidadeVendas => vendasFiltradas.length;

  double get _ticketMedio =>
      _quantidadeVendas > 0 ? _totalVendas / _quantidadeVendas : 0;

  Map<String, double> _vendasPorData() {
    Map<String, double> totais = {};
    for (var venda in vendasFiltradas) {
      final data = DateFormat('dd/MM').format(venda.data);
      totais[data] = (totais[data] ?? 0) + venda.total;
    }
    return totais;
  }

  void _showModernSnackBar(String message, {bool isError = false, bool isSuccess = false}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha:0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isError ? Icons.error_outline :
                isSuccess ? Icons.check_circle_outline : Icons.info_outline,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? _errorColor : isSuccess ? _successColor : _primaryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> exportarRelatoriosParaExcel() async {
    if (_exportando) return;
    if (vendasFiltradas.isEmpty) {
      _showModernSnackBar('Nenhuma venda para exportar', isError: true);
      return;
    }
    setState(() => _exportando = true);
    try {
      final excel = Excel.createExcel();
    final sheet = excel['Relatorios'];
    sheet.appendRow([
      TextCellValue('Cliente'),
      TextCellValue('Produto'),
      TextCellValue('Quantidade'),
      TextCellValue('Total'),
      TextCellValue('Data'),
    ]);

    for (var venda in vendasFiltradas) {
      sheet.appendRow([
        TextCellValue(venda.clienteNome),
        TextCellValue(venda.produtosDescricao),
        IntCellValue(venda.quantidade),
        TextCellValue(venda.total.toStringAsFixed(2)),
        TextCellValue(DateFormat('dd/MM/yyyy').format(venda.data)),
      ]);
    }

    final excelBytes = excel.encode();
    if (excelBytes == null) {
      if (mounted) setState(() => _exportando = false);
      return;
    }

    final fileName = 'relatorios_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    await file_saver.saveFile(Uint8List.fromList(excelBytes), fileName);

    if (!mounted) return;
    _showModernSnackBar('Arquivo exportado com sucesso!', isSuccess: true);
    } catch (e) {
      if (mounted) _showModernSnackBar('Erro ao exportar: $e', isError: true);
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  Future<void> _selecionarDataInicial() async {
    final data = await showDatePicker(
      context: context,
      initialDate: dataInicial ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _primaryColor,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: _surfaceColor,
            ),
          ),
          child: child!,
        );
      },
    );
    if (data != null) setState(() => dataInicial = data);
  }

  Future<void> _selecionarDataFinal() async {
    final data = await showDatePicker(
      context: context,
      initialDate: dataFinal ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _primaryColor,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: _surfaceColor,
            ),
          ),
          child: child!,
        );
      },
    );
    if (data != null) setState(() => dataFinal = data);
  }

  Future<void> _exportarCatalogoPdf() async {
    if (produtosBox == null || lojaId == null) {
      _showModernSnackBar('Selecione uma loja para exportar o catálogo.', isError: true);
      return;
    }
    try {
      final lista = produtosBox!.values.where((p) => p.lojaId == lojaId).toList();
      lista.sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Center(
                  child: pw.Text(
                    'Catálogo de produtos',
                    style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Text('Loja: $lojaId · ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 10)),
                pw.SizedBox(height: 16),
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey400),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(3),
                    1: const pw.FlexColumnWidth(1),
                    2: const pw.FlexColumnWidth(1),
                    3: const pw.FlexColumnWidth(0.6),
                  },
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                      children: [
                        _cell('Produto', bold: true),
                        _cell('Categoria', bold: true),
                        _cell('Preço', bold: true),
                        _cell('Est.', bold: true),
                      ],
                    ),
                    ...lista.take(200).map((p) => pw.TableRow(
                      children: [
                        _cell(p.nome),
                        _cell(p.categoria),
                        _cell('R\$ ${p.precoFinal.toStringAsFixed(2)}'),
                        _cell('${p.quantidade}'),
                      ],
                    )),
                  ],
                ),
                if (lista.length > 200)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 8),
                    child: pw.Text('... e mais ${lista.length - 200} produtos.', style: const pw.TextStyle(fontSize: 10)),
                  ),
              ],
            );
          },
        ),
      );
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'catalogo_${lojaId}_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
      if (mounted) _showModernSnackBar('Catálogo PDF gerado.', isSuccess: true);
    } catch (e) {
      if (mounted) _showModernSnackBar('Erro ao gerar PDF: $e', isError: true);
    }
  }

  pw.Widget _cell(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(text, style: pw.TextStyle(fontSize: 9, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // protecao por permissoes
    final sessaoBox = Hive.box('sessao');
    final email = sessaoBox.get('usuario_logado');
    final tipo = sessaoBox.get('tipo_usuario');

    final controleBox = Hive.box<Usuario>('usuarios');
    final usuario2 = controleBox.get(email);

    final temPermissao = tipo == 'programador' ||
        (usuario2 != null && usuario2.permissoes['relatorios'] == true);

    if (!temPermissao) {
      return Scaffold(
        backgroundColor: _backgroundColor,
        body: Center(
          child: Container(
            margin: const EdgeInsets.all(32),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: _cardColor,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha:0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _errorColor.withValues(alpha:0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock_outline, size: 48, color: _errorColor),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Acesso Negado',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: _surfaceColor,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Voce nao tem permissao para acessar esta tela.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Voltar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_lojaCarregando) {
      return const Scaffold(
        backgroundColor: _backgroundColor,
        body: Center(child: CircularProgressIndicator(color: _primaryColor)),
      );
    }
    if (lojaId == null) {
      return Scaffold(
        backgroundColor: _backgroundColor,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'Nenhuma loja selecionada. Selecione uma loja para ver os relatórios.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ),
        ),
      );
    }

    final vendasPorData = _vendasPorData();
    final barras = vendasPorData.entries.toList();

    return Scaffold(
      backgroundColor: _backgroundColor,
      body: CustomScrollView(
        slivers: [
          // Modern App Bar
          SliverAppBar(
            expandedHeight: 120,
            floating: false,
            pinned: true,
            elevation: 0,
            backgroundColor: _primaryColor,
            leading: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha:0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
              ),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              Container(
                margin: const EdgeInsets.only(right: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha:0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: IconButton(
                  icon: _exportando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.file_download_outlined, color: Colors.white),
                  onPressed: _exportando ? null : exportarRelatoriosParaExcel,
                  tooltip: _exportando ? 'Exportando...' : 'Exportar Excel',
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              title: const Text(
                'Relatorios',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _primaryColor,
                      _primaryColor.withValues(alpha:0.8),
                    ],
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
                          color: Colors.white.withValues(alpha:0.1),
                        ),
                      ),
                    ),
                    Positioned(
                      left: -30,
                      bottom: -30,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha:0.1),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Filtros de Data
                  _buildSectionCard(
                    title: 'Periodo',
                    icon: Icons.date_range_outlined,
                    iconColor: _primaryColor,
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildDateSelector(
                            label: 'Data Inicial',
                            date: dataInicial,
                            onTap: _selecionarDataInicial,
                            icon: Icons.calendar_today,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildDateSelector(
                            label: 'Data Final',
                            date: dataFinal,
                            onTap: _selecionarDataFinal,
                            icon: Icons.event,
                          ),
                        ),
                        if (dataInicial != null || dataFinal != null) ...[
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () {
                              setState(() {
                                dataInicial = null;
                                dataFinal = null;
                              });
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: _errorColor.withValues(alpha:0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.clear, color: _errorColor, size: 20),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Statistics Cards
                  _buildStatisticsRow(),

                  const SizedBox(height: 16),

                  // Carrinhos abandonados
                  InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CarrinhosAbandonadosScreen(lojaId: lojaId),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: _buildSectionCard(
                      title: 'Carrinhos abandonados',
                      icon: Icons.shopping_cart_outlined,
                      iconColor: _warningColor,
                      child: Row(
                        children: [
                          Icon(Icons.timer_outlined, color: _warningColor.withValues(alpha:0.8)),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Ver carrinhos não finalizados e enviar lembrete por e-mail ou WhatsApp.',
                              style: TextStyle(fontSize: 13, color: Colors.black87),
                            ),
                          ),
                          Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey.shade400),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Lucratividade por produto
                  InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RelatorioLucratividadeProdutoScreen(lojaId: lojaId!),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: _buildSectionCard(
                      title: 'Lucratividade por produto',
                      icon: Icons.trending_up,
                      iconColor: _successColor,
                      child: Row(
                        children: [
                          Icon(Icons.analytics_outlined, color: _successColor.withValues(alpha:0.8)),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Ver custo, venda, margem e lucro por produto.',
                              style: TextStyle(fontSize: 13, color: Colors.black87),
                            ),
                          ),
                          Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey.shade400),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Exportar catálogo em PDF
                  InkWell(
                    onTap: _exportarCatalogoPdf,
                    borderRadius: BorderRadius.circular(16),
                    child: _buildSectionCard(
                      title: 'Exportar catálogo em PDF',
                      icon: Icons.picture_as_pdf_outlined,
                      iconColor: _errorColor,
                      child: const Row(
                        children: [
                          Icon(Icons.description, color: Colors.black54),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Gerar PDF com lista de produtos (nome, categoria, preço, estoque).',
                              style: TextStyle(fontSize: 13, color: Colors.black87),
                            ),
                          ),
                          Icon(Icons.arrow_forward_ios, size: 14, color: Colors.black54),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Visitas na loja online (catálogo público)
                  FutureBuilder<int>(
                    future: CatalogVisitasService.obterVisitas(lojaId!),
                    builder: (context, snap) {
                      final visitas = snap.hasData ? snap.data! : 0;
                      return _buildSectionCard(
                        title: 'Visitas na loja online',
                        icon: Icons.visibility_outlined,
                        iconColor: _primaryColor,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Icon(Icons.storefront_outlined, color: _primaryColor.withValues(alpha:0.8)),
                              const SizedBox(width: 12),
                              Text(
                                snap.connectionState == ConnectionState.waiting
                                    ? 'Carregando...'
                                    : '$visitas visita(s) acumuladas (catálogo público; não é período do gráfico)',
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 16),

                  // Grafico de Vendas
                  _buildSectionCard(
                    title: 'Grafico de Vendas',
                    icon: Icons.bar_chart_outlined,
                    iconColor: _successColor,
                    child: barras.isEmpty
                        ? _buildEmptyChart()
                        : SizedBox(
                            height: 220,
                            child: BarChart(
                              BarChartData(
                                alignment: BarChartAlignment.spaceAround,
                                maxY: safeMaxY(barras.map((e) => e.value).toList(), marginPercent: 0.2),
                                barGroups: List.generate(
                                  barras.length,
                                  (i) => BarChartGroupData(
                                    x: i,
                                    barRods: [
                                      BarChartRodData(
                                        toY: barras[i].value,
                                        width: 20,
                                        color: _primaryColor,
                                        borderRadius: const BorderRadius.only(
                                          topLeft: Radius.circular(6),
                                          topRight: Radius.circular(6),
                                        ),
                                        backDrawRodData: BackgroundBarChartRodData(
                                          show: true,
                                          toY: safeMaxY(barras.map((e) => e.value).toList(), marginPercent: 0.2),
                                          color: Colors.grey.shade100,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                gridData: FlGridData(
                                  show: true,
                                  drawVerticalLine: false,
                                  horizontalInterval: safeInterval(
                                    min: 0,
                                    max: barras.map((e) => e.value).reduce((a, b) => a > b ? a : b),
                                    targetLines: 4,
                                  ),
                                  getDrawingHorizontalLine: (value) => FlLine(
                                    color: Colors.grey.shade200,
                                    strokeWidth: 1,
                                  ),
                                ),
                                borderData: FlBorderData(show: false),
                                titlesData: FlTitlesData(
                                  leftTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 50,
                                      getTitlesWidget: (value, meta) {
                                        return Text(
                                          _currencyFormat.format(value),
                                          style: TextStyle(
                                            color: Colors.grey.shade600,
                                            fontSize: 10,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  rightTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false),
                                  ),
                                  topTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false),
                                  ),
                                  bottomTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      getTitlesWidget: (value, meta) {
                                        if (value.toInt() < barras.length) {
                                          return Padding(
                                            padding: const EdgeInsets.only(top: 8),
                                            child: Text(
                                              barras[value.toInt()].key,
                                              style: TextStyle(
                                                color: Colors.grey.shade600,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          );
                                        }
                                        return const SizedBox.shrink();
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                  ),

                  const SizedBox(height: 16),

                  // Produtos Mais Vendidos
                  _buildSectionCard(
                    title: 'Produtos Mais Vendidos',
                    icon: Icons.trending_up,
                    iconColor: _successColor,
                    child: _buildRankingList(
                      items: _produtosMaisVendidos(),
                      emptyMessage: 'Nenhum produto vendido no periodo',
                      valueLabel: 'unidades',
                      color: _successColor,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Ranking de clientes (melhoria dashboard)
                  InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RelatorioRankingClientesScreen(lojaId: lojaId!),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: _buildSectionCard(
                      title: 'Ranking de clientes',
                      icon: Icons.people_outline,
                      iconColor: _primaryColor,
                      child: Row(
                        children: [
                          Icon(Icons.leaderboard, color: _primaryColor.withValues(alpha:0.7)),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Ver ranking por total comprado, quantidade de pedidos e ticket médio.',
                              style: TextStyle(fontSize: 13, color: Colors.black87),
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.black54),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Clientes que Mais Compram
                  _buildSectionCard(
                    title: 'Clientes que Mais Compram',
                    icon: Icons.people_outline,
                    iconColor: _primaryColor,
                    child: _buildRankingList(
                      items: _clientesMaisCompram(),
                      emptyMessage: 'Nenhuma compra no periodo',
                      valueLabel: 'compras',
                      color: _primaryColor,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Produtos com Estoque Baixo
                  _buildSectionCard(
                    title: 'Produtos com Estoque Baixo',
                    icon: Icons.warning_amber_outlined,
                    iconColor: _warningColor,
                    child: _buildLowStockList(),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade100),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 22, color: iconColor),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _surfaceColor,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _buildDateSelector({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
    required IconData icon,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: date != null ? _primaryColor.withValues(alpha:0.1) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: date != null ? _primaryColor.withValues(alpha:0.3) : Colors.grey.shade200,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: date != null ? _primaryColor : Colors.grey.shade600,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                    ),
                  ),
                  Text(
                    date != null
                        ? DateFormat('dd/MM/yyyy').format(date)
                        : 'Selecionar',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: date != null ? _primaryColor : _surfaceColor,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatisticsRow() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            title: 'Total Vendas',
            value: _currencyFormat.format(_totalVendas),
            icon: Icons.attach_money,
            color: _successColor,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            title: 'Vendas',
            value: '$_quantidadeVendas',
            icon: Icons.receipt_long_outlined,
            color: _primaryColor,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            title: 'Ticket Medio',
            value: _currencyFormat.format(_ticketMedio),
            icon: Icons.trending_up,
            color: _warningColor,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha:0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: _surfaceColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyChart() {
    return Container(
      height: 180,
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart_outlined, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'Nenhum dado para exibir',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Selecione um periodo com vendas',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRankingList({
    required List<MapEntry<String, int>> items,
    required String emptyMessage,
    required String valueLabel,
    required Color color,
  }) {
    if (items.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            emptyMessage,
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
      );
    }

    return Column(
      children: items.take(5).toList().asMap().entries.map((entry) {
        final index = entry.key;
        final item = entry.value;
        final isFirst = index == 0;

        return Container(
          margin: EdgeInsets.only(bottom: index < items.length - 1 && index < 4 ? 8 : 0),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isFirst ? color.withValues(alpha:0.1) : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: isFirst ? Border.all(color: color.withValues(alpha:0.3)) : null,
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isFirst ? color : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      color: isFirst ? Colors.white : Colors.grey.shade700,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.key,
                  style: TextStyle(
                    fontWeight: isFirst ? FontWeight.bold : FontWeight.w500,
                    color: _surfaceColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isFirst ? color : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${item.value} $valueLabel',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isFirst ? Colors.white : Colors.grey.shade700,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildLowStockList() {
    final produtos = _produtosEstoqueBaixo();

    if (produtos.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _successColor.withValues(alpha:0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, color: _successColor),
            SizedBox(width: 8),
            Text(
              'Nenhum produto com estoque baixo',
              style: TextStyle(
                color: _successColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: produtos.take(5).toList().asMap().entries.map((entry) {
        final index = entry.key;
        final produto = entry.value;
        final isLow = produto.quantidade <= 2;

        return Container(
          margin: EdgeInsets.only(bottom: index < produtos.length - 1 && index < 4 ? 8 : 0),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isLow ? _errorColor.withValues(alpha:0.1) : _warningColor.withValues(alpha:0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isLow ? _errorColor.withValues(alpha:0.3) : _warningColor.withValues(alpha:0.3),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isLow ? _errorColor : _warningColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isLow ? Icons.error_outline : Icons.warning_amber_outlined,
                  size: 18,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      produto.nome,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: _surfaceColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      isLow ? 'Estoque critico' : 'Estoque baixo',
                      style: TextStyle(
                        fontSize: 12,
                        color: isLow ? _errorColor : _warningColor,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isLow ? _errorColor : _warningColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${produto.quantidade} un.',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  List<MapEntry<String, int>> _produtosMaisVendidos() {
    final Map<String, int> contagem = {};
    for (var venda in vendasFiltradas) {
      contagem[venda.produtosDescricao] =
          (contagem[venda.produtosDescricao] ?? 0) + venda.quantidade;
    }
    final lista = contagem.entries.toList();
    lista.sort((a, b) => b.value.compareTo(a.value));
    return lista;
  }

  List<MapEntry<String, int>> _clientesMaisCompram() {
    final Map<String, int> contagem = {};
    for (var venda in vendasFiltradas) {
      contagem[venda.clienteNome] = (contagem[venda.clienteNome] ?? 0) + 1;
    }
    final lista = contagem.entries.toList();
    lista.sort((a, b) => b.value.compareTo(a.value));
    return lista;
  }

  List<Produto> _produtosEstoqueBaixo() {
    if (produtosBox == null) return [];
    return produtosBox!.values.where((p) => p.quantidade <= 5).toList();
  }
}

