// lib/screens/produto_form_screen.dart

import 'dart:async';
import 'dart:io' as io if (dart.library.html) 'package:master_palm/utils/io_stub.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:image_picker/image_picker.dart';

import '../core/compra_item_pipeline_constants.dart';
import '../core/logger.dart';
import '../core/hive_box_names.dart';
import '../core/produto_variacao_extra.dart';
import '../models/compra_item_pipeline.dart';
import '../models/produto.dart';
import '../services/compra_item_pipeline_store.dart';
import '../utils/moeda_input_formatter.dart';
import '../utils/text_utils.dart';
import '../services/catalogo_sync_service.dart' show CatalogoSyncService, SyncTarget;
import '../services/catalog_publish_service.dart';
import '../services/limits_guard.dart';
import '../services/produto_estoque_doc_id_service.dart';
import '../services/produto_exclusao_tombstone_service.dart';
import '../services/produto_sync_fila_retry_service.dart';
import '../services/produtos_firestore_service.dart';
import '../services/produto_imagens_storage_cleanup.dart';
import '../services/produto_upsert_service.dart';
import '../utils/ean13_generator.dart';
import '../services/loja_id_service.dart';
import '../services/upload_manager.dart';
import '../services/ai_loja_service.dart';
import '../services/ia_uso_limite_service.dart';
import '../services/image_upload_service.dart';
import '../services/catalog_thumbnail_service.dart';
import '../debug/boot_perf_log.dart';
import '../widgets/compra_pipeline_origem_cancelada_notice.dart';
import 'barcode_scanner_screen.dart';

/// Escolha ao salvar "novo" produto quando já existe mesmo nome+categoria.
enum _DuplicataSalvarEscolha { atualizar, criarNovo, cancelar }

// ------------------------------
// FUNÇÃO PARA GERAR SLUG
// ------------------------------
String gerarSlug(String texto) {
  return texto
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
}

/// Chave em [Produto.precoPorTamanho] / [variacoes] quando o tamanho na grade está vazio.
String produtoFormTamanhoKeyPrecoPorTamanho(String tamanhoCampo) {
  final t = tamanhoCampo.trim();
  return t.isEmpty ? 'sem-tamanho' : t;
}

Map<String, double> produtoFormBuildPrecoPorTamanhoFromControllers(
  Map<String, TextEditingController> controllers,
) {
  final out = <String, double>{};
  for (final e in controllers.entries) {
    final key = produtoFormTamanhoKeyPrecoPorTamanho(e.key);
    final v = MoedaInputFormatter.parse(e.value.text);
    if (v > 0) out[key] = v;
  }
  return out;
}

/// Agrega linhas da grade em [variacoes] / [variacoesExtraTipo] (retrocompatível).
({Map<String, dynamic> variacoes, Map<String, dynamic>? variacoesExtraTipo})
    produtoFormMergeVariacoesGrade(
        List<Map<String, TextEditingController>> rows) {
  final acc = <String, Map<String, Map<String, dynamic>>>{};
  final tiposAcc = <String, Map<String, Map<String, String>>>{};

  for (final c in rows) {
    final tamanho = (c['tamanho']?.text ?? '').trim();
    final cor = (c['cor']?.text ?? '').trim();
    final extraTipo = (c['extraTipo']?.text ?? '').trim();
    final extraValor = (c['extraValor']?.text ?? '').trim();
    final custoStr = (c['custo']?.text ?? '').trim();
    final qStr = (c['qtd']?.text ?? '').trim();
    if (qStr.isEmpty || (tamanho.isEmpty && cor.isEmpty)) continue;
    final qtd = int.tryParse(qStr) ?? 0;
    if (qtd <= 0) continue;
    final chaveTamanho = tamanho.isEmpty ? 'sem-tamanho' : tamanho;
    final corFinal = cor.isEmpty ? 'sem-cor' : cor;
    final ek = extraValor.isEmpty ? ProdutoVariacaoExtra.kSemExtraKey : extraValor;

    acc.putIfAbsent(chaveTamanho, () => {});
    acc[chaveTamanho]!.putIfAbsent(corFinal, () => {});
    acc[chaveTamanho]![corFinal]![ek] = qtd;
    final custoUnitario = MoedaInputFormatter.parse(custoStr);
    if (custoUnitario > 0) {
      acc[chaveTamanho]![corFinal]![ProdutoVariacaoExtra.kMetaCustoUnitarioKey] =
          custoUnitario;
    }

    if (ek.isNotEmpty) {
      tiposAcc.putIfAbsent(chaveTamanho, () => {});
      tiposAcc[chaveTamanho]!.putIfAbsent(corFinal, () => {});
      final label =
          extraTipo.isEmpty ? kVariacaoExtraTipoFallback : extraTipo;
      tiposAcc[chaveTamanho]![corFinal]![ek] = label;
    }
  }

  final variacoesMap = <String, dynamic>{};
  for (final te in acc.entries) {
    final innerOut = <String, dynamic>{};
    for (final ce in te.value.entries) {
      final m = ce.value;
      if (m.isEmpty) continue;
      final hasMetaCusto =
          m.containsKey(ProdutoVariacaoExtra.kMetaCustoUnitarioKey);
      if (!hasMetaCusto &&
          m.length == 1 &&
          (m.containsKey(ProdutoVariacaoExtra.kSemExtraKey) ||
              m.containsKey(ProdutoVariacaoExtra.kSemExtraKeyLegacy) ||
              m.containsKey(''))) {
        innerOut[ce.key] = m[ProdutoVariacaoExtra.kSemExtraKey] ??
            m[ProdutoVariacaoExtra.kSemExtraKeyLegacy] ??
            m[''] ??
            0;
      } else {
        innerOut[ce.key] = Map<String, dynamic>.from(m);
      }
    }
    if (innerOut.isNotEmpty) variacoesMap[te.key] = innerOut;
  }

  Map<String, dynamic>? tiposOut;
  for (final te in tiposAcc.entries) {
    final inner = <String, dynamic>{};
    for (final ce in te.value.entries) {
      if (ce.value.isNotEmpty) {
        inner[ce.key] = Map<String, dynamic>.from(ce.value);
      }
    }
    if (inner.isNotEmpty) {
      tiposOut ??= {};
      tiposOut[te.key] = inner;
    }
  }

  return (variacoes: variacoesMap, variacoesExtraTipo: tiposOut);
}

class ProdutoFormScreen extends StatefulWidget {
  final Produto? produto;
  /// DocId do pipeline (`compraId_itemCompraId`) — finalização pós-compra.
  final String? compraPipelineDocId;
  /// Quando true, [Navigator.pop] após salvar devolve o [Produto] salvo (ex.: fluxo de compra).
  /// O padrão é `false` para compatibilidade com rotas abertas com `push<bool>`.
  final bool returnProductOnSave;

  const ProdutoFormScreen({
    super.key,
    this.produto,
    this.compraPipelineDocId,
    this.returnProductOnSave = false,
  });

  @override
  State<ProdutoFormScreen> createState() => _ProdutoFormScreenState();
}

class _ProdutoFormScreenState extends State<ProdutoFormScreen> {
  final _form = GlobalKey<FormState>();

  late Box<Produto> produtosBox;
  late Box _configBox;
  String? lojaId;
  List<Map<String, dynamic>> _embalagensDisponiveis = [];

  final _nome = TextEditingController();
  final _quantidade = TextEditingController(text: '1');
  final _estoqueMinimo = TextEditingController(text: '0');
  final _fornecedor = TextEditingController();
  final _custo = TextEditingController();
  final _preco = TextEditingController();
  final _categoria = TextEditingController();
  final _subcategoria = TextEditingController();
  final _categoriaExtraInput = TextEditingController();
  final _subcategoriaExtraInput = TextEditingController();
  final Set<String> _categoriasExtrasSelecionadas = <String>{};
  final Set<String> _subcategoriasExtrasSelecionadas = <String>{};
  final _descricao = TextEditingController();
  final _peso = TextEditingController(text: '0');
  /// Unidade do peso: 'g' (padrão) ou 'kg'
  String _pesoUnidade = 'g';
  final _codigoBarras = TextEditingController();
  String _tipoEmbalagem = 'padrao';

  /// Grade: tamanho, cor, extraTipo, extraValor, qtd
  List<Map<String, String>> _gradeVariacoes = [
    {
      'tamanho': '',
      'cor': '',
      'extraTipo': '',
      'extraValor': '',
      'qtd': '',
      'custo': '',
    },
  ];

  /// Controllers das linhas de variação para garantir leitura correta ao salvar (tamanho, cor, qtd).
  final List<Map<String, TextEditingController>> _variacaoControllers = [];

  /// Preço por tamanho (ex: P=50, M=75, G=100). Chave = tamanho, valor = controller do preço.
  final Map<String, TextEditingController> _precoPorTamanhoCtrl = {};

  final _imagens = <String>[];
  /// Preview local (web) enquanto upload pendente — chave `pending://…`.
  final Map<String, Uint8List> _previewBytes = {};
  final Set<String> _uploadCancelPending = {};
  final Map<String, DateTime> _fotoPendenteInicio = {};
  final Set<String> _fotoPendenteEnviando = {};
  final Set<String> _fotoAviso3sLogged = {};
  final Set<String> _fotoAviso8sLogged = {};
  Timer? _fotoPendenteUiTimer;
  int _fotosEmUpload = 0;
  bool _publicar = false;
  final UploadManager _uploader = UploadManager(maxConcurrent: 3);
  bool _salvando = false;
  bool _sugerindoDescricao = false;

  CompraItemPipeline? _bootstrapPipeline;

  /// Só para aviso visual: concluído + compra cancelada depois (não altera fluxo de salvamento).
  CompraItemPipeline? _pipelineOrigemCancelada;

  /// Evita várias gravações em paralelo ao reordenar imagens (corrida na nuvem).
  Timer? _debouncePersistImagens;

  /// Aviso: possível duplicata (nome+categoria). O save exige diálogo — não mescla sozinho.
  Produto? _duplicataDetectada;

  /// Produto só com estoque/tamanhos legados (sem [variacoes] persistidas).
  bool _legadoEstoqueSemVariacoesCadastradas = false;

  /// Baseline de chaves `V::` / `T::` ao abrir o form (só quando havia [variacoes] persistidas).
  /// Usado para tombstone explícito ao remover linha(s) da grade e salvar — não é diff remoto/local.
  bool _tombSessaoAplicaVarTomb = false;
  Set<String> _tombSessaoV = {};
  Set<String> _tombSessaoT = {};

  void _logDiagnosticoVariacoes({
    required String evento,
    required String productId,
    required Map<String, dynamic> variacoes,
  }) {
    debugPrint('[VARIACAO_CUSTO][$evento] productId=$productId variacoes=${variacoes.length}');
    for (final te in variacoes.entries) {
      final tamanho = te.key;
      final mapaCores = te.value;
      if (mapaCores is! Map) continue;
      for (final ce in mapaCores.entries) {
        final cor = ce.key.toString();
        final cell = ce.value;
        final custo = ProdutoVariacaoExtra.custoUnitarioNaCelula(cell);
        final qtd = ProdutoVariacaoExtra.somarCelula(cell);
        debugPrint(
          '[VARIACAO_CUSTO][$evento] tam=$tamanho cor=$cor qtd=$qtd custo=${custo?.toStringAsFixed(2) ?? 'fallback'}',
        );
      }
    }
  }

  // Marketplaces selecionados
  final Set<String> _marketplacesSelecionados = {};

  // Parcelamento
  bool _divideSemJuros = false;
  final _maxParcelasSemJuros = TextEditingController(text: '12');

  // Desconto PIX (%)
  final _percentualDescontoPix = TextEditingController(text: '0');

  // Campos de promoção
  bool _emPromocao = false;
  String _tipoDesconto = 'percentual'; // 'percentual' ou 'fixo'
  final _percentualPromo = TextEditingController();
  final _valorPromo = TextEditingController();
  DateTime? _dataInicioPromo;
  DateTime? _dataFimPromo;

