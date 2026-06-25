// lib/screens/estoque_screen.dart
// Tela completa de estoque com TODAS as funcionalidades:
// - Importação (XLSX, CSV, PDF)
// - Sync com Firestore
// - Seleção múltipla e ações em lote
// - Publicação no catálogo (draft e live)
// - Integração com marketplaces
// - Estatísticas completas

import 'dart:io' as io if (dart.library.html) 'package:master_palm/utils/io_stub.dart';
import 'dart:typed_data';
import 'dart:async';
import 'dart:convert' show latin1, utf8;

import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as xls;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';

import '../core/combo_config_canonical.dart';
import '../core/hive_box_names.dart';
import '../core/logger.dart';
import '../core/produto_custo_guard.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:read_pdf_text/read_pdf_text.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_storage/firebase_storage.dart';

import '../models/produto.dart';
import '../services/permissao_service.dart';
import '../models/venda.dart';
import '../services/produto_import_service.dart';
import '../services/catalogo_sync_service.dart';
import '../services/produtos_firestore_service.dart';
import '../services/sync_queue_service.dart';
import 'produto_form_screen.dart';
import 'compras/compra_pipeline_pendentes_estoque_screen.dart';
import 'compras/compras_revenda_pendentes_screen.dart';
import '../services/compra_fornecedor_hive_store.dart';
import '../services/compra_revenda_detalhamento_service.dart';
import 'produto_combo_form_screen.dart';
import 'dicas_ia_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/loja_id_service.dart';
import '../utils/text_utils.dart';
import '../utils/moeda_input_formatter.dart';
import 'barcode_scanner_screen.dart';
import 'nova_venda/variacao_selection_sheet.dart';
import 'public_catalog_screen.dart';
import '../services/catalog_publish_service.dart';
import '../services/marketplace_service.dart';
import '../services/movimentacao_estoque_service.dart';
import '../services/estoque_service.dart';
import '../src/file_saver.dart' as file_saver;
import 'historico_movimentacao_estoque_screen.dart';
import '../services/ai_loja_service.dart';
import '../services/ia_uso_limite_service.dart';
import '../services/produto_exclusao_remota_service.dart';
import '../widgets/app_help_icon_button.dart';

const bool kAutoSyncOnStart = false;

class EstoqueScreen extends StatefulWidget {
  const EstoqueScreen({super.key});

  @override
  State<EstoqueScreen> createState() => _EstoqueScreenState();
}

class _EstoqueScreenState extends State<EstoqueScreen> {
  // Cores do tema moderno
  static const Color _primaryColor = Color(0xFF6366F1);
  static const Color _successColor = Color(0xFF22C55E);
  static const Color _warningColor = Color(0xFFF59E0B);
  static const Color _errorColor = Color(0xFFEF4444);
  static const Color _cardColor = Color(0xFFFFFFFF);
  static const Color _backgroundColor = Color(0xFFF8FAFC);
  static const Color _surfaceColor = Color(0xFF1E293B);

  final _pesquisaController = TextEditingController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late Box<Produto> _box;

  final ValueNotifier<String> _searchTextNotifier = ValueNotifier('');
  String _debouncedSearchQuery = '';
  Timer? _searchDebounce;

  bool _ready = false;
  String? _lojaId;
  bool _erroResolucaoLoja = false;
  bool _syncEmBackground = false;
  bool _temPermissao = true;
  bool _importando = false;
  int _importProgress = 0;
  int _importTotal = 0;
  int _importCriados = 0;
  int _importAtualizados = 0;
  int _importErros = 0;
  bool _publicando = false;
  bool _unificando = false;
  bool _excluindoOrfaos = false;
  bool _sincronizandoEstoque = false;
  bool _exportandoEstoque = false;
  bool _sincronizandoMarketplace = false;
  String? _marketplaceEmSync;
  bool? _temDadosParaImportar;
  bool _modoSelecao = false;
  bool _sugerindoPromocaoIa = false;
  bool _catalogoPrecisaAtualizar = false;
  int _comprasRevendaPendentesCount = 0;

  /// Ordenação: nome_asc | nome_desc | preco_asc | preco_desc | qtd_asc | qtd_desc
  String _ordenacao = 'nome_asc';

  /// Filtros: categoria, subcategoria, publicado (null = todos), sem fotos, recentemente alterados
  String? _filtroCategoria;
  String? _filtroSubcategoria;
  bool? _filtroPublicado; // null = todos, true = só publicados, false = só não publicados
  bool _filtroSemFotos = false; // true = só produtos sem imagens
  bool _filtroRecentementeAlterados = false; // true = só produtos alterados nas últimas 24 horas

  final Set<String> _produtosSelecionados = {};

