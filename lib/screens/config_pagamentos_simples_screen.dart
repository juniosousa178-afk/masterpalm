import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/loja_id_service.dart';
import '../services/pagamentos_service.dart';
import '../services/payment_gateway_service.dart';
import '../services/mercadopago_manual_connect_helper.dart';
import '../services/pagseguro_service.dart';
import '../services/ton_service.dart';
import '../services/infinitepay_service.dart';
import '../services/sync_firestore_script.dart';
import '../services/catalog_publish_service.dart';

/// Tela SIMPLIFICADA de configuração de pagamentos
/// Conexão rápida com gateways - máximo 2 cliques
class ConfigPagamentosSimplesScreen extends StatefulWidget {
  const ConfigPagamentosSimplesScreen({super.key});

  @override
  State<ConfigPagamentosSimplesScreen> createState() =>
      _ConfigPagamentosSimplesScreenState();
}

class _ConfigPagamentosSimplesScreenState
    extends State<ConfigPagamentosSimplesScreen> with WidgetsBindingObserver {
  String? _lojaId;
  bool _carregando = true;
  String? _erro;
  bool _salvando = false;
  bool _sincronizando = false;
  bool _publicando = false;
  bool _offline = false;
  bool _alteracoesPendentes = false;

  // Valores originais para detectar alterações
  String _gatewayAtivoOriginal = 'whatsapp';
  String _pixKeyOriginal = '';

  // Controllers
  final _tokenCtrl = TextEditingController();
  final _pixKeyCtrl = TextEditingController();

  // Estado dos gateways
  bool _mpConectado = false;
  String? _mpEmail;
  String _gatewayAtivo = 'whatsapp';
  bool _pagseguroConectado = false;
  String? _pagseguroEmail;
  bool _tonConectado = false;
  String? _tonId;
  bool _infinitepayConectado = false;
  String? _infinitepayMerchantId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pixKeyCtrl.addListener(_checkAlteracoes);
    _carregarDados();
  }

  void _checkAlteracoes() {
    final pix = _pixKeyCtrl.text.trim();
    final alterado =
        _gatewayAtivo != _gatewayAtivoOriginal || pix != _pixKeyOriginal;
    if (_alteracoesPendentes != alterado) {
      setState(() => _alteracoesPendentes = alterado);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _carregarDados();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pixKeyCtrl.removeListener(_checkAlteracoes);
    _tokenCtrl.dispose();
    _pixKeyCtrl.dispose();
    super.dispose();
  }

  /// ✅ Multi-loja: LojaIdService primeiro (StoreResolver), Hive apenas fallback offline
  Future<void> _carregarDados() async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      final offline = connectivity.every((r) => r == ConnectivityResult.none);
      if (mounted && _offline != offline) {
        setState(() => _offline = offline);
      }

      String? storeId = (await LojaIdService.get())?.trim();
      if (storeId == null || storeId.isEmpty) {
        final box = await Hive.openBox('config');
        storeId = box.get('store_id')?.toString().trim();
      }

      if (storeId == null || storeId.isEmpty) {
        setState(() {
          _erro = 'Loja não configurada';
          _carregando = false;
        });
        return;
      }

      setState(() => _lojaId = storeId);

      // Carregar configurações existentes
      final doc = await PagamentosService.paymentsDoc(storeId).get();
      if (doc.exists) {
        final data = doc.data() ?? {};

        // Mercado Pago
        final mp = data['mp'] as Map<String, dynamic>? ?? {};
        _mpConectado = mp['connected'] == true;
        _mpEmail = mp['email']?.toString();

        // PagSeguro
        final pagseguro = data['pagseguro'] as Map<String, dynamic>? ?? {};
        _pagseguroConectado = (pagseguro['token']?.toString() ?? '').isNotEmpty;
        _pagseguroEmail = pagseguro['seller_id']?.toString();

        // Ton
        final ton = data['ton'] as Map<String, dynamic>? ?? {};
        _tonConectado = (ton['client_id']?.toString() ?? '').isNotEmpty;
        _tonId = ton['client_id']?.toString();

        // InfinitePay (Firestore usa 'infinitpay')
        final infinit = data['infinitpay'] as Map<String, dynamic>? ?? {};
        _infinitepayConectado =
            (infinit['api_key']?.toString() ?? '').isNotEmpty;
        _infinitepayMerchantId = infinit['merchant_id']?.toString();

        // Checkout
        final checkout = data['checkout'] as Map<String, dynamic>? ?? {};
        _gatewayAtivo = checkout['gateway']?.toString() ?? 'whatsapp';
        _pixKeyCtrl.text = checkout['pixKey']?.toString() ?? '';
      }

      _gatewayAtivoOriginal = _gatewayAtivo;
      _pixKeyOriginal = _pixKeyCtrl.text.trim();
      setState(() {
        _carregando = false;
        _alteracoesPendentes = false;
      });
    } catch (e) {
      setState(() {
        _erro = 'Erro ao carregar: $e';
        _carregando = false;
      });
    }
  }

  Future<void> _conectarMercadoPagoOAuth() async {
    if (_lojaId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await PagamentosService.abrirConexaoOAuth(_lojaId!);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.open_in_browser, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Abra a página, autorize no Mercado Pago e volte aqui. A conexão será feita automaticamente.',
                ),
              ),
            ],
          ),
          duration: Duration(seconds: 5),
          backgroundColor: Colors.blue,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _mostrarErro('Erro', 'Não foi possível abrir: $e');
    }
  }

  void _mostrarConectarComToken() {
    _conectarMercadoPago();
  }

  Future<void> _conectarMercadoPago() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // Mostra modal para colar o token (fallback manual)
    final token = await showDialog<String>(
      context: navigator.context,
      builder: (ctx) => _DialogConectarMP(controller: _tokenCtrl),
    );

    if (token == null || token.isEmpty) return;
    if (!mounted) return;

    // Mostra loading
    showDialog(
      context: navigator.context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Validando credenciais...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final resultado = await MercadoPagoManualConnectHelper.connect(
        lojaId: _lojaId!,
        rawToken: token,
      );

      if (!mounted) return;
      navigator.pop(); // Fecha loading

      if (!resultado.success) {
        if (resultado.invalidToken) {
          _mostrarErro(
            'Token inválido',
            'Verifique se você copiou o Access Token de PRODUÇÃO corretamente.\n\n'
                'Dica: cole apenas o token (sem o prefixo "Bearer ").\n'
                'Exemplo: APP_USR-...',
          );
        } else {
          _mostrarErro(
            'Erro',
            'Não foi possível conectar: ${resultado.errorMessage ?? 'erro desconhecido'}',
          );
        }
        return;
      }

      setState(() {
        _mpConectado = true;
        _mpEmail = resultado.profileEmail;
        _gatewayAtivo = 'mp';
      });
      _checkAlteracoes();

      // Salva gateway padrão como MP
      await _salvarCheckout();

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  MercadoPagoManualConnectHelper.snackbarMessage(resultado),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      navigator.pop(); // Fecha loading
      _mostrarErro('Erro', 'Não foi possível conectar: $e');
    }
  }

  Future<void> _desconectarMercadoPago() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desconectar Mercado Pago?'),
        content: const Text(
          'Você poderá reconectar a qualquer momento.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Desconectar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    await PagamentosService.desconectarLoja(_lojaId!);

    setState(() {
      _mpConectado = false;
      _mpEmail = null;
      if (_gatewayAtivo == 'mp') {
        _gatewayAtivo = 'whatsapp';
      }
    });

    await _salvarCheckout();
  }

  /// Valida chave PIX: CPF (11 dígitos), e-mail, CNPJ (14 dígitos) ou chave aleatória (36 chars).
  bool _validarChavePix(String key) {
    final k = key.trim();
    if (k.isEmpty) return true;
    if (k.contains('@')) return k.length >= 5 && k.contains('.');
    final digits = k.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 11) return true;
    if (digits.length == 14) return true;
    if (k.length == 36 && k.contains('-')) return true;
    return false;
  }

  /// Detecta o tipo da chave PIX para exibição.
  String? _detectarTipoChavePix(String key) {
    final k = key.trim();
    if (k.isEmpty) return null;
    if (k.contains('@')) return 'E-mail';
    final digits = k.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 11) return 'CPF';
    if (digits.length == 14) return 'CNPJ';
    if (k.length == 36 && k.contains('-')) return 'Chave aleatória';
    return null;
  }

  Future<void> _salvarCheckout({bool skipValidation = false}) async {
    if (_lojaId == null) return;

    final pixKey = _pixKeyCtrl.text.trim();
    if (!skipValidation && pixKey.isNotEmpty && !_validarChavePix(pixKey)) {
      if (!mounted) return;
      _mostrarErro(
        'Chave PIX inválida',
        'Use CPF (11 dígitos), e-mail, CNPJ (14 dígitos) ou chave aleatória (36 caracteres).',
      );
      return;
    }

    final checkoutData = {
      'gateway': _gatewayAtivo,
      'gatewayPadrao': _gatewayAtivo,
      'pixKey': pixKey,
      'chavePix': pixKey,
      'updated_at': FieldValue.serverTimestamp(),
    };

    // Salva no doc de pagamentos
    await PagamentosService.paymentsDoc(_lojaId!).set(
      {'checkout': checkoutData},
      SetOptions(merge: true),
    );
    await PagamentosService.syncPaymentsPublic(_lojaId!);

    // Salva também no doc principal da loja
    await FirebaseFirestore.instance.collection('lojas').doc(_lojaId!).set(
      {'checkout': checkoutData},
      SetOptions(merge: true),
    );

    _gatewayAtivoOriginal = _gatewayAtivo;
    _pixKeyOriginal = pixKey;
    if (mounted) setState(() => _alteracoesPendentes = false);
  }

  Future<void> _testarConexoes() async {
    if (_lojaId == null) return;
    _mostrarLoading('Testando conexões...');
    try {
      final resultado = await PaymentGatewayService.validarConfiguracoes(
        lojaId: _lojaId!,
      );
      if (!mounted) return;
      Navigator.pop(context);
      final ok = resultado.values.any((v) => v);
      final msgs = <String>[];
      if (resultado['mercadopago'] == true) msgs.add('Mercado Pago: OK');
      if (resultado['pagseguro'] == true) msgs.add('PagSeguro: OK');
      if (resultado['ton'] == true) msgs.add('Ton: OK');
      if (resultado['infinitepay'] == true) msgs.add('InfinitePay: OK');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? (msgs.isEmpty ? 'Conexões OK' : msgs.join(' | '))
                : 'Nenhuma conexão ativa ou válida',
          ),
          backgroundColor: ok ? Colors.green : Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _mostrarErro('Erro', 'Não foi possível testar: $e');
    }
  }

  void _mostrarErro(String titulo, String mensagem) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.error, color: Colors.red),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                titulo,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Text(mensagem),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _abrirUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pagamentos')),
        body: _buildSkeletonLoading(),
      );
    }

    if (_erro != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pagamentos')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(_erro!, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _erro = null;
                    _carregando = true;
                  });
                  _carregarDados();
                },
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Pagamentos'),
            if (_alteracoesPendentes) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Alterações não salvas',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (_salvando || _sincronizando || _publicando)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          TextButton.icon(
            onPressed: (_salvando || _sincronizando || _publicando)
                ? null
                : () async {
                    HapticFeedback.selectionClick();
                    final messenger = ScaffoldMessenger.of(context);
                    setState(() => _salvando = true);
                    try {
                      await _salvarCheckout();
                      if (!mounted) return;
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('Configurações salvas!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    } finally {
                      if (mounted) setState(() => _salvando = false);
                    }
                  },
            icon: const Icon(Icons.save_outlined),
            label: const Text('Salvar'),
          ),
          TextButton.icon(
            onPressed: (_salvando || _sincronizando || _publicando)
                ? null
                : _sincronizarTudo,
            icon: const Icon(Icons.cloud_sync_outlined),
            label: const Text('Sincronizar'),
          ),
          TextButton.icon(
            onPressed: (_salvando || _sincronizando || _publicando)
                ? null
                : _publicarCatalogo,
            icon: const Icon(Icons.cloud_upload_outlined),
            label: const Text('Publicar'),
          ),
          if (_offline)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Icon(Icons.cloud_off,
                    color: Colors.orange.shade700, size: 20),
              ),
            ),
          if (_mpConectado ||
              _pagseguroConectado ||
              _tonConectado ||
              _infinitepayConectado)
            IconButton(
              icon: const Icon(Icons.wifi_tethering),
              tooltip: 'Testar conexões',
              onPressed: () async {
                HapticFeedback.selectionClick();
                await _testarConexoes();
              },
            ),
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () {
              HapticFeedback.selectionClick();
              _mostrarAjuda();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _carregarDados,
        child: ListView(
          padding: const EdgeInsets.all(16),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (_offline)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.cloud_off, color: Colors.orange.shade700),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Sem conexão. Algumas funções podem estar limitadas.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            if (!_mpConectado &&
                !_pagseguroConectado &&
                !_tonConectado &&
                !_infinitepayConectado)
              _buildEstadoVazioCard(),
            if (!_mpConectado &&
                !_pagseguroConectado &&
                !_tonConectado &&
                !_infinitepayConectado)
              const SizedBox(height: 16),
            // ===== MÉTODO PADRÃO (no topo - mais usado) =====
            _buildGatewaySelector(),

            const SizedBox(height: 16),

            // ===== CHAVE PIX (no topo - mais usado) =====
            _buildPixCard(),

            const SizedBox(height: 16),

            // ===== MERCADO PAGO =====
            _buildMercadoPagoCard(),

            const SizedBox(height: 16),

            // ===== PAGSEGURO =====
            _buildPagSeguroCard(),

            const SizedBox(height: 16),

            // ===== TON =====
            _buildTonCard(),

            const SizedBox(height: 16),

            // ===== INFINITEPAY =====
            _buildInfinitePayCard(),

            const SizedBox(height: 24),

            // ===== BOTÃO SALVAR =====
            Semantics(
              button: true,
              label:
                  _salvando ? 'Salvando configurações' : 'Salvar configurações',
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  icon: _salvando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save),
                  label:
                      Text(_salvando ? 'Salvando...' : 'Salvar Configurações'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _salvando
                      ? null
                      : () async {
                          HapticFeedback.mediumImpact();
                          final messenger = ScaffoldMessenger.of(context);
                          setState(() => _salvando = true);
                          try {
                            await _salvarCheckout();
                            if (!mounted) return;
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Configurações salvas!'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } finally {
                            if (mounted) setState(() => _salvando = false);
                          }
                        },
                ),
              ),
            ),

            const SizedBox(height: 16),
            TextButton.icon(
              icon: const Icon(Icons.tune, size: 18),
              label: const Text('Configuração avançada'),
              onPressed: () {
                HapticFeedback.selectionClick();
                Navigator.of(context).pushNamed('/config-pagamentos');
              },
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonLoading() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (int i = 0; i < 6; i++) ...[
          Container(
            height: 120,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEstadoVazioCard() {
    return Semantics(
      label:
          'Nenhum método de pagamento conectado. Conecte pelo menos um para receber pagamentos.',
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.blue.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade700, size: 24),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Conecte pelo menos um método',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Para receber pagamentos online, conecte o Mercado Pago, PagSeguro, Ton ou InfinitePay. '
              'Ou use PIX manual com sua chave.',
              style: TextStyle(color: Colors.black87, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Text(
              'Recomendamos começar pelo Mercado Pago ou pela chave PIX.',
              style: TextStyle(
                color: Colors.blue.shade700,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMercadoPagoCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: _mpConectado ? Colors.green : Colors.grey.shade300,
          width: _mpConectado ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF009EE3).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Image.network(
                    'https://http2.mlstatic.com/frontend-assets/mp-web-navigation/ui-navigation/5.19.1/mercadopago/logo__large@2x.png',
                    height: 24,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.payment,
                      color: Color(0xFF009EE3),
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Mercado Pago',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Text(
                          _mpConectado ? 'Conectado' : 'Não conectado',
                          key: ValueKey(_mpConectado),
                          style: TextStyle(
                            color: _mpConectado ? Colors.green : Colors.grey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  _mpConectado ? Icons.check_circle : Icons.radio_button_off,
                  color: _mpConectado ? Colors.green : Colors.grey,
                  size: 28,
                ),
              ],
            ),

            if (_mpConectado && _mpEmail != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.email, size: 16, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _mpEmail!,
                        style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Botões de ação
            if (_mpConectado)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.link_off, size: 18),
                      label: const Text('Desconectar'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        _desconectarMercadoPago();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(kIsWeb ? Icons.refresh : Icons.vpn_key,
                          size: 18),
                      label: const Text('Reconectar'),
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        if (kIsWeb) {
                          _conectarMercadoPagoOAuth();
                        } else {
                          _mostrarConectarComToken();
                        }
                      },
                    ),
                  ),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // APK: token manual como principal (OAuth dá erro no mobile)
                  // Web: OAuth como principal
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(kIsWeb ? Icons.link : Icons.vpn_key),
                      label: const Text(
                        kIsWeb
                            ? 'Conectar com Mercado Pago'
                            : 'Conectar com Access Token',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF009EE3),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        if (kIsWeb) {
                          _conectarMercadoPagoOAuth();
                        } else {
                          _mostrarConectarComToken();
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: kIsWeb
                          ? () => _mostrarConectarComToken()
                          : _conectarMercadoPagoOAuth,
                      child: Text(
                        kIsWeb
                            ? 'Ou conectar com token manual'
                            : 'Ou conectar via navegador (OAuth)',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

            const SizedBox(height: 12),

            // Link de ajuda (só quando conectado ou para OAuth)
            if (_mpConectado)
              Center(
                child: TextButton.icon(
                  icon: const Icon(Icons.help_outline, size: 16),
                  label: const Text('Como obter o Access Token?'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey[600],
                  ),
                  onPressed: () => _mostrarGuiaMP(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPagSeguroCard() {
    return _buildGatewayCard(
      nome: 'PagSeguro',
      cor: const Color(0xFF00A859),
      icone: Icons.credit_card,
      conectado: _pagseguroConectado,
      infoConectado: _pagseguroEmail,
      onConectar: _conectarPagSeguro,
      onDesconectar: _desconectarPagSeguro,
      linkPainel: 'https://pagseguro.uol.com.br/preferencias/integracoes.jhtml',
      dicaLink: 'Como obter Token e Seller ID?',
    );
  }

  Widget _buildTonCard() {
    return _buildGatewayCard(
      nome: 'Ton',
      cor: const Color(0xFF00D4AA),
      icone: Icons.point_of_sale,
      conectado: _tonConectado,
      infoConectado: _tonId != null
          ? 'ID: ${_tonId!.length > 12 ? '${_tonId!.substring(0, 12)}...' : _tonId}'
          : null,
      onConectar: _conectarTon,
      onDesconectar: _desconectarTon,
      linkPainel: 'https://www.ton.com.br/desenvolvedores',
      dicaLink: 'Como obter credenciais?',
    );
  }

  Widget _buildInfinitePayCard() {
    return _buildGatewayCard(
      nome: 'InfinitePay',
      cor: const Color(0xFFFF6B35),
      icone: Icons.payments,
      conectado: _infinitepayConectado,
      infoConectado: _infinitepayMerchantId,
      onConectar: _conectarInfinitePay,
      onDesconectar: _desconectarInfinitePay,
      linkPainel: 'https://www.infinitepay.io',
      dicaLink: 'Como obter API Key?',
    );
  }

  Widget _buildGatewayCard({
    required String nome,
    required Color cor,
    required IconData icone,
    required bool conectado,
    String? infoConectado,
    required VoidCallback onConectar,
    required VoidCallback onDesconectar,
    required String linkPainel,
    required String dicaLink,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: conectado ? Colors.green : Colors.grey.shade300,
          width: conectado ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cor.withOpacity(0.1),
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
                        nome,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Text(
                          conectado ? 'Conectado' : 'Não conectado',
                          key: ValueKey(conectado),
                          style: TextStyle(
                            color: conectado ? Colors.green : Colors.grey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  conectado ? Icons.check_circle : Icons.radio_button_off,
                  color: conectado ? Colors.green : Colors.grey,
                  size: 28,
                ),
              ],
            ),
            if (conectado &&
                infoConectado != null &&
                infoConectado.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle,
                        size: 16, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        infoConectado,
                        style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (conectado)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.link_off, size: 18),
                      label: const Text('Desconectar'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        onDesconectar();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Reconectar'),
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        onConectar();
                      },
                    ),
                  ),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.link),
                  label: Text('Conectar $nome'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    onConectar();
                  },
                ),
              ),
            const SizedBox(height: 12),
            Center(
              child: TextButton.icon(
                icon: const Icon(Icons.help_outline, size: 16),
                label: Text(dicaLink),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey[600],
                ),
                onPressed: () => _abrirUrl(linkPainel),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _conectarPagSeguro() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => _DialogConectarPagSeguro(),
    );
    if (result == null) return;
    final token = result['token'];
    if (token == null || token.isEmpty) return;

    _mostrarLoading('Validando credenciais...');
    try {
      final valido = await PagSeguroService.validarToken(
        token: token,
      );
      if (!mounted) return;
      Navigator.pop(context);
      if (!valido) {
        _mostrarErro(
          'Token inválido',
          'Verifique se você copiou o token corretamente do painel do PagSeguro.',
        );
        return;
      }
      final sellerId = result['seller_id']?.trim() ?? '';
      await PagamentosService.salvarGatewayConfig(
        lojaId: _lojaId!,
        gateway: 'pagseguro',
        data: {
          'token': token.trim(),
          'seller_id': sellerId,
        },
      );
      setState(() {
        _pagseguroConectado = true;
        _pagseguroEmail = sellerId.isNotEmpty ? sellerId : null;
        if (!_mpConectado) _gatewayAtivo = 'pagseguro';
      });
      await _salvarCheckout();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Text('PagSeguro conectado!'),
            ],
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _mostrarErro('Erro', 'Não foi possível conectar: $e');
    }
  }

  Future<void> _desconectarPagSeguro() async {
    final ok = await _confirmarDesconectar('PagSeguro');
    if (ok != true) return;
    await PagamentosService.salvarGatewayConfig(
      lojaId: _lojaId!,
      gateway: 'pagseguro',
      data: {},
    );
    setState(() {
      _pagseguroConectado = false;
      _pagseguroEmail = null;
      if (_gatewayAtivo == 'pagseguro') _gatewayAtivo = 'whatsapp';
    });
    await _salvarCheckout();
  }

  Future<void> _conectarTon() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => _DialogConectarTon(),
    );
    if (result == null) return;
    final clientId = result['client_id'];
    final clientSecret = result['client_secret'];
    if (clientId == null ||
        clientId.isEmpty ||
        clientSecret == null ||
        clientSecret.isEmpty) {
      return;
    }

    _mostrarLoading('Validando credenciais...');
    try {
      final valido = await TonService.validarCredenciais(
        clientId: clientId,
        clientSecret: clientSecret,
      );
      if (!mounted) return;
      Navigator.pop(context);
      if (!valido) {
        _mostrarErro(
          'Credenciais inválidas',
          'Verifique Client ID e Client Secret no painel da Ton.',
        );
        return;
      }
      await PagamentosService.salvarGatewayConfig(
        lojaId: _lojaId!,
        gateway: 'ton',
        data: {
          'client_id': clientId.trim(),
          'client_secret': clientSecret.trim(),
        },
      );
      setState(() {
        _tonConectado = true;
        final id = clientId.trim();
        _tonId = id.length > 8 ? '${id.substring(0, 8)}...' : id;
        if (!_mpConectado && !_pagseguroConectado) _gatewayAtivo = 'ton';
      });
      await _salvarCheckout();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Text('Ton conectado!'),
            ],
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _mostrarErro('Erro', 'Não foi possível conectar: $e');
    }
  }

  Future<void> _desconectarTon() async {
    final ok = await _confirmarDesconectar('Ton');
    if (ok != true) return;
    await PagamentosService.salvarGatewayConfig(
      lojaId: _lojaId!,
      gateway: 'ton',
      data: {},
    );
    setState(() {
      _tonConectado = false;
      _tonId = null;
      if (_gatewayAtivo == 'ton') _gatewayAtivo = 'whatsapp';
    });
    await _salvarCheckout();
  }

  Future<void> _conectarInfinitePay() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => _DialogConectarInfinitePay(),
    );
    if (result == null) return;
    final apiKey = result['api_key'];
    if (apiKey == null || apiKey.isEmpty) return;

    _mostrarLoading('Validando credenciais...');
    try {
      final valido = await InfinitePayService.validarApiKey(
        apiKey: apiKey,
      );
      if (!mounted) return;
      Navigator.pop(context);
      if (!valido) {
        _mostrarErro(
          'API Key inválida',
          'Verifique a API Key no painel do InfinitePay.',
        );
        return;
      }
      final merchantId = result['merchant_id']?.trim() ?? '';
      await PagamentosService.salvarGatewayConfig(
        lojaId: _lojaId!,
        gateway: 'infinitpay',
        data: {
          'api_key': apiKey.trim(),
          'merchant_id': merchantId,
        },
      );
      setState(() {
        _infinitepayConectado = true;
        _infinitepayMerchantId = merchantId.isNotEmpty ? merchantId : null;
        if (!_mpConectado && !_pagseguroConectado && !_tonConectado) {
          _gatewayAtivo = 'infinitepay';
        }
      });
      await _salvarCheckout();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Text('InfinitePay conectado!'),
            ],
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _mostrarErro('Erro', 'Não foi possível conectar: $e');
    }
  }

  Future<void> _desconectarInfinitePay() async {
    final ok = await _confirmarDesconectar('InfinitePay');
    if (ok != true) return;
    await PagamentosService.salvarGatewayConfig(
      lojaId: _lojaId!,
      gateway: 'infinitpay',
      data: {},
    );
    setState(() {
      _infinitepayConectado = false;
      _infinitepayMerchantId = null;
      if (_gatewayAtivo == 'infinitepay') _gatewayAtivo = 'whatsapp';
    });
    await _salvarCheckout();
  }

  void _mostrarLoading(String msg) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(msg),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<bool?> _confirmarDesconectar(String nome) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Desconectar $nome?'),
        content: const Text(
          'Você poderá reconectar a qualquer momento.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Desconectar'),
          ),
        ],
      ),
    );
  }

  Widget _buildPixCard() {
    final tipoChave = _detectarTipoChavePix(_pixKeyCtrl.text);
    final pixValido =
        _pixKeyCtrl.text.trim().isEmpty || _validarChavePix(_pixKeyCtrl.text);
    return Semantics(
      label: 'Campo de chave PIX para receber pagamentos',
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.teal.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.pix, color: Colors.teal),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Chave PIX',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Para receber pagamentos PIX',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _pixKeyCtrl,
                decoration: InputDecoration(
                  hintText: 'E-mail, CPF, CNPJ ou chave aleatória',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.key),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!pixValido && _pixKeyCtrl.text.trim().isNotEmpty)
                        Icon(Icons.error_outline,
                            color: Colors.red.shade700, size: 20),
                      IconButton(
                        icon: const Icon(Icons.paste),
                        tooltip: 'Colar',
                        onPressed: () async {
                          HapticFeedback.selectionClick();
                          final data = await Clipboard.getData('text/plain');
                          if (data?.text != null) {
                            final texto = data!.text!.trim();
                            _pixKeyCtrl.text = texto;
                            if (mounted) {
                              final valido = _validarChavePix(texto);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Row(
                                    children: [
                                      Icon(
                                        valido
                                            ? Icons.check_circle
                                            : Icons.warning,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        valido
                                            ? 'Chave PIX válida (${_detectarTipoChavePix(texto) ?? "desconhecido"})'
                                            : 'Chave PIX pode ser inválida',
                                      ),
                                    ],
                                  ),
                                  backgroundColor:
                                      valido ? Colors.green : Colors.orange,
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              if (tipoChave != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.label, size: 14, color: Colors.teal.shade700),
                    const SizedBox(width: 6),
                    Text(
                      'Tipo detectado: $tipoChave',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.teal.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGatewaySelector() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.settings, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  'Método de Pagamento Padrão',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Escolha como seus clientes vão pagar no catálogo',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildGatewayOption(
                  'whatsapp',
                  'WhatsApp',
                  Icons.chat,
                  Colors.green,
                  'Pedido via WhatsApp',
                ),
                if (_mpConectado)
                  _buildGatewayOption(
                    'mp',
                    'Mercado Pago',
                    Icons.payment,
                    const Color(0xFF009EE3),
                    'Pagar online',
                  ),
                if (_pagseguroConectado)
                  _buildGatewayOption(
                    'pagseguro',
                    'PagSeguro',
                    Icons.credit_card,
                    const Color(0xFF00A859),
                    'Pagar online',
                  ),
                if (_tonConectado)
                  _buildGatewayOption(
                    'ton',
                    'Ton',
                    Icons.point_of_sale,
                    const Color(0xFF00D4AA),
                    'Pagar online',
                  ),
                if (_infinitepayConectado)
                  _buildGatewayOption(
                    'infinitepay',
                    'InfinitePay',
                    Icons.payments,
                    const Color(0xFFFF6B35),
                    'Pagar online',
                  ),
                _buildGatewayOption(
                  'pix',
                  'PIX Manual',
                  Icons.pix,
                  Colors.teal,
                  'Mostrar chave PIX',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGatewayOption(
    String value,
    String label,
    IconData icon,
    Color color,
    String descricao,
  ) {
    final selecionado = _gatewayAtivo == value;
    return Tooltip(
      message: descricao,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          setState(() => _gatewayAtivo = value);
          _checkAlteracoes();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: selecionado ? color.withOpacity(0.1) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selecionado ? color : Colors.grey.shade300,
              width: selecionado ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: selecionado ? color : Colors.grey, size: 20),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: selecionado ? color : Colors.grey[700],
                    ),
                  ),
                  Text(
                    descricao,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
              if (selecionado) ...[
                const SizedBox(width: 8),
                Icon(Icons.check_circle, color: color, size: 18),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _mostrarGuiaMP() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '🔑 Como obter o Access Token',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            _buildPasso(1, 'Acesse o painel do Mercado Pago'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.open_in_new),
              label: const Text('Abrir Mercado Pago Developers'),
              onPressed: () => _abrirUrl(
                'https://www.mercadopago.com.br/developers/panel/app',
              ),
            ),
            const SizedBox(height: 16),
            _buildPasso(2, 'Faça login na sua conta'),
            const SizedBox(height: 16),
            _buildPasso(3, 'Clique em "Suas integrações"'),
            const SizedBox(height: 16),
            _buildPasso(4, 'Selecione ou crie uma aplicação'),
            const SizedBox(height: 16),
            _buildPasso(
              5,
              'Copie o ACCESS TOKEN de PRODUÇÃO',
              destaque: true,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning, color: Colors.amber),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Use o token de PRODUÇÃO, não o de teste!\n'
                      'O token começa com "APP_USR-"',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildPasso(6, 'Volte aqui e cole o token'),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _conectarMercadoPago();
                },
                child: const Text('Entendi, conectar agora'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasso(int numero, String texto, {bool destaque = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: destaque ? Colors.blue : Colors.grey[200],
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '$numero',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: destaque ? Colors.white : Colors.black,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            texto,
            style: TextStyle(
              fontSize: 15,
              fontWeight: destaque ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ],
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Sincronizado: ${p['synced'] ?? 0} produtos, ${c['synced'] ?? 0} clientes'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        final err = results['errors'] as List<dynamic>?;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(err != null && err.isNotEmpty
                ? err.first.toString()
                : 'Erro na sincronização'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erro ao sincronizar: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _sincronizando = false);
    }
  }

  Future<void> _publicarCatalogo() async {
    if (_publicando || _lojaId == null) return;
    setState(() => _publicando = true);
    try {
      final results = await CatalogPublishService.publicarCatalogoCanonicamente(
        lojaIdOverride: _lojaId,
      );
      if (!mounted) return;
      if (results['success'] == true) {
        await CatalogPublishService.limparCatalogoPrecisaAtualizar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Catálogo publicado! Produtos: ${results['products'] ?? 0}',
            ),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        final errors =
            results['errors'] is List ? results['errors'] as List : <dynamic>[];
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro na publicação: ${errors.join(', ')}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erro ao publicar: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _publicando = false);
    }
  }

  void _mostrarAjuda() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.help_outline, color: Colors.blue),
            SizedBox(width: 8),
            Text('Ajuda'),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Mercado Pago',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                'Receba pagamentos PIX, cartão e boleto diretamente na sua conta do Mercado Pago.',
              ),
              SizedBox(height: 16),
              Text(
                'Chave PIX',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                'Sua chave PIX para receber pagamentos manuais.',
              ),
              SizedBox(height: 16),
              Text(
                'Método Padrão',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                '? WhatsApp: Cliente faz pedido via WhatsApp\n'
                '? Mercado Pago: Pagamento online integrado\n'
                '? PIX Manual: Mostra sua chave para o cliente copiar',
              ),
            ],
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
  }
}

