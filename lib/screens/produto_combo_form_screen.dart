// lib/screens/produto_combo_form_screen.dart
// Tela de cadastro de Combo/Kit – produto virtual que agrupa outros produtos.
// Ao vender, dá baixa individual em cada item.

import 'dart:io' show File;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_picker/image_picker.dart';

import '../core/combo_config_canonical.dart';
import '../core/hive_box_names.dart';
import '../models/produto.dart';
import '../utils/moeda_input_formatter.dart';
import '../utils/text_utils.dart';
import '../services/catalogo_sync_service.dart' show CatalogoSyncService, SyncTarget;
import '../services/catalog_publish_service.dart';
import '../services/limits_guard.dart';
import '../services/combo_receita_normalizacao.dart';
import '../services/produtos_firestore_service.dart';
import '../services/store_resolver_facade.dart';
import '../services/ai_loja_service.dart';
import '../services/ia_uso_limite_service.dart';
import '../services/loja_id_service.dart';

String _gerarSlug(String texto) {
  return texto
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
}

class ProdutoComboFormScreen extends StatefulWidget {
  final Produto? combo;

  const ProdutoComboFormScreen({super.key, this.combo});

  @override
  State<ProdutoComboFormScreen> createState() => _ProdutoComboFormScreenState();
}

class _ProdutoComboFormScreenState extends State<ProdutoComboFormScreen> {
  final _form = GlobalKey<FormState>();
  late Box<Produto> produtosBox;
  String? lojaId;
  bool _salvando = false;

  /// Controllers do campo de pesquisa de produto por linha (para Autocomplete).
  final Map<int, TextEditingController> _productControllers = {};

  /// Obrigatório junto com [textEditingController] em [RawAutocomplete].
  final Map<int, FocusNode> _productFocusNodes = {};

  final _nome = TextEditingController();
  final _preco = TextEditingController();
  final _quantidadeDisponivel = TextEditingController(text: '1');
  final _categoria = TextEditingController();
  final _subcategoria = TextEditingController();
  final _categoriaExtraInput = TextEditingController();
  final _subcategoriaExtraInput = TextEditingController();
  final Set<String> _categoriasExtrasSelecionadas = <String>{};
  final Set<String> _subcategoriasExtrasSelecionadas = <String>{};
  final _descricao = TextEditingController();
  final _imagens = <String>[];
  bool _publicar = false;

  /// Desconto do combo (sincronizado no Firestore após save)
  double _descontoComboValor = 0;
  double _descontoComboPercentual = 0;
  /// true após "Aplicar" no diálogo — permite gravar 0,0 ao remover desconto; se false e ambos 0, não sobrescreve o Firestore (preserva após sync).
  bool _descontoComboUsuarioAplicouDialog = false;
  bool _sugerindoDescricao = false;
  bool _sugerindoPreco = false;

  /// Itens do combo: {nome, slug, quantidade, tamanho, cor, productId}. productId obrigatório ao salvar.
  final List<Map<String, dynamic>> _itensCombo = [];

  /// Configuração avançada (grupos/opções) — [Produto.comboConfig]. Vazio = só modo legado.
  final List<_GrupoComboUi> _gruposAvancados = [];

  void _dlog(String msg) {
    if (kDebugMode) {
      // ignore: avoid_print
      print(msg);
    }
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  Produto _comboMaisRecenteNoBox(Produto base) {
    final key = base.key;
    if (key is int) {
      final byKey = produtosBox.get(key);
      if (byKey != null) return byKey;
    }
    final idFb = base.idFirebase.trim();
    if (idFb.isNotEmpty) {
      final byId = produtosBox.values.firstWhereOrNull(
        (p) => p.lojaId == lojaId && p.idFirebase.trim() == idFb,
      );
      if (byId != null) return byId;
    }
    final slug = base.slug.trim();
    if (slug.isNotEmpty) {
      final bySlug = produtosBox.values.firstWhereOrNull(
        (p) => p.lojaId == lojaId && p.slug.trim() == slug,
      );
      if (bySlug != null) return bySlug;
    }
    return base;
  }

  @override
  void dispose() {
    for (final g in _gruposAvancados) {
      g.dispose();
    }
    _gruposAvancados.clear();
    for (final c in _productControllers.values) {
      c.dispose();
    }
    _productControllers.clear();
    for (final f in _productFocusNodes.values) {
      f.dispose();
    }
    _productFocusNodes.clear();
    _nome.dispose();
    _preco.dispose();
    _quantidadeDisponivel.dispose();
    _categoria.dispose();
    _subcategoria.dispose();
    _categoriaExtraInput.dispose();
    _subcategoriaExtraInput.dispose();
    _descricao.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    lojaId = await StoreResolverFacade.resolveForAdminApp();
    if (lojaId == null || lojaId!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nenhuma loja ativa')),
        );
      }
      return;
    }
    produtosBox = Hive.box<Produto>(HiveBoxNames.produtos(lojaId!));

