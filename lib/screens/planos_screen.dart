// lib/screens/planos_screen.dart
// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/planos_service.dart';
import '../services/checkout_service.dart';
import '../services/master_config_service.dart';
import '../services/remote_config_service.dart';
import '../utils/role_utils.dart';

class PlanosScreen extends StatefulWidget {
  const PlanosScreen({super.key});

  @override
  State<PlanosScreen> createState() => _PlanosScreenState();
}

class _PlanosScreenState extends State<PlanosScreen> with WidgetsBindingObserver {
  static const Color _fluorBlue = Color(0xFF00A8FF);
  static const Color _fluorGreen = Color(0xFF00FFA3);

  double get _priceMensal => RemoteConfigService.planoMensalPreco;
  double get _priceAnual => RemoteConfigService.planoAnualPreco;

  /// Economia no anual vs 12x mensal
  double get _economiaAnual {
    final anualEquiv = _priceMensal * 12;
    return anualEquiv - _priceAnual;
  }

  final PlanosService _svc = PlanosService();
  bool _loading = true;
  bool _loadingGratis = false;
  bool _loadingMensal = false;
  bool _loadingAnual = false;
  PlanInfo? _plan;
  bool _mpConfigurado = false;

  bool get _isRoot {
    try {
      if (!Hive.isBoxOpen('sessao')) return false;
      final email = FirebaseAuth.instance.currentUser?.email?.toLowerCase().trim();
      if (email == 'masterpalm26@gmail.com' || email == 'masterpalm@gmail.com' || email == 'admin@masterpalm.com') return true;
      final tipo = Hive.box('sessao').get('tipo_usuario')?.toString();
      return tipo == 'programador';
    } catch (_) {
      return false;
    }
  }

  /// Apenas root por e-mail (acesso à tela Master Config); admin/programador não.
  bool get _isRootAdmin =>
      RoleUtils.isRootEmail(FirebaseAuth.instance.currentUser?.email);

  bool get _isMobile {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  String _fmtBRL(double v) =>
      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$', decimalDigits: 2)
          .format(v);

  /// Traduz planId para português
  String _traduzirPlanId(String planId) {
    switch (planId) {
      case 'free_trial_90d':
        return 'Teste grátis';
      case 'free_limited':
        return 'Free limitado';
      case 'pro_monthly':
        return 'Mensal';
      case 'pro_yearly':
        return 'Anual';
      case 'lifetime':
        return 'Acesso vitalício';
      default:
        return planId;
    }
  }

  /// Retorna mensagem de erro amigável
  String _mensagemErroAmigavel(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('token') || s.contains('configurado')) {
      return 'Mercado Pago não está configurado. Peça ao administrador para configurar.';
    }
    if (s.contains('network') || s.contains('connection') || s.contains('socket')) {
      return 'Sem conexão com a internet. Verifique e tente novamente.';
    }
    if (s.contains('timeout')) {
      return 'A requisição demorou muito. Tente novamente.';
    }
    if (s.contains('TRIAL_ALREADY_USED')) {
      return 'Você já usou o plano grátis. Escolha mensal ou anual.';
    }
    return 'Ocorreu um erro. Tente novamente ou escolha outra forma de pagamento.';
  }

