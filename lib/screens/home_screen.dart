// lib/screens/home_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
import '../screens/relatorio_financeiro_screen.dart';
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
import '../models/conta_receber.dart';

// ✅ tela fretes/cupons
import '../screens/fretes_cupons_screen.dart';

// ✅ canais meta (WhatsApp, Instagram, Messenger)
import 'configuracoes/canais_meta_screen.dart';

// ✅ sorteios
import 'campanhas_sorteio_screen.dart';
import 'globo_sorteio_screen.dart';

// ✅ sistema de comissões
import 'metas_comissoes_screen.dart';

// ✅ planos
import '../services/planos_service.dart';
import '../utils/theme_notifier.dart';

// ✅ notas fiscais
import '../screens/notas_fiscais_screen.dart';
import '../screens/contas_receber_screen.dart';
import '../screens/financeiro/financeiro_screen.dart';

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
import '../widgets/dashboard_home_cards.dart';
import '../widgets/dashboard_insights_section.dart';
import '../widgets/home_intelligent_section.dart';
import '../widgets/painel_crescimento_widget.dart';
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
import '../widgets/plan_gated_screen.dart';
import '../services/public_store_link_helper.dart';
import '../utils/home_store_context_helper.dart';
// WebLandingPlanCard é declarado no final deste arquivo para evitar problemas de resolução de import.
import '../main.dart' show navigatorKey;
import '../utils/role_utils.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
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
  bool _carregando = true;
  bool _vendedorSemPermissao =
      false; // ✅ Vendedor sem nenhuma permissão liberada

  @override
  void initState() {
    super.initState();

    _carregarSessao();

    // Sincronização automática ao entrar (paridade Web/APK – vendas de qualquer plataforma aparecem em todas)
    AutoSyncService.syncCompleto().then((r) {
      if (mounted) setState(() {}); // Atualiza dashboard quando sync terminar
    }).catchError((_) {});

    // 🔐 Checagem de licença só para ADMIN (não afeta programador/root)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final sessao = await Hive.openBox('sessao');

      // Recalcula tipo (com ROOT override) aqui também, por segurança
      final user = FirebaseAuth.instance.currentUser;
      final email = (user?.email ?? '').trim().toLowerCase();
      final isRoot = (sessao.get('is_root') == true) || RoleUtils.isRootEmail(email);

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

    // 🔹 contexto de loja: SEMPRE resolver do Firestore (users/usuarios) para evitar
    // contaminação: no Web, Hive/IndexedDB é compartilhado; store_id em sessao pode
    // ser de outro usuário (juniosousa178 vs trindadejunio70).
    String? sessaoStore;
    try {
      sessaoStore = (await StoreResolverFacade.resolveForAdminApp()
              .timeout(const Duration(seconds: 8), onTimeout: () => null))
          ?.trim();
      if (sessaoStore != null && sessaoStore.isNotEmpty && isValidForPublicLink(sessaoStore)) {
        sessao.put('store_id', sessaoStore);
        logD('📋 [HOME] store_id resolvido (Firestore): $sessaoStore');
      } else {
        sessaoStore = null;
      }
    } catch (_) {
      sessaoStore = null;
    }
    final ctx = await resolveHomeStoreContext();
    _lojaIdInterno = ctx.lojaIdInterno;
    _lojaSlugPublico = ctx.slugPublico;
    if (_lojaIdInterno.isEmpty && sessaoStore != null && sessaoStore.isNotEmpty) {
      _lojaIdInterno = sessaoStore.trim();
    }
    if (_lojaSlugPublico.isEmpty && _lojaIdInterno.isNotEmpty && isValidForPublicLink(_lojaIdInterno)) {
      _lojaSlugPublico = _lojaIdInterno;
    }
    logD('📋 [HOME] contexto loja: interno=${_lojaIdInterno.isNotEmpty ? "ok" : "vazio"} slugPublico=${_lojaSlugPublico.isNotEmpty ? "ok" : "vazio"}');

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
              : (sessao.get('store_id') ?? sessao.get('storeId') ?? '').toString().trim())
          .trim();
      FirestoreCriticalListenerService.startPermissoesListener(
        userEmail: user.email ?? _usuario,
        tipoUsuario: _tipo,
        storeId: storeId.isNotEmpty ? storeId : null,
        userUid: user.uid,
      );
    }

    if (mounted) setState(() => _carregando = false);
    await _alertarContasReceberPendentes();

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
      final boxName = HiveBoxNames.contasReceber(_lojaIdInterno.trim());
      final box = Hive.isBoxOpen(boxName)
          ? Hive.box<ContaReceber>(boxName)
          : await Hive.openBox<ContaReceber>(boxName);
      if (!mounted) return;

      final hoje = DateTime.now();
      final hojeBase = DateTime(hoje.year, hoje.month, hoje.day);
      final pendentes = box.values
          .where((c) => c.lojaId == _lojaIdInterno && !c.pago)
          .toList();
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

      final valorTotal = (vencidas + vencendo)
          .fold<double>(0, (s, c) => s + c.valor);

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
  void dispose() {
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
      final plan = await svc.fetchCurrentPlan(uid: user.uid, email: email);
      if (!mounted) return;

      // Se não tem plano, manda pra /planos (lá pode ativar grátis 90d 1x)
      if (plan == null) {
        Navigator.pushReplacementNamed(context, '/planos');
        return;
      }

      if (plan.isLifetime) return;

      final end = plan.currentPeriodEnd;
      if (end == null) {
        // free_limited não usa currentPeriodEnd (limites numéricos) — mesmo critério que [app_start_router].
        if (plan.planId == 'free_limited') return;

        // sem end e não lifetime = considera inválido
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
        return;
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
      final lojaId = await LojaIdService.getWithTimeout(timeout: const Duration(seconds: 15))
          ?? await StoreResolverFacade.resolveForAdminApp();
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
        produtosImportados =
            await ProdutosFirestoreService.syncFirestoreToHive(
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
        clientesImportados =
            await ClientesFirestoreService.syncFirestoreToHive(
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
          logW('[IMPORT] Vendas: fallback usado (erro anterior: ${resultadoVendas.erroMensagem})');
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
          msgVendas = '\n\nVendas: ${r.totalNoFirestore} na nuvem (${r.jaExistentes} já estavam no aparelho). Abra a tela de Vendas para visualizá-las.';
        } else if (r != null && r.totalNoFirestore > 0) {
          msgVendas = '\n\nVendas na nuvem: ${r.totalNoFirestore}. Abra a tela de Vendas para conferir.';
        } else {
          msgVendas = '\n\nNenhuma venda nova para importar (todas já estavam no aparelho ou a sincronização ainda não foi feita no outro dispositivo).';
        }
        if (resultadoVendas?.erroMensagem != null) {
          msgVendas += '\n\nAviso: foi usado modo alternativo de leitura (índice Firestore pode estar sendo criado).';
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
      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$', decimalDigits: 2).format(v);

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
        style: TextStyle(fontSize: sidebarMode ? 10 : 11, color: Colors.grey[500]),
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

  Widget _buildMainCard(
    IconData icon,
    String label,
    String route, {
    Widget? pushWidget,
    PlanGateFeature? pushPlanFeature,
    Color? color,
    String? subtitle,
  }) {
    final cardColor = color ?? _primaryColor;

    return InkWell(
      onTap: () {
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
        } else {
          nav.pushNamed(route);
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cardColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 24, color: cardColor),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _surfaceColor,
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[500],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _mainCardWithPlanGate(
    IconData icon,
    String label,
    String route, {
    Widget? pushWidget,
    Color? color,
    String? subtitle,
    required bool applyPlanGate,
    required PlanAccessTier menuPlanTier,
    PlanGateFeature? planFeature,
  }) {
    if (applyPlanGate &&
        planFeature != null &&
        !PlanMatrix.allows(menuPlanTier, planFeature)) {
      return InkWell(
        onTap: () => navigatorKey.currentState?.pushNamed('/planos'),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: _cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _warningColor.withOpacity(0.35)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 22, color: _warningColor),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _surfaceColor,
                ),
                textAlign: TextAlign.center,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: Text(
                  PlanMatrix.upgradeHint(planFeature),
                  style: TextStyle(fontSize: 9, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return _buildMainCard(
      icon,
      label,
      route,
      pushWidget: pushWidget,
      pushPlanFeature: applyPlanGate ? planFeature : null,
      color: color,
      subtitle: subtitle,
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
      final u = FirebaseAuth.instance.currentUser;
      if (u != null) {
        final pi = await PlanosService().fetchCurrentPlan(
          uid: u.uid,
          email: (u.email ?? '').trim().toLowerCase(),
        );
        if (pi != null) menuPlanTier = PlanMatrix.tierFor(pi);
      }
    }

    // Seções expansíveis: (título, cor?, filhos)
    final sections = <({String title, Color? color, List<Widget> children})>[];
    String? currentSection;
    Color? currentSectionColor;
    List<Widget> currentChildren = [];

    void closeSection() {
      if (currentSection != null && currentChildren.isNotEmpty) {
        sections.add((title: currentSection!, color: currentSectionColor, children: List.from(currentChildren)));
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
    final catalogUrl = buildPublicCatalogUrl(_lojaSlugPublico);
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
            child: const Icon(Icons.language, color: Color(0xFF3B82F6), size: 20),
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
      currentChildren.add(_buildMenuTile('Estoque', Icons.inventory_2, '/estoque',
          sidebarMode: sidebarMode));
    }
    if (combinadas['vendas'] == true) {
      currentChildren.add(_buildMenuTile('Vendas', Icons.point_of_sale, '/vendas',
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
      currentChildren.add(_menuTileWithPlanGate('Precificação', Icons.calculate, '/precificacao',
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
      currentChildren.add(_menuTileWithPlanGate('Backup da Loja', Icons.backup, '/backup',
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

      currentChildren.add(_buildMenuTile('Planos', Icons.workspace_premium, '/planos',
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
      currentChildren.add(_buildMenuTile('Alterar PIN', Icons.vpn_key, '/config_pin',
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

  // ---------- cards principais ----------
  Future<List<Widget>> _buildCardsPrincipais() async {
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
      final u = FirebaseAuth.instance.currentUser;
      if (u != null) {
        final pi = await PlanosService().fetchCurrentPlan(
          uid: u.uid,
          email: (u.email ?? '').trim().toLowerCase(),
        );
        if (pi != null) menuPlanTier = PlanMatrix.tierFor(pi);
      }
    }

    final cards = <Widget>[];

    // (Loja/Catálogo: acesso só pelo atalho "Catálogo" nos atalhos inteligentes; não duplicar no grid.)

    // 1. Estoque
    if (combinadas['estoque'] == true) {
      cards.add(_buildMainCard(
        Icons.inventory_2,
        'Estoque',
        '/estoque',
        color: _primaryColor,
        subtitle: 'Produtos',
      ));
    }

    // 3. Clientes
    if (combinadas['clientes'] == true) {
      cards.add(_buildMainCard(
        Icons.people,
        'Clientes',
        '/clientes',
        color: const Color(0xFF8B5CF6),
        subtitle: 'Cadastros',
      ));
    }

    // 4. Vendas
    if (combinadas['vendas'] == true) {
      cards.add(_buildMainCard(
        Icons.point_of_sale,
        'Vendas',
        '/vendas',
        color: _successColor,
        subtitle: 'Histórico',
      ));
    }

    // 5. Fornecedores
    if (combinadas['fornecedores'] == true) {
      cards.add(_mainCardWithPlanGate(
        Icons.local_shipping,
        'Fornecedores',
        '/fornecedores',
        color: _warningColor,
        subtitle: 'Parceiros',
        applyPlanGate: applyPlanGate,
        menuPlanTier: menuPlanTier,
        planFeature: PlanGateFeature.fornecedores,
      ));
    }

    // 6. Relatórios Financeiros (apenas admin/programador)
    if (_tipo == 'admin' || _tipo == 'programador') {
      cards.add(
        _mainCardWithPlanGate(
          Icons.analytics,
          'Relatórios',
          '/relatorio_financeiro',
          pushWidget: const RelatorioFinanceiroScreen(),
          color: const Color(0xFFEC4899),
          subtitle: 'Financeiro',
          applyPlanGate: applyPlanGate,
          menuPlanTier: menuPlanTier,
          planFeature: PlanGateFeature.relatorioFinanceiroDetalhado,
        ),
      );
      cards.add(
        _mainCardWithPlanGate(
          Icons.payments_outlined,
          'Gestão financeira',
          '/financeiro',
          pushWidget: const FinanceiroScreen(),
          color: const Color(0xFF0D9488),
          subtitle: 'Lançamentos',
          applyPlanGate: applyPlanGate,
          menuPlanTier: menuPlanTier,
          planFeature: PlanGateFeature.financeiroLancamentos,
        ),
      );
    }

    // 7. Financeiro & Metas (todos podem ver - filtrado por permissão dentro da tela)
    cards.add(
      _mainCardWithPlanGate(
        Icons.trending_up,
        'Metas',
        '/relatorios_financeiros',
        pushWidget: const RelatoriosFinanceirosScreen(),
        color: const Color(0xFF10B981),
        subtitle: 'Financeiro',
        applyPlanGate: applyPlanGate,
        menuPlanTier: menuPlanTier,
        planFeature: PlanGateFeature.relatoriosFinanceirosHub,
      ),
    );

    return cards;
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header compacto (insight do mês)
                if (isValidForPublicLink(_lojaSlugPublico))
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [_primaryColor, _primaryColor.withOpacity(0.8)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: _primaryColor.withOpacity(0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: DashboardInsightsTicker(
                      lojaId: _lojaIdInterno,
                      isVendedor: _tipo == 'vendedor',
                      vendedorNome: _tipo == 'vendedor'
                          ? _getFirstName(_usuario)
                          : null,
                    ),
                  ),
                if (_lojaIdInterno.isNotEmpty) const SizedBox(height: 8),
                // Atalhos inteligentes (Motor, Campanhas, Catálogo) – interno + slug público
                if (_lojaIdInterno.isNotEmpty)
                  HomeIntelligentSection(
                    lojaIdInterno: _lojaIdInterno,
                    lojaSlugPublico: _lojaSlugPublico,
                  ),
                const SizedBox(height: 6),
                // Painel Crescimento + Dashboard (sempre lojaId interno)
                if (_lojaIdInterno.isNotEmpty) ...[
                  PainelCrescimentoWidget(lojaId: _lojaIdInterno),
                  const SizedBox(height: 6),
                  DashboardHomeCards(lojaId: _lojaIdInterno),
                ],
                const SizedBox(height: 8),
                // Grid de acesso (Loja, Estoque, Vendas, etc.)
                Expanded(
                  child: FutureBuilder<List<Widget>>(
                    future: _buildCardsPrincipais(),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(
                            child: CircularProgressIndicator(
                                color: _primaryColor));
                      }
                      final children = snap.data ?? const <Widget>[];
                      return GridView.count(
                        crossAxisCount: responsiveGridCount(context,
                            mobile: 2, tablet: 3, desktop: 4),
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: desktopWeb ? 1.4 : 1.35,
                        padding: EdgeInsets.zero,
                        children: children,
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
                  future: _buildMenuLateral(sidebarMode: true),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(
                          child:
                              CircularProgressIndicator(color: _primaryColor));
                    }
                    return AdminSidebar(
                      usuario: _usuario,
                      tipo: _tipo,
                      menuItems: snap.data ?? const [],
                      onLogout: () => fazerLogout(context),
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
                Icon(Icons.store,
                    size: 22, color: theme.colorScheme.onSurface),
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
                      builder: (_) => GlobalSearchScreen(lojaId: _lojaIdInterno),
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
          future: _buildMenuLateral(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                  child: CircularProgressIndicator(color: _primaryColor));
            }
            return ListView(
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
                ...(snap.data ?? const []),
              ],
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