/// Dialog para conectar Mercado Pago
class _DialogConectarMP extends StatefulWidget {
  final TextEditingController controller;

  const _DialogConectarMP({required this.controller});

  @override
  State<_DialogConectarMP> createState() => _DialogConectarMPState();
}

class _DialogConectarMPState extends State<_DialogConectarMP> {
  bool _mostrarToken = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.link, color: Color(0xFF009EE3)),
          SizedBox(width: 8),
          Text('Conectar Mercado Pago'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cole o Access Token de PRODUÇÃO:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: widget.controller,
              obscureText: !_mostrarToken,
              maxLines: 1,
              decoration: InputDecoration(
                hintText: 'APP_USR-xxxxxxxx...',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.key),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        _mostrarToken ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() => _mostrarToken = !_mostrarToken);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.paste),
                      tooltip: 'Colar',
                      onPressed: () async {
                        final data = await Clipboard.getData('text/plain');
                        if (data?.text != null) {
                          widget.controller.text = data!.text!.trim();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: () async {
                final uri = Uri.parse(
                  'https://www.mercadopago.com.br/developers/panel/app',
                );
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.open_in_new, size: 18, color: Colors.blue),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Abrir painel do Mercado Pago',
                        style: TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.check),
          label: const Text('Conectar'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF009EE3),
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            final token = widget.controller.text.trim();
            Navigator.pop(context, token);
          },
        ),
      ],
    );
  }
}