  @override
  void initState() {
    super.initState();
    _pesquisaController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _setup();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _pesquisaController.removeListener(_onSearchChanged);
    _pesquisaController.dispose();
    _searchTextNotifier.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchTextNotifier.value = _pesquisaController.text;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      setState(() {
        _debouncedSearchQuery = _norm(_pesquisaController.text);
      });
    });
  }

  Future<void> _setup() async {
    try {
      if (kIsWeb) {
        logD(
          '[WEB_NAV] Estoque._setup inicio (referência) uri=${Uri.base}',
        );
      }
      // Alinhado a Vendas/Clientes/Financeiro: timeout + fallback sessão/Hive
      String? lojaId = await LojaIdService.getWithTimeoutThenSessionFallback(
          timeout: kIsWeb ? const Duration(seconds: 25) : const Duration(seconds: 10));
      if (lojaId == null || lojaId.trim().isEmpty) {
        if (kIsWeb && FirebaseAuth.instance.currentUser == null) {
          try {
            await FirebaseAuth.instance.authStateChanges()
                .where((u) => u != null && !u.isAnonymous)
                .first
                .timeout(const Duration(seconds: 3), onTimeout: () => null);
            if (!mounted) return;
            lojaId = await LojaIdService.getWithTimeoutThenSessionFallback(
                timeout: const Duration(seconds: 12));
          } catch (_) {}
        }
        if (lojaId == null || lojaId.trim().isEmpty) {
          throw StateError('Nenhuma loja ativa');
        }
      }
      final boxName = HiveBoxNames.produtos(lojaId);

      if (!Hive.isBoxOpen(boxName)) {
        await Hive.openBox<Produto>(boxName);
      }

      _box = Hive.box<Produto>(boxName);

      await _verificarPermissao();

      var revendaPendentes = 0;
      try {
        final compraBox = await CompraFornecedorHiveStore.openBox(lojaId);
        if (compraBox != null) {
          revendaPendentes = CompraRevendaDetalhamentoService.contarPendentesDetalhamento(
            compraBox,
            lojaId,
          );
        }
      } catch (_) {}

      // Mostrar tela imediatamente com dados locais (Hive)
      if (mounted) {
        final catalogoPendente = await CatalogPublishService.catalogoPrecisaAtualizar;
        setState(() {
          _ready = true;
          _lojaId = lojaId;
          _catalogoPrecisaAtualizar = catalogoPendente;
          _comprasRevendaPendentesCount = revendaPendentes;
        });
      }

      // Sync em background (não bloqueia a abertura da tela)
      _syncEstoqueEmBackground(lojaId);
    } catch (e, st) {
      logE("Erro no setup Estoque (type=${e.runtimeType})", error: e, st: st);
      if (mounted) setState(() => _erroResolucaoLoja = true);
      _showSnackBar("Erro ao iniciar Estoque: $e", isError: true);
    }
  }

  /// Envia produtos locais para o Firestore (atualiza a nuvem).
  Future<void> _enviarParaFirestore() async {
    setState(() => _sincronizandoEstoque = true);
    try {
      final lojaId = await LojaIdService.getWithTimeoutThenSessionFallback(
        timeout: kIsWeb ? const Duration(seconds: 25) : const Duration(seconds: 10));
      if (lojaId == null) {
        _showSnackBar('Nenhuma loja ativa', isError: true);
        return;
      }
      final boxName = _box.name;
      await SyncQueueService.processPending();
      await ProdutosFirestoreService.syncTodosProdutos(boxName: boxName, lojaId: lojaId);
      // Não chamar limparProdutosExcedentesNoFirestore aqui: box incompleta apagaria docs válidos na nuvem.
      // Prune remoto só com opt-in explícito no futuro (ex. confirmação forte no UI).
      if (!mounted) return;
      _showSnackBar('Envio concluído com sucesso');
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Erro ao enviar: $e', isError: true);
    } finally {
      if (mounted) setState(() => _sincronizandoEstoque = false);
    }
  }

  Future<void> _verificarSeTemDadosParaImportar(String lojaId) async {
    try {
      final tem = await ProdutosFirestoreService.hasDataToImport(
        lojaId: lojaId,
        localCount: _box.length,
      );
      if (mounted) setState(() => _temDadosParaImportar = tem);
    } catch (e, st) {
      logE('[ESTOQUE] Erro ao verificar dados para importar', error: e, st: st);
      if (mounted) setState(() => _temDadosParaImportar = false);
    }
  }

  /// Puxa produtos do Firestore para o celular (atualiza o dispositivo).
  /// Não envia o estoque inteiro antes do pull: isso sobrescrevia a nuvem com valores
  /// antigos do Hive e impedia refletir alterações feitas na web.
  Future<void> _puxarDoFirestore() async {
    setState(() => _sincronizandoEstoque = true);
    try {
      final lojaId = await LojaIdService.getWithTimeoutThenSessionFallback(
        timeout: kIsWeb ? const Duration(seconds: 25) : const Duration(seconds: 10));
      if (lojaId == null) {
        _showSnackBar('Nenhuma loja ativa', isError: true);
        return;
      }
      await SyncQueueService.processPending();
      final stillPending =
          await SyncQueueService.hasPendingProdutoSyncForStore(
        lojaId: lojaId,
        includeDeadLetter: true,
      );
      if (stillPending) {
        _showSnackBar(
          'Sincronização local pendente. Primeiro o app confirma suas edições/exclusões; depois importe da nuvem.',
          isError: true,
        );
        return;
      }
      final n = await ProdutosFirestoreService.syncFirestoreToHive(
        lojaId: lojaId,
        produtosBox: _box,
        preferRemoteQuantity: true,
      );
      if (!mounted) return;
      await _verificarSeTemDadosParaImportar(lojaId);
      if (!mounted) return;
      _showSnackBar(n > 0
          ? 'Baixados $n produto(s) da nuvem'
          : 'Nenhum produto novo encontrado');
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Erro ao puxar: $e', isError: true);
    } finally {
      if (mounted) setState(() => _sincronizandoEstoque = false);
    }
  }

  /// Remove foto da logo (URL que aparece em muitos produtos ou mesma filename) de todos os produtos.
  Future<void> _removerFotoLogoDosProdutos() async {
    final lojaId = await LojaIdService.getWithTimeoutThenSessionFallback(
        timeout: kIsWeb ? const Duration(seconds: 25) : const Duration(seconds: 10));
    if (lojaId == null) return;
    final produtos = _box.values.where((p) => p.lojaId == lojaId).toList();
    if (produtos.isEmpty) {
      _showSnackBar('Nenhum produto para processar');
      return;
    }
    // 1) Contar quantas vezes cada URL exata aparece
    final contagemUrl = <String, int>{};
    for (final p in produtos) {
      for (final url in p.imagens) {
        final u = url.trim();
        if (u.isNotEmpty) contagemUrl[u] = (contagemUrl[u] ?? 0) + 1;
      }
    }
    final threshold = (produtos.length * 0.3).floor();
    if (threshold < 1) {
      _showSnackBar('Poucos produtos para detectar fotos repetidas');
      return;
    }
    // URLs exatas que aparecem em muitos produtos
    final urlsParaRemover = contagemUrl.entries
        .where((e) => e.value >= threshold)
        .map((e) => e.key)
        .toList();

    // 2) Se não encontrou por URL exata, tentar por NOME do arquivo (mesmo visual, URLs diferentes)
    List<String> urlsParaRemoverPorFilename = [];
    if (urlsParaRemover.isEmpty) {
      final contagemFilename = <String, int>{};
      for (final p in produtos) {
        final seen = <String>{};
        for (final url in p.imagens) {
          final u = url.trim();
          if (u.isEmpty) continue;
          final filename = _extrairFilename(u);
          if (filename.isNotEmpty && !seen.contains(filename)) {
            seen.add(filename);
            contagemFilename[filename] = (contagemFilename[filename] ?? 0) + 1;
          }
        }
      }
      final filenamesRepetidos = contagemFilename.entries
          .where((e) => e.value >= threshold)
          .map((e) => e.key)
          .toList();
      if (filenamesRepetidos.isNotEmpty) {
        final setFilenames = filenamesRepetidos.toSet();
        for (final p in produtos) {
          for (final url in p.imagens) {
            final fn = _extrairFilename(url.trim());
            if (fn.isNotEmpty && setFilenames.contains(fn)) {
              urlsParaRemoverPorFilename.add(url.trim());
              break;
            }
          }
        }
        urlsParaRemover.addAll(urlsParaRemoverPorFilename);
      }
    }

    // 3) Se ainda nada, oferecer remover primeira foto de todos (logo costuma ser a primeira)
    if (urlsParaRemover.isEmpty) {
      final comPrimeira = produtos.where((p) => p.imagens.isNotEmpty).toList();
      if (comPrimeira.isEmpty) {
        _showSnackBar('Nenhuma foto repetida encontrada');
        return;
      }
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Remover primeira foto?'),
          content: Text(
            'Não encontramos URLs duplicadas exatas. A logo da loja costuma estar como primeira foto.\n\n'
            'Deseja remover a primeira foto de todos os ${comPrimeira.length} produtos que têm imagem?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remover')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      int removidos = 0;
      for (final p in produtos) {
        if (p.imagens.isNotEmpty) {
          p.imagens.removeAt(0);
          try {
            await p.save();
            removidos++;
          } catch (e, st) {
            logE('[ESTOQUE] Erro ao salvar produto ao remover primeira foto', error: e, st: st);
          }
        }
      }
      if (!mounted) return;
      _showSnackBar('Primeira foto removida de $removidos produto(s). Salve e envie para a nuvem.');
      setState(() {});
      return;
    }

    final qtdProdutosAfetados = produtos.where((p) => p.imagens.any((u) => urlsParaRemover.contains(u.trim()))).length;
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover fotos repetidas?'),
        content: Text(
          urlsParaRemover.length <= 5
              ? 'Encontrada(s) ${urlsParaRemover.length} foto(s) que aparecem em vários produtos '
                  '(provável logo da loja). Remover de todos os produtos?'
              : 'Encontrada foto repetida (mesmo arquivo) em $qtdProdutosAfetados produtos '
                  '(provável logo da loja). Remover de todos?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remover')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    int removidos = 0;
    for (final p in produtos) {
      final antes = p.imagens.length;
      p.imagens.removeWhere((url) => urlsParaRemover.contains(url.trim()));
      if (p.imagens.length < antes) {
        try {
          await p.save();
          removidos++;
        } catch (e, st) {
          logE('[ESTOQUE] Erro ao salvar produto ao remover foto logo', error: e, st: st);
        }
      }
    }
    if (!mounted) return;
    _showSnackBar('Foto da logo removida de $removidos produto(s). Salve e envie para a nuvem.');
    setState(() {});
  }

  Future<void> _syncEstoqueEmBackground(String lojaId) async {
    if (mounted) setState(() => _syncEmBackground = true);
    try {
      await SyncQueueService.processPending();
    } catch (_) {}

    try {
      final stillPending =
          await SyncQueueService.hasPendingProdutoSyncForStore(
        lojaId: lojaId,
        includeDeadLetter: true,
      );
      if (stillPending) {
        logW(
          '[ESTOQUE] Pull em background adiado: há sync local de produto pendente/dead-letter (loja=$lojaId)',
        );
      } else {
      // Só pull na abertura: não enviar Hive inteiro antes (evita nuvem ser sobrescrita por base local velha/incompleta).
      await ProdutosFirestoreService.syncFirestoreToHive(
        lojaId: lojaId,
        produtosBox: _box,
        preferRemoteQuantity: true,
      );
      logD('Produtos sincronizados do Firestore');
      }
    } catch (e, st) {
      logE('[ESTOQUE] Erro ao sincronizar produtos do Firestore em background (type=${e.runtimeType})', error: e, st: st);
    }

    if (kAutoSyncOnStart && mounted) {
      _sincronizarComDraft(auto: true);
    }

    _verificarSeTemDadosParaImportar(lojaId);

    if (mounted) {
      setState(() => _syncEmBackground = false);
      final baixos = _box.values.where((p) => p.quantidade > 0 && p.quantidade < 3).toList();
      if (baixos.isNotEmpty) {
        _showSnackBar(
          '${baixos.length} produto(s) com estoque baixo (< 3 unidades)',
          isError: false,
        );
      }
    }
  }

  Future<void> _verificarPermissao() async {
    final permitido = await PermissaoService.possuiPermissao('estoque');
    if (!mounted) return;
    setState(() => _temPermissao = permitido);
  }

  String _norm(String? s) => normalizeText(s ?? '');

  /// Extrai o nome do arquivo de uma URL ou caminho local.
  String _extrairFilename(String url) {
    if (url.isEmpty) return '';
    try {
      if (url.startsWith('http://') || url.startsWith('https://')) {
        final uri = Uri.tryParse(url);
        if (uri != null) {
          final path = Uri.decodeComponent(uri.path);
          final segments = path.split('/');
          if (segments.isNotEmpty && segments.last.isNotEmpty) return segments.last;
        }
      }
      // Caminho local (file:// ou path absoluto)
      final parts = url.replaceAll('\\', '/').split('/');
      if (parts.isNotEmpty && parts.last.isNotEmpty) return parts.last;
    } catch (_) {}
    return '';
  }

  // ========== SELEÇÃO MÚLTIPLA (NOVO) ==========

  void _toggleModoSelecao() {
    setState(() {
      _modoSelecao = !_modoSelecao;
      if (!_modoSelecao) {
        _produtosSelecionados.clear();
      }
    });
  }

  void _toggleSelecaoProduto(String key) {
    // Não permitir keys vazias ou inválidas
    if (key.isEmpty) return;

    setState(() {
      if (_produtosSelecionados.contains(key)) {
        _produtosSelecionados.remove(key);
      } else {
        _produtosSelecionados.add(key);
      }
    });
  }

  /// Mesma loja da box Hive aberta na tela; fallback só se [_lojaId] ainda estiver vazio.
  Future<String?> _lojaIdParaLote() async {
    final cached = _lojaId?.trim();
    if (cached != null && cached.isNotEmpty) return cached;
    final resolved = await LojaIdService.getWithTimeoutThenSessionFallback(
        timeout: kIsWeb ? const Duration(seconds: 25) : const Duration(seconds: 10));
    if (kDebugMode && resolved != null) {
      logD('[ESTOQUE_LOTE] lojaId resolvido via getWithTimeoutThenSessionFallback (cache de tela vazio)');
    }
    return resolved;
  }

  List<int> _hiveKeysSelecionados() {
    final keys = <int>[];
    for (final keyStr in _produtosSelecionados) {
      final k = int.tryParse(keyStr);
      if (k != null) keys.add(k);
    }
    return keys;
  }

  /// IDs de documento em `lojas/{lojaId}/produtos` (slug ou slugify(nome)), alinhado ao [CatalogoSyncService].
  List<String> _catalogDocIdsSelecionados() {
    final ids = <String>[];
    final seen = <String>{};
    for (final keyStr in _produtosSelecionados) {
      final key = int.tryParse(keyStr);
      if (key == null) continue;
      final p = _box.get(key);
      if (p == null) continue;
      final docId =
          (p.slug.trim().isNotEmpty ? p.slug.trim() : CatalogoSyncService.slugify(p.nome)).trim();
      if (docId.isEmpty || seen.contains(docId)) continue;
      seen.add(docId);
      ids.add(docId);
    }
    return ids;
  }

  /// Atualiza `draft_produtos` e `produtos` com os dados atuais do Hive (categoria, subcategoria, etc.).
  Future<void> _syncCatalogoWebParaChavesHive({
    required String lojaId,
    required List<int> hiveKeys,
  }) async {
    var any = false;
    for (final key in hiveKeys) {
      final p = _box.get(key);
      if (p == null || !p.publicadoNoCatalogo) continue;
      p.updatedAt = DateTime.now();
      await p.save();
      try {
        await CatalogoSyncService.syncProduto(
          p,
          target: SyncTarget.draft,
          lojaIdOverride: lojaId,
        );
        await CatalogoSyncService.syncProduto(
          p,
          target: SyncTarget.live,
          lojaIdOverride: lojaId,
          removerSeSemEstoque: true,
        );
        any = true;
      } catch (e, st) {
        logE(
          '[ESTOQUE_LOTE] Falha ao sincronizar catálogo web (type=${e.runtimeType})',
          error: e,
          st: st,
        );
      }
    }
    if (any && mounted) {
      await CatalogPublishService.marcarCatalogoPrecisaAtualizar();
      setState(() => _catalogoPrecisaAtualizar = true);
    }
  }

  void _selecionarTodos() {
    setState(() {
      _searchDebounce?.cancel();
      _debouncedSearchQuery = _norm(_pesquisaController.text);
      final q = _debouncedSearchQuery;
      final produtos = _box.values.where((p) {
        if (q.isNotEmpty && !(_norm(p.nome).contains(q) ||
            _norm(p.descricao).contains(q) ||
            _norm(p.categoria).contains(q) ||
            _norm(p.subcategoria).contains(q) ||
            _norm(p.slug).contains(q) ||
            _norm(p.codigoBarras).contains(q))) {
          return false;
        }
        if (_filtroCategoria != null && _filtroCategoria!.isNotEmpty && _norm(p.categoria) != _norm(_filtroCategoria!)) {
          return false;
        }
        if (_filtroSubcategoria != null && _filtroSubcategoria!.isNotEmpty && _norm(p.subcategoria) != _norm(_filtroSubcategoria!)) {
          return false;
        }
        if (_filtroPublicado != null && p.publicadoNoCatalogo != _filtroPublicado) {
          return false;
        }
        if (_filtroSemFotos && p.imagens.isNotEmpty) {
          return false;
        }
        if (_filtroRecentementeAlterados) {
          if (p.updatedAt == null) return false;
          final limite = DateTime.now().subtract(const Duration(hours: 24));
          if (p.updatedAt!.isBefore(limite)) return false;
        }
        return true;
      }).toList();

      // Contar apenas produtos com keys válidas
      final produtosComKey = produtos.where((p) => p.key != null).toList();

      if (_produtosSelecionados.length == produtosComKey.length && produtosComKey.isNotEmpty) {
        _produtosSelecionados.clear();
      } else {
        _produtosSelecionados.clear();
        for (var p in produtosComKey) {
          // Usar p.key diretamente (HiveObject já tem a key)
          final key = p.key;
          if (key != null) {
            _produtosSelecionados.add(key.toString());
          }
        }
      }
    });
  }

  // ========== AÇÕES EM LOTE (NOVO) ==========

  Future<void> _alterarCategoriaLote() async {
    if (_produtosSelecionados.isEmpty) {
      _showSnackBar('Nenhum produto selecionado', isError: true);
      return;
    }
    final catNormToCanon = <String, String>{};
    for (final p in _box.values) {
      final c = p.categoria.trim();
      if (c.isEmpty) continue;
      if (p.ehCombo && _norm(c) == 'combo') continue;
      final n = _norm(c);
      catNormToCanon[n] = canonicalizeCategoria(c);
    }
    final categorias = catNormToCanon.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setDialogState) {
          return AlertDialog(
            title: const Text('Alterar Categoria em Lote'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Nova categoria para os ${_produtosSelecionados.length} produto(s):'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      labelText: 'Categoria',
                      hintText: 'Ex: Roupas',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  if (categorias.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text('Sugestões:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: categorias.take(15).map((c) => ActionChip(
                        label: Text(c, style: const TextStyle(fontSize: 12)),
                        onPressed: () {
                          controller.text = c;
                          setDialogState(() {});
                        },
                      )).toList(),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              FilledButton(
                onPressed: () {
                  final v = canonicalizeCategoria(controller.text.trim());
                  if (v.isNotEmpty) Navigator.pop(ctx, v);
                },
                child: const Text('Aplicar'),
              ),
            ],
          );
        },
      ),
    );
    if (result == null || result.isEmpty) return;
    setState(() => _publicando = true);
    try {
      int n = 0;
      for (final keyStr in _produtosSelecionados) {
        final key = int.tryParse(keyStr);
        if (key == null) continue;
        final p = _box.get(key);
        if (p == null) continue;
        p.categoria = result;
        await p.save();
        n++;
      }
      final lojaIdSync = await _lojaIdParaLote();
      if (lojaIdSync != null && lojaIdSync.trim().isNotEmpty) {
        final keys = _hiveKeysSelecionados();
        await ProdutosFirestoreService.syncProdutosPorChavesHive(
          box: _box,
          lojaId: lojaIdSync,
          hiveKeys: keys,
        );
        await _syncCatalogoWebParaChavesHive(lojaId: lojaIdSync, hiveKeys: keys);
        if (kDebugMode) {
          logD('[ESTOQUE_LOTE] categoria: sync estoque_produtos ${_hiveKeysSelecionados().length} item(ns)');
        }
      } else {
        logD('[ESTOQUE] Sync omitido: lojaId vazio após alterar categoria em lote');
        if (mounted) _showSnackBar('Alterações salvas localmente. Sincronize com a nuvem depois.');
      }
      if (!mounted) return;
      _showSnackBar('Categoria alterada em $n produto(s)');
      setState(() {
        _produtosSelecionados.clear();
        _modoSelecao = false;
      });
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Erro: $e', isError: true);
    } finally {
      if (mounted) setState(() => _publicando = false);
    }
  }

  Future<void> _alterarSubcategoriaLote() async {
    if (_produtosSelecionados.isEmpty) {
      _showSnackBar('Nenhum produto selecionado', isError: true);
      return;
    }
    final subNormToCanon = <String, String>{};
    for (final p in _box.values) {
      final s = p.subcategoria.trim();
      if (s.isEmpty) continue;
      if (p.ehCombo && _norm(s) == 'combo') continue;
      final n = _norm(s);
      subNormToCanon[n] = canonicalizeCategoria(s);
    }
    final subcategorias = subNormToCanon.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setDialogState) {
          return AlertDialog(
            title: const Text('Alterar Subcategoria em Lote'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Nova subcategoria para os ${_produtosSelecionados.length} produto(s):'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      labelText: 'Subcategoria',
                      hintText: 'Ex: Camisetas',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  if (subcategorias.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text('Sugestões:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: subcategorias.take(15).map((s) => ActionChip(
                        label: Text(s, style: const TextStyle(fontSize: 12)),
                        onPressed: () {
                          controller.text = s;
                          setDialogState(() {});
                        },
                      )).toList(),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              FilledButton(
                onPressed: () {
                  final v = canonicalizeCategoria(controller.text.trim());
                  if (v.isNotEmpty) Navigator.pop(ctx, v);
                },
                child: const Text('Aplicar'),
              ),
            ],
          );
        },
      ),
    );
    if (result == null || result.isEmpty) return;
    setState(() => _publicando = true);
    try {
      int n = 0;
      for (final keyStr in _produtosSelecionados) {
        final key = int.tryParse(keyStr);
        if (key == null) continue;
        final p = _box.get(key);
        if (p == null) continue;
        p.subcategoria = result;
        await p.save();
        n++;
      }
      final lojaIdSync = await _lojaIdParaLote();
      if (lojaIdSync != null && lojaIdSync.trim().isNotEmpty) {
        final keys = _hiveKeysSelecionados();
        await ProdutosFirestoreService.syncProdutosPorChavesHive(
          box: _box,
          lojaId: lojaIdSync,
          hiveKeys: keys,
        );
        await _syncCatalogoWebParaChavesHive(lojaId: lojaIdSync, hiveKeys: keys);
        if (kDebugMode) {
          logD('[ESTOQUE_LOTE] subcategoria: sync estoque_produtos ${_hiveKeysSelecionados().length} item(ns)');
        }
      } else {
        logD('[ESTOQUE] Sync omitido: lojaId vazio após alterar subcategoria em lote');
        if (mounted) _showSnackBar('Alterações salvas localmente. Sincronize com a nuvem depois.');
      }
      if (!mounted) return;
      _showSnackBar('Subcategoria alterada em $n produto(s)');
      setState(() {
        _produtosSelecionados.clear();
        _modoSelecao = false;
      });
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Erro: $e', isError: true);
    } finally {
      if (mounted) setState(() => _publicando = false);
    }
  }

  /// Ação em lote: ativar "dividir sem juros" nos produtos selecionados.
  Future<void> _dividirSemJurosLote() async {
    if (_produtosSelecionados.isEmpty) {
      _showSnackBar('Nenhum produto selecionado', isError: true);
      return;
    }
    final maxParcelasCtrl = TextEditingController(text: '12');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dividir sem juros em lote'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ativar parcelamento sem juros em ${_produtosSelecionados.length} produto(s).'),
            const SizedBox(height: 16),
            TextField(
              controller: maxParcelasCtrl,
              decoration: const InputDecoration(
                labelText: 'Máx. parcelas sem juros',
                hintText: '12',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Aplicar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final maxParcelas = (int.tryParse(maxParcelasCtrl.text.trim()) ?? 12).clamp(1, 24);
    setState(() => _publicando = true);
    try {
      int n = 0;
      final lojaId = await _lojaIdParaLote();
      for (final keyStr in _produtosSelecionados) {
        final key = int.tryParse(keyStr);
        if (key == null) continue;
        final p = _box.get(key);
        if (p == null) continue;
        p.divideSemJuros = true;
        p.maxParcelasSemJuros = maxParcelas;
        await p.save();
        n++;
      }
      if (lojaId != null && lojaId.isNotEmpty && n > 0) {
        await ProdutosFirestoreService.syncProdutosPorChavesHive(
          box: _box,
          lojaId: lojaId,
          hiveKeys: _hiveKeysSelecionados(),
        );
        if (kDebugMode) {
          logD('[ESTOQUE_LOTE] dividir sem juros: sync $n item(ns) loja=$lojaId');
        }
      } else if (n > 0) {
        logD('[ESTOQUE] Sync omitido: lojaId vazio após dividir sem juros em lote');
        if (mounted) {
          _showSnackBar('Alterações salvas localmente. Sincronize com a nuvem depois.');
        }
      }
      if (!mounted) return;
      _showSnackBar('Dividir sem juros aplicado em $n produto(s)');
      setState(() {
        _produtosSelecionados.clear();
        _modoSelecao = false;
      });
    } catch (e) {
      if (mounted) _showSnackBar('Erro: $e', isError: true);
    } finally {
      if (mounted) setState(() => _publicando = false);
    }
  }

  /// Ação em lote: definir % desconto PIX nos produtos selecionados.
  Future<void> _descontoPixLote() async {
    if (_produtosSelecionados.isEmpty) {
      _showSnackBar('Nenhum produto selecionado', isError: true);
      return;
    }
    final percentualCtrl = TextEditingController(text: '5');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desconto PIX em lote'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Definir percentual de desconto no PIX para ${_produtosSelecionados.length} produto(s).'),
            const SizedBox(height: 16),
            TextField(
              controller: percentualCtrl,
              decoration: const InputDecoration(
                labelText: 'Desconto PIX (%)',
                hintText: '5',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Aplicar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final percentual = (double.tryParse(percentualCtrl.text.trim()) ?? 0.0).clamp(0.0, 100.0);
    setState(() => _publicando = true);
    try {
      int n = 0;
      final lojaId = await _lojaIdParaLote();
      for (final keyStr in _produtosSelecionados) {
        final key = int.tryParse(keyStr);
        if (key == null) continue;
        final p = _box.get(key);
        if (p == null) continue;
        p.percentualDescontoPix = percentual;
        await p.save();
        n++;
      }
      if (lojaId != null && lojaId.isNotEmpty && n > 0) {
        await ProdutosFirestoreService.syncProdutosPorChavesHive(
          box: _box,
          lojaId: lojaId,
          hiveKeys: _hiveKeysSelecionados(),
        );
        if (kDebugMode) {
          logD('[ESTOQUE_LOTE] desconto PIX: sync $n item(ns) loja=$lojaId');
        }
      } else if (n > 0) {
        logD('[ESTOQUE] Sync omitido: lojaId vazio após desconto PIX em lote');
        if (mounted) {
          _showSnackBar('Alterações salvas localmente. Sincronize com a nuvem depois.');
        }
      }
      if (!mounted) return;
      _showSnackBar('Desconto PIX de ${percentual.toStringAsFixed(1)}% aplicado em $n produto(s)');
      setState(() {
        _produtosSelecionados.clear();
        _modoSelecao = false;
      });
    } catch (e) {
      if (mounted) _showSnackBar('Erro: $e', isError: true);
    } finally {
      if (mounted) setState(() => _publicando = false);
    }
  }

  /// Ação em lote: ativar promoção (% ou valor fixo) e período opcional.
  Future<void> _promocaoEmLote() async {
    if (_produtosSelecionados.isEmpty) {
      _showSnackBar('Nenhum produto selecionado', isError: true);
      return;
    }
    final percentCtrl = TextEditingController(text: '10');
    final valorCtrl = TextEditingController();
    String tipoDesconto = 'percentual';
    DateTime? dataInicio;
    DateTime? dataFim;
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: const Text('Promoção em lote'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Definir promoção para ${_produtosSelecionados.length} produto(s).',
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: RadioListTile<String>(
                            title: const Text('%'),
                            value: 'percentual',
                            groupValue: tipoDesconto,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            onChanged: (v) {
                              if (v == null) return;
                              setLocal(() => tipoDesconto = v);
                            },
                          ),
                        ),
                        Expanded(
                          child: RadioListTile<String>(
                            title: const Text('R\$ fixo'),
                            value: 'fixo',
                            groupValue: tipoDesconto,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            onChanged: (v) {
                              if (v == null) return;
                              setLocal(() => tipoDesconto = v);
                            },
                          ),
                        ),
                      ],
                    ),
                    if (tipoDesconto == 'percentual')
                      TextField(
                        controller: percentCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Desconto (%)',
                          hintText: '10',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      )
                    else
                      TextField(
                        controller: valorCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Valor de desconto (R\$)',
                          hintText: '0,00',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [MoedaInputFormatter()],
                      ),
                    const SizedBox(height: 12),
                    const Text(
                      'Período (opcional)',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final date = await showDatePicker(
                                context: ctx,
                                initialDate: dataInicio ?? DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2035),
                              );
                              if (date != null) {
                                setLocal(() => dataInicio = date);
                              }
                            },
                            icon: const Icon(Icons.calendar_today, size: 16),
                            label: Text(
                              dataInicio == null
                                  ? 'Início'
                                  : '${dataInicio!.day}/${dataInicio!.month}/${dataInicio!.year}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final date = await showDatePicker(
                                context: ctx,
                                initialDate: dataFim ?? DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2035),
                              );
                              if (date != null) {
                                setLocal(() => dataFim = date);
                              }
                            },
                            icon: const Icon(Icons.event, size: 16),
                            label: Text(
                              dataFim == null
                                  ? 'Fim'
                                  : '${dataFim!.day}/${dataFim!.month}/${dataFim!.year}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (dataInicio != null || dataFim != null)
                      TextButton(
                        onPressed: () {
                          setLocal(() {
                            dataInicio = null;
                            dataFim = null;
                          });
                        },
                        child: const Text('Limpar datas'),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Aplicar'),
                ),
              ],
            );
          },
        ),
      );
      if (ok != true || !mounted) return;

      double? pct;
      double? valFixo;
      if (tipoDesconto == 'percentual') {
        pct = (double.tryParse(percentCtrl.text.trim().replaceAll(',', '.')) ?? 0)
            .clamp(0.0, 100.0);
        if (pct <= 0) {
          _showSnackBar('Informe um percentual maior que zero.', isError: true);
          return;
        }
      } else {
        valFixo = MoedaInputFormatter.parse(valorCtrl.text);
        if (valFixo <= 0) {
          _showSnackBar('Informe um valor de desconto maior que zero.', isError: true);
          return;
        }
      }

      setState(() => _publicando = true);
      int n = 0;
      final lojaId = await _lojaIdParaLote();
      for (final keyStr in _produtosSelecionados) {
        final key = int.tryParse(keyStr);
        if (key == null) continue;
        final p = _box.get(key);
        if (p == null) continue;
        p.emPromocao = true;
        if (tipoDesconto == 'percentual') {
          p.percentualPromo = pct;
          p.valorPromo = null;
        } else {
          p.percentualPromo = null;
          p.valorPromo = valFixo;
        }
        p.dataInicioPromo = dataInicio;
        p.dataFimPromo = dataFim;
        await p.save();
        n++;
      }
      if (lojaId != null && lojaId.isNotEmpty && n > 0) {
        await ProdutosFirestoreService.syncProdutosPorChavesHive(
          box: _box,
          lojaId: lojaId,
          hiveKeys: _hiveKeysSelecionados(),
        );
        if (kDebugMode) {
          logD('[ESTOQUE_LOTE] promoção: sync $n item(ns) loja=$lojaId');
        }
      } else if (n > 0) {
        logD('[ESTOQUE] Sync omitido: lojaId vazio após promoção em lote');
        if (mounted) {
          _showSnackBar('Alterações salvas localmente. Sincronize com a nuvem depois.');
        }
      }
      if (!mounted) return;
      final msg = tipoDesconto == 'percentual'
          ? 'Promoção de ${pct!.toStringAsFixed(1)}% aplicada em $n produto(s)'
          : 'Promoção de R\$ ${valFixo!.toStringAsFixed(2)} aplicada em $n produto(s)';
      _showSnackBar(msg);
      setState(() {
        _produtosSelecionados.clear();
        _modoSelecao = false;
      });
    } catch (e) {
      if (mounted) _showSnackBar('Erro: $e', isError: true);
    } finally {
      percentCtrl.dispose();
      valorCtrl.dispose();
      if (mounted) setState(() => _publicando = false);
    }
  }

  Future<void> _excluirSelecionados() async {
    if (_produtosSelecionados.isEmpty) {
      _showSnackBar('Nenhum produto selecionado', isError: true);
      return;
    }

    final confirmar = await _showConfirmSheet(
      'Excluir ${_produtosSelecionados.length} produto(s)?',
      'Esta ação não pode ser desfeita. Os produtos serão removidos do estoque, catálogo e Firebase.',
      confirmText: 'Excluir',
      confirmColor: _errorColor,
    );

    if (confirmar != true) return;

    setState(() => _publicando = true);

    try {
      final lojaId = await _lojaIdParaLote();
      if (lojaId == null || lojaId.isEmpty) {
        _showSnackBar('Nenhuma loja ativa', isError: true);
        return;
      }

      int sucesso = 0;
      int erro = 0;

      for (var keyStr in _produtosSelecionados) {
        final key = int.tryParse(keyStr);
        if (key == null) continue;
        final produto = _box.get(key);
        if (produto == null) continue;

        try {
          await ProdutoExclusaoRemotaService.exclusaoRemotaCompletaImediata(
            produto: produto,
            lojaId: lojaId,
          );
          await _box.delete(key);
          sucesso++;
        } catch (e, st) {
          erro++;
          logE('Erro ao excluir produto (type=${e.runtimeType})', error: e, st: st);
        }
      }

      if (mounted) {
        setState(() {
          _produtosSelecionados.clear();
          _modoSelecao = false;
        });
        _showSnackBar(
          '$sucesso produto(s) excluído(s) definitivamente${erro > 0 ? ' ($erro erro(s))' : ''}.',
        );
      }
    } catch (e) {
      if (mounted) _showSnackBar('Erro ao excluir: $e', isError: true);
    } finally {
      if (mounted) setState(() => _publicando = false);
    }
  }

  Future<void> _adicionarAoCatalogoLote() async {
    if (_produtosSelecionados.isEmpty) {
      _showSnackBar('Nenhum produto selecionado', isError: true);
      return;
    }

    setState(() => _publicando = true);

    try {
      int sucesso = 0;
      int erro = 0;

      final lojaId = await _lojaIdParaLote();
      if (lojaId == null || lojaId.isEmpty) {
        _showSnackBar('Erro: Nenhuma loja ativa', isError: true);
        return;
      }

      logD('[ESTOQUE_LOTE] adicionar catálogo: ${_produtosSelecionados.length} selecionado(s) loja=$lojaId');

      for (var keyStr in _produtosSelecionados) {
        final key = int.tryParse(keyStr);

        try {
          if (key == null) {
            logW('⚠️ [LOTE] Key inválida: $keyStr');
            continue;
          }

          final produto = _box.get(key);
          if (produto == null) {
            logW('⚠️ [LOTE] Produto não encontrado para key: $key');
            continue;
          }

          produto.publicadoNoCatalogo = true;
          await produto.save();

          await CatalogoSyncService.syncProduto(
            produto,
            target: SyncTarget.draft,
            lojaIdOverride: lojaId,
          );

          final docId = (produto.slug.trim().isNotEmpty
                  ? produto.slug.trim()
                  : CatalogoSyncService.slugify(produto.nome))
              .trim();
          if (docId.isNotEmpty) {
            await CatalogPublishService.promoteOne(docId, lojaIdOverride: lojaId);
            if (kDebugMode) {
              logD('[ESTOQUE_LOTE] [CATALOGO_ITEM] publicado draft→live docId=$docId');
            }
          }

          sucesso++;
        } catch (e, st) {
          erro++;
          logE('❌ [LOTE] Erro ao adicionar ao catálogo (type=${e.runtimeType})', error: e, st: st);
        }
      }

      if (sucesso > 0 && erro == 0) {
        await CatalogPublishService.limparCatalogoPrecisaAtualizar();
        if (mounted) setState(() => _catalogoPrecisaAtualizar = false);
      } else if (sucesso > 0) {
        await CatalogPublishService.marcarCatalogoPrecisaAtualizar();
        if (mounted) setState(() => _catalogoPrecisaAtualizar = true);
      }

      if (mounted) {
        setState(() {
          _produtosSelecionados.clear();
          _modoSelecao = false;
        });
        final msg = '$sucesso produto(s) adicionado(s) ao catálogo${erro > 0 ? ' ($erro erro(s))' : ''}';
        logD('📦 [LOTE] Resultado: $msg');
        _showSnackBar(msg);
      }
    } catch (e, st) {
      logE('❌ [LOTE] Erro geral (type=${e.runtimeType})', error: e, st: st);
      if (mounted) _showSnackBar('Erro: $e', isError: true);
    } finally {
      if (mounted) setState(() => _publicando = false);
    }
  }

  Future<void> _removerDoCatalogoLote() async {
    if (_produtosSelecionados.isEmpty) {
      _showSnackBar('Nenhum produto selecionado', isError: true);
      return;
    }

    setState(() => _publicando = true);

    try {
      int sucesso = 0;
      int erro = 0;

      final lojaId = await _lojaIdParaLote();
      if (lojaId == null || lojaId.isEmpty) {
        _showSnackBar('Erro: Nenhuma loja ativa', isError: true);
        return;
      }

      logD('[ESTOQUE_LOTE] remover catálogo: ${_produtosSelecionados.length} selecionado(s) loja=$lojaId');

      for (var keyStr in _produtosSelecionados) {
        final key = int.tryParse(keyStr);

        try {
          if (key == null) {
            logW('⚠️ [LOTE] Key inválida: $keyStr');
            continue;
          }

          final produto = _box.get(key);
          if (produto == null) {
            logW('⚠️ [LOTE] Produto não encontrado para key: $key');
            continue;
          }

          produto.publicadoNoCatalogo = false;
          await produto.save();

          await CatalogoSyncService.syncProduto(
            produto,
            target: SyncTarget.draft,
            lojaIdOverride: lojaId,
          );

          final docId = (produto.slug.trim().isNotEmpty
                  ? produto.slug.trim()
                  : CatalogoSyncService.slugify(produto.nome))
              .trim();
          if (docId.isNotEmpty) {
            await CatalogPublishService.promoteOne(docId, lojaIdOverride: lojaId);
            if (kDebugMode) {
              logD('[ESTOQUE_LOTE] [CATALOGO_ITEM] despublicado draft+live docId=$docId');
            }
          }

          sucesso++;
        } catch (e, st) {
          erro++;
          logE('❌ [LOTE] Erro ao remover do catálogo (type=${e.runtimeType})', error: e, st: st);
        }
      }

      if (sucesso > 0 && erro == 0) {
        await CatalogPublishService.limparCatalogoPrecisaAtualizar();
        if (mounted) setState(() => _catalogoPrecisaAtualizar = false);
      } else if (sucesso > 0) {
        await CatalogPublishService.marcarCatalogoPrecisaAtualizar();
        if (mounted) setState(() => _catalogoPrecisaAtualizar = true);
      }

      if (mounted) {
        setState(() {
          _produtosSelecionados.clear();
          _modoSelecao = false;
        });
        final msg = '$sucesso produto(s) removido(s) do catálogo${erro > 0 ? ' ($erro erro(s))' : ''}';
        logD('🗑️ [LOTE] Resultado: $msg');
        _showSnackBar(msg);
      }
    } catch (e, st) {
      logE('❌ [LOTE] Erro geral (type=${e.runtimeType})', error: e, st: st);
      if (mounted) _showSnackBar('Erro: $e', isError: true);
    } finally {
      if (mounted) setState(() => _publicando = false);
    }
  }

  Future<void> _adicionarAoMarketplace(String marketplace) async {
    if (_produtosSelecionados.isEmpty) {
      _showSnackBar('Nenhum produto selecionado', isError: true);
      return;
    }

    final lojaId = await _lojaIdParaLote();
    if (lojaId == null || lojaId.isEmpty) {
      _showSnackBar('Erro: Nenhuma loja ativa', isError: true);
      return;
    }

    final docIds = _catalogDocIdsSelecionados();
    if (docIds.isEmpty) {
      _showSnackBar('Nenhum identificador de catálogo válido nos produtos selecionados.', isError: true);
      return;
    }
    if (kDebugMode) {
      logD('[MARKETPLACE_LOTE] $marketplace loja=$lojaId docs=${docIds.length}');
    }

    setState(() {
      _sincronizandoMarketplace = true;
      _marketplaceEmSync = marketplace;
    });
    _showSnackBar('Sincronizando com $marketplace...');

    Map<String, dynamic> resultado;
    switch (marketplace) {
      case 'Mercado Livre':
        resultado = await MarketplaceService.sincronizarProdutosMercadoLivre(
          lojaId: lojaId,
          produtoIds: docIds,
        );
        break;
      case 'TikTok Shop':
        resultado = await MarketplaceService.sincronizarProdutosTikTok(
          lojaId: lojaId,
          produtoIds: docIds,
        );
        break;
      case 'Shopee':
        resultado = await MarketplaceService.sincronizarProdutosShopee(
          lojaId: lojaId,
          produtoIds: docIds,
        );
        break;
      default:
        resultado = {'success': false, 'error': 'Marketplace não suportado'};
    }

    if (!mounted) return;
    setState(() {
      _sincronizandoMarketplace = false;
      _marketplaceEmSync = null;
      _produtosSelecionados.clear();
      _modoSelecao = false;
    });

    final success = resultado['success'] == true;
    if (success) {
      final sincr = (resultado['sincronizados'] is int) ? resultado['sincronizados'] as int : 0;
      final erros = (resultado['erros'] is int) ? resultado['erros'] as int : 0;
      final total = (resultado['total'] is int) ? resultado['total'] as int : 0;
      if (total == 0) {
        _showSnackBar(
          'Nenhum documento encontrado em catálogo publicado para os selecionados. Publique no catálogo antes de sincronizar.',
          isError: true,
        );
      } else {
        _showSnackBar('$marketplace: $sincr de $total produto(s) sincronizados${erros > 0 ? ' ($erros erros)' : ''}');
      }
    } else {
      _showSnackBar(resultado['error']?.toString() ?? 'Erro ao sincronizar', isError: true);
    }
  }

  static const String _keyMostrarEstoqueCatalogo = 'mostrar_estoque_catalogo';
  static const String _keyMostrarQuantidadeCatalogo = 'mostrar_quantidade_catalogo';

  Future<void> _abrirConfigCatalogo() async {
    final lojaId = await LojaIdService.getWithTimeoutThenSessionFallback(
        timeout: kIsWeb ? const Duration(seconds: 25) : const Duration(seconds: 10));
    if (lojaId == null || lojaId.isEmpty) {
      _showSnackBar('Erro: Nenhuma loja ativa', isError: true);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final keyEstoque = '${_keyMostrarEstoqueCatalogo}_$lojaId';
    final keyQuantidade = '${_keyMostrarQuantidadeCatalogo}_$lojaId';
    bool mostrarEstoque = prefs.getBool(keyEstoque) ?? false;
    bool mostrarQuantidade = prefs.getBool(keyQuantidade) ?? false;

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.storefront, color: _primaryColor, size: 28),
                    SizedBox(width: 12),
                    Text(
                      'Configurar catálogo',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SwitchListTile(
                  title: const Text('Mostrar estoque no catálogo'),
                  subtitle: const Text('Exibe o selo "Últimas X" nos produtos com pouco estoque (≤5 unidades)'),
                  value: mostrarEstoque,
                  onChanged: (value) async {
                    setModalState(() => mostrarEstoque = value);
                    final navigator = Navigator.of(context);
                    await prefs.setBool(keyEstoque, value);
                    try {
                      final ref =
                          FirebaseFirestore.instance.collection('lojas').doc(lojaId);
                      await ref.collection('draft_config').doc('config').set(
                            {'mostrarEstoqueNoCatalogo': value},
                            SetOptions(merge: true),
                          );
                      await ref.collection('config').doc('config').set(
                            {'mostrarEstoqueNoCatalogo': value},
                            SetOptions(merge: true),
                          );
                    } catch (e, st) {
                      logE(
                          '[ESTOQUE] Erro ao gravar mostrarEstoqueNoCatalogo no Firestore',
                          error: e,
                          st: st);
                    }
                    if (mounted) {
                      _showSnackBar(value ? 'Selo de estoque ativado' : 'Selo de estoque desativado');
                      navigator.pop();
                    }
                  },
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Mostrar quantidade no catálogo'),
                  subtitle: const Text('Quando ativo: exibe "X un." nas opções (tamanho/cor). Quando inativo: exibe "Disponível"'),
                  value: mostrarQuantidade,
                  onChanged: (value) async {
                    setModalState(() => mostrarQuantidade = value);
                    final navigator = Navigator.of(context);
                    await prefs.setBool(keyQuantidade, value);
                    try {
                      final ref = FirebaseFirestore.instance.collection('lojas').doc(lojaId);
                      await ref.collection('draft_config').doc('config').set(
                        {'mostrarQuantidadeNoCatalogo': value},
                        SetOptions(merge: true),
                      );
                      await ref.collection('config').doc('config').set(
                        {'mostrarQuantidadeNoCatalogo': value},
                        SetOptions(merge: true),
                      );
                    } catch (e, st) {
                      logE('[ESTOQUE] Erro ao gravar mostrarQuantidadeNoCatalogo no Firestore', error: e, st: st);
                    }
                    if (mounted) {
                      _showSnackBar(value ? 'Quantidade visível no catálogo' : 'Catálogo exibirá "Disponível" no lugar da quantidade');
                      navigator.pop();
                    }
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _mostrarMenuAcoes() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
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
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.flash_on, color: _primaryColor),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Ações em Lote',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${_produtosSelecionados.length} produto(s) selecionado(s)',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
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

              // Ações - AGORA ROLÁVEL
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildAcaoTile(
                        icon: Icons.add_shopping_cart,
                        titulo: 'Adicionar ao Catálogo',
                        subtitulo: 'Publicar produtos no catálogo web',
                        cor: _successColor,
                        onTap: () {
                          Navigator.pop(context);
                          _adicionarAoCatalogoLote();
                        },
                      ),

                      _buildAcaoTile(
                        icon: Icons.remove_shopping_cart,
                        titulo: 'Remover do Catálogo',
                        subtitulo: 'Despublicar do catálogo web',
                        cor: _warningColor,
                        onTap: () {
                          Navigator.pop(context);
                          _removerDoCatalogoLote();
                        },
                      ),

                      _buildAcaoTile(
                        icon: Icons.shopping_bag,
                        titulo: 'Mercado Livre',
                        subtitulo: 'Adicionar ao Mercado Livre',
                        cor: const Color(0xFFFFF159),
                        onTap: () {
                          Navigator.pop(context);
                          _adicionarAoMarketplace('Mercado Livre');
                        },
                      ),

                      _buildAcaoTile(
                        icon: Icons.video_library,
                        titulo: 'TikTok Shop',
                        subtitulo: 'Adicionar ao TikTok Shop',
                        cor: Colors.black,
                        onTap: () {
                          Navigator.pop(context);
                          _adicionarAoMarketplace('TikTok Shop');
                        },
                      ),

                      _buildAcaoTile(
                        icon: Icons.store,
                        titulo: 'Shopee',
                        subtitulo: 'Adicionar à Shopee',
                        cor: const Color(0xFFEE4D2D),
                        onTap: () {
                          Navigator.pop(context);
                          _adicionarAoMarketplace('Shopee');
                        },
                      ),

                      const Divider(height: 1),

                      _buildAcaoTile(
                        icon: Icons.category,
                        titulo: 'Alterar Categoria em Lote',
                        subtitulo: 'Definir mesma categoria para todos',
                        cor: _primaryColor,
                        onTap: () {
                          Navigator.pop(context);
                          _alterarCategoriaLote();
                        },
                      ),

                      _buildAcaoTile(
                        icon: Icons.label,
                        titulo: 'Alterar Subcategoria em Lote',
                        subtitulo: 'Definir mesma subcategoria para todos',
                        cor: _primaryColor,
                        onTap: () {
                          Navigator.pop(context);
                          _alterarSubcategoriaLote();
                        },
                      ),

                      _buildAcaoTile(
                        icon: Icons.credit_card,
                        titulo: 'Dividir sem juros em lote',
                        subtitulo: 'Ativar parcelamento sem juros nos selecionados',
                        cor: _successColor,
                        onTap: () {
                          Navigator.pop(context);
                          _dividirSemJurosLote();
                        },
                      ),

                      _buildAcaoTile(
                        icon: Icons.qr_code,
                        titulo: 'Desconto PIX em lote',
                        subtitulo: 'Definir % de desconto no PIX para os selecionados',
                        cor: _primaryColor,
                        onTap: () {
                          Navigator.pop(context);
                          _descontoPixLote();
                        },
                      ),

                      _buildAcaoTile(
                        icon: Icons.local_offer_outlined,
                        titulo: 'Promoção em lote',
                        subtitulo: 'Ativar promoção (% ou R\$ fixo) nos selecionados',
                        cor: const Color(0xFFFF6D00),
                        onTap: () {
                          Navigator.pop(context);
                          _promocaoEmLote();
                        },
                      ),

                      const Divider(height: 1),

                      _buildAcaoTile(
                        icon: Icons.delete,
                        titulo: 'Excluir Produtos',
                        subtitulo: 'Remover permanentemente do estoque',
                        cor: _errorColor,
                        onTap: () {
                          Navigator.pop(context);
                          _excluirSelecionados();
                        },
                      ),

                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAcaoTile({
    required IconData icon,
    required String titulo,
    required String subtitulo,
    required Color cor,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: cor, size: 22),
      ),
      title: Text(
        titulo,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitulo,
        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }

  /// Busca produto por código de barras (ou slug). Retorna lista de (key, produto).
  List<({int key, Produto p})> _buscarPorCodigoBarras(String codigo) {
    final q = _norm(codigo);
    if (q.isEmpty) return [];
    final resultado = <({int key, Produto p})>[];
    for (final key in _box.keys) {
      final k = key is int ? key : int.tryParse(key.toString());
      if (k == null) continue;
      final p = _box.get(k);
      if (p == null) continue;
      if (_norm(p.codigoBarras) == q || _norm(p.slug) == q) {
        resultado.add((key: k, p: p));
      }
    }
    if (resultado.isEmpty) {
      for (final key in _box.keys) {
        final k = key is int ? key : int.tryParse(key.toString());
        if (k == null) continue;
        final p = _box.get(k);
        if (p == null) continue;
        if (_norm(p.codigoBarras).contains(q) || _norm(p.slug).contains(q)) {
          resultado.add((key: k, p: p));
        }
      }
    }
    return resultado;
  }

  /// Diálogo para dar baixa no estoque pelo código de barras.
  Future<void> _baixaPorCodigoBarras() async {
    final codigoCtrl = TextEditingController();
    final qtdCtrl = TextEditingController(text: '1');
    final codigo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Baixa por código de barras'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Digite o código de barras do produto para localizar e dar baixa no estoque.'),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: codigoCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Código de barras',
                      hintText: 'EAN, código interno...',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.qr_code),
                    ),
                    autofocus: true,
                    onSubmitted: (v) => Navigator.pop(context, v.trim()),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Ler com câmera',
                  icon: const Icon(Icons.qr_code_scanner),
                  onPressed: () async {
                    final code = await BarcodeScannerScreen.scan(ctx);
                    if (code != null && code.isNotEmpty) {
                      codigoCtrl.text = code;
                    }
                  },
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, codigoCtrl.text.trim()),
            child: const Text('Buscar'),
          ),
        ],
      ),
    );
    if (codigo == null || codigo.isEmpty || !mounted) return;
    final encontrados = _buscarPorCodigoBarras(codigo);
    if (encontrados.isEmpty) {
      _showSnackBar('Nenhum produto encontrado com esse código', isError: true);
      return;
    }
    Produto produtoAlvo = encontrados.first.p;
    int keyAlvo = encontrados.first.key;
    if (encontrados.length > 1) {
      final escolhido = await showDialog<int>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Vários produtos encontrados'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: encontrados.length,
              itemBuilder: (_, i) {
                final e = encontrados[i];
                return ListTile(
                  title: Text(e.p.nome),
                  subtitle: Text('Estoque: ${e.p.quantidade}'),
                  onTap: () => Navigator.pop(context, e.key),
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ],
        ),
      );
      if (escolhido == null || !mounted) return;
      keyAlvo = escolhido;
      produtoAlvo = _box.get(keyAlvo)!;
    }
    String tam = '';
    String cor = '';
    String extraValor = '';
    int qtdFinal = 1;
    var variacaoConfirmada = false;

    final temVariacao = produtoAlvo.usaVariacoes || produtoAlvo.estoquePorTamanho.isNotEmpty;

    if (temVariacao) {
      // Produto com variação: tamanho, cor, quantidade e personalização (letra/estampa) quando houver
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => NovaVendaVariacaoSheet(
          produto: produtoAlvo,
          preco: produtoAlvo.precoFinal,
          onConfirmar: (t, c, q, ex, _) {
            tam = t;
            cor = c;
            qtdFinal = q;
            extraValor = ex;
            variacaoConfirmada = true;
          },
        ),
      );
      if (!variacaoConfirmada || !mounted) return;
    } else {
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (_, setDialogState) {
            return AlertDialog(
              title: const Text('Dar baixa no estoque'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Produto: ${produtoAlvo.nome}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text('Estoque atual: ${produtoAlvo.quantidade}'),
                  const SizedBox(height: 16),
                  TextField(
                    controller: qtdCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Quantidade a dar baixa',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setDialogState(() {}),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
                FilledButton(
                  onPressed: () {
                    final v = int.tryParse(qtdCtrl.text.trim()) ?? 1;
                    if (v > 0) Navigator.pop(context, true);
                  },
                  child: const Text('Confirmar baixa'),
                ),
              ],
            );
          },
        ),
      );
      if (confirmar != true || !mounted) return;
      qtdFinal = (int.tryParse(qtdCtrl.text.trim()) ?? 1).clamp(1, produtoAlvo.quantidade);
      if (produtoAlvo.quantidade < qtdFinal) {
        _showSnackBar('Estoque insuficiente (${produtoAlvo.quantidade})', isError: true);
        return;
      }
    }

    setState(() => _publicando = true);
    try {
      final lojaId = await LojaIdService.getWithTimeoutThenSessionFallback(
        timeout: kIsWeb ? const Duration(seconds: 25) : const Duration(seconds: 10));
      if (lojaId == null || lojaId.isEmpty) {
        _showSnackBar('Nenhuma loja ativa', isError: true);
        return;
      }
      final result = await EstoqueService.atualizarEstoque(
        produtosBox: _box,
        lojaId: lojaId,
        produtoId: produtoAlvo.idFirebase.isNotEmpty ? produtoAlvo.idFirebase : null,
        produtoSlug: produtoAlvo.slug,
        produtoNome: produtoAlvo.nome,
        tamanho: tam,
        cor: cor,
        variacaoExtra: extraValor,
        quantidade: qtdFinal,
        operacao: 'baixa',
      );
      if (!mounted) return;
      if (result.sucesso) {
        _showSnackBar(result.mensagem);
        setState(() {});
      } else {
        _showSnackBar(result.mensagem, isError: true);
      }
    } catch (e) {
      if (mounted) _showSnackBar('Erro: $e', isError: true);
    } finally {
      if (mounted) setState(() => _publicando = false);
    }
  }

  // ========== FUNÇÕES ORIGINAIS (MANTIDAS) ==========

  Future<void> _abrirForm({Produto? produto}) async {
    final isCombo = produto != null && produto.ehCombo;
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => isCombo
            ? ProdutoComboFormScreen(combo: produto)
            : ProdutoFormScreen(produto: produto),
      ),
    );
    if (ok == true && mounted) {
      final catalogoPendente = await CatalogPublishService.catalogoPrecisaAtualizar;
      setState(() => _catalogoPrecisaAtualizar = catalogoPendente);
    }
  }

  /// Abre formulário de kit (vários itens vendidos juntos).
  Future<void> _abrirNovoKitForm() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ProdutoComboFormScreen()),
    );
    if (ok == true && mounted) {
      final catalogoPendente = await CatalogPublishService.catalogoPrecisaAtualizar;
      setState(() => _catalogoPrecisaAtualizar = catalogoPendente);
    }
  }

  /// Escolha entre produto avulso ou kit ao tocar em «Novo produto».
  Future<void> _mostrarEscolhaNovoProduto() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    'Novo cadastro',
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Escolha o tipo de item',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _primaryColor.withOpacity(0.15),
                    child: const Icon(Icons.inventory_2_outlined, color: _primaryColor),
                  ),
                  title: const Text('Produto'),
                  subtitle: const Text('Um item com preço e estoque próprios'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _abrirForm();
                  },
                ),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.orange.withOpacity(0.2),
                    child: const Icon(Icons.layers_outlined, color: Colors.orange),
                  ),
                  title: const Text('Kit'),
                  subtitle: const Text('Vários produtos vendidos juntos'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _abrirNovoKitForm();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _remover(Produto p) async {
    final confirmar = await _showConfirmSheet(
      'Remover Produto?',
      'Esta ação não pode ser desfeita. O produto "${p.nome}" será removido do estoque, catálogo e Firebase.',
      confirmText: 'Remover',
      confirmColor: _errorColor,
    );

    if (confirmar != true) return;

    setState(() => _publicando = true);
    try {
      final lojaId = await LojaIdService.getWithTimeoutThenSessionFallback(
        timeout: kIsWeb ? const Duration(seconds: 25) : const Duration(seconds: 10));
      if (lojaId == null || lojaId.isEmpty) {
        _showSnackBar('Nenhuma loja ativa', isError: true);
        return;
      }
      await ProdutoExclusaoRemotaService.exclusaoRemotaCompletaImediata(
        produto: p,
        lojaId: lojaId,
      );
      await _box.delete(p.key);
      if (mounted) setState(() {});
      _showSnackBar('Produto removido definitivamente.');
    } catch (e) {
      _showSnackBar("Erro ao remover: $e", isError: true);
    } finally {
      if (mounted) setState(() => _publicando = false);
    }
  }

  Future<void> _exportarEstoque() async {
    setState(() => _exportandoEstoque = true);
    try {
      final lojaId = await LojaIdService.getWithTimeoutThenSessionFallback(
        timeout: kIsWeb ? const Duration(seconds: 25) : const Duration(seconds: 10));
      if (lojaId == null) {
        if (mounted) _showSnackBar('Nenhuma loja ativa', isError: true);
        return;
      }

      final excel = xls.Excel.createExcel();
      final sheet = excel['Estoque'];

      sheet.appendRow([
        xls.TextCellValue('Nome'),
        xls.TextCellValue('Categoria'),
        xls.TextCellValue('Subcategoria'),
        xls.TextCellValue('Código/SKU'),
        xls.TextCellValue('Quantidade'),
        xls.TextCellValue('Preço Unitário'),
        xls.TextCellValue('preco_custo'),
        xls.TextCellValue('Preço Final'),
        xls.TextCellValue('Publicado'),
      ]);

      for (var p in _box.values) {
        sheet.appendRow([
          xls.TextCellValue(p.nome),
          xls.TextCellValue(p.categoria),
          xls.TextCellValue(p.subcategoria),
          xls.TextCellValue(p.slug),
          xls.IntCellValue(p.quantidade),
          xls.TextCellValue(p.precoUnitario.toStringAsFixed(2)),
          xls.TextCellValue(p.custoReal.toStringAsFixed(2)),
          xls.TextCellValue((p.precoFinal > 0 ? p.precoFinal : p.precoUnitario).toStringAsFixed(2)),
          xls.TextCellValue(p.publicadoNoCatalogo ? 'Sim' : 'Não'),
        ]);
      }

      final bytes = excel.encode();
      if (bytes == null) {
        if (mounted) _showSnackBar('Falha ao gerar arquivo Excel. Tente novamente.', isError: true);
        return;
      }

      final fileName = 'estoque_${lojaId}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xlsx';
      await file_saver.saveFile(Uint8List.fromList(bytes), fileName);

      if (mounted) _showSnackBar('Estoque exportado com sucesso!');
    } catch (e) {
      if (mounted) _showSnackBar('Erro ao exportar: $e', isError: true);
    } finally {
      if (mounted) setState(() => _exportandoEstoque = false);
    }
  }

  Future<void> _duplicarProduto(Produto p) async {
    try {
      final copia = Produto(
        nome: '${p.nome} (cópia)',
        custoReal: p.custoReal,
        frete: p.frete,
        gastosFixos: p.gastosFixos,
        gastosVariaveis: p.gastosVariaveis,
        precoSugerido: p.precoSugerido,
        precoFinal: p.precoFinal,
        quantidade: p.quantidade,
        precoUnitario: p.precoUnitario,
        categoria: p.categoria,
        categoriasExtras: List.from(p.categoriasExtras),
        dataEntrada: p.dataEntrada,
        descricao: p.descricao,
        imagens: List.from(p.imagens),
        publicadoNoCatalogo: false,
        slug: '',
        tamanhos: List.from(p.tamanhos),
        subcategoria: p.subcategoria,
        subcategoriasExtras: List.from(p.subcategoriasExtras),
        estoquePorTamanho: Map.from(p.estoquePorTamanho),
        cores: List.from(p.cores),
        ativoNoRascunho: p.ativoNoRascunho,
        idFirebase: '',
        lojaId: p.lojaId,
        emPromocao: p.emPromocao,
        percentualPromo: p.percentualPromo,
        valorPromo: p.valorPromo,
        dataInicioPromo: p.dataInicioPromo,
        dataFimPromo: p.dataFimPromo,
        peso: p.peso,
        tipoEmbalagem: p.tipoEmbalagem,
        marketplaces: List.from(p.marketplaces),
        variacoes: p.variacoes != null ? Map.from(p.variacoes!) : null,
        divideSemJuros: p.divideSemJuros,
        percentualDescontoPix: p.percentualDescontoPix,
        maxParcelasSemJuros: p.maxParcelasSemJuros,
        videoUrl: p.videoUrl,
        codigoBarras: p.codigoBarras,
        estoqueMinimo: p.estoqueMinimo,
        fornecedor: p.fornecedor,
        precoPorTamanho: p.precoPorTamanho != null ? Map.from(p.precoPorTamanho!) : null,
        tipoProduto: p.tipoProduto,
        itensCombo: p.itensCombo?.map((e) => Map<String, dynamic>.from(e)).toList(),
        comboConfig: p.comboConfig != null
            ? ComboConfigCanonical.copyMap(p.comboConfig)
            : null,
        custoEditadoNoCadastro: true,
        updatedAt: DateTime.now(),
      );
      _box.add(copia);
      if (kDebugMode) {
        // ignore: avoid_print
        print('[ProdutoDuplicar] cópia local criada; sincroniza ao salvar no formulário');
      }
      if (mounted) setState(() {});
      _showSnackBar('Produto duplicado. Edite se necessário.');
      await _abrirForm(produto: copia);
    } catch (e) {
      _showSnackBar('Erro ao duplicar: $e', isError: true);
    }
  }

  Future<void> _abrirComprasRevendaPendentes() async {
    final lid = _lojaId?.trim();
    if (lid == null || lid.isEmpty) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ComprasRevendaPendentesScreen(lojaId: lid),
      ),
    );
    if (!mounted) return;
    try {
      final compraBox = await CompraFornecedorHiveStore.openBox(lid);
      if (compraBox != null && mounted) {
        setState(() {
          _comprasRevendaPendentesCount =
              CompraRevendaDetalhamentoService.contarPendentesDetalhamento(
            compraBox,
            lid,
          );
        });
      }
    } catch (_) {}
  }

  Future<bool> _confirmarEntradaSemVinculoCompraRevenda() async {
    if (_comprasRevendaPendentesCount <= 0) return true;
    final escolha = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Compras de revenda pendentes'),
        content: Text(
          'Existem $_comprasRevendaPendentesCount compra(s) de revenda aguardando '
          'detalhamento. Esta entrada pertence a alguma compra já lançada?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'continuar'),
            child: const Text('Continuar sem vincular'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'vincular'),
            child: const Text('Vincular a compra'),
          ),
        ],
      ),
    );
    if (escolha == 'vincular') {
      await _abrirComprasRevendaPendentes();
      return false;
    }
    return true;
  }

  Future<void> _ajustarQuantidade(Produto p, int delta) async {
    final extraTipo =
        p.variacoesExtraTipo != null && p.variacoesExtraTipo!.isNotEmpty;
    final temEstoqueEstruturado =
        p.estoquePorTamanho.isNotEmpty || p.usaVariacoes || extraTipo;
    if (temEstoqueEstruturado) {
      _showSnackBar('Use Editar para ajustar produtos com grade', isError: true);
      return;
    }
    if (delta > 0) {
      final continuar = await _confirmarEntradaSemVinculoCompraRevenda();
      if (!continuar) return;
    }
    final nova = (p.quantidade + delta).clamp(0, 99999);
    if (nova == p.quantidade) return;
    final qtdMov = nova - p.quantidade;
    p.quantidade = nova;
    p.updatedAt = DateTime.now();
    await p.save();
    final lojaId = await LojaIdService.getWithTimeoutThenSessionFallback(
        timeout: kIsWeb ? const Duration(seconds: 25) : const Duration(seconds: 10));
    if (lojaId != null && qtdMov != 0) {
      MovimentacaoEstoqueService.registrar(
        lojaId: lojaId,
        produtoId: p.idFirebase.isNotEmpty ? p.idFirebase : p.key.toString(),
        produtoNome: p.nome,
        tipo: qtdMov > 0 ? 'entrada' : 'saida',
        quantidade: qtdMov.abs(),
        motivo: 'Ajuste manual',
        usuario: 'App',
      ).catchError((_) {});
      // Sincronizar com Firestore e obter resultado para feedback (sucesso / divergência / erro)
      try {
        final resultado = await EstoqueService.sincronizarAjusteManual(p, lojaId);
        if (!mounted) return;
        switch (resultado) {
          case ResultadoAjusteEstoque.sucesso:
            _showSnackBar('Quantidade atualizada: ${p.quantidade}');
            break;
          case ResultadoAjusteEstoque.divergenciaDetectada:
            _showSnackBar(
              'Ajuste concluído com alerta: havia diferença relevante entre o estoque local e o valor no servidor. '
              'Verifique se houve vendas ou alterações recentes em outro dispositivo.',
              duration: const Duration(seconds: 6),
            );
            break;
          case ResultadoAjusteEstoque.erro:
            _showSnackBar('Quantidade salva localmente. Falha ao sincronizar com o servidor.', isError: true);
            break;
        }
      } catch (e) {
        logW('⚠️ [ESTOQUE] Falha ao sincronizar quantidade no servidor (type=${e.runtimeType}). A venda pode falhar.');
        if (mounted) _showSnackBar('Quantidade salva localmente. Verifique a conexão para sincronizar.', isError: true);
      }
    } else {
      if (mounted) setState(() {});
      _showSnackBar('Quantidade atualizada: ${p.quantidade}');
      return;
    }
    if (mounted) setState(() {});
  }

  void _showSnackBar(String message, {bool isError = false, Duration? duration}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        SnackBar(
          duration: duration ?? const Duration(seconds: 4),
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
    });
  }

  Future<bool?> _showConfirmSheet(String title, String message, {
    String confirmText = 'Confirmar',
    Color confirmColor = _primaryColor,
  }) {
    return showModalBottomSheet<bool>(
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
                color: confirmColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.warning_amber_rounded, size: 48, color: confirmColor),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              message,
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
                      backgroundColor: confirmColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(confirmText),
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

  Future<void> _sugerirPromocaoEstoqueParado() async {
    final produtosComEstoque = _box.values
        .where((p) => p.quantidade > 0 && (p.tipoProduto != 'combo'))
        .toList();
    if (produtosComEstoque.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nenhum produto com estoque para sugerir promoção.')),
        );
      }
      return;
    }
    final lista = produtosComEstoque
        .take(30)
        .map((p) => {
              'nome': p.nome,
              'quantidade': p.quantidade,
              if (p.categoria.trim().isNotEmpty) 'categoria': p.categoria,
            })
        .toList();
    final lojaId = _lojaId ?? await LojaIdService.get();
    if (!await IaUsoLimiteService.canUse(lojaId, TipoUsoIa.perguntas)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(IaUsoLimiteService.messageLimitExcedido(TipoUsoIa.perguntas)), backgroundColor: Colors.orange.shade700),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _sugerindoPromocaoIa = true);
    try {
      final sugestao = await AiLojaService.sugerirPromocaoEstoqueParado(produtos: lista);
      if (!mounted) return;
      IaUsoLimiteService.recordUse(lojaId, TipoUsoIa.perguntas);
      setState(() => _sugerindoPromocaoIa = false);
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Sugestão de promoção (estoque parado)'),
          content: SingleChildScrollView(child: SelectableText(sugestao)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _sugerindoPromocaoIa = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AiLojaService.messageForUser(e)),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  String _montarResumoEstoqueParaIa() {
    final todos = _box.values.where((p) => p.tipoProduto != 'combo').toList();
    final comEstoque = todos.where((p) => p.quantidade > 0).toList();
    final semEstoque = todos.where((p) => p.quantidade <= 0).toList();
    final sb = StringBuffer();
    sb.writeln('Total de produtos: ${todos.length}.');
    sb.writeln('Com estoque: ${comEstoque.length}. Sem estoque: ${semEstoque.length}.');
    sb.writeln('--- Produtos com mais estoque (até 25) ---');
    final ordenados = List<Produto>.from(comEstoque)..sort((a, b) => b.quantidade.compareTo(a.quantidade));
    for (final p in ordenados.take(25)) {
      sb.writeln('- ${p.nome}: ${p.quantidade} un. ${p.categoria.trim().isNotEmpty ? "| ${p.categoria}" : ""}');
    }
    if (semEstoque.isNotEmpty) {
      sb.writeln('--- Produtos sem estoque (até 15) ---');
      for (final p in semEstoque.take(15)) {
        sb.writeln('- ${p.nome} ${p.categoria.trim().isNotEmpty ? "(${p.categoria})" : ""}');
      }
    }
    return sb.toString();
  }

  Future<void> _abrirSugestoesIaEstoque() async {
    final resumo = _montarResumoEstoqueParaIa();
    final lojaId = _lojaId ?? await LojaIdService.get() ?? '';
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => _SugestoesIaEstoqueScreen(
          resumoInicial: resumo,
          lojaId: lojaId,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
// IMPORTAÇÃO (MANTIDA COMPLETA)
// ---------------------------------------------------------------------------
Future<void> _importarProdutos() async {
  setState(() => _importando = true);

  try {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowMultiple: false,
      withData: kIsWeb,
      allowedExtensions: ['xlsx', 'csv', 'pdf'],
    );

    if (result == null || result.files.isEmpty) {
      if (mounted) setState(() => _importando = false);
      return;
    }

    final file = result.files.first;
    final ext = file.extension?.toLowerCase() ??
        file.name.split('.').last.toLowerCase();

    final Uint8List fileBytes = await _readPickedFileBytes(file);

    if (fileBytes.isEmpty) {
      throw "Arquivo inválido (bytes vazios)";
    }

    List<Map<String, dynamic>> rows = [];

    if (ext == "xlsx") {
      rows = await _parseExcelSafe(fileBytes);
    } else if (ext == "csv") {
      rows = await _parseCsvSafe(fileBytes);
    } else if (ext == "pdf") {
      rows = await _parsePdfSafe(fileBytes);
    } else {
      throw "Formato não suportado";
    }

    if (rows.isEmpty) throw "Nenhum dado encontrado";

    final lojaId = await LojaIdService.getWithTimeoutThenSessionFallback(
        timeout: kIsWeb ? const Duration(seconds: 25) : const Duration(seconds: 10));
    if (lojaId == null) throw StateError('Nenhuma loja ativa');

    final vendasBoxName = HiveBoxNames.vendas(lojaId);
    if (!Hive.isBoxOpen(vendasBoxName)) {
      await Hive.openBox<Venda>(vendasBoxName);
    }
    final vendasBox = Hive.box<Venda>(vendasBoxName);

    final resultadosImport = <ProdutoImportLinhaResult>[];
    if (mounted) {
      setState(() {
        _importTotal = rows.length;
        _importProgress = 0;
        _importCriados = 0;
        _importAtualizados = 0;
        _importErros = 0;
      });
      _showSnackBar(
        'Importando ${rows.length} produtos… Aguarde, pode levar vários minutos.',
        duration: const Duration(seconds: 5),
      );
    }

    int idx = 0;
    for (final r in rows) {
      idx++;
      final nome = (r['nome'] ?? '').toString().trim();
      final precoNum = _toDouble(r['preco']);
      final qtdNum = _toInt(r['quantidade']);
      final tamanhosRaw = (r['tamanhos'] ?? '').toString();

      if (nome.isEmpty) {
        resultadosImport.add(
          ProdutoImportLinhaResult(
            linha: idx,
            status: ProdutoImportLinhaStatus.falhouDadosInvalidos,
          ),
        );
        if (mounted) {
          setState(() {
            _importProgress = idx;
            _importErros = resultadosImport
                .where((e) =>
                    e.status == ProdutoImportLinhaStatus.falhouDadosInvalidos ||
                    e.status == ProdutoImportLinhaStatus.falhouIdInvalido ||
                    e.status == ProdutoImportLinhaStatus.ignoradoConflito)
                .length;
          });
        }
        continue;
      }

      final estoqueMapa = _parseEstoquePorTamanho(tamanhosRaw);

      final int estoqueTotal =
          estoqueMapa.isNotEmpty ? _sumEstoquePorTamanho(estoqueMapa) : (qtdNum ?? 1);

      final tamanhosLista =
          estoqueMapa.isNotEmpty ? estoqueMapa.keys.toList() : _splitList(tamanhosRaw);

      final pesoStr = (r['peso'] ?? '0').toString().trim();
      final pesoNum = double.tryParse(pesoStr.replaceAll(',', '.')) ?? 0.0;

      final importCusto = ImportCustoInput.fromRowMap(r);
      final custoReal = importCusto.valorExplicito ?? 0.0;
      final frete = _toDouble(r['frete']) ?? 0.0;
      final gastosFixos = _toDouble(r['gastos_fixos']) ?? 0.0;
      final gastosVariaveis = _toDouble(r['gastos_variaveis']) ?? 0.0;
      final precoSugerido = _toDouble(r['preco_sugerido']) ?? 0.0;

      final precoFinal = precoNum ?? 0.0;

      final emPromocao =
          (r['em_promocao'] ?? 'false').toString().toLowerCase() == 'true';
      final percentualPromo = _toDouble(r['percentual_promo']);
      final valorPromo = _toDouble(r['valor_promo']);

      DateTime? dataInicioPromo;
      DateTime? dataFimPromo;

      final inicioStr = (r['data_inicio_promo'] ?? '').toString().trim();
      if (inicioStr.isNotEmpty) dataInicioPromo = _parseDate(inicioStr);

      final fimStr = (r['data_fim_promo'] ?? '').toString().trim();
      if (fimStr.isNotEmpty) dataFimPromo = _parseDate(fimStr);

      final tipoEmbalagem = (r['tipo_embalagem'] ?? 'padrao').toString().trim();

      final coresStr = (r['cores'] ?? '').toString();
      final coresList = _splitList(coresStr);

      final imagensStr = (r['imagens'] ?? r['imagens_urls'] ?? '').toString();
      final imagensListRaw = _splitList(imagensStr);

      final produtoSlugStorage = "$lojaId-${_slugify(nome)}";

      final imagensFinal = <String>[];
      var idxImg = 1;

      for (final img in imagensListRaw) {
        final s = img.trim();
        if (s.isEmpty) continue;

        if (_isUrl(s)) {
          final urlFinal = await _baixarEEnviarParaStorage(
            lojaId: lojaId,
            produtoSlug: produtoSlugStorage,
            url: s,
            index: idxImg,
          );

          if (urlFinal != null && urlFinal.trim().isNotEmpty) {
            imagensFinal.add(urlFinal);
            idxImg++;
          }
        } else {
          imagensFinal.add(s);
        }
      }

      final marketplacesStr = (r['marketplaces'] ?? '').toString();
      final marketplacesList = _splitList(marketplacesStr);

      final publicar =
          (r['publicar'] ?? 'false').toString().toLowerCase() == 'true';

      final codigoBarras = (r['codigo_barras'] ?? '').toString().trim();
      final sku = (r['sku'] ?? '').toString().trim();

      final p = Produto(
        nome: nome,
        custoReal: custoReal,
        frete: frete,
        gastosFixos: gastosFixos,
        gastosVariaveis: gastosVariaveis,
        precoSugerido: precoSugerido,
        precoFinal: precoFinal,
        quantidade: estoqueTotal,
        precoUnitario: precoFinal,
        categoria: (r['categoria'] ?? '').toString().trim(),
        subcategoria: (r['subcategoria'] ?? '').toString().trim(),
        dataEntrada: DateTime.now(),
        descricao: (r['descricao'] ?? '').toString().trim(),
        imagens: imagensFinal,
        publicadoNoCatalogo: publicar,
        tamanhos: tamanhosLista,
        estoquePorTamanho: estoqueMapa,
        lojaId: lojaId,
        peso: pesoNum,
        tipoEmbalagem: tipoEmbalagem,
        cores: coresList,
        emPromocao: emPromocao,
        percentualPromo: percentualPromo,
        valorPromo: valorPromo,
        dataInicioPromo: dataInicioPromo,
        dataFimPromo: dataFimPromo,
        marketplaces: marketplacesList,
      );

      final linhaResult = await ProdutoImportService.processarLinha(
        linha: idx,
        produto: p,
        lojaId: lojaId,
        produtosBox: _box,
        vendasBox: vendasBox,
        codigoBarras: codigoBarras.isNotEmpty ? codigoBarras : null,
        sku: sku.isNotEmpty ? sku : null,
        importCusto: importCusto,
      );
      resultadosImport.add(linhaResult);

      if (mounted) {
        setState(() {
          _importProgress = idx;
          if (linhaResult.status == ProdutoImportLinhaStatus.sincronizado ||
              linhaResult.status ==
                  ProdutoImportLinhaStatus.pendenteSincronizacao ||
              linhaResult.status ==
                  ProdutoImportLinhaStatus.importadoLocalmente) {
            _importCriados++;
          } else if (linhaResult.status ==
              ProdutoImportLinhaStatus.atualizadoLocalmente) {
            _importAtualizados++;
          } else if (linhaResult.status ==
                  ProdutoImportLinhaStatus.falhouDadosInvalidos ||
              linhaResult.status ==
                  ProdutoImportLinhaStatus.falhouIdInvalido ||
              linhaResult.status ==
                  ProdutoImportLinhaStatus.ignoradoConflito) {
            _importErros++;
          }
        });
      }
    }

    final resumo = ProdutoImportResumo(linhas: resultadosImport);

    if (!mounted) return;
    if (resumo.importadosComSucessoLocal > 0) {
      await CatalogPublishService.marcarCatalogoPrecisaAtualizar();
      setState(() => _catalogoPrecisaAtualizar = true);
    }
    _showSnackBar(resumo.mensagemResumo());
    setState(() {});
  } catch (e) {
    if (!mounted) return;
    _showSnackBar("Erro ao importar: $e", isError: true);
  } finally {
    if (mounted) setState(() => _importando = false);
  }
}


  // ---------------------------------------------------------------------------
  // SYNC COM RASCUNHO DO CATÁLOGO (MANTIDO)
  // ---------------------------------------------------------------------------

  Future<void> _sincronizarComDraft({bool auto = false}) async {
    setState(() => _publicando = true);

    try {
      await CatalogoSyncService.syncAll(
        target: SyncTarget.draft,
        removerSeSemEstoque: true,
      ).timeout(const Duration(seconds: 90));

      if (!mounted) return;
      if (!auto) _showSnackBar("Rascunho sincronizado!");
    } on TimeoutException {
      _showSnackBar("Tempo excedido ao sincronizar", isError: true);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar("Erro: $e", isError: true);
    } finally {
      if (mounted) setState(() => _publicando = false);
    }
  }

  Future<void> _publicarTudoLive() async {
    final confirmar = await _showConfirmSheet(
      'Publicar no Catálogo Live?',
      'Isso irá publicar:\n? Configurações gerais\n? Formas de pagamento\n? Todos os produtos do rascunho\n? Campanhas ativas',
      confirmText: 'Publicar',
      confirmColor: _successColor,
    );

    if (confirmar != true) return;

    setState(() => _publicando = true);

    try {
      final results =
          await CatalogPublishService.publicarCatalogoCanonicamente();

      if (!mounted) return;

      if (results['success']) {
        await CatalogPublishService.limparCatalogoPrecisaAtualizar();
        if (mounted) {
          setState(() {
            _publicando = false;
            _catalogoPrecisaAtualizar = false;
          });
        }
        _showSnackBar(
          'Publicação completa! Produtos: ${results['products']}',
        );
      } else {
        final errors = results['errors'] is List ? results['errors'] as List : <dynamic>[];
        _showSnackBar('Erro na publicação: ${errors.join(', ')}', isError: true);
        if (mounted) setState(() => _publicando = false);
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar("Erro ao publicar: $e", isError: true);
      if (mounted) setState(() => _publicando = false);
    }
  }

// ---------------------------------------------------------------------------
// AÇÕES EM LOTE ORIGINAIS (MANTIDAS)
// ---------------------------------------------------------------------------

Future<void> _publicarTodosProdutos() async {
  final confirmar = await _showConfirmSheet(
    'Marcar todos para publicar?',
    'Todos os produtos serão marcados como "Publicar no catálogo".',
    confirmText: 'Confirmar',
    confirmColor: _successColor,
  );

  if (confirmar != true) return;

  setState(() => _publicando = true);
  try {
    int count = 0;
    for (final produto in _box.values) {
      if (!produto.publicadoNoCatalogo) {
        produto.publicadoNoCatalogo = true;
        await produto.save();
        count++;
      }
    }
    if (!mounted) return;
    _showSnackBar('$count produto(s) marcado(s) para publicação!');
  } catch (e) {
    if (!mounted) return;
    _showSnackBar('Erro: $e', isError: true);
  } finally {
    if (mounted) setState(() => _publicando = false);
  }
}

Future<void> _despublicarTodosProdutos() async {
  final confirmar = await _showConfirmSheet(
    'Desmarcar todos?',
    'Todos os produtos serão desmarcados de "Publicar no catálogo".',
    confirmText: 'Desmarcar',
    confirmColor: _warningColor,
  );

  if (confirmar != true) return;

  setState(() => _publicando = true);
  try {
    int count = 0;
    for (final produto in _box.values) {
      if (produto.publicadoNoCatalogo) {
        produto.publicadoNoCatalogo = false;
        await produto.save();
        count++;
      }
    }
    if (!mounted) return;
    _showSnackBar('$count produto(s) desmarcado(s)!');
  } catch (e) {
    if (!mounted) return;
    _showSnackBar('Erro: $e', isError: true);
  } finally {
    if (mounted) setState(() => _publicando = false);
  }
}

  /// Unificação por nome só soma quantidade: não funde grade/variações/combo.
  bool _produtoTemEstruturaEstoqueRica(Produto p) {
    if (p.usaVariacoes) return true;
    if (p.estoquePorTamanho.isNotEmpty) return true;
    final vet = p.variacoesExtraTipo;
    if (vet != null && vet.isNotEmpty) return true;
    final ppt = p.precoPorTamanho;
    if (ppt != null && ppt.isNotEmpty) return true;
    if (p.tipoProduto == 'combo') return true;
    if (p.itensCombo != null && p.itensCombo!.isNotEmpty) return true;
    if (ComboConfigCanonical.isEffective(p.comboConfig)) return true;
    return false;
  }

  String _nomeCompletoUnificacaoKey(String nome) {
    return nome.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  }

Future<void> _unificarDuplicados() async {
  final confirmar = await _showConfirmSheet(
    'Unificar duplicados?',
    'Produtos com o mesmo nome serão unificados. O preço de venda e custo serão do último cadastrado. As quantidades serão somadas.',
    confirmText: 'Unificar',
    confirmColor: _primaryColor,
  );

  if (confirmar != true) return;

  setState(() => _unificando = true);
  try {
    final lojaId = await LojaIdService.getWithTimeoutThenSessionFallback(
        timeout: kIsWeb ? const Duration(seconds: 25) : const Duration(seconds: 10));
    if (lojaId == null) {
      _showSnackBar('Nenhuma loja ativa', isError: true);
      return;
    }

    final grupos = <String, List<Produto>>{};
    for (final p in _box.values) {
      if (p.lojaId != lojaId) continue;
      // Só unifica quando o nome completo for igual.
      final key = _nomeCompletoUnificacaoKey(p.nome);
      if (key.isEmpty) continue;
      grupos.putIfAbsent(key, () => []).add(p);
    }

    int unificados = 0;
    int deletados = 0;
    int falhasFirestore = 0;
    int gruposIgnoradosRicos = 0;

    for (final lista in grupos.values) {
      if (lista.length < 2) continue;

      if (lista.any((p) => _produtoTemEstruturaEstoqueRica(p))) {
        gruposIgnoradosRicos++;
        continue;
      }

      lista.sort((a, b) {
        final ka = a.key ?? -1;
        final kb = b.key ?? -1;
        return ka.compareTo(kb);
      });

      final ultimo = lista.last;
      final somaQtd = lista.fold<int>(0, (s, p) => s + p.quantidade);

      ultimo.quantidade = somaQtd;

      for (var i = 0; i < lista.length - 1; i++) {
        final dup = lista[i];
        if (dup.idFirebase.isNotEmpty) {
          try {
            await ProdutosFirestoreService.deleteProduto(dup.idFirebase, lojaId: lojaId);
          } catch (e, st) {
            logE('[ESTOQUE] Erro ao excluir duplicata no Firestore (id=${dup.idFirebase})', error: e, st: st);
            falhasFirestore++;
          }
        }
        await dup.delete();
        deletados++;
      }
      await ultimo.save();
      unificados++;

      try {
        await ProdutosFirestoreService.syncProduto(ultimo, lojaId: lojaId);
      } catch (e, st) {
        logE('[ESTOQUE] Erro ao sincronizar produto unificado no Firestore', error: e, st: st);
        falhasFirestore++;
      }
    }

    if (!mounted) return;
    final partes = <String>[];
    if (unificados > 0) {
      partes.add(
          '$unificados grupo(s) unificado(s) — $deletados duplicata(s) removida(s)');
    }
    if (gruposIgnoradosRicos > 0) {
      partes.add(
        '$gruposIgnoradosRicos grupo(s) com variações, grade por tamanho ou combo não foram unificados. '
        'Revise manualmente no cadastro (unificação automática só é segura para produtos simples).',
      );
    }
    if (partes.isEmpty) {
      partes.add('Nenhum duplicado encontrado');
    }
    var msg = partes.join(' ');
    if (falhasFirestore > 0) {
      msg = '$msg ($falhasFirestore falha(s) ao sincronizar com a nuvem)';
    }
    final soRicos =
        gruposIgnoradosRicos > 0 && unificados == 0 && deletados == 0;
    _showSnackBar(
      msg,
      isError: soRicos,
      duration: gruposIgnoradosRicos > 0
          ? const Duration(seconds: 8)
          : null,
    );
    setState(() {});
  } catch (e) {
    if (!mounted) return;
    _showSnackBar('Erro ao unificar: $e', isError: true);
  } finally {
    if (mounted) setState(() => _unificando = false);
  }
}

  /// Identifica produtos no Firestore (catálogo web) que não existem mais no
  /// cadastro de estoque, exibe a lista e só exclui após confirmação.
  Future<void> _identificarEExcluirOrfaos() async {
    setState(() => _excluindoOrfaos = true);
    try {
      final lojaId = await LojaIdService.getWithTimeoutThenSessionFallback(
        timeout: kIsWeb ? const Duration(seconds: 25) : const Duration(seconds: 10));
      if (lojaId == null) {
        _showSnackBar('Nenhuma loja ativa', isError: true);
        return;
      }

      final orfaos = await CatalogoSyncService.identificarProdutosOrfaos(
        lojaId: lojaId,
        produtosBox: _box,
      );

      if (!mounted) return;
      setState(() => _excluindoOrfaos = false);

      if (orfaos.isEmpty) {
        _showSnackBar('Nenhum produto órfão encontrado. O catálogo está sincronizado.');
        return;
      }

      final confirmar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Produtos órfãos no catálogo web'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${orfaos.length} produto(s) estão no catálogo mas não existem mais no estoque. Deseja excluí-los do catálogo web?',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                ...orfaos.map((o) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 18, color: Colors.grey[600]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          (o['nome'] ?? o['id'] ?? '').toString(),
                          style: const TextStyle(fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                )),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text('Excluir do catálogo'),
            ),
          ],
        ),
      );

      if (confirmar != true || !mounted) return;

      setState(() => _excluindoOrfaos = true);
      final ids = orfaos.map((o) => o['id'] ?? '').where((s) => s.isNotEmpty).toList();
      await CatalogoSyncService.excluirProdutosOrfaosPorIds(
        lojaId: lojaId,
        docIds: ids,
      );

      if (!mounted) return;
      _showSnackBar('${orfaos.length} produto(s) removido(s) do catálogo web');
      setState(() {});
    } catch (e, st) {
      logE('[ESTOQUE] Erro ao excluir produtos órfãos', error: e, st: st);
      if (mounted) _showSnackBar('Erro: $e', isError: true);
    } finally {
      if (mounted) setState(() => _excluindoOrfaos = false);
    }
  }

