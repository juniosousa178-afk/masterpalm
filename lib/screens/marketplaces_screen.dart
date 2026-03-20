// lib/screens/marketplaces_screen.dart

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/marketplace_service.dart';
import '../services/store_resolver_facade.dart';

class MarketplacesScreen extends StatefulWidget {
  const MarketplacesScreen({super.key});

  @override
  State<MarketplacesScreen> createState() => _MarketplacesScreenState();
}

class _MarketplacesScreenState extends State<MarketplacesScreen> {
  bool _loading = true;
  Map<String, dynamic> _config = {};
  String• _lojaId;

  /// Loading por marketplace (não bloqueia a tela inteira)
  String• _loadingMarketplace;

  /// Última sincronização por marketplace
  final Map<String, DateTime?> _ultimaSincronizacao = {};

  /// Toggle para mostrar/ocultar tokens sensíveis
  bool _mostrarTokens = false;

  // Controllers TikTok Shop
  final _tiktokAppKeyController = TextEditingController();
  final _tiktokAppSecretController = TextEditingController();
  final _tiktokAccessTokenController = TextEditingController();
  final _tiktokShopIdController = TextEditingController();

  // Controllers Mercado Livre
  final _mlClientIdController = TextEditingController();
  final _mlClientSecretController = TextEditingController();
  final _mlAccessTokenController = TextEditingController();
  final _mlRefreshTokenController = TextEditingController();

  // Controllers Shopee
  final _shopeePartnerIdController = TextEditingController();
  final _shopeePartnerKeyController = TextEditingController();
  final _shopeeShopIdController = TextEditingController();
  final _shopeeAccessTokenController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  @override
  void dispose() {
    _tiktokAppKeyController.dispose();
    _tiktokAppSecretController.dispose();
    _tiktokAccessTokenController.dispose();
    _tiktokShopIdController.dispose();
    _mlClientIdController.dispose();
    _mlClientSecretController.dispose();
    _mlAccessTokenController.dispose();
    _mlRefreshTokenController.dispose();
    _shopeePartnerIdController.dispose();
    _shopeePartnerKeyController.dispose();
    _shopeeShopIdController.dispose();
    _shopeeAccessTokenController.dispose();
    super.dispose();
  }