    if (widget.combo != null) {
      final c = _comboMaisRecenteNoBox(widget.combo!);
      _nome.text = c.nome;
      _preco.text = MoedaInputFormatter.format(c.precoFinal);
      _quantidadeDisponivel.text = c.quantidade > 0 ? '${c.quantidade}' : '1';
      _categoria.text = c.categoria;
      _subcategoria.text = c.subcategoria;
      // Legado: categoria padrão "Combo" não é categoria de negócio.
      if (normalizeText(c.categoria.trim()) == 'combo') _categoria.clear();
      if (normalizeText(c.subcategoria.trim()) == 'combo') _subcategoria.clear();
      _categoriasExtrasSelecionadas
          .addAll(c.categoriasExtras.map((e) => canonicalizeCategoria(e)));
      _subcategoriasExtrasSelecionadas
          .addAll(c.subcategoriasExtras.map((e) => canonicalizeCategoria(e)));
      _descricao.text = c.descricao;
      _imagens.addAll(c.imagens);
      _publicar = c.publicadoNoCatalogo;

      if (c.itensCombo != null && c.itensCombo!.isNotEmpty) {
        _itensCombo.clear();
        final antesMigracao = <Map<String, dynamic>>[];
        for (final m in c.itensCombo!) {
          antesMigracao.add(Map<String, dynamic>.from(m));
          final pid = (m['productId'] ?? m['id'] ?? '').toString().trim();
          _itensCombo.add({
            'nome': (m['nome'] ?? '').toString(),
            'slug': (m['slug'] ?? '').toString(),
            'quantidade': (m['quantidade'] ?? 1).toString(),
            'tamanho': (m['tamanho'] ?? '').toString(),
            'cor': (m['cor'] ?? '').toString(),
            if (pid.isNotEmpty) 'productId': pid,
          });
        }
        final lojaProds = produtosBox.values.where((p) => p.lojaId == lojaId);
        for (var i = 0; i < _itensCombo.length; i++) {
          _itensCombo[i] = ComboReceitaNormalizacao.normalizeItem(
            _itensCombo[i],
            lojaProds,
            onLog: _dlog,
          );
        }
        if (ComboReceitaNormalizacao.receitaGanhouProductIdsSeguros(antesMigracao, _itensCombo)) {
          c.itensCombo = _itensCombo.map((e) => Map<String, dynamic>.from(e)).toList();
          await c.save();
          _dlog('[ProdutoCombo] receita migrada: productIds preenchidos com resolução segura no Hive');
        }
      }
    }
    if (_itensCombo.isEmpty) {
      _itensCombo.add({'nome': '', 'slug': '', 'quantidade': '1', 'tamanho': '', 'cor': ''});
    }
    // Carregar desconto do combo (mesmo docId do catálogo: idFirebase > slug > slugify(nome))
    if (widget.combo != null && lojaId != null) {
      try {
        final comboAtual = _comboMaisRecenteNoBox(widget.combo!);
        final docId = CatalogoSyncService.catalogFirestoreDocId(comboAtual);
        Future<Map<String, dynamic>?> fetchDesconto(String collection) async {
          final snap = await FirebaseFirestore.instance
              .collection('lojas')
              .doc(lojaId)
              .collection(collection)
              .doc(docId)
              .get();
          return snap.exists ? snap.data() : null;
        }

        Map<String, dynamic>? d = await fetchDesconto('draft_produtos');
        d ??= await fetchDesconto('produtos');
        if (d != null) {
          if (d['descontoComboValor'] is num) {
            _descontoComboValor = (d['descontoComboValor'] as num).toDouble();
          }
          if (d['descontoComboPercentual'] is num) {
            _descontoComboPercentual = (d['descontoComboPercentual'] as num).toDouble();
          }
        }
      } catch (_) {}
    }
    _hidratarGruposAvancados();
    if (mounted) setState(() => _atualizarPrecoAutomatico());
  }

  void _hidratarGruposAvancados() {
    final c = widget.combo;
    if (c == null || lojaId == null) return;
    final raw = c.comboConfig;
    if (!ComboConfigCanonical.isEffective(raw)) return;
    final grupos = raw![ComboConfigKeys.grupos];
    if (grupos is! List) return;
    for (final g in grupos) {
      if (g is! Map) continue;
      _gruposAvancados.add(
        _GrupoComboUi.fromMap(Map<String, dynamic>.from(g.map((k, v) => MapEntry(k.toString(), v)))),
      );
    }
    for (final gr in _gruposAvancados) {
      gr.resolveNomesProdutos(produtosBox, lojaId!);
    }
  }

  void _adicionarGrupoAvancado() {
    setState(() {
      _gruposAvancados.add(_GrupoComboUi()..opcoes.add(_OpcaoComboUi()));
      _atualizarPrecoAutomatico();
    });
  }

  void _removerGrupoAvancado(int i) {
    if (i < 0 || i >= _gruposAvancados.length) return;
    setState(() {
      _gruposAvancados[i].dispose();
      _gruposAvancados.removeAt(i);
      _atualizarPrecoAutomatico();
    });
  }

  void _adicionarOpcaoNoGrupo(_GrupoComboUi g) {
    setState(() {
      g.opcoes.add(_OpcaoComboUi());
      _atualizarPrecoAutomatico();
    });
  }

  void _removerOpcaoDoGrupo(_GrupoComboUi g, int i) {
    if (g.opcoes.length <= 1) return;
    setState(() {
      g.opcoes[i].dispose();
      g.opcoes.removeAt(i);
      _atualizarPrecoAutomatico();
    });
  }

  /// Estimativa de preço quando não há itens legado preenchidos (soma base + adicional por opção).
  double _somaComboConfigEstimativa() {
    if (lojaId == null) return 0;
    var soma = 0.0;
    for (final g in _gruposAvancados) {
      for (final o in g.opcoes) {
        final pid = o.productId?.trim() ?? '';
        if (pid.isEmpty) continue;
        final p = produtosBox.values.firstWhereOrNull(
          (x) => x.lojaId == lojaId && x.idFirebase.trim() == pid,
        );
        if (p == null) continue;
        final qMin = int.tryParse(o.qtdMin.text) ?? 0;
        final q = qMin > 0 ? qMin : 1;
        final addTxt = o.precoAdicional.text.trim();
        final add = addTxt.isEmpty ? 0.0 : MoedaInputFormatter.parse(addTxt);
        soma += (p.precoFinal + add) * q;
      }
    }
    return soma;
  }

  String? _validarGruposAvancados() {
    if (_gruposAvancados.isEmpty) return null;
    for (var gi = 0; gi < _gruposAvancados.length; gi++) {
      final g = _gruposAvancados[gi];
      final titulo = g.titulo.text.trim();
      if (titulo.isEmpty) {
        return 'Grupo ${gi + 1}: informe o nome do grupo.';
      }
      final smin = int.tryParse(g.selecaoMin.text) ?? 0;
      final smax = int.tryParse(g.selecaoMax.text) ?? 0;
      if (smin < 0 || smax < 0) {
        return 'Grupo "$titulo": seleção mín/máx não pode ser negativa.';
      }
      if (smax > 0 && smin > smax) {
        return 'Grupo "$titulo": seleção mínima não pode ser maior que a máxima.';
      }
      var opComId = 0;
      for (var oi = 0; oi < g.opcoes.length; oi++) {
        final o = g.opcoes[oi];
        final pid = o.productId?.trim() ?? '';
        final nomeDig = o.produtoNomeCtrl.text.trim();
        if (pid.isEmpty && nomeDig.isNotEmpty) {
          return 'Grupo "$titulo": opção ${oi + 1} — selecione o produto na lista (ID obrigatório).';
        }
        if (pid.isNotEmpty) {
          opComId++;
          final p = produtosBox.values.firstWhereOrNull(
            (x) => x.lojaId == lojaId && x.idFirebase.trim() == pid,
          );
          if (p == null) {
            return 'Grupo "$titulo": produto não encontrado no estoque.';
          }
          if (p.idFirebase.trim().isEmpty) {
            return 'Grupo "$titulo": o produto "${p.nome}" ainda não tem ID sincronizado.';
          }
          final qmin = int.tryParse(o.qtdMin.text) ?? 0;
          final qmax = int.tryParse(o.qtdMax.text) ?? 0;
          if (qmin < 0 || qmax < 0) {
            return 'Grupo "$titulo" / "${p.nome}": quantidades não podem ser negativas.';
          }
          if (qmax > 0 && qmin > qmax) {
            return 'Grupo "$titulo" / "${p.nome}": qtd mínima não pode ser maior que a máxima.';
          }
        }
      }
      if (g.obrigatorio && opComId == 0) {
        return 'Grupo "$titulo" é obrigatório: adicione ao menos uma opção com produto vinculado.';
      }
    }
    return null;
  }

  Map<String, dynamic>? _montarComboConfigParaSalvar() {
    if (_gruposAvancados.isEmpty) return null;
    if (lojaId == null) return null;
    final grupos = <Map<String, dynamic>>[];
    for (final g in _gruposAvancados) {
      final gm = g.toMap(produtosBox, lojaId!);
      final ops = gm[ComboConfigKeys.grupoOpcoes] as List?;
      if (ops == null || ops.isEmpty) continue;
      grupos.add(gm);
    }
    if (grupos.isEmpty) return null;
    final raw = <String, dynamic>{
      ComboConfigKeys.version: kComboConfigSchemaVersion,
      ComboConfigKeys.grupos: grupos,
    };
    return ComboConfigCanonical.parseFromFirestore(raw);
  }

  List<Map<String, dynamic>> _derivarItensComboDosGrupos() {
    if (lojaId == null) return [];
    final acc = <String, Map<String, dynamic>>{};
    for (final g in _gruposAvancados) {
      for (final o in g.opcoes) {
        final pid = o.productId?.trim() ?? '';
        if (pid.isEmpty) continue;
        final p = produtosBox.values.firstWhereOrNull(
          (x) => x.lojaId == lojaId && x.idFirebase.trim() == pid,
        );
        if (p == null || p.idFirebase.trim().isEmpty) continue;
        final qMin = int.tryParse(o.qtdMin.text) ?? 0;
        final qAdd = qMin > 0 ? qMin : 1;
        acc.update(
          pid,
          (prev) {
            final pq = (prev['quantidade'] as int) + qAdd;
            return {
              'nome': p.nome,
              'slug': p.slug,
              'productId': pid,
              'quantidade': pq,
              'tamanho': '',
              'cor': '',
            };
          },
          ifAbsent: () => {
            'nome': p.nome,
            'slug': p.slug,
            'productId': p.idFirebase,
            'quantidade': qAdd,
            'tamanho': '',
            'cor': '',
          },
        );
      }
    }
    return acc.values.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  void _adicionarItem() {
    setState(() {
      _itensCombo.add({'nome': '', 'slug': '', 'quantidade': '1', 'tamanho': '', 'cor': ''});
      _atualizarPrecoAutomatico();
    });
  }

  /// Resolve o produto do item via [ComboReceitaNormalizacao] (productId canônico; sem match ambíguo por nome).
  Produto? _produtoParaItemCombo(Map<String, dynamic> item, String loja) {
    final lojaProds = produtosBox.values.where((p) => p.lojaId == loja);
    final norm = ComboReceitaNormalizacao.normalizeItem(item, lojaProds, onLog: _dlog);
    final pid = ComboReceitaNormalizacao.pidFrom(norm);
    if (pid.isEmpty) return null;
    return produtosBox.values.firstWhereOrNull(
      (x) => x.lojaId == loja && x.idFirebase.trim() == pid,
    );
  }

  void _removerItem(int i) {
    if (_itensCombo.length <= 1) return;
    setState(() {
      _itensCombo.removeAt(i);
      for (final c in _productControllers.values) {
        c.dispose();
      }
      _productControllers.clear();
      for (final f in _productFocusNodes.values) {
        f.dispose();
      }
      _productFocusNodes.clear();
      _atualizarPrecoAutomatico();
    });
  }

  Future<void> _abrirDesconto() async {
    final valorCtrl = TextEditingController(
      text: _descontoComboValor > 0 ? MoedaInputFormatter.format(_descontoComboValor) : '',
    );
    final percCtrl = TextEditingController(
      text: _descontoComboPercentual > 0 ? '${_descontoComboPercentual.toInt()}' : '',
    );
    final escolhido = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Desconto do combo'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Desconto em reais (R\$): aplicado sobre a soma dos itens.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: valorCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Desconto (R\$)',
                        border: OutlineInputBorder(),
                        hintText: 'Ex: 10,00',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [MoedaInputFormatter()],
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Ou desconto em percentual (%): aplicado sobre a soma dos itens.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: percCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Desconto (%)',
                        border: OutlineInputBorder(),
                        hintText: 'Ex: 15',
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setDialogState(() {}),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, 'ok'),
                  child: const Text('Aplicar'),
                ),
              ],
            );
          },
        );
      },
    );
    if (escolhido != 'ok' || !mounted) return;
    final valor = MoedaInputFormatter.parse(valorCtrl.text);
    final perc = double.tryParse(percCtrl.text.replaceAll(',', '.').trim()) ?? 0;
    setState(() {
      _descontoComboUsuarioAplicouDialog = true;
      _descontoComboValor = valor > 0 ? valor : 0;
      _descontoComboPercentual = perc > 0 ? perc.clamp(0.0, 100.0) : 0;
      _atualizarPrecoAutomatico();
    });
  }

  /// Calcula a soma dos itens (preço × quantidade) e aplica desconto. Retorna o preço final do combo.
  double _calcularPrecoCombo() {
    var soma = _somaItensCombo();
    if (soma <= 0) soma = _somaComboConfigEstimativa();
    if (soma <= 0) return 0;
    if (_descontoComboValor > 0) {
      return (soma - _descontoComboValor).clamp(0.0, double.infinity);
    }
    if (_descontoComboPercentual > 0) {
      return soma * (1 - _descontoComboPercentual / 100);
    }
    return soma;
  }

  /// Atualiza o campo de preço com o valor calculado (soma dos itens − desconto).
  void _atualizarPrecoAutomatico() {
    final valor = _calcularPrecoCombo();
    _preco.text = MoedaInputFormatter.format(valor);
  }

  Future<void> _persistirDescontoFirestore(String lojaId, String docIdCatalogo) async {
    final semDescontoUi =
        _descontoComboValor <= 0 && _descontoComboPercentual <= 0;
    if (!_descontoComboUsuarioAplicouDialog && semDescontoUi) {
      return;
    }
    try {
      final data = {
        'descontoComboValor': _descontoComboValor,
        'descontoComboPercentual': _descontoComboPercentual,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      final base = FirebaseFirestore.instance.collection('lojas').doc(lojaId);
      await base.collection('draft_produtos').doc(docIdCatalogo).set(data, SetOptions(merge: true));
      await base.collection('produtos').doc(docIdCatalogo).set(data, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _sugerirDescricaoComIa() async {
    final nome = _nome.text.trim();
    if (nome.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Informe o nome do combo para sugerir a descrição.')),
        );
      }
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

  /// Soma dos itens (preço × quantidade) sem desconto, para enviar à IA.
  double _somaItensCombo() {
    if (lojaId == null) return 0;
    double soma = 0;
    for (final item in _itensCombo) {
      final qtd = int.tryParse((item['quantidade'] ?? '0').toString()) ?? 0;
      if (qtd <= 0) continue;
      final p = _produtoParaItemCombo(item, lojaId!);
      if (p != null) soma += p.precoFinal * qtd;
    }
    return soma;
  }

  Future<void> _sugerirPrecoComboIa() async {
    if (lojaId == null) return;
    final itens = <Map<String, dynamic>>[];
    for (final item in _itensCombo) {
      final qtd = int.tryParse((item['quantidade'] ?? '0').toString()) ?? 0;
      if (qtd <= 0) continue;
      final p = _produtoParaItemCombo(item, lojaId!);
      if (p != null) itens.add({'nome': p.nome, 'preco': p.precoFinal});
    }
    if (itens.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Adicione itens ao combo para sugerir preço.')),
        );
      }
      return;
    }
    final lojaIdCombo = await LojaIdService.get();
    if (!await IaUsoLimiteService.canUse(lojaIdCombo, TipoUsoIa.perguntas)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(IaUsoLimiteService.messageLimitExcedido(TipoUsoIa.perguntas)), backgroundColor: Colors.orange.shade700),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _sugerindoPreco = true);
    try {
      final soma = _somaItensCombo();
      final sugestao = await AiLojaService.sugerirPrecoCombo(itens: itens, somaItens: soma);
      if (!mounted) return;
      IaUsoLimiteService.recordUse(lojaIdCombo, TipoUsoIa.perguntas);
      setState(() => _sugerindoPreco = false);
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Sugestão de preço (IA)'),
          content: SingleChildScrollView(child: SelectableText(sugestao)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _sugerindoPreco = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AiLojaService.messageForUser(e)), backgroundColor: Colors.red.shade700),
        );
      }
    }
  }

  Future<void> _pickImgs() async {
    final x = await ImagePicker().pickMultiImage(imageQuality: 90);
    if (x.isEmpty || lojaId == null) return;
    final guard = LimitsGuard();
    final max = await guard.maxImagesPerProduct(null);
    final paths = x.map((e) => e.path).toList();
    final aAdicionar = paths.take(max - _imagens.length).toList();
    if (aAdicionar.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Limite de $max imagem(ns) por produto no plano Free. Faça upgrade para mais.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    setState(() => _imagens.addAll(aAdicionar));
  }

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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Adicionar')),
        ],
      ),
    );
    if ((url ?? '').isEmpty || lojaId == null) return;
    final guard = LimitsGuard();
    final pode = await guard.canAddImagemProduto(lojaId!, currentCount: _imagens.length);
    if (!pode && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Limite de imagens atingido no plano Free. Faça upgrade para mais.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() => _imagens.add(url!));
  }

  Future<void> _salvar() async {
    if (!_form.currentState!.validate()) return;
    if (lojaId == null || lojaId!.isEmpty) return;

    final errAv = _validarGruposAvancados();
    if (errAv != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errAv)));
      }
      return;
    }

    var itensValidos = <Map<String, dynamic>>[];
    for (final item in _itensCombo) {
      final nome = (item['nome'] ?? '').toString().trim();
      final qtd = int.tryParse((item['quantidade'] ?? '0').toString()) ?? 0;
      if (nome.isEmpty || qtd <= 0) continue;

      final p = _produtoParaItemCombo(item, lojaId!);
      if (p == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                ComboReceitaNormalizacao.itemPendente(item)
                    ? 'Item "$nome": selecione o produto na lista (é necessário vínculo por ID; nome ambíguo ou sem correspondência).'
                    : 'Produto "$nome" não encontrado no estoque',
              ),
            ),
          );
        }
        return;
      }
      if (p.idFirebase.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'O produto "${p.nome}" ainda não tem ID sincronizado. Abra o cadastro do produto ou sincronize o estoque antes de salvar o combo.',
              ),
            ),
          );
        }
        return;
      }

      itensValidos.add({
        'nome': p.nome,
        'slug': p.slug,
        'quantidade': qtd,
        'tamanho': (item['tamanho'] ?? '').toString().trim(),
        'cor': (item['cor'] ?? '').toString().trim(),
        'productId': p.idFirebase,
      });
    }

    if (itensValidos.isEmpty) {
      final derived = _derivarItensComboDosGrupos();
      if (derived.isNotEmpty) itensValidos = derived;
    }

    if (itensValidos.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Adicione pelo menos um produto na receita legado ou configure grupos avançados com opções.',
            ),
          ),
        );
      }
      return;
    }

    setState(() => _salvando = true);
    try {
      final preco = MoedaInputFormatter.parse(_preco.text);
      final nome = capitalizeWords(_nome.text.trim());
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
      final slug = '${lojaId!}-combo-${_gerarSlug(nome)}';

      Produto combo;
      if (widget.combo != null) {
        combo = widget.combo!;
        final qtd = int.tryParse(_quantidadeDisponivel.text.trim()) ?? 1;
        // Edição de combo: atualiza somente campos explícitos da UI de combo.
        // Campos administrativos não expostos nesta tela permanecem como estavam.
        final cfgSalvar = _montarComboConfigParaSalvar();
        combo
          ..nome = nome
          ..precoFinal = preco
          ..precoUnitario = preco
          ..categoria = categoriaPrincipal
          ..subcategoria = subcategoriaPrincipal
          ..categoriasExtras = categoriasExtras
          ..subcategoriasExtras = subcategoriasExtras
          ..descricao = _descricao.text.trim()
          ..imagens = List.from(_imagens)
          ..publicadoNoCatalogo = _publicar
          ..tipoProduto = 'combo'
          ..itensCombo = itensValidos
          ..comboConfig = cfgSalvar
          ..quantidade = qtd < 0 ? 0 : qtd
          ..lojaId = lojaId!
          ..custoEditadoNoCadastro = true
          ..updatedAt = DateTime.now();
        _dlog('[ProdutoCombo] edição conservadora: campos não expostos preservados');
        await combo.save();
      } else {
        final guard = LimitsGuard();
        final pode = await guard.canAddProduto(lojaId!);
        if (!pode && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Limite de produtos atingido no plano Free')),
          );
          setState(() => _salvando = false);
          return;
        }

        final qtd = int.tryParse(_quantidadeDisponivel.text.trim()) ?? 1;
        final cfgNovo = _montarComboConfigParaSalvar();
        combo = Produto(
          nome: nome,
          custoReal: 0,
          frete: 0,
          gastosFixos: 0,
          gastosVariaveis: 0,
          precoSugerido: preco,
          precoFinal: preco,
          quantidade: qtd < 0 ? 0 : qtd,
          precoUnitario: preco,
          categoria: categoriaPrincipal,
          subcategoria: subcategoriaPrincipal,
          categoriasExtras: categoriasExtras,
          subcategoriasExtras: subcategoriasExtras,
          dataEntrada: DateTime.now(),
          descricao: _descricao.text.trim(),
          imagens: List.from(_imagens),
          publicadoNoCatalogo: _publicar,
          slug: slug,
          lojaId: lojaId!,
          tipoProduto: 'combo',
          itensCombo: itensValidos,
          comboConfig: cfgNovo,
          custoEditadoNoCadastro: true,
          updatedAt: DateTime.now(),
        );
        await produtosBox.add(combo);
        _dlog('[ProdutoCombo] novo combo criado com defaults seguros');
      }

      final remoteStatus = await ProdutosFirestoreService.syncProdutoComStatus(
        combo,
        lojaId: lojaId,
        enqueueOnFailure: true,
      );
      if (remoteStatus == ProdutoSyncRemotoStatus.confirmado) {
        await CatalogoSyncService.upsertFromProduto(combo, target: SyncTarget.draft);
        await CatalogoSyncService.upsertFromProduto(combo, target: SyncTarget.live);
        await CatalogPublishService.marcarCatalogoPrecisaAtualizar();
        final docIdCatalogo = CatalogoSyncService.catalogFirestoreDocId(combo);
        await _persistirDescontoFirestore(lojaId!, docIdCatalogo);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              remoteStatus == ProdutoSyncRemotoStatus.confirmado
                  ? 'Combo salvo e sincronizado com sucesso'
                  : 'Combo salvo localmente e marcado como pendente de sincronização',
            ),
            backgroundColor: remoteStatus == ProdutoSyncRemotoStatus.confirmado
                ? null
                : Colors.orange,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  List<String> _opcoesUnicasCategoria(Iterable<Produto> produtos) {
    final normToCanon = <String, String>{};
    for (final p in produtos) {
      for (final c in [p.categoria, ...p.categoriasExtras]) {
        final t = c.trim();
        if (t.isEmpty) continue;
        // Combo não usa "Combo" como categoria implícita; não sugerir valor legado do tipo.
        if (p.ehCombo && normalizeText(t) == 'combo') continue;
        final n = normalizeText(t);
        normToCanon[n] = canonicalizeCategoria(t);
      }
    }
    final list = normToCanon.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  List<String> _opcoesUnicasSubcategoria(Iterable<Produto> produtos) {
    final normToCanon = <String, String>{};
    for (final p in produtos) {
      for (final s in [p.subcategoria, ...p.subcategoriasExtras]) {
        final t = s.trim();
        if (t.isEmpty) continue;
        if (p.ehCombo && normalizeText(t) == 'combo') continue;
        final n = normalizeText(t);
        normToCanon[n] = canonicalizeCategoria(t);
      }
    }
    final list = normToCanon.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
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

  Widget _buildCategoriaAutocomplete({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required List<String> opcoes,
  }) {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: controller.text),
      optionsBuilder: (textEditingValue) {
        if (textEditingValue.text.isEmpty) return opcoes;
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
            border: const OutlineInputBorder(),
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

  @override
  Widget build(BuildContext context) {
    if (lojaId == null || !Hive.isBoxOpen(HiveBoxNames.produtos(lojaId!))) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final produtosDaLoja = produtosBox.values
        .where((p) => p.lojaId == lojaId && !p.ehCombo)
        .toList()
      ..sort((a, b) => a.nome.compareTo(b.nome));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.combo != null ? 'Editar Combo' : 'Novo Combo'),
        elevation: 0,
      ),
      body: AbsorbPointer(
        absorbing: _salvando,
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue),
                          SizedBox(width: 12),
                          Text(
                            'Informações do Combo',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _nome,
                        decoration: const InputDecoration(
                          labelText: 'Nome do combo *',
                          hintText: 'Ex: Kit Festa',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o nome' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _preco,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'Preço do combo (R\$) *',
                          border: OutlineInputBorder(),
                          helperText: 'Calculado: soma dos itens − desconto (use o botão Desconto).',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [MoedaInputFormatter()],
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Adicione itens ao combo';
                          final p = MoedaInputFormatter.parse(v);
                          if (p <= 0) return 'Preço deve ser maior que zero (adicione itens e/ou reduza o desconto)';
                          return null;
                        },
                      ),
                      const SizedBox(height: 8),
                      FilledButton.tonalIcon(
                        onPressed: _sugerindoPreco ? null : _sugerirPrecoComboIa,
                        icon: _sugerindoPreco
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.auto_awesome, size: 20),
                        label: Text(_sugerindoPreco ? 'Gerando…' : 'Sugerir preço com IA'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _quantidadeDisponivel,
                        decoration: const InputDecoration(
                          labelText: 'Quantidade disponível (em estoque)',
                          hintText: 'Ex: 2 = 2 combos disponíveis',
                          border: OutlineInputBorder(),
                          helperText: 'Quantos kits/combos deste tipo você tem à venda.',
                        ),
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Informe a quantidade';
                          final q = int.tryParse(v.trim());
                          if (q == null || q < 0) return 'Use 0 ou mais';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
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
                      TextFormField(
                        controller: _descricao,
                        decoration: const InputDecoration(
                          labelText: 'Descrição (opcional)',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 2,
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
                      const SizedBox(height: 12),
                      SwitchListTile(
                        title: const Text('Publicar no catálogo'),
                        value: _publicar,
                        onChanged: (v) => setState(() => _publicar = v),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _abrirDesconto,
                        icon: Icon(
                          _descontoComboValor > 0 || _descontoComboPercentual > 0
                              ? Icons.discount
                              : Icons.percent,
                        ),
                        label: Text(
                          _descontoComboValor > 0 || _descontoComboPercentual > 0
                              ? 'Desconto: ${[
                                    if (_descontoComboValor > 0) 'R\$${MoedaInputFormatter.format(_descontoComboValor)}',
                                    if (_descontoComboPercentual > 0) '${_descontoComboPercentual.toInt()}%',
                                  ].join(' ou ')}'
                              : 'Desconto',
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          alignment: Alignment.centerLeft,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.inventory_2_outlined, color: Colors.green),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Produtos do combo',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _adicionarItem,
                            icon: const Icon(Icons.add),
                            label: const Text('Adicionar'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Ao vender o combo, será dada baixa em cada produto abaixo.',
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.tune, size: 18, color: Colors.blue.shade700),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Variações (tamanho/cor): se os produtos do combo tiverem tamanho ou cor, o cliente escolhe na hora da venda (Nova Venda ou catálogo).',
                                style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      ...List.generate(_itensCombo.length, (i) {
                        final item = _itensCombo[i];
                        final nomeAtual = (item['nome'] ?? '').toString();
                        _productControllers[i] ??= TextEditingController(text: nomeAtual);
                        if (_productControllers[i]!.text != nomeAtual &&
                            !(_productFocusNodes[i]?.hasFocus ?? false)) {
                          _productControllers[i]!.value = TextEditingValue(
                            text: nomeAtual,
                            selection:
                                TextSelection.collapsed(offset: nomeAtual.length),
                          );
                        }
                        final ctrl = _productControllers[i]!;
                        _productFocusNodes.putIfAbsent(i, FocusNode.new);
                        final focusNode = _productFocusNodes[i]!;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 3,
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    return RawAutocomplete<Produto>(
                                      textEditingController: ctrl,
                                      focusNode: focusNode,
                                      displayStringForOption: (p) => p.nome,
                                      optionsBuilder: (value) {
                                        final q = value.text.trim().toLowerCase();
                                        if (q.isEmpty) return produtosDaLoja.take(20);
                                        return produtosDaLoja
                                            .where((p) => p.nome.toLowerCase().contains(q))
                                            .take(20);
                                      },
                                      onSelected: (p) {
                                        setState(() {
                                          item['nome'] = p.nome;
                                          item['slug'] = p.slug;
                                          if (p.idFirebase.trim().isNotEmpty) {
                                            item['productId'] = p.idFirebase;
                                          } else {
                                            item.remove('productId');
                                          }
                                          ctrl.text = p.nome;
                                          _atualizarPrecoAutomatico();
                                        });
                                      },
                                      fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                                        return TextField(
                                          controller: controller,
                                          focusNode: focusNode,
                                          decoration: const InputDecoration(
                                            labelText: 'Produto',
                                            hintText: 'Digite para buscar...',
                                            border: OutlineInputBorder(),
                                            isDense: true,
                                          ),
                                          style: const TextStyle(overflow: TextOverflow.ellipsis),
                                          maxLines: 1,
                                          onChanged: (v) {
                                            setState(() {
                                              item['nome'] = v;
                                              final pid = (item['productId'] ?? '')
                                                  .toString()
                                                  .trim();
                                              if (pid.isNotEmpty) {
                                                final sel = produtosDaLoja
                                                    .firstWhereOrNull(
                                                  (x) =>
                                                      x.idFirebase.trim() ==
                                                      pid,
                                                );
                                                if (sel != null &&
                                                    sel.nome
                                                            .trim()
                                                            .toLowerCase() !=
                                                        v.trim().toLowerCase()) {
                                                  item.remove('productId');
                                                }
                                              }
                                              _atualizarPrecoAutomatico();
                                            });
                                          },
                                        );
                                      },
                                      optionsViewBuilder: (context, onSelected, options) {
                                        return Align(
                                          alignment: Alignment.topLeft,
                                          child: Material(
                                            elevation: 4,
                                            child: ConstrainedBox(
                                              constraints: BoxConstraints(
                                                maxWidth: constraints.maxWidth,
                                                maxHeight: 200,
                                              ),
                                              child: ListView.builder(
                                                padding: EdgeInsets.zero,
                                                shrinkWrap: true,
                                                itemCount: options.length,
                                                itemBuilder: (context, index) {
                                                  final p = options.elementAt(index);
                                                  return InkWell(
                                                    onTap: () => onSelected(p),
                                                    child: Padding(
                                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                                      child: Text(
                                                        p.nome,
                                                        overflow: TextOverflow.ellipsis,
                                                        maxLines: 1,
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 70,
                                child: TextFormField(
                                  initialValue: item['quantidade'] ?? '1',
                                  decoration: const InputDecoration(
                                    labelText: 'Qtd',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  keyboardType: TextInputType.number,
                                  onChanged: (v) {
                                    item['quantidade'] = v;
                                    setState(() => _atualizarPrecoAutomatico());
                                  },
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.remove_circle, color: Colors.red),
                                onPressed: _itensCombo.length > 1 ? () => _removerItem(i) : null,
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildCardConfiguracaoAvancada(produtosDaLoja),
              const SizedBox(height: 16),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.image_outlined, color: Colors.teal),
                          SizedBox(width: 12),
                          Text(
                            'Imagens do combo',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
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
                      if (_imagens.isNotEmpty)
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: _imagens.asMap().entries.map((e) {
                            final i = e.key;
                            final src = e.value;
                            final isBlobOtherOrigin = kIsWeb && src.startsWith('blob:');
                            final preview = isBlobOtherOrigin
                                ? Container(
                                    width: 100,
                                    height: 100,
                                    color: Colors.grey[300],
                                    child: const Icon(Icons.broken_image),
                                  )
                                : (src.startsWith('http') || kIsWeb)
                                    ? Image.network(
                                        src,
                                        width: 100,
                                        height: 100,
                                        fit: BoxFit.cover,
                                      )
                                    : Image.file(
                                        File(src),
                                        width: 100,
                                        height: 100,
                                        fit: BoxFit.cover,
                                      );
                            return Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.grey.shade300, width: 2),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: preview,
                                  ),
                                ),
                                Positioned(
                                  right: -8,
                                  top: -8,
                                  child: Container(
                                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                    child: IconButton(
                                      icon: const Icon(Icons.close, color: Colors.white, size: 18),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () => setState(() => _imagens.removeAt(i)),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
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
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _salvando ? null : _salvar,
                  icon: _salvando
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(_salvando ? 'Salvando...' : 'Salvar combo'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    floatingActionButton: FloatingActionButton(
      onPressed: _abrirMenuIaCombo,
      tooltip: 'IA: descrição e preço do combo',
      backgroundColor: Colors.amber,
      child: const Icon(Icons.auto_awesome, color: Colors.black87),
    ),
    );
  }

  Widget _buildCardConfiguracaoAvancada(List<Produto> produtosDaLoja) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.dashboard_customize_outlined, color: Colors.deepPurple.shade700),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Configuração avançada (grupos)',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple.shade900,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _adicionarGrupoAvancado,
                  icon: const Icon(Icons.add),
                  label: const Text('Grupo'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Opcional. Monte escolhas (ex.: corrente + pingentes). A receita legado acima '
              'continua válida para estoque/catálogo. Se preencher só grupos, a receita será '
              'derivada das opções ao salvar.',
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
            if (_gruposAvancados.isEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Nenhum grupo. Toque em «Grupo» para começar.',
                style: TextStyle(color: Colors.grey[600], fontStyle: FontStyle.italic),
              ),
            ],
            ...List.generate(_gruposAvancados.length, (gi) {
              final g = _gruposAvancados[gi];
              return _buildGrupoEditorCard(g, gi, produtosDaLoja);
            }),
            if (_gruposAvancados.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _resumoTextualGrupos(),
                style: TextStyle(fontSize: 12, color: Colors.grey[800], height: 1.35),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _resumoTextualGrupos() {
    if (_gruposAvancados.isEmpty) return '';
    final b = StringBuffer('Prévia: ');
    for (var i = 0; i < _gruposAvancados.length; i++) {
      final g = _gruposAvancados[i];
      if (i > 0) b.write(' · ');
      final tit = g.titulo.text.trim();
      b.write(tit.isEmpty ? 'Grupo ${i + 1}' : tit);
      b.write(' (${_labelTipoGrupoUi(g.tipo)})');
      final n = g.opcoes.where((o) => (o.productId ?? '').trim().isNotEmpty).length;
      b.write(' — $n opção(ões)');
    }
    return b.toString();
  }

  static String _labelTipoGrupoUi(String t) {
    switch (t) {
      case 'unica_obrigatoria':
        return '1 obrigatória';
      case 'unica_opcional':
        return '1 opcional';
      case 'multipla_opcional':
        return 'múltipla opc.';
      case 'multipla_quantidade':
        return 'múltipla+qtd';
      case 'fixo':
        return 'fixo';
      default:
        return t;
    }
  }

  Widget _buildGrupoEditorCard(_GrupoComboUi g, int gi, List<Produto> produtosDaLoja) {
    final tipoValor =
        kComboConfigTiposGrupo.contains(g.tipo) ? g.tipo : 'unica_obrigatoria';
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Material(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Grupo ${gi + 1}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.deepPurple.shade800,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline, color: Colors.red.shade700),
                    tooltip: 'Remover grupo',
                    onPressed: () => _removerGrupoAvancado(gi),
                  ),
                ],
              ),
              TextField(
                controller: g.titulo,
                decoration: const InputDecoration(
                  labelText: 'Nome do grupo *',
                  hintText: 'Ex: Corrente, Pingentes',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: tipoValor,
                decoration: const InputDecoration(
                  labelText: 'Tipo do grupo',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'unica_obrigatoria',
                    child: Text('Escolha única obrigatória'),
                  ),
                  DropdownMenuItem(
                    value: 'unica_opcional',
                    child: Text('Escolha única opcional'),
                  ),
                  DropdownMenuItem(
                    value: 'multipla_opcional',
                    child: Text('Múltipla opcional'),
                  ),
                  DropdownMenuItem(
                    value: 'multipla_quantidade',
                    child: Text('Múltipla com quantidade'),
                  ),
                  DropdownMenuItem(
                    value: 'fixo',
                    child: Text('Item fixo (sempre incluso)'),
                  ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    g.tipo = v;
                    if (v == 'fixo') g.obrigatorio = true;
                    _atualizarPrecoAutomatico();
                  });
                },
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Grupo obrigatório'),
                value: g.obrigatorio,
                onChanged: g.tipo == 'fixo'
                    ? null
                    : (v) => setState(() {
                          g.obrigatorio = v;
                        }),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: g.selecaoMin,
                      decoration: const InputDecoration(
                        labelText: 'Mín. seleções (opções distintas)',
                        helperText: 'Ex.: 1',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() => _atualizarPrecoAutomatico()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: g.selecaoMax,
                      decoration: const InputDecoration(
                        labelText: 'Máx. (0 = sem limite)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() => _atualizarPrecoAutomatico()),
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Permitir repetir a mesma opção (grupo)'),
                subtitle: const Text(
                  'Relevante para «múltipla com quantidade».',
                  style: TextStyle(fontSize: 11),
                ),
                value: g.permiteRepetirOpcao,
                onChanged: (v) => setState(() => g.permiteRepetirOpcao = v),
              ),
              TextField(
                controller: g.observacao,
                decoration: const InputDecoration(
                  labelText: 'Observação (opcional)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text('Opções', style: TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _adicionarOpcaoNoGrupo(g),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Opção'),
                  ),
                ],
              ),
              ...List.generate(g.opcoes.length, (oi) {
                final o = g.opcoes[oi];
                return _buildOpcaoRow(g, o, gi, oi, produtosDaLoja);
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOpcaoRow(
    _GrupoComboUi g,
    _OpcaoComboUi o,
    int gi,
    int oi,
    List<Produto> produtosDaLoja,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return RawAutocomplete<Produto>(
                      textEditingController: o.produtoNomeCtrl,
                      focusNode: o.focusNode,
                      displayStringForOption: (p) => p.nome,
                      optionsBuilder: (value) {
                        final q = value.text.trim().toLowerCase();
                        if (q.isEmpty) return produtosDaLoja.take(20);
                        return produtosDaLoja
                            .where((p) => p.nome.toLowerCase().contains(q))
                            .take(20);
                      },
                      onSelected: (p) {
                        setState(() {
                          o.productId =
                              p.idFirebase.trim().isNotEmpty ? p.idFirebase : null;
                          o.produtoNomeCtrl.text = p.nome;
                          _atualizarPrecoAutomatico();
                        });
                      },
                      fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                        return TextField(
                          controller: controller,
                          focusNode: focusNode,
                          decoration: const InputDecoration(
                            labelText: 'Produto da opção',
                            hintText: 'Buscar...',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (v) {
                            setState(() {
                              final pid = o.productId ?? '';
                              if (pid.isNotEmpty) {
                                final sel = produtosDaLoja.firstWhereOrNull(
                                  (x) => x.idFirebase.trim() == pid,
                                );
                                if (sel != null &&
                                    sel.nome.trim().toLowerCase() !=
                                        v.trim().toLowerCase()) {
                                  o.productId = null;
                                }
                              }
                              _atualizarPrecoAutomatico();
                            });
                          },
                        );
                      },
                      optionsViewBuilder: (context, onSelected, options) {
                        return Align(
                          alignment: Alignment.topLeft,
                          child: Material(
                            elevation: 4,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: constraints.maxWidth,
                                maxHeight: 200,
                              ),
                              child: ListView.builder(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                itemCount: options.length,
                                itemBuilder: (context, index) {
                                  final p = options.elementAt(index);
                                  return InkWell(
                                    onTap: () => onSelected(p),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 10,
                                      ),
                                      child: Text(
                                        p.nome,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              IconButton(
                icon: Icon(Icons.remove_circle_outline, color: Colors.red.shade700),
                onPressed: g.opcoes.length > 1 ? () => _removerOpcaoDoGrupo(g, oi) : null,
                tooltip: 'Remover opção',
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: o.precoAdicional,
                  decoration: const InputDecoration(
                    labelText: 'Preço adicional (R\$)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [MoedaInputFormatter()],
                  onChanged: (_) => setState(() => _atualizarPrecoAutomatico()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: o.qtdMin,
                  decoration: const InputDecoration(
                    labelText: 'Qtd mín',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() => _atualizarPrecoAutomatico()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: o.qtdMax,
                  decoration: const InputDecoration(
                    labelText: 'Qtd máx (0=livre)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() => _atualizarPrecoAutomatico()),
                ),
              ),
            ],
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Permitir repetir esta opção'),
            value: o.permiteRepetir,
            onChanged: (v) => setState(() => o.permiteRepetir = v),
          ),
        ],
      ),
    );
  }

  void _abrirMenuIaCombo() {
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
                leading: const Icon(Icons.attach_money, color: Colors.green),
                title: const Text('Sugerir preço do combo'),
                onTap: () {
                  Navigator.pop(ctx);
                  _sugerirPrecoComboIa();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _GrupoComboUi {
  _GrupoComboUi({String? presetId})
      : id = (presetId != null && presetId.trim().isNotEmpty)
            ? presetId.trim()
            : _novoIdGrupo();

  static String _novoIdGrupo() => 'g_${DateTime.now().microsecondsSinceEpoch}';

  final String id;
  final titulo = TextEditingController();
  final observacao = TextEditingController();
  String tipo = 'unica_obrigatoria';
  bool obrigatorio = true;
  final selecaoMin = TextEditingController(text: '1');
  final selecaoMax = TextEditingController(text: '0');
  bool permiteRepetirOpcao = true;
  final opcoes = <_OpcaoComboUi>[];

  factory _GrupoComboUi.fromMap(Map<String, dynamic> m) {
    final idRaw = m[ComboConfigKeys.grupoId]?.toString();
    final g = _GrupoComboUi(
      presetId: idRaw != null && idRaw.trim().isNotEmpty ? idRaw : null,
    );
    g.titulo.text = (m[ComboConfigKeys.grupoTitulo] ?? '').toString();
    final tipoRaw = (m[ComboConfigKeys.grupoTipo] ?? 'unica_obrigatoria').toString();
    g.tipo = kComboConfigTiposGrupo.contains(tipoRaw) ? tipoRaw : 'unica_obrigatoria';
    g.obrigatorio = m[ComboConfigKeys.grupoObrigatorio] != false;
    final smin = m[ComboConfigKeys.grupoSelecaoMin];
    final smax = m[ComboConfigKeys.grupoSelecaoMax];
    g.selecaoMin.text =
        '${smin is num ? smin.toInt() : int.tryParse('$smin') ?? 1}';
    g.selecaoMax.text =
        '${smax is num ? smax.toInt() : int.tryParse('$smax') ?? 0}';
    g.permiteRepetirOpcao = m[ComboConfigKeys.grupoPermiteRepetirOpcao] != false;
    g.observacao.text = (m[ComboConfigKeys.grupoObservacao] ?? '').toString();
    final op = m[ComboConfigKeys.grupoOpcoes];
    if (op is List) {
      for (final e in op) {
        if (e is Map) {
          g.opcoes.add(
            _OpcaoComboUi.fromMap(
              Map<String, dynamic>.from(
                e.map((k, v) => MapEntry(k.toString(), v)),
              ),
            ),
          );
        }
      }
    }
    if (g.opcoes.isEmpty) g.opcoes.add(_OpcaoComboUi());
    return g;
  }

  void resolveNomesProdutos(Box<Produto> box, String loja) {
    for (final o in opcoes) {
      final pid = o.productId?.trim() ?? '';
      if (pid.isEmpty) continue;
      final p = box.values.firstWhereOrNull(
        (x) => x.lojaId == loja && x.idFirebase.trim() == pid,
      );
      if (p != null) o.produtoNomeCtrl.text = p.nome;
    }
  }

  Map<String, dynamic> toMap(Box<Produto> box, String lojaId) {
    final ops = <Map<String, dynamic>>[];
    for (final o in opcoes) {
      final om = o.toMap(box, lojaId);
      if (om.isNotEmpty) ops.add(om);
    }
    return {
      ComboConfigKeys.grupoId: id,
      ComboConfigKeys.grupoTitulo: titulo.text.trim(),
      ComboConfigKeys.grupoTipo: tipo,
      ComboConfigKeys.grupoObrigatorio: obrigatorio,
      ComboConfigKeys.grupoSelecaoMin: int.tryParse(selecaoMin.text) ?? 0,
      ComboConfigKeys.grupoSelecaoMax: int.tryParse(selecaoMax.text) ?? 0,
      ComboConfigKeys.grupoPermiteRepetirOpcao: permiteRepetirOpcao,
      if (observacao.text.trim().isNotEmpty)
        ComboConfigKeys.grupoObservacao: observacao.text.trim(),
      ComboConfigKeys.grupoOpcoes: ops,
    };
  }

  void dispose() {
    titulo.dispose();
    observacao.dispose();
    selecaoMin.dispose();
    selecaoMax.dispose();
    for (final o in opcoes) {
      o.dispose();
    }
    opcoes.clear();
  }
}

class _OpcaoComboUi {
  _OpcaoComboUi();

  final produtoNomeCtrl = TextEditingController();
  final focusNode = FocusNode();
  String? productId;
  final precoAdicional = TextEditingController();
  final qtdMin = TextEditingController(text: '0');
  final qtdMax = TextEditingController(text: '0');
  bool permiteRepetir = true;

  factory _OpcaoComboUi.fromMap(Map<String, dynamic> m) {
    final o = _OpcaoComboUi();
    final pid = (m[ComboConfigKeys.opProductId] ?? '').toString().trim();
    o.productId = pid.isEmpty ? null : pid;
    o.produtoNomeCtrl.text = (m[ComboConfigKeys.opNome] ?? '').toString();
    final pa = m[ComboConfigKeys.opPrecoAdicional];
    if (pa is num && pa.toDouble() > 0) {
      o.precoAdicional.text = MoedaInputFormatter.format(pa.toDouble());
    }
    final qn = m[ComboConfigKeys.opQtdMin];
    final qx = m[ComboConfigKeys.opQtdMax];
    o.qtdMin.text = '${qn is num ? qn.toInt() : int.tryParse('$qn') ?? 0}';
    o.qtdMax.text = '${qx is num ? qx.toInt() : int.tryParse('$qx') ?? 0}';
    o.permiteRepetir = m[ComboConfigKeys.opPermiteRepetir] != false;
    return o;
  }

  Map<String, dynamic> toMap(Box<Produto> box, String lojaId) {
    final pid = productId?.trim() ?? '';
    if (pid.isEmpty) return {};
    final p = box.values.firstWhereOrNull(
      (x) => x.lojaId == lojaId && x.idFirebase.trim() == pid,
    );
    final nome = (p?.nome ?? produtoNomeCtrl.text).trim();
    final slug = (p?.slug ?? '').trim();
    final addTxt = precoAdicional.text.trim();
    final add = addTxt.isEmpty ? 0.0 : MoedaInputFormatter.parse(addTxt);
    return {
      ComboConfigKeys.opProductId: pid,
      ComboConfigKeys.opNome: nome,
      if (slug.isNotEmpty) ComboConfigKeys.opSlug: slug,
      if (add > 0) ComboConfigKeys.opPrecoAdicional: add,
      ComboConfigKeys.opQtdMin: int.tryParse(qtdMin.text) ?? 0,
      ComboConfigKeys.opQtdMax: int.tryParse(qtdMax.text) ?? 0,
      ComboConfigKeys.opPermiteRepetir: permiteRepetir,
    };
  }

  void dispose() {
    produtoNomeCtrl.dispose();
    focusNode.dispose();
    precoAdicional.dispose();
    qtdMin.dispose();
    qtdMax.dispose();
  }
}
