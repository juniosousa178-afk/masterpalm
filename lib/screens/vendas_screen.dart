// lib/screens/vendas_screen.dart
import 'dart:async';

import 'package:diacritic/diacritic.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import '../src/file_saver.dart' as file_saver;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/hive_box_names.dart';
import '../core/venda_metrics_filter.dart';
import '../core/logger.dart';
import '../models/cliente.dart';
import '../models/produto.dart';
import '../models/venda.dart';
import '../models/venda_item.dart';
import '../services/permissao_service.dart';
import '../services/vendas_firestore_service.dart';
import '../services/importar_vendas_firestore_service.dart';
import '../services/reconciliacao_vendas_clientes_service.dart';
import '../services/migracao_vendas_itens_service.dart';
import '../services/deduplicacao_clientes_service.dart';
import '../services/firestore_critical_listener_service.dart';
import '../services/produtos_firestore_service.dart';
import '../services/clientes_firestore_service.dart';
import '../services/sync_queue_service.dart';
import '../services/financeiro_firestore_service.dart';
import '../utils/responsive.dart';
import '../widgets/app_help_icon_button.dart';
import '../widgets/empty_state_cta.dart';
import 'nova_venda_modal.dart';
import '../services/loja_id_service.dart';
import '../services/ai_loja_service.dart';
import '../services/ia_uso_limite_service.dart';
import '../services/soft_delete_service.dart';
import '../main.dart' show scaffoldMessengerKey;
import '../utils/store_screen_route_observer.dart';

String removerAcentos(String texto) {
  return removeDiacritics(texto).toLowerCase();
}

class _NovaVendaIntent extends Intent {
  const _NovaVendaIntent();
}

class VendasScreen extends StatefulWidget {
  const VendasScreen({super.key});

  @override
  State<VendasScreen> createState() => _VendasScreenState();
}

