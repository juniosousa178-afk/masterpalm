// lib/screens/fornecedores_screen.dart
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/hive_box_names.dart';
import '../core/logger.dart';
import '../models/fornecedor.dart';
import '../utils/instagram_launcher.dart';
import '../services/permissao_service.dart';
import '../services/fornecedores_firestore_service.dart';
import '../services/loja_id_service.dart';
import '../services/sync_queue_service.dart';
import 'compras/fornecedor_compras_screen.dart';
import '../widgets/app_help_icon_button.dart';
import '../core/spreadsheet/spreadsheet_file_reader.dart';
import '../core/spreadsheet/spreadsheet_import_result.dart';
import '../core/spreadsheet/spreadsheet_import_ui_helper.dart';
import '../services/spreadsheet/fornecedor_spreadsheet_import_parser.dart';

class FornecedoresScreen extends StatefulWidget {
  const FornecedoresScreen({super.key});

  @override
  State<FornecedoresScreen> createState() => _FornecedoresScreenState();
}

class _FornecedoresScreenState extends State<FornecedoresScreen>
    with SingleTickerProviderStateMixin {
  // ==================== CORES DO TEMA ====================
  static const Color primaryColor = Color(0xFF6366F1);
  static const Color secondaryColor = Color(0xFF8B5CF6);
  static const Color successColor = Color(0xFF22C55E);
  static const Color warningColor = Color(0xFFF59E0B);
  static const Color errorColor = Color(0xFFEF4444);
  static const Color surfaceColor = Color(0xFFF8FAFC);
  static const Color cardColor = Colors.white;

  final _nomeController = TextEditingController();
  final _telefoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _instagramController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _searchController = TextEditingController();

  late Box<Fornecedor> _fornecedoresBox;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  /// 🔹 Loja atual (multi-loja via Hive/sessao)
  String? lojaId;

  /// 🔹 Estado de carregamento
  bool _carregando = true;
  bool _erroResolucaoLoja = false;
  bool _importando = false;
  bool _sincronizando = false;
  bool _enviandoFornecedores = false;
  bool? _temDadosParaImportar;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _init();
  }

  Future<void> _init() async {
    await _verificarPermissao();
    if (!mounted) return;

    // 🔹 Resolver lojaId
    lojaId = await LojaIdService.getWithTimeout(timeout: const Duration(seconds: 10));
    if (!mounted) return;
    if (lojaId == null || lojaId!.trim().isEmpty) {
      if (mounted) setState(() { _carregando = false; _erroResolucaoLoja = true; });
      return;
    }

    // 🔥 Abre box por loja
    _fornecedoresBox = await Hive.openBox<Fornecedor>(HiveBoxNames.fornecedores(lojaId!));

    // 🔄 Sincronizar fornecedores do Firestore para o Hive
    try {
      await FornecedoresFirestoreService.syncFirestoreToHive(
        lojaId: lojaId!,
        fornecedoresBox: _fornecedoresBox,
      );
      logD('✅ Fornecedores sincronizados do Firestore');
    } catch (e) {
      logW('⚠️ Erro ao sincronizar fornecedores do Firestore (type=${e.runtimeType})');
    }

    _verificarSeTemDadosParaImportar();

    if (mounted) {
      setState(() {
        _carregando = false;
      });
      _animationController.forward();
    }
  }

  Future<void> _enviarFornecedoresParaNuvem() async {
    setState(() => _enviandoFornecedores = true);
    try {
      await SyncQueueService.processPending();
      final boxName = HiveBoxNames.fornecedores(lojaId!);
      await FornecedoresFirestoreService.syncTodosFornecedores(boxName: boxName);
      if (!mounted) return;
      _mostrarSnackBarModerno('Envio concluído com sucesso', Icons.check_circle, successColor);
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      _mostrarSnackBarModerno('Falha ao enviar para a nuvem: $e', Icons.error, errorColor);
    } finally {
      if (mounted) setState(() => _enviandoFornecedores = false);
    }
  }

  Future<void> _baixarFornecedoresDaNuvem() async {
    setState(() => _sincronizando = true);
    try {
      final n = await FornecedoresFirestoreService.syncFirestoreToHive(
        lojaId: lojaId!,
        fornecedoresBox: _fornecedoresBox,
      );
      if (!mounted) return;
      await _verificarSeTemDadosParaImportar();
      if (!mounted) return;
      final msg = n > 0
          ? 'Baixados $n novo(s) fornecedor(es)'
          : 'Nenhum fornecedor novo encontrado';
      _mostrarSnackBarModerno(msg, Icons.check_circle, successColor);
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      _mostrarSnackBarModerno('Falha ao baixar da nuvem: $e', Icons.error, errorColor);
    } finally {
      if (mounted) setState(() => _sincronizando = false);
    }
  }

  Future<void> _verificarSeTemDadosParaImportar() async {
    try {
      final tem = await FornecedoresFirestoreService.hasDataToImport(
        lojaId: lojaId!,
        localCount: _fornecedoresBox.length,
      );
      if (mounted) setState(() => _temDadosParaImportar = tem);
    } catch (_) {
      if (mounted) setState(() => _temDadosParaImportar = false);
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _telefoneController.dispose();
    _emailController.dispose();
    _instagramController.dispose();
    _whatsappController.dispose();
    _searchController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _verificarPermissao() async {
    final permitido = await PermissaoService.possuiPermissao('fornecedores');
    if (!permitido && mounted) {
      Navigator.pop(context);
      _mostrarSnackBarModerno(
        'Você não tem permissão para acessar esta tela',
        Icons.lock_outline,
        errorColor,
      );
    }
  }

  void _mostrarSnackBarModerno(String mensagem, IconData icone, Color cor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icone, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                mensagem,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: cor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ===========================================================================
  // CRUD
  // ===========================================================================

  void _mostrarFormularioAdicionar() {
    _nomeController.clear();
    _telefoneController.clear();
    _emailController.clear();
    _instagramController.clear();
    _whatsappController.clear();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildFormularioBottomSheet(),
    );
  }

  void _mostrarFormularioEditar(Fornecedor fornecedor, int index) {
    _nomeController.text = fornecedor.nome;
    _telefoneController.text = fornecedor.telefone;
    _emailController.text = fornecedor.email;
    _instagramController.text = fornecedor.instagram;
    _whatsappController.text = fornecedor.whatsapp;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildFormularioBottomSheet(
        isEditing: true,
        fornecedor: fornecedor,
        index: index,
      ),
    );
  }

  Widget _buildFormularioBottomSheet({
    bool isEditing = false,
    Fornecedor? fornecedor,
    int? index,
  }) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Título
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [primaryColor, secondaryColor],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isEditing ? Icons.edit : Icons.person_add,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  isEditing ? 'Editar Fornecedor' : 'Novo Fornecedor',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Campos do formulário
            _buildModernTextField(
              controller: _nomeController,
              label: 'Nome do Fornecedor',
              icon: Icons.person_outline,
              isRequired: true,
            ),
            const SizedBox(height: 16),
            _buildModernTextField(
              controller: _telefoneController,
              label: 'Telefone',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              isRequired: true,
            ),
            const SizedBox(height: 16),
            _buildModernTextField(
              controller: _emailController,
              label: 'E-mail',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            _buildModernTextField(
              controller: _instagramController,
              label: 'Link do Instagram',
              icon: Icons.camera_alt_outlined,
              hint: '@usuario ou link completo',
            ),
            const SizedBox(height: 16),
            _buildModernTextField(
              controller: _whatsappController,
              label: 'WhatsApp',
              icon: Icons.chat_outlined,
              keyboardType: TextInputType.phone,
              hint: 'Ex: 5533999999999',
            ),
            const SizedBox(height: 24),

            // Botões
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: BorderSide(color: Colors.grey[300]!),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Cancelar',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: () {
                      if (isEditing && fornecedor != null && index != null) {
                        _atualizarFornecedor(fornecedor, index);
                      } else {
                        _adicionarFornecedor();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(isEditing ? Icons.save : Icons.add, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          isEditing ? 'Salvar' : 'Adicionar',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool isRequired = false,
    String? hint,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(
          fontSize: 16,
          color: Color(0xFF1E293B),
        ),
        decoration: InputDecoration(
          labelText: isRequired ? '$label *' : label,
          hintText: hint,
          prefixIcon: Icon(icon, color: primaryColor, size: 22),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          labelStyle: TextStyle(
            color: Colors.grey[600],
            fontSize: 14,
          ),
          hintStyle: TextStyle(
            color: Colors.grey[400],
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Future<void> _adicionarFornecedor() async {
    final nome = _nomeController.text.trim();
    final telefone = _telefoneController.text.trim();
    final email = _emailController.text.trim();
    final instagram = _instagramController.text.trim();
    final whatsapp = _whatsappController.text.trim();

    if (nome.isEmpty || telefone.isEmpty) {
      _mostrarSnackBarModerno(
        'Nome e telefone são obrigatórios',
        Icons.warning_amber_rounded,
        warningColor,
      );
      return;
    }

    if (email.isNotEmpty && !Fornecedor.validarEmail(email)) {
      _mostrarSnackBarModerno(
        'E-mail inválido',
        Icons.error_outline,
        errorColor,
      );
      return;
    }

    final fornecedor = Fornecedor(
      nome: nome,
      telefone: telefone,
      email: email,
      instagram: instagram,
      whatsapp: whatsapp,
      dataCadastro: DateTime.now(),
      lojaId: lojaId!,
    );

    final key = await _fornecedoresBox.add(fornecedor);

    // 🔄 Offline-first: enfileirar sync (sincroniza quando houver internet)
    await SyncQueueService.enqueue(
      type: SyncOperationType.upsertFornecedor,
      lojaId: lojaId!,
      boxName: HiveBoxNames.fornecedores(lojaId!),
      entityKey: key,
    );

    if (!mounted) return;
    Navigator.pop(context);
    setState(() {});

    _mostrarSnackBarModerno(
      'Fornecedor adicionado com sucesso!',
      Icons.check_circle_outline,
      successColor,
    );
  }

  Future<void> _atualizarFornecedor(Fornecedor fornecedor, int index) async {
    final nome = _nomeController.text.trim();
    final telefone = _telefoneController.text.trim();
    final email = _emailController.text.trim();
    final instagram = _instagramController.text.trim();
    final whatsapp = _whatsappController.text.trim();

    if (nome.isEmpty || telefone.isEmpty) {
      _mostrarSnackBarModerno(
        'Nome e telefone são obrigatórios',
        Icons.warning_amber_rounded,
        warningColor,
      );
      return;
    }

    if (email.isNotEmpty && !Fornecedor.validarEmail(email)) {
      _mostrarSnackBarModerno(
        'E-mail inválido',
        Icons.error_outline,
        errorColor,
      );
      return;
    }

    final fornecedorAtualizado = Fornecedor(
      nome: nome,
      telefone: telefone,
      email: email,
      instagram: instagram,
      whatsapp: whatsapp,
      dataCadastro: fornecedor.dataCadastro,
      lojaId: lojaId!,
    );

    // Encontrar o índice real na box
    final allFornecedores = _fornecedoresBox.values.toList();
    final realIndex = allFornecedores.indexOf(fornecedor);
    if (realIndex != -1) {
      _fornecedoresBox.putAt(realIndex, fornecedorAtualizado);
      final key = _fornecedoresBox.keyAt(realIndex) as int;
      await SyncQueueService.enqueue(
        type: SyncOperationType.upsertFornecedor,
        lojaId: lojaId!,
        boxName: HiveBoxNames.fornecedores(lojaId!),
        entityKey: key,
      );
    }

    if (!mounted) return;
    Navigator.pop(context);
    setState(() {});

    _mostrarSnackBarModerno(
      'Fornecedor atualizado com sucesso!',
      Icons.check_circle_outline,
      successColor,
    );
  }

  void _confirmarRemocao(Fornecedor fornecedor, int index) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: errorColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.delete_outline,
                color: errorColor,
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Remover Fornecedor',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tem certeza que deseja remover "${fornecedor.nome}"?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: BorderSide(color: Colors.grey[300]!),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Cancelar',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _removerFornecedor(fornecedor);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: errorColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.delete_outline, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Remover',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _removerFornecedor(Fornecedor fornecedor) {
    final allFornecedores = _fornecedoresBox.values.toList();
    final realIndex = allFornecedores.indexOf(fornecedor);
    if (realIndex != -1) {
      _fornecedoresBox.deleteAt(realIndex);
    }
    setState(() {});

    _mostrarSnackBarModerno(
      'Fornecedor removido',
      Icons.check_circle_outline,
      successColor,
    );
  }

  // ===========================================================================
  // Importar via Excel
  // ===========================================================================
  Future<void> _importarExcel() async {
    if (_importando) return;
    setState(() => _importando = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'csv'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        if (mounted) setState(() => _importando = false);
        return;
      }

      final picked = result.files.single;
      final bytes = await readPlatformFileBytes(picked);
      final parsed = parseFornecedorSpreadsheet(
        bytes,
        fileName: picked.name,
      );

      if (parsed.result.issues.any(
        (i) =>
            i.code == SpreadsheetImportCode.ambiguousSheet ||
            i.code == SpreadsheetImportCode.noValidSheet,
      )) {
        if (!mounted) return;
        final issue = parsed.result.issues.first;
        _mostrarSnackBarModerno(
          issue.message ?? issue.codeLabel,
          Icons.error_outline,
          errorColor,
        );
        return;
      }

      int importados = 0;

      for (final row in parsed.rows) {
        final fornecedor = Fornecedor(
          nome: row.nome,
          telefone: row.telefone,
          email: row.email,
          instagram: row.instagram,
          whatsapp: row.whatsapp,
          dataCadastro: DateTime.now(),
          lojaId: lojaId!,
        );

        final key = await _fornecedoresBox.add(fornecedor);
        await SyncQueueService.enqueue(
          type: SyncOperationType.upsertFornecedor,
          lojaId: lojaId!,
          boxName: HiveBoxNames.fornecedores(lojaId!),
          entityKey: key,
        );
        importados++;
      }

      if (!mounted) return;

      final summary = formatSpreadsheetImportSummary(
        SpreadsheetImportResult(
          importedRows: importados,
          rejectedRows: parsed.result.rejectedRows,
          skippedRows: parsed.result.skippedRows,
        ),
      );
      final details = topSpreadsheetIssues(parsed.result.issues);
      final message = details.isEmpty
          ? summary
          : '$summary\n${details.join('\n')}';

      _mostrarSnackBarModerno(
        message,
        importados > 0 ? Icons.check_circle_outline : Icons.info_outline,
        importados > 0 ? successColor : warningColor,
      );

      setState(() {});
    } catch (e) {
      if (!mounted) return;
      _mostrarSnackBarModerno(
        'Erro ao importar: $e',
        Icons.error_outline,
        errorColor,
      );
    } finally {
      if (mounted) setState(() => _importando = false);
    }
  }

  // ===========================================================================
  // Util: abrir link externo (Instagram / WhatsApp)
  // ===========================================================================
  Future<void> _abrirInstagram(String instagram) async {
    String url = instagram;
    if (!instagram.startsWith('http')) {
      final username = instagram.replaceAll('@', '');
      url = 'https://instagram.com/$username';
    }
    // No mobile, tentar abrir no app do Instagram
    if (await openInstagramInApp(url)) return;
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      _mostrarSnackBarModerno(
        'Link do Instagram inválido',
        Icons.error_outline,
        errorColor,
      );
    }
  }

  Future<void> _abrirWhatsApp(String whatsapp) async {
    // Remove caracteres não numéricos
    final numero = whatsapp.replaceAll(RegExp(r'[^\d]'), '');
    final url = 'https://wa.me/$numero';
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      _mostrarSnackBarModerno(
        'Link do WhatsApp inválido',
        Icons.error_outline,
        errorColor,
      );
    }
  }

  Future<void> _ligar(String telefone) async {
    final numero = telefone.replaceAll(RegExp(r'[^\d]'), '');
    final url = 'tel:$numero';
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  int? _resolverChaveHiveFornecedor(Fornecedor f) {
    for (final k in _fornecedoresBox.keys) {
      final o = _fornecedoresBox.get(k);
      if (o == null) continue;
      if (identical(o, f)) return k as int;
      if (o.nome == f.nome &&
          o.telefone == f.telefone &&
          o.email == f.email &&
          o.lojaId == f.lojaId &&
          o.dataCadastro == f.dataCadastro) {
        return k as int;
      }
    }
    return null;
  }

  void _abrirComprasFornecedor(Fornecedor fornecedor) {
    final key = _resolverChaveHiveFornecedor(fornecedor);
    if (key == null || lojaId == null) {
      _mostrarSnackBarModerno(
        'Não foi possível abrir compras deste fornecedor.',
        Icons.error_outline,
        errorColor,
      );
      return;
    }
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => FornecedorComprasScreen(
          lojaId: lojaId!,
          fornecedorHiveKey: key,
          fornecedor: fornecedor,
        ),
      ),
    );
  }

  Future<void> _enviarEmail(String email) async {
    final url = 'mailto:$email';
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  // ===========================================================================
  // UI
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    if (_erroResolucaoLoja) {
      return Scaffold(
        appBar: AppBar(title: const Text('Fornecedores')),
        backgroundColor: surfaceColor,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.store_outlined, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text('Não foi possível carregar a loja.', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text('Verifique sua conexão e tente novamente.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600])),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () {
                    setState(() { _erroResolucaoLoja = false; _carregando = true; });
                    _init();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Tentar novamente'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_carregando) {
      return Scaffold(
        backgroundColor: surfaceColor,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Carregando fornecedores...',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 🔹 filtra fornecedores da loja atual (legado: lojaId vazio mostra no contexto atual)
    var fornecedores = _fornecedoresBox.values
        .where((f) => f.lojaId.isEmpty || f.lojaId == lojaId)
        .toList()
      ..sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));

    // Filtro de busca
    if (_searchQuery.isNotEmpty) {
      fornecedores = fornecedores
          .where((f) =>
              f.nome.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              f.telefone.contains(_searchQuery) ||
              f.email.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }

    return Scaffold(
      backgroundColor: surfaceColor,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: CustomScrollView(
          slivers: [
            // ==================== APP BAR ====================
            SliverAppBar(
              expandedHeight: 140,
              floating: false,
              pinned: true,
              elevation: 0,
              backgroundColor: primaryColor,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                const AppHelpIconButton(iconColor: Colors.white),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  tooltip: 'Mais opções',
                  onSelected: (v) {
                    if (v == 'modelo_import') {
                      Navigator.pushNamed(
                        context,
                        '/modelos_importacao',
                        arguments: const {'tab': 2},
                      );
                    }
                  },
                  itemBuilder: (ctx) => [
                    PopupMenuItem(
                      value: 'modelo_import',
                      child: Row(
                        children: [
                          const Icon(Icons.table_chart_outlined, size: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Modelo de importação (planilha)',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(ctx).textTheme.bodyLarge,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: _enviandoFornecedores
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.cloud_upload, color: Colors.white),
                  tooltip: 'Enviar para Nuvem',
                  onPressed: _enviandoFornecedores ? null : _enviarFornecedoresParaNuvem,
                ),
                IconButton(
                  icon: _sincronizando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.cloud_download, color: Colors.white),
                  tooltip: _temDadosParaImportar == true
                      ? 'Baixar da Nuvem (há fornecedores novos)'
                      : 'Baixar da Nuvem',
                  onPressed: _sincronizando ? null : _baixarFornecedoresDaNuvem,
                ),
                IconButton(
                  icon: _importando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.upload_file, color: Colors.white),
                  tooltip: _importando ? 'Importando...' : 'Importar Excel',
                  onPressed: _importando ? null : _importarExcel,
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [primaryColor, secondaryColor],
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        right: -30,
                        top: -30,
                        child: Container(
                          width: 150,
                          height: 150,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.1),
                          ),
                        ),
                      ),
                      Positioned(
                        left: -20,
                        bottom: -20,
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.08),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 20,
                        right: 20,
                        bottom: 20,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Fornecedores',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${fornecedores.length} fornecedor(es) cadastrado(s)',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ==================== BARRA DE BUSCA ====================
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Container(
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'Buscar fornecedor...',
                      hintStyle: TextStyle(color: Colors.grey[400]),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: primaryColor,
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, color: Colors.grey),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                });
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ==================== LISTA DE FORNECEDORES ====================
            if (fornecedores.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildEmptyState(),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final fornecedor = fornecedores[index];
                      return _buildFornecedorCard(fornecedor, index);
                    },
                    childCount: fornecedores.length,
                  ),
                ),
              ),

            // Espaço extra no final
            const SliverToBoxAdapter(
              child: SizedBox(height: 100),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _mostrarFormularioAdicionar,
        backgroundColor: primaryColor,
        elevation: 4,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Novo Fornecedor',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.people_outline,
              size: 64,
              color: primaryColor,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Nenhum fornecedor',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty
                ? 'Nenhum resultado para "$_searchQuery"'
                : 'Adicione seu primeiro fornecedor',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 24),
          if (_searchQuery.isEmpty)
            ElevatedButton.icon(
              onPressed: _mostrarFormularioAdicionar,
              icon: const Icon(Icons.add),
              label: const Text('Adicionar Fornecedor'),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFornecedorCard(Fornecedor fornecedor, int index) {
    final iniciais = fornecedor.nome.isNotEmpty
        ? fornecedor.nome
            .split(' ')
            .take(2)
            .map((e) => e.isNotEmpty ? e[0].toUpperCase() : '')
            .join()
        : '?';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _mostrarFormularioEditar(fornecedor, index),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Header do card
                Row(
                  children: [
                    // Avatar com iniciais
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [primaryColor, secondaryColor],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: Text(
                          iniciais,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Nome e data
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fornecedor.nome,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Desde ${DateFormat('dd/MM/yyyy').format(fornecedor.dataCadastro)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => _abrirComprasFornecedor(fornecedor),
                      icon: const Icon(
                        Icons.receipt_long_outlined,
                        color: Color(0xFF6366F1),
                      ),
                      tooltip: 'Lançamento de compra',
                    ),
                    // Botão de remover
                    IconButton(
                      onPressed: () => _confirmarRemocao(fornecedor, index),
                      icon: Icon(
                        Icons.delete_outline,
                        color: Colors.grey[400],
                      ),
                      tooltip: 'Remover',
                    ),
                  ],
                ),

                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),

                // Informações de contato
                _buildInfoRow(
                  Icons.phone_outlined,
                  fornecedor.telefone,
                  onTap: () => _ligar(fornecedor.telefone),
                ),
                if (fornecedor.email.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildInfoRow(
                    Icons.email_outlined,
                    fornecedor.email,
                    onTap: () => _enviarEmail(fornecedor.email),
                  ),
                ],

                const SizedBox(height: 16),

                // Botões de ação (Instagram e WhatsApp)
                Row(
                  children: [
                    if (fornecedor.instagram.isNotEmpty)
                      Expanded(
                        child: _buildActionButton(
                          icon: Icons.camera_alt_outlined,
                          label: 'Instagram',
                          color: const Color(0xFFE4405F),
                          onTap: () => _abrirInstagram(fornecedor.instagram),
                        ),
                      ),
                    if (fornecedor.instagram.isNotEmpty &&
                        fornecedor.whatsapp.isNotEmpty)
                      const SizedBox(width: 12),
                    if (fornecedor.whatsapp.isNotEmpty)
                      Expanded(
                        child: _buildActionButton(
                          icon: Icons.chat_outlined,
                          label: 'WhatsApp',
                          color: successColor,
                          onTap: () => _abrirWhatsApp(fornecedor.whatsapp),
                        ),
                      ),
                    if (fornecedor.instagram.isEmpty &&
                        fornecedor.whatsapp.isEmpty)
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'Sem redes sociais cadastradas',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[400],
                              fontStyle: FontStyle.italic,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 18, color: primaryColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 14,
                  color: onTap != null ? primaryColor : Colors.grey[700],
                  decoration:
                      onTap != null ? TextDecoration.underline : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