/// Dialog para conectar PagSeguro
class _DialogConectarPagSeguro extends StatefulWidget {
  @override
  State<_DialogConectarPagSeguro> createState() =>
      _DialogConectarPagSeguroState();
}

class _DialogConectarPagSeguroState extends State<_DialogConectarPagSeguro> {
  final _tokenCtrl = TextEditingController();
  final _sellerIdCtrl = TextEditingController();
  bool _mostrarToken = false;

  @override
  void dispose() {
    _tokenCtrl.dispose();
    _sellerIdCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.credit_card, color: Color(0xFF00A859)),
          SizedBox(width: 8),
          Text('Conectar PagSeguro'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Token:', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(
              controller: _tokenCtrl,
              obscureText: !_mostrarToken,
              decoration: InputDecoration(
                hintText: 'Cole o token do PagSeguro',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.vpn_key),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(_mostrarToken
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () =>
                          setState(() => _mostrarToken = !_mostrarToken),
                    ),
                    IconButton(
                      icon: const Icon(Icons.paste),
                      tooltip: 'Colar',
                      onPressed: () async {
                        final data = await Clipboard.getData('text/plain');
                        if (data?.text != null) {
                          _tokenCtrl.text = data!.text!.trim();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Seller ID / E-mail (opcional):',
                style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(
              controller: _sellerIdCtrl,
              decoration: const InputDecoration(
                hintText: 'E-mail da conta PagSeguro',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email),
              ),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: () async {
                final uri = Uri.parse(
                    'https://pagseguro.uol.com.br/preferencias/integracoes.jhtml');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF00A859).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.open_in_new, size: 18, color: Color(0xFF00A859)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Abrir painel do PagSeguro',
                        style: TextStyle(
                          color: Color(0xFF00A859),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.check),
          label: const Text('Conectar'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00A859),
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            Navigator.pop(context, {
              'token': _tokenCtrl.text.trim(),
              'seller_id': _sellerIdCtrl.text.trim(),
            });
          },
        ),
      ],
    );
  }
}