class _VendasScreenState extends State<VendasScreen>
    with SingleTickerProviderStateMixin, RouteAware {
  // Cores do tema moderno
  static const Color _primaryColor = Color(0xFF6366F1);
  static const Color _successColor = Color(0xFF22C55E);
  static const Color _warningColor = Color(0xFFF59E0B);
  static const Color _errorColor = Color(0xFFEF4444);
  static const Color _cardColor = Color(0xFFFFFFFF);
  static const Color _backgroundColor = Color(0xFFF8FAFC);
  static const Color _surfaceColor = Color(0xFF1E293B);

  late Box<Venda> vendasBox;
  late Box<Cliente> clientesBox;
  late Box<Produto> produtosBox;

  String searchQuery = '';
  String vendedorSelecionado = 'Todos';
  String? lojaId;
  String ordenacaoVendas = 'data_desc'; // data_desc | data_asc | cliente_asc | cliente_desc
  bool _carregando = true;
  bool _erroResolucaoLoja = false;
  bool _erroHiveCacheLocal = false;
  String? _erroHiveCacheDetalhe;
  /// FASE 3: true quando sync em background falhou (lista local permanece; usuário vê aviso)
  bool _syncFalhou = false;
  bool _importandoVendas = false;
  bool _exportandoVendas = false;
  bool _enviandoVendas = false;
  bool? _temVendasParaImportar; // null = ainda não verificou, true/false = resultado
  String _tipoUsuario = 'vendedor';

  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      logD('[VENDAS_LIFECYCLE] initState uri=${Uri.base}');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        logD(
          '[VENDAS_LIFECYCLE] initState postFrame route=${ModalRoute.of(context)?.settings.name ?? "null"}',
        );
      });
    }
    if (kDebugMode) logD('[STORE-SCREEN-VENDAS] initState → entrada da tela');
    _init();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (kIsWeb) {
      logD(
        '[VENDAS_LIFECYCLE] didChangeDependencies route=${ModalRoute.of(context)?.settings.name ?? "null"} uri=${Uri.base}',
      );
    }
    final route = ModalRoute.of(context);
    if (route != null) {
      storeScreenRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    if (kIsWeb) {
      logD('[VENDAS_LIFECYCLE] dispose uri=${Uri.base}');
    }
    storeScreenRouteObserver.unsubscribe(this);
    FirestoreCriticalListenerService.cancelProdutosListener();
    _searchController.dispose();
    if (kDebugMode) logD('[STORE-SCREEN-VENDAS] dispose → saída da tela');
    super.dispose();
  }

  @override
  void didPopNext() {
    if (kDebugMode) logD('[STORE-SCREEN-VENDAS] didPopNext → retorno para a tela');
    _onReturnToScreen();
  }

  void _onReturnToScreen() {
    if (!mounted) return;
    if (_erroResolucaoLoja || _erroHiveCacheLocal) {
      if (kDebugMode) logD('[STORE-RETURN] Vendas: em erro, reexecutando _init');
      setState(() {
        _erroResolucaoLoja = false;
        _erroHiveCacheLocal = false;
        _erroHiveCacheDetalhe = null;
        _carregando = true;
      });
      _init();
    }
  }

  String _shortStack(StackTrace st) {
    final lines = st.toString().trim().split('\n');
    return lines.take(3).join(' | ');
  }

  Future<void> _repairHiveBoxOnWeb(String boxName, String origin) async {
    if (!kIsWeb) return;
    logW('[HIVE_REPAIR] origem=$origin tentando repair (box=$boxName) uri=${Uri.base}');
    try {
      if (Hive.isBoxOpen(boxName)) {
        final opened = Hive.box(boxName);
        logD('[HIVE_REPAIR] fechando box aberta (box=$boxName)');
        await opened.close();
      }
      await Hive.deleteBoxFromDisk(boxName);
      logD('[HIVE_REPAIR] deleteBoxFromDisk ok (box=$boxName)');
    } catch (e, st) {
      logE('[HIVE_REPAIR] falha ao reparar box (box=$boxName) type=${e.runtimeType}', error: e, st: st);
      logD('[TRACE_ERRO] [HIVE_REPAIR] $origin box=$boxName stack=${_shortStack(st)}');
    }
  }

  Future<void> _init() async {
    if (kDebugMode) {
      final user = FirebaseAuth.instance.currentUser;
      logD('[VENDAS_INIT] inicio _init');
      logD('[VENDAS_INIT] auth uid=${user?.uid ?? "null"} email=${user?.email ?? "null"}');
      // ModalRoute.of(context) não pode rodar antes de initState terminar — log após o 1º frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        logD('[VENDAS_INIT] rota=${ModalRoute.of(context)?.settings.name ?? "null"} uri=${kIsWeb ? Uri.base.toString() : "n/a"}');
      });
      try {
        final sessao = Hive.isBoxOpen('sessao') ? Hive.box('sessao') : await Hive.openBox('sessao');
        final cfg = Hive.isBoxOpen('config') ? Hive.box('config') : await Hive.openBox('config');
        logD('[VENDAS_INIT] sessao.store_id=${sessao.get("store_id")} config.store_id=${cfg.get("store_id")} usuario_logado_email=${sessao.get("usuario_logado_email")} usuario_logado=${sessao.get("usuario_logado")}');
      } catch (e) {
        logW('[VENDAS_INIT] leitura sessao/config falhou (type=${e.runtimeType})');
      }
    }
    bool permissaoOk = false;
    try {
      permissaoOk = await _verificarPermissao()
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
    } on TimeoutException {
      logW('⚠️ [VendasScreen] _verificarPermissao timeout - bloqueando acesso');
      permissaoOk = false;
    } catch (e) {
      logW('⚠️ [VendasScreen] _verificarPermissao erro (type=${e.runtimeType}) - bloqueando acesso');
      permissaoOk = false;
    }
    if (!permissaoOk) {
      if (mounted) {
        Navigator.pop(context);
        _showSnackBar('Você não tem permissão para acessar esta tela ou a verificação falhou.', isError: true);
      }
      return;
    }
    if (!mounted) return;

    logD('[LOJAID] origem=Vendas._init antes LojaIdService.getWithTimeoutThenSessionFallback');
    lojaId = await LojaIdService.getWithTimeoutThenSessionFallback(
        timeout: kIsWeb ? const Duration(seconds: 25) : const Duration(seconds: 10));
    logD('[LOJAID] origem=Vendas._init depois LojaIdService.getWithTimeoutThenSessionFallback valor=${lojaId ?? "null"}');
    if (!mounted) return;
    if (lojaId == null || lojaId!.trim().isEmpty) {
      if (kDebugMode) logD('[STORE-RESOLVE] Vendas: lojaId null, tentando retry em 2s');
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      logD('[LOJAID] origem=Vendas._init retry antes LojaIdService.getWithTimeoutThenSessionFallback');
      lojaId = await LojaIdService.getWithTimeoutThenSessionFallback(
          timeout: kIsWeb ? const Duration(seconds: 15) : const Duration(seconds: 8));
      logD('[LOJAID] origem=Vendas._init retry depois LojaIdService.getWithTimeoutThenSessionFallback valor=${lojaId ?? "null"}');
    }
    if (!mounted) return;
    if (lojaId == null || lojaId!.trim().isEmpty) {
      // Web: Auth pode ter restaurado após o timeout; dar uma última chance
      if (kIsWeb && FirebaseAuth.instance.currentUser == null) {
        logD('[STORE-SCREEN-VENDAS] Web: aguardando Auth (3s) antes de exibir erro');
        try {
          await FirebaseAuth.instance.authStateChanges()
              .where((u) => u != null && !u.isAnonymous)
              .first
              .timeout(const Duration(seconds: 3), onTimeout: () => null);
          if (!mounted) return;
          logD('[LOJAID] origem=Vendas._init authWait antes LojaIdService.getWithTimeoutThenSessionFallback');
          lojaId = await LojaIdService.getWithTimeoutThenSessionFallback(
              timeout: const Duration(seconds: 12));
          logD('[LOJAID] origem=Vendas._init authWait depois LojaIdService.getWithTimeoutThenSessionFallback valor=${lojaId ?? "null"}');
        } catch (e) {
          logW('[VENDAS_INIT] auth wait/retry falhou (type=${e.runtimeType})');
        }
      }
      if (!mounted) return;
      if (lojaId == null || lojaId!.trim().isEmpty) {
        logW('[ERRO_LOJA] origem=Vendas._init motivo=lojaId null/vazio apos retries authUid=${FirebaseAuth.instance.currentUser?.uid ?? "null"} authEmail=${FirebaseAuth.instance.currentUser?.email ?? "null"}');
        if (mounted) {
          setState(() {
            _carregando = false;
            _erroResolucaoLoja = true;
            _erroHiveCacheLocal = false;
            _erroHiveCacheDetalhe = null;
          });
        }
        return;
      }
    }
    if (kDebugMode) logD('[STORE-RESOLVE] Vendas: lojaId=$lojaId');

    // -----------------------------------------------------------------------
    // HIVE: abre boxes em blocos separados (para identificar exatamente qual
    // box está falhando no WEB e reparar somente vendas/clientes).
    // -----------------------------------------------------------------------
    try {
      logD('[HIVE_BOX] origem=Vendas.sessao antes abrir box=sessao uri=${Uri.base}');
      final sessao = await Hive.openBox('sessao');
      logD('[HIVE_BOX] origem=Vendas.sessao depois abrir box=sessao');
      _tipoUsuario = sessao.get('tipo_usuario', defaultValue: 'vendedor');
    } catch (e, st) {
      logE('[HIVE_BOX] origem=Vendas.sessao falha abrir (type=${e.runtimeType})', error: e, st: st);
      logD('[TRACE_ERRO] [VENDAS] sessao box stack=${_shortStack(st)}');
      if (mounted) {
        setState(() {
          _carregando = false;
          _erroHiveCacheLocal = true;
          _erroHiveCacheDetalhe = 'sessao';
        });
      }
      return;
    }

    final vendasBoxName = HiveBoxNames.vendas(lojaId!);
    final clientesBoxName = HiveBoxNames.clientes(lojaId!);
    final produtosBoxName = HiveBoxNames.produtos(lojaId!);

    Object? vendasBoxError;
    Object? clientesBoxError;

    logD(
      '[HIVE_BOX] adapters registradas Cliente(typeId=0)=${Hive.isAdapterRegistered(0)} Venda(typeId=1)=${Hive.isAdapterRegistered(1)}',
    );

    // ---- VENDAS box
    try {
      logD('[HIVE_VENDAS] antes abrir box=$vendasBoxName');
      vendasBox = await Hive.openBox<Venda>(vendasBoxName);
      logD('[HIVE_VENDAS] depois abrir box=$vendasBoxName length=${vendasBox.length}');
    } catch (e, st) {
      vendasBoxError = e;
      logE('[HIVE_BOX] origem=Vendas.vendasBox falha ao abrir (box=$vendasBoxName type=${e.runtimeType})',
          error: e, st: st);
      logD('[TRACE_ERRO] [HIVE_VENDAS] stack=${_shortStack(st)}');

      // Repair SOMENTE no WEB para esta box
      await _repairHiveBoxOnWeb(vendasBoxName, 'Vendas.vendasBox');

      // Re-tentativa 1x após repair
      try {
        logD('[HIVE_VENDAS] retry abrir box=$vendasBoxName após repair');
        vendasBox = await Hive.openBox<Venda>(vendasBoxName);
        logD('[HIVE_VENDAS] retry ok box=$vendasBoxName length=${vendasBox.length}');
        vendasBoxError = null;
      } catch (e2, st2) {
        vendasBoxError = e2;
        logE('[HIVE_BOX] retry falhou (box=$vendasBoxName type=${e2.runtimeType})', error: e2, st: st2);
        logD('[TRACE_ERRO] [HIVE_VENDAS] retry stack=${_shortStack(st2)}');
      }
    }

    // ---- CLIENTES box
    try {
      logD('[HIVE_CLIENTES] antes abrir box=$clientesBoxName');
      clientesBox = await Hive.openBox<Cliente>(clientesBoxName);
      logD('[HIVE_CLIENTES] depois abrir box=$clientesBoxName length=${clientesBox.length}');
    } catch (e, st) {
      clientesBoxError = e;
      logE('[HIVE_BOX] origem=Vendas.clientesBox falha ao abrir (box=$clientesBoxName type=${e.runtimeType})',
          error: e, st: st);
      logD('[TRACE_ERRO] [HIVE_CLIENTES] stack=${_shortStack(st)}');

      // Repair SOMENTE no WEB para esta box
      await _repairHiveBoxOnWeb(clientesBoxName, 'Vendas.clientesBox');

      // Re-tentativa 1x após repair
      try {
        logD('[HIVE_CLIENTES] retry abrir box=$clientesBoxName após repair');
        clientesBox = await Hive.openBox<Cliente>(clientesBoxName);
        logD('[HIVE_CLIENTES] retry ok box=$clientesBoxName length=${clientesBox.length}');
        clientesBoxError = null;
      } catch (e2, st2) {
        clientesBoxError = e2;
        logE('[HIVE_BOX] retry falhou (box=$clientesBoxName type=${e2.runtimeType})', error: e2, st: st2);
        logD('[TRACE_ERRO] [HIVE_CLIENTES] retry stack=${_shortStack(st2)}');
      }
    }

    // ---- PRODUTOS box (NÃO REPARAR aqui, somente abrir)
    try {
      logD('[HIVE_BOX] origem=Vendas.produtosBox antes abrir box=$produtosBoxName');
      produtosBox = await Hive.openBox<Produto>(produtosBoxName);
      logD('[HIVE_BOX] origem=Vendas.produtosBox depois abrir box=$produtosBoxName length=${produtosBox.length}');
    } catch (e, st) {
      logE('[HIVE_BOX] origem=Vendas.produtosBox falha ao abrir (box=$produtosBoxName type=${e.runtimeType})', error: e, st: st);
      logD('[TRACE_ERRO] [VENDAS] produtosBox stack=${_shortStack(st)}');
      // Falha de produtos também é Hive/cache local; mas não especificamos repair aqui.
      if (mounted) {
        setState(() {
          _carregando = false;
          _erroHiveCacheLocal = true;
          _erroHiveCacheDetalhe = 'produtos_$lojaId';
        });
      }
      return;
    }

    // Se qualquer um dos boxes críticos (vendas/clientes) ainda falhou, aborta.
    if (vendasBoxError != null || clientesBoxError != null) {
      logW('[HIVE_BOX] Vendas: falha persistente ao abrir boxes críticas. vendasError=${vendasBoxError != null} clientesError=${clientesBoxError != null}');
      if (mounted) {
        setState(() {
          _carregando = false;
          _erroHiveCacheLocal = true;
          _erroResolucaoLoja = false;
          _erroHiveCacheDetalhe = '${vendasBoxName}${clientesBoxError != null ? ' + ' + clientesBoxName : ''}';
        });
      }
      return;
    }

    if (kDebugMode) {
      logD('📌 [VENDAS_READ] lojaId=$lojaId | vendasLocais=${vendasBox.length} | clientesLocais=${clientesBox.length}');
    }

    // Mostrar tela imediatamente com dados locais (Hive); telas dependentes só "prontas"
    if (mounted) {
      setState(() {
        _carregando = false;
        _erroHiveCacheLocal = false;
        _erroHiveCacheDetalhe = null;
      });
    }

    // Sincronização em background (não bloqueia a abertura da tela)
    _syncEmBackground();
    _verificarSeTemVendasParaImportar();
  }

  Future<void> _verificarSeTemVendasParaImportar() async {
    try {
      final tem = await VendasFirestoreService.hasDataToImport(
        lojaId: lojaId!,
        localCount: vendasBox.length,
      );
      if (mounted) setState(() => _temVendasParaImportar = tem);
    } catch (_) {
      if (mounted) setState(() => _temVendasParaImportar = false);
    }
  }

  Future<void> _syncEmBackground() async {
    if (kDebugMode) {
      logD('🔄 [SYNC] _syncEmBackground iniciando → lojaId=$lojaId | vendasLocais=${vendasBox.length}');
    }
    try {
      await SyncQueueService.processPending();
      await ClientesFirestoreService.syncFirestoreToHive(
        lojaId: lojaId!,
        clientesBox: clientesBox,
      );
      await ImportarVendasFirestoreService.importar(
        lojaId: lojaId!,
        vendasBox: vendasBox,
      );
      await ReconciliacaoVendasClientesService.reconciliar(
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        lojaId: lojaId!,
      );
      await MigracaoVendasItensService.migrarVendasDaBox(vendasBox);
      await DeduplicacaoClientesService.deduplicar(
        clientesBox,
        vendasBox,
        lojaId!,
      );
      if (mounted) setState(() => _syncFalhou = false);
      if (kDebugMode) logD('✅ [SYNC] Vendas/clientes sincronizados');
    } catch (e, st) {
      logE('❌ [SYNC] Erro ao sincronizar vendas do Firestore (type=${e.runtimeType})', error: e, st: st);
      if (mounted) setState(() => _syncFalhou = true);
    }

    try {
      // Enviar alterações locais ANTES de puxar (evita sobrescrever quantidade atualizada no estoque)
      await SyncQueueService.processPending();
      await ProdutosFirestoreService.syncTodosProdutos(
        boxName: produtosBox.name,
        lojaId: lojaId!,
      );
      await ProdutosFirestoreService.syncFirestoreToHive(
        lojaId: lojaId!,
        produtosBox: produtosBox,
      );
      logD('Produtos sincronizados (enviados + puxados)');
    } catch (e, st) {
      logE('Erro ao sincronizar produtos (type=${e.runtimeType})', error: e, st: st);
      if (mounted) setState(() => _syncFalhou = true);
    }

    FirestoreCriticalListenerService.startProdutosListener(
      lojaId: lojaId!,
      produtosBox: produtosBox,
    );

    try {
      await FinanceiroFirestoreService.migrarLojaHiveParaFirestorePolicyA(
        lojaId!,
      );
      await FinanceiroFirestoreService.pullLojaFirestoreParaHiveFase2d(
        lojaId!,
      );
      logD('💰 [SYNC] Módulo financeiro (lançamentos + gastos fixos) sincronizado');
    } catch (e, st) {
      logE(
        'Erro ao sincronizar módulo financeiro (type=${e.runtimeType})',
        error: e,
        st: st,
      );
    }

    if (mounted) setState(() {});
  }

  Future<void> _enviarVendasParaNuvem() async {
    setState(() => _enviandoVendas = true);
    try {
      await SyncQueueService.processPending();
      final boxName = HiveBoxNames.vendas(lojaId!);
      await VendasFirestoreService.syncTodasVendas(boxName: boxName);
      if (!mounted) return;
      _showSnackBar('Envio concluído com sucesso');
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Falha ao enviar para a nuvem: $e', isError: true);
    } finally {
      if (mounted) setState(() => _enviandoVendas = false);
    }
  }

  Future<void> _importarVendasDoFirestore() async {
    setState(() => _importandoVendas = true);
    logD('📥 [SYNC-DEBUG] _importarVendasDoFirestore (botão) → lojaId=$lojaId | vendasLocais=${vendasBox.length}');
    try {
      await SyncQueueService.processPending();
      final resultado = await ImportarVendasFirestoreService.importar(
        lojaId: lojaId!,
        vendasBox: vendasBox,
      );
      await ReconciliacaoVendasClientesService.reconciliar(
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        lojaId: lojaId!,
      );
      await MigracaoVendasItensService.migrarVendasDaBox(vendasBox);
      await DeduplicacaoClientesService.deduplicar(
        clientesBox,
        vendasBox,
        lojaId!,
      );
      if (!mounted) return;
      final msg = resultado.importadas > 0
          ? 'Importação concluída! ${resultado.importadas} venda(s) nova(s) importada(s).'
          : (resultado.jaExistentes > 0
              ? 'Todas as vendas já estavam no aparelho (${resultado.jaExistentes} verificadas).'
              : 'Nenhuma venda nova para importar.');
      _showSnackBar(msg);
      await _verificarSeTemVendasParaImportar();
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Erro ao importar vendas: $e', isError: true);
    } finally {
      if (mounted) setState(() => _importandoVendas = false);
    }
  }

  /// Retorna true se o usuário tem permissão; false caso contrário. Não faz pop.
  Future<bool> _verificarPermissao() async {
    final permitido = await PermissaoService.possuiPermissao('vendas');
    return permitido;
  }

  // ---------------- TOTAIS (por loja) ----------------

  /// Filtro: venda pertence à loja (inclui lojaId null/vazio = legado)
  bool _vendaDaLoja(Venda v) =>
      v.lojaId == null || (v.lojaId?.isEmpty ?? true) || v.lojaId == lojaId;

  /// KPIs / IA: mesma regra que painel e relatórios (exclui cancelada/estornada).
  bool _vendaParaKpis(Venda v) =>
      _vendaDaLoja(v) && incluirVendaEmMetricas(v);

  double get totalVendasDia {
    final hoje = DateTime.now();
    return vendasBox.values
        .where(_vendaParaKpis)
        .where((v) =>
            v.data.day == hoje.day &&
            v.data.month == hoje.month &&
            v.data.year == hoje.year)
        .fold(0.0, (s, v) => s + v.total);
  }

  double get totalVendasMes {
    final hoje = DateTime.now();
    return vendasBox.values
        .where(_vendaParaKpis)
        .where((v) => v.data.month == hoje.month && v.data.year == hoje.year)
        .fold(0.0, (s, v) => s + v.total);
  }

  double get totalVendasAno {
    final hoje = DateTime.now();
    return vendasBox.values
        .where(_vendaParaKpis)
        .where((v) => v.data.year == hoje.year)
        .fold(0.0, (s, v) => s + v.total);
  }

  int get totalVendasCount {
    return vendasBox.values.where(_vendaParaKpis).length;
  }

  // ---------------- LISTA FILTRADA (por loja) ----------------

  List<Venda> get vendasFiltradas {
    final query = removerAcentos(searchQuery);

    var lista = vendasBox.values
        .where(_vendaDaLoja)
        .where((v) {
          final cliente = removerAcentos(v.clienteNome);
          final produto = removerAcentos(v.produtosDescricao);
          final data = DateFormat('dd/MM/yyyy').format(v.data);

          final vendedorMatch =
              vendedorSelecionado == 'Todos' || v.vendedor == vendedorSelecionado;

          return vendedorMatch &&
              (cliente.contains(query) ||
                  produto.contains(query) ||
                  data.contains(query));
        })
        .toList();

    switch (ordenacaoVendas) {
      case 'data_asc':
        lista.sort((a, b) => a.data.compareTo(b.data));
        break;
      case 'cliente_asc':
        lista.sort((a, b) => a.clienteNome.toLowerCase().compareTo(b.clienteNome.toLowerCase()));
        break;
      case 'cliente_desc':
        lista.sort((a, b) => b.clienteNome.toLowerCase().compareTo(a.clienteNome.toLowerCase()));
        break;
      default: // data_desc
        lista.sort((a, b) => b.data.compareTo(a.data));
    }
    return lista;
  }

  List<String> get vendedoresDisponiveis {
    final vendedores = vendasBox.values
        .where((v) => v.lojaId == lojaId)
        .map((v) => v.vendedor)
        .toSet()
        .toList()
      ..sort();
    return ['Todos', ...vendedores];
  }

  String _montarResumoVendasParaIa() {
    final lista = vendasBox.values.where(_vendaParaKpis).toList();
    if (lista.isEmpty) return 'Nenhuma venda registrada nesta loja.';
    final total = lista.fold<double>(0, (s, v) => s + v.total);
    final ticketMedio = total / lista.length;
    final agora = DateTime.now();
    final ultimos30 = lista.where((v) => v.data.isAfter(agora.subtract(const Duration(days: 30)))).toList();
    final total30 = ultimos30.fold<double>(0, (s, v) => s + v.total);
    final porVendedor = <String, double>{};
    for (final v in lista) {
      final nome = v.vendedor.trim().isEmpty ? 'Sem vendedor' : v.vendedor;
      porVendedor[nome] = (porVendedor[nome] ?? 0) + v.total;
    }
    final topVendedores = porVendedor.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final fmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$', decimalDigits: 2);
    final sb = StringBuffer();
    sb.writeln('Total de vendas (geral): ${lista.length}. Faturamento total: ${fmt.format(total)}.');
    sb.writeln('Ticket médio: ${fmt.format(ticketMedio)}.');
    sb.writeln('Últimos 30 dias: ${ultimos30.length} vendas, ${fmt.format(total30)}.');
    sb.writeln('Top vendedores por faturamento: ${topVendedores.take(5).map((e) => '${e.key} ${fmt.format(e.value)}').join('; ')}.');
    return sb.toString();
  }

  void _abrirSugestoesIaVendas() {
    final resumo = _montarResumoVendasParaIa();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => _SugestoesIaVendasScreen(resumoInicial: resumo),
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false, Duration? duration}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
              size: 24,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? _errorColor : _successColor,
        behavior: SnackBarBehavior.floating,
        duration: duration ?? (isError ? const Duration(seconds: 5) : const Duration(seconds: 4)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    if (_erroHiveCacheLocal) {
      return Scaffold(
        appBar: AppBar(title: const Text('Vendas')),
        backgroundColor: _backgroundColor,
        body: _VendasHiveCacheErroLojaBody(
          detalhe: _erroHiveCacheDetalhe ?? 'vendas/clientes',
          onRetry: () {
            if (kDebugMode) logD('[STORE-LIFECYCLE] Vendas: retry Hive cache');
            setState(() {
              _erroHiveCacheLocal = false;
              _erroHiveCacheDetalhe = null;
              _erroResolucaoLoja = false;
              _carregando = true;
            });
            _init();
          },
        ),
      );
    }
    if (_erroResolucaoLoja) {
      return Scaffold(
        appBar: AppBar(title: const Text('Vendas')),
        backgroundColor: _backgroundColor,
        body: _VendasErroLojaBody(
          onRetry: () {
            if (kDebugMode) logD('[STORE-LIFECYCLE] Vendas: clique em Tentar novamente');
            setState(() {
              _erroResolucaoLoja = false;
              _erroHiveCacheLocal = false;
              _erroHiveCacheDetalhe = null;
              _carregando = true;
            });
            _init();
          },
        ),
      );
    }
    if (_carregando) {
      return const Scaffold(
        backgroundColor: _backgroundColor,
        body: _VendasLoadingBody(successColor: _successColor),
      );
    }

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyN, control: true): _NovaVendaIntent(),
      },
      child: Actions(
        actions: {
          _NovaVendaIntent: CallbackAction<_NovaVendaIntent>(
            onInvoke: (_) {
              _abrirNovaVenda();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        backgroundColor: _cardColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _surfaceColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Vendas',
          style: TextStyle(
            color: _surfaceColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          const AppHelpIconButton(iconColor: _surfaceColor),
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _successColor.withValues(alpha:0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _enviandoVendas
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: _successColor),
                    )
                  : const Icon(Icons.cloud_upload, color: _successColor, size: 20),
            ),
            onPressed: _enviandoVendas ? null : _enviarVendasParaNuvem,
            tooltip: 'Enviar para Nuvem',
          ),
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6).withValues(alpha:0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _importandoVendas
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_download, color: Color(0xFF3B82F6), size: 20),
            ),
            onPressed: _importandoVendas ? null : _importarVendasDoFirestore,
            tooltip: _temVendasParaImportar == true
                ? 'Baixar da Nuvem (há vendas novas)'
                : 'Baixar da Nuvem',
          ),
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha:0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.auto_awesome, color: Colors.amber, size: 20),
            ),
            onPressed: _abrirSugestoesIaVendas,
            tooltip: 'Sugestões com IA (vendas, ticket, vendedores)',
          ),
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _primaryColor.withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _exportandoVendas
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: _primaryColor),
                    )
                  : const Icon(Icons.download, color: _primaryColor, size: 20),
            ),
            onPressed: _exportandoVendas ? null : _exportarExcel,
            tooltip: _exportandoVendas ? 'Exportando...' : 'Exportar Excel',
          ),
        ],
        bottom: _operacaoEmAndamento
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'fab_ia_vendas',
            onPressed: _abrirSugestoesIaVendas,
            tooltip: 'Sugestões com IA (vendas, ticket, vendedores)',
            backgroundColor: Colors.amber,
            mini: true,
            child: const Icon(Icons.auto_awesome, color: Colors.black87),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            onPressed: _abrirNovaVenda,
            backgroundColor: _successColor,
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text('Nova Venda', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
          child: Column(
            children: [
              // FASE 3: Aviso quando sync falhou (lista local permanece visível)
              if (_syncFalhou)
                _VendasSyncFalhouBanner(
                  warningColor: _warningColor,
                  onRetry: () {
                    setState(() => _syncFalhou = false);
                    _syncEmBackground();
                  },
                ),
              // Statistics Header
              _buildStatisticsHeader(),

              // Search and Filter
              _buildSearchAndFilter(),

              // Sales List
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _init,
                  child: ValueListenableBuilder(
                    valueListenable: vendasBox.listenable(),
                    builder: (context, Box<Venda> box, _) {
                      final vendas = vendasFiltradas;

                      if (vendas.isEmpty) {
                        return ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                            _buildEmptyState(),
                          ],
                        );
                      }

                      return ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                        itemCount: vendas.length,
                        itemBuilder: (context, index) {
                          final v = vendas[index];
                          return _buildVendaCard(v);
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatisticsHeader() {
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_successColor, _successColor.withValues(alpha:0.8)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _successColor.withValues(alpha:0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha:0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.point_of_sale, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Vendas de Hoje',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha:0.9),
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      currencyFormat.format(totalVendasDia),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha:0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$totalVendasCount vendas',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (_tipoUsuario != 'vendedor') ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Este Mês',
                    currencyFormat.format(totalVendasMes),
                    Icons.calendar_month,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    'Este Ano',
                    currencyFormat.format(totalVendasAno),
                    Icons.calendar_today,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return _VendasStatCard(label: label, value: value, icon: icon);
  }

  Widget _buildSearchAndFilter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          // Search Field
          Container(
            decoration: BoxDecoration(
              color: _cardColor,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha:0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar por cliente, produto ou data...',
                hintStyle: TextStyle(color: Colors.grey[400]),
                prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
                suffixIcon: searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, color: Colors.grey[400]),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => searchQuery = '');
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              onChanged: (value) => setState(() => searchQuery = value),
            ),
          ),
          const SizedBox(height: 12),
          // Filtros: Vendedor + Ordenação
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: _cardColor,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha:0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: vendedorSelecionado,
                      icon: const Icon(Icons.keyboard_arrow_down, color: _primaryColor),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      borderRadius: BorderRadius.circular(12),
                      onChanged: (value) {
                        if (value != null) setState(() => vendedorSelecionado = value);
                      },
                      items: vendedoresDisponiveis.map((v) {
                        return DropdownMenuItem<String>(
                          value: v,
                          child: Row(
                            children: [
                              Icon(
                                v == 'Todos' ? Icons.groups : Icons.person,
                                color: _primaryColor,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(v, overflow: TextOverflow.ellipsis),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: _cardColor,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha:0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: ordenacaoVendas,
                      icon: const Icon(Icons.sort, color: _primaryColor),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      borderRadius: BorderRadius.circular(12),
                      onChanged: (value) {
                        if (value != null) setState(() => ordenacaoVendas = value);
                      },
                      items: const [
                        DropdownMenuItem(value: 'data_desc', child: Text('Data (mais recente)')),
                        DropdownMenuItem(value: 'data_asc', child: Text('Data (mais antiga)')),
                        DropdownMenuItem(value: 'cliente_asc', child: Text('Cliente (A-Z)')),
                        DropdownMenuItem(value: 'cliente_desc', child: Text('Cliente (Z-A)')),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    if (searchQuery.isNotEmpty) {
      return const _VendasEmptyStateFiltros();
    }
    return EmptyStateCta(
      icon: Icons.receipt_long,
      title: 'Nenhuma venda registrada',
      subtitle: 'Registre sua primeira venda para começar',
      buttonLabel: 'Nova venda',
      onPressed: _abrirNovaVenda,
      accentColor: _successColor,
    );
  }

  Widget _buildVendaCard(Venda v) {
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final initials = v.clienteNome.isNotEmpty
        ? v.clienteNome.trim().split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join().toUpperCase()
        : '?';

    // Cor baseada no valor da venda
    final avatarColor = _getAvatarColor(v.clienteNome);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showVendaDetails(v),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    // Avatar
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: avatarColor.withValues(alpha:0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          initials,
                          style: TextStyle(
                            color: avatarColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            v.clienteNome,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: _surfaceColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _resumoProdutos(v),
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                              height: 1.35,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    // Value
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            currencyFormat.format(v.total),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: _successColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            DateFormat('dd/MM/yy').format(v.data),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Footer
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildInfoChip(Icons.payment, _resumoPagamento(v), _primaryColor),
                          _buildInfoChip(Icons.person_outline, _resumoVendedor(v.vendedor), Colors.grey[600]!),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: _primaryColor.withValues(alpha:0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.edit_outlined, color: _primaryColor, size: 18),
                      ),
                      onPressed: () => _showEditarVenda(v),
                      tooltip: 'Editar',
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                    ),
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: _primaryColor.withValues(alpha:0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.print, color: _primaryColor, size: 18),
                      ),
                      onPressed: () => _imprimirPedido(v),
                      tooltip: 'Imprimir',
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                    ),
                    if (_tipoUsuario != 'vendedor')
                      IconButton(
                        icon: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: _errorColor.withValues(alpha:0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.delete_outline, color: _errorColor, size: 18),
                        ),
                        onPressed: () => _confirmarExclusao(v),
                        tooltip: 'Excluir',
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text, Color color) {
    return _VendasInfoChip(icon: icon, text: text, color: color);
  }

  /// Resumo discriminado: Dinheiro R$ X ? Pix R$ Y ? Cartão R$ Z (apenas os preenchidos)
  String _resumoPagamento(Venda v) {
    final partes = <String>[];
    if (v.pagamentoDinheiro > 0) partes.add('Dinheiro R\$ ${v.pagamentoDinheiro.toStringAsFixed(2).replaceAll('.', ',')}');
    if (v.pagamentoPix > 0) partes.add('Pix R\$ ${v.pagamentoPix.toStringAsFixed(2).replaceAll('.', ',')}');
    if (v.pagamentoCartao > 0) partes.add('Cartão R\$ ${v.pagamentoCartao.toStringAsFixed(2).replaceAll('.', ',')}');
    if (partes.isNotEmpty) return partes.join(' ? ');
    return v.formasPagamento.isNotEmpty ? v.formasPagamento : '—';
  }

  String _resumoVendedor(String vendedor) {
    if (vendedor.length <= 18) return vendedor;
    if (vendedor.contains('@')) return vendedor.split('@').first;
    return '${vendedor.substring(0, 18)}...';
  }

  String _resumoProdutos(Venda v) {
    if (v.itens != null && v.itens!.isNotEmpty) {
      if (v.itens!.length == 1) {
        return '${v.itens!.first.quantidade}x ${v.itens!.first.produtoNome}';
      }
      return v.itens!
          .map((i) => '${i.quantidade}x ${i.produtoNome}')
          .take(2)
          .join(' ? ') +
          (v.itens!.length > 2 ? ' +${v.itens!.length - 2}' : '');
    }
    final desc = v.produtosDescricao.trim();
    if (desc.isEmpty) return '-';
    return desc.split('\n').first;
  }

  Color _getAvatarColor(String name) {
    final colors = [
      _primaryColor,
      _successColor,
      _warningColor,
      const Color(0xFF8B5CF6),
      const Color(0xFFEC4899),
      const Color(0xFF06B6D4),
    ];
    final index = name.hashCode.abs() % colors.length;
    return colors[index];
  }

  void _showVendaDetails(Venda v) {
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: _cardColor,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12),
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
                        color: _successColor.withValues(alpha:0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.receipt_long, color: _successColor, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Detalhes da Venda',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: _surfaceColor,
                            ),
                          ),
                          Text(
                            DateFormat('dd/MM/yyyy - HH:mm').format(v.data),
                            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      currencyFormat.format(v.total),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: _successColor,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    _buildDetailSection('Cliente', [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _primaryColor.withValues(alpha:0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _primaryColor.withValues(alpha:0.2),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: _primaryColor.withValues(alpha:0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.person, size: 24, color: _primaryColor),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Cliente',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  SelectableText(
                                    v.clienteNome,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                      color: _surfaceColor,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ]),
                    const SizedBox(height: 16),
                    _buildDetailSection('Produtos', [
                      if (v.itens != null && v.itens!.isNotEmpty) ...[
                        ...v.itens!.map((item) => _buildProdutoItem(item)),
                      ] else
                        _buildDetailRow(Icons.shopping_bag, 'Itens', v.produtosDescricao, expandValue: true),
                      _buildDetailRow(Icons.numbers, 'Quantidade', v.quantidade.toString()),
                    ]),
                    const SizedBox(height: 16),
                    _buildDetailSection('Pagamento', [
                      _buildDetailRow(Icons.attach_money, 'Subtotal', currencyFormat.format(v.preco)),
                      if (v.desconto > 0)
                        _buildDetailRow(Icons.discount, 'Desconto', '${v.desconto.toStringAsFixed(1)}%'),
                      if (v.frete > 0)
                        _buildDetailRow(Icons.local_shipping, 'Frete', currencyFormat.format(v.frete)),
                      _buildDetailRow(Icons.payment, 'Forma', v.formasPagamentoDiscriminado, expandValue: true),
                    ]),
                    const SizedBox(height: 16),
                    _buildDetailSection('Outros', [
                      _buildDetailRow(Icons.badge, 'Vendedor', v.vendedor, expandValue: true),
                      if (v.observacao.isNotEmpty)
                        _buildDetailRow(Icons.note, 'Observação', v.observacao),
                    ]),
                  ],
                ),
              ),
              // Actions
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _imprimirPedido(v);
                        },
                        icon: const Icon(Icons.print),
                        label: const Text('Imprimir'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _primaryColor,
                          side: const BorderSide(color: _primaryColor),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
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
                        child: const Text('Fechar'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey[500],
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: _backgroundColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value, {bool expandValue = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: expandValue
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 20, color: _primaryColor),
                    const SizedBox(width: 12),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 32),
                  child: SelectableText(
                    value,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: _surfaceColor,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: _primaryColor),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                const Spacer(),
                Flexible(
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: _surfaceColor,
                    ),
                    textAlign: TextAlign.right,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildProdutoItem(VendaItem item) {
    final subtotal = item.precoUnitario * item.quantidade;
    final variacao = [
      if (item.tamanho.isNotEmpty) item.tamanho,
      if (item.cor.isNotEmpty) item.cor,
    ].join(' ? ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _successColor.withValues(alpha:0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.inventory_2_outlined, size: 18, color: _successColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item.quantidade}x ${item.produtoNome}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _surfaceColor,
                  ),
                ),
                if (variacao.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      variacao,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ),
              ],
            ),
          ),
          Text(
            'R\$ ${subtotal.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: _successColor,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- Ações ----------------

  Future<void> _abrirNovaVenda() async {
    if (lojaId == null || lojaId!.trim().isEmpty) {
      _showSnackBar('Não foi possível identificar a loja. Tente novamente.', isError: true);
      return;
    }
    final sessao = await Hive.openBox('sessao');
    final vendedor = (sessao.get('usuario_logado') ??
            sessao.get('usuario_logado_email') ??
            'vendedor')
        .toString();

    if (!mounted) return;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NovaVendaModal(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        vendedor: vendedor,
        lojaId: lojaId!,
        onVendaFinalizada: () => setState(() {}),
        onErroAoFinalizar: (msg) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: Colors.red.shade700,
            ),
          );
        },
      ),
    );
    if (!mounted) return;
    if (result == true) {
      _showSnackBar(
        'Venda registrada com sucesso! O estoque foi atualizado.',
        duration: const Duration(seconds: 5),
      );
    }
  }

  Future<void> _confirmarExclusao(Venda venda) async {
    final confirmar = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
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
                color: _errorColor.withValues(alpha:0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_forever, size: 48, color: _errorColor),
            ),
            const SizedBox(height: 16),
            const Text(
              'Excluir Venda?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'A venda será removida. Você pode desfazer em até 30 segundos.',
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
                      backgroundColor: _errorColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Excluir'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );

    if (confirmar == true) {
      try {
        final id = await SoftDeleteService.scheduleVendaDelete(
          venda: venda,
          vendasBox: vendasBox,
          clientesBox: clientesBox,
          lojaId: lojaId!,
        );
        if (mounted) {
          setState(() {});
          scaffoldMessengerKey.currentState?.showSnackBar(
            SnackBar(
              content: const Text('Venda excluída. Desfazer?'),
              duration: const Duration(seconds: 30),
              action: id != null
                  ? SnackBarAction(
                      label: 'Desfazer',
                      onPressed: () {
                        scaffoldMessengerKey.currentState?.hideCurrentSnackBar();
                        _undoVenda(id);
                      },
                    )
                  : null,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (mounted) _showSnackBar('Erro ao excluir venda: $e', isError: true);
      }
    }
  }

  Future<void> _undoVenda(String id) async {
    final ok = await SoftDeleteService.undo(id);
    if (mounted) setState(() {});
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(ok ? 'Venda restaurada' : 'Não foi possível desfazer'),
        backgroundColor: ok ? null : Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showEditarVenda(Venda v) async {
    if (lojaId == null || lojaId!.trim().isEmpty) {
      _showSnackBar('Não foi possível identificar a loja. Tente novamente.', isError: true);
      return;
    }
    final sessao = await Hive.openBox('sessao');
    final vendedor = (sessao.get('usuario_logado') ??
            sessao.get('usuario_logado_email') ??
            'vendedor')
        .toString();

    if (!mounted) return;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NovaVendaModal(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        vendedor: vendedor,
        lojaId: lojaId!,
        vendaParaEditar: v,
        onVendaFinalizada: () => setState(() {}),
        onErroAoFinalizar: (msg) {
          if (!context.mounted) return;
          _showSnackBar(msg, isError: true);
        },
      ),
    );
    if (result == true && mounted) {
      _showSnackBar(
        'Venda atualizada com sucesso! O estoque foi recalculado.',
        duration: const Duration(seconds: 5),
      );
    }
  }

  Future<void> _imprimirPedido(Venda venda) async {
    try {
      Cliente? cliente;
      for (final c in clientesBox.values) {
        if (c.lojaId == lojaId && c.nome == venda.clienteNome) {
          cliente = c;
          break;
        }
      }

      final pdf = pw.Document();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Center(
                  child: pw.Column(
                    children: [
                      pw.Text(
                        'PEDIDO DE VENDA',
                        style: pw.TextStyle(
                          fontSize: 24,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 8),
                      pw.Text(
                        'Loja: $lojaId',
                        style: const pw.TextStyle(fontSize: 12),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Data: ${DateFormat('dd/MM/yyyy – HH:mm').format(venda.data)}',
                        style: const pw.TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 24),
                pw.Divider(thickness: 2),
                pw.SizedBox(height: 16),
                pw.Text(
                  'DADOS DO CLIENTE',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Text('Nome: ${venda.clienteNome}'),
                if (cliente != null) ...[
                  if (cliente.telefone.isNotEmpty)
                    pw.Text('Telefone: ${cliente.telefone}'),
                  if ((cliente.email ?? '').isNotEmpty)
                    pw.Text('Email: ${cliente.email}'),
                  if ((cliente.endereco ?? '').isNotEmpty)
                    pw.Text('Endereço: ${cliente.endereco}'),
                  if (cliente.cep.isNotEmpty)
                    pw.Text('CEP: ${cliente.cep}'),
                  if (cliente.cidade.isNotEmpty)
                    pw.Text('Cidade: ${cliente.cidade}'),
                ],
                pw.SizedBox(height: 16),
                pw.Divider(),
                pw.SizedBox(height: 16),
                pw.Text(
                  'PRODUTOS',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey400),
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.grey300,
                      ),
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text(
                            'Produto',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text(
                            'Tamanho',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text(
                            'Cor',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text(
                            'Variação',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text(
                            'Qtd',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text(
                            'Valor Unit.',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text(
                            'Total',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    if (venda.itens != null && venda.itens!.isNotEmpty)
                      ...venda.itens!.map((item) {
                        final totalItem = item.precoUnitario * item.quantidade;
                        return pw.TableRow(
                          children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(4),
                              child: pw.Text(item.produtoNome),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(4),
                              child: pw.Text(item.tamanho.isNotEmpty ? item.tamanho : '-'),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(4),
                              child: pw.Text(item.cor.isNotEmpty ? item.cor : '-'),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(4),
                              child: pw.Text(
                                item.variacaoExtraResumo.isNotEmpty
                                    ? item.variacaoExtraResumo
                                    : '-',
                              ),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(4),
                              child: pw.Text(item.quantidade.toString()),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(4),
                              child: pw.Text('R\$ ${item.precoUnitario.toStringAsFixed(2)}'),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(4),
                              child: pw.Text('R\$ ${totalItem.toStringAsFixed(2)}'),
                            ),
                          ],
                        );
                      })
                    else
                      pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Text(venda.produtosDescricao),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Text('-'),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Text('-'),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Text('-'),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Text(venda.quantidade.toString()),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Text('R\$ ${venda.preco.toStringAsFixed(2)}'),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Text('R\$ ${venda.total.toStringAsFixed(2)}'),
                          ),
                        ],
                      ),
                  ],
                ),
                pw.SizedBox(height: 16),
                pw.Divider(),
                pw.SizedBox(height: 16),
                pw.Text(
                  'RESUMO FINANCEIRO',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Subtotal:'),
                    pw.Text('R\$ ${venda.preco.toStringAsFixed(2)}'),
                  ],
                ),
                if (venda.frete > 0)
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Frete:'),
                      pw.Text('R\$ ${venda.frete.toStringAsFixed(2)}'),
                    ],
                  ),
                if (venda.desconto > 0)
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Desconto:'),
                      pw.Text('-R\$ ${(venda.preco * venda.desconto / 100).toStringAsFixed(2)} (${venda.desconto.toStringAsFixed(1)}%)'),
                    ],
                  ),
                pw.Divider(),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'TOTAL:',
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      'R\$ ${venda.total.toStringAsFixed(2)}',
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 16),
                pw.Divider(),
                pw.SizedBox(height: 16),
                pw.Text(
                  'PAGAMENTO E ENTREGA',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Text('Forma de Pagamento: ${venda.formasPagamentoDiscriminado}'),
                if (venda.frete > 0) ...[
                  pw.Text('Tipo de Entrega: ${venda.frete > 0 ? "Com frete (R\$ ${venda.frete.toStringAsFixed(2)})" : "Retirada na loja"}'),
                ],
                pw.SizedBox(height: 8),
                pw.Text('Vendedor: ${venda.vendedor}'),
                if (venda.observacao.isNotEmpty) ...[
                  pw.SizedBox(height: 16),
                  pw.Divider(),
                  pw.SizedBox(height: 16),
                  pw.Text(
                    'OBSERVAÇÕES',
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(venda.observacao),
                ],
                pw.Spacer(),
                pw.Divider(),
                pw.SizedBox(height: 8),
                pw.Center(
                  child: pw.Text(
                    'Documento gerado em ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
                    style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                  ),
                ),
              ],
            );
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'Pedido_${venda.clienteNome}_${DateFormat('ddMMyyyy_HHmm').format(venda.data)}.pdf',
      );

      if (mounted) {
        _showSnackBar('Pedido preparado para impressão');
      }
    } catch (e, st) {
      logE('Erro ao imprimir pedido (type=${e.runtimeType})', error: e, st: st);
      if (mounted) {
        _showSnackBar('Erro ao imprimir pedido: $e', isError: true);
      }
    }
  }

  Future<void> _exportarExcel() async {
    setState(() => _exportandoVendas = true);
    try {
      await _exportarExcelImpl();
    } finally {
      if (mounted) setState(() => _exportandoVendas = false);
    }
  }

  Future<void> _exportarExcelImpl() async {
    final excel = Excel.createExcel();
    final sheet = excel['Vendas'];

    sheet.appendRow([
      TextCellValue('Cliente'),
      TextCellValue('Descrição'),
      TextCellValue('Quantidade'),
      TextCellValue('Valor Unitário'),
      TextCellValue('Total'),
      TextCellValue('Forma Pagamento'),
      TextCellValue('Desconto'),
      TextCellValue('Frete'),
      TextCellValue('Vendedor'),
      TextCellValue('Data'),
    ]);

    final vendasDaLoja =
        vendasBox.values.where(_vendaDaLoja).toList();

    for (var v in vendasDaLoja) {
      sheet.appendRow([
        TextCellValue(v.clienteNome),
        TextCellValue(v.produtosDescricao),
        TextCellValue(v.quantidade.toString()),
        TextCellValue(v.preco.toStringAsFixed(2)),
        TextCellValue(v.total.toStringAsFixed(2)),
        TextCellValue(v.formasPagamentoDiscriminado),
        TextCellValue(v.desconto.toStringAsFixed(2)),
        TextCellValue(v.frete.toStringAsFixed(2)),
        TextCellValue(v.vendedor),
        TextCellValue(DateFormat('dd/MM/yyyy HH:mm').format(v.data)),
      ]);
    }

    final bytes = excel.encode();
    if (bytes == null) {
      if (mounted) _showSnackBar('Falha ao gerar arquivo Excel. Tente novamente.', isError: true);
      return;
    }

    final fileName = 'relatorio_vendas_$lojaId.xlsx';
    await file_saver.saveFile(Uint8List.fromList(bytes), fileName);

    if (mounted) {
      _showSnackBar('Arquivo exportado com sucesso!');
    }
  }

  bool get _operacaoEmAndamento => _importandoVendas || _exportandoVendas || _enviandoVendas;
}

