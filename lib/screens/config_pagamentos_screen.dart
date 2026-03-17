import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/loja_id_service.dart';
import '../services/pagamentos_service.dart';
import '../services/payment_gateway_service.dart';
import '../services/sync_firestore_script.dart';
import '../services/catalogo_sync_service.dart';
import 'package:hive/hive.dart';
import 'package:url_launcher/url_launcher.dart';

class ConfigPagamentosScreen extends StatefulWidget {
  const ConfigPagamentosScreen({super.key});

  @override
  State<ConfigPagamentosScreen> createState() => _ConfigPagamentosScreenState();
}

class _ConfigPagamentosScreenState extends State<ConfigPagamentosScreen>
    with SingleTickerProviderStateMixin {
  // ==================== CORES DO TEMA ====================
  static const Color primaryColor = Color(0xFF6366F1);
  static const Color secondaryColor = Color(0xFF8B5CF6);
  static const Color successColor = Color(0xFF22C55E);
  static const Color warningColor = Color(0xFFF59E0B);
  static const Color errorColor = Color(0xFFEF4444);
  static const Color surfaceColor = Color(0xFFF8FAFC);
  static const Color cardColor = Colors.white;

  String? _lojaId;
  bool _sincronizando = false;
  bool _publicando = false;

  // Mercado Pago
  final _publicKeyCtrl = TextEditingController();

  // PagSeguro
  final _pagseguroTokenCtrl = TextEditingController();
  final _pagseguroSellerIdCtrl = TextEditingController();

  // Ton
  final _tonClientIdCtrl = TextEditingController();
  final _tonClientSecretCtrl = TextEditingController();

  // InfinitePay
  final _infinitApiKeyCtrl = TextEditingController();
  final _infinitMerchantIdCtrl = TextEditingController();

  // Checkout do cat�logo / site
  final _pixKeyCtrl = TextEditingController();
  final _jurosParcelamentoCtrl = TextEditingController(text: '1.99');
  final _maxParcelasCtrl = TextEditingController(text: '12');
  String _gatewayPadrao = 'whatsapp';
  bool _checkoutLoaded = false;

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
    _loadLoja();
  }

  /// ✅ Multi-loja: LojaIdService primeiro (StoreResolver), Hive apenas fallback offline
  Future<void> _loadLoja() async {
    try {
      String? storeId = (await LojaIdService.get())?.trim();
      if (storeId == null || storeId.isEmpty) {
        final box = await Hive.openBox('config');
        storeId = box.get('store_id')?.toString().trim();
      }

      if (!mounted) return;
      setState(() => _lojaId = storeId);
      _animationController.forward();
    } catch (e) {
      if (!mounted) return;
      setState(() => _lojaId = null);
      debugPrint('Erro ao carregar loja (type=${e.runtimeType})');
    }
  }

  @override
  void dispose() {
    _publicKeyCtrl.dispose();
    _pagseguroTokenCtrl.dispose();
    _pagseguroSellerIdCtrl.dispose();
    _tonClientIdCtrl.dispose();
    _tonClientSecretCtrl.dispose();
    _infinitApiKeyCtrl.dispose();
    _infinitMerchantIdCtrl.dispose();
    _pixKeyCtrl.dispose();
    _jurosParcelamentoCtrl.dispose();
    _maxParcelasCtrl.dispose();
    _animationController.dispose();
    super.dispose();
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

  Future<void> _abrirUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      _mostrarSnackBarModerno(
        'N�o foi poss�vel abrir o link',
        Icons.error_outline,
        errorColor,
      );
    }
  }

  Future<void> _validarGateway(String gateway) async {
    if (_lojaId == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: primaryColor),
              SizedBox(height: 16),
              Text('Validando conex�o...'),
            ],
          ),
        ),
      ),
    );

    final validacao = await PaymentGatewayService.validarConfiguracoes(
      lojaId: _lojaId!,
    );

    if (!mounted) return;
    Navigator.pop(context);

    final isValido = validacao[gateway] ?? false;

    _mostrarResultadoValidacao(gateway, isValido);
  }

  void _mostrarResultadoValidacao(String gateway, bool isValido) {
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
                color: isValido
                    ? successColor.withValues(alpha:0.1)
                    : errorColor.withValues(alpha:0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isValido ? Icons.check_circle : Icons.error_outline,
                color: isValido ? successColor : errorColor,
                size: 48,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isValido ? 'Conex�o Validada!' : 'Falha na Valida��o',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isValido ? successColor : errorColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isValido
                  ? 'As credenciais do $gateway est�o corretas e funcionando!'
                  : 'N�o foi poss�vel validar as credenciais do $gateway.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            if (!isValido) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: warningColor.withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.lightbulb_outline,
                            color: warningColor, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Poss�veis causas:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[800],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildDicaItem('Token de TESTE ao inv�s de PRODU��O'),
                    _buildDicaItem('Access Token expirado ou inv�lido'),
                    _buildDicaItem('Sem conex�o com a internet'),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Entendi',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDicaItem(String texto) {
    return Padding(
      padding: const EdgeInsets.only(left: 28, top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('� ', style: TextStyle(color: Colors.grey[700])),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarGuia(String gateway) {
    String titulo = '';
    IconData icone = Icons.help_outline;
    Color cor = primaryColor;
    List<Map<String, dynamic>> passos = [];

    switch (gateway) {
      case 'mercadopago':
        titulo = 'Como Conectar Mercado Pago';
        icone = Icons.account_balance_wallet;
        cor = const Color(0xFF00BCFF);
        passos = [
          {'icon': Icons.touch_app, 'text': 'Toque em "Obter Credenciais"'},
          {'icon': Icons.login, 'text': 'Fa�a login na sua conta Mercado Pago'},
          {'icon': Icons.apps, 'text': 'Clique em "Suas integra��es"'},
          {
            'icon': Icons.folder_open,
            'text': 'Selecione uma aplica��o existente OU crie uma nova'
          },
          {
            'icon': Icons.vpn_key,
            'text': 'Copie o ACCESS TOKEN de PRODU��O (APP_USR-)'
          },
          {'icon': Icons.arrow_back, 'text': 'Volte para este app'},
          {'icon': Icons.content_paste, 'text': 'Cole o token no campo abaixo'},
          {'icon': Icons.save, 'text': 'Toque em "Conectar Mercado Pago"'},
        ];
        break;

      case 'pagseguro':
        titulo = 'Como Configurar PagSeguro';
        icone = Icons.credit_card;
        cor = const Color(0xFF00A859);
        passos = [
          {'icon': Icons.touch_app, 'text': 'Toque em "Gerar Token"'},
          {'icon': Icons.login, 'text': 'Fa�a login no PagSeguro'},
          {
            'icon': Icons.settings,
            'text': 'V� em "Integra��es" ? "Token de Seguran�a"'
          },
          {'icon': Icons.add_circle, 'text': 'Clique em "Gerar novo token"'},
          {'icon': Icons.copy, 'text': 'Copie o token gerado'},
          {'icon': Icons.content_paste, 'text': 'Cole o token no campo abaixo'},
          {
            'icon': Icons.email,
            'text': 'Digite seu email no campo "Seller ID"'
          },
          {'icon': Icons.save, 'text': 'Toque em "Salvar"'},
        ];
        break;

      case 'ton':
        titulo = 'Como Configurar Ton';
        icone = Icons.point_of_sale;
        cor = const Color(0xFF00D4AA);
        passos = [
          {'icon': Icons.touch_app, 'text': 'Toque em "Portal Desenvolvedor"'},
          {'icon': Icons.login, 'text': 'Fa�a login na Ton'},
          {'icon': Icons.apps, 'text': 'V� em "Aplica��es"'},
          {'icon': Icons.add_circle, 'text': 'Clique em "Nova Aplica��o"'},
          {'icon': Icons.edit, 'text': 'D� um nome (ex: "MasterPalm")'},
          {'icon': Icons.copy, 'text': 'Copie o Client ID e Client Secret'},
          {'icon': Icons.content_paste, 'text': 'Cole nos campos abaixo'},
          {'icon': Icons.save, 'text': 'Toque em "Salvar"'},
        ];
        break;

      case 'infinitepay':
        titulo = 'Como Configurar InfinitePay';
        icone = Icons.payments;
        cor = const Color(0xFFFF6B35);
        passos = [
          {'icon': Icons.touch_app, 'text': 'Toque em "Gerar API Key"'},
          {'icon': Icons.login, 'text': 'Fa�a login no InfinitePay'},
          {'icon': Icons.settings, 'text': 'Acesse "Configura��es" ? "API"'},
          {'icon': Icons.add_circle, 'text': 'Clique em "Gerar nova chave"'},
          {'icon': Icons.copy, 'text': 'Copie a API Key e o Merchant ID'},
          {'icon': Icons.content_paste, 'text': 'Cole nos campos abaixo'},
          {'icon': Icons.save, 'text': 'Toque em "Salvar"'},
        ];
        break;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
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
                      color: cor.withValues(alpha:0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icone, color: cor, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      titulo,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Passos
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.all(20),
                itemCount: passos.length,
                itemBuilder: (context, index) {
                  final passo = passos[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: cor.withValues(alpha:0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: cor,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: surfaceColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  passo['icon'] as IconData,
                                  color: Colors.grey[600],
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    passo['text'] as String,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF1E293B),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            // Bot�o
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Entendi',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
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

  Future<void> _sincronizarTudo() async {
    if (_sincronizando || _lojaId == null) return;
    setState(() => _sincronizando = true);
    try {
      final results = await SyncFirestoreScript.syncTudo();
      if (!mounted) return;
      if (results['success'] == true) {
        final p = results['produtos'] as Map<String, int>? ?? {};
        final c = results['clientes'] as Map<String, int>? ?? {};
        _mostrarSnackBarModerno(
          'Sincronizado: ${p['synced'] ?? 0} produtos, ${c['synced'] ?? 0} clientes',
          Icons.cloud_done,
          successColor,
        );
      } else {
        final err = results['errors'] as List<dynamic>?;
        _mostrarSnackBarModerno(
          err != null && err.isNotEmpty ? err.first.toString() : 'Erro na sincroniza��o',
          Icons.error_outline,
          errorColor,
        );
      }
    } catch (e) {
      if (mounted) {
        _mostrarSnackBarModerno('Erro ao sincronizar: $e', Icons.error_outline, errorColor);
      }
    } finally {
      if (mounted) setState(() => _sincronizando = false);
    }
  }

  Future<void> _publicarCatalogo() async {
    if (_publicando || _lojaId == null) return;
    setState(() => _publicando = true);
    try {
      await CatalogoSyncService.pushAllToLive(lojaIdOverride: _lojaId);
      if (!mounted) return;
      _mostrarSnackBarModerno('Cat�logo publicado com sucesso!', Icons.cloud_done, successColor);
    } catch (e) {
      if (mounted) {
        _mostrarSnackBarModerno('Erro ao publicar: $e', Icons.error_outline, errorColor);
      }
    } finally {
      if (mounted) setState(() => _publicando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_lojaId == null) {
      return Scaffold(
        backgroundColor: surfaceColor,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha:0.1),
                  shape: BoxShape.circle,
                ),
                child: const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Carregando configura��es...',
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

    return Scaffold(
      backgroundColor: surfaceColor,
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: PagamentosService.paymentsDocStream(_lojaId!),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: primaryColor),
            );
          }

          final data = snap.data?.data() ?? <String, dynamic>{};

          // Extrair dados de cada gateway
          final mp = (data['mp'] as Map<String, dynamic>?) ?? {};
          final connectedMp = mp['connected'] == true;
          final userIdMp = (mp['user_id'] ?? '').toString();
          final publicKeyMp = (mp['public_key'] ?? '').toString();

          // Mantido para quando reativar gateways (PagSeguro, Ton, InfinitePay)
          final pagseguro = (data['pagseguro'] as Map<String, dynamic>?) ?? {};
          final pagseguroToken = (pagseguro['token'] ?? '').toString();
          final pagseguroSellerId = (pagseguro['seller_id'] ?? '').toString();
          // ignore: unused_local_variable
          final pagseguroConfigured = pagseguroToken.isNotEmpty;

          final ton = (data['ton'] as Map<String, dynamic>?) ?? {};
          final tonClientId = (ton['client_id'] ?? '').toString();
          final tonClientSecret = (ton['client_secret'] ?? '').toString();
          // ignore: unused_local_variable
          final tonConfigured = tonClientId.isNotEmpty;

          final infinit = (data['infinitpay'] as Map<String, dynamic>?) ?? {};
          final infinitApiKey = (infinit['api_key'] ?? '').toString();
          final infinitMerchantId = (infinit['merchant_id'] ?? '').toString();
          // ignore: unused_local_variable
          final infinitConfigured = infinitApiKey.isNotEmpty;

          final checkout = (data['checkout'] as Map<String, dynamic>?) ?? {};
          final checkoutGatewayRaw =
              (checkout['gateway'] ?? checkout['gatewayPadrao'] ?? 'whatsapp')
                  .toString();
          final pixKey =
              (checkout['pixKey'] ?? checkout['chavePix'] ?? '').toString();
          final jurosParcelamento =
              (checkout['jurosParcelamento'] ?? 1.99).toString();
          final maxParcelas = (checkout['maxParcelas'] ?? 12).toString();

          // Preencher controllers
          void setIfEmpty(TextEditingController c, String v) {
            if (c.text.isEmpty && v.isNotEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                c.text = v;
              });
            }
          }

          setIfEmpty(_publicKeyCtrl, publicKeyMp);
          setIfEmpty(_pagseguroTokenCtrl, pagseguroToken);
          setIfEmpty(_pagseguroSellerIdCtrl, pagseguroSellerId);
          setIfEmpty(_tonClientIdCtrl, tonClientId);
          setIfEmpty(_tonClientSecretCtrl, tonClientSecret);
          setIfEmpty(_infinitApiKeyCtrl, infinitApiKey);
          setIfEmpty(_infinitMerchantIdCtrl, infinitMerchantId);

          if (!_checkoutLoaded) {
            var gateway = checkoutGatewayRaw;
            if (gateway == 'infinitpay') gateway = 'infinitepay';
            _gatewayPadrao = gateway;
            setIfEmpty(_pixKeyCtrl, pixKey);
            setIfEmpty(_jurosParcelamentoCtrl, jurosParcelamento);
            setIfEmpty(_maxParcelasCtrl, maxParcelas);
            _checkoutLoaded = true;
          }

          return FadeTransition(
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
                    IconButton(
                      icon: const Icon(Icons.save_outlined, color: Colors.white),
                      tooltip: 'Salvar',
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'As altera��es de pagamento s�o salvas ao editar cada se��o.',
                            ),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                    if (_sincronizando)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                      )
                    else
                      IconButton(
                        icon: const Icon(Icons.cloud_sync_outlined, color: Colors.white),
                        tooltip: 'Sincronizar tudo',
                        onPressed: _lojaId == null ? null : _sincronizarTudo,
                      ),
                    if (_publicando)
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                      )
                    else
                      IconButton(
                        icon: const Icon(Icons.cloud_upload_outlined, color: Colors.white),
                        tooltip: 'Publicar cat�logo',
                        onPressed: _lojaId == null ? null : _publicarCatalogo,
                      ),
                    const SizedBox(width: 8),
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
                                color: Colors.white.withValues(alpha:0.1),
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
                                color: Colors.white.withValues(alpha:0.08),
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
                                  'Pagamentos',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Loja: $_lojaId',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha:0.9),
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

                // ==================== CONTE�DO ====================
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        // Info card
                        _buildInfoCard(),
                        const SizedBox(height: 20),

                        // Mercado Pago
                        _buildGatewayCard(
                          titulo: 'Mercado Pago',
                          icone: Icons.account_balance_wallet,
                          cor: const Color(0xFF00BCFF),
                          isConnected: connectedMp,
                          userId: userIdMp,
                          onGuide: () => _mostrarGuia('mercadopago'),
                          onOpenPanel: () => _abrirUrl(
                            'https://www.mercadopago.com.br/developers/panel',
                          ),
                          onCredentials: () => _abrirUrl(
                            'https://www.mercadopago.com.br/developers/panel/app',
                          ),
                          onTest: connectedMp
                              ? () => _validarGateway('mercadopago')
                              : null,
                          onDisconnect: connectedMp
                              ? () async {
                                  await PagamentosService.desconectarLoja(
                                      _lojaId!);
                                  if (!mounted) return;
                                  _mostrarSnackBarModerno(
                                    'Desconectado do Mercado Pago',
                                    Icons.link_off,
                                    warningColor,
                                  );
                                }
                              : null,
                          formContent: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Access Token de PRODU��O:',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey[800],
                                ),
                              ),
                              const SizedBox(height: 8),
                              _buildModernTextField(
                                controller: _publicKeyCtrl,
                                label: 'Access Token',
                                hint: 'APP_USR-xxxxxxxxxxxxxxxxxxxxxx',
                                icon: Icons.vpn_key_outlined,
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () async {
                                    final token = _publicKeyCtrl.text.trim();
                                    if (token.isEmpty) {
                                      _mostrarSnackBarModerno(
                                        'Cole o Access Token',
                                        Icons.warning_amber_rounded,
                                        warningColor,
                                      );
                                      return;
                                    }
                                    await PagamentosService.salvarAccessToken(
                                      _lojaId!,
                                      token,
                                    );
                                    if (!mounted) return;
                                    _mostrarSnackBarModerno(
                                      'Mercado Pago conectado!',
                                      Icons.check_circle_outline,
                                      successColor,
                                    );
                                  },
                                  icon: const Icon(Icons.link),
                                  label: const Text('Conectar Mercado Pago'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF00BCFF),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // ========== GATEWAY INATIVADA � descomente para reativar ==========
                        // // PagSeguro
                        // _buildGatewayCard(
                        //   titulo: 'PagSeguro',
                        //   icone: Icons.credit_card,
                        //   cor: const Color(0xFF00A859),
                        //   isConnected: pagseguroConfigured,
                        //   onGuide: () => _mostrarGuia('pagseguro'),
                        //   onOpenPanel: () => _abrirUrl(
                        //     'https://pagseguro.uol.com.br/preferencias/integracoes.jhtml',
                        //   ),
                        //   onCredentials: () => _abrirUrl(
                        //     'https://pagseguro.uol.com.br/preferencias/integracoes.jhtml',
                        //   ),
                        //   onTest: pagseguroConfigured
                        //       ? () => _validarGateway('pagseguro')
                        //       : null,
                        //   formContent: Column(
                        //     children: [
                        //       _buildModernTextField(
                        //         controller: _pagseguroTokenCtrl,
                        //         label: 'Token PagSeguro',
                        //         icon: Icons.vpn_key_outlined,
                        //       ),
                        //       const SizedBox(height: 12),
                        //       _buildModernTextField(
                        //         controller: _pagseguroSellerIdCtrl,
                        //         label: 'Seller ID / E-mail',
                        //         icon: Icons.email_outlined,
                        //       ),
                        //       const SizedBox(height: 12),
                        //       SizedBox(
                        //         width: double.infinity,
                        //         child: ElevatedButton.icon(
                        //           onPressed: () => _salvarGateway(
                        //             'pagseguro',
                        //             {
                        //               'token': _pagseguroTokenCtrl.text.trim(),
                        //               'seller_id':
                        //                   _pagseguroSellerIdCtrl.text.trim(),
                        //             },
                        //           ),
                        //           icon: const Icon(Icons.save),
                        //           label: const Text('Salvar PagSeguro'),
                        //           style: ElevatedButton.styleFrom(
                        //             backgroundColor: const Color(0xFF00A859),
                        //             foregroundColor: Colors.white,
                        //             padding: const EdgeInsets.symmetric(
                        //                 vertical: 14),
                        //             shape: RoundedRectangleBorder(
                        //               borderRadius: BorderRadius.circular(12),
                        //             ),
                        //           ),
                        //         ),
                        //       ),
                        //     ],
                        //   ),
                        // ),
                        // const SizedBox(height: 20),

                        // ========== GATEWAY INATIVADA � descomente para reativar ==========
                        // // Ton
                        // _buildGatewayCard(
                        //   titulo: 'Ton',
                        //   icone: Icons.point_of_sale,
                        //   cor: const Color(0xFF00D4AA),
                        //   isConnected: tonConfigured,
                        //   onGuide: () => _mostrarGuia('ton'),
                        //   onOpenPanel: () => _abrirUrl('https://www.ton.com.br'),
                        //   onCredentials: () =>
                        //       _abrirUrl('https://www.ton.com.br/desenvolvedores'),
                        //   onTest: tonConfigured
                        //       ? () => _validarGateway('ton')
                        //       : null,
                        //   formContent: Column(
                        //     children: [
                        //       _buildModernTextField(
                        //         controller: _tonClientIdCtrl,
                        //         label: 'Client ID',
                        //         icon: Icons.badge_outlined,
                        //       ),
                        //       const SizedBox(height: 12),
                        //       _buildModernTextField(
                        //         controller: _tonClientSecretCtrl,
                        //         label: 'Client Secret',
                        //         icon: Icons.lock_outline,
                        //         obscureText: true,
                        //       ),
                        //       const SizedBox(height: 12),
                        //       SizedBox(
                        //         width: double.infinity,
                        //         child: ElevatedButton.icon(
                        //           onPressed: () => _salvarGateway(
                        //             'ton',
                        //             {
                        //               'client_id': _tonClientIdCtrl.text.trim(),
                        //               'client_secret':
                        //                   _tonClientSecretCtrl.text.trim(),
                        //             },
                        //           ),
                        //           icon: const Icon(Icons.save),
                        //           label: const Text('Salvar Ton'),
                        //           style: ElevatedButton.styleFrom(
                        //             backgroundColor: const Color(0xFF00D4AA),
                        //             foregroundColor: Colors.white,
                        //             padding: const EdgeInsets.symmetric(
                        //                 vertical: 14),
                        //             shape: RoundedRectangleBorder(
                        //               borderRadius: BorderRadius.circular(12),
                        //             ),
                        //           ),
                        //         ),
                        //       ),
                        //     ],
                        //   ),
                        // ),
                        // const SizedBox(height: 20),

                        // ========== GATEWAY INATIVADA � descomente para reativar ==========
                        // // InfinitePay
                        // _buildGatewayCard(
                        //   titulo: 'InfinitePay',
                        //   icone: Icons.payments,
                        //   cor: const Color(0xFFFF6B35),
                        //   isConnected: infinitConfigured,
                        //   onGuide: () => _mostrarGuia('infinitepay'),
                        //   onOpenPanel: () =>
                        //       _abrirUrl('https://www.infinitepay.io'),
                        //   onCredentials: () =>
                        //       _abrirUrl('https://www.infinitepay.io'),
                        //   onTest: infinitConfigured
                        //       ? () => _validarGateway('infinitepay')
                        //       : null,
                        //   formContent: Column(
                        //     children: [
                        //       _buildModernTextField(
                        //         controller: _infinitApiKeyCtrl,
                        //         label: 'API Key',
                        //         icon: Icons.vpn_key_outlined,
                        //       ),
                        //       const SizedBox(height: 12),
                        //       _buildModernTextField(
                        //         controller: _infinitMerchantIdCtrl,
                        //         label: 'Merchant ID',
                        //         icon: Icons.store_outlined,
                        //       ),
                        //       const SizedBox(height: 12),
                        //       SizedBox(
                        //         width: double.infinity,
                        //         child: ElevatedButton.icon(
                        //           onPressed: () => _salvarGateway(
                        //             'infinitpay',
                        //             {
                        //               'api_key': _infinitApiKeyCtrl.text.trim(),
                        //               'merchant_id':
                        //                   _infinitMerchantIdCtrl.text.trim(),
                        //             },
                        //           ),
                        //           icon: const Icon(Icons.save),
                        //           label: const Text('Salvar InfinitePay'),
                        //           style: ElevatedButton.styleFrom(
                        //             backgroundColor: const Color(0xFFFF6B35),
                        //             foregroundColor: Colors.white,
                        //             padding: const EdgeInsets.symmetric(
                        //                 vertical: 14),
                        //             shape: RoundedRectangleBorder(
                        //               borderRadius: BorderRadius.circular(12),
                        //             ),
                        //           ),
                        //         ),
                        //       ),
                        //     ],
                        //   ),
                        // ),
                        // const SizedBox(height: 20),

                        // Checkout / PIX
                        _buildCheckoutCard(),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primaryColor.withValues(alpha:0.1),
            secondaryColor.withValues(alpha:0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primaryColor.withValues(alpha:0.2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha:0.1),
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
                  'Configure os m�todos de pagamento que seus clientes poder�o usar.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.lightbulb_outline,
                    color: warningColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Dica: Toque em "Como Conectar" em cada gateway para ver o passo a passo.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[700],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGatewayCard({
    required String titulo,
    required IconData icone,
    required Color cor,
    required bool isConnected,
    String? userId,
    required VoidCallback onGuide,
    required VoidCallback onOpenPanel,
    required VoidCallback onCredentials,
    VoidCallback? onTest,
    VoidCallback? onDisconnect,
    required Widget formContent,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cor.withValues(alpha:0.05),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cor.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icone, color: cor, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      if (userId != null && userId.isNotEmpty)
                        Text(
                          'ID: $userId',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isConnected
                        ? successColor.withValues(alpha:0.1)
                        : Colors.grey.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isConnected
                            ? Icons.check_circle
                            : Icons.circle_outlined,
                        size: 14,
                        color: isConnected ? successColor : Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isConnected ? 'Ativo' : 'Inativo',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isConnected ? successColor : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Actions
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildActionChip(
                    'Como Conectar',
                    Icons.menu_book,
                    cor,
                    onGuide,
                  ),
                  const SizedBox(width: 8),
                  _buildActionChip(
                    'Credenciais',
                    Icons.vpn_key,
                    Colors.grey[600]!,
                    onCredentials,
                  ),
                  const SizedBox(width: 8),
                  _buildActionChip(
                    'Painel',
                    Icons.open_in_new,
                    Colors.grey[600]!,
                    onOpenPanel,
                  ),
                  if (onTest != null) ...[
                    const SizedBox(width: 8),
                    _buildActionChip(
                      'Testar',
                      Icons.verified_outlined,
                      successColor,
                      onTest,
                    ),
                  ],
                  if (onDisconnect != null) ...[
                    const SizedBox(width: 8),
                    _buildActionChip(
                      'Desconectar',
                      Icons.link_off,
                      errorColor,
                      onDisconnect,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          // Form
          Padding(
            padding: const EdgeInsets.all(16),
            child: formContent,
          ),
        ],
      ),
    );
  }

  Widget _buildActionChip(
      String label, IconData icon, Color color, VoidCallback onTap) {
    return Material(
      color: color.withValues(alpha:0.1),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
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

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    IconData? icon,
    String? hint,
    bool obscureText = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B)),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon:
              icon != null ? Icon(icon, color: primaryColor, size: 20) : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          labelStyle: TextStyle(color: Colors.grey[600], fontSize: 13),
          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildCheckoutCard() {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha:0.05),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.shopping_cart_checkout,
                    color: primaryColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Checkout do Cat�logo',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      Text(
                        'Gateway padr�o e PIX',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Gateway padr�o para checkout:',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildGatewayChip('WhatsApp', 'whatsapp', Icons.chat),
                    _buildGatewayChip(
                        'Mercado Pago', 'mp', Icons.account_balance_wallet),
                    _buildGatewayChip(
                        'PagSeguro', 'pagseguro', Icons.credit_card),
                    _buildGatewayChip('Ton', 'ton', Icons.point_of_sale),
                    _buildGatewayChip(
                        'InfinitePay', 'infinitepay', Icons.payments),
                  ],
                ),
                const SizedBox(height: 20),
                _buildModernTextField(
                  controller: _pixKeyCtrl,
                  label: 'Chave PIX para recebimento',
                  hint: 'E-mail, CPF/CNPJ ou chave aleat�ria',
                  icon: Icons.pix,
                ),
                const SizedBox(height: 12),
                _buildModernTextField(
                  controller: _jurosParcelamentoCtrl,
                  label: 'Juros de parcelamento (% ao m�s)',
                  hint: 'Ex: 1.99 (taxa da maquininha/gateway)',
                  icon: Icons.percent,
                ),
                const SizedBox(height: 12),
                _buildModernTextField(
                  controller: _maxParcelasCtrl,
                  label: 'M�ximo de parcelas',
                  hint: 'Ex: 12 (at� quantas vezes dividir)',
                  icon: Icons.numbers,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _salvarCheckout,
                    icon: const Icon(Icons.save),
                    label: const Text('Salvar Configura��es de Checkout'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: surfaceColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          color: Colors.grey[500], size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'O cat�logo p�blico usar� este gateway e PIX como padr�o.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGatewayChip(String label, String value, IconData icon) {
    final selected = _gatewayPadrao == value;
    return Material(
      color: selected ? primaryColor : Colors.grey[100],
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => setState(() => _gatewayPadrao = value),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? Colors.white : Colors.grey[600],
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : Colors.grey[700],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Usado ao reativar gateways PagSeguro/Ton/InfinitePay (cards comentados acima)
  // ignore: unused_element
  Future<void> _salvarGateway(String gateway, Map<String, dynamic> data) async {
    data['updated_at'] = FieldValue.serverTimestamp();
    await PagamentosService.salvarGatewayConfig(
      lojaId: _lojaId!,
      gateway: gateway,
      data: data,
    );
    if (!mounted) return;
    _mostrarSnackBarModerno(
      'Configura��es salvas!',
      Icons.check_circle_outline,
      successColor,
    );
  }

  Future<void> _salvarCheckout() async {
    final jurosVal =
        double.tryParse(_jurosParcelamentoCtrl.text.trim()) ?? 1.99;
    final maxParcelas =
        (int.tryParse(_maxParcelasCtrl.text.trim()) ?? 12).clamp(1, 24);
    final checkoutData = {
      'gateway': _gatewayPadrao,
      'gatewayPadrao': _gatewayPadrao,
      'pixKey': _pixKeyCtrl.text.trim(),
      'chavePix': _pixKeyCtrl.text.trim(),
      'jurosParcelamento': jurosVal,
      'maxParcelas': maxParcelas,
      'updated_at': FieldValue.serverTimestamp(),
    };

    await PagamentosService.paymentsDoc(_lojaId!).set(
      {'checkout': checkoutData},
      SetOptions(merge: true),
    );

    await FirebaseFirestore.instance.collection('lojas').doc(_lojaId!).set(
      {'checkout': checkoutData},
      SetOptions(merge: true),
    );

    if (!mounted) return;
    _mostrarSnackBarModerno(
      'Configura��es de checkout salvas!',
      Icons.check_circle_outline,
      successColor,
    );
  }
}

