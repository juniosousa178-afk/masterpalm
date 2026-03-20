// lib/screens/clientes_screen.dart
import 'dart:async';

import 'dart:io' as io if (dart.library.html) 'package:master_palm/utils/io_stub.dart';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:contacts_service_plus/contacts_service_plus.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/hive_box_names.dart';
import '../core/logger.dart';
import '../widgets/empty_state_cta.dart';
import '../models/cliente.dart';
import '../models/venda.dart';
import '../services/limits_guard.dart';
import '../services/permissao_service.dart';
import '../services/loja_id_service.dart';
import '../services/clientes_firestore_service.dart';
import '../services/sync_queue_service.dart';
import '../services/vendas_firestore_service.dart';
import '../services/reconciliacao_vendas_clientes_service.dart';
import '../services/repair_historico_clientes_service.dart';
import '../services/deduplicacao_clientes_service.dart';
import '../utils/export_excel.dart';
import '../utils/responsive.dart';
import '../utils/text_utils.dart' show normalizeText, capitalizeWords;
import 'redefinir_senha_cliente_loja_screen.dart';
import '../services/ai_loja_service.dart';
import '../services/ia_uso_limite_service.dart';
import '../services/soft_delete_service.dart';
import '../main.dart' show scaffoldMessengerKey;
import '../utils/store_screen_route_observer.dart';

class ClientesScreen extends StatefulWidget {
  const ClientesScreen({super.key});

  @override
  State<ClientesScreen> createState() => _ClientesScreenState();
}