  void _mostrarErroMpNaoConfigurado() {
    final msg = _isRootAdmin
        ? 'Configure o Mercado Pago em Configurações Master (menu lateral) para receber pagamentos de planos.'
        : 'O Mercado Pago ainda não foi configurado. Entre em contato com o administrador para assinar um plano.';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: _fluorBlue),
            SizedBox(width: 12),
            Text('Mercado Pago', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(msg, style: const TextStyle(color: Colors.white70)),
        actions: [
          if (_isRootAdmin)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/master_login');
              },
              child: const Text('Configurar agora', style: TextStyle(color: _fluorGreen)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendi', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  Future<void> _mostrarAvisoCheckout(Future<void> Function() onConfirm) async {
    if (!_isMobile) {
      await onConfirm();
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.open_in_new, color: _fluorBlue),
            SizedBox(width: 12),
            Text('Abrir checkout', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'Você será redirecionado para o checkout do Mercado Pago. '
          'Após completar o pagamento, volte ao app automaticamente.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continuar', style: TextStyle(color: _fluorGreen)),
          ),
        ],
      ),
    );
    if (ok == true) await onConfirm();
  }

  Future<void> _mostrarDialogConfigurarMp() async {
    final accessTokenCtrl = TextEditingController();
    final publicKeyCtrl = TextEditingController();
    bool showToken = false;
    bool testing = false;
    bool saving = false;

    try {
      final config = await MasterConfigService.loadMasterConfig();
      accessTokenCtrl.text = config.mercadoPagoAccessToken ?? '';
      publicKeyCtrl.text = config.mercadoPagoPublicKey ?? '';
    } catch (_) {}

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.payment, color: _fluorGreen),
                SizedBox(width: 10),
                Text('Conectar Mercado Pago', style: TextStyle(color: Colors.white)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      final uri = Uri.parse('https://www.mercadopago.com.br/developers/panel/app');
                      if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
                    },
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Abrir painel do Mercado Pago'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _fluorGreen,
                      side: const BorderSide(color: _fluorGreen),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Cole as chaves da sua aplicação (Produção):',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: accessTokenCtrl,
                    obscureText: !showToken,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Access Token',
                      labelStyle: const TextStyle(color: Colors.white70),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(showToken ? Icons.visibility_off : Icons.visibility, color: Colors.white54, size: 20),
                        onPressed: () => setDialogState(() => showToken = !showToken),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: publicKeyCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Public Key',
                      labelStyle: TextStyle(color: Colors.white70),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: testing || saving
                              ? null
                              : () async {
                                  final token = accessTokenCtrl.text.trim();
                                  if (token.isEmpty) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      const SnackBar(content: Text('Digite o Access Token'), backgroundColor: Colors.orange),
                                    );
                                    return;
                                  }
                                  setDialogState(() => testing = true);
                                  final ok = await MasterConfigService.testMercadoPagoConnection(token);
                                  setDialogState(() => testing = false);
                                  if (!ctx.mounted) return;
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(
                                      content: Text(ok ? 'Conexão OK!' : 'Falha na conexão. Verifique o token.'),
                                      backgroundColor: ok ? Colors.green : Colors.red,
                                    ),
                                  );
                                },
                          icon: testing
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _fluorGreen))
                              : const Icon(Icons.wifi_tethering, size: 18, color: _fluorGreen),
                          label: Text(testing ? 'Testando...' : 'Testar'),
                          style: OutlinedButton.styleFrom(foregroundColor: _fluorGreen, side: const BorderSide(color: _fluorGreen)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: testing || saving
                              ? null
                              : () async {
                                  final token = accessTokenCtrl.text.trim();
                                  final publicKey = publicKeyCtrl.text.trim();
                                  if (token.isEmpty || publicKey.isEmpty) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      const SnackBar(content: Text('Preencha Access Token e Public Key'), backgroundColor: Colors.orange),
                                    );
                                    return;
                                  }
                                  setDialogState(() => saving = true);
                                  try {
                                    final email = FirebaseAuth.instance.currentUser?.email ?? 'programador';
                                    await MasterConfigService.updateMercadoPagoKeys(
                                      accessToken: token,
                                      publicKey: publicKey,
                                      updatedBy: email,
                                    );
                                    if (!ctx.mounted) return;
                                    Navigator.of(ctx).pop();
                                    _load();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Mercado Pago configurado!'), backgroundColor: Colors.green),
                                    );
                                  } catch (e) {
                                    if (ctx.mounted) {
                                      ScaffoldMessenger.of(ctx).showSnackBar(
                                        SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
                                      );
                                    }
                                  } finally {
                                    if (ctx.mounted) setDialogState(() => saving = false);
                                  }
                                },
                          icon: saving
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                              : const Icon(Icons.save, size: 18),
                          label: Text(saving ? 'Salvando...' : 'Salvar'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _fluorGreen,
                            foregroundColor: Colors.black,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Fechar', style: TextStyle(color: Colors.white54)),
              ),
            ],
          );
        },
      ),
    );
    accessTokenCtrl.dispose();
    publicKeyCtrl.dispose();
  }

  Widget _buildMpNaoConfiguradoBanner() {
    return Card(
      color: const Color(0xFF2A2A1A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _fluorGreen, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.payment, color: _fluorGreen, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Mercado Pago não configurado',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        _isRoot
                            ? 'Configure para receber pagamentos de planos mensais e anuais.'
                            : 'Assinaturas pagas indisponíveis. Contate o administrador.',
                        style: const TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_isRoot) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _mostrarDialogConfigurarMp,
                  icon: const Icon(Icons.link, size: 18),
                  label: const Text('Conectar Mercado Pago'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _fluorGreen,
                    foregroundColor: Colors.black,
                  ),
                ),
              ),
              if (_isRootAdmin) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pushNamed(context, '/master_login'),
                    icon: const Icon(Icons.settings, size: 18),
                    label: const Text('Ir para Configurações Master'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _fluorGreen,
                      side: const BorderSide(color: _fluorGreen),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    Intl.defaultLocale ??= 'pt_BR';
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/login');
        return;
      }
      final email = (user.email ?? '').trim().toLowerCase();

      final p = await _svc.fetchCurrentPlan(uid: user.uid, email: email);

      bool mpOk = false;
      try {
        final token = await MasterConfigService.getMercadoPagoAccessToken();
        mpOk = token != null && token.trim().isNotEmpty;
      } catch (_) {}

      if (mounted) {
        setState(() {
          _plan = p;
          _mpConfigurado = mpOk;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _ativarGratis90d() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _loadingGratis = true);
    try {
      await _svc.activateFreeTrial90d(
        uid: user.uid,
        email: (user.email ?? '').trim().toLowerCase(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plano grátis ativado por 90 dias!')),
      );
      Navigator.pushReplacementNamed(context, '/home');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_mensagemErroAmigavel(e)),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) setState(() => _loadingGratis = false);
      await _load();
    }
  }

  Future<void> _assinarMensal() async {
    await _mostrarAvisoCheckout(() async {
      setState(() => _loadingMensal = true);
      try {
        await CheckoutService.abrirCheckoutPlano(
          titulo: 'Plano Mensal MasterPalm',
          preco: _priceMensal,
          planoId: 'mensal',
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Checkout aberto! Complete o pagamento na janela do Mercado Pago.'),
            duration: Duration(seconds: 4),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ ${_mensagemErroAmigavel(e)}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      } finally {
        if (mounted) setState(() => _loadingMensal = false);
      }
    });
  }

  Future<void> _assinarAnual() async {
    await _mostrarAvisoCheckout(() async {
      setState(() => _loadingAnual = true);
      try {
        await CheckoutService.abrirCheckoutPlano(
          titulo: 'Plano Anual MasterPalm',
          preco: _priceAnual,
          planoId: 'anual',
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Checkout aberto! Complete o pagamento na janela do Mercado Pago.'),
            duration: Duration(seconds: 4),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ ${_mensagemErroAmigavel(e)}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      } finally {
        if (mounted) setState(() => _loadingAnual = false);
      }
    });
  }

  /// Card explicando como funcionam os planos (trial → free limitado → pago)
  Widget _buildComoFuncionaCard() {
    return Card(
      color: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          // ignore: prefer_const_literals_to_create_immutables
          children: [
            Row(
              // ignore: prefer_const_literals_to_create_immutables
              children: [
                Icon(Icons.info_outline, color: _fluorBlue, size: 22),
                const SizedBox(width: 8),
                const Text(
                  'Como funcionam os planos',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              '1º Teste grátis (90 dias)',
              style: TextStyle(color: _fluorGreen, fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 4),
            const Text(
              'Durante 90 dias você tem: 80 produtos, 150 clientes, 50 vendas por mês, 3 fotos por produto e até 6 banners. '
              'É suficiente para testar o app com sua loja.',
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.35),
            ),
            const SizedBox(height: 12),
            const Text(
              '2º Após os 90 dias (Free limitado)',
              style: TextStyle(color: Colors.amber, fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 4),
            const Text(
              'O plano vira Free limitado automaticamente — não bloqueia o acesso. Seus dados não são apagados: você continua vendo e editando todos os produtos e clientes já cadastrados. '
              'Os limites (10 produtos, 20 clientes, 10 vendas/mês, 1 foto por produto, 1 banner) valem só para adicionar coisas novas: não poderá cadastrar novo produto nem novo cliente até ficar dentro do limite ou assinar o plano pago. '
              'Para continuar crescendo sem reduzir nada, assine o Mensal ou Anual.',
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.35),
            ),
            const SizedBox(height: 12),
            const Text(
              '3º Planos Mensal e Anual (pago)',
              style: TextStyle(color: _fluorBlue, fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 4),
            const Text(
              'Produtos, clientes e vendas ilimitados. 6 fotos por produto e até 6 banners. Catálogo completo, relatórios, backup e suporte.',
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(PlanInfo? plan) {
    String statusLabel = 'Sem plano';
    String? expiresText;

    if (plan != null) {
      statusLabel = _traduzirPlanId(plan.planId);
      if (plan.status == 'active' || plan.status == 'trialing') {
        statusLabel = '$statusLabel (ativo)';
      } else if (plan.status == 'expired') {
        statusLabel = '$statusLabel (vencido)';
      }

      if (plan.isLifetime) {
        expiresText = 'Acesso permanente';
      } else if (plan.planId == 'free_limited') {
        expiresText = 'Plano com limites (10 produtos, 1 foto/produto, 10 vendas/mês, 20 clientes). Faça upgrade para liberar.';
      } else if (plan.currentPeriodEnd != null) {
        final d = plan.currentPeriodEnd!;
        expiresText =
            'Válido até ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
        final days = plan.daysLeft ?? 0;
        if (days > 0) {
          expiresText += ' • $days dias restantes';
        }
      }
    }

    return Semantics(
      container: true,
      label: 'Status do plano: $statusLabel. $expiresText',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Planos',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (_mpConfigurado)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _fluorGreen.withValues(alpha:0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _fluorGreen),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, size: 16, color: _fluorGreen),
                        SizedBox(width: 6),
                        Text(
                          'MP configurado',
                          style: TextStyle(color: _fluorGreen, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Seu status: $statusLabel',
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
            if (expiresText != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  expiresText,
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                ),
              ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: _fluorGreen,
                side: const BorderSide(color: _fluorGreen),
              ),
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Atualizar'),
            ),
          ],
        ),
      ),
    );
  }

  bool _isPlanoAtual(String planKey) {
    if (_plan == null) return false;
    switch (planKey) {
      case 'gratis':
        return _plan!.planId == 'free_trial_90d' && _plan!.isActive;
      case 'free_limited':
        return _plan!.planId == 'free_limited';
      case 'mensal':
        return _plan!.planId == 'pro_monthly' && _plan!.isActive;
      case 'anual':
        return _plan!.planId == 'pro_yearly' && _plan!.isActive;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final canShowFree =
        _plan == null ? true : (_plan!.trialUsed == false && _plan!.manualOverride == false);

    final cards = <Widget>[
      if (canShowFree)
        _card(
          key: 'gratis',
          title: 'Plano Grátis (90 dias)',
          subtitle: 'Até 80 produtos, 150 clientes, 50 vendas/mês. Após 90 dias, vira Free limitado.',
          price: '${_fmtBRL(0)} / 90 dias',
          bullets: const [
            'Durante o trial: 80 produtos, 150 clientes, 50 vendas/mês',
            '3 fotos por produto e até 6 banners (desktop + mobile)',
            'Após 90 dias: Free limitado (10 produtos, 1 foto/produto, 10 vendas/mês, 20 clientes)',
            'Faça upgrade para liberar mais',
          ],
          buttonLabel: 'Ativar grátis (90 dias)',
          onPressed: _ativarGratis90d,
          isLoading: _loadingGratis,
          isCurrent: _isPlanoAtual('gratis'),
        ),
      _card(
        key: 'mensal',
        title: 'Plano Mensal',
        subtitle: 'Tudo liberado',
        price: '${_fmtBRL(_priceMensal)} / mês',
        bullets: const [
          'Produtos, clientes e vendas ilimitados',
          '6 fotos por produto e até 6 banners',
          'Catálogo completo, relatórios e backup',
          'Suporte',
        ],
        buttonLabel: _mpConfigurado ? 'Assinar mensal' : 'Mercado Pago não configurado',
        onPressed: _mpConfigurado ? _assinarMensal : () async => _mostrarErroMpNaoConfigurado(),
        isLoading: _loadingMensal,
        isCurrent: _isPlanoAtual('mensal'),
      ),
      _card(
        key: 'anual',
        title: 'Plano Anual',
        subtitle: 'Mais barato no ano',
        price: '${_fmtBRL(_priceAnual)} / ano',
        economiaText: _economiaAnual > 0 ? 'Economize ${_fmtBRL(_economiaAnual)} no ano' : null,
        bullets: const [
          'Tudo do mensal',
          'Benefícios extras',
          'Melhor custo-benefício',
          'Suporte prioritário',
        ],
        buttonLabel: _mpConfigurado ? 'Assinar anual' : 'Mercado Pago não configurado',
        onPressed: _mpConfigurado ? _assinarAnual : () async => _mostrarErroMpNaoConfigurado(),
        isLoading: _loadingAnual,
        isCurrent: _isPlanoAtual('anual'),
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF101010),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Planos'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _header(_plan),
                const SizedBox(height: 16),
                _buildComoFuncionaCard(),
                const SizedBox(height: 16),

                if (!_mpConfigurado) ...[
                  _buildMpNaoConfiguradoBanner(),
                  const SizedBox(height: 16),
                ],

                if (_isRoot)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Card(
                      color: const Color(0xFF1A1A2E),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: const Icon(Icons.manage_accounts, color: Colors.purpleAccent),
                        title: const Text(
                          'Gerenciar Usuários & Planos',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        subtitle: const Text(
                          'Liberar acesso vitalício, 90 dias, 1 ano ou revogar',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 16),
                        onTap: () => Navigator.pushNamed(context, '/admin_usuarios'),
                      ),
                    ),
                  ),

                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 600;
                    if (isWide) {
                      return GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: constraints.maxWidth >= 900 ? 3 : 2,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: 0.75,
                        children: cards,
                      );
                    }
                    return Column(
                      children: cards.map((c) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: c,
                      )).toList(),
                    );
                  },
                ),
              ],
            ),
    );
  }

  Widget _card({
    required String key,
    required String title,
    required String subtitle,
    required String price,
    required List<String> bullets,
    required String buttonLabel,
    required Future<void> Function() onPressed,
    bool isLoading = false,
    bool isCurrent = false,
    String? economiaText,
  }) {
    return Semantics(
      button: true,
      label: '$title. $subtitle. $price. $buttonLabel',
      child: Card(
        color: const Color(0xFF141414),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: isCurrent
              ? const BorderSide(color: _fluorGreen, width: 2)
              : BorderSide.none,
        ),
        elevation: 8,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isCurrent)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle, color: _fluorGreen, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Seu plano atual',
                        style: TextStyle(
                          color: _fluorGreen,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _fluorGreen,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              Text(
                price,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (economiaText != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _fluorGreen.withValues(alpha:0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    economiaText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _fluorGreen,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              ...bullets.map((b) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('• ', style: TextStyle(color: Colors.white70)),
                        Expanded(
                          child: Text(
                            b,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                      ],
                    ),
                  )),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _fluorBlue,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: Colors.grey.withValues(alpha:0.3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: isLoading ? null : () => onPressed(),
                  child: isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : Text(
                          buttonLabel,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}