  @override
  void initState() {
    super.initState();
    _initLojaEBox();

    final p = widget.produto;
    if (p != null) {
      _nome.text = p.nome;
      _quantidade.text = '${p.quantidade}';
      _estoqueMinimo.text = '${p.estoqueMinimo}';
      _fornecedor.text = p.fornecedor;
      _custo.text = MoedaInputFormatter.format(p.custoReal);
      _preco.text = MoedaInputFormatter.format(p.precoFinal);
      _categoria.text = p.categoria;
      _subcategoria.text = p.subcategoria;
      _categoriasExtrasSelecionadas
          .addAll(p.categoriasExtras.map((e) => canonicalizeCategoria(e)));
      _subcategoriasExtrasSelecionadas
          .addAll(p.subcategoriasExtras.map((e) => canonicalizeCategoria(e)));
      _descricao.text = p.descricao;
      _peso.text = p.peso >= 1000 ? (p.peso / 1000).toStringAsFixed(2) : p.peso.toStringAsFixed(0);
      _pesoUnidade = p.peso >= 1000 ? 'kg' : 'g';
      _codigoBarras.text = p.codigoBarras;
      _tipoEmbalagem = p.tipoEmbalagem;
      _imagens.addAll(p.imagens);
      _publicar = p.publicadoNoCatalogo;
      _divideSemJuros = p.divideSemJuros;
      _maxParcelasSemJuros.text = p.maxParcelasSemJuros.toString();
      _percentualDescontoPix.text = (p.percentualDescontoPix > 0)
          ? p.percentualDescontoPix.toStringAsFixed(1)
          : '0';

      // 🔹 Preenche grade de variações (tamanho + cor + quantidade)
      if (p.variacoes != null && p.variacoes!.isNotEmpty) {
        debugPrint('\n🔍 [DEBUG CARREGAR] Carregando variações do Firestore:');
        debugPrint('  p.variacoes = ${p.variacoes}');

        _gradeVariacoes = [];
        final vet = p.variacoesExtraTipo;
        for (final tamanhoEntry in p.variacoes!.entries) {
          final tamanho = tamanhoEntry.key;
          final mapaCores = tamanhoEntry.value;
          if (mapaCores is Map) {
            for (final corEntry in mapaCores.entries) {
              final cor = corEntry.key;
              final raw = corEntry.value;
              String tipoPara(String ev) {
                if (vet == null) return '';
                final tm = vet[tamanho];
                if (tm is! Map) return '';
                final cm = tm[cor];
                if (cm is! Map) return '';
                for (final e in cm.entries) {
                  if (ProdutoVariacaoExtra.keysMatch(e.key.toString(), ev)) {
                    return e.value?.toString() ?? '';
                  }
                }
                return '';
              }

              if (raw is num) {
                debugPrint('  ➜ Linha: $tamanho + $cor = $raw');
                _gradeVariacoes.add({
                  'tamanho': tamanho == 'sem-tamanho' ? '' : tamanho,
                  'cor': cor == 'sem-cor' ? '' : cor,
                  'extraTipo': '',
                  'extraValor': '',
                  'qtd': raw.toInt().toString(),
                  'custo': '',
                });
              } else if (raw is Map) {
                final custoCelula = ProdutoVariacaoExtra.custoUnitarioNaCelula(raw);
                final custoTexto =
                    (custoCelula != null && custoCelula > 0)
                        ? MoedaInputFormatter.format(custoCelula)
                        : '';
                for (final ie in raw.entries) {
                  if (ProdutoVariacaoExtra.isMetaKey(ie.key.toString())) {
                    continue;
                  }
                  final ev = ie.key.toString();
                  final q = ie.value is num
                      ? (ie.value as num).toInt()
                      : int.tryParse(ie.value?.toString() ?? '') ?? 0;
                  final evDisp = ProdutoVariacaoExtra.isSemExtraMapKey(ev)
                      ? ''
                      : ev;
                  debugPrint('  ➜ Linha: $tamanho + $cor + extra=$evDisp = $q');
                  _gradeVariacoes.add({
                    'tamanho': tamanho == 'sem-tamanho' ? '' : tamanho,
                    'cor': cor == 'sem-cor' ? '' : cor,
                    'extraTipo': tipoPara(evDisp),
                    'extraValor': evDisp,
                    'qtd': q.toString(),
                    'custo': custoTexto,
                  });
                }
              }
            }
          }
        }
        debugPrint('  Total de linhas carregadas: ${_gradeVariacoes.length}');
        _logDiagnosticoVariacoes(
          evento: 'carregar',
          productId: p.idFirebase.isNotEmpty ? p.idFirebase : p.slug,
          variacoes: Map<String, dynamic>.from(p.variacoes!),
        );

        if (_gradeVariacoes.isEmpty) {
          _gradeVariacoes.add({
            'tamanho': '',
            'cor': '',
            'extraTipo': '',
            'extraValor': '',
            'qtd': '',
            'custo': '',
          });
        }
      } else {
        // Sem [variacoes] persistidas: não simular grade a partir de estoquePorTamanho/tamanhos
        // (evita "variação fantasma"). Quantidade total continua em [quantidade].
        _legadoEstoqueSemVariacoesCadastradas =
            p.estoquePorTamanho.isNotEmpty || p.tamanhos.isNotEmpty;
        debugPrint(
          '[VARIACAO_GUARD] edição: sem variacoes persistidas; legado estoque/tamanhos=$_legadoEstoqueSemVariacoesCadastradas',
        );
      }

      // 🔹 Preenche campos de promoção
      _emPromocao = p.emPromocao;
      if (p.percentualPromo != null && p.percentualPromo! > 0) {
        _tipoDesconto = 'percentual';
        _percentualPromo.text = MoedaInputFormatter.format(p.percentualPromo!);
      } else if (p.valorPromo != null && p.valorPromo! > 0) {
        _tipoDesconto = 'fixo';
        _valorPromo.text = MoedaInputFormatter.format(p.valorPromo!);
      }
      _dataInicioPromo = p.dataInicioPromo;
      _dataFimPromo = p.dataFimPromo;

      // 🔹 Preenche marketplaces selecionados
      _marketplacesSelecionados.addAll(p.marketplaces);

      // 🔹 Preenche preço por tamanho
      if (p.precoPorTamanho != null && p.precoPorTamanho!.isNotEmpty) {
        for (final e in p.precoPorTamanho!.entries) {
          final key = produtoFormTamanhoKeyPrecoPorTamanho(e.key);
          _precoPorTamanhoCtrl[key] = TextEditingController(
            text: MoedaInputFormatter.format(e.value),
          );
        }
      }
      _initTombSessaoBaseline(p);
    }
    _initVariacaoControllers();
  }

  void _initTombSessaoBaseline(Produto p) {
    if (p.variacoes != null && p.variacoes!.isNotEmpty) {
      _tombSessaoAplicaVarTomb = true;
      _tombSessaoV = ProdutoExclusaoTombstoneService.chavesCelulaDeVariacoes(
        Map<String, dynamic>.from(p.variacoes!),
      );
      _tombSessaoT = ProdutoExclusaoTombstoneService.chavesSoloTamanhoDeEstoquePorTamanho(
        p.estoquePorTamanho,
      );
    } else {
      _tombSessaoAplicaVarTomb = false;
      _tombSessaoV = {};
      _tombSessaoT = {};
    }
  }

  void _atualizarTombSessaoAposTombstoneOk(
    Map<String, dynamic> variacoesMap,
    Map<String, int> estoqueMapa,
  ) {
    _tombSessaoV = ProdutoExclusaoTombstoneService.chavesCelulaDeVariacoes(
      variacoesMap,
    );
    _tombSessaoT = ProdutoExclusaoTombstoneService.chavesSoloTamanhoDeEstoquePorTamanho(
      estoqueMapa,
    );
  }

  void _syncTombSessaoBaselineAposSalvarVariacoes(
    Map<String, dynamic> variacoesMap,
    Map<String, int> estoqueMapa,
  ) {
    if (variacoesMap.isNotEmpty) {
      _tombSessaoAplicaVarTomb = true;
      _atualizarTombSessaoAposTombstoneOk(variacoesMap, estoqueMapa);
      return;
    }
    _tombSessaoAplicaVarTomb = false;
    _tombSessaoV = {};
    _tombSessaoT = {};
  }

  String? _estoqueDocIdParaTombstone(Produto p) {
    final a = p.idFirebase.trim();
    if (a.isNotEmpty) return a;
    final s = p.slug.trim();
    return s.isNotEmpty ? s : null;
  }

  Future<void> _liberarTombstonesVarAtivasPosSave(
    Produto p,
    Map<String, dynamic> variacoesMap,
    Map<String, int> estoqueMapa,
  ) async {
    if (lojaId == null) return;
    final doc = _estoqueDocIdParaTombstone(p);
    if (doc == null) return;
    await ProdutoExclusaoTombstoneService.liberarTombstonesVariacoesAtivas(
      lojaId: lojaId!,
      estoqueDocId: doc,
      variacoesMap: variacoesMap,
      estoquePorTamanho: estoqueMapa,
    );
  }

  /// Antes de [save]/sync: `exclusao_produto` com [p: false] e chaves em [v] — só com prova (grade persistida + remoção de chave).
  Future<bool> _tentarTombstoneVarRemovidaSessaoSeNecessario({
    required Produto pBase,
    required Map<String, dynamic> variacoesMap,
    required Map<String, int> estoqueMapa,
  }) async {
    if (lojaId == null) return true;
    if (!_tombSessaoAplicaVarTomb) {
      return true;
    }
    final novoV = ProdutoExclusaoTombstoneService.chavesCelulaDeVariacoes(variacoesMap);
    final novoT = ProdutoExclusaoTombstoneService.chavesSoloTamanhoDeEstoquePorTamanho(
      estoqueMapa,
    );
    final remV = _tombSessaoV.difference(novoV);
    final remT = _tombSessaoT.difference(novoT);
    if (remV.isEmpty && remT.isEmpty) return true;
    final chaves = <String>{...remV, ...remT};
    final doc = _estoqueDocIdParaTombstone(pBase);
    if (doc == null) {
      logE(
        '[TOMBSTONE_VAR_FAIL] sem idFirebase/slug; nao e possivel gravar v',
        tag: 'TOMBSTONE',
      );
      return false;
    }
    final ok = await ProdutoExclusaoTombstoneService
        .registrarTombstoneExclusaoVarSessaoExplicita(
      lojaId: lojaId!,
      estoqueDocId: doc,
      chaves: chaves,
    );
    if (!ok) return false;
    await ProdutoExclusaoTombstoneService.ensureHydratedForLoja(lojaId!);
    _atualizarTombSessaoAposTombstoneOk(variacoesMap, estoqueMapa);
    return true;
  }

  /// Retorna os tamanhos únicos da grade para [precoPorTamanho] (alinhado ao merge: vazio → sem-tamanho).
  Set<String> get _tamanhosUnicos {
    final set = <String>{};
    for (final c in _variacaoControllers) {
      final t = (c['tamanho']?.text ?? '').trim();
      final cor = (c['cor']?.text ?? '').trim();
      final qStr = (c['qtd']?.text ?? '').trim();
      if (qStr.isEmpty) continue;
      if (t.isEmpty && cor.isEmpty) continue;
      set.add(produtoFormTamanhoKeyPrecoPorTamanho(c['tamanho']?.text ?? ''));
    }
    return set;
  }

  void _initPrecoPorTamanhoControllers() {
    final tamanhos = _tamanhosUnicos;
    for (final t in _precoPorTamanhoCtrl.keys.toList()) {
      if (!tamanhos.contains(t)) {
        final v = MoedaInputFormatter.parse(_precoPorTamanhoCtrl[t]?.text ?? '');
        if (v <= 0) {
          _precoPorTamanhoCtrl[t]?.dispose();
          _precoPorTamanhoCtrl.remove(t);
        }
      }
    }
    for (final t in tamanhos) {
      if (!_precoPorTamanhoCtrl.containsKey(t)) {
        _precoPorTamanhoCtrl[t] = TextEditingController();
      }
    }
  }

  void _initVariacaoControllers() {
    for (final c in _variacaoControllers) {
      c['tamanho']?.dispose();
      c['cor']?.dispose();
      c['extraTipo']?.dispose();
      c['extraValor']?.dispose();
      c['custo']?.dispose();
      c['qtd']?.dispose();
    }
    _variacaoControllers.clear();
    for (final row in _gradeVariacoes) {
      _variacaoControllers.add({
        'tamanho': TextEditingController(text: row['tamanho'] ?? ''),
        'cor': TextEditingController(text: row['cor'] ?? ''),
        'extraTipo': TextEditingController(text: row['extraTipo'] ?? ''),
        'extraValor': TextEditingController(text: row['extraValor'] ?? ''),
        'custo': TextEditingController(text: row['custo'] ?? ''),
        'qtd': TextEditingController(text: row['qtd'] ?? ''),
      });
    }
    _initPrecoPorTamanhoControllers();
  }

