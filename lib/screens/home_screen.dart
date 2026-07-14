// lib/screens/home_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:hive/hive.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/hive_box_names.dart';
import '../services/permissao_service.dart';
import '../widgets/vendedor_aguarde_widget.dart';
import 'package:master_palm/widgets/responsive_shell.dart';
import '../utils/responsive.dart';
import '../screens/admin_login.dart';
import '../screens/relatorios_financeiros_screen.dart';
import '../screens/pre_pedidos_screen.dart';
import 'loja_config_screen.dart';
import '../services/license_manager.dart';
import '../utils/migrar_para_estoque.dart';
import '../services/loja_id_service.dart';
import '../services/store_resolver_facade.dart';
import '../services/session_sanity.dart';
import '../services/produtos_firestore_service.dart';
import '../services/clientes_firestore_service.dart';
import '../services/fornecedores_firestore_service.dart';
import '../services/vendas_firestore_service.dart';
import '../services/importar_vendas_firestore_service.dart';
import '../services/reconciliacao_vendas_clientes_service.dart';
import '../services/firestore_critical_listener_service.dart';
import '../services/auto_sync_service.dart';
import '../services/sync_queue_service.dart';
import '../models/produto.dart';
import '../models/cliente.dart';
import '../models/fornecedor.dart';
import '../models/venda.dart';
import '../services/conta_receber_service.dart';

// ✅ tela fretes/cupons
import '../screens/fretes_cupons_screen.dart';
import '../screens/carrinhos_abandonados_screen.dart';

// ✅ canais meta (WhatsApp, Instagram, Messenger)
import 'configuracoes/canais_meta_screen.dart';

// ✅ sorteios
import 'campanhas_sorteio_screen.dart';
import 'globo_sorteio_screen.dart';

// ✅ M3.8 Sprint 2 — dashboards marketing
import 'marketing/marketing_hub_screen.dart';
import 'marketing/campanhas_dashboard_screen.dart';
import 'marketing/roleta_dashboard_screen.dart';
import 'marketing/marketing_estatisticas_screen.dart';
import '../widgets/home_quick_actions_row.dart';
import '../widgets/home_portal_grid.dart';
import '../widgets/dashboard_home_cards.dart';
import '../screens/home_portal_category_screen.dart';
import '../core/home_module_registry.dart';
import '../core/app_module_definition.dart';
import '../screens/configure_loja_placeholder_screen.dart';

// ✅ sistema de comissões
import 'metas_comissoes_screen.dart';

// ✅ planos
import '../services/planos_service.dart';
import '../utils/theme_notifier.dart';

// ✅ notas fiscais
import '../screens/notas_fiscais_screen.dart';
import '../screens/contas_receber_screen.dart';
import '../screens/contas_pagar_screen.dart';

// ✅ consolidação de lojas
import '../screens/consolidate_stores_screen.dart';

// ✅ marketplaces / ERP
import '../screens/marketplaces_screen.dart';