/// Dialog para conectar Ton
class _DialogConectarTon extends StatefulWidget {
  @override
  State<_DialogConectarTon> createState() => _DialogConectarTonState();
}

class _DialogConectarTonState extends State<_DialogConectarTon> {
  final _clientIdCtrl = TextEditingController();
  final _clientSecretCtrl = TextEditingController();
  bool _mostrarSecret = false;

  @override
  void dispose() {
    _clientIdCtrl.dispose();
    _clientSecretCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.point_of_sale, color: Color(0xFF00D4AA)),
          SizedBox(width: 8),
          Text('Conectar Ton'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Client ID:',
                style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(
              controller: _clientIdCtrl,
              decoration: const InputDecoration(
                hintText: 'Cole o Client ID',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.badge),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Client Secret:',
                style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(
              controller: _clientSecretCtrl,
              obscureText: !_mostrarSecret,
              decoration: InputDecoration(
                hintText: 'Cole o Client Secret',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: IconButton(
                  icon: Icon(
                      _mostrarSecret ? Icons.visibility_off : Icons.visibility),
                  onPressed: () =>
                      setState(() => _mostrarSecret = !_mostrarSecret),
                ),
              ),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: () async {
                final uri = Uri.parse('https://www.ton.com.br/desenvolvedores');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF00D4AA).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.open_in_new, size: 18, color: Color(0xFF00D4AA)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Abrir painel Ton (Desenvolvedores)',
                        style: TextStyle(
                          color: Color(0xFF00D4AA),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.check),
          label: const Text('Conectar'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00D4AA),
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            Navigator.pop(context, {
              'client_id': _clientIdCtrl.text.trim(),
              'client_secret': _clientSecretCtrl.text.trim(),
            });
          },
        ),
      ],
    );
  }
}