// ---------------------------------------------------------------------------
// PARSERS (MANTIDOS COMPLETOS)
// ---------------------------------------------------------------------------

/// Extrai valor primitivo de CellValue (excel 4.x) ou objeto qualquer
dynamic _cellValueToObject(dynamic v) {
  if (v == null) return null;
  if (v is xls.CellValue) {
    return switch (v) {
      xls.TextCellValue(:final value) => value.text ?? value.toString(),
      xls.IntCellValue(:final value) => value,
      xls.DoubleCellValue(:final value) => value,
      xls.BoolCellValue(:final value) => value.toString(),
      xls.DateCellValue() => v.toString(),
      xls.DateTimeCellValue() => v.toString(),
      xls.TimeCellValue() => v.toString(),
      xls.FormulaCellValue() => v.toString(),
    };
  }
  return v;
}

String _sanitizeHeader(String s) {
  final lower = (s).toLowerCase().trim();

  const from = 'áàãâäéèêëíìîïóòõôöúùûüçñ';
  const to   = 'aaaaaeeeeiiiiooooouuuucn';

  var out = lower;
  for (var i = 0; i < from.length; i++) {
    out = out.replaceAll(from[i], to[i]);
  }

  out = out
      .replaceAll(RegExp(r'[\t\r\n]+'), ' ')
      .replaceAll(RegExp(r'[_\-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  return out;
}

bool _rowHasUsefulData(List<dynamic> row) {
  for (final c in row) {
    final v = (c ?? '').toString().trim();
    if (v.isNotEmpty) return true;
  }
  return false;
}

int _findBestHeaderRow(List<List<dynamic>> rows) {
  final maxScan = rows.length < 50 ? rows.length : 50;

  bool looksLikeHeader(List<dynamic> row) {
    final texts = row
        .map((e) => _sanitizeHeader((e ?? '').toString()))
        .where((e) => e.isNotEmpty)
        .toList();

    if (texts.length < 2) return false;

    final joined = texts.join(' ');
    final hasNome = joined.contains('nome') || joined.contains('produto') || joined.contains('title') || joined.contains('titulo');
    final hasPreco = joined.contains('preco') || joined.contains('valor') || joined.contains('price') || joined.contains('unitario');

    return hasNome || hasPreco;
  }

  for (var r = 0; r < maxScan; r++) {
    if (looksLikeHeader(rows[r])) return r;
  }

  return 0;
}

Future<List<Map<String, dynamic>>> _parseExcelSafe(Uint8List bytes) async {
  try {
    final excel = xls.Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) return [];

    String? bestSheet;
    int bestScore = -1;

    for (final entry in excel.tables.entries) {
      final table = entry.value;
      if (table.rows.isEmpty) continue;

      var score = 0;
      for (final row in table.rows) {
        final values = row.map((c) => _cellValueToObject(c?.value)).toList();
        if (_rowHasUsefulData(values)) score++;
      }

      if (score > bestScore) {
        bestScore = score;
        bestSheet = entry.key;
      }
    }

    if (bestSheet == null) return [];

    final table = excel.tables[bestSheet]!;
    final rawRows = table.rows.map((r) => r.map((c) => _cellValueToObject(c?.value)).toList()).toList();
    if (rawRows.isEmpty) return [];

    final headerRowIndex = _findBestHeaderRow(rawRows);

    final headerRow = rawRows[headerRowIndex];
    final headers = <int, String>{};

    for (var c = 0; c < headerRow.length; c++) {
      final h = _sanitizeHeader((headerRow[c] ?? '').toString());
      headers[c] = h.isEmpty ? 'col$c' : h;
    }

    final out = <Map<String, dynamic>>[];

    for (var r = headerRowIndex + 1; r < rawRows.length; r++) {
      final row = rawRows[r];
      if (!_rowHasUsefulData(row)) continue;

      final map = <String, dynamic>{};
      for (var c = 0; c < headers.length; c++) {
        map[headers[c] ?? 'col$c'] = c < row.length ? row[c] : null;
      }

      final normalized = _normalizeRow(map);
      if (normalized.isNotEmpty) out.add(normalized);
    }

    return out;
  } catch (e, st) {
    logE('Erro _parseExcelSafe (type=${e.runtimeType})', error: e, st: st);
    return [];
  }
}

Future<List<Map<String, dynamic>>> _parseCsvSafe(Uint8List bytes) async {
  try {
    String text;
    try {
      text = utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      text = latin1.decode(bytes);
    }

    if (text.trim().isEmpty) return [];

    final firstLine = text.split('\n').first;
    final semicolons = ';'.allMatches(firstLine).length;
    final commas = ','.allMatches(firstLine).length;
    final delimiter = semicolons > commas ? ';' : ',';

    final rows = const CsvToListConverter(
      eol: '\n',
      shouldParseNumbers: false,
      fieldDelimiter: ',',
    ).convert(
      delimiter == ',' ? text : text.replaceAll(',', '§§'),
    );

    if (rows.isEmpty) return [];

    List<List<dynamic>> safeRows;
    if (delimiter == ';') {
      safeRows = text
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .map((l) => l.split(';').map((e) => e.replaceAll('§§', ',')).toList())
          .toList();
    } else {
      safeRows = rows;
    }

    if (safeRows.isEmpty) return [];

    final header = safeRows.first
        .map((e) => _sanitizeHeader(e.toString()))
        .toList();

    final out = <Map<String, dynamic>>[];

    for (var i = 1; i < safeRows.length; i++) {
      final line = safeRows[i];
      if (line.isEmpty) continue;

      final map = <String, dynamic>{};
      for (var c = 0; c < header.length && c < line.length; c++) {
        final key = header[c].isEmpty ? 'col$c' : header[c];
        map[key] = line[c];
      }

      final normalized = _normalizeRow(map);
      if (normalized.isNotEmpty) out.add(normalized);
    }

    return out;
  } catch (e, st) {
    logE('Erro _parseCsvSafe (type=${e.runtimeType})', error: e, st: st);
    return [];
  }
}

Future<List<Map<String, dynamic>>> _parsePdfSafe(Uint8List bytes) async {
  if (kIsWeb) throw "Importação de PDF não está disponível no navegador. Use arquivo Excel (.xlsx) ou CSV.";

  try {
    final tmp = io.File(
      '${io.Directory.systemTemp.path}/masterpalm_import_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
    await tmp.writeAsBytes(bytes, flush: true);

    final text = await ReadPdfText.getPDFtext(tmp.path);
    final lines = text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    if (lines.length < 2) return [];

    String delim = ';';
    if (!lines.first.contains(';') && lines.first.contains(',')) delim = ',';
    if (!lines.first.contains(';') && !lines.first.contains(',') && lines.first.contains('\t')) delim = '\t';

    final header = lines.first
        .split(delim)
        .map((e) => _sanitizeHeader(e))
        .toList();

    final out = <Map<String, dynamic>>[];

    for (var i = 1; i < lines.length; i++) {
      final cols = lines[i].split(delim);
      if (cols.isEmpty) continue;

      final map = <String, dynamic>{};
      for (var c = 0; c < header.length && c < cols.length; c++) {
        final key = header[c].isEmpty ? 'col$c' : header[c];
        map[key] = cols[c];
      }

      final normalized = _normalizeRow(map);
      if (normalized.isNotEmpty) out.add(normalized);
    }

    return out;
  } catch (e, st) {
    logE('Erro _parsePdfSafe (type=${e.runtimeType})', error: e, st: st);
    return [];
  }
}

// ---------------------------------------------------------------------------
// HELPERS (MANTIDOS COMPLETOS)
// ---------------------------------------------------------------------------

bool _isUrl(String s) {
  final t = s.trim().toLowerCase();
  return t.startsWith('http://') || t.startsWith('https://');
}

String _extFromUrl(String url) {
  final clean = url.split('?').first;
  final i = clean.lastIndexOf('.');
  if (i == -1) return 'jpg';
  final ext = clean.substring(i + 1).toLowerCase();
  if (ext.length > 5) return 'jpg';
  return ext;
}

Future<String?> _baixarEEnviarParaStorage({
  required String lojaId,
  required String produtoSlug,
  required String url,
  required int index,
}) async {
  try {
    final resp = await http.get(Uri.parse(url));
    if (resp.statusCode != 200) return null;

    final bytes = resp.bodyBytes;
    if (bytes.isEmpty) return null;

    final ext = _extFromUrl(url);
    // Path único por upload: evita sobrescrever o mesmo objeto no Storage (mesma URL + cache imutável).
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path =
        'lojas/$lojaId/produtos/$produtoSlug/${index.toString().padLeft(2, '0')}_$ts.$ext';

    final ref = FirebaseStorage.instance.ref().child(path);

    await ref.putData(
      bytes,
      SettableMetadata(contentType: 'image/$ext'),
    );

    return await ref.getDownloadURL();
  } catch (_) {
    return null;
  }
}

Future<Uint8List> _readPickedFileBytes(PlatformFile file) async {
  if (file.bytes != null && file.bytes!.isNotEmpty) {
    return file.bytes!;
  }

  final stream = file.readStream;
  if (stream != null) {
    final buffer = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      buffer.add(chunk);
    }
    final data = buffer.takeBytes();
    if (data.isNotEmpty) return data;
  }

  final p = file.path;
  if (p != null && p.trim().isNotEmpty) {
    return await io.File(p).readAsBytes();
  }

  throw "Não foi possível ler o arquivo (bytes/path/stream nulos).";
}

Map<String, dynamic> _normalizeRow(Map<String, dynamic> raw) {
  final rawSan = <String, dynamic>{};
  for (final entry in raw.entries) {
    rawSan[_sanitizeHeader(entry.key)] = entry.value;
  }

  String pick(List<String> keys) {
    for (final k in keys) {
      final kk = _sanitizeHeader(k);
      final v = rawSan[kk];
      if (v != null && v.toString().trim().isNotEmpty) {
        return v.toString().trim();
      }
    }
    return '';
  }

  final map = {
    'nome': pick([
      'nome', 'name', 'produto', 'product', 'titulo', 'title', 'nome do produto'
    ]),

    'preco': pick([
      'preco', 'preço', 'valor', 'price', 'preco venda', 'valor venda',
      'preco unitario', 'preço unitário', 'preco_unitario', 'preco unit',
      'preco de venda', 'valor unitario', 'valor unitário', 'valor unit',
      'preco final', 'preço final', 'valor final', 'vlr', 'vl', 'venda'
    ]),

    'quantidade': pick([
      'quantidade', 'qtd', 'estoque', 'stock', 'quant', 'quantidade estoque'
    ]),

    'descricao': pick([
      'descricao', 'descrição', 'description', 'desc'
    ]),

    'tamanhos': pick([
      'tamanhos', 'tamanho', 'size', 'sizes', 'variacao', 'variações'
    ]),

    'imagens': pick([
      'imagen',
      'imagens',
      'imagens_urls',
      'fotos',
      'urls',
      'images',
      'image_urls',
      'foto',
      'imagem',
      'url_imagem',
      'url_imagens',
      'links_imagens',
    ]),

    'codigo_barras': pick([
      'codigo barras', 'codigo_barras', 'barcode', 'ean', 'gtin', 'codigo'
    ]),

    'sku': pick([
      'sku', 'codigo interno', 'codigo_interno', 'codigo produto', 'referencia'
    ]),

    'categoria': pick([
      'categoria', 'category', 'cat'
    ]),

    'subcategoria': pick([
      'subcategoria', 'subcategory', 'subcat'
    ]),

    'peso': pick(['peso']),
    'custo': pick([
      'preco custo',
      'preco de custo',
      'preco_custo',
      'preco de custo unitario',
      'preco_custo_unitario',
      'custo',
      'custo real',
      'custo_real',
      'valor custo',
      'valor de custo',
    ]),
    'frete': pick(['frete']),
    'gastos_fixos': pick(['gastos fixos', 'gastos_fixos']),
    'gastos_variaveis': pick(['gastos variaveis', 'gastos_variaveis']),
    'preco_sugerido': pick(['preco sugerido', 'preco_sugerido']),
    'em_promocao': pick(['em promocao', 'em_promocao']),
    'percentual_promo': pick(['percentual promo', 'percentual_promo']),
    'valor_promo': pick(['valor promo', 'valor_promo']),
    'data_inicio_promo': pick(['data inicio promo', 'data_inicio_promo']),
    'data_fim_promo': pick(['data fim promo', 'data_fim_promo']),
    'marketplaces': pick(['marketplaces']),
    'publicar': pick(['publicar']),
  };

  if ((map['nome'] as String).isEmpty) return {};

  return map;
}

double? _toDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  var s = v.toString().trim();
  if (s.isEmpty) return null;
  // Remove símbolos de moeda e espaços: R$ 56,90 → 56,90
  s = s.replaceAll(RegExp(r'[R\$€USD\s]+', caseSensitive: false), '');
  if (s.isEmpty) return null;
  // Formato BR: 1.234,56 (milhar . decimal ,) ou 56,90
  final brMatch = RegExp(r'^(\d{1,3}(?:\.\d{3})*),(\d+)$').firstMatch(s);
  if (brMatch != null) {
    final parteInteira = brMatch.group(1)!.replaceAll('.', '');
    final parteDec = brMatch.group(2)!;
    return double.tryParse('$parteInteira.$parteDec');
  }
  // Formato US: 1,234.56 ou 56.90
  return double.tryParse(s.replaceAll(',', '.'));
}