class _ClientesScreenState extends State<ClientesScreen>
    with SingleTickerProviderStateMixin, RouteAware {
  // Controllers básicos
  final TextEditingController _nomeController = TextEditingController();
  final TextEditingController _telefoneController = TextEditingController();
  final TextEditingController _instagramController = TextEditingController();
  final TextEditingController _cepController = TextEditingController();
  final TextEditingController _cidadeController = TextEditingController();
  final TextEditingController _filtroController = TextEditingController();

  // Campos extra
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _enderecoController = TextEditingController();

  // Avatar temporário do diálogo
  Uint8List? _novoAvatarBytes;

  late Box<Cliente> clientesBox;
  late Box<Venda> vendasBox;

  String? lojaId;
  String filtro = '';
  bool _carregando = true;
  bool _erroResolucaoLoja = false;
  bool _erroHiveCacheLocal = false;
  String? _erroHiveCacheDetalhe;
  /// FASE 3: true quando sync em background falhou (lista local permanece; usuário vê aviso)
  bool _syncFalhou = false;
  bool _importando = false;
  bool _exportando = false;
  bool _reparando = false;
  bool _sincronizando = false;
  bool _enviandoClientes = false;
  bool? _temDadosParaImportar; // null = ainda não verificou
  Timer? _filtroDebounce;
  static const _filtroDebounceDuration = Duration(milliseconds: 300);

  // TabController para as abas
  late TabController _tabController;

  // Filtros para histórico
  DateTime? dataInicial;
  DateTime? dataFinal;
  String filtroNomeHistorico = '';
  String ordenacaoClientes = 'alfabetica'; // alfabetica | alfabetica_desc | data
  String ordenacaoHistorico = 'data_desc'; // data_desc | data_asc | cliente_asc | cliente_desc

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      logD('[CLIENTES_LIFECYCLE] initState uri=${Uri.base}');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        logD(
          '[CLIENTES_LIFECYCLE] initState postFrame route=${ModalRoute.of(context)?.settings.name ?? "null"}',
        );
      });
    }
    if (kDebugMode) logD('[STORE-SCREEN-CLIENTES] initState → entrada da tela');

    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });

    _filtroController.addListener(() {
      _filtroDebounce?.cancel();
      _filtroDebounce = Timer(_filtroDebounceDuration, () {
        if (mounted) {
          setState(() {
            filtro = _filtroController.text.toLowerCase().trim();
          });
        }
      });
    });

    _init();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (kIsWeb) {
      logD(
        '[CLIENTES_LIFECYCLE] didChangeDependencies route=${ModalRoute.of(context)?.settings.name ?? "null"} uri=${Uri.base}',
      );
    }
    final route = ModalRoute.of(context);
    if (route != null) {
      storeScreenRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPopNext() {
    if (kDebugMode) logD('[STORE-SCREEN-CLIENTES] didPopNext → retorno para a tela');
    _onReturnToScreen();
  }

  void _onReturnToScreen() {
    if (!mounted) return;
    if (_erroResolucaoLoja || _erroHiveCacheLocal) {
      if (kDebugMode) logD('[STORE-RETURN] Clientes: em erro, reexecutando _init');
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
      logD('[CLIENTES_INIT] inicio _init');
      logD('[CLIENTES_INIT] auth uid=${user?.uid ?? "null"} email=${user?.email ?? "null"}');
      logD('[CLIENTES_INIT] rota=${ModalRoute.of(context)?.settings.name ?? "null"} uri=${kIsWeb ? Uri.base.toString() : "n/a"}');
      try {
        final sessao = Hive.isBoxOpen('sessao') ? Hive.box('sessao') : await Hive.openBox('sessao');
        final cfg = Hive.isBoxOpen('config') ? Hive.box('config') : await Hive.openBox('config');
        logD('[CLIENTES_INIT] sessao.store_id=${sessao.get("store_id")} config.store_id=${cfg.get("store_id")} usuario_logado_email=${sessao.get("usuario_logado_email")} usuario_logado=${sessao.get("usuario_logado")}');
      } catch (e) {
        logW('[CLIENTES_INIT] leitura sessao/config falhou (type=${e.runtimeType})');
      }
    }
    try {
      await _verificarPermissao()
          .timeout(const Duration(seconds: 5), onTimeout: () {});
    } on TimeoutException {
      logW('⚠️ [ClientesScreen] _verificarPermissao timeout - prosseguindo');
    } catch (_) {}
    if (!mounted) return;

    logD('[LOJAID] origem=Clientes._init antes LojaIdService.getWithTimeout');
    lojaId = await LojaIdService.getWithTimeout(
        timeout: kIsWeb ? const Duration(seconds: 25) : const Duration(seconds: 10));
    logD('[LOJAID] origem=Clientes._init depois LojaIdService.getWithTimeout valor=${lojaId ?? "null"}');
    if (!mounted) return;
    if (lojaId == null || lojaId!.trim().isEmpty) {
      if (kDebugMode) logD('[STORE-RESOLVE] Clientes: lojaId null, tentando retry em 2s');
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      logD('[LOJAID] origem=Clientes._init retry antes LojaIdService.getWithTimeout');
      lojaId = await LojaIdService.getWithTimeout(
          timeout: kIsWeb ? const Duration(seconds: 15) : const Duration(seconds: 8));
      logD('[LOJAID] origem=Clientes._init retry depois LojaIdService.getWithTimeout valor=${lojaId ?? "null"}');
    }
    if (!mounted) return;
    if (lojaId == null || lojaId!.trim().isEmpty) {
      if (kIsWeb && FirebaseAuth.instance.currentUser == null) {
        if (kDebugMode) logD('[STORE-SCREEN-CLIENTES] Web: aguardando Auth (3s) antes de exibir erro');
        try {
          await FirebaseAuth.instance.authStateChanges()
              .where((u) => u != null && !u.isAnonymous)
              .first
              .timeout(const Duration(seconds: 3), onTimeout: () => null);
          if (!mounted) return;
          logD('[LOJAID] origem=Clientes._init authWait antes LojaIdService.getWithTimeout');
          lojaId = await LojaIdService.getWithTimeout(
              timeout: const Duration(seconds: 12));
          logD('[LOJAID] origem=Clientes._init authWait depois LojaIdService.getWithTimeout valor=${lojaId ?? "null"}');
        } catch (e) {
          logW('[CLIENTES_INIT] auth wait/retry falhou (type=${e.runtimeType})');
        }
      }
      if (!mounted) return;
      if (lojaId == null || lojaId!.trim().isEmpty) {
        logW('[ERRO_LOJA] origem=Clientes._init motivo=lojaId null/vazio apos retries authUid=${FirebaseAuth.instance.currentUser?.uid ?? "null"} authEmail=${FirebaseAuth.instance.currentUser?.email ?? "null"}');
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
    if (kDebugMode) logD('[STORE-RESOLVE] Clientes: lojaId=$lojaId');

    // -----------------------------------------------------------------------
    // HIVE: abre boxes em blocos separados (para identificar exatamente qual
    // box está falhando no WEB e reparar somente clientes/vendas).
    // -----------------------------------------------------------------------
    try {
      logD('[HIVE_BOX] origem=Clientes.sessao antes abrir box=sessao uri=${Uri.base}');
      await Hive.openBox('sessao');
      logD('[HIVE_BOX] origem=Clientes.sessao depois abrir box=sessao');
    } catch (e, st) {
      logE('[HIVE_BOX] origem=Clientes.sessao falha ao abrir (type=${e.runtimeType})', error: e, st: st);
      logD('[TRACE_ERRO] [CLIENTES] sessao box stack=${_shortStack(st)}');
      if (mounted) {
        setState(() {
          _carregando = false;
          _erroResolucaoLoja = false;
          _erroHiveCacheLocal = true;
          _erroHiveCacheDetalhe = 'sessao';
        });
      }
      return;
    }

    final clientesBoxName = HiveBoxNames.clientes(lojaId!);
    final vendasBoxName = HiveBoxNames.vendas(lojaId!);

    Object? clientesBoxError;
    Object? vendasBoxError;

    logD(
      '[HIVE_BOX] adapters registradas Cliente(typeId=0)=${Hive.isAdapterRegistered(0)} Venda(typeId=1)=${Hive.isAdapterRegistered(1)}',
    );

    // ---- CLIENTES box
    try {
      logD('[HIVE_BOX] origem=Clientes.clientesBox antes abrir box=$clientesBoxName');
      clientesBox = await Hive.openBox<Cliente>(clientesBoxName);
      logD('[HIVE_BOX] origem=Clientes.clientesBox depois abrir box=$clientesBoxName length=${clientesBox.length}');
    } catch (e, st) {
      clientesBoxError = e;
      logE('[HIVE_BOX] origem=Clientes.clientesBox falha ao abrir (box=$clientesBoxName type=${e.runtimeType})', error: e, st: st);
      logD('[TRACE_ERRO] [HIVE_CLIENTES] stack=${_shortStack(st)}');
      await _repairHiveBoxOnWeb(clientesBoxName, 'Clientes.clientesBox');
      try {
        logD('[HIVE_CLIENTES] retry abrir box=$clientesBoxName após repair');
        clientesBox = await Hive.openBox<Cliente>(clientesBoxName);
        logD('[HIVE_CLIENTES] retry ok length=${clientesBox.length}');
        clientesBoxError = null;
      } catch (e2, st2) {
        clientesBoxError = e2;
        logE('[HIVE_BOX] retry falhou (box=$clientesBoxName type=${e2.runtimeType})', error: e2, st: st2);
        logD('[TRACE_ERRO] [HIVE_CLIENTES] retry stack=${_shortStack(st2)}');
      }
    }

    // ---- VENDAS box
    try {
      logD('[HIVE_BOX] origem=Clientes.vendasBox antes abrir box=$vendasBoxName');
      vendasBox = await Hive.openBox<Venda>(vendasBoxName);
      logD('[HIVE_BOX] origem=Clientes.vendasBox depois abrir box=$vendasBoxName length=${vendasBox.length}');
    } catch (e, st) {
      vendasBoxError = e;
      logE('[HIVE_BOX] origem=Clientes.vendasBox falha ao abrir (box=$vendasBoxName type=${e.runtimeType})', error: e, st: st);
      logD('[TRACE_ERRO] [HIVE_VENDAS] stack=${_shortStack(st)}');
      await _repairHiveBoxOnWeb(vendasBoxName, 'Clientes.vendasBox');
      try {
        logD('[HIVE_VENDAS] retry abrir box=$vendasBoxName após repair');
        vendasBox = await Hive.openBox<Venda>(vendasBoxName);
        logD('[HIVE_VENDAS] retry ok length=${vendasBox.length}');
        vendasBoxError = null;
      } catch (e2, st2) {
        vendasBoxError = e2;
        logE('[HIVE_BOX] retry falhou (box=$vendasBoxName type=${e2.runtimeType})', error: e2, st: st2);
        logD('[TRACE_ERRO] [HIVE_VENDAS] retry stack=${_shortStack(st2)}');
      }
    }

    // Se qualquer box crítica falhar, aborta com cache local.
    if (clientesBoxError != null || vendasBoxError != null) {
      logW('[HIVE_BOX] Clientes: falha persistente ao abrir boxes críticas. clientesError=${clientesBoxError != null} vendasError=${vendasBoxError != null}');
      if (mounted) {
        setState(() {
          _carregando = false;
          _erroResolucaoLoja = false;
          _erroHiveCacheLocal = true;
          _erroHiveCacheDetalhe =
              '$clientesBoxName${vendasBoxError != null ? ' + $vendasBoxName' : ''}';
        });
      }
      return;
    }

    if (kDebugMode) {
      logD('📌 [CLIENTES_READ] lojaId=$lojaId | clientesLocais=${clientesBox.length} | vendasLocais=${vendasBox.length}');
    }

    if (mounted) {
      setState(() {
        _carregando = false;
        _erroHiveCacheLocal = false;
        _erroHiveCacheDetalhe = null;
      });
    }

    _syncClientesEmBackground();
    _verificarSeTemDadosParaImportar();
  }

  Future<void> _verificarSeTemDadosParaImportar() async {
    try {
      final tem = await ClientesFirestoreService.hasDataToImport(
        lojaId: lojaId!,
        localCount: clientesBox.length,
      );
      if (mounted) setState(() => _temDadosParaImportar = tem);
    } catch (_) {
      if (mounted) setState(() => _temDadosParaImportar = false);
    }
  }

  Future<void> _syncClientesEmBackground() async {
    if (kDebugMode) logD('🔄 [SYNC] _syncClientesEmBackground iniciando → lojaId=$lojaId');
    bool falhou = false;
    try {
      await SyncQueueService.processPending();
    } catch (_) {}

    try {
      await ClientesFirestoreService.syncFirestoreToHive(
        lojaId: lojaId!,
        clientesBox: clientesBox,
      );
    } catch (e) {
      logW('⚠️ [SYNC] Erro ao sincronizar clientes (type=${e.runtimeType})');
      falhou = true;
    }

    try {
      await VendasFirestoreService.syncFirestoreToHive(
        lojaId: lojaId!,
        vendasBox: vendasBox,
      );
    } catch (e) {
      logW('⚠️ [SYNC] Erro ao sincronizar vendas (type=${e.runtimeType})');
      falhou = true;
    }

    try {
      final n = await ReconciliacaoVendasClientesService.reconciliar(
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        lojaId: lojaId!,
      );
      if (n > 0 && kDebugMode) logD('✅ $n vendas vinculadas ao histórico');
    } catch (e) {
      logW('⚠️ [SYNC] Erro ao reconciliar (type=${e.runtimeType})');
      falhou = true;
    }

    try {
      await DeduplicacaoClientesService.deduplicar(clientesBox, vendasBox, lojaId!);
    } catch (e) {
      logW('⚠️ [SYNC] Erro ao deduplicar (type=${e.runtimeType})');
      falhou = true;
    }

    if (mounted) setState(() => _syncFalhou = falhou);
    if (kDebugMode && !falhou) logD('✅ [SYNC] Clientes/vendas sincronizados');
  }

  Future<void> _enviarClientesParaNuvem() async {
    setState(() => _enviandoClientes = true);
    try {
      await SyncQueueService.processPending();
      final boxName = HiveBoxNames.clientes(lojaId!);
      await ClientesFirestoreService.syncTodosClientes(boxName: boxName);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Envio concluído com sucesso'),
          backgroundColor: Colors.green,
        ),
      );
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Falha ao enviar para a nuvem: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _enviandoClientes = false);
    }
  }

  Future<void> _baixarClientesDaNuvem() async {
    setState(() => _sincronizando = true);
    try {
      await SyncQueueService.processPending();
      final n = await ClientesFirestoreService.syncFirestoreToHive(
        lojaId: lojaId!,
        clientesBox: clientesBox,
      );
      if (!mounted) return;
      await ReconciliacaoVendasClientesService.reconciliar(
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        lojaId: lojaId!,
      );
      await DeduplicacaoClientesService.deduplicar(clientesBox, vendasBox, lojaId!);
      await _verificarSeTemDadosParaImportar();
      if (!mounted) return;
      final msg = n > 0
          ? 'Baixados $n novo(s) cliente(s)'
          : 'Nenhum cliente novo encontrado';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Colors.green,
        ),
      );
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Falha ao baixar da nuvem: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _sincronizando = false);
    }
  }

  // ignore: unused_element
  Future<void> _sincronizarDoFirestore() async {
    setState(() => _sincronizando = true);
    try {
      await _syncClientesEmBackground();
      if (!mounted) return;
      await _verificarSeTemDadosParaImportar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sincronização concluída!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao sincronizar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _sincronizando = false);
    }
  }

  @override
  void dispose() {
    if (kIsWeb) {
      logD('[CLIENTES_LIFECYCLE] dispose uri=${Uri.base}');
    }
    storeScreenRouteObserver.unsubscribe(this);
    if (kDebugMode) logD('[STORE-SCREEN-CLIENTES] dispose → saída da tela');
    _filtroDebounce?.cancel();
    _nomeController.dispose();
    _telefoneController.dispose();
    _instagramController.dispose();
    _cepController.dispose();
    _cidadeController.dispose();
    _filtroController.dispose();
    _emailController.dispose();
    _enderecoController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _verificarPermissao() async {
    final permitido = await PermissaoService.possuiPermissao('clientes');
    if (!permitido && mounted) {
      final messenger = ScaffoldMessenger.of(context);
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Você não tem permissão para acessar esta tela'),
        ),
      );
    }
  }

  // -------------------------------
  // Utilitários
  // -------------------------------

  String _getInitials(String name) {
    final t = name.trim();
    if (t.isEmpty) return '?';
    final parts = t.split(' ');
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) {
      return parts[0].isEmpty ? '?' : parts[0][0].toUpperCase();
    }
    final last = parts[parts.length - 1];
    if (parts[0].isEmpty || last.isEmpty) return '?';
    return '${parts[0][0]}${last[0]}'.toUpperCase();
  }

  Color _getAvatarColor(String name) {
    final colors = [
      const Color(0xFF6366F1), // Indigo
      const Color(0xFF8B5CF6), // Purple
      const Color(0xFFEC4899), // Pink
      const Color(0xFFEF4444), // Red
      const Color(0xFFF97316), // Orange
      const Color(0xFFEAB308), // Yellow
      const Color(0xFF22C55E), // Green
      const Color(0xFF14B8A6), // Teal
      const Color(0xFF06B6D4), // Cyan
      const Color(0xFF3B82F6), // Blue
    ];
    final index = name.isEmpty ? 0 : name.codeUnitAt(0) % colors.length;
    return colors[index];
  }

  Future<String?> _salvarAvatarLocal(String telefoneE164, Uint8List bytes) async {
    if (kIsWeb) return null; // No web, avatars não são salvos localmente
    try {
      final dir = await getApplicationDocumentsDirectory();
      final avatarsDir = io.Directory(p.join(dir.path, 'avatars'));
      if (!await avatarsDir.exists()) {
        await avatarsDir.create(recursive: true);
      }

      final file = io.File(p.join(avatarsDir.path, '$telefoneE164.jpg'));
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickAvatarFromGallery(StateSetter setStateDialog) async {
    final picker = ImagePicker();
    final XFile? img =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (img != null) {
      _novoAvatarBytes = await img.readAsBytes();
      setStateDialog(() {});
    }
  }

  // -------------------------------
  // Estatísticas
  // -------------------------------

  /// Estatísticas: clientes da clientesBox, vendas/valor da vendasBox (fonte única)
  Map<String, dynamic> _getStats() {
    final clientes = clientesBox.values.where((c) => c.lojaId == lojaId).toList();
    final vendasDaLoja = vendasBox.values.where((v) {
      if (v.lojaId != null && v.lojaId!.isNotEmpty && v.lojaId != lojaId) return false;
      return true;
    }).toList();

    return {
      'total': clientes.length,
      'vendas': vendasDaLoja.length,
      'valor': vendasDaLoja.fold<double>(0, (s, v) => s + v.total),
    };
  }

  // -------------------------------
  // Adicionar / editar cliente
  // -------------------------------

  Future<void> adicionarCliente() async {
    if (_nomeController.text.isEmpty || _telefoneController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Nome e Telefone são obrigatórios")),
      );
      return;
    }

    final guard = LimitsGuard();
    final pode = await guard.canAddCliente(lojaId!);
    if (!mounted) return;
    if (!pode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Limite de clientes atingido no plano Free. Faça upgrade para adicionar mais.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final cliente = Cliente(
      nome: capitalizeWords(_nomeController.text.trim()),
      telefone: _telefoneController.text.trim(),
      instagram: _instagramController.text.trim(),
      cep: _cepController.text.trim(),
      cidade: _cidadeController.text.trim(),
      lojaId: lojaId!,
    );

    clientesBox.add(cliente);
    ClientesFirestoreService.syncCliente(cliente, lojaId: lojaId!);

    if (!mounted) return;
    _nomeController.clear();
    _telefoneController.clear();
    _instagramController.clear();
    _cepController.clear();
    _cidadeController.clear();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Cliente adicionado com sucesso!")),
    );
  }

  void editarCliente(Cliente cliente) {
    _nomeController.text = cliente.nome;
    _telefoneController.text = cliente.telefone;
    _instagramController.text = cliente.instagram;
    _cepController.text = cliente.cep;
    _cidadeController.text = cliente.cidade;
    _emailController.text = cliente.email ?? '';
    _enderecoController.text = cliente.endereco ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: _getAvatarColor(cliente.nome),
                    child: Text(
                      _getInitials(cliente.nome),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Editar Cliente',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          cliente.nome,
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildTextField(
                controller: _nomeController,
                label: 'Nome',
                icon: Icons.person_outline,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _telefoneController,
                label: 'Telefone',
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _emailController,
                label: 'E-mail',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _instagramController,
                label: 'Instagram',
                icon: Icons.alternate_email,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _enderecoController,
                label: 'Endereço',
                icon: Icons.location_on_outlined,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _cepController,
                      label: 'CEP',
                      icon: Icons.local_post_office_outlined,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildTextField(
                      controller: _cidadeController,
                      label: 'Cidade',
                      icon: Icons.location_city_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    cliente.nome = capitalizeWords(_nomeController.text.trim());
                    cliente.telefone = _telefoneController.text.trim();
                    cliente.instagram = _instagramController.text.trim();
                    cliente.cep = _cepController.text.trim();
                    cliente.cidade = _cidadeController.text.trim();
                    cliente.email = _emailController.text.trim().isEmpty
                        ? null
                        : _emailController.text.trim();
                    cliente.endereco = _enderecoController.text.trim().isEmpty
                        ? null
                        : _enderecoController.text.trim();

                    if (cliente.lojaId.isEmpty) {
                      cliente.lojaId = lojaId!;
                    }

                    cliente.save();
                    ClientesFirestoreService.syncCliente(cliente, lojaId: lojaId!);

                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Cliente atualizado!")),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Salvar Alterações',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        filled: true,
        fillColor: Colors.grey[100],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF6366F1), width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  /// Retorna o resumo dos produtos da venda (itens exatamente como vendidos)
  String _resumoProdutosVenda(Venda v) {
    final itens = v.itensOuVazio;
    if (itens.isNotEmpty) {
      return itens.map((item) {
        final variacao = [
          if (item.tamanho.isNotEmpty) item.tamanho,
          if (item.cor.isNotEmpty) item.cor,
        ].join(' / ');
        final suf = variacao.isNotEmpty ? ' ($variacao)' : '';
        return '${item.quantidade}x ${item.produtoNome}$suf';
      }).join('\n');
    }
    return v.produtosDescricao;
  }

  /// Retorna o cliente pelo nome (primeiro que corresponder).
  Cliente? _clientePorNome(String nome) {
    final nomeNorm = normalizeText(nome);
    return clientesBox.values.firstWhereOrNull(
      (c) => _lojaMatch(c.lojaId, lojaId) && normalizeText(c.nome) == nomeNorm,
    );
  }

  static bool _lojaMatch(String? cLoja, String? lojaId) {
    if (lojaId == null || lojaId.isEmpty) return false;
    if (cLoja == null || cLoja.isEmpty) return true; // legado: mostra no contexto atual
    return cLoja == lojaId;
  }

  /// Retorna as vendas do cliente a partir de vendasBox.
  /// Usa clienteNome como fonte de verdade (igual à tela Vendas) para evitar
  /// vendas erradas vindas de clienteId incorreto (reconciliação antiga).
  List<Venda> _vendasDoCliente(Cliente cliente) {
    final nomeNorm = normalizeText(cliente.nome);

    final lista = vendasBox.values.where((v) {
      if (v.lojaId != null && v.lojaId!.isNotEmpty && v.lojaId != lojaId) return false;
      return normalizeText(v.clienteNome) == nomeNorm;
    }).toList();

    lista.sort((a, b) => b.data.compareTo(a.data));
    return lista;
  }

  // -------------------------------
  // Histórico do cliente
  // Usa vendasBox como fonte de verdade (evita mistura entre clientes)
  // -------------------------------
  void visualizarHistorico(Cliente cliente) {
    final vendasDoCliente = _vendasDoCliente(cliente);
    final totalGasto = vendasDoCliente.fold<double>(0, (sum, v) => sum + v.total);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
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
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: _getAvatarColor(cliente.nome),
                      child: Text(
                        _getInitials(cliente.nome),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cliente.nome,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${vendasDoCliente.length} compras',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E).withValues(alpha:0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'R\$ ${totalGasto.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Color(0xFF22C55E),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Lista de compras
              Expanded(
                child: vendasDoCliente.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.shopping_bag_outlined,
                              size: 64,
                              color: Colors.grey[300],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Nenhuma compra registrada',
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: vendasDoCliente.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final venda = vendasDoCliente[index];
                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF6366F1)
                                            .withValues(alpha:0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.shopping_bag,
                                        size: 20,
                                        color: Color(0xFF6366F1),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _resumoProdutosVenda(venda),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                            maxLines: 4,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            DateFormat('dd/MM/yyyy • HH:mm')
                                                .format(venda.data),
                                            style: TextStyle(
                                              color: Colors.grey[500],
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Flexible(
                                      child: Text(
                                        'R\$ ${venda.total.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          color: Color(0xFF22C55E),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                if (venda.observacao.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withValues(alpha:0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.notes,
                                          size: 14,
                                          color: Colors.orange,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            venda.observacao,
                                            style: const TextStyle(
                                              color: Colors.orange,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------
  // Importar clientes via Excel
  // -------------------------------
  Future<void> importarExcel() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      if (mounted) setState(() => _importando = true);

      final picked = result.files.first;
      final fileBytes = picked.bytes ??
          (picked.path != null && !kIsWeb
              ? await io.File(picked.path!).readAsBytes()
              : null);
      if (fileBytes == null) {
        if (mounted) setState(() => _importando = false);
        return;
      }
      final excel = Excel.decodeBytes(fileBytes);
      if (excel.tables.isEmpty) {
        if (mounted) {
          setState(() => _importando = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('O arquivo não contém planilhas.')),
          );
        }
        return;
      }
      final Sheet? sheet = excel.tables[excel.tables.keys.first];

      if (sheet == null) {
        if (mounted) setState(() => _importando = false);
        return;
      }

      int importados = 0;
      bool limiteAtingido = false;
      for (int i = 1; i < sheet.maxRows; i++) {
        final row = sheet.row(i);
        final nome = row[0]?.value?.toString() ?? '';
        final telefone = row[1]?.value?.toString() ?? '';
        final instagram = row.length > 2 ? row[2]?.value?.toString() ?? '' : '';
        final cep = row.length > 3 ? row[3]?.value?.toString() ?? '' : '';
        final cidade = row.length > 4 ? row[4]?.value?.toString() ?? '' : '';

        if (nome.isNotEmpty && telefone.isNotEmpty) {
          final limpo = telefone.replaceAll(RegExp(r'\D'), '');
          final e164 = limpo.startsWith('55') ? limpo : '55$limpo';
          if (e164.length < 10) continue;
          final existe = clientesBox.values.any(
            (cli) => cli.telefone == e164 && cli.lojaId == lojaId,
          );
          if (existe) continue;
          final guard = LimitsGuard();
          final pode = await guard.canAddCliente(lojaId!);
          if (!pode) {
            limiteAtingido = true;
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Limite de clientes atingido. Alguns contatos não foram importados.',
                  ),
                  backgroundColor: Colors.orange,
                ),
              );
            }
            break;
          }
          final cliente = Cliente(
            nome: capitalizeWords(nome),
            telefone: e164,
            instagram: instagram,
            cep: cep,
            cidade: cidade,
            lojaId: lojaId!,
          );
          clientesBox.add(cliente);
          ClientesFirestoreService.syncCliente(cliente, lojaId: lojaId!);
          importados++;
        }
      }

      if (mounted) {
        setState(() => _importando = false);
        if (limiteAtingido && importados == 0) {
          // Mensagem de limite já exibida no break
        } else if (limiteAtingido && importados > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '$importados cliente(s) importado(s). Limite do plano atingido; os demais não foram importados.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("$importados clientes importados!")),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _importando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erro ao importar: $e")),
        );
      }
    }
  }

  // -------------------------------
  // Importar contatos do WhatsApp
  // -------------------------------
  Future<void> importarContatosWhatsApp() async {
    if (kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Importação de contatos não disponível na versão Web.")),
      );
      return;
    }
    try {
      final status = await Permission.contacts.request();
      if (!status.isGranted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Permissão para acessar contatos negada.")),
        );
        return;
      }

      final Iterable<Contact> contatos = await ContactsService.getContacts(
        withThumbnails: true,
        photoHighResolution: true,
      );

      final Map<String, String> mapaNomePorTelefone = {};
      for (final c in contatos) {
        final nome = (c.displayName ?? '').trim();
        final phone = c.phones?.firstOrNull?.value ?? '';
        final limpo = phone.replaceAll(RegExp(r'\D'), '');
        if (nome.isEmpty || limpo.length < 10) continue;

        final e164 = limpo.startsWith('55') ? limpo : '55$limpo';
        mapaNomePorTelefone.putIfAbsent(e164, () => nome);
      }

      if (!mounted) return;

      final selecionados = await showModalBottomSheet<Set<String>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (dialogContext) {
          final Set<String> selecionadosTemp = {};
          final lista = mapaNomePorTelefone.entries.toList()
            ..sort((a, b) => a.value.compareTo(b.value));

          return StatefulBuilder(
            builder: (context, setStateSB) => DraggableScrollableSheet(
              initialChildSize: 0.8,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              builder: (context, scrollController) => Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(Icons.contacts, color: Color(0xFF25D366)),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Selecionar Contatos',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6366F1).withValues(alpha:0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${selecionadosTemp.length} selecionados',
                              style: const TextStyle(
                                color: Color(0xFF6366F1),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: lista.length,
                        itemBuilder: (_, i) {
                          final item = lista[i];
                          final tel = item.key;
                          final nome = item.value;
                          final isOn = selecionadosTemp.contains(tel);

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _getAvatarColor(nome),
                              child: Text(
                                _getInitials(nome),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(nome),
                            subtitle: Text(tel),
                            trailing: Checkbox(
                              value: isOn,
                              activeColor: const Color(0xFF6366F1),
                              onChanged: (v) {
                                setStateSB(() {
                                  if (v == true) {
                                    selecionadosTemp.add(tel);
                                  } else {
                                    selecionadosTemp.remove(tel);
                                  }
                                });
                              },
                            ),
                            onTap: () {
                              setStateSB(() {
                                if (isOn) {
                                  selecionadosTemp.remove(tel);
                                } else {
                                  selecionadosTemp.add(tel);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha:0.05),
                            blurRadius: 10,
                            offset: const Offset(0, -5),
                          ),
                        ],
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: selecionadosTemp.isEmpty
                              ? null
                              : () => Navigator.of(dialogContext).pop(selecionadosTemp),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF25D366),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            'Importar ${selecionadosTemp.length} contatos',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );

      if (selecionados == null || selecionados.isEmpty) return;

      if (mounted) setState(() => _importando = true);

      int adicionados = 0;
      for (final tel in selecionados) {
        final existe = clientesBox.values.any(
          (cli) => cli.telefone == tel && cli.lojaId == lojaId,
        );
        if (existe) continue;

        final nome = mapaNomePorTelefone[tel] ?? 'Sem nome';

        final novoCliente = Cliente(
          nome: capitalizeWords(nome),
          telefone: tel,
          instagram: '',
          cep: '',
          cidade: '',
          lojaId: lojaId!,
        );

        clientesBox.add(novoCliente);
        ClientesFirestoreService.syncCliente(novoCliente, lojaId: lojaId!);
        adicionados++;
      }

      if (mounted) {
        setState(() => _importando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$adicionados contatos importados!')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _importando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falha ao importar contatos: $e')),
        );
      }
    }
  }

  // -------------------------------
  // Diálogo de cadastro completo
  // -------------------------------
  Future<void> _abrirCadastroCliente() async {
    _nomeController.clear();
    _telefoneController.clear();
    _instagramController.clear();
    _cepController.clear();
    _cidadeController.clear();
    _emailController.clear();
    _enderecoController.clear();
    _novoAvatarBytes = null;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => _pickAvatarFromGallery(setStateDialog),
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 32,
                            backgroundColor: Colors.grey[200],
                            backgroundImage: (_novoAvatarBytes != null)
                                ? MemoryImage(_novoAvatarBytes!)
                                : null,
                            child: (_novoAvatarBytes == null)
                                ? Icon(Icons.person, size: 32, color: Colors.grey[400])
                                : null,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Color(0xFF6366F1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.camera_alt,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Novo Cliente',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Preencha os dados abaixo',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _buildTextField(
                  controller: _nomeController,
                  label: 'Nome *',
                  icon: Icons.person_outline,
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _telefoneController,
                  label: 'Telefone *',
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _emailController,
                  label: 'E-mail',
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _enderecoController,
                  label: 'Endereço',
                  icon: Icons.location_on_outlined,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _cepController,
                        label: 'CEP',
                        icon: Icons.local_post_office_outlined,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildTextField(
                        controller: _cidadeController,
                        label: 'Cidade',
                        icon: Icons.location_city_outlined,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _instagramController,
                  label: 'Instagram',
                  icon: Icons.alternate_email,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (_nomeController.text.trim().isEmpty ||
                          _telefoneController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Nome e Telefone são obrigatórios'),
                          ),
                        );
                        return;
                      }

                      final navigator = Navigator.of(context);
                      final messenger = ScaffoldMessenger.of(context);

                      final limpo = _telefoneController.text.replaceAll(RegExp(r'\D'), '');
                      final e164 = limpo.startsWith('55') ? limpo : '55$limpo';

                      String? caminhoAvatar;
                      if (_novoAvatarBytes != null && _novoAvatarBytes!.isNotEmpty) {
                        caminhoAvatar = await _salvarAvatarLocal(e164, _novoAvatarBytes!);
                      }

                      final novo = Cliente(
                        nome: capitalizeWords(_nomeController.text.trim()),
                        telefone: e164,
                        instagram: _instagramController.text.trim(),
                        cep: _cepController.text.trim(),
                        cidade: _cidadeController.text.trim(),
                        lojaId: lojaId!,
                      )
                        ..email = _emailController.text.trim().isEmpty
                            ? null
                            : _emailController.text.trim()
                        ..endereco = _enderecoController.text.trim().isEmpty
                            ? null
                            : _enderecoController.text.trim()
                        ..avatarPath = caminhoAvatar;

                      final guard = LimitsGuard();
                      final pode = await guard.canAddCliente(lojaId!);
                      if (!pode) {
                        if (mounted) {
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Limite de clientes atingido no plano Free. Faça upgrade.',
                              ),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        }
                        return;
                      }
                      clientesBox.add(novo);
                      ClientesFirestoreService.syncCliente(novo, lojaId: lojaId!);

                      if (mounted) {
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Cliente cadastrado!')),
                        );
                        navigator.pop();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Cadastrar Cliente',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------
  // Métodos do histórico geral
  // -------------------------------

  Future<void> _selecionarDataInicial() async {
    final data = await showDatePicker(
      context: context,
      initialDate: dataInicial ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (data != null) setState(() => dataInicial = data);
  }

  Future<void> _selecionarDataFinal() async {
    final data = await showDatePicker(
      context: context,
      initialDate: dataFinal ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (data != null) setState(() => dataFinal = data);
  }

  /// Vendas filtradas: fonte vendasBox (consistente com Histórico de Clientes)
  List<Venda> _vendasFiltradas() {
    var di = dataInicial;
    var df = dataFinal;
    if (di != null && df != null && df.isBefore(di)) {
      di = dataFinal;
      df = dataInicial;
    }

    var lista = vendasBox.values.where((v) {
      if (v.lojaId != null && v.lojaId!.isNotEmpty && v.lojaId != lojaId) return false;
      final dentroDoIntervalo =
          (di == null || v.data.isAfter(di.subtract(const Duration(days: 1)))) &&
          (df == null || v.data.isBefore(df.add(const Duration(days: 1))));
      final contemNome = filtroNomeHistorico.isEmpty ||
          v.clienteNome.toLowerCase().contains(filtroNomeHistorico.toLowerCase());
      return dentroDoIntervalo && contemNome;
    }).toList();

    switch (ordenacaoHistorico) {
      case 'data_asc':
        lista.sort((a, b) => a.data.compareTo(b.data));
        break;
      case 'cliente_asc':
        lista.sort((a, b) => a.clienteNome.toLowerCase().compareTo(b.clienteNome.toLowerCase()));
        break;
      case 'cliente_desc':
        lista.sort((a, b) => b.clienteNome.toLowerCase().compareTo(a.clienteNome.toLowerCase()));
        break;
      default:
        lista.sort((a, b) => b.data.compareTo(a.data));
    }
    return lista;
  }

  Future<void> _imprimirPedido(Venda venda) async {
    try {
      final cliente = _clientePorNome(venda.clienteNome);
      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context context) {
            final itensPdf = venda.itensOuVazio;
            final subtotalReal = itensPdf.isNotEmpty
                ? itensPdf.fold<double>(0.0, (s, i) => s + i.precoUnitario * i.quantidade)
                : venda.preco;
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
                    pw.Text('R\$ ${subtotalReal.toStringAsFixed(2)}'),
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
                      pw.Text(
                        '-R\$ ${(subtotalReal * venda.desconto / 100).toStringAsFixed(2)} (${venda.desconto.toStringAsFixed(1)}%)',
                      ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pedido preparado para impressão')),
        );
      }
    } catch (e, st) {
      logE('Erro ao imprimir pedido (type=${e.runtimeType})', error: e, st: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao imprimir pedido: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _confirmarExclusaoVenda(Venda venda) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Excluir venda'),
        content: const Text('A venda será removida. Você pode desfazer em até 30 segundos.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao excluir venda: $e')),
        );
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

  Future<void> _undoCliente(String id) async {
    final ok = await SoftDeleteService.undo(id);
    if (mounted) setState(() {});
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(ok ? 'Cliente restaurado' : 'Não foi possível desfazer'),
        backgroundColor: ok ? null : Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // -------------------------------
  // UI - Aba Clientes
  // -------------------------------

  Widget _buildClientesTab() {
    final stats = _getStats();

    return Column(
      children: [
        // Header com estatísticas
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
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
              // Cards de estatísticas
              Row(
                children: [
                  _buildStatCard(
                    icon: Icons.people,
                    label: 'Clientes',
                    value: stats['total'].toString(),
                    color: const Color(0xFF6366F1),
                  ),
                  const SizedBox(width: 12),
                  _buildStatCard(
                    icon: Icons.shopping_bag,
                    label: 'Vendas',
                    value: stats['vendas'].toString(),
                    color: const Color(0xFF22C55E),
                  ),
                  const SizedBox(width: 12),
                  _buildStatCard(
                    icon: Icons.attach_money,
                    label: 'Total',
                    value: 'R\$ ${(stats['valor'] as double).toStringAsFixed(0)}',
                    color: const Color(0xFFF97316),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Campo de busca
              TextField(
                controller: _filtroController,
                decoration: InputDecoration(
                  hintText: 'Buscar cliente...',
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 12),
              // Ordenação
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: ordenacaoClientes,
                    icon: const Icon(Icons.sort, color: Color(0xFF6366F1), size: 20),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    onChanged: (value) {
                      if (value != null) setState(() => ordenacaoClientes = value);
                    },
                    items: const [
                      DropdownMenuItem(value: 'alfabetica', child: Text('Ordenar: Alfabética (A-Z)')),
                      DropdownMenuItem(value: 'alfabetica_desc', child: Text('Ordenar: Alfabética (Z-A)')),
                      DropdownMenuItem(value: 'data', child: Text('Ordenar: Última compra')),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Botões de importação
              Row(
                children: [
                  Expanded(
                    child: _buildImportButton(
                      icon: Icons.table_chart,
                      label: 'Importar Excel',
                      color: const Color(0xFF22C55E),
                      onPressed: _importando ? null : importarExcel,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildImportButton(
                      icon: FontAwesomeIcons.whatsapp,
                      label: 'WhatsApp',
                      color: const Color(0xFF25D366),
                      onPressed: _importando ? null : importarContatosWhatsApp,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Lista de clientes
        Expanded(
          child: ValueListenableBuilder<Box<Cliente>>(
            valueListenable: clientesBox.listenable(),
            builder: (context, box, _) {
              var clientesFiltrados = box.values
                  .where((cliente) =>
                      cliente.lojaId == lojaId &&
                      cliente.nome.toLowerCase().contains(filtro.toLowerCase()))
                  .toList();

              if (ordenacaoClientes == 'data') {
                clientesFiltrados.sort((a, b) {
                  final vendasA = _vendasDoCliente(a);
                  final vendasB = _vendasDoCliente(b);
                  final dataA = vendasA.isNotEmpty
                      ? vendasA.map((v) => v.data).reduce((a, b) => a.isAfter(b) ? a : b)
                      : DateTime(2000);
                  final dataB = vendasB.isNotEmpty
                      ? vendasB.map((v) => v.data).reduce((a, b) => a.isAfter(b) ? a : b)
                      : DateTime(2000);
                  return dataB.compareTo(dataA);
                });
              } else if (ordenacaoClientes == 'alfabetica_desc') {
                clientesFiltrados.sort((a, b) => b.nome.compareTo(a.nome));
              } else {
                clientesFiltrados.sort((a, b) => a.nome.compareTo(b.nome));
              }

              if (clientesFiltrados.isEmpty) {
                return RefreshIndicator(
                  onRefresh: _init,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      EmptyStateCta(
                        icon: Icons.people_outline,
                        title: filtro.isEmpty
                            ? 'Nenhum cliente cadastrado'
                            : 'Nenhum cliente encontrado',
                        subtitle: filtro.isEmpty
                            ? 'Adicione seu primeiro cliente'
                            : 'Tente ajustar o filtro de busca',
                        buttonLabel: filtro.isEmpty ? 'Adicionar cliente' : 'Limpar busca',
                        onPressed: filtro.isEmpty
                            ? _abrirCadastroCliente
                            : () => setState(() => _filtroController.clear()),
                        accentColor: const Color(0xFF6366F1),
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: _init,
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: clientesFiltrados.length,
                  itemBuilder: (context, index) {
                    final cliente = clientesFiltrados[index];
                    return _buildClienteCard(cliente);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha:0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: color.withValues(alpha:0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImportButton({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: _importando
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          : Icon(icon, size: 18),
      label: Text(_importando ? 'Importando...' : label),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  Widget _buildClienteCard(Cliente cliente) {
    final hasAvatar = !kIsWeb && cliente.avatarPath != null && io.File(cliente.avatarPath!).existsSync();
    final compras = _vendasDoCliente(cliente).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => visualizarHistorico(cliente),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Avatar
                hasAvatar
                    ? CircleAvatar(
                        radius: 26,
                        backgroundImage: FileImage(io.File(cliente.avatarPath!)),
                      )
                    : CircleAvatar(
                        radius: 26,
                        backgroundColor: _getAvatarColor(cliente.nome),
                        child: Text(
                          _getInitials(cliente.nome),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                const SizedBox(width: 14),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cliente.nome,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.phone, size: 14, color: Colors.grey[400]),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              cliente.telefone,
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (compras > 0) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1).withValues(alpha:0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$compras ${compras == 1 ? 'compra' : 'compras'}',
                            style: const TextStyle(
                              color: Color(0xFF6366F1),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Actions
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () async {
                        final numero = cliente.telefone.replaceAll(RegExp(r'\D'), '');
                        if (numero.length < 10) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Número inválido')),
                          );
                          return;
                        }
                        try {
                          await launchUrl(
                            Uri.parse('https://wa.me/$numero'),
                            mode: LaunchMode.externalApplication,
                          );
                        } catch (_) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Não foi possível abrir o WhatsApp.')),
                            );
                          }
                        }
                      },
                      icon: const FaIcon(
                        FontAwesomeIcons.whatsapp,
                        color: Color(0xFF25D366),
                        size: 22,
                      ),
                      tooltip: 'WhatsApp',
                    ),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert, color: Colors.grey[400]),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      onSelected: (value) async {
                        if (value == 'editar') {
                          editarCliente(cliente);
                        } else if (value == 'excluir') {
                          final confirmar = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              title: const Text('Excluir cliente'),
                              content: Text(
                                'Deseja excluir "${cliente.nome}"?\nVocê pode desfazer em até 30 segundos.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: const Text('Cancelar'),
                                ),
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                  ),
                                  child: const Text('Excluir'),
                                ),
                              ],
                            ),
                          );
                          if (confirmar == true) {
                            try {
                              final id = await SoftDeleteService.scheduleClienteDelete(
                                cliente: cliente,
                                clientesBox: clientesBox,
                                lojaId: lojaId!,
                              );
                              if (mounted) {
                                setState(() {});
                                scaffoldMessengerKey.currentState?.showSnackBar(
                                  SnackBar(
                                    content: const Text('Cliente excluído. Desfazer?'),
                                    duration: const Duration(seconds: 30),
                                    action: id != null
                                        ? SnackBarAction(
                                            label: 'Desfazer',
                                            onPressed: () {
                                              scaffoldMessengerKey.currentState?.hideCurrentSnackBar();
                                              _undoCliente(id);
                                            },
                                          )
                                        : null,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Erro ao excluir: $e')),
                                );
                              }
                            }
                          }
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'editar',
                          child: Row(
                            children: [
                              Icon(Icons.edit_outlined, size: 20),
                              SizedBox(width: 10),
                              Text('Editar'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'excluir',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline, size: 20, color: Colors.red),
                              SizedBox(width: 10),
                              Text('Excluir', style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                      ],
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

  // -------------------------------
  // UI - Aba Histórico
  // -------------------------------

  Widget _buildHistoricoTab() {
    final vendas = _vendasFiltradas();
    final totalVendas = vendas.fold<double>(0, (sum, v) => sum + v.total);

    return Column(
      children: [
        // Filtros
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
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
              TextField(
                decoration: InputDecoration(
                  hintText: 'Buscar por cliente...',
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onChanged: (value) => setState(() => filtroNomeHistorico = value.trim()),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildDateButton(
                      label: dataInicial == null
                          ? 'Data inicial'
                          : DateFormat('dd/MM/yy').format(dataInicial!),
                      onPressed: _selecionarDataInicial,
                      hasValue: dataInicial != null,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.arrow_forward, size: 16, color: Colors.grey[400]),
                  ),
                  Expanded(
                    child: _buildDateButton(
                      label: dataFinal == null
                          ? 'Data final'
                          : DateFormat('dd/MM/yy').format(dataFinal!),
                      onPressed: _selecionarDataFinal,
                      hasValue: dataFinal != null,
                    ),
                  ),
                  if (dataInicial != null || dataFinal != null)
                    IconButton(
                      onPressed: () => setState(() {
                        dataInicial = null;
                        dataFinal = null;
                      }),
                      icon: const Icon(Icons.clear, size: 20),
                      tooltip: 'Limpar filtros',
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: ordenacaoHistorico,
                    icon: const Icon(Icons.sort, color: Color(0xFF6366F1), size: 20),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    onChanged: (value) {
                      if (value != null) setState(() => ordenacaoHistorico = value);
                    },
                    items: const [
                      DropdownMenuItem(value: 'data_desc', child: Text('Ordenar: Data (mais recente)')),
                      DropdownMenuItem(value: 'data_asc', child: Text('Ordenar: Data (mais antiga)')),
                      DropdownMenuItem(value: 'cliente_asc', child: Text('Ordenar: Cliente (A-Z)')),
                      DropdownMenuItem(value: 'cliente_desc', child: Text('Ordenar: Cliente (Z-A)')),
                    ],
                  ),
                ),
              ),
              if (vendas.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E).withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${vendas.length} vendas encontradas',
                        style: const TextStyle(
                          color: Color(0xFF22C55E),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        'R\$ ${totalVendas.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Color(0xFF22C55E),
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        // Lista
        Expanded(
          child: RefreshIndicator(
            onRefresh: _init,
            child: vendas.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      _ClientesHistoricoEmptyBody(),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: vendas.length,
                    itemBuilder: (context, index) {
                      final venda = vendas[index];
                      return _buildVendaCard(venda);
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildDateButton({
    required String label,
    required VoidCallback onPressed,
    required bool hasValue,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(
        Icons.calendar_today,
        size: 16,
        color: hasValue ? const Color(0xFF6366F1) : Colors.grey,
      ),
      label: Text(
        label,
        style: TextStyle(
          color: hasValue ? const Color(0xFF6366F1) : Colors.grey[600],
        ),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12),
        side: BorderSide(
          color: hasValue ? const Color(0xFF6366F1) : Colors.grey.shade300,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  Widget _buildVendaCard(Venda venda) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: _getAvatarColor(venda.clienteNome),
                  child: Text(
                    _getInitials(venda.clienteNome),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        venda.clienteNome,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        DateFormat('dd/MM/yyyy • HH:mm').format(venda.data),
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'R\$ ${venda.total.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Color(0xFF22C55E),
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        venda.formasPagamentoDiscriminado,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.shopping_bag_outlined, size: 16, color: Colors.grey[500]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _resumoProdutosVenda(venda),
                      style: TextStyle(color: Colors.grey[700], fontSize: 13),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            if (venda.observacao.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.notes, size: 14, color: Colors.orange),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        venda.observacao,
                        style: const TextStyle(color: Colors.orange, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () {
                    final c = _clientePorNome(venda.clienteNome);
                    if (c != null) {
                      visualizarHistorico(c);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Cliente "${venda.clienteNome}" não encontrado')),
                      );
                    }
                  },
                  icon: const Icon(Icons.history, size: 18, color: Color(0xFF6366F1)),
                  label: const Text('Ver histórico', style: TextStyle(color: Color(0xFF6366F1))),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _imprimirPedido(venda),
                  icon: const Icon(Icons.print, size: 18, color: Color(0xFF6366F1)),
                  label: const Text('Imprimir', style: TextStyle(color: Color(0xFF6366F1))),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _confirmarExclusaoVenda(venda),
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                  label: const Text('Excluir', style: TextStyle(color: Colors.red)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _montarResumoClientesParaIa() {
    final clientes = clientesBox.values.where((c) => c.lojaId == lojaId).toList();
    final vendasDaLoja = vendasBox.values.where((v) => v.lojaId == null || v.lojaId!.isEmpty || v.lojaId == lojaId).toList();
    final porCliente = <String, double>{};
    for (final v in vendasDaLoja) {
      final nome = v.clienteNome.trim().isEmpty ? 'Sem nome' : v.clienteNome;
      porCliente[nome] = (porCliente[nome] ?? 0) + v.total;
    }
    final topClientes = porCliente.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final fmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$', decimalDigits: 2);
    final sb = StringBuffer();
    sb.writeln('Total de clientes: ${clientes.length}. Total de vendas: ${vendasDaLoja.length}.');
    sb.writeln('Top 10 clientes por faturamento: ${topClientes.take(10).map((e) => '${e.key} ${fmt.format(e.value)}').join('; ')}.');
    return sb.toString();
  }

  void _abrirSugestoesIaClientes() {
    final resumo = _montarResumoClientesParaIa();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => _SugestoesIaClientesScreen(
          resumoInicial: resumo,
          lojaId: lojaId!,
        ),
      ),
    );
  }

  // -------------------------------
  // Build Principal
  // -------------------------------

  @override
  Widget build(BuildContext context) {
    if (_erroHiveCacheLocal) {
      return Scaffold(
        appBar: AppBar(title: const Text('Clientes')),
        body: _ClientesHiveCacheErroLojaBody(
          detalhe: _erroHiveCacheDetalhe ?? 'clientes/vendas',
          onRetry: () {
            if (kDebugMode) logD('[STORE-LIFECYCLE] Clientes: retry Hive cache');
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
        appBar: AppBar(title: const Text('Clientes')),
        body: _ClientesErroLojaBody(
          onRetry: () {
            if (kDebugMode) logD('[STORE-LIFECYCLE] Clientes: clique em Tentar novamente');
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
        body: _ClientesLoadingBody(),
      );
    }

    final vendas = _vendasFiltradas();

    final operacaoEmAndamento = _importando || _exportando || _reparando || _sincronizando;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Clientes'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha:0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _enviandoClientes
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.green),
                    )
                  : const Icon(Icons.cloud_upload, color: Colors.green, size: 20),
            ),
            tooltip: 'Enviar para Nuvem',
            onPressed: _enviandoClientes ? null : _enviarClientesParaNuvem,
          ),
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6).withValues(alpha:0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _sincronizando
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_download, color: Color(0xFF3B82F6), size: 20),
            ),
            tooltip: _temDadosParaImportar == true
                ? 'Baixar da Nuvem (há clientes novos)'
                : 'Baixar da Nuvem',
            onPressed: _sincronizando ? null : _baixarClientesDaNuvem,
          ),
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha:0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.auto_awesome, color: Colors.amber, size: 20),
            ),
            tooltip: 'Sugestões com IA (retenção, indicação)',
            onPressed: _abrirSugestoesIaClientes,
          ),
          IconButton(
            icon: _reparando
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.build_circle_outlined),
            tooltip: 'Reparar histórico de compras',
            onPressed: _reparando
                ? null
                : () async {
                    setState(() => _reparando = true);
                    try {
                      final r = await RepairHistoricoClientesService.reparar(
                        clientesBox: clientesBox,
                        vendasBox: vendasBox,
                        lojaId: lojaId!,
                      );
                      if (!mounted) return;
                      setState(() {});
                      final msg =
                          'Histórico reparado! ${r[RepairHistoricoClientesService.keyVendasAtribuidas]} vendas corrigidas.';
                      scaffoldMessengerKey.currentState?.showSnackBar(
                        SnackBar(
                          content: Text(msg),
                          backgroundColor: Colors.green,
                        ),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      scaffoldMessengerKey.currentState?.showSnackBar(
                        SnackBar(
                          content: Text('Erro ao reparar: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    } finally {
                      if (mounted) setState(() => _reparando = false);
                    }
                  },
          ),
          if (_tabController.index == 1 && vendas.isNotEmpty)
            IconButton(
              icon: _exportando
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download),
              tooltip: 'Exportar para Excel',
              onPressed: _exportando
                  ? null
                  : () async {
                      setState(() => _exportando = true);
                      try {
                        await exportarParaExcelComDialog(context, vendas);
                      } finally {
                        if (mounted) setState(() => _exportando = false);
                      }
                    },
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Mais opções',
            onSelected: (value) {
              if (value == 'redefinir_senha_catalogo') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const RedefinirSenhaClienteLojaScreen(),
                  ),
                );
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'redefinir_senha_catalogo',
                child: Row(
                  children: [
                    Icon(Icons.lock_reset, size: 22),
                    SizedBox(width: 12),
                    Text('Redefinir senha do cliente (catálogo)'),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(operacaoEmAndamento ? 52 : 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (operacaoEmAndamento)
                const LinearProgressIndicator(),
              Container(
                color: Colors.white,
                child: TabBar(
              controller: _tabController,
              indicatorColor: const Color(0xFF6366F1),
              indicatorWeight: 3,
              labelColor: const Color(0xFF6366F1),
              unselectedLabelColor: Colors.grey,
              tabs: const [
                Tab(text: 'Clientes'),
                Tab(text: 'Histórico'),
              ],
            ),
          ),
            ],
          ),
        ),
      ),
      body: Stack(
        children: [
          // FASE 3: Aviso quando sync falhou (lista local permanece visível)
          if (_syncFalhou)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _ClientesSyncFalhouBanner(
                onRetry: () {
                  setState(() => _syncFalhou = false);
                  _syncClientesEmBackground();
                },
              ),
            ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildClientesTab(),
                  _buildHistoricoTab(),
                ],
              ),
            ),
          ),
          if (_importando || _exportando || _reparando || _sincronizando)
            Container(
              color: Colors.black.withValues(alpha:0.3),
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          _reparando
                              ? 'Reparando histórico...'
                              : _sincronizando
                                  ? 'Sincronizando...'
                                  : (_exportando ? 'Exportando...' : 'Importando...'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'fab_ia_clientes',
            onPressed: _abrirSugestoesIaClientes,
            tooltip: 'Sugestões com IA (retenção, indicação)',
            backgroundColor: Colors.amber,
            mini: true,
            child: const Icon(Icons.auto_awesome, color: Colors.black87),
          ),
          if (_tabController.index == 0) ...[
            const SizedBox(height: 12),
            FloatingActionButton.extended(
              heroTag: 'fab_novo_cliente',
              onPressed: _abrirCadastroCliente,
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Novo Cliente'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Widget apenas visual: estado de carregamento da tela de clientes.
class _ClientesLoadingBody extends StatelessWidget {
  const _ClientesLoadingBody();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha:0.08),
              shape: BoxShape.circle,
            ),
            child: const CircularProgressIndicator(),
          ),
          const SizedBox(height: 24),
          const Text(
            'Carregando clientes da loja...',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Aguarde alguns segundos.\nEstamos resolvendo a loja e sincronizando seus dados.',
            style: TextStyle(fontSize: 13, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Widget apenas visual: estado de erro de resolução da loja (com botão de retry).
class _ClientesHiveCacheErroLojaBody extends StatelessWidget {
  final String detalhe;
  final VoidCallback onRetry;

  const _ClientesHiveCacheErroLojaBody({
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
            Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
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

class _ClientesErroLojaBody extends StatelessWidget {
  final VoidCallback onRetry;

  const _ClientesErroLojaBody({required this.onRetry});

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
              style: (Theme.of(context).textTheme.bodyMedium ?? Theme.of(context).textTheme.bodyLarge)?.copyWith(color: Colors.grey[600]) ?? const TextStyle(fontSize: 14, color: Colors.grey),
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
class _ClientesSyncFalhouBanner extends StatelessWidget {
  final VoidCallback onRetry;

  const _ClientesSyncFalhouBanner({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.orange.shade100,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.cloud_off, color: Colors.orange.shade800, size: 22),
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

/// Widget apenas visual: empty state da aba Histórico (sem botão, sem callback).
class _ClientesHistoricoEmptyBody extends StatelessWidget {
  const _ClientesHistoricoEmptyBody();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.2),
        Icon(Icons.receipt_long_outlined, size: 80, color: Colors.grey[300]),
        const SizedBox(height: 16),
        Text(
          'Nenhuma venda encontrada',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            color: Colors.grey[500],
          ),
        ),
        Text(
          'Tente ajustar os filtros',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[400]),
        ),
      ],
    );
  }
}

/// Tela cheia de sugestões com IA – Clientes.
class _SugestoesIaClientesScreen extends StatefulWidget {
  final String resumoInicial;
  final String lojaId;

  const _SugestoesIaClientesScreen({
    required this.resumoInicial,
    required this.lojaId,
  });

  @override
  State<_SugestoesIaClientesScreen> createState() => _SugestoesIaClientesScreenState();
}

class _SugestoesIaClientesScreenState extends State<_SugestoesIaClientesScreen> {
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
    final lojaId = widget.lojaId;
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
        title: const Text('IA – Clientes', style: TextStyle(color: Colors.white)),
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
              'Sugestões de retenção, indicação e segmentação. Dados de clientes já enviados.',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _enviando ? null : () => _enviar('Sugestões para reter clientes e reduzir abandono.'),
                  icon: const Icon(Icons.loyalty, size: 18),
                  label: const Text('Retenção'),
                  style: FilledButton.styleFrom(backgroundColor: _primaryColor.withValues(alpha:0.15)),
                ),
                FilledButton.tonalIcon(
                  onPressed: _enviando ? null : () => _enviar('Sugestões para programa de indicação (trazer amigos).'),
                  icon: const Icon(Icons.group_add, size: 18),
                  label: const Text('Indicação'),
                  style: FilledButton.styleFrom(backgroundColor: _primaryColor.withValues(alpha:0.15)),
                ),
                FilledButton.tonalIcon(
                  onPressed: _enviando ? null : () => _enviar('Como segmentar clientes para campanhas? Sugestões.'),
                  icon: const Icon(Icons.pie_chart_outline, size: 18),
                  label: const Text('Segmentação'),
                  style: FilledButton.styleFrom(backgroundColor: _primaryColor.withValues(alpha:0.15)),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _perguntaCtrl,
              decoration: InputDecoration(
                hintText: 'Ex: Como fidelizar os top 10 clientes?',
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