/// Widget apenas visual: estado de carregamento da tela de vendas.
class _VendasLoadingBody extends StatelessWidget {
  final Color successColor;

  const _VendasLoadingBody({required this.successColor});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: successColor.withValues(alpha:0.1),
              shape: BoxShape.circle,
            ),
            child: CircularProgressIndicator(color: successColor),
          ),
          const SizedBox(height: 24),
          const Text(
            'Carregando vendas da loja...',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Aguarde alguns segundos enquanto resolvemos o contexto da loja\n'
            'e sincronizamos as vendas com a nuvem.',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Widget apenas visual: estado de erro de resolução da loja (com botão de retry).
class _VendasErroLojaBody extends StatelessWidget {
  final VoidCallback onRetry;

  const _VendasErroLojaBody({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.store_mall_directory_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Não foi possível carregar a loja.',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Verifique sua conexão e tente novamente.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
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
}

/// Widget apenas visual: erro de cache local Hive (vendas/clientes) no navegador.
class _VendasHiveCacheErroLojaBody extends StatelessWidget {
  final String detalhe;
  final VoidCallback onRetry;

  const _VendasHiveCacheErroLojaBody({
    required this.detalhe,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'Falha ao carregar dados locais (cache Hive)',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Problema em: $detalhe. No WEB, o cache pode estar corrompido. Clique em "Tentar novamente" para reparar.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
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
}

/// Widget apenas visual: banner de sincronização falhou (com botão tentar novamente).
class _VendasSyncFalhouBanner extends StatelessWidget {
  final Color warningColor;
  final VoidCallback onRetry;

  const _VendasSyncFalhouBanner({
    required this.warningColor,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: warningColor.withValues(alpha:0.15),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.cloud_off, color: warningColor, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Sincronização falhou. Mostrando dados locais.\nPuxe para atualizar ou toque em "Tentar novamente".',
                  style: TextStyle(fontSize: 13, color: Colors.grey[800]),
                ),
              ),
              TextButton(
                onPressed: onRetry,
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Estado vazio quando a busca não encontrou vendas (apenas visual).
class _VendasEmptyStateFiltros extends StatelessWidget {
  const _VendasEmptyStateFiltros();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha:0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.receipt_long, size: 64, color: Colors.grey[400]),
          ),
          const SizedBox(height: 24),
          Text(
            'Nenhuma venda encontrada',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tente ajustar os filtros de busca',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Card de estatística (label + valor + ícone) para o cabeçalho de vendas.
class _VendasStatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _VendasStatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha:0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha:0.8),
                    fontSize: 11,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip de informação (ícone + texto) usado no card de venda.
class _VendasInfoChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _VendasInfoChip({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha:0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tela cheia de sugestões com IA – Vendas.
class _SugestoesIaVendasScreen extends StatefulWidget {
  final String resumoInicial;

  const _SugestoesIaVendasScreen({required this.resumoInicial});

  @override
  State<_SugestoesIaVendasScreen> createState() => _SugestoesIaVendasScreenState();
}

class _SugestoesIaVendasScreenState extends State<_SugestoesIaVendasScreen> {
  final _perguntaCtrl = TextEditingController();
  String? _resposta;
  bool _enviando = false;
  static const _primaryColor = Color(0xFF6366F1);
  static const _cardColor = Color(0xFF1E293B);

  @override
  void dispose() {
    _perguntaCtrl.dispose();
    super.dispose();
  }

  Future<void> _enviar(String? perguntaFixa) async {
    final pergunta = perguntaFixa ?? _perguntaCtrl.text.trim();
    if (pergunta.isEmpty || _enviando) return;
    final lojaId = await LojaIdService.get();
    if (lojaId == null || lojaId.trim().isEmpty) {
      if (kDebugMode) logD('⚠️ [IA-VENDAS] lojaId não resolvido - uso não contabilizado');
    }
    if (!await IaUsoLimiteService.canUse(lojaId, TipoUsoIa.perguntas)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(IaUsoLimiteService.messageLimitExcedido(TipoUsoIa.perguntas)), backgroundColor: Colors.orange.shade700),
      );
      return;
    }
    if (!mounted) return;
    setState(() { _enviando = true; _resposta = null; });
    try {
      final resposta = await AiLojaService.analiseVendasNatural(
        pergunta: pergunta,
        resumoVendas: widget.resumoInicial,
      );
      if (mounted) {
        IaUsoLimiteService.recordUse(lojaId, TipoUsoIa.perguntas);
        setState(() { _resposta = resposta; _enviando = false; });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _enviando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AiLojaService.messageForUser(e)), backgroundColor: Colors.red.shade700),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _cardColor,
      appBar: AppBar(
        backgroundColor: _cardColor,
        title: const Text('IA – Vendas', style: TextStyle(color: Colors.white)),
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _enviando ? null : () => _enviar(null),
        tooltip: 'Enviar pergunta',
        backgroundColor: _primaryColor,
        child: _enviando
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.send, color: Colors.white),
      ),
      body: Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: 20 + MediaQuery.of(context).padding.bottom + 100,
          ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Sugestões para aumentar vendas e ticket médio. Dados de vendas e vendedores já enviados.',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _enviando ? null : () => _enviar('Como aumentar o ticket médio? Dê sugestões práticas.'),
                  icon: const Icon(Icons.trending_up, size: 18),
                  label: const Text('Aumentar ticket médio'),
                  style: FilledButton.styleFrom(backgroundColor: _primaryColor.withValues(alpha:0.2)),
                ),
                FilledButton.tonalIcon(
                  onPressed: _enviando ? null : () => _enviar('Sugestões para vender mais com base nos dados de vendas e vendedores.'),
                  icon: const Icon(Icons.point_of_sale, size: 18),
                  label: const Text('Vender mais'),
                  style: FilledButton.styleFrom(backgroundColor: _primaryColor.withValues(alpha:0.2)),
                ),
                FilledButton.tonalIcon(
                  onPressed: _enviando ? null : () => _enviar('Analise o desempenho dos vendedores e sugira melhorias ou incentivos.'),
                  icon: const Icon(Icons.people, size: 18),
                  label: const Text('Desempenho vendedores'),
                  style: FilledButton.styleFrom(backgroundColor: _primaryColor.withValues(alpha:0.2)),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _perguntaCtrl,
              decoration: InputDecoration(
                hintText: 'Ex: Por que as vendas caíram no último mês?',
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white.withValues(alpha:0.05),
              ),
              maxLines: 2,
              enabled: !_enviando,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _enviando ? null : () => _enviar(null),
              icon: _enviando ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send),
              label: Text(_enviando ? 'Analisando…' : 'Enviar'),
              style: FilledButton.styleFrom(backgroundColor: _primaryColor),
            ),
            if (_resposta != null) ...[
              const SizedBox(height: 24),
              const Text('Resposta:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _primaryColor.withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Scrollbar(
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    child: SelectableText(_resposta!, style: const TextStyle(color: Colors.white, height: 1.5, fontSize: 15)),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 120),
          ],
        ),
        ),
      ),
    );
  }
}

