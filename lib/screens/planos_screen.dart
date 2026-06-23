// lib/screens/planos_screen.dart
// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform, debugPrint;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import '../core/plan_renewal_messages.dart';
import '../services/planos_service.dart';
import '../services/checkout_service.dart';
import '../services/remote_config_service.dart';
import '../utils/role_utils.dart';

/// Preços exibidos (checkout continua definido no servidor).
const double _kPrecoBasico = 19.99;
const double _kPrecoIntermediario = 29.99;
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

  double get _economiaAnualVsIntermediario {
    const ref = _kPrecoIntermediario * 12;
    return ref - _priceAnual;
  }

  final PlanosService _svc = PlanosService();
  bool _loading = true;
  bool _loadingGratis = false;
  bool _loadingBasico = false;
  bool _loadingIntermediario = false;
  bool _loadingMensal = false;
  bool _loadingAnual = false;
  bool _loadingRenewal = false;
  bool _syncPilotLoading = false;
  final TextEditingController _supportLookupController = TextEditingController();
  bool _supportConsultLoading = false;
  String? _supportConsultResult;
  PlanInfo? _plan;
  /// Checkout de planos usa Cloud Function + Secret Manager (token MP não fica no app).
  bool _checkoutPlanoServidor = true;

  bool get _isRoot {
    try {
      if (!Hive.isBoxOpen('sessao')) return false;
      final email = FirebaseAuth.instance.currentUser?.email;
      if (RoleUtils.isRootEmail(email)) return true;
      final tipo = Hive.box('sessao').get('tipo_usuario')?.toString();
      return tipo == 'programador';
    } catch (_) {
      return false;
    }
  }

  bool get _isMobile {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  /// Assinatura paga com renovação ainda ativa (não é corte imediato de acesso).
  bool get _canOfferCancelRenewal =>
      _plan != null &&
      _plan!.isPaidSubscription &&
      !_plan!.manualOverride &&
      !_isRoot &&
      _plan!.cancelAtPeriodEnd != true &&
      _plan!.currentPeriodEnd != null &&
      _plan!.currentPeriodEnd!.isAfter(DateTime.now()) &&
      _plan!.isActive;

  bool get _canOfferReactivateRenewal =>
      _plan != null &&
      _plan!.isPaidSubscription &&
      _plan!.cancelAtPeriodEnd == true &&
      _plan!.currentPeriodEnd != null &&
      _plan!.currentPeriodEnd!.isAfter(DateTime.now());

  String _fmtBRL(double v) =>
      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$', decimalDigits: 2)
          .format(v);

  /// Traduz planId para português
  String _traduzirPlanId(String planId) {
    switch (planId) {
      case 'free_trial_30d':
        return 'Teste grátis (30 dias)';
      case 'free_trial_90d':
        return 'Teste grátis (90 dias)';
      case 'free_limited':
        return 'Free limitado';
      case 'basic_monthly':
        return 'Básico';
      case 'intermediate_monthly':
        return 'Intermediário';
      case 'pro_monthly':
        return 'Pro mensal';
      case 'pro_yearly':
        return 'Pro anual';
      case 'lifetime':
        return 'Acesso vitalício';
      default:
        return planId;
    }
  }

  /// Retorna mensagem de erro amigável
  String _mensagemErroAmigavel(Object e) {
    final renewalMsg = planRenewalErrorMessage(e);
    if (renewalMsg != null) return renewalMsg;

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
    if (s.contains('sessão inválida') ||
        s.contains('sessão expirada') ||
        s.contains('faça login novamente')) {
      return 'Sessão expirada. Faça login novamente.';
    }
    if (s.contains('muitas tentativas')) {
      return 'Muitas tentativas. Aguarde um minuto e tente de novo.';
    }
    if (s.contains('resposta inválida do servidor')) {
      return 'Resposta inválida do servidor. Tente de novo em instantes.';
    }
    if (s.contains('plano inválido')) {
      return 'Este plano não está disponível. Atualize o app ou contate o suporte.';
    }
    // Propaga mensagens curtas já amigáveis do backend (planCreatePreference, MP).
    final full = e.toString();
    if (full.startsWith('Exception: ')) {
      final inner = full.substring('Exception: '.length).trim();
      if (isInternalPlanRenewalErrorCode(inner)) {
        return planRenewalErrorMessage(e) ??
            'Ocorreu um erro. Tente novamente ou entre em contato com o suporte.';
      }
      if (inner.length >= 8 &&
          inner.length <= 200 &&
          !inner.contains('stacktrace') &&
          !inner.contains('at ')) {
        return inner;
      }
    }
    return 'Ocorreu um erro. Tente novamente ou escolha outra forma de pagamento.';
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

  @override
  void initState() {
    super.initState();
    Intl.defaultLocale ??= 'pt_BR';
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    _supportLookupController.dispose();
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

      var p = await _svc.fetchCurrentPlan(uid: user.uid, email: email);
      if (p != null) {
        try {
          await _svc.reconcilePlanStateWithBackend();
          final refreshed =
              await _svc.fetchCurrentPlan(uid: user.uid, email: email);
          if (refreshed != null) p = refreshed;
        } catch (e) {
          debugPrint('⚠️ [PlanosScreen] reconcile: $e');
        }
      }

      if (mounted) {
        setState(() {
          _plan = p;
          _checkoutPlanoServidor = true;
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
      await _svc.activateFreeTrialViaBackend(
        uid: user.uid,
        email: (user.email ?? '').trim().toLowerCase(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Teste completo ativado por 30 dias!')),
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

  Future<void> _assinarBasico() async {
    await _mostrarAvisoCheckout(() async {
      setState(() => _loadingBasico = true);
      try {
        await CheckoutService.abrirCheckoutPlano(
          titulo: 'MasterPalm Básico',
          preco: _kPrecoBasico,
          planoId: 'basic_monthly',
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Checkout aberto. O plano libera após confirmação do pagamento no servidor.',
            ),
            duration: Duration(seconds: 6),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ ${_mensagemErroAmigavel(e)}'),
            backgroundColor: Colors.red,
          ),
        );
      } finally {
        if (mounted) setState(() => _loadingBasico = false);
      }
    });
  }

  Future<void> _assinarIntermediario() async {
    await _mostrarAvisoCheckout(() async {
      setState(() => _loadingIntermediario = true);
      try {
        await CheckoutService.abrirCheckoutPlano(
          titulo: 'MasterPalm Intermediário',
          preco: _kPrecoIntermediario,
          planoId: 'intermediate_monthly',
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Checkout aberto. O plano libera após confirmação do pagamento no servidor.',
            ),
            duration: Duration(seconds: 6),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ ${_mensagemErroAmigavel(e)}'),
            backgroundColor: Colors.red,
          ),
        );
      } finally {
        if (mounted) setState(() => _loadingIntermediario = false);
      }
    });
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
            content: Text(
              'Checkout aberto. Após pagar, aguarde a confirmação no servidor — o plano libera quando o pagamento estiver aprovado no Mercado Pago.',
            ),
            duration: Duration(seconds: 6),
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
            content: Text(
              'Checkout aberto. Após pagar, aguarde a confirmação no servidor — o plano libera quando o pagamento estiver aprovado no Mercado Pago.',
            ),
            duration: Duration(seconds: 6),
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

  /// Somente root/programador: estado canônico billing v2 + sync manual (piloto).
  Widget _buildPilotBillingCard() {
    final user = FirebaseAuth.instance.currentUser;
    final rcGlobal = RemoteConfigService.useRecurringPlanBilling;
    final rcEffective = user != null
        ? RemoteConfigService.shouldUseRecurringPlanBilling(
            uid: user.uid,
            email: user.email,
          )
        : false;
    final snap = _plan == null
        ? null
        : PlanCanonicalBillingSnapshot.fromPlanInfo(_plan!);
    final hints = PilotBillingOperationHints.fromInputs(
      snapshot: snap,
      rcGlobal: rcGlobal,
      rcEffective: rcEffective,
    );
    final pilotTitleSuffix = snap == null
        ? ''
        : (snap.usesMercadoRecurringPlanBilling ? ' · doc v2' : ' · doc legado');

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        color: const Color(0xFF151520),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.teal.shade800, width: 0.5),
        ),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          iconColor: Colors.tealAccent,
          collapsedIconColor: Colors.tealAccent,
          title: Text(
            'Piloto billing v2$pilotTitleSuffix',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            'Checkout v2: global=${rcGlobal ? "on" : "off"} · '
            'efetivo=${rcEffective ? "sim" : "não"} · '
            'via=${!rcEffective ? "—" : (rcGlobal ? "RC global" : "allowlist")}',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          children: [
            Text(
              hints.asPilotSummaryLines,
              style: const TextStyle(
                color: Colors.tealAccent,
                fontSize: 11,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Dump canônico (users/{uid})',
              style: TextStyle(color: Colors.white38, fontSize: 10),
            ),
            const SizedBox(height: 4),
            SelectableText(
              snap == null
                  ? 'Sem snapshot (atualize ou faça login).'
                  : snap.asSupportText,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 11,
                fontFamily: 'monospace',
                height: 1.35,
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: (_syncPilotLoading || !hints.syncCallableLikelyUseful)
                    ? null
                    : _syncBillingV2Pilot,
                icon: _syncPilotLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        Icons.sync,
                        size: 18,
                        color: hints.syncCallableLikelyUseful
                            ? Colors.tealAccent
                            : Colors.white24,
                      ),
                label: Text(
                  _syncPilotLoading
                      ? 'Sincronizando…'
                      : 'Sincronizar com Mercado Pago (syncPlanSubscription)',
                  style: TextStyle(
                    color: hints.syncCallableLikelyUseful
                        ? Colors.tealAccent
                        : Colors.white24,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            if (!hints.syncCallableLikelyUseful)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Sync desativado até existir providerSubscriptionId no doc (após create ou webhook).',
                  style: TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ),
            if (RoleUtils.isRootEmail(
                FirebaseAuth.instance.currentUser?.email,
              )) ...[
              const Divider(height: 28, color: Colors.white24),
              const Text(
                'Consulta outra conta (e-mail root na lista interna, leitura)',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _supportLookupController,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'UID Firebase ou e-mail do usuário',
                  hintStyle: const TextStyle(color: Colors.white30),
                  filled: true,
                  fillColor: const Color(0xFF0D0D12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.teal.shade900),
                  ),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed:
                      _supportConsultLoading ? null : _consultSupportSnapshot,
                  icon: _supportConsultLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search, size: 18, color: Colors.amber),
                  label: Text(
                    _supportConsultLoading ? 'Consultando…' : 'Consultar',
                    style: const TextStyle(color: Colors.amber, fontSize: 13),
                  ),
                ),
              ),
              if (_supportConsultResult != null) ...[
                const SizedBox(height: 8),
                SelectableText(
                  _supportConsultResult!,
                  style: const TextStyle(
                    color: Colors.amberAccent,
                    fontSize: 11,
                    fontFamily: 'monospace',
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
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
              '1º Teste grátis (30 dias — contas novas)',
              style: TextStyle(color: _fluorGreen, fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 4),
            const Text(
              'Durante o trial você usa o app como no Pro: sem bloquear módulos. Contas antigas com trial de 90 dias continuam válidas até o fim do período.',
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.35),
            ),
            const SizedBox(height: 12),
            const Text(
              '2º Após o trial (Free limitado)',
              style: TextStyle(color: Colors.amber, fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 4),
            const Text(
              'Migração automática para Free limitado: seus dados permanecem. Aplicam-se limites (ex.: vendas/mês, produtos, clientes) e alguns módulos passam a pedir upgrade — sem apagar histórico.',
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.35),
            ),
            const SizedBox(height: 12),
            const Text(
              '3º Planos pagos (Básico, Intermediário, Pro)',
              style: TextStyle(color: _fluorBlue, fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 4),
            const Text(
              'Cada nível libera mais operações e integrações. O checkout é seguro pelo servidor; o plano só ativa após confirmação do Mercado Pago.',
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
        expiresText =
            'Plano com limites (30 produtos, 20 clientes, 10 vendas/mês, 1 foto/produto, 1 banner). Faça upgrade para liberar mais.';
      } else if (plan.currentPeriodEnd != null) {
        final d = plan.currentPeriodEnd!;
        expiresText =
            'Válido até ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
        final days = plan.daysLeft ?? 0;
        if (days > 0) {
          expiresText += ' · $days dias restantes';
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
                if (_checkoutPlanoServidor)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _fluorGreen.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _fluorGreen),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.verified_user, size: 16, color: _fluorGreen),
                        SizedBox(width: 6),
                        Text(
                          'Confirmação no servidor',
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
            if (plan != null &&
                plan.cancelAtPeriodEnd &&
                plan.currentPeriodEnd != null) ...[
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'Renovação cancelada. Seu plano continua ativo até '
                  '${plan.currentPeriodEnd!.day.toString().padLeft(2, '0')}/'
                  '${plan.currentPeriodEnd!.month.toString().padLeft(2, '0')}/'
                  '${plan.currentPeriodEnd!.year} — sem nova cobrança após essa data.',
                  style: TextStyle(
                    color: Colors.amber.shade200,
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
              ),
            ],
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
            if (_canOfferCancelRenewal) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.orange.shade200,
                  side: BorderSide(color: Colors.orange.shade400),
                ),
                onPressed: (_loading || _loadingRenewal)
                    ? null
                    : _confirmarCancelarRenovacao,
                icon: const Icon(Icons.event_busy, size: 18),
                label: const Text('Cancelar renovação'),
              ),
            ],
            if (_canOfferReactivateRenewal) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: _fluorGreen,
                  side: const BorderSide(color: _fluorGreen),
                ),
                onPressed:
                    (_loading || _loadingRenewal) ? null : _reativarRenovacao,
                icon: const Icon(Icons.autorenew, size: 18),
                label: const Text('Reativar renovação'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmarCancelarRenovacao() async {
    final p = _plan;
    if (p == null || p.currentPeriodEnd == null) return;
    final e = p.currentPeriodEnd!;
    final lim = '${e.day.toString().padLeft(2, '0')}/'
        '${e.month.toString().padLeft(2, '0')}/${e.year}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Cancelar renovação?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Você mantém o acesso completo até $lim. Depois disso, o app passa para o '
          'plano Free limitado (seus dados permanecem). Não haverá nova cobrança '
          'após essa data.',
          style: const TextStyle(color: Colors.white70, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Confirmar',
              style: TextStyle(color: Colors.orange.shade200),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _loadingRenewal = true);
    try {
      await _svc.cancelCurrentPlanRenewal(
        uid: user.uid,
        email: user.email ?? '',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            formatPlanRenewalCancelSuccess(
              planLabel: _traduzirPlanId(p.planId),
              periodEnd: p.currentPeriodEnd!,
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_mensagemErroAmigavel(e)),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _loadingRenewal = false);
        await _load();
      }
    }
  }

  Future<void> _syncBillingV2Pilot() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _syncPilotLoading = true);
    try {
      final r = await _svc.syncMercadoPlanSubscriptionFromBackend();
      if (!mounted) return;
      final msg = r.synced
          ? 'Sync MP: ok (status=${r.mpStatus ?? "?"})'
          : 'Sync MP: sem alteração (${r.reason ?? "—"})';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_mensagemErroAmigavel(e)),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _syncPilotLoading = false);
        await _load();
      }
    }
  }

  /// Diagnóstico somente leitura de outra conta (callable root-only).
  Future<void> _consultSupportSnapshot() async {
    final raw = _supportLookupController.text.trim();
    if (raw.isEmpty) return;
    setState(() {
      _supportConsultLoading = true;
      _supportConsultResult = null;
    });
    try {
      final looksEmail = raw.contains('@');
      final r = await _svc.getPlanBillingSnapshotForSupport(
        targetUid: looksEmail ? null : raw,
        targetEmail: looksEmail ? raw : null,
      );
      if (!mounted) return;
      setState(() => _supportConsultResult = r.asSupportText);
    } catch (e) {
      if (!mounted) return;
      setState(() => _supportConsultResult = _mensagemErroAmigavel(e));
    } finally {
      if (mounted) setState(() => _supportConsultLoading = false);
    }
  }

  Future<void> _reativarRenovacao() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _loadingRenewal = true);
    try {
      await _svc.reactivateCurrentPlanRenewal(
        uid: user.uid,
        email: user.email ?? '',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Renovação reativada. As próximas cobranças seguem o fluxo normal.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_mensagemErroAmigavel(e)),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _loadingRenewal = false);
        await _load();
      }
    }
  }

  bool _isPlanoAtual(String planKey) {
    if (_plan == null) return false;
    switch (planKey) {
      case 'gratis':
        return (_plan!.planId == 'free_trial_90d' ||
                _plan!.planId == 'free_trial_30d') &&
            _plan!.isActive;
      case 'free_limited':
        return _plan!.planId == 'free_limited';
      case 'basico':
        return _plan!.planId == 'basic_monthly' && _plan!.isActive;
      case 'intermediario':
        return _plan!.planId == 'intermediate_monthly' && _plan!.isActive;
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
          badge: 'Comece aqui',
          title: 'Teste tudo por 30 dias',
          subtitle: 'Depois migra para o Free limitado, sem apagar dados.',
          price: '${_fmtBRL(0)} / 30 dias',
          titleColor: const Color(0xFF7DD3FC),
          bullets: const [
            'Todos os módulos como no Pro durante o trial',
            'Contas antigas com trial de 90 dias seguem válidas até o fim',
            'Ao expirar: limites e bloqueios — sem perder cadastros',
          ],
          buttonLabel: 'Ativar teste grátis',
          onPressed: _ativarGratis90d,
          isLoading: _loadingGratis,
          isCurrent: _isPlanoAtual('gratis'),
        ),
      if (_plan?.planId == 'free_limited')
        _card(
          key: 'free_limited',
          badge: 'Continue grátis',
          title: 'Free limitado',
          subtitle: 'Ideal para começar · catálogo básico e pedidos via WhatsApp',
          price: '${_fmtBRL(0)} / mês',
          titleColor: const Color(0xFFE2E8F0),
          bullets: const [
            'Até 30 produtos, 20 clientes, 10 vendas/mês',
            '1 foto por produto · 1 banner · 1 usuário',
            'Upgrade libera compras, precificação, combos e relatórios',
          ],
          buttonLabel: 'Plano atual',
          onPressed: () async {},
          isLoading: false,
          isCurrent: _isPlanoAtual('free_limited'),
          buttonDisabled: true,
        ),
      _card(
        key: 'basico',
        badge: 'Organização',
        title: 'Básico',
        subtitle: 'Para organizar sua loja',
        price: '${_fmtBRL(_kPrecoBasico)} / mês',
        titleColor: _fluorGreen,
        bullets: const [
          '300 produtos · 500 clientes · 5 fotos/produto · 3 banners',
          'Estoque, vendas, clientes, contas a receber, relatório básico',
          'Sem fornecedores/compras/precificação/combos',
        ],
        buttonLabel: 'Assinar Básico',
        onPressed: _assinarBasico,
        isLoading: _loadingBasico,
        isCurrent: _isPlanoAtual('basico'),
      ),
      _card(
        key: 'intermediario',
        badge: 'Mais vendido',
        title: 'Intermediário',
        subtitle: 'Compras, precificação e combos para mais margem',
        price: '${_fmtBRL(_kPrecoIntermediario)} / mês',
        titleColor: const Color(0xFFA78BFA),
        bullets: const [
          '2.000 produtos · 3.000 clientes · 10 fotos · 10 banners · 3 usuários',
          'Fornecedores, compras, precificação, combos, pedidos',
          'Relatório financeiro, ranking, lucratividade, carrinhos abandonados',
        ],
        buttonLabel: 'Assinar Intermediário',
        onPressed: _assinarIntermediario,
        isLoading: _loadingIntermediario,
        isCurrent: _isPlanoAtual('intermediario'),
        highlightBorder: true,
      ),
      _card(
        key: 'mensal',
        badge: 'Pro',
        title: 'Pro mensal',
        subtitle: 'Gestão completa',
        price: '${_fmtBRL(_priceMensal)} / mês',
        titleColor: _fluorGreen,
        bullets: const [
          'Limites altos · equipe · IA · campanhas · integrações',
          'Vendedores, metas, fretes/cupons, Meta e marketplaces',
          'Tudo do Intermediário e muito mais',
        ],
        buttonLabel: 'Assinar Pro mensal',
        onPressed: _assinarMensal,
        isLoading: _loadingMensal,
        isCurrent: _isPlanoAtual('mensal'),
      ),
      _card(
        key: 'anual',
        badge: 'Melhor oferta',
        title: 'Pro anual',
        subtitle: 'Economize no anual · tudo do Pro',
        price: '${_fmtBRL(_priceAnual)} / ano',
        titleColor: const Color(0xFFFBBF24),
        economiaText: _economiaAnual > 0
            ? 'Economize ${_fmtBRL(_economiaAnual)} vs 12x Pro mensal'
            : (_economiaAnualVsIntermediario > 0
                ? 'Economize ${_fmtBRL(_economiaAnualVsIntermediario)} vs 12x Intermediário'
                : null),
        bullets: const [
          'Mesmo acesso do Pro mensal',
          'Renovação anual · previsibilidade de custo',
          'Destaque para quem quer escalar a operação',
        ],
        buttonLabel: 'Assinar Pro anual',
        onPressed: _assinarAnual,
        isLoading: _loadingAnual,
        isCurrent: _isPlanoAtual('anual'),
        highlightBorder: true,
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

                if (_isRoot) _buildPilotBillingCard(),

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
                        childAspectRatio: 0.62,
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
    String? badge,
    Color titleColor = _fluorGreen,
    bool highlightBorder = false,
    bool buttonDisabled = false,
  }) {
    final borderColor = isCurrent
        ? _fluorGreen
        : (highlightBorder ? const Color(0xFF6366F1) : Colors.transparent);
    final borderW = isCurrent ? 2.0 : (highlightBorder ? 1.5 : 0.0);
    return Semantics(
      button: true,
      label: '$title. $subtitle. $price. $buttonLabel',
      child: Card(
        color: const Color(0xFF141414),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: borderW > 0
              ? BorderSide(color: borderColor, width: borderW)
              : BorderSide.none,
        ),
        elevation: highlightBorder ? 12 : 8,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (badge != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: titleColor.withOpacity(0.45)),
                      ),
                      child: Text(
                        badge,
                        style: TextStyle(
                          color: titleColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
                ),
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
                style: TextStyle(
                  color: titleColor,
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
                    color: _fluorGreen.withOpacity(0.15),
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
                    disabledBackgroundColor: Colors.grey.withOpacity(0.3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: (isLoading || buttonDisabled) ? null : () => onPressed(),
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