/// Dialog para conectar InfinitePay
class _DialogConectarInfinitePay extends StatefulWidget {
  @override
  State<_DialogConectarInfinitePay> createState() =>
      _DialogConectarInfinitePayState();
}

class _DialogConectarInfinitePayState
    extends State<_DialogConectarInfinitePay> {
  final _apiKeyCtrl = TextEditingController();
  final _merchantIdCtrl = TextEditingController();
  bool _mostrarApiKey = false;

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    _merchantIdCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.payments, color: Color(0xFFFF6B35)),
          SizedBox(width: 8),
          Text('Conectar InfinitePay'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('API Key:',
                style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(
              controller: _apiKeyCtrl,
              obscureText: !_mostrarApiKey,
              decoration: InputDecoration(
                hintText: 'Cole a API Key',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.key),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(_mostrarApiKey
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () =>
                          setState(() => _mostrarApiKey = !_mostrarApiKey),
                    ),
                    IconButton(
                      icon: const Icon(Icons.paste),
                      tooltip: 'Colar',
                      onPressed: () async {
                        final data = await Clipboard.getData('text/plain');
                        if (data?.text != null) {
                          _apiKeyCtrl.text = data!.text!.trim();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Merchant ID (opcional):',
                style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(
              controller: _merchantIdCtrl,
              decoration: const InputDecoration(
                hintText: 'ID do comerciante',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.store),
              ),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: () async {
                final uri = Uri.parse('https://www.infinitepay.io');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B35).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.open_in_new, size: 18, color: Color(0xFFFF6B35)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Abrir painel InfinitePay',
                        style: TextStyle(
                          color: Color(0xFFFF6B35),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.check),
          label: const Text('Conectar'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF6B35),
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            Navigator.pop(context, {
              'api_key': _apiKeyCtrl.text.trim(),
              'merchant_id': _merchantIdCtrl.text.trim(),
            });
          },
        ),
      ],
    );
  }
}