import '../services/app_update_service.dart';
import '../services/remote_config_service.dart';
import 'package:intl/intl.dart';
import '../services/notificacao_centro_service.dart';
import '../widgets/update_app_dialog.dart';
import '../widgets/notificacao_centro_sheet.dart';
import '../widgets/app_help_icon_button.dart';
import '../utils/catalog_payment_support_nav.dart';
import 'onboarding_app_screen.dart';
import 'global_search_screen.dart';
import 'dicas_ia_screen.dart';
import 'textos_whatsapp_ia_screen.dart';
import 'gerar_postagem_screen.dart';
import 'compartilhar_whatsapp_screen.dart';
import 'analise_vendas_ia_screen.dart';
import 'dashboard_insights_screen.dart';
import '../motor_crescimento/screens/motor_crescimento_screen.dart';
import '../motor_crescimento_automacoes/screens/campanhas_sugeridas_screen.dart';
import '../core/logger.dart';
import '../core/plan_matrix.dart';
import '../core/plan_access_resolver.dart';
import '../widgets/plan_gated_screen.dart';
import '../utils/store_screen_route_observer.dart';
import '../services/catalog_public_url_service.dart';
import '../services/public_store_link_helper.dart';
import '../utils/home_store_context_helper.dart';
// WebLandingPlanCard é declarado no final deste arquivo para evitar problemas de resolução de import.
import '../main.dart' show navigatorKey;
import '../utils/role_utils.dart';
import '../debug/boot_perf_log.dart';
import '../core/loja_id_adapter.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, RouteAware {
  // Cores do tema moderno
  static const Color _primaryColor = Color(0xFF6366F1); // Indigo
  static const Color _successColor = Color(0xFF22C55E); // Green
  static const Color _warningColor = Color(0xFFF59E0B); // Amber
  static const Color _errorColor = Color(0xFFEF4444); // Red
  static const Color _cardColor = Color(0xFFFFFFFF);
  static const Color _backgroundColor = Color(0xFFF8FAFC);
  static const Color _surfaceColor = Color(0xFF1E293B);

  String _usuario = '';
  String _tipo = 'vendedor';

  /// Identificador interno da loja ativa (Hive, Firestore, Motor, Campanhas, Painel).
  String _lojaIdInterno = '';

  /// Slug/identificador público para link e catálogo (pode ser igual ao interno).
  String _lojaSlugPublico = '';

  /// URL pública do catálogo (domínio próprio ou hosted).
  String? _catalogOnlineUrl;
  bool _carregando = true;
  bool _vendedorSemPermissao =
      false; // ✅ Vendedor sem nenhuma permissão liberada

  /// Recria [FutureBuilder]s após falha em carregamento Home / menu.
  int _homeCardsRetryKey = 0;
  int _homeSidebarMenuRetryKey = 0;
  int _homeDrawerMenuRetryKey = 0;

  @override
  void initState() {
    super.initState();
    BootPerfLog.markBoot('home_init');

    _carregarSessao();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      BootPerfLog.markBoot('home_first_paint');
    });

    // Atualiza acesso efetivo para gates da Home (cortesia, assinatura paga, etc.)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refreshPlanGates(force: true));
    });

    // Sincronização automática ao entrar (paridade Web/APK – vendas de qualquer plataforma aparecem em todas)
    // Web: atraso maior para não competir com scroll/gestos logo após o login.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(Duration(milliseconds: kIsWeb ? 1400 : 220), () {
        BootPerfLog.markBoot('initial_sync_start');
        if (!mounted) return;
        AutoSyncService.syncCompleto().then((r) {
          BootPerfLog.markBoot('initial_sync_end', detail: 'ok=${r.sucesso}');
          if (mounted) {
            setState(() {}); // Atualiza dashboard quando sync terminar
          }
        }).catchError((_) {
          BootPerfLog.markBoot('initial_sync_end', detail: 'erro');
        });
      });
    });

    // 🔐 Checagem de licença só para ADMIN (não afeta programador/root)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final sessao = await Hive.openBox('sessao');

      // Recalcula tipo (com ROOT override) aqui também, por segurança
      final user = FirebaseAuth.instance.currentUser;
      final email = (user?.email ?? '').trim().toLowerCase();
      final isRoot =
          (sessao.get('is_root') == true) || RoleUtils.isRootEmail(email);

      final tipoHive = (sessao.get('tipo_usuario') as String?) ?? 'vendedor';
      final tipoEfetivo = isRoot ? 'programador' : tipoHive;

      if (tipoEfetivo == 'admin') {
        final ok = await LicenseManager.hasValidAccessFallbackLegacy();
        if (!mounted) return;
        if (!ok) {
          Navigator.pushReplacementNamed(context, '/planos');
          return;
        }
      }

      // ✅ Gate do plano + avisos
      await _checkPlanAndMaybeWarn();

      // ✅ Carregar centro de notificações para o badge
      await NotificacaoCentroService().getUnreadCount();
    });
  }

  Future<void> _carregarSessao() async {
    final sessao = await Hive.openBox('sessao');

    // pega o usuário atual (pra resolver root de forma 100% confiável)
    final user = FirebaseAuth.instance.currentUser;
    final emailAuth = (user?.email ?? '').trim().toLowerCase();

    _usuario = (sessao.get('usuario_logado') as String?) ??
        (emailAuth.isNotEmpty ? emailAuth : 'Usuário');
    _tipo = (sessao.get('tipo_usuario') as String?) ?? 'vendedor';

    // Fast path: store_id em cache (Hive) → 1º paint sem esperar Firestore.
    final cachedUser = (sessao.get('usuario_logado') ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final cachedStore = normalizeFromBox(sessao)?.trim() ?? '';
    if (cachedStore.isNotEmpty &&
        emailAuth.isNotEmpty &&
        (cachedUser.isEmpty || cachedUser == emailAuth) &&
        isValidForPublicLink(cachedStore)) {
      _lojaIdInterno = cachedStore;
      _lojaSlugPublico = cachedStore;
      if (mounted) setState(() => _carregando = false);
      BootPerfLog.markBoot('home_cached_store', detail: cachedStore);
    }

    // 🔹 contexto de loja: StoreResolver (Firestore) + fallback Hive validado.
    BootPerfLog.markBoot('store_context_start');
    final ctx = await resolveHomeStoreContext();
    BootPerfLog.markBoot('store_context_end', detail: ctx.lojaIdInterno);
    _lojaIdInterno = ctx.lojaIdInterno;
    _lojaSlugPublico = ctx.slugPublico;
    if (_lojaIdInterno.isNotEmpty && isValidForPublicLink(_lojaIdInterno)) {
      sessao.put('store_id', _lojaIdInterno);
      logD('📋 [HOME] store_id persistido na sessão: $_lojaIdInterno');
    }
    if (_lojaSlugPublico.isEmpty &&
        _lojaIdInterno.isNotEmpty &&
        isValidForPublicLink(_lojaIdInterno)) {
      _lojaSlugPublico = _lojaIdInterno;
    }
    logD(
        '📋 [HOME] contexto loja: interno=${_lojaIdInterno.isNotEmpty ? "ok" : "vazio"} slugPublico=${_lojaSlugPublico.isNotEmpty ? "ok" : "vazio"}');

    // ✅ ROOT override (impede "root virar vendedor")
    final isRoot = (sessao.get('is_root') == true) ||
        RoleUtils.isRootEmail(emailAuth) ||
        RoleUtils.isRootEmail(_usuario);
    if (isRoot) {
      // força apenas no app (e grava no hive pra não ficar voltando)
      _tipo = 'programador';
      sessao.put('is_root', true);
      sessao.put('tipo_usuario',
          'programador'); // <- pode trocar pra 'admin' se quiser
    }

    // ✅ VENDEDOR: Verificar se tem alguma permissão liberada
    if (_tipo == 'vendedor' && !isRoot) {
      final temPermissao = await PermissaoService.vendedorTemAlgumaPermissao();
      _vendedorSemPermissao = !temPermissao;
    }

    // Listener em tempo real de permissões (admin/vendedor)
    // ✅ Usar _lojaIdInterno (já resolvido via StoreResolver) em vez de sessao direto
    if (user != null) {
      final storeId = (_lojaIdInterno.isNotEmpty
              ? _lojaIdInterno
              : (sessao.get('store_id') ?? sessao.get('storeId') ?? '')
                  .toString()
                  .trim())
          .trim();
      FirestoreCriticalListenerService.startPermissoesListener(
        userEmail: user.email ?? _usuario,
        tipoUsuario: _tipo,
        storeId: storeId.isNotEmpty ? storeId : null,
        userUid: user.uid,
      );
    }

    if (mounted) setState(() => _carregando = false);
    BootPerfLog.markBoot('dashboard_data_loaded', detail: 'shell');

    final lidForCatalogUrl = _lojaIdInterno.isNotEmpty
        ? _lojaIdInterno
        : (_lojaSlugPublico.isNotEmpty ? _lojaSlugPublico : '');
    if (lidForCatalogUrl.isNotEmpty) {
      unawaited(() async {
        try {
          final url = await CatalogPublicUrlService.montarUrlCatalogoPublicoAsync(
            lidForCatalogUrl,
            slug: _lojaSlugPublico.isNotEmpty ? _lojaSlugPublico : null,
          );
          if (!mounted) return;
          setState(() => _catalogOnlineUrl = url);
        } catch (_) {
          if (!mounted) return;
          setState(
            () => _catalogOnlineUrl = buildPublicCatalogUrl(
              _lojaSlugPublico.isNotEmpty ? _lojaSlugPublico : lidForCatalogUrl,
            ),
          );
        }
      }());
    } else {
      _catalogOnlineUrl = null;
    }

    // Contas a receber: abrir box + varrer valores no isolate principal atrasa scroll/UI —
    // rodar após 1º frame + pequeno delay (dialog continua igual quando necessário).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 500), () {
        if (mounted) unawaited(_alertarContasReceberPendentes());
      });
    });

    // ✅ Onboarding (primeira vez): exibir após sessão carregada
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final done = await isOnboardingAppDone();
        if (!mounted) return;
        if (!done) {
          await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => OnboardingAppScreen(
                onDone: () => Navigator.of(context).pop(true),
              ),
            ),
          );
          if (mounted) setState(() {});
        }
      });
    }
  }

  Future<void> _alertarContasReceberPendentes() async {
    if (!mounted || _lojaIdInterno.trim().isEmpty) return;
    try {
      final box = await ContaReceberService.openBoxLoja(_lojaIdInterno.trim());
      if (!mounted) return;

      final hoje = DateTime.now();
      final hojeBase = DateTime(hoje.year, hoje.month, hoje.day);
      final pendentes = ContaReceberService.listar(
        contas: box.values,
        lojaId: _lojaIdInterno,
        filtro: 'pendentes',
      );
      if (pendentes.isEmpty) return;

      final vencidas = pendentes.where((c) {
        final d = DateTime(
          c.dataVencimento.year,
          c.dataVencimento.month,
          c.dataVencimento.day,
        );
        return d.isBefore(hojeBase);
      }).toList();
      final vencendo = pendentes.where((c) {
        final d = DateTime(
          c.dataVencimento.year,
          c.dataVencimento.month,
          c.dataVencimento.day,
        );
        final dias = d.difference(hojeBase).inDays;
        return dias >= 0 && dias <= 2;
      }).toList();
      if (vencidas.isEmpty && vencendo.isEmpty) return;

      final valorTotal =
          (vencidas + vencendo).fold<double>(0, (s, c) => s + c.valor);

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Lembrete de cobrança'),
          content: Text(
            'Você tem ${vencidas.length} conta(s) em atraso e '
            '${vencendo.length} vencendo em até 2 dias.\n\n'
            'Total pendente: R\$ ${valorTotal.toStringAsFixed(2).replaceAll('.', ',')}.\n'
            'Esse aviso continuará aparecendo até as contas serem quitadas.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Lembrar depois'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ContasReceberScreen(),
                  ),
                );
              },
              child: const Text('Abrir contas a receber'),
            ),
          ],
        ),
      );
    } catch (_) {
      // Aviso não pode bloquear a Home caso a box não esteja disponível.
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      storeScreenRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPopNext() {
    unawaited(_refreshPlanGates(force: true));
  }

  Future<void> _refreshPlanGates({bool force = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      PlanosService().clearEffectivePlanCache();
      return;
    }
    if (_tipo == 'admin') {
      await PlanosService().refreshEffectivePlanAccess(force: force);
    }
    if (!mounted) return;
    setState(() {
      _homeCardsRetryKey++;
      _homeSidebarMenuRetryKey++;
      _homeDrawerMenuRetryKey++;
    });
  }

  Future<PlanAccessTier> _resolveMenuPlanTier() async {
    if (_tipo != 'admin') return PlanAccessTier.lifetime;
    return PlanAccessResolver.currentTier();
  }

  @override
  void dispose() {
    storeScreenRouteObserver.unsubscribe(this);
    FirestoreCriticalListenerService.cancelPermissoesListener();
    super.dispose();
  }

  // ✅ Gate do plano + avisos internos 15/10/5/0
  Future<void> _checkPlanAndMaybeWarn() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final email = (user.email ?? '').trim().toLowerCase();

      final svc = PlanosService();

      // Só lê (não cria automaticamente aqui).
      PlanInfo? plan = await svc.fetchCurrentPlan(uid: user.uid, email: email);
      if (!mounted) return;

      // fetch null (timeout/rede) não pode sobrepor o mesmo critério do Splash/LicenseManager.
      if (plan == null) {
        final stillOk = await LicenseManager.hasValidAccessFallbackLegacy();
        if (!mounted) return;
        if (!stillOk) {
          Navigator.pushReplacementNamed(context, '/planos');
        }
        return;
      }

      if (plan.isLifetime) return;

      DateTime? end = plan.currentPeriodEnd;
      if (end == null) {
        // free_limited não usa currentPeriodEnd (limites numéricos) — mesmo critério que [app_start_router].
        if (plan.planId == 'free_limited') return;
        if (PlanosService.planGrantsAdminAppAccess(plan)) return;

        final rescue = await LicenseManager.hasValidAccessFallbackLegacy();
        if (!mounted) return;
        if (!rescue) {
          await FirebaseAuth.instance.signOut();
          if (!mounted) return;
          Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
          return;
        }
        final refreshed =
            await svc.fetchCurrentPlan(uid: user.uid, email: email);
        if (!mounted) return;
        if (refreshed != null) plan = refreshed;
        end = plan.currentPeriodEnd ?? await LicenseManager.getCachedExpiry();
        if (end == null && !PlanosService.planGrantsAdminAppAccess(plan)) {
          await FirebaseAuth.instance.signOut();
          if (!mounted) return;
          Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
          return;
        }
        if (end == null) return;
      }

      final daysLeft = end.difference(DateTime.now()).inDays;

      // Venceu: marca expired e desloga
      if (daysLeft < 0) {
        await svc.markExpiredIfNeeded(uid: user.uid, email: email);
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
        return;
      }

      // Avisos: 15, 10, 5, 0
      const triggers = [15, 10, 5, 0];
      if (triggers.contains(daysLeft)) {
        if (!mounted) return;
        _showPlanWarningSheet(daysLeft);
      }
    } catch (_) {
      // silêncio
    }
  }

  void _showPlanWarningSheet(int daysLeft) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: _cardColor,
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
                color: _warningColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.warning_amber_rounded,
                  size: 48, color: _warningColor),
            ),
            const SizedBox(height: 16),
            const Text(
              'Seu plano está vencendo',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Faltam $daysLeft dias para vencer seu plano.',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Depois'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/planos');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Assinar'),
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

  // ✅ logout limpa sessao + config + cache multi-tenant
  Future<void> fazerLogout(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut();

      // ✅ CRÍTICO: Limpar cache de loja para evitar mistura multi-tenant
      await SessionSanity.clearAllStoreCache();

      if (Hive.isBoxOpen('sessao')) {
        await Hive.box('sessao').clear();
      } else {
        final box = await Hive.openBox('sessao');
        await box.clear();
      }

      if (Hive.isBoxOpen('config')) {
        await Hive.box('config').clear();
      } else {
        final box = await Hive.openBox('config');
        await box.clear();
      }

      if (!context.mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
    } catch (e) {
      logD("Erro ao deslogar (type=${e.runtimeType})");
    }
  }

  // ✅ Migração de dados para coleções estoque_*
  Future<void> _migrarDados() async {
    try {
      // Confirmação via bottom sheet
      final confirm = await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (ctx) => Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: _cardColor,
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
                  color: _warningColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.cloud_sync,
                    size: 48, color: _warningColor),
              ),
              const SizedBox(height: 16),
              const Text(
                'Migração de Dados',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                'Esta operação irá copiar todos os dados das coleções antigas para as novas coleções de backup.\n\n'
                'Isso garante que seus dados persistam mesmo ao desinstalar o aplicativo.\n\n'
                'Execute esta operação UMA VEZ apenas.',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _warningColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Migrar Agora'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      );

      if (confirm != true) return;

      // Obter lojaId
      final lojaId = await StoreResolverFacade.resolveForAdminApp();
      if (lojaId == null || lojaId.isEmpty) {
        if (!mounted) return;
        _showSnackBar('Não foi possível determinar a loja atual',
            isError: true);
        return;
      }

      // Mostrar loading
      if (!mounted) return;
      _showLoadingDialog(
          'Migrando dados...\nAguarde, isso pode levar alguns minutos.');

      // Executar migração
      await migrarParaEstoque(lojaId);

      // Fechar loading
      if (!mounted) return;
      Navigator.pop(context);

      // Mostrar sucesso
      if (!mounted) return;
      _showSuccessSheet(
        'Migração Concluída!',
        'Todos os dados foram migrados com sucesso!\n\n'
            'Agora seus produtos, clientes, fornecedores e vendas '
            'persistirão mesmo ao desinstalar o aplicativo.',
      );
    } catch (e) {
      logD('Erro na migração (type=${e.runtimeType})');

      // Fechar loading se estiver aberto
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      // Mostrar erro
      if (!mounted) return;
      _showSnackBar('Erro na migração: $e', isError: true);
    }
  }

  // ✅ Importação de dados do Firestore para o Hive
  Future<void> _importarDoFirestore() async {
    try {
      // Confirmação via bottom sheet
      final confirm = await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (ctx) => Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: _cardColor,
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
                  color: _primaryColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.cloud_download,
                    size: 48, color: _primaryColor),
              ),
              const SizedBox(height: 16),
              const Text(
                'Importar dados',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                'Esta operação irá baixar todos os seus dados da nuvem e salvar no celular.\n\n'
                'Use quando:\n'
                '? Reinstalar o aplicativo\n'
                '? Trocar de dispositivo\n'
                '? Recuperar dados da nuvem',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Importar agora'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      );

      if (confirm != true) return;

      // Obter lojaId (mesmo que VendasScreen usa, para garantir mesma box)
      final lojaId = await LojaIdService.getWithTimeout(
              timeout: const Duration(seconds: 15)) ??
          await StoreResolverFacade.resolveForAdminApp();
      logD('📥 [SYNC-DEBUG] Importar dados (menu) → lojaId=$lojaId');
      if (lojaId == null || lojaId.isEmpty) {
        if (!mounted) return;
        _showSnackBar('Não foi possível determinar a loja atual',
            isError: true);
        return;
      }

      // Mostrar loading
      if (!mounted) return;
      _showLoadingDialog(
          'Importando dados...\nAguarde, isso pode levar alguns minutos.');

      // Enviar alterações locais pendentes ANTES de importar (evita sobrescrever fotos/exclusões)
      try {
        await SyncQueueService.processPending();
      } catch (_) {}

      // Enviar todas as vendas locais para o Firestore (celular de origem deve ter feito isso antes)
      try {
        final vendasBoxName = HiveBoxNames.vendas(lojaId);
        await VendasFirestoreService.syncTodasVendas(boxName: vendasBoxName);
      } catch (_) {}

      int totalImportados = 0;
      int totalErros = 0;
      int produtosImportados = 0;
      int clientesImportados = 0;
      int fornecedoresImportados = 0;
      int vendasImportadas = 0;

      // 1. Importar PRODUTOS
      try {
        logD('[IMPORT] Importando produtos...');
        final produtosBox =
            await Hive.openBox<Produto>(HiveBoxNames.produtos(lojaId));
        await ProdutosFirestoreService.syncTodosProdutos(
          boxName: produtosBox.name,
          lojaId: lojaId,
        );
        produtosImportados = await ProdutosFirestoreService.syncFirestoreToHive(
          lojaId: lojaId,
          produtosBox: produtosBox,
        );
        totalImportados += produtosImportados;
        logD('[IMPORT] $produtosImportados produtos importados');
      } catch (e) {
        totalErros++;
        logD('[IMPORT] Erro ao importar produtos (type=${e.runtimeType})');
      }

      // 2. Importar CLIENTES
      try {
        logD('[IMPORT] Importando clientes...');
        final clientesBox =
            await Hive.openBox<Cliente>(HiveBoxNames.clientes(lojaId));
        clientesImportados = await ClientesFirestoreService.syncFirestoreToHive(
          lojaId: lojaId,
          clientesBox: clientesBox,
        );
        totalImportados += clientesImportados;
        logD('[IMPORT] $clientesImportados clientes importados');
      } catch (e) {
        totalErros++;
        logD('[IMPORT] Erro ao importar clientes (type=${e.runtimeType})');
      }

      // 3. Importar FORNECEDORES
      try {
        logD('[IMPORT] Importando fornecedores...');
        final fornecedoresBox =
            await Hive.openBox<Fornecedor>(HiveBoxNames.fornecedores(lojaId));
        fornecedoresImportados =
            await FornecedoresFirestoreService.syncFirestoreToHive(
          lojaId: lojaId,
          fornecedoresBox: fornecedoresBox,
        );
        totalImportados += fornecedoresImportados;
        logD('[IMPORT] $fornecedoresImportados fornecedores importados');
      } catch (e) {
        totalErros++;
        logD('[IMPORT] Erro ao importar fornecedores (type=${e.runtimeType})');
      }

      // 4. Importar VENDAS (sem duplicar - apenas as que não estão no aparelho)
      ImportarVendasResultado? resultadoVendas;
      try {
        logD('[IMPORT] Importando vendas (sem duplicar)...');
        final vendasBox =
            await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId));
        resultadoVendas = await ImportarVendasFirestoreService.importar(
          lojaId: lojaId,
          vendasBox: vendasBox,
        );
        vendasImportadas = resultadoVendas.importadas;
        totalImportados += vendasImportadas;
        logD(
            '[IMPORT] ${resultadoVendas.importadas} vendas novas importadas (${resultadoVendas.jaExistentes} já existiam, total Firestore=${resultadoVendas.totalNoFirestore})');
        if (resultadoVendas.erroMensagem != null) {
          logW(
              '[IMPORT] Vendas: fallback usado (erro anterior: ${resultadoVendas.erroMensagem})');
        }
      } catch (e) {
        totalErros++;
        logD('[IMPORT] Erro ao importar vendas (type=${e.runtimeType}): $e');
      }

      // 5. Reconciliação: vincular vendas ao histórico dos clientes
      try {
        final clientesBox =
            await Hive.openBox<Cliente>(HiveBoxNames.clientes(lojaId));
        final vendasBox =
            await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId));
        final n = await ReconciliacaoVendasClientesService.reconciliar(
          clientesBox: clientesBox,
          vendasBox: vendasBox,
          lojaId: lojaId,
        );
        if (n > 0) logD('[IMPORT] $n vendas vinculadas ao histórico');
      } catch (e) {
        logD('[IMPORT] Aviso ao reconciliar (type=${e.runtimeType})');
      }

      // Fechar loading
      if (!mounted) return;
      Navigator.pop(context);

      // Mostrar resultado (verdade do sucesso: breakdown por tipo)
      if (!mounted) return;
      final breakdown = 'Produtos: $produtosImportados | '
          'Clientes: $clientesImportados | '
          'Fornecedores: $fornecedoresImportados | '
          'Vendas: $vendasImportadas';
      String msgVendas = '';
      if (vendasImportadas == 0) {
        final r = resultadoVendas;
        if (r != null && r.totalNoFirestore > 0 && r.jaExistentes > 0) {
          msgVendas =
              '\n\nVendas: ${r.totalNoFirestore} na nuvem (${r.jaExistentes} já estavam no aparelho). Abra a tela de Vendas para visualizá-las.';
        } else if (r != null && r.totalNoFirestore > 0) {
          msgVendas =
              '\n\nVendas na nuvem: ${r.totalNoFirestore}. Abra a tela de Vendas para conferir.';
        } else {
          msgVendas =
              '\n\nNenhuma venda nova para importar (todas já estavam no aparelho ou a sincronização ainda não foi feita no outro dispositivo).';
        }
        if (resultadoVendas?.erroMensagem != null) {
          msgVendas +=
              '\n\nAviso: foi usado modo alternativo de leitura (índice Firestore pode estar sendo criado).';
        }
      }
      _showSuccessSheet(
        totalErros == 0
            ? 'Importação Concluída!'
            : 'Importação Concluída com Avisos',
        totalErros == 0
            ? 'Total importado: $totalImportados registros\n'
                '$breakdown\n\n'
                'Seus dados foram sincronizados com sucesso!$msgVendas'
            : 'Total importado: $totalImportados registros\n'
                '$breakdown\n'
                'Erros: $totalErros\n\n'
                'Verifique os logs para mais detalhes.',
      );

      // Recarregar a tela para mostrar os dados importados
      setState(() {});
    } catch (e) {
      logD('Erro na importação (type=${e.runtimeType})');

      // Fechar loading se estiver aberto
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      // Mostrar erro
      if (!mounted) return;
      _showSnackBar('Erro na importação: $e', isError: true);
    }
  }

  void _showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: _cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              const CircularProgressIndicator(color: _primaryColor),
              const SizedBox(width: 20),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSuccessSheet(String title, String message) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: _cardColor,
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
                color: _successColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle,
                  size: 48, color: _successColor),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _successColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('OK'),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? _errorColor : _successColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // Preços fixos alinhados a lib/screens/planos_screen.dart (Pro vem do Remote Config).
  static const double _kLandingPrecoBasico = 19.99;
  static const double _kLandingPrecoIntermediario = 29.99;

  String _fmtBRL(double v) =>
      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$', decimalDigits: 2)
          .format(v);

  // =========================
  // WEB landing (mastepalm.com.br) com seção de planos
  // =========================
  Widget _buildWebLanding() {
    final proMensal = RemoteConfigService.planoMensalPreco;
    final proAnual = RemoteConfigService.planoAnualPreco;
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo + saudação
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [_primaryColor, _primaryColor.withOpacity(0.8)],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _primaryColor.withOpacity(0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.storefront,
                        size: 64, color: Colors.white),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Bem-vindo à MasterPalm!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: _surfaceColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Gerencie sua loja com facilidade. Catálogo online, pedidos, estoque e vendas em um só lugar.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 16, color: Colors.grey[600], height: 1.4),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pushNamed(context, '/loja'),
                      icon: const Icon(Icons.shopping_bag_outlined, size: 22),
                      label: const Text('Ver Catálogo'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pushNamed(context, '/login'),
                      icon: const Icon(Icons.login, size: 20),
                      label: const Text('Login / Cadastro'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _primaryColor,
                        side: const BorderSide(color: _primaryColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 48),
                  const Divider(height: 1),
                  const SizedBox(height: 24),
                  const Text(
                    'Planos',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: _surfaceColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Escolha o plano ideal para a sua loja. Todos incluem catálogo web, pedidos e suporte.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 24),
                  _buildWebLandingPlanCard(
                    title: 'Teste grátis (30 dias — contas novas)',
                    price: 'R\$ 0',
                    period: '30 dias',
                    color: _successColor,
                    icon: Icons.card_giftcard,
                    description:
                        'Use o app no nível Pro durante o trial. Contas antigas com trial de 90 dias continuam válidas até o fim do período.',
                    bullets: const [
                      'Todos os módulos como no Pro durante o trial',
                      'Ao expirar: migra para Free limitado, sem apagar seus dados',
                      'Checkout seguro no servidor (Mercado Pago) para planos pagos',
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildWebLandingPlanCard(
                    title: 'Free limitado',
                    price: 'R\$ 0',
                    period: 'sempre',
                    color: _warningColor,
                    icon: Icons.savings_outlined,
                    description:
                        'Após o trial, limites numéricos para novas inclusões; histórico e cadastros existentes permanecem.',
                    bullets: const [
                      'Até 30 produtos, 20 clientes, 10 vendas/mês',
                      '1 foto por produto e 1 banner',
                      'Upgrade para Básico, Intermediário ou Pro libera mais',
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildWebLandingPlanCard(
                    title: 'Básico e Intermediário',
                    price:
                        '${_fmtBRL(_kLandingPrecoBasico)} (Básico) · ${_fmtBRL(_kLandingPrecoIntermediario)} (Intermediário)',
                    period: 'mês',
                    color: _primaryColor,
                    icon: Icons.trending_up,
                    description:
                        'Níveis intermediários entre o Free e o Pro: mais produtos, fotos, relatórios e módulos operacionais.',
                    bullets: const [
                      'Básico: até 300 produtos, 500 clientes, relatório básico',
                      'Intermediário: compras, precificação, combos e relatórios avançados',
                      'Valores fixos; detalhes na tela Planos após login',
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildWebLandingPlanCard(
                    title: 'Pro mensal',
                    price: _fmtBRL(proMensal),
                    period: 'mês',
                    color: _primaryColor,
                    icon: Icons.workspace_premium,
                    description:
                        'Gestão completa: equipe, IA, campanhas, integrações e limites altos. Preço pode ser ajustado no Firebase Remote Config.',
                    bullets: const [
                      'Tudo do Intermediário e recursos premium',
                      'Vendedores, metas, fretes/cupons, Meta e marketplaces',
                      'Cancele quando quiser (mensal)',
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildWebLandingPlanCard(
                    title: 'Pro anual',
                    price: _fmtBRL(proAnual),
                    period: 'ano',
                    color: const Color(0xFF0EA5E9),
                    icon: Icons.verified_user,
                    description:
                        'Mesmo acesso do Pro mensal com economia no ano. Confirmação de pagamento pelo servidor.',
                    bullets: const [
                      'Renovação anual · previsibilidade de custo',
                      'Ideal para lojas em crescimento',
                      'Melhor custo-benefício vs 12x mensal',
                    ],
                    badge: 'Recomendado',
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'Quer começar? Faça login ou cadastre-se e ative o teste grátis (30 dias para contas novas).',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: _surfaceColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pushNamed(context, '/login'),
                      icon: const Icon(Icons.rocket_launch, size: 20),
                      label: const Text('Começar agora'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Card de plano na landing web (mastepalm.com.br)
  Widget _buildWebLandingPlanCard({
    required String title,
    required String price,
    required String period,
    required Color color,
    required IconData icon,
    required String description,
    required List<String> bullets,
    String? badge,
  }) {
    return WebLandingPlanCard(
      title: title,
      price: price,
      period: period,
      color: color,
      icon: icon,
      description: description,
      bullets: bullets,
      badge: badge,
      cardColor: _cardColor,
      surfaceColor: _surfaceColor,
    );
  }

  // ---------- helpers ----------
  Widget _buildMenuTile(
    String label,
    IconData icon,
    String route, {
    Widget? pushWidget,
    PlanGateFeature? pushPlanFeature,
    Color? color,
    Color? iconBgColor,
    bool sidebarMode = false,
    VoidCallback? customOnTap,
  }) {
    final theme = Theme.of(context);
    final itemColor = color ?? theme.colorScheme.onSurface;
    final bgColor = iconBgColor ?? _primaryColor.withOpacity(0.1);
    final trailingColor = theme.colorScheme.onSurface.withOpacity(0.5);

    return ListTile(
      dense: sidebarMode,
      visualDensity: sidebarMode ? const VisualDensity(vertical: -1) : null,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color ?? _primaryColor, size: 20),
      ),
      title: Text(
        label,
        style: TextStyle(
          color: itemColor,
          fontWeight: FontWeight.w500,
          fontSize: sidebarMode ? 13 : null,
        ),
      ),
      trailing: Icon(Icons.chevron_right, color: trailingColor, size: 20),
      onTap: () {
        if (!sidebarMode) Navigator.pop(context);
        if (customOnTap != null) {
          customOnTap();
          return;
        }
        // Usar navigatorKey para garantir que a navegação use o root navigator (corrige telas que não abrem no app web)
        final nav = navigatorKey.currentState;
        if (nav == null) return;
        if (pushWidget != null) {
          final w = pushWidget;
          final Widget page = pushPlanFeature != null
              ? PlanGatedScreen(
                  feature: pushPlanFeature,
                  child: w,
                )
              : w;
          nav.push(MaterialPageRoute(builder: (_) => page));
        } else if (label == 'Licença (Admin)') {
          nav.push(MaterialPageRoute(builder: (_) => const AdminLoginScreen()));
        } else {
          nav.pushNamed(route);
        }
      },
    );
  }

  Widget _buildLockedPlanMenuTile(
    String label,
    IconData icon,
    PlanGateFeature feature, {
    bool sidebarMode = false,
    Color? color,
    Color? iconBgColor,
  }) {
    final muted = Colors.grey[600]!;
    final bg = iconBgColor ?? _primaryColor.withOpacity(0.08);
    return ListTile(
      dense: sidebarMode,
      visualDensity: sidebarMode ? const VisualDensity(vertical: -1) : null,
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: muted, size: 20),
          ),
          Positioned(
            right: -2,
            top: -2,
            child: Icon(Icons.lock_rounded, size: 16, color: _warningColor),
          ),
        ],
      ),
      title: Text(
        label,
        style: TextStyle(
          color: muted,
          fontWeight: FontWeight.w500,
          fontSize: sidebarMode ? 13 : null,
        ),
      ),
      subtitle: Text(
        PlanMatrix.upgradeHint(feature),
        style:
            TextStyle(fontSize: sidebarMode ? 10 : 11, color: Colors.grey[500]),
        maxLines: 3,
      ),
      trailing: TextButton(
        onPressed: () {
          if (!sidebarMode) Navigator.pop(context);
          navigatorKey.currentState?.pushNamed('/planos');
        },
        child: const Text('Planos'),
      ),
    );
  }

  Widget _menuTileWithPlanGate(
    String label,
    IconData icon,
    String route, {
    Widget? pushWidget,
    Color? color,
    Color? iconBgColor,
    bool sidebarMode = false,
    required bool applyPlanGate,
    required PlanAccessTier menuPlanTier,
    PlanGateFeature? planFeature,
  }) {
    if (applyPlanGate &&
        planFeature != null &&
        !PlanMatrix.allows(menuPlanTier, planFeature)) {
      return _buildLockedPlanMenuTile(
        label,
        icon,
        planFeature,
        sidebarMode: sidebarMode,
        color: color,
        iconBgColor: iconBgColor,
      );
    }
    return _buildMenuTile(
      label,
      icon,
      route,
      pushWidget: pushWidget,
      pushPlanFeature: applyPlanGate ? planFeature : null,
      color: color,
      iconBgColor: iconBgColor,
      sidebarMode: sidebarMode,
    );
  }

  // ---------- menu lateral ----------
  Future<List<Widget>> _buildMenuLateral({bool sidebarMode = false}) async {
    final permissoes = await PermissaoService.todas();

    // ✅ combinadas: programador/admin vê tudo; vendedor depende do hive
    final combinadas = <String, bool>{
      for (final k in permissoes.keys)
        k: (_tipo == 'programador' || _tipo == 'admin')
            ? true
            : (permissoes[k] ?? false),
    };

    PlanAccessTier menuPlanTier = PlanAccessTier.lifetime;
    final bool applyPlanGate = _tipo == 'admin';
    if (applyPlanGate) {
      menuPlanTier = await _resolveMenuPlanTier();
    }

    // Seções expansíveis: (título, cor?, filhos)
    final sections = <({String title, Color? color, List<Widget> children})>[];
    String? currentSection;
    Color? currentSectionColor;
    List<Widget> currentChildren = [];

    void closeSection() {
      if (currentSection != null && currentChildren.isNotEmpty) {
        sections.add((
          title: currentSection!,
          color: currentSectionColor,
          children: List.from(currentChildren)
        ));
        currentChildren = [];
      }
    }

    void startSection(String title, {Color? color}) {
      closeSection();
      currentSection = title;
      currentSectionColor = color;
    }

    // Seção: Loja
    startSection('Loja');

    if ((combinadas['catalogo_publico'] ?? combinadas['catalogo']) == true &&
        isValidForPublicLink(_lojaSlugPublico)) {
      currentChildren.add(
        _buildMenuTile(
          'Visualizar Loja',
          Icons.storefront,
          '/loja/$_lojaSlugPublico',
          iconBgColor: _successColor.withOpacity(0.1),
          color: _successColor,
          sidebarMode: sidebarMode,
        ),
      );
    }

    if (_tipo == 'admin' ||
        _tipo == 'programador' ||
        combinadas['minha_loja'] == true) {
      currentChildren.add(
        _buildMenuTile(
          'Configurações do Catálogo',
          Icons.brush,
          '/loja_config',
          pushWidget: const LojaConfigScreen(),
          sidebarMode: sidebarMode,
        ),
      );
      currentChildren.add(
        _buildMenuTile(
          'Moderar avaliações',
          Icons.rate_review_outlined,
          '/catalog_avaliacoes_moderacao',
          iconBgColor: const Color(0xFF8B5CF6).withOpacity(0.1),
          color: const Color(0xFF8B5CF6),
          sidebarMode: sidebarMode,
        ),
      );
    }

    // ✅ Abrir catálogo online (link direto da loja ativa; sem placeholder)
    final catalogUrl =
        _catalogOnlineUrl ?? buildPublicCatalogUrl(_lojaSlugPublico);
    if (catalogUrl != null) {
      currentChildren.add(
        ListTile(
          dense: sidebarMode,
          visualDensity: sidebarMode ? const VisualDensity(vertical: -1) : null,
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF3B82F6).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child:
                const Icon(Icons.language, color: Color(0xFF3B82F6), size: 20),
          ),
          title: Text(
            'Abrir catálogo online',
            style: TextStyle(
              color: const Color(0xFF3B82F6),
              fontWeight: FontWeight.w500,
              fontSize: sidebarMode ? 13 : null,
            ),
          ),
          subtitle: sidebarMode
              ? null
              : Text(
                  catalogUrl,
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.copy, size: 18, color: Colors.grey),
                tooltip: 'Copiar link do catálogo',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: catalogUrl));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Link do catálogo copiado!'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
              const Icon(Icons.open_in_new, size: 18, color: Colors.grey),
            ],
          ),
          onTap: () async {
            if (!sidebarMode) Navigator.pop(context);
            final uri = Uri.parse(catalogUrl);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
        ),
      );
    }

    // Seção: Gestão
    startSection('Gestão');

    if (combinadas['estoque'] == true) {
      currentChildren.add(_buildMenuTile(
          'Estoque', Icons.inventory_2, '/estoque',
          sidebarMode: sidebarMode));
    }
    if (combinadas['vendas'] == true) {
      currentChildren.add(_buildMenuTile(
          'Vendas', Icons.point_of_sale, '/vendas',
          iconBgColor: _successColor.withOpacity(0.1),
          color: _successColor,
          sidebarMode: sidebarMode));
    }

    // Sugestões / Insights – usa dados da loja ativa (sem placeholder)
    if (_lojaIdInterno.isNotEmpty) {
      currentChildren.add(
        _menuTileWithPlanGate(
          'Sugestões (Insights)',
          Icons.lightbulb_outline,
          '/dashboard_insights',
          pushWidget: DashboardInsightsScreen(
            lojaId: _lojaIdInterno,
            isVendedor: _tipo == 'vendedor',
            vendedorNome: _tipo == 'vendedor' ? _getFirstName(_usuario) : null,
          ),
          iconBgColor: _primaryColor.withOpacity(0.1),
          color: _primaryColor,
          sidebarMode: sidebarMode,
          applyPlanGate: applyPlanGate,
          menuPlanTier: menuPlanTier,
          planFeature: PlanGateFeature.insights,
        ),
      );
    }

    // Relatórios Financeiros & Metas — gate para admin (free limitado vê upgrade)
    currentChildren.add(
      _menuTileWithPlanGate(
        'Financeiro & Metas',
        Icons.trending_up,
        '/relatorios_financeiros',
        pushWidget: const RelatoriosFinanceirosScreen(),
        iconBgColor: const Color(0xFFEC4899).withOpacity(0.1),
        color: const Color(0xFFEC4899),
        sidebarMode: sidebarMode,
        applyPlanGate: applyPlanGate,
        menuPlanTier: menuPlanTier,
        planFeature: PlanGateFeature.relatoriosFinanceirosHub,
      ),
    );

    // ✅ Metas & Comissões - vendedores veem suas próprias, admin vê todas
    currentChildren.add(
      _menuTileWithPlanGate(
        'Metas & Comissões',
        Icons.monetization_on,
        '/metas_comissoes',
        pushWidget: const MetasComissoesScreen(),
        iconBgColor: const Color(0xFF10B981).withOpacity(0.1),
        color: const Color(0xFF10B981),
        sidebarMode: sidebarMode,
        applyPlanGate: applyPlanGate,
        menuPlanTier: menuPlanTier,
        planFeature: PlanGateFeature.metasComissoes,
      ),
    );

    currentChildren.add(
      _menuTileWithPlanGate(
        'Mais vendidos',
        Icons.trending_up,
        '/relatorio_mais_vendidos',
        iconBgColor: const Color(0xFFEC4899).withOpacity(0.1),
        color: const Color(0xFFEC4899),
        sidebarMode: sidebarMode,
        applyPlanGate: applyPlanGate,
        menuPlanTier: menuPlanTier,
        planFeature: PlanGateFeature.maisVendidos,
      ),
    );

    // Seção de Pedidos (unificada: pré-pedidos + pendentes)
    startSection('Pedidos');

    if (_lojaIdInterno.isNotEmpty) {
      currentChildren.add(
        _menuTileWithPlanGate(
          'Pedidos',
          Icons.receipt_long,
          '/pedidos',
          pushWidget: PrePedidosScreen(lojaId: _lojaIdInterno),
          iconBgColor: _warningColor.withOpacity(0.1),
          color: _warningColor,
          sidebarMode: sidebarMode,
          applyPlanGate: applyPlanGate,
          menuPlanTier: menuPlanTier,
          planFeature: PlanGateFeature.pedidosPrePedidos,
        ),
      );
    }

    // Seção: Cadastros
    startSection('Cadastros');

    if (combinadas['clientes'] == true) {
      currentChildren.add(_buildMenuTile('Clientes', Icons.people, '/clientes',
          sidebarMode: sidebarMode));
    }
    if (combinadas['fornecedores'] == true) {
      currentChildren.add(_menuTileWithPlanGate(
          'Fornecedores', Icons.local_shipping, '/fornecedores',
          sidebarMode: sidebarMode,
          applyPlanGate: applyPlanGate,
          menuPlanTier: menuPlanTier,
          planFeature: PlanGateFeature.fornecedores));
    }
    if (combinadas['precificacao'] == true) {
      currentChildren.add(_menuTileWithPlanGate(
          'Precificação', Icons.calculate, '/precificacao',
          sidebarMode: sidebarMode,
          applyPlanGate: applyPlanGate,
          menuPlanTier: menuPlanTier,
          planFeature: PlanGateFeature.precificacao));
    }

    // ✅ Notas Fiscais (admin/programador)
    if (_tipo == 'admin' || _tipo == 'programador') {
      startSection('Fiscal');
      currentChildren.add(
        _buildMenuTile(
          'Notas Fiscais',
          Icons.receipt,
          '/notas_fiscais',
          pushWidget: const NotasFiscaisScreen(),
          sidebarMode: sidebarMode,
        ),
      );
      currentChildren.add(
        _menuTileWithPlanGate(
          'Contas a receber',
          Icons.receipt_long,
          '/contas_receber',
          pushWidget: const ContasReceberScreen(),
          sidebarMode: sidebarMode,
          applyPlanGate: applyPlanGate,
          menuPlanTier: menuPlanTier,
          planFeature: PlanGateFeature.contasReceber,
        ),
      );
      currentChildren.add(
        _menuTileWithPlanGate(
          'Contas a pagar',
          Icons.payments_outlined,
          '/contas_pagar',
          pushWidget: const ContasPagarScreen(),
          sidebarMode: sidebarMode,
          applyPlanGate: applyPlanGate,
          menuPlanTier: menuPlanTier,
          planFeature: PlanGateFeature.financeiroLancamentos,
        ),
      );
    }

    if (_tipo == 'admin' || _tipo == 'programador') {
      startSection('Equipe');

      // ✅ VENDEDORES (tela unificada: lista, cadastra e gerencia permissões)
      currentChildren.add(
        _menuTileWithPlanGate(
          'Vendedores',
          Icons.people,
          '/vendedores',
          iconBgColor: const Color(0xFF6366F1).withOpacity(0.1),
          color: const Color(0xFF6366F1),
          sidebarMode: sidebarMode,
          applyPlanGate: applyPlanGate,
          menuPlanTier: menuPlanTier,
          planFeature: PlanGateFeature.vendedores,
        ),
      );

      startSection('IA');

      currentChildren.add(
        _menuTileWithPlanGate(
          'Motor de Crescimento IA',
          Icons.rocket_launch_outlined,
          '/motor_crescimento',
          pushWidget: MotorCrescimentoScreen(lojaId: _lojaIdInterno),
          iconBgColor: _primaryColor.withOpacity(0.1),
          color: _primaryColor,
          sidebarMode: sidebarMode,
          applyPlanGate: applyPlanGate,
          menuPlanTier: menuPlanTier,
          planFeature: PlanGateFeature.motorCrescimento,
        ),
      );
      currentChildren.add(
        _menuTileWithPlanGate(
          'Campanhas sugeridas',
          Icons.auto_awesome_motion,
          '/campanhas_sugeridas',
          pushWidget: CampanhasSugeridasScreen(lojaId: _lojaIdInterno),
          iconBgColor: _primaryColor.withOpacity(0.1),
          color: _primaryColor,
          sidebarMode: sidebarMode,
          applyPlanGate: applyPlanGate,
          menuPlanTier: menuPlanTier,
          planFeature: PlanGateFeature.campanhasSugeridas,
        ),
      );
      currentChildren.add(
        _menuTileWithPlanGate(
          'Marketing (Dicas)',
          Icons.auto_awesome,
          '/dicas_ia',
          pushWidget: const DicasIaScreen(),
          iconBgColor: _primaryColor.withOpacity(0.1),
          color: _primaryColor,
          sidebarMode: sidebarMode,
          applyPlanGate: applyPlanGate,
          menuPlanTier: menuPlanTier,
          planFeature: PlanGateFeature.dicasIA,
        ),
      );
      currentChildren.add(
        _menuTileWithPlanGate(
          'Textos WhatsApp',
          Icons.chat,
          '/textos_whatsapp_ia',
          pushWidget: const TextosWhatsAppIaScreen(),
          iconBgColor: const Color(0xFF25D366).withOpacity(0.1),
          color: const Color(0xFF25D366),
          sidebarMode: sidebarMode,
          applyPlanGate: applyPlanGate,
          menuPlanTier: menuPlanTier,
          planFeature: PlanGateFeature.textosWhatsappIA,
        ),
      );
      currentChildren.add(
        _menuTileWithPlanGate(
          'Criar postagem',
          Icons.campaign_outlined,
          '/gerar_postagem',
          pushWidget: const GerarPostagemScreen(),
          iconBgColor: const Color(0xFF8B5CF6).withOpacity(0.1),
          color: const Color(0xFF8B5CF6),
          sidebarMode: sidebarMode,
          applyPlanGate: applyPlanGate,
          menuPlanTier: menuPlanTier,
          planFeature: PlanGateFeature.gerarPostagem,
        ),
      );
      currentChildren.add(
        _menuTileWithPlanGate(
          'Compartilhar catálogo no WhatsApp',
          Icons.share,
          '/compartilhar_whatsapp',
          pushWidget: const CompartilharWhatsAppScreen(),
          iconBgColor: const Color(0xFF25D366).withOpacity(0.1),
          color: const Color(0xFF25D366),
          sidebarMode: sidebarMode,
          applyPlanGate: applyPlanGate,
          menuPlanTier: menuPlanTier,
          planFeature: PlanGateFeature.compartilharWhatsapp,
        ),
      );
      currentChildren.add(
        _menuTileWithPlanGate(
          'Pergunte sobre vendas',
          Icons.analytics,
          '/analise_vendas_ia',
          pushWidget: const AnaliseVendasIaScreen(),
          iconBgColor: _successColor.withOpacity(0.1),
          color: _successColor,
          sidebarMode: sidebarMode,
          applyPlanGate: applyPlanGate,
          menuPlanTier: menuPlanTier,
          planFeature: PlanGateFeature.analiseVendasIA,
        ),
      );

      startSection('Marketing');

      currentChildren.add(
        _menuTileWithPlanGate(
          'Painel Marketing',
          Icons.campaign_outlined,
          '/marketing_hub',
          pushWidget: MarketingHubScreen(
            lojaId: _lojaIdInterno.isNotEmpty ? _lojaIdInterno : null,
          ),
          iconBgColor: const Color(0xFFEC4899).withOpacity(0.1),
          color: const Color(0xFFEC4899),
          sidebarMode: sidebarMode,
          applyPlanGate: applyPlanGate,
          menuPlanTier: menuPlanTier,
          planFeature: PlanGateFeature.campanhasSorteios,
        ),
      );

      currentChildren.add(
        _menuTileWithPlanGate(
          'Dashboard Campanhas',
          Icons.insights,
          '/campanhas_dashboard',
          pushWidget: CampanhasDashboardScreen(
            lojaId: _lojaIdInterno.isNotEmpty ? _lojaIdInterno : null,
          ),
          iconBgColor: const Color(0xFFEC4899).withOpacity(0.1),
          color: const Color(0xFFEC4899),
          sidebarMode: sidebarMode,
          applyPlanGate: applyPlanGate,
          menuPlanTier: menuPlanTier,
          planFeature: PlanGateFeature.campanhasSorteios,
        ),
      );

      currentChildren.add(
        _menuTileWithPlanGate(
          'Dashboard Roleta',
          Icons.casino_outlined,
          '/roleta_dashboard',
          pushWidget: RoletaDashboardScreen(
            lojaId: _lojaIdInterno.isNotEmpty ? _lojaIdInterno : null,
          ),
          iconBgColor: const Color(0xFF8B5CF6).withOpacity(0.1),
          color: const Color(0xFF8B5CF6),
          sidebarMode: sidebarMode,
          applyPlanGate: applyPlanGate,
          menuPlanTier: menuPlanTier,
          planFeature: PlanGateFeature.campanhasSorteios,
        ),
      );

      currentChildren.add(
        _menuTileWithPlanGate(
          'Estatísticas Marketing',
          Icons.bar_chart_rounded,
          '/marketing_estatisticas',
          pushWidget: MarketingEstatisticasScreen(
            lojaId: _lojaIdInterno.isNotEmpty ? _lojaIdInterno : null,
          ),
          iconBgColor: _primaryColor.withOpacity(0.1),
          color: _primaryColor,
          sidebarMode: sidebarMode,
          applyPlanGate: applyPlanGate,
          menuPlanTier: menuPlanTier,
          planFeature: PlanGateFeature.campanhasSorteios,
        ),
      );

      currentChildren.add(
        _menuTileWithPlanGate(
          'Campanhas & Sorteios',
          Icons.casino,
          '/campanhas_sorteio',
          pushWidget: const CampanhasSorteioScreen(),
          iconBgColor: const Color(0xFFEC4899).withOpacity(0.1),
          color: const Color(0xFFEC4899),
          sidebarMode: sidebarMode,
          applyPlanGate: applyPlanGate,
          menuPlanTier: menuPlanTier,
          planFeature: PlanGateFeature.campanhasSorteios,
        ),
      );

      currentChildren.add(
        _menuTileWithPlanGate(
          'Globo de Sorteio',
          Icons.emoji_events,
          '/globo_sorteio',
          pushWidget: const GloboSorteioScreenWrapper(),
          iconBgColor: const Color(0xFFEC4899).withOpacity(0.1),
          color: const Color(0xFFEC4899),
          sidebarMode: sidebarMode,
          applyPlanGate: applyPlanGate,
          menuPlanTier: menuPlanTier,
          planFeature: PlanGateFeature.globoSorteio,
        ),
      );

      startSection('Configurações');

      currentChildren.add(
        _menuTileWithPlanGate(
          'Fretes & Cupons',
          Icons.local_offer,
          '/fretes_cupons',
          pushWidget: const FretesCuponsScreen(),
          sidebarMode: sidebarMode,
          applyPlanGate: applyPlanGate,
          menuPlanTier: menuPlanTier,
          planFeature: PlanGateFeature.fretesCupons,
        ),
      );

      currentChildren.add(
        _menuTileWithPlanGate(
          '🛒 Carrinhos Abandonados',
          Icons.shopping_cart_outlined,
          '/carrinhos_abandonados',
          pushWidget: CarrinhosAbandonadosScreen(
            lojaId: _lojaIdInterno.isNotEmpty ? _lojaIdInterno : null,
          ),
          iconBgColor: const Color(0xFFF59E0B).withOpacity(0.12),
          color: const Color(0xFFF59E0B),
          sidebarMode: sidebarMode,
          applyPlanGate: applyPlanGate,
          menuPlanTier: menuPlanTier,
          planFeature: PlanGateFeature.carrinhosAbandonados,
        ),
      );

      // Tempo de abandono — mesma rota do registry HomeModuleRegistry
      currentChildren.add(
        _menuTileWithPlanGate(
          'Config. carrinhos abandonados',
          Icons.timer_outlined,
          '/config_carrinhos_abandonados',
          iconBgColor: const Color(0xFFF59E0B).withOpacity(0.12),
          color: const Color(0xFFF59E0B),
          sidebarMode: sidebarMode,
          applyPlanGate: applyPlanGate,
          menuPlanTier: menuPlanTier,
          planFeature: PlanGateFeature.carrinhosAbandonados,
        ),
      );

      // ✅ CANAIS META (WhatsApp, Instagram, Messenger)
      currentChildren.add(
        _menuTileWithPlanGate(
          'Canais Meta',
          Icons.chat_bubble,
          '/configuracoes/canais_meta',
          pushWidget: const CanaisMetaScreen(),
          iconBgColor: const Color(0xFF25D366).withOpacity(0.1),
          color: const Color(0xFF25D366),
          sidebarMode: sidebarMode,
          applyPlanGate: applyPlanGate,
          menuPlanTier: menuPlanTier,
          planFeature: PlanGateFeature.canaisMeta,
        ),
      );

      currentChildren.add(_menuTileWithPlanGate(
          'Configurar Pagamentos', Icons.payments, '/config/pagamentos',
          sidebarMode: sidebarMode,
          applyPlanGate: applyPlanGate,
          menuPlanTier: menuPlanTier,
          planFeature: PlanGateFeature.configurarPagamentosOnline));
      currentChildren.add(_menuTileWithPlanGate(
          'Sincronizar dados', Icons.cloud_sync, '/admin_sync',
          sidebarMode: sidebarMode,
          applyPlanGate: applyPlanGate,
          menuPlanTier: menuPlanTier,
          planFeature: PlanGateFeature.adminSync));
      currentChildren.add(_menuTileWithPlanGate(
          'Backup da Loja', Icons.backup, '/backup',
          sidebarMode: sidebarMode,
          applyPlanGate: applyPlanGate,
          menuPlanTier: menuPlanTier,
          planFeature: PlanGateFeature.backupLoja));

      // ✅ CONSOLIDAR LOJAS - Apenas para Naty Pratas
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      if (currentUid == 'tcnbZdmFXsMPJ2bU29dDt3z5ZHr2') {
        currentChildren.add(
          _buildMenuTile(
            'Consolidar Lojas',
            Icons.merge_type,
            '/consolidate_stores',
            pushWidget: const ConsolidateStoresScreen(),
            sidebarMode: sidebarMode,
          ),
        );
      }

      // ✅ MARKETPLACES / ERP
      currentChildren.add(
        _menuTileWithPlanGate(
          'Marketplaces / ERP',
          Icons.shopping_bag,
          '/marketplaces',
          pushWidget: const MarketplacesScreen(),
          sidebarMode: sidebarMode,
          applyPlanGate: applyPlanGate,
          menuPlanTier: menuPlanTier,
          planFeature: PlanGateFeature.marketplaces,
        ),
      );

      currentChildren.add(_buildMenuTile(
          'Planos', Icons.workspace_premium, '/planos',
          iconBgColor: _warningColor.withOpacity(0.1),
          color: _warningColor,
          sidebarMode: sidebarMode));
    }

    // Telas de desenvolvedor: apenas para programador, não para admin
    if (_tipo == 'programador') {
      startSection('Desenvolvedor');
      currentChildren.add(_buildMenuTile(
          'Diagnóstico do App', Icons.bug_report, '/diagnostico',
          iconBgColor: Colors.orange.withOpacity(0.1),
          color: Colors.orange,
          sidebarMode: sidebarMode));
      currentChildren.add(_buildMenuTile(
          'Alterar PIN', Icons.vpn_key, '/config_pin',
          sidebarMode: sidebarMode));
      currentChildren.add(_buildMenuTile(
          'Teste Checkout (MP)', Icons.payment, '/test_checkout',
          sidebarMode: sidebarMode));
      currentChildren.add(_buildMenuTile(
          'Health Check (App Check)', Icons.health_and_safety, '/health',
          sidebarMode: sidebarMode));
    }

    // Master Config - apenas root (lista canônica RoleUtils; admin de loja não)
    if (RoleUtils.isRootEmail(_usuario)) {
      startSection('Master', color: _errorColor);
      if (RoleUtils.isMasterPlanAdminEmail(_usuario)) {
        currentChildren.add(
          _buildMenuTile(
            'Assinaturas e Acessos',
            Icons.card_membership,
            '/mestre/assinaturas',
            color: _errorColor,
            iconBgColor: _errorColor.withOpacity(0.1),
            sidebarMode: sidebarMode,
          ),
        );
      }
      currentChildren.add(
        _buildMenuTile(
          'Configurações Master',
          Icons.admin_panel_settings,
          '/master_login',
          color: _errorColor,
          iconBgColor: _errorColor.withOpacity(0.1),
          sidebarMode: sidebarMode,
        ),
      );
      currentChildren.add(
        _buildMenuTile(
          'Gerenciar Usuários & Planos',
          Icons.manage_accounts,
          '/admin_usuarios',
          color: _errorColor,
          iconBgColor: _errorColor.withOpacity(0.1),
          sidebarMode: sidebarMode,
        ),
      );
      currentChildren.add(
        _buildMenuTile(
          'Suporte pagamento catálogo MP',
          Icons.receipt_long,
          '/catalog_payment_support',
          color: _errorColor,
          iconBgColor: _errorColor.withOpacity(0.1),
          sidebarMode: sidebarMode,
          customOnTap: () {
            final nav = navigatorKey.currentState;
            if (nav == null) return;
            openCatalogPaymentSupport(nav.context);
          },
        ),
      );
      currentChildren.add(
        _buildMenuTile(
          'Configurar Site',
          Icons.language,
          '/site_config',
          color: _errorColor,
          iconBgColor: _errorColor.withOpacity(0.1),
          sidebarMode: sidebarMode,
        ),
      );
    }

    startSection('Dados');

    // Botão de migração de dados
    currentChildren.add(
      ListTile(
        dense: sidebarMode,
        visualDensity: sidebarMode ? const VisualDensity(vertical: -1) : null,
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _warningColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.cloud_sync, color: _warningColor, size: 20),
        ),
        title: Text(
          'Migrar Dados',
          style: TextStyle(
              color: _warningColor,
              fontWeight: FontWeight.w500,
              fontSize: sidebarMode ? 13 : null),
        ),
        subtitle: sidebarMode
            ? null
            : Text(
                'Use apenas uma vez',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
        trailing: Icon(Icons.chevron_right, color: Colors.grey[400], size: 20),
        onTap: () async {
          if (!sidebarMode) Navigator.pop(context);
          await _migrarDados();
        },
      ),
    );

    // Botão de importação do Firestore
    currentChildren.add(
      ListTile(
        dense: sidebarMode,
        visualDensity: sidebarMode ? const VisualDensity(vertical: -1) : null,
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child:
              const Icon(Icons.cloud_download, color: _primaryColor, size: 20),
        ),
        title: Text(
          'Importar dados',
          style: TextStyle(
              color: _primaryColor,
              fontWeight: FontWeight.w500,
              fontSize: sidebarMode ? 13 : null),
        ),
        trailing: Icon(Icons.chevron_right, color: Colors.grey[400], size: 20),
        onTap: () async {
          if (!sidebarMode) Navigator.pop(context);
          await _importarDoFirestore();
        },
      ),
    );

    currentChildren.add(const SizedBox(height: 16));

    // Modo escuro
    startSection('Suporte');
    currentChildren.add(_buildMenuTile('Ajuda', Icons.help_outline, '/ajuda',
        sidebarMode: sidebarMode));

    currentChildren.add(
      ListTile(
        dense: sidebarMode,
        visualDensity: sidebarMode ? const VisualDensity(vertical: -1) : null,
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child:
              const Icon(Icons.system_update, color: _primaryColor, size: 20),
        ),
        title: Text(
          'Verificar atualização',
          style: TextStyle(
              color: _primaryColor,
              fontWeight: FontWeight.w500,
              fontSize: sidebarMode ? 13 : null),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
        onTap: () async {
          if (!sidebarMode) Navigator.pop(context);
          if (kIsWeb) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content:
                    Text('No navegador você sempre usa a versão mais recente.'),
                duration: Duration(seconds: 2),
              ),
            );
            return;
          }
          final update = await AppUpdateService.checkForUpdate();
          if (!context.mounted) return;
          final ctx = context;
          if (!ctx.mounted) return;
          if (update != null) {
            showDialog(
              context: ctx,
              barrierDismissible: false,
              builder: (ctx) => UpdateAppDialog(info: update),
            );
          } else {
            ScaffoldMessenger.of(ctx).showSnackBar(
              const SnackBar(
                content: Text('Você já está com a versão mais recente.'),
                duration: Duration(seconds: 3),
              ),
            );
          }
        },
      ),
    );

    startSection('Aparência');
    currentChildren.add(
      ListenableBuilder(
        listenable: darkModeNotifier,
        builder: (_, __) {
          final darkMode = darkModeNotifier.value;
          return SwitchListTile(
            dense: sidebarMode,
            secondary: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(darkMode ? Icons.dark_mode : Icons.light_mode,
                  color: _primaryColor, size: 20),
            ),
            title: Text(
              'Modo escuro',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: sidebarMode ? 13 : null,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            value: darkMode,
            onChanged: (v) => setDarkMode(v),
          );
        },
      ),
    );

    currentChildren.add(const SizedBox(height: 16));

    currentChildren.add(
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ElevatedButton.icon(
          onPressed: () => fazerLogout(context),
          icon: const Icon(Icons.logout),
          label: const Text('Sair'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _errorColor,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );

    currentChildren.add(const SizedBox(height: 24));

    closeSection();
    // ignore: use_build_context_synchronously
    final theme = Theme.of(context);
    final menu = <Widget>[];
    for (final s in sections) {
      if (s.children.isEmpty) continue;
      menu.add(
        ExpansionTile(
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          title: Text(
            s.title.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: s.color ?? theme.colorScheme.onSurface.withOpacity(0.6),
              letterSpacing: 1.2,
            ),
          ),
          children: s.children,
        ),
      );
    }
    return menu;
  }

  // ignore: unused_element
  Widget _buildMenuSection(String title, {Color? color}) {
    final theme = Theme.of(context);
    final sectionColor = color ?? theme.colorScheme.onSurface.withOpacity(0.6);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: sectionColor,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  // ---------- Home M3.8 S2-R3 — accordion + registry ----------
  Future<HomeModuleAccessContext> _loadHomeAccessContext() async {
    final permissoes = await PermissaoService.todas();
    final combinadas = <String, bool>{
      for (final k in permissoes.keys)
        k: (_tipo == 'programador' || _tipo == 'admin')
            ? true
            : (permissoes[k] ?? false),
    };

    PlanAccessTier menuPlanTier = PlanAccessTier.lifetime;
    final bool applyPlanGate = _tipo == 'admin';
    if (applyPlanGate) {
      menuPlanTier = await _resolveMenuPlanTier();
    }

    return HomeModuleAccessContext(
      tipoUsuario: _tipo,
      permissoes: combinadas,
      planTier: menuPlanTier,
      applyPlanGate: applyPlanGate,
    );
  }

  Future<_HomePanelBundle> _loadHomePanelBundle() async {
    final access = await _loadHomeAccessContext();
    return _HomePanelBundle(access: access, openCategoryId: null);
  }

  void _abrirModuloHome(AppModuleDefinition module, {required bool planLocked}) {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    if (planLocked) {
      nav.pushNamed('/planos');
      return;
    }
    if (module.id == 'catalogo_loja') {
      unawaited(_abrirCatalogoLojaPublico());
      return;
    }
    nav.pushNamed(module.route);
  }

  Future<void> _abrirCatalogoLojaPublico() async {
    final slug = _lojaSlugPublico.trim();
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    if (!isValidForPublicLink(slug)) {
      final navCtx = navigatorKey.currentContext;
      if (navCtx != null && navCtx.mounted) {
        await Navigator.of(navCtx).push(
          MaterialPageRoute(
            builder: (_) => const ConfigureLojaPlaceholderScreen(),
          ),
        );
      }
      return;
    }
    // Rota canônica pública: /loja/{slug} (evita CatalogoScreen legado vazio).
    await nav.pushNamed('/loja/$slug');
  }

  void _abrirPortalCategoria(
    HomeModuleCategory category,
    HomeModuleAccessContext access,
  ) {
    final navCtx = navigatorKey.currentContext;
    if (navCtx == null || !navCtx.mounted) return;
    Navigator.of(navCtx).push(
      MaterialPageRoute(
        builder: (_) => HomePortalCategoryScreen(
          category: category,
          access: access,
          onOpenModule: _abrirModuloHome,
        ),
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Bom dia';
    if (hour < 18) return 'Boa tarde';
    return 'Boa noite';
  }

  String _getFirstName(String fullName) {
    if (fullName.contains('@')) {
      return fullName.split('@').first;
    }
    return fullName.split(' ').first;
  }

  /// [FutureBuilder] de listas (atalhos / menu) — erro, loading e retry sem tela vazia.
  Widget _futureListOrError<T>({
    required AsyncSnapshot<List<T>> snap,
    required VoidCallback onRetry,
    required Widget Function(List<T> items) onData,
  }) {
    final theme = Theme.of(context);
    if (snap.hasError) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 48,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(
                'Não foi possível carregar',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Text(
                kDebugMode
                    ? snap.error.toString()
                    : 'Verifique a conexão e tente novamente.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }
    if (snap.connectionState == ConnectionState.waiting) {
      return const Center(
        child: CircularProgressIndicator(color: _primaryColor),
      );
    }
    return onData(snap.data ?? <T>[]);
  }

  @override
  Widget build(BuildContext context) {
    // 🔥 CORREÇÃO: Mostrar landing page apenas se estiver na web E não tiver usuário logado
    if (kIsWeb && _usuario.isEmpty) {
      return _buildWebLanding();
    }

    // ✅ VENDEDOR SEM PERMISSÃO: Mostrar tela de aguarde
    if (_vendedorSemPermissao && _tipo == 'vendedor') {
      return VendedorAguardeWidget(
        vendedorNome: _getFirstName(_usuario),
        lojaId: _lojaIdInterno,
        onLogout: () => fazerLogout(context),
      );
    }

    if (_carregando) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _primaryColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const CircularProgressIndicator(color: _primaryColor),
              ),
              const SizedBox(height: 24),
              Text(
                'Carregando...',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final desktopWeb = kIsWeb && !isMobile(context);

    // Conteúdo principal (body) – layout compacto, uma tela sem overflow
    final mainBody = SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Saudação
                Text(
                  '${_getGreeting()}, ${_getFirstName(_usuario)}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _surfaceColor,
                  ),
                ),
                if (_lojaSlugPublico.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    _lojaSlugPublico,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
                const SizedBox(height: 10),
                if (_lojaIdInterno.isNotEmpty)
                  DashboardHomeCards(lojaId: _lojaIdInterno),
                Expanded(
                  child: FutureBuilder<_HomePanelBundle>(
                    key: ValueKey(_homeCardsRetryKey),
                    future: _loadHomePanelBundle(),
                    builder: (context, snap) {
                      if (snap.hasError) {
                        return Center(
                          child: FilledButton.icon(
                            onPressed: () {
                              unawaited(_refreshPlanGates(force: true));
                            },
                            icon: const Icon(Icons.refresh),
                            label: const Text('Tentar novamente'),
                          ),
                        );
                      }
                      if (!snap.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(color: _primaryColor),
                        );
                      }
                      final bundle = snap.data!;
                      return ListView(
                        padding: const EdgeInsets.only(bottom: 24),
                        children: [
                          HomeQuickActionsRow(
                            access: bundle.access,
                            onModuleTap: _abrirModuloHome,
                          ),
                          Text(
                            'Módulos',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey[600],
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 10),
                          HomePortalGrid(
                            access: bundle.access,
                            onOpenCategory: (cat) =>
                                _abrirPortalCategoria(cat, bundle.access),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Desktop web: sidebar fixa + conteúdo
    if (desktopWeb) {
      final theme = Theme.of(context);
      final bgColor = theme.colorScheme.surface;
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Row(
          children: [
            // Sidebar fixa (usa cores do tema para modo escuro)
            SizedBox(
              width: 280,
              child: Material(
                color: bgColor,
                elevation: 2,
                child: FutureBuilder<List<Widget>>(
                  key: ValueKey(_homeSidebarMenuRetryKey),
                  future: _buildMenuLateral(sidebarMode: true),
                  builder: (context, snap) {
                    return _futureListOrError(
                      snap: snap,
                      onRetry: () {
                        unawaited(_refreshPlanGates(force: true));
                      },
                      onData: (items) => AdminSidebar(
                        usuario: _usuario,
                        tipo: _tipo,
                        menuItems: items,
                        onLogout: () => fazerLogout(context),
                      ),
                    );
                  },
                ),
              ),
            ),
            // Conteúdo
            Expanded(
              child: Column(
                children: [
                  // AppBar simplificada (sem hamburger)
                  Container(
                    color: bgColor,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _getGreeting(),
                                style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.6)),
                              ),
                              Text(
                                _getFirstName(_usuario),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onSurface,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Atualizar',
                          icon: Icon(Icons.refresh,
                              color: theme.colorScheme.onSurface),
                          onPressed: _carregando
                              ? null
                              : () async {
                                  setState(() => _carregando = true);
                                  await _carregarSessao();
                                },
                        ),
                        IconButton(
                          icon: Icon(Icons.search,
                              color: theme.colorScheme.onSurface),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    GlobalSearchScreen(lojaId: _lojaIdInterno),
                              ),
                            );
                          },
                        ),
                        ListenableBuilder(
                          listenable: NotificacaoCentroService(),
                          builder: (_, __) {
                            final svc = NotificacaoCentroService();
                            // ✅ Usar _lojaIdInterno (StoreResolver) em vez de sessao direto
                            final storeId = _lojaIdInterno.isNotEmpty
                                ? _lojaIdInterno
                                : null;
                            final count = svc.unreadCountParaLoja(storeId);
                            return Container(
                              margin: const EdgeInsets.only(right: 8),
                              child: Tooltip(
                                message: count > 0
                                    ? '$count notificação(ões)'
                                    : 'Notificações',
                                child: IconButton(
                                  icon: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF3B82F6)
                                          .withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Badge(
                                      isLabelVisible: count > 0,
                                      label: count > 0
                                          ? Text('$count',
                                              style:
                                                  const TextStyle(fontSize: 10))
                                          : null,
                                      child: const Icon(
                                          Icons.notifications_outlined,
                                          color: Color(0xFF3B82F6),
                                          size: 20),
                                    ),
                                  ),
                                  onPressed: () =>
                                      NotificacaoCentroSheet.show(context),
                                ),
                              ),
                            );
                          },
                        ),
                        IconButton(
                          icon: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _errorColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.logout,
                                color: _errorColor, size: 20),
                          ),
                          onPressed: () => fazerLogout(context),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // Body
                  Expanded(child: mainBody),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DicasIaScreen()),
            );
          },
          icon: const Icon(Icons.auto_awesome),
          label: const Text('Marketing'),
          tooltip: 'Marketing – Dicas e ideias para sua loja com IA',
          backgroundColor: _primaryColor,
          foregroundColor: Colors.white,
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      );
    }

    // Mobile: layout original com Drawer (usa tema para modo escuro)
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: Icon(Icons.menu, color: theme.colorScheme.onSurface),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.store, size: 22, color: theme.colorScheme.onSurface),
                const SizedBox(width: 8),
                const Text(
                  'MasterPalm',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Gerencie sua loja com facilidade',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
        actions: [
          AppHelpIconButton(iconColor: theme.colorScheme.onSurface),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: theme.colorScheme.onSurface),
            tooltip: 'Mais opções',
            onSelected: (value) async {
              switch (value) {
                case 'refresh':
                  if (!_carregando) {
                    setState(() => _carregando = true);
                    await _carregarSessao();
                  }
                  break;
                case 'search':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          GlobalSearchScreen(lojaId: _lojaIdInterno),
                    ),
                  );
                  break;
                case 'sync':
                  // Abre drawer ou mostra snack; sync já tem item no menu
                  break;
                case 'notifications':
                  NotificacaoCentroSheet.show(context);
                  break;
              }
            },
            itemBuilder: (context) {
              // ✅ Usar _lojaIdInterno (StoreResolver) em vez de sessao direto
              final storeId = _lojaIdInterno.isNotEmpty ? _lojaIdInterno : null;
              final notifCount =
                  NotificacaoCentroService().unreadCountParaLoja(storeId);
              return [
                const PopupMenuItem(
                  value: 'refresh',
                  child: ListTile(
                    leading: Icon(Icons.refresh),
                    title: Text('Atualizar'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'search',
                  child: ListTile(
                    leading: Icon(Icons.search),
                    title: Text('Buscar'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'sync',
                  child: ListTile(
                    leading: Icon(Icons.cloud_sync),
                    title: Text('Sincronização'),
                  ),
                ),
                PopupMenuItem(
                  value: 'notifications',
                  child: ListTile(
                    leading: Badge(
                      isLabelVisible: notifCount > 0,
                      label: notifCount > 0 ? Text('$notifCount') : null,
                      child: const Icon(Icons.notifications_outlined),
                    ),
                    title: const Text('Notificações'),
                  ),
                ),
              ];
            },
          ),
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _errorColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.logout, color: _errorColor, size: 20),
            ),
            onPressed: () => fazerLogout(context),
            tooltip: 'Sair',
          ),
        ],
      ),
      drawer: Drawer(
        backgroundColor: theme.colorScheme.surface,
        child: FutureBuilder<List<Widget>>(
          key: ValueKey(_homeDrawerMenuRetryKey),
          future: _buildMenuLateral(),
          builder: (context, snap) {
            return _futureListOrError(
              snap: snap,
              onRetry: () {
                unawaited(_refreshPlanGates(force: true));
              },
              onData: (items) => ListView(
                padding: EdgeInsets.zero,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [_primaryColor, _primaryColor.withOpacity(0.8)],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.person,
                              size: 32, color: Colors.white),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _usuario,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _tipo.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...items,
                ],
              ),
            );
          },
        ),
      ),
      body: mainBody,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DicasIaScreen()),
          );
        },
        icon: const Icon(Icons.auto_awesome),
        label: const Text('Marketing'),
        tooltip: 'Marketing – Dicas e ideias para sua loja com IA',
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

/// Card de plano na landing web (mastepalm.com.br).
/// Mantido aqui para evitar falhas de resolução do import em ambientes Windows.
class _HomePanelBundle {
  const _HomePanelBundle({
    required this.access,
    this.openCategoryId,
  });

  final HomeModuleAccessContext access;
  final String? openCategoryId;
}

class WebLandingPlanCard extends StatelessWidget {
  final String title;
  final String price;
  final String period;
  final Color color;
  final IconData icon;
  final String description;
  final List<String> bullets;
  final String? badge;
  final Color cardColor;
  final Color surfaceColor;

  const WebLandingPlanCard({
    super.key,
    required this.title,
    required this.price,
    required this.period,
    required this.color,
    required this.icon,
    required this.description,
    required this.bullets,
    this.badge,
    required this.cardColor,
    required this.surfaceColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (badge != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withOpacity(0.5)),
              ),
              child: Text(
                badge!,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: surfaceColor,
                      ),
                    ),
                    Text(
                      '$price / $period',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            description,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          ...bullets.map(
            (b) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle_outline, size: 18, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      b,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[800],
                        height: 1.35,
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
  }
}