  Future<void> _carregarDados() async {
    setState(() => _loading = true);

    try {
      final lojaId = await StoreResolverFacade.resolveForAdminApp();

      if (!mounted) return;
      if (lojaId == null) {
        _mostrarErro('Loja não identificada');
        return;
      }

      _lojaId = lojaId;
      final config = await MarketplaceService.buscarConfig(lojaId);

      if (!mounted) return;
      setState(() {
        _config = config;
        _preencherControllers();
      });
    } catch (e) {
      debugPrint('Erro ao carregar dados (type=${e.runtimeType})');
      if (mounted) _mostrarErro(_mensagemAmigavel(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _preencherControllers() {
    final tiktok = _config['tiktok_shop'] as Map<String, dynamic>• ?• {};
    _tiktokAppKeyController.text = tiktok['app_key'] ?• '';
    _tiktokAppSecretController.text = tiktok['app_secret'] ?• '';
    _tiktokAccessTokenController.text = tiktok['access_token'] ?• '';
    _tiktokShopIdController.text = tiktok['shop_id'] ?• '';

    final ml = _config['mercado_livre'] as Map<String, dynamic>• ?• {};
    _mlClientIdController.text = ml['client_id'] ?• '';
    _mlClientSecretController.text = ml['client_secret'] ?• '';
    _mlAccessTokenController.text = ml['access_token'] ?• '';
    _mlRefreshTokenController.text = ml['refresh_token'] ?• '';

    final shopee = _config['shopee'] as Map<String, dynamic>• ?• {};
    _shopeePartnerIdController.text = shopee['partner_id'] ?• '';
    _shopeePartnerKeyController.text = shopee['partner_key'] ?• '';
    _shopeeShopIdController.text = shopee['shop_id'] ?• '';
    _shopeeAccessTokenController.text = shopee['access_token'] ?• '';
  }

  String _mensagemAmigavel(dynamic e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('permission') || msg.contains('permissão')) return 'Sem permissão. Verifique o acesso à loja.';
    if (msg.contains('network') || msg.contains('connection')) return 'Sem conexão. Verifique sua internet.';
    return e.toString();
  }

  void _mostrarErro(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  void _mostrarSucesso(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.green),
    );
  }

  Future<void> _abrirUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Valida campos obrigatórios antes de salvar
  String• _validarAntesDeSalvar() {
    final tiktokAtivo = _tiktokAppKeyController.text.trim().isNotEmpty;
    if (tiktokAtivo) {
      if (_tiktokAppSecretController.text.trim().isEmpty) return 'TikTok: App Secret é obrigatório';
      if (_tiktokAccessTokenController.text.trim().isEmpty) return 'TikTok: Access Token é obrigatório';
      if (_tiktokShopIdController.text.trim().isEmpty) return 'TikTok: Shop ID é obrigatório';
    }

    final mlAtivo = _mlAccessTokenController.text.trim().isNotEmpty;
    if (mlAtivo) {
      final hasRefresh = _mlRefreshTokenController.text.trim().isNotEmpty;
      final hasClient = _mlClientIdController.text.trim().isNotEmpty && _mlClientSecretController.text.trim().isNotEmpty;
      if (hasRefresh && !hasClient) {
        return 'Mercado Livre: Para renovação automática do token, preencha Client ID e Client Secret';
      }
    }

    final shopeeAtivo = _shopeePartnerIdController.text.trim().isNotEmpty;
    if (shopeeAtivo) {
      if (_shopeePartnerKeyController.text.trim().isEmpty) return 'Shopee: Partner Key é obrigatório';
      if (_shopeeShopIdController.text.trim().isEmpty) return 'Shopee: Shop ID é obrigatório';
      if (_shopeeAccessTokenController.text.trim().isEmpty) return 'Shopee: Access Token é obrigatório';
    }

    return null;
  }

  Future<void> _salvar() async {
    if (_lojaId == null) return;

    final erro = _validarAntesDeSalvar();
    if (erro != null) {
      _mostrarErro(erro);
      return;
    }

    setState(() => _loading = true);

    try {
      final novaConfig = {
        'tiktok_shop': {
          'app_key': _tiktokAppKeyController.text.trim(),
          'app_secret': _tiktokAppSecretController.text.trim(),
          'access_token': _tiktokAccessTokenController.text.trim(),
          'shop_id': _tiktokShopIdController.text.trim(),
          'ativo': _tiktokAppKeyController.text.trim().isNotEmpty,
        },
        'mercado_livre': {
          'client_id': _mlClientIdController.text.trim(),
          'client_secret': _mlClientSecretController.text.trim(),
          'access_token': _mlAccessTokenController.text.trim(),
          'refresh_token': _mlRefreshTokenController.text.trim(),
          'ativo': _mlAccessTokenController.text.trim().isNotEmpty,
        },
        'shopee': {
          'partner_id': _shopeePartnerIdController.text.trim(),
          'partner_key': _shopeePartnerKeyController.text.trim(),
          'shop_id': _shopeeShopIdController.text.trim(),
          'access_token': _shopeeAccessTokenController.text.trim(),
          'ativo': _shopeePartnerIdController.text.trim().isNotEmpty,
        },
        'ultima_atualizacao': DateTime.now().toIso8601String(),
      };

      final sucesso = await MarketplaceService.salvarConfig(_lojaId!, novaConfig);

      if (!mounted) return;
      if (sucesso) {
        _mostrarSucesso('Configurações salvas!');
        await _carregarDados();
      } else {
        _mostrarErro('Erro ao salvar configurações');
      }
    } catch (e) {
      if (mounted) _mostrarErro(_mensagemAmigavel(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _testarConexao(String marketplace) async {
    if (_lojaId == null) return;

    setState(() => _loadingMarketplace = marketplace);

    try {
      Map<String, dynamic> resultado;

      switch (marketplace) {
        case 'tiktok':
          resultado = await MarketplaceService.testarConexaoTikTok(
            appKey: _tiktokAppKeyController.text.trim(),
            appSecret: _tiktokAppSecretController.text.trim(),
            accessToken: _tiktokAccessTokenController.text.trim(),
            shopId: _tiktokShopIdController.text.trim(),
          );
          break;
        case 'mercadolivre':
          resultado = await MarketplaceService.testarConexaoMercadoLivre(
            accessToken: _mlAccessTokenController.text.trim(),
          );
          break;
        case 'shopee':
          resultado = await MarketplaceService.testarConexaoShopee(
            partnerId: _shopeePartnerIdController.text.trim(),
            partnerKey: _shopeePartnerKeyController.text.trim(),
            shopId: _shopeeShopIdController.text.trim(),
            accessToken: _shopeeAccessTokenController.text.trim(),
          );
          break;
        default:
          resultado = {'success': false, 'error': 'Marketplace não suportado'};
      }

      if (!mounted) return;
      if (resultado['success'] == true) {
        _mostrarSucesso(resultado['message'] ?• 'Conexão OK!');
      } else {
        _mostrarErro(resultado['error'] ?• 'Falha na conexão');
      }
    } catch (e) {
      if (mounted) _mostrarErro(_mensagemAmigavel(e));
    } finally {
      if (mounted) setState(() => _loadingMarketplace = null);
    }
  }

  Future<void> _sincronizarProdutos(String marketplace) async {
    if (_lojaId == null) return;

    // Confirmação antes de sincronizar
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sincronizar produtos?'),
        content: Text(
          'Os produtos da loja serão enviados/atualizados no $marketplace. '
          'Isso pode levar alguns minutos.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sincronizar')),
        ],
      ),
    );

    if (confirmado != true || !mounted) return;

    setState(() => _loadingMarketplace = marketplace);

    try {
      Map<String, dynamic> resultado;
      switch (marketplace) {
        case 'tiktok':
          resultado = await MarketplaceService.sincronizarProdutosTikTok(lojaId: _lojaId!);
          break;
        case 'mercadolivre':
          resultado = await MarketplaceService.sincronizarProdutosMercadoLivre(lojaId: _lojaId!);
          break;
        case 'shopee':
          resultado = await MarketplaceService.sincronizarProdutosShopee(lojaId: _lojaId!);
          break;
        default:
          resultado = {'success': false, 'error': 'Marketplace não suportado'};
      }

      if (!mounted) return;
      _ultimaSincronizacao[marketplace] = DateTime.now();

      if (resultado['success'] == true) {
        final total = resultado['total'] ?• 0;
        final sincronizados = resultado['sincronizados'] ?• 0;
        final erros = resultado['erros'] ?• 0;

        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Sincronização concluída'),
            content: Text(
              'Total: $total\n'
              'Sincronizados: $sincronizados\n'
              'Erros: $erros',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } else {
        _mostrarErro(resultado['error'] ?• 'Erro na sincronização');
      }
    } catch (e) {
      if (mounted) _mostrarErro(_mensagemAmigavel(e));
    } finally {
      if (mounted) setState(() => _loadingMarketplace = null);
    }
  }

  Widget _campoToken({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureDefault = true,
  }) {
    final obscure = obscureDefault && !_mostrarTokens;
    return TextField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        prefixIcon: Icon(icon),
        suffixIcon: obscureDefault
            • IconButton(
                icon: Icon(obscure • Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _mostrarTokens = !_mostrarTokens),
              )
            : null,
      ),
      maxLines: obscure • 1 : 3,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Integração com Marketplaces'),
        actions: [
          if (!_loading)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _salvar,
              tooltip: 'Salvar Configurações',
            ),
        ],
      ),
      body: _loading
          • const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoCard(),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Checkbox(
                        value: _mostrarTokens,
                        onChanged: (v) => setState(() => _mostrarTokens = v ?• false),
                      ),
                      const Text('Mostrar tokens sensíveis'),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildTikTokShopSection(),
                  const SizedBox(height: 24),
                  _buildMercadoLivreSection(),
                  const SizedBox(height: 24),
                  _buildShopeeSection(),
                  const SizedBox(height: 24),
                  _buildOutrosMarketplacesSection(),
                  const SizedBox(height: 32),
                  _buildBotaoSalvar(),
                ],
              ),
            ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Text(
                  'Como Funciona',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue.shade700),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              '• Configure os tokens/credenciais de cada marketplace\n'
              '• Use "Testar conexão" para validar antes de salvar\n'
              '• Sincronize seus produtos automaticamente\n'
              '• Gerencie estoque em todos os marketplaces',
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTikTokShopSection() {
    final tiktok = _config['tiktok_shop'] as Map<String, dynamic>• ?• {};
    final ativo = tiktok['ativo'] == true;
    final loading = _loadingMarketplace == 'tiktok';
    final ultima = _ultimaSincronizacao['tiktok'];

    return Card(
      child: ExpansionTile(
        leading: const Text('🎵', style: TextStyle(fontSize: 32)),
        title: const Text('TikTok Shop', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ativo • '✅ Configurado' : '⚠️ Não configurado', style: TextStyle(color: ativo • Colors.green : Colors.orange)),
            if (ultima != null)
              Text(
                'Última sync: ${ultima.hour.toString().padLeft(2, '0')}:${ultima.minute.toString().padLeft(2, '0')}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _tiktokAppKeyController,
                  decoration: const InputDecoration(
                    labelText: 'App Key',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.key),
                  ),
                ),
                const SizedBox(height: 12),
                _campoToken(
                  controller: _tiktokAppSecretController,
                  label: 'App Secret',
                  icon: Icons.lock,
                ),
                const SizedBox(height: 12),
                _campoToken(
                  controller: _tiktokAccessTokenController,
                  label: 'Access Token',
                  icon: Icons.vpn_key,
                  obscureDefault: false,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _tiktokShopIdController,
                  decoration: const InputDecoration(
                    labelText: 'Shop ID',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.store),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: (ativo && !loading) • () => _testarConexao('tiktok') : null,
                        icon: loading • const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.wifi_tethering),
                        label: Text(loading • 'Testando...' : 'Testar conexão'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: (ativo && !loading) • () => _sincronizarProdutos('tiktok') : null,
                        icon: const Icon(Icons.sync),
                        label: const Text('Sincronizar'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => _mostrarAjudaTikTok(),
                      icon: const Icon(Icons.help_outline),
                      label: const Text('Como obter credenciais?'),
                    ),
                    TextButton.icon(
                      onPressed: () => _abrirUrl(MarketplaceService.linksDocumentacao['tiktok']!),
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('Documentação'),
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

  void _mostrarAjudaTikTok() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🎵 Como configurar TikTok Shop'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('PASSO 1: Criar conta vendedor', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              SizedBox(height: 8),
              Text('1. Acesse: seller.tiktokglobalshop.com\n2. Clique em "Sign Up"\n3. Preencha seus dados\n4. Verifique seu email'),
              SizedBox(height: 16),
              Text('PASSO 2: Criar App no Developer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              SizedBox(height: 8),
              Text('1. Acesse: partner.tiktokshop.com\n2. Faça login\n3. "My Apps" → "Create App"\n4. Marque permissões de produtos e pedidos'),
              SizedBox(height: 16),
              Text('PASSO 3: Obter Credenciais', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              SizedBox(height: 8),
              Text('Após criar o app: App Key, App Secret, Access Token (Generate), Shop ID'),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('ENTENDI'))],
      ),
    );
  }

  Widget _buildMercadoLivreSection() {
    final ml = _config['mercado_livre'] as Map<String, dynamic>• ?• {};
    final ativo = ml['ativo'] == true;
    final loading = _loadingMarketplace == 'mercadolivre';
    final ultima = _ultimaSincronizacao['mercadolivre'];

    return Card(
      child: ExpansionTile(
        leading: const Text('🟡', style: TextStyle(fontSize: 32)),
        title: const Text('Mercado Livre', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ativo • '✅ Configurado' : '⚠️ Não configurado', style: TextStyle(color: ativo • Colors.green : Colors.orange)),
            if (ultima != null)
              Text('Última sync: ${ultima.hour.toString().padLeft(2, '0')}:${ultima.minute.toString().padLeft(2, '0')}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Client ID e Secret (para renovação automática do token)', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 4),
                TextField(
                  controller: _mlClientIdController,
                  decoration: const InputDecoration(
                    labelText: 'Client ID',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.badge),
                  ),
                ),
                const SizedBox(height: 12),
                _campoToken(controller: _mlClientSecretController, label: 'Client Secret', icon: Icons.lock),
                const SizedBox(height: 16),
                _campoToken(controller: _mlAccessTokenController, label: 'Access Token', icon: Icons.vpn_key, obscureDefault: false),
                const SizedBox(height: 12),
                _campoToken(controller: _mlRefreshTokenController, label: 'Refresh Token', icon: Icons.refresh),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: (ativo && !loading) • () => _testarConexao('mercadolivre') : null,
                        icon: loading • const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.wifi_tethering),
                        label: Text(loading • 'Testando...' : 'Testar conexão'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: (ativo && !loading) • () => _sincronizarProdutos('mercadolivre') : null,
                        icon: const Icon(Icons.sync),
                        label: const Text('Sincronizar'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => _mostrarAjudaMercadoLivre(),
                      icon: const Icon(Icons.help_outline),
                      label: const Text('Como obter tokens?'),
                    ),
                    TextButton.icon(
                      onPressed: () => _abrirUrl(MarketplaceService.linksDocumentacao['mercadolivre']!),
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('Documentação'),
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

  void _mostrarAjudaMercadoLivre() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🟡 Como configurar Mercado Livre'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('PASSO 1: Criar App no ML Developers', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              SizedBox(height: 8),
              Text('1. Acesse: developers.mercadolivre.com.br\n2. "Meus Aplicativos" → "Criar"\n3. Redirect URI: https://app.mastepalm.com.br/callback\n4. Permissions: read, write, offline_access'),
              SizedBox(height: 16),
              Text('PASSO 2: Obter tokens', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              SizedBox(height: 8),
              Text('1. Copie Client ID e Client Secret do app\n2. Use a URL de autorização para obter o code\n3. Troque o code por Access Token e Refresh Token'),
              SizedBox(height: 16),
              Text('⚠️ IMPORTANTE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.orange)),
              Text('Access Token expira em ~6h. Com Client ID, Secret e Refresh Token, o app renova automaticamente.'),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('ENTENDI'))],
      ),
    );
  }

  Widget _buildShopeeSection() {
    final shopee = _config['shopee'] as Map<String, dynamic>• ?• {};
    final ativo = shopee['ativo'] == true;
    final loading = _loadingMarketplace == 'shopee';
    final ultima = _ultimaSincronizacao['shopee'];

    return Card(
      child: ExpansionTile(
        leading: const Text('🛍️', style: TextStyle(fontSize: 32)),
        title: const Text('Shopee', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ativo • '✅ Configurado' : '⚠️ Não configurado', style: TextStyle(color: ativo • Colors.green : Colors.orange)),
            if (ultima != null)
              Text('Última sync: ${ultima.hour.toString().padLeft(2, '0')}:${ultima.minute.toString().padLeft(2, '0')}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _shopeePartnerIdController,
                  decoration: const InputDecoration(
                    labelText: 'Partner ID',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.badge),
                  ),
                ),
                const SizedBox(height: 12),
                _campoToken(controller: _shopeePartnerKeyController, label: 'Partner Key', icon: Icons.key),
                const SizedBox(height: 12),
                TextField(
                  controller: _shopeeShopIdController,
                  decoration: const InputDecoration(
                    labelText: 'Shop ID',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.store),
                  ),
                ),
                const SizedBox(height: 12),
                _campoToken(controller: _shopeeAccessTokenController, label: 'Access Token', icon: Icons.vpn_key, obscureDefault: false),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: (ativo && !loading) • () => _testarConexao('shopee') : null,
                        icon: loading • const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.wifi_tethering),
                        label: Text(loading • 'Testando...' : 'Testar conexão'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: (ativo && !loading) • () => _sincronizarProdutos('shopee') : null,
                        icon: const Icon(Icons.sync),
                        label: const Text('Sincronizar'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => _mostrarAjudaShopee(),
                      icon: const Icon(Icons.help_outline),
                      label: const Text('Como obter credenciais?'),
                    ),
                    TextButton.icon(
                      onPressed: () => _abrirUrl(MarketplaceService.linksDocumentacao['shopee']!),
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('Documentação'),
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

  void _mostrarAjudaShopee() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🛍️ Como configurar Shopee'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('PASSO 1: Acessar Shopee Open Platform', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              SizedBox(height: 8),
              Text('1. Acesse: open.shopee.com\n2. "Console" → "Criar Aplicativo"\n3. Marque: Product, Orders, Logistics'),
              SizedBox(height: 16),
              Text('PASSO 2: Obter Credenciais', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              SizedBox(height: 8),
              Text('Após aprovação: Partner ID, Partner Key, Shop ID. Gere o Access Token no console.'),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('ENTENDI'))],
      ),
    );
  }

  Widget _buildOutrosMarketplacesSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Outros Marketplaces', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _buildMarketplaceItem('Amazon', '📦', false),
            _buildMarketplaceItem('Magazine Luiza', '🔵', false),
            _buildMarketplaceItem('Americanas', '🔴', false),
            _buildMarketplaceItem('Casas Bahia', '🟠', false),
            const SizedBox(height: 12),
            const Text('⚠️ Disponíveis em breve', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }

  Widget _buildMarketplaceItem(String nome, String emoji, bool ativo) {
    return ListTile(
      leading: Text(emoji, style: const TextStyle(fontSize: 24)),
      title: Text(nome),
      trailing: Chip(
        label: Text(ativo • 'Ativo' : 'Em breve'),
        backgroundColor: ativo • Colors.green.shade100 : Colors.grey.shade200,
      ),
    );
  }

  Widget _buildBotaoSalvar() {
    return ElevatedButton.icon(
      onPressed: _loading • null : _salvar,
      icon: const Icon(Icons.save),
      label: const Text('SALVAR CONFIGURAÇÕES'),
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 56),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
    );
  }
}
