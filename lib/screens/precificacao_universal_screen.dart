// lib/screens/precificacao_universal_screen.dart
// Tela de Precificação Universal - Layout moderno alinhado ao sistema

import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:collection/collection.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/hive_box_names.dart';
import '../models/produto.dart';
import '../services/store_resolver_facade.dart';
import '../utils/moeda_input_formatter.dart';

class PrecificacaoUniversalScreen extends StatefulWidget {
  const PrecificacaoUniversalScreen({super.key});

  @override
  State<PrecificacaoUniversalScreen> createState() =>
      _PrecificacaoUniversalScreenState();
}

class _PrecificacaoUniversalScreenState
    extends State<PrecificacaoUniversalScreen> with TickerProviderStateMixin {
  // Cores do tema (padrão das demais telas)
  static const Color _primaryColor = Color(0xFF6366F1);
  static const Color _successColor = Color(0xFF22C55E);
  static const Color _warningColor = Color(0xFFF59E0B);
  static const Color _errorColor = Color(0xFFEF4444);
  static const Color _backgroundColor = Color(0xFFF8FAFC);
  static const Color _cardColor = Color(0xFFFFFFFF);

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  Box<Produto>? estoqueBox;
  String? _lojaId;
  final List<Map<String, dynamic>> produtos = [];
  bool _carregando = true;
  bool _importando = false;
  String _filtroBusca = '';

  /// Controllers por item para Preço Pretendido (evita perda ao rolar)
  final Map<String, TextEditingController> _pretendidoControllers = {};

  final freteController = TextEditingController(text: '0');
  final markupController = TextEditingController(text: '150');
  final gastosFixosController = TextEditingController(text: '10');
  final meiController = TextEditingController(text: '3.5');
  final embalagemController = TextEditingController(text: '3.0');
  final taxaCartaoController = TextEditingController(text: '5');
  final buscaController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _init();
  }

  @override
  void dispose() {
    _animationController.dispose();
    freteController.dispose();
    markupController.dispose();
    gastosFixosController.dispose();
    meiController.dispose();
    embalagemController.dispose();
    taxaCartaoController.dispose();
    buscaController.dispose();
    for (final c in _pretendidoControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final lojaId = await StoreResolverFacade.resolveForAdminApp();
      if (lojaId == null) {
        throw StateError('Nenhuma loja ativa');
      }
      _lojaId = lojaId;
      final boxName = HiveBoxNames.produtos(lojaId);

      if (!Hive.isBoxOpen(boxName)) {
        await Hive.openBox<Produto>(boxName);
      }

      estoqueBox = Hive.box<Produto>(boxName);
    } catch (e) {
      debugPrint("Erro ao inicializar box de produtos (type=${e.runtimeType})");
    } finally {
      if (mounted) {
        setState(() => _carregando = false);
        _animationController.forward();
      }
    }
  }

  void _showSnackBar(String message,
      {bool isError = false, bool isWarning = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError
                  ? Icons.error_outline
                  : isWarning
                      ? Icons.warning_amber
                      : Icons.check_circle_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError
            ? _errorColor
            : isWarning
                ? _warningColor
                : _successColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  double parseCentavos(String input) {
    input = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (input.isEmpty) return 0.0;
    if (input.length == 1) return double.parse('0.0$input');
    if (input.length == 2) return double.parse('0.$input');
    final valor =
        "${input.substring(0, input.length - 2)}.${input.substring(input.length - 2)}";
    return double.tryParse(valor) ?? 0.0;
  }

  String _chaveItem(Map<String, dynamic> item) =>
      '${item['_uid'] ?? identityHashCode(item)}_${item['nome']}_${item['custo']}_${item['quantidade']}';

  TextEditingController _controllerPretendido(Map<String, dynamic> item) {
    final key = _chaveItem(item);
    _pretendidoControllers[key] ??= TextEditingController(
      text: (item['precoPretendido'] as num? ?? 0) > 0
          ? MoedaInputFormatter.format((item['precoPretendido'] as num).toDouble())
          : '',
    );
    return _pretendidoControllers[key]!;
  }

  void _disposeControllerPretendido(String key) {
    _pretendidoControllers[key]?.dispose();
    _pretendidoControllers.remove(key);
  }

  Future<void> importarExcel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.bytes == null) {
      if (mounted) _showSnackBar('Arquivo vazio ou inacessóvel', isError: true);
      return;
    }

    if (mounted) setState(() => _importando = true);

    try {
      final bytes = file.bytes!;
      final excel = Excel.decodeBytes(bytes);
      final sheet = excel.tables[excel.tables.keys.first];
      if (sheet == null) {
        if (mounted) _showSnackBar('Planilha inválida', isError: true);
        return;
      }

      final novos = <Map<String, dynamic>>[];
      for (var row in sheet.rows.skip(1)) {
        final nome = row[0]?.value.toString().trim() ?? '';
        final custo = (double.tryParse(row[1]?.value.toString() ?? '0') ?? 0)
            .clamp(0.0, double.infinity);
        final quantidade = (int.tryParse(row[2]?.value.toString() ?? '0') ?? 1)
            .clamp(1, 999999);

        if (nome.isNotEmpty && custo > 0) {
          novos.add({
            'nome': nome,
            'custo': custo,
            'quantidade': quantidade,
            'precoPretendido': 0.0,
          });
        }
      }

      if (!mounted) return;
      setState(() {
        produtos.addAll(novos);
        _importando = false;
      });

      if (novos.isNotEmpty) {
        _showSnackBar('${novos.length} produto(s) importado(s) com sucesso!');
      } else {
        _showSnackBar(
            'Nenhum produto válido encontrado. Verifique: Nome (col A), Custo (col B), Quantidade (col C)',
            isWarning: true);
      }
    } catch (e) {
      debugPrint('Erro ao importar Excel (type=${e.runtimeType})');
      if (mounted) {
        setState(() => _importando = false);
        _showSnackBar('Erro ao importar: $e', isError: true);
      }
    }
  }

  double calcularPrecoVenda(double custo) {
    final frete = (double.tryParse(freteController.text) ?? 0)
        .clamp(0.0, double.infinity);
    final markup =
        (double.tryParse(markupController.text) ?? 150).clamp(1.0, 9999.0);
    final gastosFixos =
        (double.tryParse(gastosFixosController.text) ?? 10).clamp(0.0, 100.0);
    final mei = (double.tryParse(meiController.text) ?? 3.5).clamp(0.0, 100.0);
    final embalagem = (double.tryParse(embalagemController.text) ?? 3.0)
        .clamp(0.0, double.infinity);
    final taxaCartao =
        (double.tryParse(taxaCartaoController.text) ?? 5).clamp(0.0, 100.0);

    final custoPorItemFrete =
        frete / (produtos.isNotEmpty ? produtos.length : 1);
    final totalCustos = custo +
        (custo * (gastosFixos / 100)) +
        (custo * (mei / 100)) +
        embalagem +
        custoPorItemFrete;
    final precoSemTaxa = totalCustos * (markup / 100);
    return precoSemTaxa * (1 + taxaCartao / 100);
  }

  void confirmarPrecificacao() {
    if (estoqueBox == null || _lojaId == null) {
      _showSnackBar('Erro: Box de produtos não inicializado', isError: true);
      return;
    }

    if (produtos.isEmpty) {
      _showSnackBar('Adicione produtos antes de confirmar', isWarning: true);
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _successColor.withValues(alpha:0.15),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.check_circle, size: 48, color: _successColor),
            ),
            const SizedBox(height: 16),
            const Text(
              'Confirmar Precificação',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'Deseja atualizar o preço de ${produtos.length} produto(s)?',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _executarPrecificacao();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _successColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Confirmar'),
                  ),
                ),
              ],
            ),
            SizedBox(height: MediaQuery.of(ctx).padding.bottom + 16),
          ],
        ),
      ),
    );
  }

  void _executarPrecificacao() {
    if (estoqueBox == null || _lojaId == null) return;

    int atualizados = 0;
    int criados = 0;

    for (var item in produtos) {
      final nome = item['nome'] as String;
      final custo = item['custo'] as double;
      final precoPretendido =
          (item['precoPretendido'] as num?)?.toDouble() ?? 0.0;
      final precoSugerido = calcularPrecoVenda(custo);
      final precoFinal = precoPretendido > 0 ? precoPretendido : precoSugerido;

      final produtoExistente = estoqueBox!.values.firstWhereOrNull(
        (p) => p.nome.toLowerCase() == nome.toLowerCase(),
      );

      if (produtoExistente != null) {
        produtoExistente
          ..custoReal = custo
          ..precoUnitario = custo
          ..precoSugerido = precoSugerido
          ..precoFinal = precoFinal;
        produtoExistente.save();
        atualizados++;
      } else {
        estoqueBox!.add(
          Produto(
            nome: nome,
            custoReal: custo,
            frete: 0,
            gastosFixos: 0,
            gastosVariaveis: 0,
            precoSugerido: precoSugerido,
            precoFinal: precoFinal,
            quantidade: 0,
            precoUnitario: custo,
            categoria: '',
            dataEntrada: DateTime.now(),
            lojaId: _lojaId!,
          ),
        );
        criados++;
      }
    }

    for (final key in _pretendidoControllers.keys.toList()) {
      _disposeControllerPretendido(key);
    }

    if (mounted) {
      setState(() => produtos.clear());
      _showSnackBar(
          'Precificação concluída! $atualizados atualizado(s), $criados criado(s).');
    }
  }

  Future<void> exportarPDF() async {
    if (produtos.isEmpty) {
      _showSnackBar('Adicione produtos antes de exportar', isWarning: true);
      return;
    }

    try {
      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          build: (ctx) => [
            pw.Text('Relatório de Precificação',
                style:
                    pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            pw.TableHelper.fromTextArray(
              headers: ['Produto', 'Custo', 'Sugerido', 'Pretendido'],
              data: produtos.map((item) {
                final sugerido = calcularPrecoVenda(item['custo'] as double);
                final pretendido = item['precoPretendido'] as num? ?? 0;
                return [
                  item['nome'],
                  'R\$ ${(item['custo'] as num).toStringAsFixed(2)}',
                  'R\$ ${sugerido.toStringAsFixed(2)}',
                  pretendido > 0 ? 'R\$ ${pretendido.toStringAsFixed(2)}' : '-',
                ];
              }).toList(),
            ),
          ],
        ),
      );

      await Printing.layoutPdf(onLayout: (format) => pdf.save());
    } catch (e) {
      if (mounted) _showSnackBar('Erro ao exportar PDF: $e', isError: true);
    }
  }

  void adicionarProdutoManual() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _AddProdutoSheet(
        onAdd: (nome, custo, quantidade) {
          if (nome.isEmpty) {
            _showSnackBar('Informe o nome do produto', isWarning: true);
            return;
          }
          if (custo <= 0) {
            _showSnackBar('Informe um custo válido (ex: 10,90)',
                isWarning: true);
            return;
          }

          setState(() {
            produtos.add({
              '_uid': DateTime.now().microsecondsSinceEpoch,
              'nome': nome,
              'custo': custo,
              'quantidade': quantidade,
              'precoPretendido': 0.0,
            });
          });
          Navigator.pop(ctx);
          _showSnackBar('Produto adicionado!');
        },
      ),
    );
  }

  void limparTudo() {
    if (produtos.isEmpty) {
      _showSnackBar('Não há produtos para limpar', isWarning: true);
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _errorColor.withValues(alpha:0.1),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.delete_forever, size: 48, color: _errorColor),
            ),
            const SizedBox(height: 16),
            const Text(
              'Limpar Tudo',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'Tem certeza que deseja remover todos os ${produtos.length} produtos?',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      for (final key in _pretendidoControllers.keys.toList()) {
                        _disposeControllerPretendido(key);
                      }
                      setState(() => produtos.clear());
                      Navigator.pop(ctx);
                      _showSnackBar('Lista limpa!');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _errorColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Limpar'),
                  ),
                ),
              ],
            ),
            SizedBox(height: MediaQuery.of(ctx).padding.bottom + 16),
          ],
        ),
      ),
    );
  }

  void _restaurarPadrao() {
    freteController.text = '0';
    markupController.text = '150';
    gastosFixosController.text = '10';
    meiController.text = '3.5';
    embalagemController.text = '3.0';
    taxaCartaoController.text = '5';
    setState(() {});
    _showSnackBar('Valores restaurados para o padrão');
  }

  List<Map<String, dynamic>> get _produtosFiltrados {
    if (_filtroBusca.isEmpty) return produtos;
    final q = _filtroBusca.toLowerCase();
    return produtos
        .where((p) => (p['nome'] as String).toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_carregando) {
      return Scaffold(
        backgroundColor: isDark ? cs.surface : _backgroundColor,
        appBar: AppBar(
          backgroundColor: isDark ? cs.primary : _primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text('Precificação Universal'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _primaryColor.withValues(alpha:0.15),
                  shape: BoxShape.circle,
                ),
                child: const CircularProgressIndicator(color: _primaryColor, strokeWidth: 2),
              ),
              const SizedBox(height: 24),
              Text('Carregando...',
                  style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? cs.surface : _backgroundColor,
      appBar: AppBar(
        backgroundColor: isDark ? cs.primary : _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Precificação Universal'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: Colors.white.withValues(alpha:0.9)),
            onPressed: _restaurarPadrao,
            tooltip: 'Restaurar padrão',
          ),
          IconButton(
            icon: Icon(Icons.picture_as_pdf, color: Colors.white.withValues(alpha:0.9)),
            onPressed: exportarPDF,
            tooltip: 'Exportar PDF',
          ),
        ],
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: _importando
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 48,
                      height: 48,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Importando Excel...',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Aguarde enquanto os produtos são processados',
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurfaceVariant.withValues(alpha:0.8),
                      ),
                    ),
                  ],
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildConfigCard(context),
                    const SizedBox(height: 24),
                    _buildProdutosHeader(context),
                    if (produtos.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildBusca(context),
                      const SizedBox(height: 12),
                    ],
                    if (produtos.isEmpty)
                      _buildEmptyState(context)
                    else
                      _buildListaProdutos(context),
                  ],
                ),
              ),
      ),
      bottomNavigationBar: produtos.isNotEmpty
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: Semantics(
                    label: 'Confirmar precificação de ${produtos.length} produtos',
                    button: true,
                    child: ElevatedButton.icon(
                      onPressed: confirmarPrecificacao,
                      icon: const Icon(Icons.check_circle, size: 20),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Confirmar Precificação (${produtos.length} produtos)',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _successColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildConfigCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? cs.primary : _primaryColor;
    return Card(
      elevation: 0,
      color: isDark ? cs.surfaceContainerHighest : _cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: primaryColor.withValues(alpha:0.3)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha:0.08),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha:0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.tune, color: primaryColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Configurações de Cálculo',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: cs.onSurface),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Tooltip(
                    message: 'Markup: multiplicador do custo (150 = 1,5x). '
                        'Taxa cartão: percentual adicional (ex: 5%).',
                    child: Icon(Icons.help_outline,
                        size: 20, color: primaryColor.withValues(alpha:0.8)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildConfigField(context, 'Frete (R\$)', freteController,
                    Icons.local_shipping),
                _buildConfigField(
                    context, 'Markup (%)', markupController, Icons.trending_up, minValue: 1, maxValue: 9999),
                _buildConfigField(context, 'Gastos Fixos (%)',
                    gastosFixosController, Icons.business),
                _buildConfigField(
                    context, 'MEI (%)', meiController, Icons.receipt),
                _buildConfigField(context, 'Embalagem (R\$)',
                    embalagemController, Icons.inventory),
                _buildConfigField(context, 'Taxa cartão (%)',
                    taxaCartaoController, Icons.credit_card),
              ],
            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigField(BuildContext context, String label,
      TextEditingController controller, IconData icon,
      {double minValue = 0, double maxValue = 999999}) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? cs.primary : _primaryColor;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 150, minWidth: 100),
      child: Semantics(
        label: label,
        hint: 'Campo numérico',
        child: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
          onChanged: (_) {
            final v = double.tryParse(controller.text) ?? 0;
            if (v < minValue || v > maxValue) {
              controller.text = v.clamp(minValue, maxValue).toString();
            }
            setState(() {});
          },
        style: TextStyle(color: cs.onSurface),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          prefixIcon: Icon(icon, size: 18, color: primaryColor),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: cs.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: primaryColor, width: 2),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          filled: true,
          fillColor: cs.surfaceContainerHigh,
        ),
        ),
      ),
    );
  }

  Widget _buildProdutosHeader(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? cs.primary : _primaryColor;
    return Row(
      children: [
        Icon(Icons.shopping_bag, color: primaryColor, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Produtos (${produtos.length})',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: cs.onSurface),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Row(
          children: [
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _primaryColor.withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.file_upload, color: primaryColor, size: 20),
              ),
              onPressed: _importando ? null : importarExcel,
              tooltip: 'Importar Excel',
            ),
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _successColor.withValues(alpha:0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.add_circle, color: _successColor, size: 22),
              ),
              onPressed: adicionarProdutoManual,
              tooltip: 'Adicionar produto',
            ),
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _errorColor.withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.delete_sweep, color: _errorColor, size: 20),
              ),
              onPressed: limparTudo,
              tooltip: 'Limpar tudo',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBusca(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? cs.primary : _primaryColor;
    return TextField(
      controller: buscaController,
      onChanged: (v) => setState(() => _filtroBusca = v),
      style: TextStyle(color: cs.onSurface),
      decoration: InputDecoration(
        hintText: 'Buscar por nome...',
        hintStyle: TextStyle(color: cs.onSurfaceVariant),
        prefixIcon: Icon(Icons.search, color: primaryColor.withValues(alpha:0.8)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primaryColor.withValues(alpha:0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primaryColor, width: 2),
        ),
        filled: true,
        fillColor: isDark ? cs.surfaceContainerHighest : _cardColor,
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? cs.primary : _primaryColor;
    return Card(
      elevation: 0,
      color: isDark ? cs.surfaceContainerHighest : _cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: primaryColor.withValues(alpha:0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha:0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.inventory_2_outlined,
                  size: 64, color: primaryColor),
            ),
            const SizedBox(height: 24),
            Text(
              'Nenhum produto adicionado',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              'Importe do Excel (colunas: Nome, Custo, Quantidade) ou adicione manualmente',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
              overflow: TextOverflow.visible,
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: importarExcel,
                  icon: const Icon(Icons.file_upload, size: 18),
                  label: const Text('Importar Excel'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: primaryColor,
                    side: BorderSide(color: primaryColor),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: adicionarProdutoManual,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Adicionar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _successColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListaProdutos(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lista = _produtosFiltrados;
    if (lista.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            'Nenhum produto encontrado para "$_filtroBusca"',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: lista.length,
      itemBuilder: (context, index) => _buildItemProduto(context, lista[index]),
    );
  }

  Widget _buildItemProduto(BuildContext context, Map<String, dynamic> item) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? cs.primary : _primaryColor;
    final precoSugerido = calcularPrecoVenda(item['custo'] as double);
    final controller = _controllerPretendido(item);

    return Card(
      key: ObjectKey(item),
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: isDark ? cs.surfaceContainerHighest : _cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: primaryColor.withValues(alpha:0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.inventory_2, color: primaryColor, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['nome'] as String,
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: cs.onSurface),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          _buildPriceTag('Custo', item['custo'] as double,
                              cs.onSurfaceVariant),
                          _buildPriceTag(
                              'Sugerido', precoSugerido, _successColor),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: _errorColor),
                  onPressed: () {
                    _disposeControllerPretendido(_chaveItem(item));
                    final idx = produtos.indexOf(item);
                    if (idx >= 0) {
                      setState(() => produtos.removeAt(idx));
                      _showSnackBar('Produto removido');
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [MoedaInputFormatter()],
              style: TextStyle(color: cs.onSurface),
              decoration: InputDecoration(
                labelText: 'Preço Pretendido (ex: 50,00)',
                labelStyle: TextStyle(color: cs.onSurfaceVariant),
                hintText: 'Opcional',
                hintStyle: TextStyle(color: cs.onSurfaceVariant),
                prefixIcon: Icon(Icons.edit, color: primaryColor, size: 20),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: cs.outlineVariant),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: primaryColor, width: 2),
                ),
                filled: true,
                fillColor: cs.surfaceContainerHigh,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              onChanged: (value) {
                item['precoPretendido'] = MoedaInputFormatter.parse(value);
                setState(() {});
              },
            ),
            if ((item['precoPretendido'] as num? ?? 0) > 0) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _successColor.withValues(alpha:0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check, size: 16, color: _successColor),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Preço final: R\$ ${(item['precoPretendido'] as num).toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: _successColor,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
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

  Widget _buildPriceTag(String label, double value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha:0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label: R\$ ${value.toStringAsFixed(2)}',
        style:
            TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
    );
  }
}

/// Bottom sheet para adicionar produto - controllers próprios, dispostos em dispose
class _AddProdutoSheet extends StatefulWidget {
  final void Function(String nome, double custo, int quantidade) onAdd;

  const _AddProdutoSheet({required this.onAdd});

  @override
  State<_AddProdutoSheet> createState() => _AddProdutoSheetState();
}

class _AddProdutoSheetState extends State<_AddProdutoSheet> {
  static const Color _sheetPrimary = Color(0xFF6366F1);
  static const Color _sheetSuccess = Color(0xFF22C55E);
  static const Color _sheetBg = Color(0xFFF5F5F5);

  late final TextEditingController nomeController;
  late final TextEditingController custoController;
  late final TextEditingController quantidadeController;

  @override
  void initState() {
    super.initState();
    nomeController = TextEditingController();
    custoController = TextEditingController();
    quantidadeController = TextEditingController(text: '1');
  }

  @override
  void dispose() {
    nomeController.dispose();
    custoController.dispose();
    quantidadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _sheetPrimary.withValues(alpha:0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add_shopping_cart, color: _sheetPrimary),
              ),
              const SizedBox(width: 12),
              const Text(
                'Novo Produto',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 24),
          TextField(
            controller: nomeController,
            decoration: InputDecoration(
              labelText: 'Nome do Produto',
              prefixIcon: const Icon(Icons.inventory_2, color: _sheetPrimary),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: _sheetBg,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: custoController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [MoedaInputFormatter()],
            decoration: InputDecoration(
              labelText: 'Custo (ex: 10,90)',
              prefixIcon: const Icon(Icons.attach_money, color: _sheetPrimary),
              prefixText: 'R\$ ',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: _sheetBg,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: quantidadeController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'Quantidade',
              prefixIcon: const Icon(Icons.numbers, color: _sheetPrimary),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: _sheetBg,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                final nome = nomeController.text.trim();
                final custo = MoedaInputFormatter.parse(custoController.text);
                final quantidade =
                    (int.tryParse(quantidadeController.text) ?? 1).clamp(1, 999999);
                widget.onAdd(nome, custo, quantidade);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _sheetSuccess,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Adicionar Produto'),
            ),
          ),
        ],
        ),
      ),
    );
  }
}

