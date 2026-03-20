// lib/screens/master_config_screen.dart
import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';

import '../models/master_config.dart';
import '../services/master_config_service.dart';
import '../themes/app_colors.dart';
import '../utils/role_utils.dart';
import '../utils/text_utils.dart';

/// Tela de configurações master do aplicativo (apenas root)
class MasterConfigScreen extends StatefulWidget {
  const MasterConfigScreen({super.key});

  @override
  State<MasterConfigScreen> createState() => _MasterConfigScreenState();
}

class _MasterConfigScreenState extends State<MasterConfigScreen> {
  static const _emailRegex = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$';
  static const _updatedBy = 'masterpalm26@gmail.com';
  static const _sessionTimeoutMinutes = 5;

  MasterConfig• _config;
  bool _loading = true;
  String• _loadError;
  bool _savingMercadoPago = false;
  bool _savingAccess = false;
  String• _savingRevokeEmail;
  bool _savingSwitch = false;
  bool _showAccessToken = false;
  bool _testingMp = false;
  bool _maintenanceMode = false;
  bool _savingMaintenance = false;
  final Map<String, bool> _featureFlags = {};
  bool _savingFeatureFlags = false;
  String _searchAccess = '';
  final _bulkEmailsController = TextEditingController();
  bool _savingBulk = false;
  String _appVersion = '1.0.0';
  Timer• _sessionTimer;

  final _mpAccessTokenController = TextEditingController();
  final _mpPublicKeyController = TextEditingController();
  final _newUserEmailController = TextEditingController();
  final _maintenanceMessageController = TextEditingController();
  final _supportPhoneController = TextEditingController();
  bool _savingSupportPhone = false;

