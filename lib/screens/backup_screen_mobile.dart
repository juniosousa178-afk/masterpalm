// lib/screens/backup_screen.dart
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import '../services/loja_id_service.dart';
import '../services/notificacao_service.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen>
    with SingleTickerProviderStateMixin {
  // ==================== CORES DO TEMA ====================
  static const Color primaryColor = Color(0xFF6366F1);
  static const Color secondaryColor = Color(0xFF8B5CF6);
  static const Color successColor = Color(0xFF22C55E);
  static const Color warningColor = Color(0xFFF59E0B);
  static const Color errorColor = Color(0xFFEF4444);
  static const Color surfaceColor = Color(0xFFF8FAFC);
  static const Color cardColor = Colors.white;

  String? _storeId;
  bool _isLoading = false;
  List<File> _backupFiles = [];

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

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
    _loadStoreId();
    _loadBackupFiles();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  // LojaIdService primeiro (StoreResolver), sessão só fallback offline.
  Future<void> _loadStoreId() async {
    try {
      var id = (await LojaIdService.getWithTimeout(timeout: const Duration(seconds: 8)))?.trim();
      if (id == null || id.isEmpty) {
        if (Hive.isBoxOpen('sessao')) {
          id = Hive.box('sessao').get('store_id')?.toString().trim();
        }
      }
      _storeId = (id != null && id.isNotEmpty) ? id : null;
    } catch (_) {
      _storeId = null;
    }
    if (mounted) {
      setState(() {});
      _animationController.forward();
    }
  }

  Future<void> _loadBackupFiles() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.zip') && f.path.contains('backup_'))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));

      if (mounted) {
        setState(() => _backupFiles = files);
      }
    } catch (_) {}
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

  // -------------------------------------------------------
  // BACKUP — salva SOMENTE os arquivos referentes à loja
  // -------------------------------------------------------
  Future<void> _fazerBackupLoja() async {
    if (_storeId == null || _storeId!.isEmpty) {
      _mostrarSnackBarModerno(
        'Selecione uma loja para criar o backup.',
        Icons.warning_amber,
        warningColor,
      );
      return;
    }
    setState(() => _isLoading = true);

    try {
      final storeId = _storeId!;
      final dir = await getApplicationDocumentsDirectory();
      final files = dir.listSync();

      final backupDir = Directory('${dir.path}/backup_$storeId');
      if (!await backupDir.exists()) {
        await backupDir.create();
      }

      for (final f in files) {
        final name = f.uri.pathSegments.last;
        if (name.contains(storeId) || name == 'sessao.hive') {
          final dest = File('${backupDir.path}/$name');
          await dest.writeAsBytes(await File(f.path).readAsBytes());
        }
      }

      final encoder = ZipFileEncoder();
      final zipPath =
          '${dir.path}/backup_${storeId}_${DateTime.now().millisecondsSinceEpoch}.zip';

      encoder.create(zipPath);
      encoder.addDirectory(backupDir);
      encoder.close();

      await backupDir.delete(recursive: true);

      await NotificacaoService.enviarNotificacao(
        titulo: 'Backup Manual',
        corpo: 'Backup salvo com sucesso!',
      );

      await _loadBackupFiles();

      if (!mounted) return;
      _mostrarSnackBarModerno(
        'Backup criado com sucesso!',
        Icons.check_circle_outline,
        successColor,
      );
    } catch (e) {
      if (!mounted) return;
      _mostrarSnackBarModerno(
        'Erro ao realizar backup: $e',
        Icons.error_outline,
        errorColor,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // -------------------------------------------------------
  // RESTAURAR — mostra todos os zips e restaura somente o ZIP escolhido
  // -------------------------------------------------------
  Future<void> _restaurarBackupLoja() async {
    await _loadBackupFiles();

    if (_backupFiles.isEmpty) {
      _mostrarSnackBarModerno(
        'Nenhum backup encontrado.',
        Icons.warning_amber_rounded,
        warningColor,
      );
      return;
    }

    if (!mounted) return;

    final selecionado = await showModalBottomSheet<File>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
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
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.restore,
                      color: primaryColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Selecione o Backup',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      Text(
                        'Escolha qual backup deseja restaurar',
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.all(16),
                itemCount: _backupFiles.length,
                itemBuilder: (context, index) {
                  final file = _backupFiles[index];
                  final fileName = file.uri.pathSegments.last;
                  final fileStat = file.statSync();
                  final fileDate = fileStat.modified;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: surfaceColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.archive_outlined,
                          color: primaryColor,
                        ),
                      ),
                      title: Text(
                        fileName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        DateFormat('dd/MM/yyyy HH:mm').format(fileDate),
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: primaryColor,
                      ),
                      onTap: () => Navigator.pop(context, file),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (selecionado == null) return;
    if (_storeId == null || _storeId!.isEmpty) {
      _mostrarSnackBarModerno(
        'Selecione uma loja para restaurar o backup.',
        Icons.warning_amber,
        warningColor,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final storeId = _storeId!;
      final dir = await getApplicationDocumentsDirectory();
      final bytes = await selecionado.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      for (final file in archive) {
        final name = file.name;

        if (!name.contains(storeId)) continue;

        final outFile = File('${dir.path}/$name');
        await outFile.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);
      }

      await NotificacaoService.enviarNotificacao(
        titulo: 'Restaurado',
        corpo: 'Backup restaurado com sucesso!',
      );

      if (!mounted) return;
      _mostrarSnackBarModerno(
        'Backup restaurado com sucesso!',
        Icons.check_circle_outline,
        successColor,
      );
    } catch (e) {
      if (!mounted) return;
      _mostrarSnackBarModerno(
        'Erro ao restaurar: $e',
        Icons.error_outline,
        errorColor,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _confirmarExclusaoBackup(File file) {
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
              'Excluir Backup',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tem certeza que deseja excluir este backup?',
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
                    onPressed: () async {
                      Navigator.pop(context);
                      await file.delete();
                      await _loadBackupFiles();
                      _mostrarSnackBarModerno(
                        'Backup excluído',
                        Icons.check_circle_outline,
                        successColor,
                      );
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
                    child: const Text(
                      'Excluir',
                      style: TextStyle(fontWeight: FontWeight.w600),
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

  // -------------------------------------------------------
  // UI
  // -------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Scaffold(
        backgroundColor: surfaceColor,
        appBar: AppBar(
          title: const Text('Backup da Loja'),
          backgroundColor: primaryColor,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'Backup local não disponível na versão Web',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 8),
                Text(
                  'Use o aplicativo Android para fazer backup local dos dados.\nOs dados da loja são sincronizados automaticamente com o Firestore.',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: surfaceColor,
      body: Stack(
        children: [
          FadeTransition(
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
                                  'Backup',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _storeId != null ? 'Loja: $_storeId' : 'Nenhuma loja selecionada',
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

                // ==================== CONTEÚDO ====================
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Card de informações
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                primaryColor.withOpacity(0.1),
                                secondaryColor.withOpacity(0.05),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: primaryColor.withOpacity(0.2),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: primaryColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.info_outline,
                                  color: primaryColor,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Faça backup dos dados da sua loja para não perder informações importantes.',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Botões de ação
                        Row(
                          children: [
                            Expanded(
                              child: _buildActionCard(
                                icon: Icons.cloud_upload_outlined,
                                title: 'Criar Backup',
                                subtitle: 'Salvar dados atuais',
                                color: successColor,
                                onTap: _isLoading ? null : _fazerBackupLoja,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildActionCard(
                                icon: Icons.cloud_download_outlined,
                                title: 'Restaurar',
                                subtitle: 'Recuperar backup',
                                color: primaryColor,
                                onTap: _isLoading ? null : _restaurarBackupLoja,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),

                        // Lista de backups
                        const Text(
                          'Backups Disponíveis',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 16),

                        if (_backupFiles.isEmpty)
                          _buildEmptyState()
                        else
                          ..._backupFiles.map((file) => _buildBackupItem(file)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Loading overlay
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(
                child: CircularProgressIndicator(color: primaryColor),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Material(
      color: cardColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: color, size: 32),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(32),
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
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.cloud_off_outlined,
              size: 48,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Nenhum backup encontrado',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Crie seu primeiro backup para proteger seus dados',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildBackupItem(File file) {
    final fileName = file.uri.pathSegments.last;
    final fileStat = file.statSync();
    final fileDate = fileStat.modified;
    final fileSize = (fileStat.size / 1024).toStringAsFixed(1);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.archive_outlined,
            color: primaryColor,
          ),
        ),
        title: Text(
          fileName,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              DateFormat('dd/MM/yyyy HH:mm').format(fileDate),
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
            ),
            Text(
              '$fileSize KB',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 11,
              ),
            ),
          ],
        ),
        trailing: IconButton(
          onPressed: () => _confirmarExclusaoBackup(file),
          icon: Icon(
            Icons.delete_outline,
            color: Colors.grey[400],
          ),
        ),
      ),
    );
  }
}