int? _toInt(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString().replaceAll(RegExp(r'[^0-9]'), ''));
}

List<String> _splitList(dynamic v) {
  if (v == null) return [];
  return v
      .toString()
      .split(RegExp(r'[|,;]'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
}

String _slugify(String s) {
  return s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
}

DateTime? _parseDate(String dateStr) {
  if (dateStr.trim().isEmpty) return null;

  try {
    return DateTime.parse(dateStr);
  } catch (_) {
    final parts = dateStr.split('/');
    if (parts.length == 3) {
      final day = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final year = int.tryParse(parts[2]);
      if (day != null && month != null && year != null) {
        return DateTime(year, month, day);
      }
    }
  }
  return null;
}

Map<String, int> _parseEstoquePorTamanho(String raw) {
  final mapa = <String, int>{};
  if (raw.trim().isEmpty) return mapa;

  final partes = raw.split(RegExp(r'[;,]'));
  for (final parte in partes) {
    final t = parte.trim();
    if (t.isEmpty) continue;

    final m = RegExp(r'^(\S+)\s*[:=xX-]\s*(\d+)$').firstMatch(t);
    if (m == null) continue;

    final tamanho = m.group(1)!.trim();
    final qtd = int.tryParse(m.group(2)!.trim());
    if (tamanho.isEmpty || qtd == null || qtd <= 0) continue;

    mapa[tamanho] = qtd;
  }

  return mapa;
}

int _sumEstoquePorTamanho(Map<String, int> mapa) {
  var total = 0;
  for (final v in mapa.values) {
    total += v;
  }
  return total;
}

String _formatGradeTexto(Produto p) {
  final mapa = p.estoquePorTamanho.map((k, v) => MapEntry(k.toString(), v));

  if (mapa.isEmpty) {
    if (p.tamanhos.isNotEmpty) return p.tamanhos.join(', ');
    return 'Único';
  }

  final chaves = mapa.keys.toList()..sort((a, b) => a.compareTo(b));
  final partes = <String>[];
  for (final t in chaves) {
    final qtd = mapa[t] ?? 0;
    partes.add('$t ($qtd)');
  }
  return partes.join(' ? ');
}

  // ---------------------------------------------------------------------------
  // Statistics
  // ---------------------------------------------------------------------------

  /// Itens que compõem inventário físico. Combos (`ehCombo`) não entram: quantidade/valor
  /// já estão nos produtos componentes.
  Iterable<Produto> get _produtosInventarioFisico =>
      _box.values.where((p) => !p.ehCombo);

  int get _totalProdutos => _produtosInventarioFisico.length;
  int get _totalEstoque =>
      _produtosInventarioFisico.fold(0, (acc, p) => acc + p.quantidade);
  int get _totalPublicados => _box.values.where((p) => p.publicadoNoCatalogo).length;
  /// Custo total (custo real × quantidade; sem combos)
  double get _custoTotal => _produtosInventarioFisico.fold(
        0.0,
        (acc, p) => acc + p.custoTotalEstoque(),
      );
  /// Valor de venda total (preço final × quantidade; sem combos)
  double get _valorTotal => _produtosInventarioFisico.fold(
        0.0,
        (acc, p) => acc + (p.precoFinal * p.quantidade),
      );

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  Drawer _buildEstoqueDrawer() {
    final podeVoltar = Navigator.of(context).canPop();
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: _primaryColor.withOpacity(0.12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Icon(Icons.inventory_2, size: 40, color: _primaryColor),
                const SizedBox(height: 8),
                const Text(
                  'Estoque',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: _surfaceColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Ações e configurações',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          if (podeVoltar)
            ListTile(
              leading: const Icon(Icons.arrow_back),
              title: const Text('Voltar'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).pop();
              },
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Atalhos rápidos',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
          ),
          _drawerTile(
            icon: Icons.receipt_long_outlined,
            iconColor: _primaryColor,
            label: 'Compras — finalizar no estoque',
            onTap: () {
              Navigator.pop(context);
              Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      const CompraPipelinePendentesEstoqueScreen(),
                ),
              );
            },
          ),
          _drawerTile(
            icon: Icons.cloud_upload,
            iconColor: _successColor,
            label: _sincronizandoEstoque ? 'Enviando…' : 'Enviar para Nuvem',
            onTap: _sincronizandoEstoque
                ? null
                : () {
                    Navigator.pop(context);
                    _enviarParaFirestore();
                  },
          ),
          _drawerTile(
            icon: Icons.cloud_download,
            iconColor: const Color(0xFF3B82F6),
            label: _sincronizandoEstoque ? 'Baixando…' : 'Baixar da Nuvem',
            subtitle: _temDadosParaImportar == true
                ? 'Há produtos na nuvem para importar'
                : (_temDadosParaImportar == false
                    ? 'Sem novidades para importar'
                    : null),
            onTap: _sincronizandoEstoque
                ? null
                : () {
                    Navigator.pop(context);
                    _puxarDoFirestore();
                  },
          ),
          _drawerTile(
            icon: Icons.auto_awesome,
            iconColor: Colors.amber,
            label: 'Sugestões com IA (ofertas, compra, encalhados)',
            onTap: () {
              Navigator.pop(context);
              _abrirSugestoesIaEstoque();
            },
          ),
          _drawerTile(
            icon: Icons.preview,
            iconColor: _warningColor,
            label: 'Visualizar catálogo',
            onTap: () async {
              Navigator.pop(context);
              if (!mounted) return;
              final nav = Navigator.of(context);
              final lojaId = await LojaIdService.getWithTimeoutThenSessionFallback(
                timeout: kIsWeb
                    ? const Duration(seconds: 25)
                    : const Duration(seconds: 10),
              );
              if (lojaId == null || lojaId.isEmpty || !mounted) return;
              if (kIsWeb) {
                nav.pushNamed(
                  '/loja_preview',
                  arguments: <String, dynamic>{'lojaId': lojaId},
                );
                return;
              }
              nav.push(
                MaterialPageRoute(
                  builder: (_) => PublicCatalogScreen(
                    lojaId: lojaId,
                    preview: true,
                  ),
                ),
              );
            },
          ),
          _drawerTile(
            icon: Icons.qr_code_scanner,
            iconColor: _warningColor,
            label: 'Ler código de barras',
            onTap: () {
              Navigator.pop(context);
              _baixaPorCodigoBarras();
            },
          ),
          _drawerTile(
            icon: Icons.checklist,
            iconColor: _primaryColor,
            label: 'Marcar produtos em lote',
            onTap: () {
              Navigator.pop(context);
              _toggleModoSelecao();
            },
          ),
          const Divider(height: 24),
          _drawerTile(
            icon: Icons.layers_outlined,
            iconColor: Colors.orange,
            label: 'Cadastrar kit',
            onTap: () async {
              Navigator.pop(context);
              await _abrirNovoKitForm();
            },
          ),
          _drawerTile(
            icon: Icons.auto_awesome,
            iconColor: Colors.amber,
            label: 'Dicas com IA',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DicasIaScreen()),
              );
            },
          ),
          _drawerTile(
            icon: Icons.discount,
            iconColor: _successColor,
            label: _sugerindoPromocaoIa ? 'Gerando…' : 'Sugerir promoção (estoque parado)',
            onTap: _sugerindoPromocaoIa ? null : () {
              Navigator.pop(context);
              _sugerirPromocaoEstoqueParado();
            },
          ),
          _drawerTile(
            icon: Icons.file_upload_outlined,
            iconColor: _primaryColor,
            label: _importando ? 'Importando…' : 'Importar produtos',
            onTap: _importando ? null : () {
              Navigator.pop(context);
              _importarProdutos();
            },
          ),
          _drawerTile(
            icon: Icons.table_chart_outlined,
            iconColor: const Color(0xFFF59E0B),
            label: 'Modelo de planilha (editar e baixar)',
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(
                context,
                '/modelos_importacao',
                arguments: const {'tab': 0},
              );
            },
          ),
          _drawerTile(
            icon: Icons.cloud_sync_outlined,
            iconColor: _successColor,
            label: _publicando ? 'Sincronizando…' : 'Sincronizar rascunho',
            onTap: _publicando ? null : () {
              Navigator.pop(context);
              _sincronizarComDraft();
            },
          ),
          const Divider(height: 24),
          _drawerTile(
            icon: Icons.history,
            iconColor: _primaryColor,
            label: 'Histórico de movimentação',
            onTap: () async {
              Navigator.pop(context);
              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);
              final lojaId = await LojaIdService.getWithTimeoutThenSessionFallback(
                  timeout: kIsWeb ? const Duration(seconds: 25) : const Duration(seconds: 10));
              if (!mounted) return;
              if (lojaId == null || lojaId.trim().isEmpty) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Não foi possível identificar a loja. Tente novamente.'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              navigator.push(
                MaterialPageRoute(
                  builder: (_) => HistoricoMovimentacaoEstoqueScreen(
                    lojaId: lojaId,
                  ),
                ),
              );
            },
          ),
          _drawerTile(
            icon: Icons.download,
            iconColor: _primaryColor,
            label: 'Exportar estoque (Excel)',
            onTap: () {
              Navigator.pop(context);
              _exportarEstoque();
            },
          ),
          _drawerTile(
            icon: Icons.rocket_launch,
            iconColor: _primaryColor,
            label: 'Publicar TUDO no Live',
            onTap: () {
              Navigator.pop(context);
              _publicarTudoLive();
            },
          ),
          _drawerTile(
            icon: Icons.publish,
            iconColor: _successColor,
            label: 'Marcar todos (publicar)',
            onTap: () {
              Navigator.pop(context);
              _publicarTodosProdutos();
            },
          ),
          _drawerTile(
            icon: Icons.unpublished,
            iconColor: _warningColor,
            label: 'Desmarcar todos',
            onTap: () {
              Navigator.pop(context);
              _despublicarTodosProdutos();
            },
          ),
          const Divider(height: 24),
          _drawerTile(
            icon: Icons.merge_type,
            iconColor: _primaryColor,
            label: 'Unificar duplicados',
            onTap: _unificando
                ? null
                : () {
                    Navigator.pop(context);
                    _unificarDuplicados();
                  },
          ),
          _drawerTile(
            icon: Icons.image_not_supported,
            iconColor: _warningColor,
            label: 'Remover fotos repetidas (logo da loja)',
            onTap: () {
              Navigator.pop(context);
              _removerFotoLogoDosProdutos();
            },
          ),
          _drawerTile(
            icon: Icons.cleaning_services,
            iconColor: Colors.orange,
            label: _excluindoOrfaos
                ? 'Excluindo órfãos…'
                : 'Identificar e excluir produtos órfãos',
            onTap: _excluindoOrfaos
                ? null
                : () {
                    Navigator.pop(context);
                    _identificarEExcluirOrfaos();
                  },
          ),
          _drawerTile(
            icon: Icons.storefront,
            iconColor: Colors.blue,
            label: 'Configurar catálogo',
            onTap: () {
              Navigator.pop(context);
              _abrirConfigCatalogo();
            },
          ),
        ],
      ),
    );
  }

  ListTile _drawerTile({
    required IconData icon,
    required Color iconColor,
    required String label,
    VoidCallback? onTap,
    String? subtitle,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 22, color: iconColor),
      ),
      title: Text(label),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            )
          : null,
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_erroResolucaoLoja) {
      return Scaffold(
        appBar: AppBar(title: const Text('Estoque')),
        backgroundColor: _backgroundColor,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.cloud_off, size: 64, color: Colors.grey[400]),
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
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() { _erroResolucaoLoja = false; });
                    _setup();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Tentar novamente'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (!_ready) {
      return const Scaffold(
        backgroundColor: _backgroundColor,
        body: _EstoqueLoadingBody(primaryColor: _primaryColor),
      );
    }

    if (!_temPermissao) {
      return Scaffold(
        backgroundColor: _backgroundColor,
        appBar: AppBar(
          backgroundColor: _cardColor,
          elevation: 0,
          title: const Text("Acesso negado", style: TextStyle(color: _surfaceColor)),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: _surfaceColor),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: const _EstoqueAcessoNegadoBody(errorColor: _errorColor),
      );
    }

    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        backgroundColor: _cardColor,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.menu, color: _surfaceColor),
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              tooltip: 'Menu do estoque',
            ),
            if (Navigator.of(context).canPop())
              IconButton(
                icon: const Icon(Icons.arrow_back, color: _surfaceColor),
                onPressed: () => Navigator.pop(context),
                tooltip: 'Voltar',
              ),
          ],
        ),
        leadingWidth: Navigator.of(context).canPop() ? 112 : 56,
        titleSpacing: 8,
        centerTitle: false,
        title: _modoSelecao
            ? Text(
                '${_produtosSelecionados.length} selecionado(s)',
                style: const TextStyle(color: _surfaceColor, fontWeight: FontWeight.bold),
              )
            : Row(
                children: [
                  Expanded(child: _buildEstoqueAppBarSearchField()),
                ],
              ),
        actions: [
          if (_modoSelecao) ...[
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.check_box, color: _primaryColor, size: 20),
              ),
              onPressed: _selecionarTodos,
              tooltip: 'Selecionar todos',
            ),
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _errorColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.close, color: _errorColor, size: 20),
              ),
              onPressed: _toggleModoSelecao,
              tooltip: 'Cancelar seleção',
            ),
          ] else ...[
            IconButton(
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                minimumSize: const Size(40, 40),
                padding: const EdgeInsets.all(8),
              ),
              tooltip: _contagemFiltrosAtivos() > 0
                  ? 'Filtros (${_contagemFiltrosAtivos()} ativos)'
                  : 'Filtros',
              onPressed: _abrirPainelFiltros,
              icon: Badge(
                isLabelVisible: _contagemFiltrosAtivos() > 0,
                label: Text('${_contagemFiltrosAtivos()}'),
                child: const Icon(Icons.tune, color: _surfaceColor, size: 22),
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Ordenar',
              style: IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                minimumSize: const Size(40, 40),
                padding: const EdgeInsets.all(8),
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.sort, color: _surfaceColor, size: 22),
              onSelected: (v) => setState(() => _ordenacao = v),
              itemBuilder: (context) => [
                CheckedPopupMenuItem<String>(
                  value: 'nome_asc',
                  checked: _ordenacao == 'nome_asc',
                  child: const Text('Nome (A-Z)'),
                ),
                CheckedPopupMenuItem<String>(
                  value: 'nome_desc',
                  checked: _ordenacao == 'nome_desc',
                  child: const Text('Nome (Z-A)'),
                ),
                CheckedPopupMenuItem<String>(
                  value: 'preco_asc',
                  checked: _ordenacao == 'preco_asc',
                  child: const Text('Preço (menor)'),
                ),
                CheckedPopupMenuItem<String>(
                  value: 'preco_desc',
                  checked: _ordenacao == 'preco_desc',
                  child: const Text('Preço (maior)'),
                ),
                CheckedPopupMenuItem<String>(
                  value: 'qtd_asc',
                  checked: _ordenacao == 'qtd_asc',
                  child: const Text('Estoque (menor)'),
                ),
                CheckedPopupMenuItem<String>(
                  value: 'qtd_desc',
                  checked: _ordenacao == 'qtd_desc',
                  child: const Text('Estoque (maior)'),
                ),
              ],
            ),
          ],
          const AppHelpIconButton(iconColor: _surfaceColor),
        ],
        bottom: (_importando && _importTotal > 0) || _exportandoEstoque || _syncEmBackground
            ? PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(
                      value: (_importando && _importTotal > 0) ? _importProgress / _importTotal : null,
                      backgroundColor: _primaryColor.withOpacity(0.2),
                      valueColor: const AlwaysStoppedAnimation<Color>(_primaryColor),
                    ),
                  ],
                ),
              )
            : null,
      ),
      drawer: _buildEstoqueDrawer(),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_catalogoPrecisaAtualizar) ...[
            FloatingActionButton.extended(
              heroTag: 'fab_atualizar_catalogo',
              onPressed: _publicando ? null : _publicarTudoLive,
              backgroundColor: _successColor,
              icon: _publicando
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.cloud_upload, color: Colors.white),
              label: Text(
                _publicando ? 'Publicando...' : 'Atualizar catálogo',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 12),
          ],
          FloatingActionButton(
            heroTag: 'fab_ia_estoque',
            onPressed: _abrirSugestoesIaEstoque,
            tooltip: 'Sugestões com IA (ofertas, compra, encalhados)',
            backgroundColor: Colors.amber,
            mini: true,
            child: const Icon(Icons.auto_awesome, color: Colors.black87),
          ),
          const SizedBox(height: 12),
          _modoSelecao && _produtosSelecionados.isNotEmpty
              ? FloatingActionButton.extended(
                  heroTag: 'fab_acoes_estoque',
                  onPressed: _publicando ? null : _mostrarMenuAcoes,
                  backgroundColor: _primaryColor,
                  icon: _publicando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.flash_on, color: Colors.white),
                  label: Text(
                    _publicando ? 'Processando...' : 'Ações',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                )
              : FloatingActionButton.extended(
                  heroTag: 'fab_novo_produto',
                  onPressed: _mostrarEscolhaNovoProduto,
                  backgroundColor: _primaryColor,
                  icon: const Icon(Icons.add, color: Colors.white),
                  label: const Text('Novo Produto', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                ),
        ],
      ),
      body: Stack(
        children: [
          // FIX ParentDataWidget: Column inside Stack gets unbounded constraints.
          // Wrap in Positioned.fill so Expanded receives bounded height.
          Positioned.fill(
            child: Column(
              children: [
              // Banner sincronizando marketplace
              if (_sincronizandoMarketplace && _marketplaceEmSync != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                  color: _primaryColor.withOpacity(0.12),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: _primaryColor),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Sincronizando com $_marketplaceEmSync...',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: _surfaceColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_comprasRevendaPendentesCount > 0)
                MaterialBanner(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  leading: const Icon(Icons.inventory_2_outlined, color: _warningColor),
                  content: Text(
                    '$_comprasRevendaPendentesCount compra(s) de revenda aguardando '
                    'detalhamento de produtos.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: _abrirComprasRevendaPendentes,
                      child: const Text('Ver compras'),
                    ),
                  ],
                ),
              // Statistics Header
              _buildStatisticsHeader(currencyFormat),

              // Products List
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _setup,
                  child: ValueListenableBuilder(
                    valueListenable: _box.listenable(),
                    builder: (_, Box<Produto> box, __) {
                      final q = _debouncedSearchQuery;
                      final limite24h = DateTime.now().subtract(const Duration(hours: 24));

                      var itens = box.values.where((p) {
                        if (q.isNotEmpty &&
                            !(_norm(p.nome).contains(q) ||
                                _norm(p.descricao).contains(q) ||
                                _norm(p.categoria).contains(q) ||
                                _norm(p.subcategoria).contains(q) ||
                                _norm(p.slug).contains(q) ||
                                _norm(p.codigoBarras).contains(q))) {
                          return false;
                        }
                        if (_filtroCategoria != null && _filtroCategoria!.isNotEmpty &&
                            _norm(p.categoria) != _norm(_filtroCategoria!)) {
                          return false;
                        }
                        if (_filtroSubcategoria != null && _filtroSubcategoria!.isNotEmpty &&
                            _norm(p.subcategoria) != _norm(_filtroSubcategoria!)) {
                          return false;
                        }
                        if (_filtroPublicado != null && p.publicadoNoCatalogo != _filtroPublicado) {
                          return false;
                        }
                        if (_filtroSemFotos && p.imagens.isNotEmpty) return false;
                        if (_filtroRecentementeAlterados) {
                          if (p.updatedAt == null) return false;
                          if (p.updatedAt!.isBefore(limite24h)) return false;
                        }
                        return true;
                      }).toList();

                      switch (_ordenacao) {
                        case 'nome_desc':
                          itens.sort((a, b) => _norm(b.nome).compareTo(_norm(a.nome)));
                          break;
                        case 'preco_asc':
                          itens.sort((a, b) => (a.precoFinal > 0 ? a.precoFinal : a.precoUnitario)
                              .compareTo(b.precoFinal > 0 ? b.precoFinal : b.precoUnitario));
                          break;
                        case 'preco_desc':
                          itens.sort((a, b) => (b.precoFinal > 0 ? b.precoFinal : b.precoUnitario)
                              .compareTo(a.precoFinal > 0 ? a.precoFinal : a.precoUnitario));
                          break;
                        case 'qtd_asc':
                          itens.sort((a, b) => a.quantidade.compareTo(b.quantidade));
                          break;
                        case 'qtd_desc':
                          itens.sort((a, b) => b.quantidade.compareTo(a.quantidade));
                          break;
                        default:
                          itens.sort((a, b) => _norm(a.nome).compareTo(_norm(b.nome)));
                      }

                      if (itens.isEmpty) {
                        return ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(height: MediaQuery.of(context).size.height * 0.15),
                            _buildEmptyState(),
                          ],
                        );
                      }

                      return ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      itemCount: itens.length,
                      itemBuilder: (_, i) {
                        final p = itens[i];
                        // Usar HiveObject.key diretamente (mais confiável que comparação de objetos)
                        final key = p.key;
                        // Só usar keys válidas (não nulas e não vazias)
                        if (key == null) {
                          return const SizedBox.shrink(); // Produto sem key válida
                        }
                        final keyStr = key.toString();
                        final selecionado = _produtosSelecionados.contains(keyStr);

                        return _buildProdutoCard(p, keyStr, selecionado, currencyFormat);
                      },
                    );
                  },
                ),
                ),
              ),
            ],
          ),
        ),
          if (_importando || _publicando)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.3),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: _cardColor,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: _primaryColor),
                        const SizedBox(height: 16),
                        Text(
                          _importando ? 'Importando produtos...' : 'Processando...',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                        ),
                        if (_importando && _importTotal > 0) ...[
                          const SizedBox(height: 12),
                          Text(
                            '$_importProgress de $_importTotal',
                            style: const TextStyle(
                              color: _primaryColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 18,
                            ),
                          ),
                          if (_importCriados > 0 || _importAtualizados > 0) ...[
                            const SizedBox(height: 8),
                            Text(
                              '? $_importCriados novos ? $_importAtualizados atualizados${_importErros > 0 ? " ? $_importErros ignorados" : ""}',
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 13,
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            'Aguarde… pode levar vários minutos.',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Campo de pesquisa na [AppBar] (mesmo controller, debounce e filtro da lista).
  Widget _buildEstoqueAppBarSearchField() {
    return ValueListenableBuilder<String>(
      valueListenable: _searchTextNotifier,
      builder: (_, searchText, __) {
        return Material(
          color: _backgroundColor,
          borderRadius: BorderRadius.circular(10),
          child: TextField(
            controller: _pesquisaController,
            style: const TextStyle(fontSize: 15, color: _surfaceColor),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Pesquisar produtos...',
              hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
              prefixIcon: Icon(Icons.search, color: Colors.grey[400], size: 22),
              prefixIconConstraints: const BoxConstraints(minWidth: 40, maxHeight: 40),
              suffixIcon: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 40),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      tooltip: 'Ler código de barras',
                      icon: Icon(Icons.qr_code_scanner, color: Colors.grey[500], size: 22),
                      onPressed: () async {
                        final code = await BarcodeScannerScreen.scan(context);
                        if (code != null && code.isNotEmpty && mounted) {
                          _pesquisaController.text = code;
                        }
                      },
                    ),
                    if (searchText.isNotEmpty)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                        icon: Icon(Icons.clear, color: Colors.grey[500], size: 22),
                        onPressed: () => _pesquisaController.clear(),
                      ),
                  ],
                ),
              ),
              suffixIconConstraints: const BoxConstraints(maxHeight: 40),
              filled: false,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatisticsHeader(NumberFormat currencyFormat) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 520;
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 6, 12, 8),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_primaryColor, _primaryColor.withOpacity(0.82)],
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: _primaryColor.withOpacity(0.22),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.inventory_2, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Estoque',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Total em estoque: $_totalEstoque itens',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        'Publicados',
                        '$_totalPublicados',
                        Icons.storefront,
                        compact: true,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildStatCard(
                        'Custo total',
                        currencyFormat.format(_custoTotal),
                        Icons.shopping_cart,
                        compact: true,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildStatCard(
                        'Valor de venda',
                        currencyFormat.format(_valorTotal),
                        Icons.attach_money,
                        compact: true,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildStatCard(
                        'Qtd. produtos',
                        '$_totalProdutos',
                        Icons.layers_outlined,
                        compact: true,
                      ),
                    ),
                  ],
                )
              else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        'Publicados',
                        '$_totalPublicados',
                        Icons.storefront,
                        compact: true,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildStatCard(
                        'Custo total',
                        currencyFormat.format(_custoTotal),
                        Icons.shopping_cart,
                        compact: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        'Valor de venda',
                        currencyFormat.format(_valorTotal),
                        Icons.attach_money,
                        compact: true,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildStatCard(
                        'Qtd. produtos',
                        '$_totalProdutos',
                        Icons.layers_outlined,
                        compact: true,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, {bool compact = false}) {
    final pad = compact ? 8.0 : 12.0;
    final iconSize = compact ? 18.0 : 20.0;
    final labelSize = compact ? 10.0 : 11.0;
    final valueSize = compact ? 12.5 : 14.0;
    return Container(
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(compact ? 10 : 12),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: iconSize),
          SizedBox(width: compact ? 6 : 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(color: Colors.white.withOpacity(0.82), fontSize: labelSize),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: valueSize,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final isSearch = _debouncedSearchQuery.isNotEmpty;
    if (isSearch) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[400]),
            ),
            const SizedBox(height: 24),
            Text(
              'Nenhum produto encontrado',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              'Tente ajustar a busca',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _primaryColor.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.inventory_2_outlined, size: 56, color: _primaryColor),
            ),
            const SizedBox(height: 24),
            Text(
              'Nenhum produto cadastrado',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: _surfaceColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Adicione seu primeiro produto para começar',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _surfaceColor.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _mostrarEscolhaNovoProduto,
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Adicionar produto'),
              style: FilledButton.styleFrom(
                backgroundColor: _primaryColor,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProdutoCard(Produto p, String key, bool selecionado, NumberFormat currencyFormat) {
    final thumb = p.imagens.isNotEmpty ? p.imagens.first : '';
    final gradeTexto = _formatGradeTexto(p);
    final avatarColor = _getAvatarColor(p.nome);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        border: selecionado
            ? Border.all(color: _primaryColor, width: 2)
            : null,
        boxShadow: [
          BoxShadow(
            color: selecionado
                ? _primaryColor.withOpacity(0.2)
                : Colors.black.withOpacity(0.05),
            blurRadius: selecionado ? 10 : 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _modoSelecao
              ? () => _toggleSelecaoProduto(key)
              : () => _abrirForm(produto: p),
          onLongPress: !_modoSelecao
              ? () {
                  setState(() => _modoSelecao = true);
                  _toggleSelecaoProduto(key);
                }
              : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Checkbox ou Thumbnail
                if (_modoSelecao)
                  Container(
                    margin: const EdgeInsets.only(right: 12),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: selecionado ? _primaryColor : Colors.transparent,
                      border: Border.all(
                        color: selecionado ? _primaryColor : Colors.grey,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: selecionado
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : null,
                  )
                else
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 70,
                      height: 70,
                      child: thumb.isEmpty
                          ? Container(
                              color: avatarColor.withOpacity(0.1),
                              child: Icon(Icons.image_outlined, color: avatarColor),
                            )
                          : Image(
                              image: (kIsWeb && thumb.startsWith('blob:'))
                                  ? const AssetImage('assets/images/placeholder.png')
                                  : (thumb.startsWith('http') || kIsWeb)
                                      ? NetworkImage(thumb) as ImageProvider
                                      : FileImage(io.File(thumb)) as ImageProvider,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: avatarColor.withOpacity(0.1),
                                child: Icon(Icons.broken_image, color: avatarColor),
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
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              p.nome,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: _surfaceColor,
                              ),
                            ),
                          ),
                          if (p.publicadoNoCatalogo) ...[
                            const SizedBox(width: 4),
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: _successColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.storefront, size: 11, color: _successColor),
                                    SizedBox(width: 3),
                                    Flexible(
                                      child: Text(
                                        'Pub',
                                        style: TextStyle(
                                          color: _successColor,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (p.categoria.isNotEmpty || p.subcategoria.isNotEmpty)
                        Text(
                          [p.categoria, p.subcategoria].where((s) => s.isNotEmpty).join(' / '),
                          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                        ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          if (p.estoquePorTamanho.isEmpty)
                            _ehKitVirtualPorReceitaExibicao(p)
                                ? _buildInfoChip(
                                    Icons.layers_outlined,
                                    _chipKitReceitaLabel,
                                    const Color(0xFF64748B),
                                  )
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _buildInfoChip(
                                        Icons.inventory,
                                        'Qtd: ${p.quantidade}${p.quantidade > 0 && p.quantidade < 3 ? ' ⚠️' : ''}',
                                        p.quantidade == 0
                                            ? _errorColor
                                            : (p.quantidade < 3 ? _warningColor : _primaryColor),
                                      ),
                                      const SizedBox(width: 4),
                                      Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(6),
                                          onTap: () => _ajustarQuantidade(p, -1),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: _primaryColor.withOpacity(0.15),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: const Icon(Icons.remove, size: 14, color: _primaryColor),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(6),
                                          onTap: () => _ajustarQuantidade(p, 1),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: _successColor.withOpacity(0.15),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: const Icon(Icons.add, size: 14, color: _successColor),
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                          else
                            _ehKitVirtualPorReceitaExibicao(p)
                                ? _buildInfoChip(
                                    Icons.layers_outlined,
                                    _chipKitReceitaLabel,
                                    const Color(0xFF64748B),
                                  )
                                : _buildInfoChip(
                                    Icons.inventory,
                                    'Qtd: ${p.quantidade}${p.quantidade > 0 && p.quantidade < 3 ? ' ⚠️' : ''}',
                                    p.quantidade == 0
                                        ? _errorColor
                                        : (p.quantidade < 3 ? _warningColor : _primaryColor),
                                  ),
                          if (gradeTexto != 'Único')
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 150),
                              child: Text(
                                gradeTexto,
                                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        currencyFormat.format(p.precoFinal),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _successColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Actions
                if (!_modoSelecao)
                  Column(
                    children: [
                      IconButton(
                        icon: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: _primaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.edit, color: _primaryColor, size: 18),
                        ),
                        onPressed: () => _abrirForm(produto: p),
                        tooltip: 'Editar',
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: 4),
                      IconButton(
                        icon: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: _warningColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.copy, color: _warningColor, size: 18),
                        ),
                        onPressed: () => _duplicarProduto(p),
                        tooltip: 'Duplicar',
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: 4),
                      IconButton(
                        icon: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: _errorColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.delete_outline, color: _errorColor, size: 18),
                        ),
                        onPressed: () => _remover(p),
                        tooltip: 'Remover',
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

  int _contagemFiltrosAtivos() {
    var n = 0;
    if (_filtroCategoria != null && _filtroCategoria!.trim().isNotEmpty) n++;
    if (_filtroSubcategoria != null && _filtroSubcategoria!.trim().isNotEmpty) {
      n++;
    }
    if (_filtroPublicado != null) n++;
    if (_filtroSemFotos) n++;
    if (_filtroRecentementeAlterados) n++;
    return n;
  }

  void _abrirPainelFiltros() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.72,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          expand: false,
          builder: (_, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: _cardColor,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x1A000000),
                    blurRadius: 12,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: ValueListenableBuilder<Box<Produto>>(
                valueListenable: _box.listenable(),
                builder: (_, Box<Produto> box, __) {
                  // Unifica por forma canônica: "Anel"/"anel" → uma entrada "Anel".
                  final catNormToCanon = <String, String>{};
                  for (final p in box.values) {
                    final c = p.categoria.trim();
                    if (c.isEmpty) continue;
                    final n = _norm(c);
                    catNormToCanon[n] = canonicalizeCategoria(c);
                  }
                  final categorias = catNormToCanon.values.toList()
                    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

                  final subNormToCanon = <String, String>{};
                  for (final p in box.values) {
                    if (_filtroCategoria != null &&
                        _norm(p.categoria) != _norm(_filtroCategoria!)) {
                      continue;
                    }
                    final s = p.subcategoria.trim();
                    if (s.isEmpty) continue;
                    final n = _norm(s);
                    subNormToCanon[n] = canonicalizeCategoria(s);
                  }
                  final subcategorias = subNormToCanon.values.toList()
                    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
                  return ListView(
                    controller: scrollController,
                    padding: EdgeInsets.fromLTRB(
                      16,
                      12,
                      16,
                      16 + MediaQuery.paddingOf(sheetContext).bottom,
                    ),
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.filter_list, color: _primaryColor),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Filtros',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(sheetContext),
                            tooltip: 'Fechar',
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _buildFiltroFieldLabel('Categoria do produto'),
                      const SizedBox(height: 6),
                      _buildFilterDropdown<String?>(
                        value: _filtroCategoria,
                        hint: 'Categoria',
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('Todas as categorias'),
                          ),
                          ...categorias.map(
                            (c) => DropdownMenuItem(
                              value: c,
                              child: Text(c, overflow: TextOverflow.ellipsis),
                            ),
                          ),
                        ],
                        onChanged: (v) => setState(() {
                          _filtroCategoria = v;
                          if (_filtroSubcategoria != null &&
                              (v == null ||
                                  !subcategorias.contains(_filtroSubcategoria))) {
                            _filtroSubcategoria = null;
                          }
                        }),
                      ),
                      const SizedBox(height: 14),
                      _buildFiltroFieldLabel('Subcategoria'),
                      const SizedBox(height: 6),
                      _buildFilterDropdown<String?>(
                        value: _filtroSubcategoria,
                        hint: 'Subcategoria',
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('Todas as subcategorias'),
                          ),
                          ...subcategorias.map(
                            (s) => DropdownMenuItem(
                              value: s,
                              child: Text(s, overflow: TextOverflow.ellipsis),
                            ),
                          ),
                        ],
                        onChanged: (v) =>
                            setState(() => _filtroSubcategoria = v),
                      ),
                      const SizedBox(height: 14),
                      _buildFiltroFieldLabel('Visível no catálogo online'),
                      const SizedBox(height: 6),
                      _buildFilterDropdown<bool?>(
                        value: _filtroPublicado,
                        hint: 'Publicação',
                        items: const [
                          DropdownMenuItem(
                            value: null,
                            child: Text('Qualquer (publicado ou não)'),
                          ),
                          DropdownMenuItem(
                            value: true,
                            child: Text('Só publicados'),
                          ),
                          DropdownMenuItem(
                            value: false,
                            child: Text('Só não publicados'),
                          ),
                        ],
                        onChanged: (v) => setState(() => _filtroPublicado = v),
                      ),
                      const SizedBox(height: 4),
                      SwitchListTile(
                        title: const Text('Só produtos sem fotos'),
                        value: _filtroSemFotos,
                        onChanged: (v) => setState(() => _filtroSemFotos = v),
                        thumbColor: MaterialStateProperty.resolveWith((s) =>
                            s.contains(MaterialState.selected) ? _warningColor : null),
                      ),
                      SwitchListTile(
                        title: const Text('Alterados nas últimas 24 horas'),
                        subtitle: Text(
                          'Com base em data de atualização do produto',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                        value: _filtroRecentementeAlterados,
                        onChanged: (v) => setState(
                          () => _filtroRecentementeAlterados = v,
                        ),
                        thumbColor: MaterialStateProperty.resolveWith((s) =>
                            s.contains(MaterialState.selected) ? _primaryColor : null),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _filtroCategoria = null;
                                _filtroSubcategoria = null;
                                _filtroPublicado = null;
                                _filtroSemFotos = false;
                                _filtroRecentementeAlterados = false;
                              });
                            },
                            child: const Text('Limpar tudo'),
                          ),
                          const Spacer(),
                          FilledButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            child: const Text('Concluir'),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFiltroFieldLabel(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.grey[800],
        ),
      ),
    );
  }

  Widget _buildFilterDropdown<T>({
    required T? value,
    required String hint,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          hint: Text(hint, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          icon: const Icon(Icons.filter_list, color: _primaryColor, size: 18),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  /// Combos/kits por receita: a baixa é nos componentes; não exibir [quantidade] do cadastro como estoque físico do kit.
  bool _ehKitVirtualPorReceitaExibicao(Produto p) {
    return p.ehCombo ||
        (p.itensCombo != null && p.itensCombo!.isNotEmpty) ||
        p.temComboConfigEfetivo;
  }

  static const String _chipKitReceitaLabel = 'Kit por receita · pelos itens';

  Widget _buildInfoChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
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
}

/// Widget apenas visual: estado de carregamento da tela de estoque.
class _EstoqueLoadingBody extends StatelessWidget {
  final Color primaryColor;

  const _EstoqueLoadingBody({required this.primaryColor});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: CircularProgressIndicator(color: primaryColor),
          ),
          const SizedBox(height: 24),
          Text(
            'Carregando estoque...',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}

/// Widget apenas visual: corpo do estado "Acesso negado" (sem callback).
class _EstoqueAcessoNegadoBody extends StatelessWidget {
  final Color errorColor;

  const _EstoqueAcessoNegadoBody({required this.errorColor});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: errorColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.lock, size: 64, color: errorColor),
          ),
          const SizedBox(height: 24),
          Text(
            'Você não tem permissão',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}

/// Tela cheia de sugestões com IA – Estoque (ofertas, compra, encalhados).
class _SugestoesIaEstoqueScreen extends StatefulWidget {
  final String resumoInicial;
  final String lojaId;

  const _SugestoesIaEstoqueScreen({
    required this.resumoInicial,
    required this.lojaId,
  });

  @override
  State<_SugestoesIaEstoqueScreen> createState() => _SugestoesIaEstoqueScreenState();
}

class _SugestoesIaEstoqueScreenState extends State<_SugestoesIaEstoqueScreen> {
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
        title: const Text('IA – Estoque', style: TextStyle(color: Colors.white)),
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
              'Sugestões de ofertas, compra e alertas. Os dados do estoque já foram enviados para a IA.',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _enviando ? null : () => _enviar('Sugestões de oferta ou promoção para escoar estoque. Quais produtos promover e como?'),
                  icon: const Icon(Icons.discount, size: 18),
                  label: const Text('Sugestões de oferta'),
                  style: FilledButton.styleFrom(backgroundColor: _primaryColor.withOpacity(0.2)),
                ),
                FilledButton.tonalIcon(
                  onPressed: _enviando ? null : () => _enviar('Sugestão de compra ou reposição. Quais produtos repor com base no estoque atual?'),
                  icon: const Icon(Icons.shopping_cart, size: 18),
                  label: const Text('Sugestão de compra'),
                  style: FilledButton.styleFrom(backgroundColor: _primaryColor.withOpacity(0.2)),
                ),
                FilledButton.tonalIcon(
                  onPressed: _enviando ? null : () => _enviar('Quais produtos parecem encalhados ou parados? Dê alertas e sugestões para movimentar.'),
                  icon: const Icon(Icons.warning_amber, size: 18),
                  label: const Text('Alertas produtos encalhados'),
                  style: FilledButton.styleFrom(backgroundColor: _primaryColor.withOpacity(0.2)),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _perguntaCtrl,
              decoration: InputDecoration(
                hintText: 'Ex: Qual categoria tem mais estoque parado?',
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
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
                  color: _primaryColor.withOpacity(0.1),
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