  @override
  void initState() {
    super.initState();
    if (!RoleUtils.isRootEmail(FirebaseAuth.instance.currentUser?.email)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Acesso restrito ao root. Você não tem permissão.')),
        );
      });
      return;
    }
    _loadConfig();
    _loadAppVersion();
    _resetSessionTimer();
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    _mpAccessTokenController.dispose();
    _mpPublicKeyController.dispose();
    _newUserEmailController.dispose();
    _bulkEmailsController.dispose();
    _maintenanceMessageController.dispose();
    _supportPhoneController.dispose();
    super.dispose();
  }

  void _resetSessionTimer() {
    _sessionTimer?.cancel();
    _sessionTimer = Timer(const Duration(minutes: _sessionTimeoutMinutes), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _appVersion = info.version);
    } catch (_) {}
  }

  Future<void> _loadConfig() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final config = await MasterConfigService.loadMasterConfig();
      final maintenance = await MasterConfigService.getMaintenanceMode();
      final message = await MasterConfigService.getMaintenanceMessage();
      final catalogo = await MasterConfigService.getFeatureFlag('catalogoWeb');
      final cupons = await MasterConfigService.getFeatureFlag('cupons');
      final supportPhone = await MasterConfigService.getSupportPhone();
      if (!mounted) return;
      setState(() {
        _config = config;
        _loadError = null;
        _mpAccessTokenController.text = config.mercadoPagoAccessToken ?• '';
        _mpPublicKeyController.text = config.mercadoPagoPublicKey ?• '';
        _maintenanceMode = maintenance;
        _maintenanceMessageController.text = message;
        _featureFlags['catalogoWeb'] = catalogo;
        _featureFlags['cupons'] = cupons;
        _supportPhoneController.text = supportPhone;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Erro ao carregar configurações: $e';
      });
      _showError(_loadError!);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _testMercadoPagoConnection() async {
    final token = _mpAccessTokenController.text.trim();
    if (token.isEmpty) {
      _showError('Digite o Access Token para testar');
      return;
    }
    setState(() => _testingMp = true);
    try {
      final ok = await MasterConfigService.testMercadoPagoConnection(token);
      if (!mounted) return;
      if (ok) {
        _showSuccess('Conexão com Mercado Pago OK!');
      } else {
        _showError('Falha na conexão. Verifique o Access Token.');
      }
    } finally {
      if (mounted) setState(() => _testingMp = false);
    }
  }

  Future<void> _saveMercadoPagoKeys() async {
    final accessToken = _mpAccessTokenController.text.trim();
    final publicKey = _mpPublicKeyController.text.trim();

    if (accessToken.isEmpty || publicKey.isEmpty) {
      _showError('Preencha ambas as chaves do Mercado Pago');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar alteração'),
        content: const Text(
          'As chaves do Mercado Pago serão substituídas. '
          'Isso pode afetar pagamentos em andamento. Deseja continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _savingMercadoPago = true);
    try {
      await MasterConfigService.updateMercadoPagoKeys(
        accessToken: accessToken,
        publicKey: publicKey,
        updatedBy: _updatedBy,
      );
      _showSuccess('Chaves do Mercado Pago salvas com sucesso!');
      await _loadConfig();
    } catch (e) {
      _showError('Erro ao salvar chaves: $e');
    } finally {
      if (mounted) setState(() => _savingMercadoPago = false);
    }
  }

  Future<void> _changePassword() async {
    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Alterar Senha Master'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: oldPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Senha Atual',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: newPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Nova Senha',
                  prefixIcon: Icon(Icons.lock),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: confirmPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirmar Nova Senha',
                  prefixIcon: Icon(Icons.lock),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final oldPassword = oldPasswordController.text.trim();
              final newPassword = newPasswordController.text.trim();
              final confirmPassword = confirmPasswordController.text.trim();

              if (oldPassword.isEmpty ||
                  newPassword.isEmpty ||
                  confirmPassword.isEmpty) {
                _showError('Preencha todos os campos');
                return;
              }

              if (newPassword != confirmPassword) {
                _showError('As senhas não coincidem');
                return;
              }

              if (newPassword.length < 8) {
                _showError('A senha deve ter no mínimo 8 caracteres');
                return;
              }

              try {
                await MasterConfigService.updateMasterPassword(
                  oldPassword: oldPassword,
                  newPassword: newPassword,
                  updatedBy: _updatedBy,
                );
                if (!mounted) return;
                // ignore: use_build_context_synchronously
                Navigator.pop(context, true);
              } catch (e) {
                _showError('Erro: $e');
              }
            },
            child: const Text('Alterar'),
          ),
        ],
      ),
    );

    if (result == true) {
      _showSuccess('Senha alterada com sucesso!');
      await _loadConfig();
    }
  }

  Future<void> _grantUnlimitedAccess() async {
    final email = _newUserEmailController.text.trim();

    if (email.isEmpty) {
      _showError('Digite o e-mail do usuário');
      return;
    }

    if (!RegExp(_emailRegex).hasMatch(email)) {
      _showError('E-mail inválido');
      return;
    }

    setState(() => _savingAccess = true);
    try {
      await MasterConfigService.grantUnlimitedAccess(
        userEmail: email,
        grantedBy: _updatedBy,
      );
      _showSuccess('Acesso ilimitado concedido para $email');
      _newUserEmailController.clear();
      await _loadConfig();
    } catch (e) {
      _showError('Erro ao conceder acesso: $e');
    } finally {
      if (mounted) setState(() => _savingAccess = false);
    }
  }

  Future<void> _revokeUnlimitedAccess(String email) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revogar Acesso'),
        content: Text('Deseja remover o acesso ilimitado de $email?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Revogar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _savingRevokeEmail = email);
    try {
      await MasterConfigService.revokeUnlimitedAccess(
        userEmail: email,
        revokedBy: _updatedBy,
      );
      _showSuccess('Acesso revogado de $email');
      await _loadConfig();
    } catch (e) {
      _showError('Erro ao revogar acesso: $e');
    } finally {
      if (mounted) setState(() => _savingRevokeEmail = null);
    }
  }

  Future<void> _grantBulkUnlimitedAccess() async {
    final text = _bulkEmailsController.text;
    final emails = text
        .split(RegExp(r'[\n,;]'))
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty && RegExp(_emailRegex).hasMatch(e))
        .toSet()
        .toList();
    if (emails.isEmpty) {
      _showError('Digite e-mails válidos (um por linha ou separados por vírgula)');
      return;
    }
    setState(() => _savingBulk = true);
    try {
      final added = await MasterConfigService.grantBulkUnlimitedAccess(
        emails: emails,
        grantedBy: _updatedBy,
      );
      _showSuccess('$added usuário(s) adicionado(s) com acesso ilimitado');
      _bulkEmailsController.clear();
      await _loadConfig();
    } catch (e) {
      _showError('Erro ao adicionar: $e');
    } finally {
      if (mounted) setState(() => _savingBulk = false);
    }
  }

  Future<void> _exportConfig() async {
    try {
      final json = await MasterConfigService.exportConfigJson();
      await SharePlus.instance.share(ShareParams(
        text: sanitizeForPlatform(json),
        subject: 'MasterPalm Config Backup',
      ));
    } catch (e) {
      _showError('Erro ao exportar: $e');
    }
  }

  /// Decodifica bytes para String UTF-8 (evita Invalid UTF8 ao enviar para native/share).
  static String _decodeBytesToUtf8String(List<int> bytes) {
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }

  Future<void> _importConfig() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final bytes = result.files.first.bytes;
      if (bytes == null) return;
      final json = _decodeBytesToUtf8String(bytes);
      await MasterConfigService.importConfigJson(json, updatedBy: _updatedBy);
      _showSuccess('Configuração importada');
      await _loadConfig();
    } catch (e) {
      _showError('Erro ao importar: $e');
    }
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFF22C55E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _config == null && _loadError == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Configurações Master')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadError != null && _config == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Configurações Master')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  _loadError!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _loadConfig,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Tentar novamente'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        _resetSessionTimer();
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            • null
            : AppColors.background,
        appBar: AppBar(
        title: const Text('Configurações Master'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadConfig,
            tooltip: 'Recarregar',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadConfig,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            _buildDashboardStats(),
            const SizedBox(height: 24),
            _buildMercadoPagoSection(),
            const SizedBox(height: 24),
            _buildMaintenanceSection(),
            const SizedBox(height: 24),
            _buildUnlimitedAccessSection(),
            const SizedBox(height: 24),
            _buildGlobalSettingsSection(),
            const SizedBox(height: 24),
            _buildFeatureFlagsSection(),
            const SizedBox(height: 24),
            _buildSecuritySection(),
            const SizedBox(height: 24),
            _buildAuditLogSection(),
            const SizedBox(height: 24),
            _buildSystemInfo(),
            const SizedBox(height: 24),
            _buildBackupSection(),
          ],
        ),
      ),
    ));
  }

  Widget _buildDashboardStats() {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.dashboard, color: theme.primaryColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Resumo',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildStatChip(
                  'Acesso ilimitado',
                  '${_config!.usersWithUnlimitedAccess.length}',
                  Icons.people,
                  const Color(0xFF6366F1),
                ),
                _buildStatChip(
                  'Manutenção',
                  _maintenanceMode • 'Ativo' : 'Inativo',
                  Icons.build,
                  _maintenanceMode • const Color(0xFFF59E0B) : const Color(0xFF22C55E),
                ),
                _buildStatChip(
                  'Mercado Pago',
                  _config!.mercadoPagoAccessToken != null • 'OK' : 'Não config',
                  Icons.payment,
                  _config!.mercadoPagoAccessToken != null • const Color(0xFF22C55E) : Colors.grey,
                ),
                _buildStatChip(
                  'Versão',
                  _appVersion,
                  Icons.info_outline,
                  Colors.grey,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha:0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha:0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: color,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(
              Icons.admin_panel_settings,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Painel de Controle Master',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Configurações globais do aplicativo',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),
                  if (_config!.lastUpdated != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Última atualização: ${_formatDate(_config!.lastUpdated!)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[500],
                          ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMercadoPagoSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.payment, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Mercado Pago - Assinaturas',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _mpAccessTokenController,
              obscureText: !_showAccessToken,
              decoration: InputDecoration(
                labelText: 'Access Token',
                prefixIcon: const Icon(Icons.vpn_key),
                border: const OutlineInputBorder(),
                helperText: 'Token de acesso para receber pagamentos',
                suffixIcon: IconButton(
                  icon: Icon(
                    _showAccessToken • Icons.visibility_off : Icons.visibility,
                    size: 22,
                  ),
                  onPressed: () => setState(() => _showAccessToken = !_showAccessToken),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _mpPublicKeyController,
              decoration: const InputDecoration(
                labelText: 'Public Key',
                prefixIcon: Icon(Icons.public),
                border: OutlineInputBorder(),
                helperText: 'Chave pública para checkout',
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _testingMp • null : _testMercadoPagoConnection,
                    icon: _testingMp
                        • const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wifi_tethering),
                    label: Text(_testingMp • 'Testando...' : 'Testar conexão'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _savingMercadoPago • null : _saveMercadoPagoKeys,
                icon: _savingMercadoPago
                    • const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.save),
                      label: Text(_savingMercadoPago • 'Salvando...' : 'Salvar'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor: AppColors.primary,
                      ),
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

  Widget _buildMaintenanceSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.build, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Modo Manutenção',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Quando ativo, usuários veem mensagem de indisponibilidade',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _maintenanceMessageController,
              decoration: const InputDecoration(
                labelText: 'Mensagem para usuários',
                prefixIcon: Icon(Icons.message_outlined),
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _savingMaintenance • null : () async {
                  setState(() => _savingMaintenance = true);
                  _resetSessionTimer();
                  try {
                    await MasterConfigService.setMaintenanceMode(
                      enabled: _maintenanceMode,
                      message: _maintenanceMessageController.text.trim().isEmpty
                          • null
                          : _maintenanceMessageController.text.trim(),
                      updatedBy: _updatedBy,
                    );
                    await _loadConfig();
                    _showSuccess('Mensagem salva');
                  } catch (e) {
                    _showError('Erro: $e');
                  } finally {
                    if (mounted) setState(() => _savingMaintenance = false);
                  }
                },
                icon: const Icon(Icons.save),
                label: const Text('Salvar mensagem'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Ativar modo manutenção'),
              value: _maintenanceMode,
              onChanged: _savingMaintenance
                  • null
                  : (value) async {
                      setState(() => _savingMaintenance = true);
                      _resetSessionTimer();
                      try {
                        await MasterConfigService.setMaintenanceMode(
                          enabled: value,
                          message: _maintenanceMessageController.text.trim().isEmpty
                              • null
                              : _maintenanceMessageController.text.trim(),
                          updatedBy: _updatedBy,
                        );
                        await _loadConfig();
                        _showSuccess(value • 'Modo manutenção ativado' : 'Modo manutenção desativado');
                      } catch (e) {
                        _showError('Erro: $e');
                      } finally {
                        if (mounted) setState(() => _savingMaintenance = false);
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnlimitedAccessSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.all_inclusive, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Usuários com Acesso Ilimitado',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Usuários com acesso ilimitado não precisam de plano ativo',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Buscar por e-mail',
                hintText: 'Digite para filtrar...',
                prefixIcon: Icon(Icons.search, size: 20),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _searchAccess = v.trim().toLowerCase()),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newUserEmailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'E-mail do usuário',
                      prefixIcon: Icon(Icons.person_add),
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _grantUnlimitedAccess(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _savingAccess • null : _grantUnlimitedAccess,
                  icon: _savingAccess
                      • const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.add),
                  label: Text(_savingAccess • '...' : 'Adicionar'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _bulkEmailsController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Adicionar vários (um por linha)',
                hintText: 'email1@exemplo.com\nemail2@exemplo.com',
                prefixIcon: Icon(Icons.list),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _savingBulk • null : _grantBulkUnlimitedAccess,
                icon: _savingBulk
                    • const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_circle_outline),
                label: Text(_savingBulk • 'Adicionando...' : 'Adicionar todos'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Builder(
              builder: (_) {
                final list = _config!.usersWithUnlimitedAccess;
                final filtered = _searchAccess.isEmpty
                    • list
                    : list.where((e) => e.toLowerCase().contains(_searchAccess)).toList();
                if (filtered.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                    child: Center(
                      child: Text(
                        list.isEmpty
                            • 'Nenhum usuário com acesso ilimitado'
                            : 'Nenhum resultado para "$_searchAccess"',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                  );
                }
                return Column(
                  children: filtered.map((email) => ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.person),
                    ),
                    title: Text(email),
                    subtitle: const Text('Acesso ilimitado'),
                    trailing: _savingRevokeEmail == email
                        • const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: _savingRevokeEmail != null
                                • null
                                : () => _revokeUnlimitedAccess(email),
                          ),
                  )).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlobalSettingsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.settings, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Configurações Globais',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _supportPhoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'WhatsApp de Suporte (Ajuda)',
                hintText: '(11) 99999-9999 ou 5511999999999',
                helperText:
                    'Exibido na tela Ajuda. Ao clicar, abre WhatsApp com mensagem pronta',
                prefixIcon: Icon(Icons.chat),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: _savingSupportPhone • null : _saveSupportPhone,
                icon: _savingSupportPhone
                    • const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save, size: 18),
                label: Text(_savingSupportPhone • 'Salvando...' : 'Salvar telefone'),
              ),
            ),
            const Divider(height: 24),
            SwitchListTile(
              title: const Text('Exigir plano para novos usuários'),
              subtitle: const Text(
                'Novos usuários precisam assinar um plano para usar o app',
              ),
              value: _config!.requirePlanForNewUsers,
              onChanged: _savingSwitch
                  • null
                  : (value) async {
                      setState(() => _savingSwitch = true);
                      _resetSessionTimer();
                      try {
                        final updated = _config!.copyWith(requirePlanForNewUsers: value);
                        await MasterConfigService.saveMasterConfig(
                          updated,
                          updatedBy: _updatedBy,
                          auditAction: 'Exigir plano alterado',
                          auditDetails: value • 'Sim' : 'Não',
                        );
                        await _loadConfig();
                        _showSuccess('Configuração atualizada');
                      } catch (e) {
                        _showError('Erro ao atualizar: $e');
                      } finally {
                        if (mounted) setState(() => _savingSwitch = false);
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureFlagsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.flag, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Feature Flags',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Ative ou desative funcionalidades sem novo deploy',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Catálogo Web'),
              subtitle: const Text('Página de catálogo para clientes'),
              value: _featureFlags['catalogoWeb'] ?• true,
              onChanged: _savingFeatureFlags
                  • null
                  : (v) => _toggleFeatureFlag('catalogoWeb', v),
            ),
            SwitchListTile(
              title: const Text('Cupons'),
              subtitle: const Text('Sistema de cupons de desconto'),
              value: _featureFlags['cupons'] ?• true,
              onChanged: _savingFeatureFlags
                  • null
                  : (v) => _toggleFeatureFlag('cupons', v),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveSupportPhone() async {
    setState(() => _savingSupportPhone = true);
    _resetSessionTimer();
    try {
      await MasterConfigService.setSupportPhone(
        phone: _supportPhoneController.text,
        updatedBy: _updatedBy,
      );
      _showSuccess('Telefone de suporte salvo');
    } catch (e) {
      _showError('Erro ao salvar: $e');
    } finally {
      if (mounted) setState(() => _savingSupportPhone = false);
    }
  }

  Future<void> _toggleFeatureFlag(String key, bool value) async {
    setState(() => _savingFeatureFlags = true);
    try {
      await MasterConfigService.setFeatureFlag(
        key: key,
        value: value,
        updatedBy: _updatedBy,
      );
      await _loadConfig();
      _showSuccess('Feature flag atualizada');
    } catch (e) {
      _showError('Erro: $e');
    } finally {
      if (mounted) setState(() => _savingFeatureFlags = false);
    }
  }

  Widget _buildSecuritySection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.security, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Segurança',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.lock),
              title: const Text('Alterar Senha Master'),
              subtitle: const Text('Modificar senha de acesso master'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
              _resetSessionTimer();
              _changePassword();
            },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuditLogSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Log de Auditoria',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Histórico de alterações recentes',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  _resetSessionTimer();
                  final log = await MasterConfigService.getAuditLog();
                  if (!mounted) return;
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Log de Auditoria'),
                      content: SizedBox(
                        width: double.maxFinite,
                        child: log.isEmpty
                            • const Text('Nenhum registro')
                            : ListView.builder(
                                shrinkWrap: true,
                                itemCount: log.length,
                                itemBuilder: (_, i) {
                                  final e = log[i];
                                  final ts = e['timestamp'] as String?;
                                  final action = e['action'] as String• ?• '';
                                  final user = e['user'] as String• ?• '';
                                  final details = e['details'] as String• ?• '';
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          action,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                          ),
                                        ),
                                        if (details.isNotEmpty)
                                          Text(details, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                                        Text(
                                          '$user • ${ts != null • ts.substring(0, 16).replaceAll('T', ' ') : ''}',
                                          style: TextStyle(color: Colors.grey[500], fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Fechar'),
                        ),
                      ],
                    ),
                  );
                },
                icon: const Icon(Icons.history),
                label: const Text('Ver histórico'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemInfo() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Informações do Sistema',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInfoRow('Versão do app', _appVersion),
            _buildInfoRow('Última atualização',
                _config!.lastUpdated != null • _formatDate(_config!.lastUpdated!) : 'N/A'),
            _buildInfoRow('Atualizado por', _config!.updatedBy ?• 'Sistema'),
            _buildInfoRow('Usuários com acesso ilimitado',
                _config!.usersWithUnlimitedAccess.length.toString()),
            _buildInfoRow(
              'Mercado Pago configurado',
              _config!.mercadoPagoAccessToken != null • 'Sim' : 'Não',
            ),
            _buildInfoRow('Modo manutenção', _maintenanceMode • 'Ativo' : 'Inativo'),
          ],
        ),
      ),
    );
  }

  Widget _buildBackupSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.backup, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Backup e Restauração',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Exporte ou importe configurações (sem dados sensíveis)',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _exportConfig,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Exportar'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _importConfig,
                    icon: const Icon(Icons.download),
                    label: const Text('Importar'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
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

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.grey[600]),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

