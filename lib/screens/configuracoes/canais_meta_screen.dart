// ARQUIVO: lib/screens/configuracoes/canais_meta_screen.dart
// Tela de configuração dos canais Meta (WhatsApp, Instagram, Messenger)
// Modelo SaaS: Cada loja conecta seus próprios tokens

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import '../../services/loja_id_service.dart';

part 'canais_meta_widgets.dart';

class CanaisMetaScreen extends StatefulWidget {
  const CanaisMetaScreen({super.key});

  @override
  State<CanaisMetaScreen> createState() => _CanaisMetaScreenState();
}

class _CanaisMetaScreenState extends State<CanaisMetaScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;
  bool _savingWhatsApp = false;
  bool _savingInstagram = false;
  bool _savingMessenger = false;

  // Cores do tema moderno
  static const Color _primaryColor = Color(0xFF6366F1); // Indigo
  static const Color _successColor = Color(0xFF22C55E); // Green
  static const Color _errorColor = Color(0xFFEF4444); // Red
  static const Color _whatsappColor = Color(0xFF25D366); // WhatsApp Green
  static const Color _instagramColor = Color(0xFFE4405F); // Instagram Pink
  static const Color _messengerColor = Color(0xFF0084FF); // Messenger Blue

  // === WhatsApp ===
  final _whatsappPhoneNumberIdController = TextEditingController();
  final _whatsappBusinessAccountIdController = TextEditingController();
  final _whatsappAccessTokenController = TextEditingController();
  final _whatsappTemplateNameController = TextEditingController();
  bool _whatsappEnabled = false;
  String? _whatsappStatus;
  bool _whatsappTokenVisible = false;

  // === Instagram ===
  final _instagramBusinessAccountIdController = TextEditingController();
  final _instagramPageIdController = TextEditingController();
  final _instagramPageAccessTokenController = TextEditingController();
  bool _instagramEnabled = false;
  String? _instagramStatus;
  bool _instagramTokenVisible = false;

  // === Messenger ===
  final _messengerPageIdController = TextEditingController();
  final _messengerPageAccessTokenController = TextEditingController();
  bool _messengerEnabled = false;
  String? _messengerStatus;
  bool _messengerTokenVisible = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadConfigs();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _whatsappPhoneNumberIdController.dispose();
    _whatsappBusinessAccountIdController.dispose();
    _whatsappAccessTokenController.dispose();
    _whatsappTemplateNameController.dispose();
    _instagramBusinessAccountIdController.dispose();
    _instagramPageIdController.dispose();
    _instagramPageAccessTokenController.dispose();
    _messengerPageIdController.dispose();
    _messengerPageAccessTokenController.dispose();
    super.dispose();
  }

  // ========== CARREGAR CONFIGURAÇÕES ==========
  Future<void> _loadConfigs() async {
    if (mounted) setState(() => _isLoading = true);

    try {
      final lojaId = await LojaIdService.get();

      if (lojaId == null || lojaId.isEmpty) {
        _showError('Loja não identificada. Faça login novamente.');
        return;
      }

      final db = FirebaseFirestore.instance;

      // Carregar WhatsApp
      try {
        final whatsappDoc = await db
            .collection('lojas')
            .doc(lojaId)
            .collection('canais')
            .doc('whatsapp')
            .get();

        if (whatsappDoc.exists) {
          final data = whatsappDoc.data()!;
          setState(() {
            _whatsappEnabled = data['enabled'] ?? false;
            _whatsappPhoneNumberIdController.text = data['phone_number_id'] ?? '';
            _whatsappBusinessAccountIdController.text =
                data['business_account_id'] ?? '';
            _whatsappAccessTokenController.text = data['access_token'] ?? '';
            _whatsappTemplateNameController.text =
                data['messageTemplates']?['outside24h_template_name'] ?? '';
          });
        }
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied') {
          debugPrint('?? Sem permissão para ler WhatsApp config - continuando...');
          setState(() => _whatsappStatus = 'Sem permissão para visualizar');
        } else {
          debugPrint('Erro ao carregar WhatsApp: ${e.message}');
        }
      } catch (e) {
        debugPrint('Erro inesperado ao carregar WhatsApp (type=${e.runtimeType})');
      }

      // Carregar Instagram
      try {
        final instagramDoc = await db
            .collection('lojas')
            .doc(lojaId)
            .collection('canais')
            .doc('instagram')
            .get();

        if (instagramDoc.exists) {
          final data = instagramDoc.data()!;
          setState(() {
            _instagramEnabled = data['enabled'] ?? false;
            _instagramBusinessAccountIdController.text =
                data['ig_business_account_id'] ?? '';
            _instagramPageIdController.text = data['page_id'] ?? '';
            _instagramPageAccessTokenController.text =
                data['page_access_token'] ?? '';
          });
        }
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied') {
          debugPrint('?? Sem permissão para ler Instagram config - continuando...');
          setState(() => _instagramStatus = 'Sem permissão para visualizar');
        } else {
          debugPrint('Erro ao carregar Instagram: ${e.message}');
        }
      } catch (e) {
        debugPrint('Erro inesperado ao carregar Instagram (type=${e.runtimeType})');
      }

      // Carregar Messenger
      try {
        final messengerDoc = await db
            .collection('lojas')
            .doc(lojaId)
            .collection('canais')
            .doc('messenger')
            .get();

        if (messengerDoc.exists) {
          final data = messengerDoc.data()!;
          setState(() {
            _messengerEnabled = data['enabled'] ?? false;
            _messengerPageIdController.text = data['page_id'] ?? '';
            _messengerPageAccessTokenController.text =
                data['page_access_token'] ?? '';
          });
        }
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied') {
          debugPrint('?? Sem permissão para ler Messenger config - continuando...');
          setState(() => _messengerStatus = 'Sem permissão para visualizar');
        } else {
          debugPrint('Erro ao carregar Messenger: ${e.message}');
        }
      } catch (e) {
        debugPrint('Erro inesperado ao carregar Messenger (type=${e.runtimeType})');
      }
    } catch (e) {
      debugPrint('Erro geral ao carregar configurações (type=${e.runtimeType})');
      // Não mostrar erro ao usuário se for apenas falta de permissão individual
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ========== WHATSAPP ==========
  Future<void> _saveWhatsAppConfig() async {
    if (!_validateWhatsAppFields()) return;

    setState(() => _savingWhatsApp = true);

    try {
      final lojaId = await LojaIdService.get();

      if (lojaId == null || lojaId.isEmpty) {
        throw Exception('Loja não identificada');
      }

      await FirebaseFirestore.instance
          .collection('lojas')
          .doc(lojaId)
          .collection('canais')
          .doc('whatsapp')
          .set({
        'enabled': _whatsappEnabled,
        'phone_number_id': _whatsappPhoneNumberIdController.text.trim(),
        'business_account_id':
            _whatsappBusinessAccountIdController.text.trim(),
        'access_token': _whatsappAccessTokenController.text.trim(),
        'verify_token': 'masterpalm_verify_2026',
        'messageTemplates': {
          'outside24h_template_name':
              _whatsappTemplateNameController.text.trim(),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      });

      setState(() {
        _whatsappStatus = '✅ Configuração salva com sucesso!';
      });

      _showSuccess('WhatsApp configurado com sucesso!');
    } catch (e) {
      setState(() {
        _whatsappStatus = '❌ Erro ao salvar: $e';
      });
      _showError('Erro ao salvar: $e');
    } finally {
      if (mounted) setState(() => _savingWhatsApp = false);
    }
  }

  Future<void> _testWhatsAppConnection() async {
    if (!_validateWhatsAppFields()) return;

    setState(() => _isLoading = true);

    try {
      final phoneNumberId = _whatsappPhoneNumberIdController.text.trim();
      final accessToken = _whatsappAccessTokenController.text.trim();

      // GET /{phone-number-id} valida o token sem enviar mensagem
      final url = Uri.parse(
          'https://graph.facebook.com/v18.0/$phoneNumberId?fields=verified_name,display_phone_number');

      debugPrint('🔎 Testando WhatsApp: $url');

      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
      );

      debugPrint('🔎 Resposta: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        setState(() {
          _whatsappStatus = '✅ Conexão OK! Credenciais válidas.';
        });
        _showSuccess('Conexão estabelecida com sucesso!');
      } else {
        final body = response.body;
        String? errorMsg;
        try {
          final error = jsonDecode(body) as Map<String, dynamic>;
          errorMsg = error['error']?['message'] ?? body;
        } catch (_) {
          errorMsg = body;
        }
        throw Exception('Erro ${response.statusCode}: $errorMsg');
      }
    } catch (e) {
      setState(() {
        _whatsappStatus = '❌ Falha: $e';
      });
      _showError('Erro na conexão: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  bool _validateWhatsAppFields() {
    if (_whatsappPhoneNumberIdController.text.trim().isEmpty) {
      _showError('Phone Number ID é obrigatório');
      return false;
    }
    if (_whatsappBusinessAccountIdController.text.trim().isEmpty) {
      _showError('Business Account ID é obrigatório');
      return false;
    }
    if (_whatsappAccessTokenController.text.trim().isEmpty) {
      _showError('Access Token é obrigatório');
      return false;
    }
    return true;
  }

  // ========== INSTAGRAM ==========
  Future<void> _saveInstagramConfig() async {
    if (!_validateInstagramFields()) return;

    setState(() => _savingInstagram = true);

    try {
      final lojaId = await LojaIdService.get();

      if (lojaId == null || lojaId.isEmpty) {
        throw Exception('Loja não identificada');
      }

      await FirebaseFirestore.instance
          .collection('lojas')
          .doc(lojaId)
          .collection('canais')
          .doc('instagram')
          .set({
        'enabled': _instagramEnabled,
        'ig_business_account_id':
            _instagramBusinessAccountIdController.text.trim(),
        'page_id': _instagramPageIdController.text.trim(),
        'page_access_token': _instagramPageAccessTokenController.text.trim(),
        'verify_token': 'masterpalm_verify_2026',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      setState(() {
        _instagramStatus = '✅ Configuração salva com sucesso!';
      });

      _showSuccess('Instagram configurado com sucesso!');
    } catch (e) {
      setState(() {
        _instagramStatus = '❌ Erro ao salvar: $e';
      });
      _showError('Erro ao salvar: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _testInstagramConnection() async {
    if (!_validateInstagramFields()) return;

    setState(() => _isLoading = true);

    try {
      final pageId = _instagramPageIdController.text.trim();
      final accessToken = _instagramPageAccessTokenController.text.trim();

      final url = Uri.parse(
          'https://graph.facebook.com/v18.0/$pageId?fields=name,access_token');

      debugPrint('🔎 Testando Instagram: $url');

      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      debugPrint('🔎 Resposta: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        setState(() {
          _instagramStatus = '✅ Conexão OK! Credenciais válidas.';
        });
        _showSuccess('Conexão estabelecida com sucesso!');
      } else {
        final body = response.body;
        String? errorMsg;
        try {
          final error = jsonDecode(body) as Map<String, dynamic>;
          errorMsg = error['error']?['message'] ?? body;
        } catch (_) {
          errorMsg = body;
        }
        throw Exception('Erro ${response.statusCode}: $errorMsg');
      }
    } catch (e) {
      setState(() {
        _instagramStatus = '❌ Falha: $e';
      });
      _showError('Erro na conexão: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _testMessengerConnection() async {
    if (!_validateMessengerFields()) return;

    setState(() => _isLoading = true);

    try {
      final pageId = _messengerPageIdController.text.trim();
      final accessToken = _messengerPageAccessTokenController.text.trim();

      final url = Uri.parse(
          'https://graph.facebook.com/v18.0/$pageId?fields=name,access_token');

      debugPrint('🔎 Testando Messenger: $url');

      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      debugPrint('🔎 Resposta: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        setState(() {
          _messengerStatus = '✅ Conexão OK! Credenciais válidas.';
        });
        _showSuccess('Conexão estabelecida com sucesso!');
      } else {
        final body = response.body;
        String? errorMsg;
        try {
          final error = jsonDecode(body) as Map<String, dynamic>;
          errorMsg = error['error']?['message'] ?? body;
        } catch (_) {
          errorMsg = body;
        }
        throw Exception('Erro ${response.statusCode}: $errorMsg');
      }
    } catch (e) {
      setState(() {
        _messengerStatus = '❌ Falha: $e';
      });
      _showError('Erro na conexão: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  bool _validateInstagramFields() {
    if (_instagramBusinessAccountIdController.text.trim().isEmpty) {
      _showError('Instagram Business Account ID é obrigatório');
      return false;
    }
    if (_instagramPageIdController.text.trim().isEmpty) {
      _showError('Page ID é obrigatório');
      return false;
    }
    if (_instagramPageAccessTokenController.text.trim().isEmpty) {
      _showError('Page Access Token é obrigatório');
      return false;
    }
    return true;
  }

  // ========== MESSENGER ==========
  Future<void> _saveMessengerConfig() async {
    if (!_validateMessengerFields()) return;

    setState(() => _savingMessenger = true);

    try {
      final lojaId = await LojaIdService.get();

      if (lojaId == null || lojaId.isEmpty) {
        throw Exception('Loja não identificada');
      }

      await FirebaseFirestore.instance
          .collection('lojas')
          .doc(lojaId)
          .collection('canais')
          .doc('messenger')
          .set({
        'enabled': _messengerEnabled,
        'page_id': _messengerPageIdController.text.trim(),
        'page_access_token': _messengerPageAccessTokenController.text.trim(),
        'verify_token': 'masterpalm_verify_2026',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      setState(() {
        _messengerStatus = '✅ Configuração salva com sucesso!';
      });

      _showSuccess('Messenger configurado com sucesso!');
    } catch (e) {
      setState(() {
        _messengerStatus = '❌ Erro ao salvar: $e';
      });
      _showError('Erro ao salvar: $e');
    } finally {
      if (mounted) setState(() => _savingMessenger = false);
    }
  }

  bool _validateMessengerFields() {
    if (_messengerPageIdController.text.trim().isEmpty) {
      _showError('Page ID é obrigatório');
      return false;
    }
    if (_messengerPageAccessTokenController.text.trim().isEmpty) {
      _showError('Page Access Token é obrigatório');
      return false;
    }
    return true;
  }

  // ========== HELPERS ==========
  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: _successColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: _errorColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    _showSuccess('$label copiado!');
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _showError('Não foi possível abrir o link');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Canais de Comunicação',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: _primaryColor,
            child: TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              tabs: const [
                Tab(icon: Icon(Icons.chat, size: 20), text: 'WhatsApp'),
                Tab(icon: Icon(Icons.camera_alt, size: 20), text: 'Instagram'),
                Tab(icon: Icon(Icons.messenger, size: 20), text: 'Messenger'),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: _showGeneralHelp,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _primaryColor))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildWhatsAppTab(),
                _buildInstagramTab(),
                _buildMessengerTab(),
              ],
            ),
    );
  }

  void _setWhatsAppEnabled(bool v) => setState(() => _whatsappEnabled = v);
  void _setWhatsAppTokenVisible(bool v) => setState(() => _whatsappTokenVisible = v);
  void _setInstagramEnabled(bool v) => setState(() => _instagramEnabled = v);
  void _setInstagramTokenVisible(bool v) => setState(() => _instagramTokenVisible = v);
  void _setMessengerEnabled(bool v) => setState(() => _messengerEnabled = v);
  void _setMessengerTokenVisible(bool v) => setState(() => _messengerTokenVisible = v);

  // ========== DIÁLOGOS DE AJUDA ==========
  void _showGeneralHelp() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final csSheet = Theme.of(context).colorScheme;
        return Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: csSheet.surfaceContainerHighest,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: csSheet.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _primaryColor.withValues(alpha:0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.help_outline, color: _primaryColor),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ajuda - Canais Meta',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: csSheet.onSurface,
                          ),
                        ),
                        Text(
                          'Como funciona a integração',
                          style: TextStyle(color: csSheet.onSurfaceVariant, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHelpSection(
                      icon: Icons.phone_android,
                      title: 'O que são os Canais Meta?',
                      content:
                          'WhatsApp, Instagram e Messenger são canais de comunicação da Meta que permitem responder automaticamente seus clientes.',
                    ),
                    const SizedBox(height: 20),
                    _buildHelpSection(
                      icon: Icons.attach_money,
                      title: 'Modelo SaaS',
                      content:
                          'Você conecta seus próprios tokens e paga os custos diretamente à Meta. O MasterPalm fornece apenas a plataforma de automação.',
                    ),
                    const SizedBox(height: 20),
                    _buildHelpSection(
                      icon: Icons.settings,
                      title: 'Como funciona?',
                      content:
                          '1. Configure cada canal nas abas acima\n2. O bot responderá automaticamente\n3. Consultas de preço, estoque, fotos, etc.\n4. Handover para atendente humano\n5. Respeita horário de funcionamento',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
  }

  Widget _buildHelpSection({
    required IconData icon,
    required String title,
    required String content,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _primaryColor, size: 24),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            content,
            style: TextStyle(
              color: Colors.grey[700],
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  void _showWhatsAppGuide() {
    _showGuideBottomSheet(
      title: 'Como Configurar WhatsApp',
      color: _whatsappColor,
      steps: [
        'Acesse Meta Developers (developers.facebook.com/apps)',
        'Crie um app Business',
        'Adicione o produto WhatsApp',
        'Configure o Webhook URL (copie da tela)',
        'Inscreva nos eventos: messages',
        'Copie Phone Number ID e Business Account ID',
        'Gere o Access Token',
        'Cole os valores nos campos acima',
        'Clique em "Salvar Configurações"',
        'Teste enviando uma mensagem',
      ],
    );
  }

  void _showInstagramGuide() {
    _showGuideBottomSheet(
      title: 'Como Configurar Instagram',
      color: _instagramColor,
      steps: [
        'Acesse Meta Developers',
        'No mesmo app, adicione Instagram',
        'Conecte sua conta Instagram Business',
        'Configure o Webhook URL (copie da tela)',
        'Inscreva nos eventos: messages',
        'Copie Instagram Business Account ID e Page ID',
        'Gere Page Access Token',
        'Cole os valores nos campos acima',
        'Clique em "Salvar"',
      ],
    );
  }

  void _showMessengerGuide() {
    _showGuideBottomSheet(
      title: 'Como Configurar Messenger',
      color: _messengerColor,
      steps: [
        'Crie uma Página no Facebook',
        'Acesse Meta Developers',
        'No mesmo app, adicione Messenger',
        'Conecte à página criada',
        'Configure o Webhook URL',
        'Inscreva nos eventos: messages',
        'Copie Page ID',
        'Gere Page Access Token',
        'Cole os valores nos campos acima',
        'Clique em "Salvar"',
      ],
    );
  }

  void _showGuideBottomSheet({
    required String title,
    required Color color,
    required List<String> steps,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha:0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.help_outline, color: color),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: steps.length,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          steps[index],
                          style: const TextStyle(
                            fontSize: 15,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                border: Border(top: BorderSide(color: Colors.grey[200]!)),
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _openUrl('https://developers.facebook.com/apps');
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Abrir Meta Developers'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.all(16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Delegate to extension methods
  Widget _buildWhatsAppTab() => _buildWhatsAppTabImpl();
  Widget _buildInstagramTab() => _buildInstagramTabImpl();
  Widget _buildMessengerTab() => _buildMessengerTabImpl();
}