  Future<void> _initLojaEBox() async {
    try {
      final id = await LojaIdService.getWithTimeout(timeout: const Duration(seconds: 10));
      lojaId = id;
      if (id == null || id.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Não foi possível identificar a loja. Tente fazer login novamente.'),
              backgroundColor: Colors.red,
            ),
          );
          Navigator.of(context).maybePop();
        }
        return;
      }
      final nomeBox = HiveBoxNames.produtos(id);
      if (Hive.isBoxOpen(nomeBox)) {
        produtosBox = Hive.box<Produto>(nomeBox);
      } else {
        produtosBox = await Hive.openBox<Produto>(nomeBox);
      }

      // Carregar embalagens disponíveis
      if (Hive.isBoxOpen('config')) {
        _configBox = Hive.box('config');
      } else {
        _configBox = await Hive.openBox('config');
      }

      final rawEmbalagens = _configBox.get('embalagens');
      if (rawEmbalagens is List && rawEmbalagens.isNotEmpty) {
        final embalagensTemp = rawEmbalagens.map<Map<String, dynamic>>((e) {
          if (e is Map) {
            return {
              'id': e['id']?.toString() ?? '',
              'nome': e['nome']?.toString() ?? '',
              'peso': (e['peso'] is num)
                  ? (e['peso'] as num).toDouble()
                  : double.tryParse('${e['peso']}') ?? 0.0,
              'tamanho': (e['tamanho'] is num)
                  ? (e['tamanho'] as num).toInt()
                  : int.tryParse('${e['tamanho']}') ?? 0,
            };
          }
          return {'id': '', 'nome': '', 'peso': 0.0, 'tamanho': 0};
        }).toList();

        // ✅ Remover duplicatas baseado no 'id'
        final idsVistos = <String>{};
        _embalagensDisponiveis = embalagensTemp.where((e) {
          final id = e['id'].toString();
          if (id.isEmpty || idsVistos.contains(id)) {
            return false;
          }
          idsVistos.add(id);
          return true;
        }).toList();

        // ✅ Se ficou vazia após remover duplicatas, usar padrão
        if (_embalagensDisponiveis.isEmpty) {
          _embalagensDisponiveis = [
            {'id': 'padrao', 'nome': 'Padrão', 'peso': 50.0, 'tamanho': 1},
          ];
        }
      } else {
        // Padrão caso não tenha nada configurado
        _embalagensDisponiveis = [
          {'id': 'padrao', 'nome': 'Padrão', 'peso': 50.0, 'tamanho': 1},
          {'id': 'pequena', 'nome': 'Pequena', 'peso': 100.0, 'tamanho': 2},
          {'id': 'media', 'nome': 'Média', 'peso': 200.0, 'tamanho': 3},
          {'id': 'grande', 'nome': 'Grande', 'peso': 350.0, 'tamanho': 4},
        ];
      }

      // ✅ Validar se _tipoEmbalagem existe nas opções disponíveis
      final idsDisponiveis = _embalagensDisponiveis.map((e) => e['id'].toString()).toSet();
      if (!idsDisponiveis.contains(_tipoEmbalagem)) {
        _tipoEmbalagem = _embalagensDisponiveis.first['id'].toString();
      }

      if (widget.produto == null && mounted) {
        final args = ModalRoute.of(context)?.settings.arguments;
        if (args is Map) {
          final f = (args['prefillFornecedor'] ?? '').toString().trim();
          if (f.isNotEmpty && _fornecedor.text.trim().isEmpty) {
            _fornecedor.text = f;
          }
        }
      }

      final pipeId = widget.compraPipelineDocId?.trim() ?? '';
      if (pipeId.isNotEmpty) {
        final pBox = await CompraItemPipelineStore.openBox(id);
        final pip = pBox?.get(pipeId);
        if (pip != null) {
          final origemCanceladaAudit =
              compraPipelineDeveExibirOrigemCancelada(pip);
          if (pip.estado == CompraItemPipelineEstado.precificadoPendenteEstoque) {
            _bootstrapPipeline = pip;
            if (widget.produto == null) {
              _nome.text = pip.nomeProdutoProvisorio;
              _quantidade.text = '${pip.quantidade}';
              _custo.text = MoedaInputFormatter.format(pip.custoUnitario);
              _preco.text = MoedaInputFormatter.format(pip.precoFinal);
              _fornecedor.text = pip.fornecedorNome;
              if (pip.codigoBarras.isNotEmpty) {
                _codigoBarras.text = pip.codigoBarras;
              }
              if (pip.observacaoItem.isNotEmpty) {
                _descricao.text = pip.observacaoItem;
              }
            }
          } else if (origemCanceladaAudit) {
            _pipelineOrigemCancelada = pip;
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Item não está pendente de estoque (${CompraItemPipelineEstado.legivel(pip.estado)}).',
                  ),
                  backgroundColor: Colors.orange.shade800,
                ),
              );
            }
          }
        }
      }

      if (_pipelineOrigemCancelada == null && widget.produto != null) {
        final auditBox = await CompraItemPipelineStore.openBox(id);
        if (auditBox != null) {
          final prod = widget.produto!;
          final fid = prod.idFirebase.trim();
          final dynamic k = prod.key;
          final hk = k is int ? k : null;
          for (final row in auditBox.values) {
            if (row.lojaId.trim() != id.trim()) continue;
            if (!compraPipelineDeveExibirOrigemCancelada(row)) continue;
            final matchFb =
                fid.isNotEmpty && row.produtoIdFirebaseGravado.trim() == fid;
            final matchHive = hk != null && row.produtoHiveKey == hk;
            if (matchFb || matchHive) {
              _pipelineOrigemCancelada = row;
              break;
            }
          }
        }
      }

      // Para novo produto: verificar se já existe ao mudar nome/categoria
      if (widget.produto == null) {
        _nome.addListener(_verificarProdutoExistente);
        _categoria.addListener(_verificarProdutoExistente);
        WidgetsBinding.instance.addPostFrameCallback((_) => _verificarProdutoExistente());
      }
    } catch (e) {
      debugPrint('❌ Erro ao inicializar ProdutoForm (type=${e.runtimeType})');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar loja: $e')),
        );
      }
    } finally {
      if (mounted) setState(() {});
    }
  }

  /// Peso em gramas (converte de kg se _pesoUnidade for 'kg').
  double get _pesoEmGramas {
    final v = double.tryParse(_peso.text.trim().replaceAll(',', '.')) ?? 0.0;
    return _pesoUnidade == 'kg' ? v * 1000 : v;
  }

  /// Salva [pesoAnterior] se o campo estiver vazio e já havia peso (>0), evitando zero acidental.
  double _pesoGramasParaSalvar({required double? pesoAnterior}) {
    final t = _peso.text.trim();
    if (t.isEmpty && pesoAnterior != null && pesoAnterior > 0) {
      debugPrint(
        '[PESO_GUARD] produto_form: campo peso vazio, mantendo ${pesoAnterior.toStringAsFixed(1)} g',
      );
      return pesoAnterior;
    }
    return _pesoEmGramas;
  }

  void _verificarProdutoExistente() {
    if (lojaId == null || widget.produto != null) return;
    final nome = _nome.text.trim();
    final cat = _categoria.text.trim();
    if (nome.isEmpty) {
      if (_duplicataDetectada != null && mounted) {
        setState(() => _duplicataDetectada = null);
      }
      return;
    }
    final existente = findProdutoExistente(
      produtosBox,
      lojaId!,
      nome: nome,
      categoria: cat,
    );
    if (mounted && existente != _duplicataDetectada) {
      setState(() => _duplicataDetectada = existente);
    }
  }

  Future<_DuplicataSalvarEscolha?> _perguntarDuplicataSalvar(Produto duplicata) async {
    debugPrint('[PRODUTO_MATCH_GUARD] exigindo confirmação para duplicata hiveKey=${duplicata.key}');
    return showDialog<_DuplicataSalvarEscolha>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Produto já cadastrado'),
        content: Text(
          'Já existe um produto com o nome "${duplicata.nome}" nesta categoria. '
          'Atualizar o cadastro existente ou criar outro registro (pode haver nomes duplicados)?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _DuplicataSalvarEscolha.cancelar),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _DuplicataSalvarEscolha.criarNovo),
            child: const Text('Criar outro'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _DuplicataSalvarEscolha.atualizar),
            child: const Text('Atualizar existente'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    if (widget.produto == null) {
      _nome.removeListener(_verificarProdutoExistente);
      _categoria.removeListener(_verificarProdutoExistente);
    }
    _nome.dispose();
    _quantidade.dispose();
    _estoqueMinimo.dispose();
    _fornecedor.dispose();
    _custo.dispose();
    _preco.dispose();
    _categoria.dispose();
    _subcategoria.dispose();
    _categoriaExtraInput.dispose();
    _subcategoriaExtraInput.dispose();
    _descricao.dispose();
    _peso.dispose();
    _codigoBarras.dispose();
    for (final c in _variacaoControllers) {
      c['tamanho']?.dispose();
      c['cor']?.dispose();
      c['extraTipo']?.dispose();
      c['extraValor']?.dispose();
      c['custo']?.dispose();
      c['qtd']?.dispose();
    }
    _variacaoControllers.clear();
    for (final ctrl in _precoPorTamanhoCtrl.values) {
      ctrl.dispose();
    }
    _precoPorTamanhoCtrl.clear();
    _percentualPromo.dispose();
    _valorPromo.dispose();
    _percentualDescontoPix.dispose();
    _maxParcelasSemJuros.dispose();
    _uploader.dispose();
    _debouncePersistImagens?.cancel();
    _fotoPendenteUiTimer?.cancel();
    super.dispose();
  }

  bool _fotoPendenteCancelada(String localId) =>
      _uploadCancelPending.contains(localId);

  void _limparEstadoPendente(String localId) {
    _previewBytes.remove(localId);
    _fotoPendenteInicio.remove(localId);
    _fotoPendenteEnviando.remove(localId);
    _fotoAviso3sLogged.remove(localId);
    _fotoAviso8sLogged.remove(localId);
  }

  void _garantirTickerUiFotosPendentes() {
    if (_fotoPendenteUiTimer != null) return;
    _fotoPendenteUiTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      final pendentes =
          _imagens.where((u) => u.startsWith('pending://')).toList();
      if (pendentes.isEmpty) {
        _fotoPendenteUiTimer?.cancel();
        _fotoPendenteUiTimer = null;
        return;
      }
      final now = DateTime.now();
      for (final id in pendentes) {
        final t0 = _fotoPendenteInicio[id];
        if (t0 == null) continue;
        final elapsed = now.difference(t0);
        if (elapsed >= const Duration(seconds: 3) &&
            _fotoAviso3sLogged.add(id)) {
          BootPerfLog.fotoMark(
            'timeout_warning',
            detail: '3s $id',
          );
        }
        if (elapsed >= const Duration(seconds: 8) &&
            _fotoAviso8sLogged.add(id)) {
          BootPerfLog.fotoMark(
            'timeout_warning',
            detail: '8s $id',
          );
        }
      }
      setState(() {});
    });
  }

  String _mensagemCardFotoPendente(String localId) {
    if (_fotoPendenteEnviando.contains(localId)) {
      return 'Enviando…';
    }
    final t0 = _fotoPendenteInicio[localId];
    final elapsed = t0 == null
        ? Duration.zero
        : DateTime.now().difference(t0);
    if (elapsed < const Duration(seconds: 3)) {
      return 'Preparando imagem…';
    }
    if (elapsed < const Duration(seconds: 8)) {
      return 'Processando imagem…';
    }
    return 'Imagem grande, ainda processando…';
  }

  /// Persistência após gestos rápidos (reordenar / excluir / upload) — um save após debounce.
  void _agendarPersistenciaImagens() {
    if (widget.produto == null || lojaId == null) return;
    _debouncePersistImagens?.cancel();
    _debouncePersistImagens = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted || widget.produto == null) return;
      BootPerfLog.fotoStart('persist_start');
      try {
        await _persistirProdutoAtual(widget.produto!, mostrarSnackSucesso: false);
      } finally {
        BootPerfLog.fotoEnd('persist_done');
      }
    });
  }

  bool get _temUploadFotoPendente =>
      _fotosEmUpload > 0 || _imagens.any((u) => u.startsWith('pending://'));

  List<String> get _imagensParaPersistir => _imagens
      .where((u) => !u.startsWith('pending://'))
      .toList(growable: false);

  void _removerFotoNoIndice(int i) {
    if (i < 0 || i >= _imagens.length) return;
    final src = _imagens[i];
    if (src.startsWith('pending://')) {
      _uploadCancelPending.add(src);
    }
    setState(() {
      _imagens.removeAt(i);
      _limparEstadoPendente(src);
    });
    if (widget.produto != null && !src.startsWith('pending://')) {
      _agendarPersistenciaImagens();
    }
  }

  Future<void> _processWebPhoto(XFile file) async {
    final localId = 'pending://${DateTime.now().microsecondsSinceEpoch}';
    if (!mounted || lojaId == null) return;

    BootPerfLog.fotoStart('preview_added', detail: localId);
    setState(() {
      _imagens.add(localId);
      _fotoPendenteInicio[localId] = DateTime.now();
    });
    _garantirTickerUiFotosPendentes();
    BootPerfLog.fotoEnd('preview_added', detail: localId);

    var uploadIniciado = false;
    try {
      await Future<void>.delayed(Duration.zero);
      if (_fotoPendenteCancelada(localId)) return;

      BootPerfLog.fotoStart('read_start', detail: localId);
      final rawBytes = await file.readAsBytes().timeout(
        const Duration(seconds: 120),
        onTimeout: () => throw TimeoutException('read_timeout'),
      );
      BootPerfLog.fotoEnd(
        'read_done',
        detail: 'bytes=${rawBytes.length} $localId',
      );

      if (_fotoPendenteCancelada(localId) || !_imagens.contains(localId)) {
        return;
      }
      if (mounted) {
        setState(() => _previewBytes[localId] = rawBytes);
      }

      BootPerfLog.fotoStart('compress_start', detail: localId);
      final encoded = await Future<Uint8List?>(() =>
          CatalogThumbnailService.encodeBytesAsOptimizedJpegForProductUpload(
        rawBytes,
      ));
      BootPerfLog.fotoEnd(
        'compress_done',
        detail: 'bytes=${(encoded ?? rawBytes).length} $localId',
      );

      if (_fotoPendenteCancelada(localId) || !_imagens.contains(localId)) {
        return;
      }

      final Uint8List bytes;
      final String ext;
      final String contentType;
      if (encoded != null) {
        bytes = encoded;
        ext = 'jpg';
        contentType = 'image/jpeg';
      } else {
        bytes = rawBytes;
        if (rawBytes.length >= 3 &&
            rawBytes[0] == 0xFF &&
            rawBytes[1] == 0xD8 &&
            rawBytes[2] == 0xFF) {
          ext = 'jpg';
          contentType = 'image/jpeg';
        } else if (rawBytes.length >= 8 &&
            rawBytes[0] == 0x89 &&
            rawBytes[1] == 0x50 &&
            rawBytes[2] == 0x4E &&
            rawBytes[3] == 0x47) {
          ext = 'png';
          contentType = 'image/png';
        } else {
          ext = 'jpg';
          contentType = 'image/jpeg';
        }
      }

      if (mounted) {
        setState(() {
          _fotosEmUpload++;
          _fotoPendenteEnviando.add(localId);
        });
      }
      uploadIniciado = true;
      BootPerfLog.fotoStart('upload_start', detail: localId);
      final url = await ImageUploadService.uploadImageFromBytes(
        bytes: bytes,
        folder: 'produtos',
        lojaId: lojaId!,
        extension: ext,
        contentType: contentType,
      ).timeout(
        const Duration(seconds: 90),
        onTimeout: () => throw TimeoutException('upload_timeout'),
      );
      BootPerfLog.fotoEnd('upload_done', detail: url != null ? 'ok' : 'null');

      if (_fotoPendenteCancelada(localId) || !_imagens.contains(localId)) {
        if (url != null && lojaId != null) {
          unawaited(
            ImageUploadService.deleteImageIfManagedForLoja(url, lojaId!),
          );
        }
        return;
      }

      if (!mounted) return;
      setState(() {
        final idx = _imagens.indexOf(localId);
        if (idx >= 0 && url != null) {
          _imagens[idx] = url;
          _limparEstadoPendente(localId);
        }
      });

      if (url == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Falha ao enviar uma imagem. Toque em ✕ para remover.',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else if (widget.produto != null) {
        _agendarPersistenciaImagens();
      }
    } on TimeoutException catch (e) {
      debugPrint('[ProdutoForm] Timeout foto web ($localId): $e');
      if (!_fotoPendenteCancelada(localId) && mounted) {
        setState(() {
          _imagens.remove(localId);
          _limparEstadoPendente(localId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.message == 'read_timeout'
                  ? 'Não foi possível ler a imagem. Tente outra foto ou reduza o tamanho.'
                  : 'Envio da imagem demorou demais. Tente novamente.',
            ),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } catch (e) {
      debugPrint('[ProdutoForm] Erro foto web ($localId, type=${e.runtimeType}): $e');
      if (!_fotoPendenteCancelada(localId) && mounted) {
        setState(() {
          _imagens.remove(localId);
          _limparEstadoPendente(localId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao enviar imagem: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (uploadIniciado && mounted) {
        setState(() => _fotosEmUpload = (_fotosEmUpload - 1).clamp(0, 999));
      }
    }
  }

  Widget _buildFotoPreview(String src) {
    final mem = _previewBytes[src];
    if (mem != null) {
      return Image.memory(
        mem,
        width: 100,
        height: 100,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    }
    if (src.startsWith('pending://')) {
      return Container(
        width: 100,
        height: 100,
        color: Colors.grey.shade200,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(height: 6),
            Text(
              _mensagemCardFotoPendente(src),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 9, color: Colors.grey.shade700),
            ),
          ],
        ),
      );
    }
    if (src.startsWith('http') || kIsWeb) {
      return Image.network(
        src,
        width: 100,
        height: 100,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    }
    return Image.file(
      io.File(src),
      width: 100,
      height: 100,
      fit: BoxFit.cover,
    );
  }

  // ------------------------------
  // PICK DE IMAGENS
  // ------------------------------
  /// Web: preview imediato + upload em background; nativo: path local até salvar.
  Future<void> _pickImgs() async {
    BootPerfLog.fotoStart('pick_start');
    final x = await ImagePicker().pickMultiImage(
      imageQuality: 78,
      maxWidth: 1800,
      maxHeight: 1800,
    );
    BootPerfLog.fotoEnd('pick_done', detail: '${x.length} arquivo(s)');
    if (x.isEmpty) return;
    if (lojaId == null) return;
    final guard = LimitsGuard();
    final max = await guard.maxImagesPerProduct(null);
    final slots = max - _imagens.length;
    if (slots <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Limite de $max imagem(ns) por produto no plano Free. Faça upgrade para mais.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    if (kIsWeb) {
      final toProcess = x.take(slots).toList();
      for (final file in toProcess) {
        unawaited(_processWebPhoto(file));
      }
      if (mounted && toProcess.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              toProcess.length == 1
                  ? 'Imagem adicionada — enviando em segundo plano…'
                  : '${toProcess.length} imagens — enviando em segundo plano…',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    final paths = x.map((e) => e.path).toList();
    final aAdicionar = paths.take(slots).toList();
    setState(() => _imagens.addAll(aAdicionar));
    BootPerfLog.fotoEnd('preview_added', detail: '${aAdicionar.length} path(s)');
    if (widget.produto != null) {
      _agendarPersistenciaImagens();
    }
  }

  // ------------------------------
  // ADICIONAR IMAGEM POR URL
  // ------------------------------
  Future<void> _addImgByUrl() async {
    final ctrl = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Adicionar imagem por URL'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'https://...jpg'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Adicionar'),
          ),
        ],
      ),
    );
    ctrl.dispose();

    if ((url ?? '').isNotEmpty && lojaId != null) {
      final guard = LimitsGuard();
      final pode = await guard.canAddImagemProduto(
        lojaId!,
        currentCount: _imagens.length,
      );
      if (!pode && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Limite de 1 imagem por produto no plano Free. Faça upgrade para mais.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      setState(() => _imagens.add(url!));
      if (widget.produto != null) {
        try {
          await _persistirProdutoAtual(widget.produto!);
        } on TimeoutException catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('URL salva localmente; nuvem: ${e.message ?? 'timeout'}'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Erro ao sincronizar imagem por URL: $e'), backgroundColor: Colors.red.shade700),
            );
          }
        }
      }
    }
  }

  /// Aplica estado atual do formulário ao produto e sincroniza Hive + Firestore.
  /// Chamado ao salvar ou quando editar foto/variação (auto-persist).
  /// [mostrarSnackSucesso]: false em auto-save frequente (reordenação) para não spammar.
  Future<void> _persistirProdutoAtual(Produto p, {bool mostrarSnackSucesso = true}) async {
    if (lojaId == null) return;
    final imagensAntesPersist = List<String>.from(p.imagens);
    try {
      final qtdGeral = int.tryParse(_quantidade.text) ?? 0;
      final custo = MoedaInputFormatter.parse(_custo.text);
      final preco = MoedaInputFormatter.parse(_preco.text);
      final merged = produtoFormMergeVariacoesGrade(_variacaoControllers);
      final variacoesMap = merged.variacoes;
      final Set<String> tamanhosSet = {};
      final Set<String> coresSet = {};
      int quantidadeTotalVariacoes = 0;
      for (final c in _variacaoControllers) {
        final tamanho = (c['tamanho']?.text ?? '').trim();
        final cor = (c['cor']?.text ?? '').trim();
        final qStr = (c['qtd']?.text ?? '').trim();
        if (qStr.isEmpty || (tamanho.isEmpty && cor.isEmpty)) continue;
        final qtd = int.tryParse(qStr) ?? 0;
        if (qtd <= 0) continue;
        if (tamanho.isNotEmpty) tamanhosSet.add(tamanho);
        if (cor.isNotEmpty) coresSet.add(cor);
        quantidadeTotalVariacoes += qtd;
      }
      final int quantidadeFinal = variacoesMap.isEmpty ? qtdGeral : quantidadeTotalVariacoes;
      final List<String> tamanhosList = tamanhosSet.toList();
      final List<String> coresList = coresSet.toList();
      final Map<String, int> estoqueMapa = {};
      for (final t in variacoesMap.keys) {
        if (t == 'sem-tamanho') continue;
        final m = variacoesMap[t] as Map<String, dynamic>;
        var sum = 0;
        for (final v in m.values) {
          sum += ProdutoVariacaoExtra.somarCelula(v);
        }
        estoqueMapa[t] = sum;
      }
      final percentualDescontoPix = (double.tryParse(_percentualDescontoPix.text.trim()) ?? 0.0).clamp(0.0, 100.0);
      final maxParcelasSemJuros = (int.tryParse(_maxParcelasSemJuros.text.trim()) ?? 12).clamp(1, 24);
      final categoriaPrincipal = canonicalizeCategoria(_categoria.text.trim());
      final subcategoriaPrincipal =
          canonicalizeCategoria(_subcategoria.text.trim());
      final categoriasExtras = _extrasSemPrincipal(
        _categoriasExtrasSelecionadas,
        categoriaPrincipal,
      );
      final subcategoriasExtras = _extrasSemPrincipal(
        _subcategoriasExtrasSelecionadas,
        subcategoriaPrincipal,
      );
      double? percentualPromo;
      double? valorPromo;
      if (_emPromocao) {
        if (_tipoDesconto == 'percentual') {
          percentualPromo = MoedaInputFormatter.parse(_percentualPromo.text);
        } else {
          valorPromo = MoedaInputFormatter.parse(_valorPromo.text);
        }
      }
      p
        ..nome = capitalizeWords(_nome.text.trim())
        ..quantidade = quantidadeFinal
        ..custoReal = custo
        ..precoFinal = preco
        ..precoUnitario = preco
        ..categoria = categoriaPrincipal
        ..subcategoria = subcategoriaPrincipal
        ..categoriasExtras = categoriasExtras
        ..subcategoriasExtras = subcategoriasExtras
        ..descricao = _descricao.text.trim()
        ..imagens = List.from(_imagensParaPersistir)
        ..publicadoNoCatalogo = _publicar
        ..divideSemJuros = _divideSemJuros
        ..percentualDescontoPix = percentualDescontoPix
        ..maxParcelasSemJuros = maxParcelasSemJuros
        ..slug = p.slug.isNotEmpty ? p.slug : '${lojaId!}-${gerarSlug(_nome.text.trim())}'
        ..tamanhos = tamanhosList
        ..estoquePorTamanho = estoqueMapa
        ..lojaId = p.lojaId.isNotEmpty ? p.lojaId : lojaId!
        ..emPromocao = _emPromocao
        ..percentualPromo = percentualPromo
        ..valorPromo = valorPromo
        ..dataInicioPromo = _dataInicioPromo
        ..dataFimPromo = _dataFimPromo
        ..peso = _pesoGramasParaSalvar(pesoAnterior: p.peso)
        ..codigoBarras = _codigoBarras.text.trim()
        ..tipoEmbalagem = _tipoEmbalagem
        ..cores = coresList
        ..marketplaces = _marketplacesSelecionados.toList()
        ..variacoes = variacoesMap.isNotEmpty ? variacoesMap : null
        ..variacoesExtraTipo =
            variacoesMap.isNotEmpty ? merged.variacoesExtraTipo : null
        ..estoqueMinimo = int.tryParse(_estoqueMinimo.text) ?? 0
        ..fornecedor = _fornecedor.text.trim()
        ..custoEditadoNoCadastro = true;
      final precoPorTamanhoMap =
          produtoFormBuildPrecoPorTamanhoFromControllers(_precoPorTamanhoCtrl);
      p.precoPorTamanho = precoPorTamanhoMap.isNotEmpty ? precoPorTamanhoMap : null;
      if (variacoesMap.isNotEmpty) p.recalcularQuantidadeTotal();
      if (!await _tentarTombstoneVarRemovidaSessaoSeNecessario(
        pBase: p,
        variacoesMap: Map<String, dynamic>.from(variacoesMap),
        estoqueMapa: estoqueMapa,
      )) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Não foi possível confirmar a remoção da variação na nuvem. Verifique a conexão e tente de novo.',
              ),
              backgroundColor: Colors.red.shade700,
            ),
          );
        }
        return;
      }
      p.updatedAt = DateTime.now();
      await p.save();
      await _liberarTombstonesVarAtivasPosSave(p, variacoesMap, estoqueMapa);
      _syncTombSessaoBaselineAposSalvarVariacoes(variacoesMap, estoqueMapa);
      await ProdutosFirestoreService.syncProduto(p, lojaId: lojaId)
          .timeout(const Duration(seconds: 45), onTimeout: () => throw TimeoutException('Sincronização demorou muito'));
      await CatalogoSyncService.upsertFromProduto(p, target: SyncTarget.draft)
          .timeout(const Duration(seconds: 30), onTimeout: () => throw TimeoutException('Catálogo demorou muito'));
      await CatalogoSyncService.upsertFromProduto(p, target: SyncTarget.live)
          .timeout(const Duration(seconds: 30), onTimeout: () => throw TimeoutException('Catálogo demorou muito'));
      await CatalogPublishService.marcarCatalogoPrecisaAtualizar();
      await ProdutoImagensStorageCleanup.apagarUrlsRemovidasGerenciadas(
        anteriores: imagensAntesPersist,
        atuais: List<String>.from(p.imagens),
        lojaId: lojaId!,
      );
      if (mounted && mostrarSnackSucesso) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Alterações salvas localmente e na nuvem.')),
        );
      }
    } on TimeoutException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Salvo no aparelho; a nuvem demorou demais (${e.message ?? 'timeout'}). Verifique a conexão e salve de novo.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              mostrarSnackSucesso
                  ? 'Erro ao salvar alterações: $e'
                  : 'Falha ao sincronizar (ordem das imagens): $e',
            ),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  Future<void> _sugerirDescricaoComIa() async {
    final nome = _nome.text.trim();
    if (nome.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o nome do produto para sugerir a descrição.')),
      );
      return;
    }
    final lojaId = await LojaIdService.get();
    if (!await IaUsoLimiteService.canUse(lojaId, TipoUsoIa.descricao)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(IaUsoLimiteService.messageLimitExcedido(TipoUsoIa.descricao)), backgroundColor: Colors.orange.shade700),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _sugerindoDescricao = true);
    try {
      final descricao = await AiLojaService.sugerirDescricao(
        nome: nome,
        categoria: _categoria.text.trim().isEmpty ? null : _categoria.text.trim(),
        subcategoria: _subcategoria.text.trim().isEmpty ? null : _subcategoria.text.trim(),
      );
      if (mounted) {
        _descricao.text = descricao;
        IaUsoLimiteService.recordUse(lojaId, TipoUsoIa.descricao);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Descrição sugerida pela IA. Você pode editar o texto.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não foi possível gerar sugestão: ${AiLojaService.messageForUser(e)}'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sugerindoDescricao = false);
    }
  }

  bool _sugerindoIa = false;

  Future<void> _sugerirTituloIa() async {
    final nome = _nome.text.trim();
    if (nome.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Informe o nome do produto.')));
      return;
    }
    final lojaId = await LojaIdService.get();
    if (!await IaUsoLimiteService.canUse(lojaId, TipoUsoIa.perguntas)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(IaUsoLimiteService.messageLimitExcedido(TipoUsoIa.perguntas)), backgroundColor: Colors.orange.shade700),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _sugerindoIa = true);
    try {
      final titulo = await AiLojaService.sugerirTitulo(
        nome: nome,
        categoria: _categoria.text.trim().isEmpty ? null : _categoria.text.trim(),
      );
      if (mounted) {
        _nome.text = titulo;
        IaUsoLimiteService.recordUse(lojaId, TipoUsoIa.perguntas);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Título sugerido pela IA.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AiLojaService.messageForUser(e)), backgroundColor: Colors.red.shade700),
        );
      }
    } finally {
      if (mounted) setState(() => _sugerindoIa = false);
    }
  }

  Future<void> _sugerirCategoriaIa() async {
    final nome = _nome.text.trim();
    if (nome.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Informe o nome do produto.')));
      return;
    }
    final lojaId = await LojaIdService.get();
    if (!await IaUsoLimiteService.canUse(lojaId, TipoUsoIa.perguntas)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(IaUsoLimiteService.messageLimitExcedido(TipoUsoIa.perguntas)), backgroundColor: Colors.orange.shade700),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _sugerindoIa = true);
    try {
      final out = await AiLojaService.sugerirCategoriaSubcategoria(
        nome: nome,
        descricao: _descricao.text.trim().isEmpty ? null : _descricao.text.trim(),
      );
      if (mounted) {
        _categoria.text = out['categoria'] ?? _categoria.text;
        _subcategoria.text = out['subcategoria'] ?? _subcategoria.text;
        IaUsoLimiteService.recordUse(lojaId, TipoUsoIa.perguntas);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Categoria e subcategoria sugeridas. Tags: ${(out['tags'] as List?)?.join(", ") ?? ""}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AiLojaService.messageForUser(e)), backgroundColor: Colors.red.shade700),
        );
      }
    } finally {
      if (mounted) setState(() => _sugerindoIa = false);
    }
  }

  Future<void> _sugerirVariacoesDescricaoIa() async {
    final nome = _nome.text.trim();
    if (nome.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o nome do produto.')),
      );
      return;
    }
    final lojaId = await LojaIdService.get();
    if (!await IaUsoLimiteService.canUse(lojaId, TipoUsoIa.perguntas)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(IaUsoLimiteService.messageLimitExcedido(TipoUsoIa.perguntas)), backgroundColor: Colors.orange.shade700),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _sugerindoIa = true);
    try {
      final out = await AiLojaService.sugerirVariacoesDescricao(
        nome: nome,
        descricaoAtual: _descricao.text.trim().isEmpty ? null : _descricao.text.trim(),
      );
      if (!mounted) return;
      IaUsoLimiteService.recordUse(lojaId, TipoUsoIa.perguntas);
      setState(() => _sugerindoIa = false);
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Variações de texto (IA)'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Feed/Catálogo', style: TextStyle(fontWeight: FontWeight.bold)),
                SelectableText(out['paraFeed'] ?? ''),
                const SizedBox(height: 12),
                const Text('WhatsApp', style: TextStyle(fontWeight: FontWeight.bold)),
                SelectableText(out['paraWhatsApp'] ?? ''),
                const SizedBox(height: 12),
                const Text('Instagram', style: TextStyle(fontWeight: FontWeight.bold)),
                SelectableText(out['paraInstagram'] ?? ''),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
            FilledButton(
              onPressed: () {
                _descricao.text = out['paraFeed'] ?? _descricao.text;
                Navigator.pop(ctx);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Descrição preenchida com versão Feed.')),
                );
              },
              child: const Text('Usar Feed na descrição'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _sugerindoIa = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AiLojaService.messageForUser(e)), backgroundColor: Colors.red.shade700),
        );
      }
    }
  }

  Future<void> _sugerirLegendaInstagramIa() async {
    final nome = _nome.text.trim();
    if (nome.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Informe o nome do produto.')));
      return;
    }
    final lojaId = await LojaIdService.get();
    if (!await IaUsoLimiteService.canUse(lojaId, TipoUsoIa.perguntas)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(IaUsoLimiteService.messageLimitExcedido(TipoUsoIa.perguntas)), backgroundColor: Colors.orange.shade700),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _sugerindoIa = true);
    try {
      final legenda = await AiLojaService.sugerirLegendaInstagram(
        produtoNome: nome,
        descricao: _descricao.text.trim().isEmpty ? null : _descricao.text.trim(),
      );
      if (!mounted) return;
      IaUsoLimiteService.recordUse(lojaId, TipoUsoIa.perguntas);
      setState(() => _sugerindoIa = false);
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Legenda Instagram / Reels'),
          content: SelectableText(legenda),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _sugerindoIa = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AiLojaService.messageForUser(e)), backgroundColor: Colors.red.shade700),
        );
      }
    }
  }

  /// Marca pipeline como concluído após Hive + sync do produto (idempotente).
  Future<void> _vincularCompraPipelineAposSalvar(Produto salvo) async {
    final docId = widget.compraPipelineDocId?.trim();
    if (docId == null || docId.isEmpty || lojaId == null) return;
    final pBox = await CompraItemPipelineStore.openBox(lojaId!);
    if (pBox == null) return;
    final row = pBox.get(docId);
    if (row == null) return;
    if (row.estado == CompraItemPipelineEstado.cancelado) return;
    if (row.estado == CompraItemPipelineEstado.concluidoNoEstoque) return;
    final k = salvo.key;
    final hid = salvo.idFirebase.trim();
    await pBox.put(
      docId,
      row.copyWith(
        estado: CompraItemPipelineEstado.concluidoNoEstoque,
        produtoHiveKey: k is int ? k : row.produtoHiveKey,
        produtoIdFirebaseGravado:
            hid.isNotEmpty ? hid : row.produtoIdFirebaseGravado,
        atualizadoEm: DateTime.now(),
      ),
    );
  }

  // ------------------------------
  // SALVAR PRODUTO (NOVO / EDIT)
  // ------------------------------
  Future<void> _salvar() async {
    if (!_form.currentState!.validate()) return;
    if (lojaId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Loja não carregada ainda. Tente novamente.')),
      );
      return;
    }
    if (_temUploadFotoPendente) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Aguarde o envio das fotos terminar (ou remova as pendentes) antes de salvar.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _salvando = true);

      late final Produto produtoSalvoParaRetorno;
      var remoteStatus = ProdutoSyncRemotoStatus.confirmado;

    try {
      final qtdGeral = int.tryParse(_quantidade.text) ?? 0;
      final custo = MoedaInputFormatter.parse(_custo.text);
      final preco = MoedaInputFormatter.parse(_preco.text);

      // 🔹 Processa variações a partir dos controllers (garante valores salvos)
      debugPrint('\n🔍 [DEBUG SALVAR] Processando ${_variacaoControllers.length} linhas da grade:');
      final mergedSalvar = produtoFormMergeVariacoesGrade(_variacaoControllers);
      final variacoesMap = mergedSalvar.variacoes;
      final Set<String> tamanhosSet = {};
      final Set<String> coresSet = {};
      int quantidadeTotalVariacoes = 0;

      for (int i = 0; i < _variacaoControllers.length; i++) {
        final c = _variacaoControllers[i];
        final tamanho = (c['tamanho']?.text ?? '').trim();
        final cor = (c['cor']?.text ?? '').trim();
        final qStr = (c['qtd']?.text ?? '').trim();

        debugPrint('  Linha $i: tamanho="$tamanho" cor="$cor" qtd="$qStr"');

        if (qStr.isEmpty || (tamanho.isEmpty && cor.isEmpty)) continue;
        final qtd = int.tryParse(qStr) ?? 0;
        if (qtd <= 0) continue;

        debugPrint('  ➜ Processando: $tamanho + $cor = $qtd');

        if (tamanho.isNotEmpty) tamanhosSet.add(tamanho);
        if (cor.isNotEmpty) coresSet.add(cor);
        quantidadeTotalVariacoes += qtd;
      }

      debugPrint('\n📊 [DEBUG SALVAR] Resultado final:');
      debugPrint('  variacoesMap: $variacoesMap');
      debugPrint('  Total de variações: $quantidadeTotalVariacoes un');
      _logDiagnosticoVariacoes(
        evento: 'salvar',
        productId: (widget.produto?.idFirebase.isNotEmpty ?? false)
            ? widget.produto!.idFirebase
            : (widget.produto?.slug ?? 'novo-produto'),
        variacoes: variacoesMap,
      );

      int quantidadeFinal = variacoesMap.isEmpty ? qtdGeral : quantidadeTotalVariacoes;
      List<String> tamanhosList = tamanhosSet.toList();
      List<String> coresList = coresSet.toList();

      // Mapa estoquePorTamanho para compatibilidade (soma por tamanho; ignora sem-tamanho)
      final Map<String, int> estoqueMapa = {};
      for (final tamanho in variacoesMap.keys) {
        if (tamanho == 'sem-tamanho') continue;
        final mapaInterno = variacoesMap[tamanho] as Map<String, dynamic>;
        var total = 0;
        for (final v in mapaInterno.values) {
          total += ProdutoVariacaoExtra.somarCelula(v);
        }
        estoqueMapa[tamanho] = total;
      }

      final percentualDescontoPix = (double.tryParse(_percentualDescontoPix.text.trim()) ?? 0.0).clamp(0.0, 100.0);
      final maxParcelasSemJuros =
          (int.tryParse(_maxParcelasSemJuros.text.trim()) ?? 12).clamp(1, 24);
      final categoriaPrincipal = canonicalizeCategoria(_categoria.text.trim());
      final subcategoriaPrincipal =
          canonicalizeCategoria(_subcategoria.text.trim());
      final categoriasExtras = _extrasSemPrincipal(
        _categoriasExtrasSelecionadas,
        categoriaPrincipal,
      );
      final subcategoriasExtras = _extrasSemPrincipal(
        _subcategoriasExtrasSelecionadas,
        subcategoriaPrincipal,
      );

      final precoPorTamanhoMap =
          produtoFormBuildPrecoPorTamanhoFromControllers(_precoPorTamanhoCtrl);

      // 🔹 Calcula valores de promoção
      double? percentualPromo;
      double? valorPromo;
      if (_emPromocao) {
        if (_tipoDesconto == 'percentual') {
          percentualPromo = MoedaInputFormatter.parse(_percentualPromo.text);
        } else {
          valorPromo = MoedaInputFormatter.parse(_valorPromo.text);
        }
      }

      if (widget.produto == null) {
        // NOVO PRODUTO — duplicata nome+categoria exige confirmação (não mescla sozinha)
        var existente = findProdutoExistente(
          produtosBox,
          lojaId!,
          nome: capitalizeWords(_nome.text.trim()),
          categoria: categoriaPrincipal,
        );
        if (existente != null) {
          final escolha = await _perguntarDuplicataSalvar(existente);
          if (!mounted) return;
          if (escolha == null || escolha == _DuplicataSalvarEscolha.cancelar) {
            setState(() => _salvando = false);
            return;
          }
          if (escolha == _DuplicataSalvarEscolha.criarNovo) {
            existente = null;
          }
        }

        if (existente != null) {
          // ATUALIZAR produto existente (evita duplicação)
          final imagensAntesExistente = List<String>.from(existente.imagens);
          existente
            ..nome = capitalizeWords(_nome.text.trim())
            ..quantidade = quantidadeFinal
            ..custoReal = custo
            ..precoFinal = preco
            ..precoUnitario = preco
            ..categoria = categoriaPrincipal
            ..subcategoria = subcategoriaPrincipal
            ..categoriasExtras = categoriasExtras
            ..subcategoriasExtras = subcategoriasExtras
            ..descricao = _descricao.text.trim()
            ..imagens = List.from(_imagensParaPersistir)
            ..publicadoNoCatalogo = _publicar
            ..divideSemJuros = _divideSemJuros
            ..percentualDescontoPix = percentualDescontoPix
            ..maxParcelasSemJuros = maxParcelasSemJuros
            ..tamanhos = tamanhosList
            ..estoquePorTamanho = estoqueMapa
            ..emPromocao = _emPromocao
            ..percentualPromo = percentualPromo
            ..valorPromo = valorPromo
            ..dataInicioPromo = _dataInicioPromo
            ..dataFimPromo = _dataFimPromo
            ..peso = _pesoGramasParaSalvar(pesoAnterior: existente.peso)
            ..codigoBarras = _codigoBarras.text.trim()
            ..tipoEmbalagem = _tipoEmbalagem
            ..cores = coresList
            ..marketplaces = _marketplacesSelecionados.toList()
            ..variacoes = variacoesMap.isNotEmpty ? variacoesMap : null
            ..variacoesExtraTipo =
                variacoesMap.isNotEmpty ? mergedSalvar.variacoesExtraTipo : null
            ..estoqueMinimo = int.tryParse(_estoqueMinimo.text) ?? 0
            ..fornecedor = _fornecedor.text.trim()
            ..precoPorTamanho = precoPorTamanhoMap.isNotEmpty ? precoPorTamanhoMap : null
            ..custoEditadoNoCadastro = true;

          if (variacoesMap.isNotEmpty) {
            existente.recalcularQuantidadeTotal();
          } else {
            debugPrint('[VARIACAO_CLEAR] save: grade vazia → variacoes/extra limpos no Hive');
          }

          existente.updatedAt = DateTime.now();
          await existente.save();
          _syncTombSessaoBaselineAposSalvarVariacoes(variacoesMap, estoqueMapa);
          remoteStatus = await ProdutoSyncFilaRetryService.syncComRetentativaFila(
            existente,
            lojaId: lojaId!,
            enqueueOnFailure: true,
          )
              .timeout(const Duration(seconds: 45), onTimeout: () => throw TimeoutException('Sincronização com Firestore demorou muito.'));
          if (remoteStatus == ProdutoSyncRemotoStatus.confirmado) {
            await CatalogoSyncService.upsertFromProduto(existente, target: SyncTarget.draft, lojaIdOverride: lojaId)
                .timeout(const Duration(seconds: 30), onTimeout: () => throw TimeoutException('Sincronização com catálogo demorou muito.'));
            await CatalogoSyncService.upsertFromProduto(existente, target: SyncTarget.live, lojaIdOverride: lojaId)
                .timeout(const Duration(seconds: 30), onTimeout: () => throw TimeoutException('Sincronização com catálogo demorou muito.'));
            await CatalogPublishService.marcarCatalogoPrecisaAtualizar();
          }
          await ProdutoImagensStorageCleanup.apagarUrlsRemovidasGerenciadas(
            anteriores: imagensAntesExistente,
            atuais: List<String>.from(existente.imagens),
            lojaId: lojaId!,
          );
          await _vincularCompraPipelineAposSalvar(existente);
          produtoSalvoParaRetorno = existente;
        } else {
          // 🔒 Limite free_limited: verifica antes de inserir
          final guard = LimitsGuard();
          final pode = await guard.canAddProduto(lojaId!);
          if (!pode) {
            setState(() => _salvando = false);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Limite de produtos atingido no plano Free. '
                  'Faça upgrade para adicionar mais.',
                ),
                backgroundColor: Colors.orange,
              ),
            );
            return;
          }
          // INSERIR novo produto
          final docIdSeguro =
              await ProdutoEstoqueDocIdService.resolverDocIdSeguroNovoProduto(
            lojaId: lojaId!,
            nome: _nome.text.trim(),
          );
          final novo = Produto(
            nome: capitalizeWords(_nome.text.trim()),
            quantidade: quantidadeFinal,
            custoReal: custo,
            precoFinal: preco,
            precoUnitario: preco,
            categoria: categoriaPrincipal,
            subcategoria: subcategoriaPrincipal,
            categoriasExtras: categoriasExtras,
            subcategoriasExtras: subcategoriasExtras,
            descricao: _descricao.text.trim(),
            dataEntrada: DateTime.now(),
            imagens: List.from(_imagensParaPersistir),
            publicadoNoCatalogo: _publicar,
            divideSemJuros: _divideSemJuros,
            percentualDescontoPix: percentualDescontoPix,
            maxParcelasSemJuros: maxParcelasSemJuros,
            slug: docIdSeguro,
            idFirebase: docIdSeguro,
            tamanhos: tamanhosList,
            estoquePorTamanho: estoqueMapa,
            frete: 0.0,
            gastosFixos: 0.0,
            gastosVariaveis: 0.0,
            precoSugerido: _bootstrapPipeline?.precoSugerido ?? 0.0,
            lojaId: lojaId!,
            emPromocao: _emPromocao,
            percentualPromo: percentualPromo,
            valorPromo: valorPromo,
            dataInicioPromo: _dataInicioPromo,
            dataFimPromo: _dataFimPromo,
            peso: _pesoEmGramas,
            tipoEmbalagem: _tipoEmbalagem,
            codigoBarras: _codigoBarras.text.trim(),
            cores: coresList,
            marketplaces: _marketplacesSelecionados.toList(),
            variacoes: variacoesMap.isNotEmpty ? variacoesMap : null,
            variacoesExtraTipo:
                variacoesMap.isNotEmpty ? mergedSalvar.variacoesExtraTipo : null,
            videoUrl: '',
            estoqueMinimo: int.tryParse(_estoqueMinimo.text) ?? 0,
            fornecedor: _fornecedor.text.trim(),
            precoPorTamanho: precoPorTamanhoMap.isNotEmpty ? precoPorTamanhoMap : null,
            updatedAt: DateTime.now(),
            custoEditadoNoCadastro: true,
          );

          await produtosBox.add(novo);
          remoteStatus = await ProdutoSyncFilaRetryService.syncComRetentativaFila(
            novo,
            lojaId: lojaId!,
            enqueueOnFailure: true,
          )
              .timeout(const Duration(seconds: 45), onTimeout: () => throw TimeoutException('Sincronização com Firestore demorou muito.'));
          if (remoteStatus == ProdutoSyncRemotoStatus.confirmado) {
            await CatalogoSyncService.upsertFromProduto(novo, target: SyncTarget.draft, lojaIdOverride: lojaId)
                .timeout(const Duration(seconds: 30), onTimeout: () => throw TimeoutException('Sincronização com catálogo demorou muito.'));
            await CatalogoSyncService.upsertFromProduto(novo, target: SyncTarget.live, lojaIdOverride: lojaId)
                .timeout(const Duration(seconds: 30), onTimeout: () => throw TimeoutException('Sincronização com catálogo demorou muito.'));
            await CatalogPublishService.marcarCatalogoPrecisaAtualizar();
          }
          await _vincularCompraPipelineAposSalvar(novo);
          produtoSalvoParaRetorno = novo;
        }
      } else {
        // EDITAR PRODUTO
        final p = widget.produto!;
        final imagensAntesEdit = List<String>.from(p.imagens);
        p
          ..nome = capitalizeWords(_nome.text.trim())
          ..quantidade = quantidadeFinal
          ..custoReal = custo
          ..precoFinal = preco
          ..precoUnitario = preco
          ..categoria = categoriaPrincipal
          ..subcategoria = subcategoriaPrincipal
          ..categoriasExtras = categoriasExtras
          ..subcategoriasExtras = subcategoriasExtras
          ..descricao = _descricao.text.trim()
          ..imagens = List.from(_imagensParaPersistir)
          ..publicadoNoCatalogo = _publicar
          ..divideSemJuros = _divideSemJuros
          ..percentualDescontoPix = percentualDescontoPix
          ..maxParcelasSemJuros = maxParcelasSemJuros
          ..slug = p.slug.isNotEmpty
              ? p.slug
              : '${lojaId!}-${gerarSlug(_nome.text.trim())}'
          ..tamanhos = tamanhosList
          ..estoquePorTamanho = estoqueMapa
          ..lojaId = p.lojaId.isNotEmpty ? p.lojaId : lojaId!
          ..emPromocao = _emPromocao
          ..percentualPromo = percentualPromo
          ..valorPromo = valorPromo
          ..dataInicioPromo = _dataInicioPromo
          ..dataFimPromo = _dataFimPromo
          ..peso = _pesoGramasParaSalvar(pesoAnterior: p.peso)
          ..codigoBarras = _codigoBarras.text.trim()
          ..tipoEmbalagem = _tipoEmbalagem
          ..cores = coresList
          ..marketplaces = _marketplacesSelecionados.toList()
          ..variacoes = variacoesMap.isNotEmpty ? variacoesMap : null
          ..variacoesExtraTipo =
              variacoesMap.isNotEmpty ? mergedSalvar.variacoesExtraTipo : null
          ..estoqueMinimo = int.tryParse(_estoqueMinimo.text) ?? 0
          ..fornecedor = _fornecedor.text.trim()
          ..precoPorTamanho = precoPorTamanhoMap.isNotEmpty ? precoPorTamanhoMap : null
          ..custoEditadoNoCadastro = true;

        // 🔹 Recalcular quantidade total com base nas variações
        if (variacoesMap.isNotEmpty) {
          p.recalcularQuantidadeTotal();
        } else {
          debugPrint('[VARIACAO_CLEAR] save: grade vazia → variacoes/extra limpos no Hive');
        }

        if (!await _tentarTombstoneVarRemovidaSessaoSeNecessario(
          pBase: p,
          variacoesMap: Map<String, dynamic>.from(variacoesMap),
          estoqueMapa: estoqueMapa,
        )) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  'Não foi possível confirmar a remoção da variação na nuvem. Verifique a conexão e tente de novo.',
                ),
                backgroundColor: Colors.red.shade700,
              ),
            );
          }
          return;
        }

        p.updatedAt = DateTime.now();
        await p.save();
        await _liberarTombstonesVarAtivasPosSave(p, variacoesMap, estoqueMapa);
        _syncTombSessaoBaselineAposSalvarVariacoes(variacoesMap, estoqueMapa);
        remoteStatus = await ProdutoSyncFilaRetryService.syncComRetentativaFila(
          p,
          lojaId: lojaId!,
          enqueueOnFailure: true,
        )
            .timeout(const Duration(seconds: 45), onTimeout: () => throw TimeoutException('Sincronização com Firestore demorou muito.'));
        if (remoteStatus == ProdutoSyncRemotoStatus.confirmado) {
          await CatalogoSyncService.upsertFromProduto(p, target: SyncTarget.draft, lojaIdOverride: lojaId)
              .timeout(const Duration(seconds: 30), onTimeout: () => throw TimeoutException('Sincronização com catálogo demorou muito.'));
          await CatalogoSyncService.upsertFromProduto(p, target: SyncTarget.live, lojaIdOverride: lojaId)
              .timeout(const Duration(seconds: 30), onTimeout: () => throw TimeoutException('Sincronização com catálogo demorou muito.'));
          await CatalogPublishService.marcarCatalogoPrecisaAtualizar();
        }
        await ProdutoImagensStorageCleanup.apagarUrlsRemovidasGerenciadas(
          anteriores: imagensAntesEdit,
          atuais: List<String>.from(p.imagens),
          lojaId: lojaId!,
        );
        await _vincularCompraPipelineAposSalvar(p);
        produtoSalvoParaRetorno = p;
      }

      if (!mounted) return;

      final mensagemSalvar = switch (remoteStatus) {
        ProdutoSyncRemotoStatus.confirmado => _publicar
            ? 'Produto salvo, publicado e sincronizado com Hive e Firestore!'
            : 'Produto salvo e sincronizado com Hive e Firestore.',
        ProdutoSyncRemotoStatus.pendenteFila =>
          'Produto salvo no aparelho e colocado na fila de sincronização. '
              'Quando a conexão estabilizar, ele será enviado para a nuvem automaticamente.',
        ProdutoSyncRemotoStatus.falhaRemota =>
          'Produto salvo no aparelho, mas a sincronização com a nuvem falhou agora. '
              'Tente novamente em instantes.',
        ProdutoSyncRemotoStatus.lojaInvalida =>
          'Produto salvo no aparelho, mas sem contexto de loja para sincronizar com a nuvem.',
        ProdutoSyncRemotoStatus.produtoInvalido =>
          'Produto salvo no aparelho, mas o identificador local ficou inválido para sincronização automática.',
        ProdutoSyncRemotoStatus.semMudancas =>
          'Produto salvo sem alterações remotas pendentes.',
        ProdutoSyncRemotoStatus.bloqueadoExclusaoTombstone =>
          'Produto salvo localmente, porém bloqueado para sincronização porque foi marcado para exclusão remota.',
      };

      final corMensagem = remoteStatus == ProdutoSyncRemotoStatus.confirmado ||
              remoteStatus == ProdutoSyncRemotoStatus.semMudancas
          ? null
          : Colors.orange;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mensagemSalvar),
          backgroundColor: corMensagem,
        ),
      );

      Navigator.pop(
        context,
        widget.returnProductOnSave ? produtoSalvoParaRetorno : true,
      );
    } on TimeoutException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Salvamento demorou muito. Tente novamente.'), backgroundColor: Colors.orange),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Falha na sincronização com a nuvem. Se o produto já existia, as alterações podem estar só neste aparelho. '
            'Detalhes: $e',
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  // ------------------------------
  // UI PRINCIPAL
  // ------------------------------
  @override
  Widget build(BuildContext context) {
    final isEdit = widget.produto != null;
    final args = ModalRoute.of(context)?.settings.arguments;
    final returnToVenda = args is Map && (args['returnToVenda'] == true);

    // Enquanto não carregou a loja/box:
    if (lojaId == null || !Hive.isBoxOpen(HiveBoxNames.produtos(lojaId!))) {
      return const Scaffold(
        body: _ProdutoFormLoadingBody(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Editar Produto' : 'Novo Produto'),
        elevation: 0,
        actions: returnToVenda
            ? [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.shopping_cart, size: 18),
                    label: const Text('Voltar para venda'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                    ),
                  ),
                ),
              ]
            : null,
      ),
      body: AbsorbPointer(
        absorbing: _salvando,
        child: Stack(
          children: [
            Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  CompraPipelineOrigemCanceladaNotice(
                    pipeline: _pipelineOrigemCancelada,
                  ),
                  if (_pipelineOrigemCancelada != null)
                    const SizedBox(height: 12),
                  if (widget.produto == null && _duplicataDetectada != null) ...[
                    Material(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Já existe produto com este nome e categoria. Ao salvar, será pedido se deseja '
                                'atualizar o existente ou criar outro registro.',
                                style: TextStyle(color: Colors.orange.shade900, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (isEdit && _legadoEstoqueSemVariacoesCadastradas) ...[
                    Material(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.inventory_2_outlined, color: Colors.blue.shade800),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Estoque ou tamanhos legados (sem variações cadastradas). '
                                'A quantidade total do produto continua válida. A grade só mostra variações salvas explicitamente.',
                                style: TextStyle(color: Colors.blue.shade900, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                  // 📝 CARD: INFORMAÇÕES BÁSICAS
                  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                  _buildSectionCard(
                    title: 'Informações Básicas',
                    icon: Icons.info_outline,
                    iconColor: Colors.blue,
                    children: [
                      // Nome
                      _buildTextField(
                        controller: _nome,
                        label: 'Nome do Produto *',
                        icon: Icons.shopping_bag_outlined,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Informe o nome'
                            : null,
                      ),
                      const SizedBox(height: 12),

                      // Categoria e Subcategoria (unificadas: Anel/anel → Anel; ignora acentos)
                      Row(
                        children: [
                          Expanded(
                            child: _buildCategoriaAutocomplete(
                              controller: _categoria,
                              label: 'Categoria',
                              icon: Icons.category_outlined,
                              opcoes: _opcoesUnicasCategoria(produtosBox.values),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildCategoriaAutocomplete(
                              controller: _subcategoria,
                              label: 'Subcategoria',
                              icon: Icons.label_outline,
                              opcoes: _opcoesUnicasSubcategoria(produtosBox.values),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildClassificacaoExtrasEditor(
                        titulo: 'Categorias adicionais',
                        icon: Icons.category_outlined,
                        inputController: _categoriaExtraInput,
                        selecionados: _categoriasExtrasSelecionadas,
                        sugestoes: _opcoesUnicasCategoria(produtosBox.values),
                        principalAtual: _categoria.text,
                      ),
                      const SizedBox(height: 12),
                      _buildClassificacaoExtrasEditor(
                        titulo: 'Subcategorias adicionais',
                        icon: Icons.label_outline,
                        inputController: _subcategoriaExtraInput,
                        selecionados: _subcategoriasExtrasSelecionadas,
                        sugestoes: _opcoesUnicasSubcategoria(produtosBox.values),
                        principalAtual: _subcategoria.text,
                      ),
                      const SizedBox(height: 12),

                      // Código de barras (opcional)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _buildTextField(
                              controller: _codigoBarras,
                              label: 'Código de barras (opcional)',
                              icon: Icons.qr_code_outlined,
                              helperText: 'EAN, GTIN ou código interno para busca e baixa no estoque',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Padding(
                            padding: const EdgeInsets.only(top: 20),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton.filled(
                                  tooltip: 'Gerar EAN-13',
                                  icon: const Icon(Icons.add_circle_outline),
                                  onPressed: () {
                                    if (mounted) {
                                      _codigoBarras.text = gerarEAN13();
                                    }
                                  },
                                ),
                                const SizedBox(width: 8),
                                IconButton.filled(
                                  tooltip: 'Ler com câmera',
                                  icon: const Icon(Icons.qr_code_scanner),
                                  onPressed: () async {
                                    final code = await BarcodeScannerScreen.scan(context);
                                    if (code != null && code.isNotEmpty && mounted) {
                                      _codigoBarras.text = code;
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Descrição
                      _buildTextField(
                        controller: _descricao,
                        label: 'Descrição',
                        icon: Icons.description_outlined,
                        maxLines: 3,
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.tonalIcon(
                          onPressed: _sugerindoDescricao ? null : _sugerirDescricaoComIa,
                          icon: _sugerindoDescricao
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.auto_awesome, size: 20),
                          label: Text(_sugerindoDescricao ? 'Gerando…' : 'Sugerir com IA'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonal(
                        onPressed: _sugerindoIa ? null : _sugerirTituloIa,
                        child: const Text('Título'),
                      ),
                      FilledButton.tonal(
                        onPressed: _sugerindoIa ? null : _sugerirCategoriaIa,
                        child: const Text('Categoria'),
                      ),
                      FilledButton.tonal(
                        onPressed: _sugerindoIa ? null : _sugerirVariacoesDescricaoIa,
                        child: const Text('Variações'),
                      ),
                      FilledButton.tonal(
                        onPressed: _sugerindoIa ? null : _sugerirLegendaInstagramIa,
                        child: const Text('Legenda IG'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                  // 💰 CARD: PREÇOS E ESTOQUE
                  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                  _buildSectionCard(
                    title: 'Preços e Estoque',
                    icon: Icons.attach_money,
                    iconColor: Colors.green,
                    children: [
                      // Custo e Preço de Venda
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              controller: _custo,
                              label: 'Custo (R\$) *',
                              icon: Icons.money_off_outlined,
                              keyboardType: TextInputType.number,
                              inputFormatters: [MoedaInputFormatter()],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildTextField(
                              controller: _preco,
                              label: 'Preço de Venda (R\$) *',
                              icon: Icons.sell_outlined,
                              keyboardType: TextInputType.number,
                              inputFormatters: [MoedaInputFormatter()],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Quantidade Geral
                      _buildTextField(
                        controller: _quantidade,
                        label: 'Quantidade em Estoque *',
                        icon: Icons.inventory_outlined,
                        keyboardType: TextInputType.number,
                        helperText: 'Será recalculada se preencher tamanhos/cores',
                      ),
                      const SizedBox(height: 12),
                      // Estoque mínimo (alerta no dashboard)
                      _buildTextField(
                        controller: _estoqueMinimo,
                        label: 'Estoque mínimo (alerta)',
                        icon: Icons.warning_amber_outlined,
                        keyboardType: TextInputType.number,
                        helperText: '0 = usa padrão 5. Quando estoque ≤ este valor, aparece no card "Estoque baixo" da home.',
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: _fornecedor,
                        label: 'Fornecedor',
                        icon: Icons.local_shipping_outlined,
                        helperText:
                            'Opcional. Uso interno (app/estoque); não aparece no catálogo público.',
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                  // 🎯 CARD: VARIAÇÕES (TAMANHO + COR)
                  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                  _buildSectionCard(
                    title: 'Variações (Tamanho + Cor + Extra)',
                    icon: Icons.tune,
                    iconColor: Colors.deepPurple,
                    children: [
                      const Text(
                        'Adicione tamanho, cor, quantidade e, se quiser, tipo/valor da variação extra (estampa, letra, etc.).\n'
                        'Preço de custo por variação é opcional. Deixe os campos vazios quando não usar custo diferente por variação.',
                        style: TextStyle(fontSize: 13, color: Colors.black54),
                      ),
                      const SizedBox(height: 12),

                      ..._variacaoControllers.asMap().entries.map((entry) {
                        final i = entry.key;
                        final c = entry.value;

                        return Padding(
                          key: ValueKey('var_$i'),
                          padding: const EdgeInsets.only(bottom: 10.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: TextFormField(
                                      controller: c['tamanho'],
                                      decoration: InputDecoration(
                                        labelText: 'Tamanho',
                                        hintText: 'P, M, 36',
                                        filled: true,
                                        fillColor: Colors.grey.shade50,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        contentPadding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    flex: 2,
                                    child: TextFormField(
                                      controller: c['cor'],
                                      decoration: InputDecoration(
                                        labelText: 'Cor',
                                        hintText: 'Rosa, Azul',
                                        filled: true,
                                        fillColor: Colors.grey.shade50,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        contentPadding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    flex: 1,
                                    child: TextFormField(
                                      controller: c['qtd'],
                                      decoration: InputDecoration(
                                        labelText: 'Qtd',
                                        hintText: '0',
                                        filled: true,
                                        fillColor: Colors.grey.shade50,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        contentPadding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 14,
                                        ),
                                      ),
                                      keyboardType: TextInputType.number,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    flex: 2,
                                    child: TextFormField(
                                      controller: c['custo'],
                                      decoration: InputDecoration(
                                        labelText: 'Preço de custo (opcional)',
                                        hintText: _custo.text.isNotEmpty
                                            ? 'Geral: ${_custo.text}'
                                            : '0,00',
                                        filled: true,
                                        fillColor: Colors.grey.shade50,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        contentPadding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 14,
                                        ),
                                      ),
                                      keyboardType: const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                      inputFormatters: [MoedaInputFormatter()],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle, color: Colors.red),
                                    tooltip: _variacaoControllers.length > 1
                                        ? 'Remover variação'
                                        : 'Limpar última variação',
                                    onPressed: () async {
                                      setState(() {
                                        if (_variacaoControllers.length > 1) {
                                          c['tamanho']?.dispose();
                                          c['cor']?.dispose();
                                          c['extraTipo']?.dispose();
                                          c['extraValor']?.dispose();
                                          c['custo']?.dispose();
                                          c['qtd']?.dispose();
                                          _variacaoControllers.removeAt(i);
                                          _gradeVariacoes.removeAt(i);
                                        } else {
                                          // Permite "apagar tudo" sem manter variação fantasma.
                                          c['tamanho']?.clear();
                                          c['cor']?.clear();
                                          c['extraTipo']?.clear();
                                          c['extraValor']?.clear();
                                          c['custo']?.clear();
                                          c['qtd']?.clear();
                                          if (_gradeVariacoes.isNotEmpty) {
                                            _gradeVariacoes[0] = {
                                              'tamanho': '',
                                              'cor': '',
                                              'extraTipo': '',
                                              'extraValor': '',
                                              'custo': '',
                                              'qtd': '',
                                            };
                                          }
                                        }
                                        _initPrecoPorTamanhoControllers();
                                      });
                                      if (widget.produto != null) {
                                        await _persistirProdutoAtual(widget.produto!);
                                      }
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: c['extraTipo'],
                                      decoration: InputDecoration(
                                        labelText: 'Tipo extra (opcional)',
                                        hintText: 'Estampa, Letra, Desenho…',
                                        filled: true,
                                        fillColor: Colors.grey.shade50,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        contentPadding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: TextFormField(
                                      controller: c['extraValor'],
                                      decoration: InputDecoration(
                                        labelText: 'Valor extra (opcional)',
                                        hintText: 'Floral, A, Borboleta…',
                                        filled: true,
                                        fillColor: Colors.grey.shade50,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        contentPadding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }),

                      const SizedBox(height: 8),
                      // Botão logo abaixo da lista de variações (antes de preço por tamanho)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          icon: const Icon(Icons.add_circle_outline),
                          label: const Text('Adicionar Variação'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.deepPurple,
                          ),
                          onPressed: () async {
                            setState(() {
                              _gradeVariacoes.add({
                                'tamanho': '',
                                'cor': '',
                                'extraTipo': '',
                                'extraValor': '',
                                'custo': '',
                                'qtd': '',
                              });
                              _variacaoControllers.add({
                                'tamanho': TextEditingController(),
                                'cor': TextEditingController(),
                                'extraTipo': TextEditingController(),
                                'extraValor': TextEditingController(),
                                'custo': TextEditingController(),
                                'qtd': TextEditingController(),
                              });
                              _initPrecoPorTamanhoControllers();
                            });
                            if (widget.produto != null) {
                              await _persistirProdutoAtual(widget.produto!);
                            }
                          },
                        ),
                      ),

                      // Preço por tamanho (quando há variações com tamanhos)
                      if (_tamanhosUnicos.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _buildSectionCard(
                          title: 'Preço por tamanho (opcional)',
                          icon: Icons.payments_outlined,
                          iconColor: Colors.green,
                          children: [
                            Text(
                              'Se cada tamanho tiver valor diferente, informe abaixo. Ex: P=R\$50, M=R\$75, G=R\$100. No catálogo aparecerá "R\$ 50,00 até R\$ 100,00".',
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: _precoPorTamanhoCtrl.entries.map((e) {
                                return SizedBox(
                                  width: 120,
                                  child: TextFormField(
                                    controller: e.value,
                                    decoration: InputDecoration(
                                      labelText: e.key == 'sem-tamanho'
                                          ? 'Sem tamanho (R\$)'
                                          : '${e.key} (R\$)',
                                      hintText: '0,00',
                                      filled: true,
                                      fillColor: Colors.grey.shade50,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                    ),
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    inputFormatters: [MoedaInputFormatter()],
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 16),

                  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                  // 📦 CARD: PESO E EMBALAGEM
                  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                  _buildSectionCard(
                    title: 'Peso e Embalagem',
                    icon: Icons.scale_outlined,
                    iconColor: Colors.orange,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              controller: _peso,
                              label: _pesoUnidade == 'kg' ? 'Peso (kg)' : 'Peso (g)',
                              icon: Icons.monitor_weight_outlined,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            ),
                          ),
                          const SizedBox(width: 12),
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(value: 'g', label: Text('g'), icon: Icon(Icons.straighten, size: 18)),
                              ButtonSegment(value: 'kg', label: Text('kg'), icon: Icon(Icons.scale, size: 18)),
                            ],
                            selected: {_pesoUnidade},
                            onSelectionChanged: (Set<String> v) {
                              if (v.isNotEmpty) {
                                final novaUnidade = v.first;
                                if (novaUnidade == _pesoUnidade) return;
                                final valorAtual = double.tryParse(_peso.text.trim().replaceAll(',', '.')) ?? 0.0;
                                setState(() {
                                  _pesoUnidade = novaUnidade;
                                  if (novaUnidade == 'kg') {
                                    _peso.text = (valorAtual / 1000).toStringAsFixed(2);
                                  } else {
                                    _peso.text = (valorAtual * 1000).toStringAsFixed(0);
                                  }
                                });
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<String>(
                              value: _tipoEmbalagem,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: 'Tipo de Embalagem',
                                prefixIcon: const Icon(Icons.inventory_2_outlined),
                                filled: true,
                                fillColor: Colors.grey.shade50,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              items: _embalagensDisponiveis.map((e) {
                                return DropdownMenuItem<String>(
                                  value: e['id'].toString(),
                                  child: Text(
                                    '${e['nome']} (${e['peso']}g)',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }).toList(),
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() => _tipoEmbalagem = v);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                  // 🖼️ CARD: IMAGENS
                  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                  _buildSectionCard(
                    title: 'Imagens',
                    icon: Icons.image_outlined,
                    iconColor: Colors.teal,
                    children: [
                      if (_imagens.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: const Center(
                            child: Column(
                              children: [
                                Icon(Icons.image_outlined, size: 48, color: Colors.grey),
                                SizedBox(height: 8),
                                Text(
                                  'Nenhuma imagem adicionada',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        ),

                      if (_imagens.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Arraste para reordenar. A primeira imagem é a capa do catálogo.',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                        ),
                        ReorderableListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          buildDefaultDragHandles: false,
                          itemCount: _imagens.length,
                          onReorder: (oldIndex, newIndex) {
                            setState(() {
                              if (newIndex > oldIndex) newIndex--;
                              final src = _imagens.removeAt(oldIndex);
                              _imagens.insert(newIndex, src);
                            });
                            _agendarPersistenciaImagens();
                          },
                          itemBuilder: (context, i) {
                            final src = _imagens[i];
                            return Padding(
                              key: ValueKey(src),
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ReorderableDragStartListener(
                                    index: i,
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: 8, top: 36),
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Icon(
                                          Icons.drag_handle,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        Container(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(
                                              color: i == 0
                                                  ? Colors.teal
                                                  : Colors.grey.shade300,
                                              width: i == 0 ? 3 : 2,
                                            ),
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(10),
                                            child: _buildFotoPreview(src),
                                          ),
                                        ),
                                        if (i == 0)
                                          Positioned(
                                            left: 8,
                                            top: 8,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.teal,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: const Text(
                                                'Capa',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                        Positioned(
                                          right: 4,
                                          top: 4,
                                          child: Material(
                                            color: Colors.red,
                                            shape: const CircleBorder(),
                                            child: InkWell(
                                              customBorder: const CircleBorder(),
                                              onTap: () => _removerFotoNoIndice(i),
                                              child: const Padding(
                                                padding: EdgeInsets.all(6),
                                                child: Icon(
                                                  Icons.close,
                                                  color: Colors.white,
                                                  size: 18,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],

                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _pickImgs,
                              icon: const Icon(Icons.photo_library_outlined),
                              label: const Text('Galeria'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _addImgByUrl,
                              icon: const Icon(Icons.link),
                              label: const Text('URL'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                  // 🏷️ CARD: PROMOÇÕES
                  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                  _buildSectionCard(
                    title: 'Promoção',
                    icon: Icons.local_offer_outlined,
                    iconColor: Colors.deepOrange,
                    trailing: Switch(
                      value: _emPromocao,
                      onChanged: (v) => setState(() => _emPromocao = v),
                    ),
                    children: [
                      if (_emPromocao) ...[
                        const Text(
                          'Tipo de desconto',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: RadioListTile<String>(
                                title: const Text('Percentual (%)'),
                                value: 'percentual',
                                // ignore: deprecated_member_use
                                groupValue: _tipoDesconto,
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                // ignore: deprecated_member_use
                                onChanged: (v) => setState(() {
                                  _tipoDesconto = v!;
                                  _valorPromo.clear();
                                }),
                              ),
                            ),
                            Expanded(
                              child: RadioListTile<String>(
                                title: const Text('Valor fixo (R\$)'),
                                value: 'fixo',
                                // ignore: deprecated_member_use
                                groupValue: _tipoDesconto,
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                // ignore: deprecated_member_use
                                onChanged: (v) => setState(() {
                                  _tipoDesconto = v!;
                                  _percentualPromo.clear();
                                }),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),
                        if (_tipoDesconto == 'percentual')
                          _buildTextField(
                            controller: _percentualPromo,
                            label: 'Percentual de desconto (%)',
                            icon: Icons.percent,
                            keyboardType: TextInputType.number,
                            inputFormatters: [MoedaInputFormatter()],
                          ),

                        if (_tipoDesconto == 'fixo')
                          _buildTextField(
                            controller: _valorPromo,
                            label: 'Valor de desconto (R\$)',
                            icon: Icons.attach_money,
                            keyboardType: TextInputType.number,
                            inputFormatters: [MoedaInputFormatter()],
                          ),

                        const SizedBox(height: 16),
                        const Text(
                          'Período da promoção (opcional)',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  final date = await showDatePicker(
                                    context: context,
                                    initialDate: _dataInicioPromo ?? DateTime.now(),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2030),
                                  );
                                  if (date != null) {
                                    setState(() => _dataInicioPromo = date);
                                  }
                                },
                                icon: const Icon(Icons.calendar_today, size: 16),
                                label: Text(
                                  _dataInicioPromo == null
                                      ? 'Data início'
                                      : '${_dataInicioPromo!.day}/${_dataInicioPromo!.month}/${_dataInicioPromo!.year}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  final date = await showDatePicker(
                                    context: context,
                                    initialDate: _dataFimPromo ?? DateTime.now(),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2030),
                                  );
                                  if (date != null) {
                                    setState(() => _dataFimPromo = date);
                                  }
                                },
                                icon: const Icon(Icons.calendar_today, size: 16),
                                label: Text(
                                  _dataFimPromo == null
                                      ? 'Data fim'
                                      : '${_dataFimPromo!.day}/${_dataFimPromo!.month}/${_dataFimPromo!.year}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ),
                          ],
                        ),

                        if (_dataInicioPromo != null || _dataFimPromo != null) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () => setState(() {
                                _dataInicioPromo = null;
                                _dataFimPromo = null;
                              }),
                              icon: const Icon(Icons.clear, size: 16),
                              label: const Text('Limpar datas'),
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),

                  const SizedBox(height: 16),

                  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                  // 🏪 CARD: MARKETPLACES
                  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                  _buildSectionCard(
                    title: 'Marketplaces',
                    icon: Icons.store_outlined,
                    iconColor: Colors.indigo,
                    children: [
                      const Text(
                        'Selecione em quais marketplaces este produto será publicado:',
                        style: TextStyle(fontSize: 13, color: Colors.black54),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildMarketplaceChip('mercadolivre', 'Mercado Livre', Colors.yellow.shade700),
                          _buildMarketplaceChip('shopee', 'Shopee', Colors.orange.shade700),
                          _buildMarketplaceChip('tiktokshop', 'TikTok Shop', Colors.black),
                          _buildMarketplaceChip('magazineluiza', 'Magazine Luiza', Colors.blue.shade700),
                          _buildMarketplaceChip('amazon', 'Amazon', Colors.orange.shade900),
                          _buildMarketplaceChip('americanas', 'Americanas', Colors.red.shade700),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                  // ✅ PUBLICAR NO CATÁLOGO
                  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: SwitchListTile(
                      title: const Text(
                        'Publicar no Catálogo',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text(
                        'O produto ficará visível para os clientes',
                        style: TextStyle(fontSize: 12),
                      ),
                      secondary: const Icon(Icons.visibility_outlined, color: Colors.green),
                      value: _publicar,
                      onChanged: (v) => setState(() => _publicar = v),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                  // PARCELAMENTO SEM JUROS
                  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                  SwitchListTile(
                    title: const Text(
                      'Dividir sem juros',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text(
                      'Define parcelamento sem juros para este produto no catálogo.',
                      style: TextStyle(fontSize: 12),
                    ),
                    secondary: const Icon(Icons.credit_card, color: Colors.blue),
                    value: _divideSemJuros,
                    onChanged: (v) => setState(() => _divideSemJuros = v),
                  ),

                  if (_divideSemJuros) ...[
                    const SizedBox(height: 8),
                    ListTile(
                      leading: const Icon(Icons.filter_9_plus, color: Colors.blue),
                      title: const Text(
                        'Até quantas vezes sem juros',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text(
                        'Esse limite será usado no checkout do Mercado Pago.',
                        style: TextStyle(fontSize: 12),
                      ),
                      trailing: SizedBox(
                        width: 90,
                        child: TextFormField(
                          controller: _maxParcelasSemJuros,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            suffixText: 'x',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 12),

                  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                  // DESCONTO NO PIX
                  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                  ListTile(
                    leading: const Icon(Icons.pix, color: Colors.green),
                    title: const Text(
                      'Desconto no PIX (%)',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text(
                      'Ex: 5% → R\$100 no cartão / R\$95 no PIX',
                      style: TextStyle(fontSize: 12),
                    ),
                    trailing: SizedBox(
                      width: 80,
                      child: TextFormField(
                        controller: _percentualDescontoPix,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          suffixText: '%',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                  // 💾 BOTÕES FINAIS
                  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: _salvar,
                          icon: const Icon(Icons.save_outlined),
                          label: Text(
                            _publicar ? 'Salvar e Publicar' : 'Salvar Rascunho',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade600,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.cancel_outlined),
                          label: const Text('Cancelar'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),

            if (_salvando)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.3),
                  child: const Center(
                    child: Card(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text(
                              'Salvando produto...',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    floatingActionButton: FloatingActionButton(
      onPressed: _abrirMenuIaProduto,
      tooltip: 'IA: descrição, título, categoria, variações, legenda',
      backgroundColor: Colors.amber,
      child: const Icon(Icons.auto_awesome, color: Colors.black87),
    ),
    );
  }

  void _abrirMenuIaProduto() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Sugestões com IA', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.description, color: Colors.blue),
                title: const Text('Sugerir descrição'),
                onTap: () {
                  Navigator.pop(ctx);
                  _sugerirDescricaoComIa();
                },
              ),
              ListTile(
                leading: const Icon(Icons.title, color: Colors.green),
                title: const Text('Sugerir título'),
                onTap: () {
                  Navigator.pop(ctx);
                  _sugerirTituloIa();
                },
              ),
              ListTile(
                leading: const Icon(Icons.category, color: Colors.orange),
                title: const Text('Sugerir categoria e tags'),
                onTap: () {
                  Navigator.pop(ctx);
                  _sugerirCategoriaIa();
                },
              ),
              ListTile(
                leading: const Icon(Icons.format_quote, color: Colors.purple),
                title: const Text('Variações (Feed, WhatsApp, Instagram)'),
                onTap: () {
                  Navigator.pop(ctx);
                  _sugerirVariacoesDescricaoIa();
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Colors.pink),
                title: const Text('Legenda Instagram / Reels'),
                onTap: () {
                  Navigator.pop(ctx);
                  _sugerirLegendaInstagramIa();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // WIDGETS AUXILIARES
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// Widget para criar cards de seção
  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<Widget> children,
    Widget? trailing,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
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
                    color: iconColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 24),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                if (trailing != null) ...[
                  const Spacer(),
                  trailing,
                ],
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  List<String> _opcoesUnicasCategoria(Iterable<Produto> produtos) {
    final normToCanon = <String, String>{};
    for (final p in produtos) {
      final c = p.categoria.trim();
      if (c.isEmpty) continue;
      final n = normalizeText(c);
      normToCanon[n] = canonicalizeCategoria(c);
    }
    final list = normToCanon.values.toList();
    list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  List<String> _opcoesUnicasSubcategoria(Iterable<Produto> produtos) {
    final normToCanon = <String, String>{};
    for (final p in produtos) {
      final s = p.subcategoria.trim();
      if (s.isEmpty) continue;
      final n = normalizeText(s);
      normToCanon[n] = canonicalizeCategoria(s);
    }
    final list = normToCanon.values.toList();
    list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  List<String> _extrasSemPrincipal(Set<String> valores, String principal) {
    final p = normalizeText(principal.trim());
    final list = valores
        .where((v) => normalizeText(v) != p)
        .where((v) => v.trim().isNotEmpty)
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  Widget _buildClassificacaoExtrasEditor({
    required String titulo,
    required IconData icon,
    required TextEditingController inputController,
    required Set<String> selecionados,
    required List<String> sugestoes,
    required String principalAtual,
  }) {
    void addFromInput(String raw) {
      final valor = canonicalizeCategoria(raw.trim());
      if (valor.isEmpty) return;
      if (normalizeText(valor) == normalizeText(principalAtual.trim())) {
        inputController.clear();
        return;
      }
      setState(() {
        selecionados.add(valor);
        inputController.clear();
      });
    }

    final opcoes = sugestoes
        .where((s) => normalizeText(s) != normalizeText(principalAtual))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: Colors.grey.shade700),
            const SizedBox(width: 8),
            Text(
              titulo,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildCategoriaAutocomplete(
                controller: inputController,
                label: 'Adicionar',
                icon: icon,
                opcoes: opcoes,
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: () => addFromInput(inputController.text),
              child: const Text('Adicionar'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (selecionados.isEmpty)
          const Text('Nenhuma adicional selecionada.')
        else
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: _extrasSemPrincipal(selecionados, principalAtual)
                .map(
                  (v) => InputChip(
                    label: Text(v),
                    onDeleted: () => setState(() => selecionados.remove(v)),
                  ),
                )
                .toList(),
          ),
      ],
    );
  }

  /// Autocomplete para categoria/subcategoria com sugestões existentes
  /// Match ignora maiúsculas, acentos etc.
  Widget _buildCategoriaAutocomplete({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required List<String> opcoes,
  }) {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: controller.text),
      optionsBuilder: (textEditingValue) {
        if (textEditingValue.text.isEmpty) {
          return opcoes;
        }
        final norm = normalizeText(textEditingValue.text);
        return opcoes.where((s) => normalizeText(s).contains(norm)).toList();
      },
      onSelected: (value) {
        controller.text = value;
        setState(() {});
      },
      fieldViewBuilder: (context, fieldController, focusNode, onSubmit) {
        if (fieldController.text != controller.text) {
          fieldController.text = controller.text;
        }
        return TextFormField(
          controller: fieldController,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon),
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2),
            ),
          ),
          onChanged: (v) {
            controller.text = v;
            setState(() {});
          },
          onFieldSubmitted: (_) => onSubmit(),
        );
      },
    );
  }

  /// Widget para criar text fields padronizados
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    IconData? icon,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    String? helperText,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextFormField(
      controller: controller,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        prefixIcon: icon != null ? Icon(icon) : null,
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2),
        ),
      ),
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
    );
  }

  /// Widget helper para criar chip de marketplace
  Widget _buildMarketplaceChip(String id, String label, Color color) {
    final selecionado = _marketplacesSelecionados.contains(id);
    return FilterChip(
      label: Text(label),
      selected: selecionado,
      onSelected: (selected) {
        setState(() {
          if (selected) {
            _marketplacesSelecionados.add(id);
          } else {
            _marketplacesSelecionados.remove(id);
          }
        });
      },
      selectedColor: color.withOpacity(0.2),
      checkmarkColor: color,
      backgroundColor: Colors.grey.shade100,
      labelStyle: TextStyle(
        color: selecionado ? color : Colors.black87,
        fontWeight: selecionado ? FontWeight.bold : FontWeight.normal,
      ),
      side: BorderSide(
        color: selecionado ? color : Colors.grey.shade400,
        width: selecionado ? 2 : 1,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
  }
}

/// Widget apenas visual: estado de carregamento da tela de formulário de produto.
class _ProdutoFormLoadingBody extends StatelessWidget {
  const _ProdutoFormLoadingBody();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

