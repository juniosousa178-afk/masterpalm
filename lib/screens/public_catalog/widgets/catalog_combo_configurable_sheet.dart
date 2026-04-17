// Sheet do catálogo: combo com [comboConfig] (grupos/opções/quantidades).
// Combos legados sem config efetiva continuam em [CatalogComboVariationSheet].

import 'dart:async' show scheduleMicrotask, unawaited;
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/combo_config_canonical.dart';
import '../../../core/produto_variacao_extra.dart';
import '../../../core/safe_cast.dart' show asMapDeep;
import '../../../utils/platform_adaptive.dart';
import '../../../utils/safe_parse.dart'
    show safeDouble, safeBool, safeInt, safeListString, safeStr;
import '../catalog_estoque_helper.dart';
import 'catalog_after_add_choice_dialog.dart';
import 'catalog_combo_opcao_variacao_block.dart';
import 'catalog_combo_variation_sheet.dart' show showCatalogComboVariationSheetLegacy;

/// Abre sheet de combo: configurável se [comboConfig] efetivo; senão delega ao legado.
Future<void> showCatalogComboVariationSheet({
  required BuildContext context,
  required Map<String, dynamic> comboProduct,
  required List<Map<String, dynamic>> todosProdutos,
  required bool Function(Map<String, dynamic> item) onAdd,
  VoidCallback? onAbrirCarrinho,
  VoidCallback? onAfterSilentAddWhenAdded,
  bool showAfterAddChoiceDialog = true,
}) {
  if (!context.mounted) return Future.value();
  final parsed = ComboConfigCanonical.parseFromFirestore(comboProduct['comboConfig']);
  if (parsed != null && ComboConfigCanonical.isEffective(parsed)) {
    final wideChrome = usePointerFirstChrome(context);
    Widget body() {
      return CatalogComboConfigurableSheet(
        comboProduct: comboProduct,
        comboConfig: parsed,
        todosProdutos: todosProdutos,
        onAdd: onAdd,
        onAbrirCarrinho: onAbrirCarrinho,
        onAfterSilentAddWhenAdded: onAfterSilentAddWhenAdded,
        showAfterAddChoiceDialog: showAfterAddChoiceDialog,
      );
    }

    if (wideChrome) {
      return showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (sheetContext) {
          final mq = MediaQuery.of(sheetContext);
          final theme = Theme.of(sheetContext);
          final maxW = math.min(kMaxContentWidth, mq.size.width - 40);
          return Dialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxW,
                maxHeight: mq.size.height * 0.92,
              ),
              child: Material(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: body(),
              ),
            ),
          );
        },
      );
    }
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => body(),
    );
  }

  return showCatalogComboVariationSheetLegacy(
    context: context,
    comboProduct: comboProduct,
    todosProdutos: todosProdutos,
    onAdd: onAdd,
    onAbrirCarrinho: onAbrirCarrinho,
    onAfterSilentAddWhenAdded: onAfterSilentAddWhenAdded,
    showAfterAddChoiceDialog: showAfterAddChoiceDialog,
  );
}

class CatalogComboConfigurableSheet extends StatefulWidget {
  final Map<String, dynamic> comboProduct;
  final Map<String, dynamic> comboConfig;
  final List<Map<String, dynamic>> todosProdutos;
  final bool Function(Map<String, dynamic> item) onAdd;
  final VoidCallback? onAbrirCarrinho;
  final VoidCallback? onAfterSilentAddWhenAdded;
  final bool showAfterAddChoiceDialog;

  const CatalogComboConfigurableSheet({
    super.key,
    required this.comboProduct,
    required this.comboConfig,
    required this.todosProdutos,
    required this.onAdd,
    this.onAbrirCarrinho,
    this.onAfterSilentAddWhenAdded,
    this.showAfterAddChoiceDialog = true,
  });

  @override
  State<CatalogComboConfigurableSheet> createState() =>
      _CatalogComboConfigurableSheetState();
}

class _SelGrupo {
  /// Índice da opção escolhida (única).
  int? unicaIdx;

  /// Índices marcados (múltipla opcional).
  final Set<int> multiIdx = {};

  /// opIndex -> quantidade (múltipla com quantidade / fixo).
  final Map<int, int> qty = {};
}

class _CatalogComboConfigurableSheetState
    extends State<CatalogComboConfigurableSheet> {
  late List<Map<String, dynamic>> _grupos;
  late List<_SelGrupo> _sel;
  int _qtdKits = 1;

  /// `'gi.oi'` → tamanho/cor/extra (mesmo contrato mental do combo legado).
  final Map<String, Map<String, String>> _varPorOp = {};

  List<Map<String, dynamic>> get _gruposList {
    final g = widget.comboConfig[ComboConfigKeys.grupos];
    if (g is! List) return [];
    return g.whereType<Map>().map((e) => Map<String, dynamic>.from(e.map((k, v) => MapEntry(k.toString(), v)))).toList();
  }

  @override
  void initState() {
    super.initState();
    _grupos = _gruposList;
    _sel = List.generate(_grupos.length, (_) => _SelGrupo());
    for (var gi = 0; gi < _grupos.length; gi++) {
      _inicializarGrupo(gi);
    }
  }

  String _normTipo(Map<String, dynamic> g) {
    final t = (g[ComboConfigKeys.grupoTipo] ?? '').toString().trim();
    if (t == 'multipla') return 'multipla_opcional';
    return t;
  }

  List<Map<String, dynamic>> _opcoesDe(Map<String, dynamic> g) {
    final raw = g[ComboConfigKeys.grupoOpcoes];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e.map((k, v) => MapEntry(k.toString(), v))))
        .toList();
  }

  void _inicializarGrupo(int gi) {
    final g = _grupos[gi];
    final tipo = _normTipo(g);
    final opcoes = _opcoesDe(g);
    final st = _sel[gi];
    st.unicaIdx = null;
    st.multiIdx.clear();
    st.qty.clear();

    if (tipo == 'fixo') {
      for (var oi = 0; oi < opcoes.length; oi++) {
        final qMin = _opQtdMin(opcoes[oi]);
        st.qty[oi] = math.max(qMin, 1);
      }
      return;
    }
    if (tipo == 'multipla_quantidade') {
      for (var oi = 0; oi < opcoes.length; oi++) {
        final qMin = _opQtdMin(opcoes[oi]);
        st.qty[oi] = qMin;
      }
    }
  }

  int _opQtdMin(Map<String, dynamic> op) {
    final v = op[ComboConfigKeys.opQtdMin];
    if (v is num) return math.max(0, v.toInt());
    return math.max(0, int.tryParse('$v') ?? 0);
  }

  int _opQtdMax(Map<String, dynamic> op) {
    final v = op[ComboConfigKeys.opQtdMax];
    if (v is num) return math.max(0, v.toInt());
    return math.max(0, int.tryParse('$v') ?? 0);
  }

  double _opPrecoAdicional(Map<String, dynamic> op) {
    final v = op[ComboConfigKeys.opPrecoAdicional];
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }

  Map<String, dynamic>? _findProductById(String id) {
    final sid = id.trim();
    if (sid.isEmpty) return null;
    for (final p in widget.todosProdutos) {
      if ((p['id'] ?? '').toString().trim() == sid) return p;
    }
    return null;
  }

  Map<String, dynamic>? _produtoParaOpcao(Map<String, dynamic> op) {
    final id = (op[ComboConfigKeys.opProductId] ?? '').toString().trim();
    if (id.isNotEmpty) return _findProductById(id);
    return null;
  }

  String _vk(int gi, int oi) => '$gi.$oi';

  Map<String, String> _varsGiOi(int gi, int oi) => _varPorOp.putIfAbsent(
        _vk(gi, oi),
        () => {'tamanho': '', 'cor': '', 'extra': ''},
      );

  void _setVarsGiOi(
    int gi,
    int oi, {
    required String tamanho,
    required String cor,
    required String extra,
  }) {
    _varPorOp[_vk(gi, oi)] = {
      'tamanho': tamanho,
      'cor': cor,
      'extra': extra,
    };
  }

  double _precoDoProdutoParaSelecao(
      Map<String, dynamic> p, String tamanho, String cor) {
    final base = safeDouble(p['preco']);
    final tam = tamanho.trim();
    final c = cor.trim();
    final variacoes = asMapDeep(p['variacoes']);
    if (tam.isNotEmpty && variacoes.isNotEmpty && variacoes[tam] is Map) {
      final mapa = variacoes[tam] as Map;
      if (c.isNotEmpty && mapa[c] != null) {
        final pv = mapa[c];
        if (pv is Map && pv['preco'] is num) return (pv['preco'] as num).toDouble();
      }
    }
    if ((tam.isEmpty || tam == 'sem-tamanho') &&
        variacoes['sem-tamanho'] is Map &&
        c.isNotEmpty) {
      final st = variacoes['sem-tamanho'] as Map;
      final pv = st[c];
      if (pv is Map && pv['preco'] is num) return (pv['preco'] as num).toDouble();
    }
    final ppt = p['precoPorTamanho'];
    if (ppt is Map && ppt.isNotEmpty && tam.isNotEmpty) {
      final v = ppt[tam];
      if (v is num) return v.toDouble();
    }
    return base;
  }

  double _linhaUnitaria(int gi, int oi, Map<String, dynamic> op) {
    final p = _produtoParaOpcao(op);
    final v = _varsGiOi(gi, oi);
    final base = p != null
        ? _precoDoProdutoParaSelecao(
            p,
            v['tamanho'] ?? '',
            v['cor'] ?? '',
          )
        : 0.0;
    return base + _opPrecoAdicional(op);
  }

  double get _precoBaseComboConfig {
    final v = widget.comboConfig[ComboConfigKeys.precoBase];
    if (v is num) return v.toDouble();
    return 0;
  }

  double get _subtotalAntesDescontoCombo {
    var s = _precoBaseComboConfig;
    for (var gi = 0; gi < _grupos.length; gi++) {
      final g = _grupos[gi];
      final tipo = _normTipo(g);
      final opcoes = _opcoesDe(g);
      final st = _sel[gi];
      switch (tipo) {
        case 'unica_obrigatoria':
        case 'unica_opcional':
          final idx = st.unicaIdx;
          if (idx != null && idx >= 0 && idx < opcoes.length) {
            s += _linhaUnitaria(gi, idx, opcoes[idx]);
          }
          break;
        case 'multipla_opcional':
          for (final idx in st.multiIdx) {
            if (idx >= 0 && idx < opcoes.length) {
              s += _linhaUnitaria(gi, idx, opcoes[idx]);
            }
          }
          break;
        case 'multipla_quantidade':
        case 'fixo':
          st.qty.forEach((oi, q) {
            if (q > 0 && oi >= 0 && oi < opcoes.length) {
              s += _linhaUnitaria(gi, oi, opcoes[oi]) * q;
            }
          });
          break;
      }
    }
    return s;
  }

  double get _descontoComboValor =>
      (widget.comboProduct['descontoComboValor'] is num)
          ? (widget.comboProduct['descontoComboValor'] as num).toDouble()
          : 0.0;

  double get _descontoComboPercentual =>
      (widget.comboProduct['descontoComboPercentual'] is num)
          ? (widget.comboProduct['descontoComboPercentual'] as num).toDouble()
          : 0.0;

  double get _precoFinalUnidadeKit {
    final sub = _subtotalAntesDescontoCombo;
    if (sub <= 0) return 0;
    final dValor = _descontoComboValor;
    final dPerc = _descontoComboPercentual;
    if (dValor <= 0 && dPerc <= 0) return sub;
    final comValor = (sub - dValor).clamp(0.0, double.infinity);
    final comPerc = sub * (1 - dPerc / 100).clamp(0.0, double.infinity);
    return comValor < comPerc ? comValor : comPerc;
  }

  double get _percentualDescontoPix =>
      safeDouble(widget.comboProduct['percentualDescontoPix']);

  bool get _divideSemJuros => safeBool(widget.comboProduct['divideSemJuros']);

  int get _maxParcelas =>
      safeBool(widget.comboProduct['divideSemJuros'])
          ? safeInt(widget.comboProduct['maxParcelasSemJuros'], 12).clamp(1, 24)
          : 12;

  String _fmt2(num v) => v.toStringAsFixed(2).replaceAll('.', ',');

  double _parcelaComJuros(double valor, double taxaMensalPct, int n) {
    if (n <= 0 || taxaMensalPct <= 0) return valor / n;
    final i = taxaMensalPct / 100;
    var p = 1.0;
    for (var k = 0; k < n; k++) {
      p *= (1 + i);
    }
    return valor * (i * p) / (p - 1);
  }

  String _textoParcelamento(double precoTotal) {
    final n = _maxParcelas.clamp(1, 24);
    if (_divideSemJuros) {
      return '$n x de R\$ ${_fmt2(precoTotal / n)} sem juros';
    }
    final jurosRaw = widget.comboProduct['jurosParcelamento'];
    final juros = (jurosRaw is num)
        ? jurosRaw.toDouble()
        : double.tryParse('$jurosRaw') ?? 0;
    if (juros > 0) {
      final parc = _parcelaComJuros(precoTotal, juros, n);
      return 'Até $n x de R\$ ${_fmt2(parc)}';
    }
    return 'Até $n x de R\$ ${_fmt2(precoTotal / n)}';
  }

  int _grupoSelecaoMin(Map<String, dynamic> g) {
    final v = g[ComboConfigKeys.grupoSelecaoMin];
    if (v is num) return math.max(0, v.toInt());
    return math.max(0, int.tryParse('$v') ?? 0);
  }

  int _grupoSelecaoMax(Map<String, dynamic> g) {
    final v = g[ComboConfigKeys.grupoSelecaoMax];
    if (v is num) return math.max(0, v.toInt());
    return math.max(0, int.tryParse('$v') ?? 0);
  }

  bool _grupoPermiteRepetir(Map<String, dynamic> g) =>
      g[ComboConfigKeys.grupoPermiteRepetirOpcao] != false;

  bool _opPermiteRepetir(Map<String, dynamic> op) =>
      op[ComboConfigKeys.opPermiteRepetir] != false;

  int _contagemSelecoesDistintas(_SelGrupo st, String tipo) {
    if (tipo == 'multipla_opcional') return st.multiIdx.length;
    if (tipo == 'multipla_quantidade' || tipo == 'fixo') {
      var c = 0;
      st.qty.forEach((_, q) {
        if (q > 0) c++;
      });
      return c;
    }
    return st.unicaIdx != null ? 1 : 0;
  }

  String? _erroValidacao() {
    for (var gi = 0; gi < _grupos.length; gi++) {
      final g = _grupos[gi];
      final tipo = _normTipo(g);
      final opcoes = _opcoesDe(g);
      final st = _sel[gi];
      final obr = g[ComboConfigKeys.grupoObrigatorio] != false;
      final tit =
          (g[ComboConfigKeys.grupoTitulo] ?? 'Grupo ${gi + 1}').toString();

      if (tipo == 'unica_obrigatoria') {
        if (st.unicaIdx == null) return 'Escolha uma opção em «$tit».';
      }
      final minS = _grupoSelecaoMin(g);
      final maxS = _grupoSelecaoMax(g);
      if (tipo == 'multipla_opcional' || tipo == 'multipla_quantidade') {
        final cnt = _contagemSelecoesDistintas(st, tipo);
        if (obr && cnt < minS) {
          return '«$tit»: selecione ao menos $minS opção(ões).';
        }
        if (maxS > 0 && cnt > maxS) {
          return '«$tit»: no máximo $maxS opção(ões).';
        }
      }
      if (tipo == 'unica_obrigatoria' || tipo == 'unica_opcional') {
        final idx = st.unicaIdx;
        if (idx != null && idx >= 0 && idx < opcoes.length) {
          final pid = (opcoes[idx][ComboConfigKeys.opProductId] ?? '')
              .toString()
              .trim();
          if (pid.isEmpty) {
            return '«$tit»: a opção escolhida não tem produto vinculado (não é possível reservar estoque).';
          }
        }
      } else if (tipo == 'multipla_opcional') {
        for (final idx in st.multiIdx) {
          if (idx < 0 || idx >= opcoes.length) continue;
          final pid = (opcoes[idx][ComboConfigKeys.opProductId] ?? '')
              .toString()
              .trim();
          if (pid.isEmpty) {
            return '«$tit»: uma opção marcada não tem produto vinculado (não é possível reservar estoque).';
          }
        }
      }
      if (tipo == 'multipla_quantidade' || tipo == 'fixo') {
        for (var oi = 0; oi < opcoes.length; oi++) {
          final op = opcoes[oi];
          final q = st.qty[oi] ?? 0;
          if (q <= 0) continue;
          final pid =
              (op[ComboConfigKeys.opProductId] ?? '').toString().trim();
          if (pid.isEmpty) {
            return '«$tit»: ${_nomeOpcao(op)} não tem produto vinculado (não é possível reservar estoque).';
          }
          final qmin = _opQtdMin(op);
          final qmax = _opQtdMax(op);
          if (q < qmin) {
            return '«$tit»: quantidade mínima ${_nomeOpcao(op)} é $qmin.';
          }
          if (qmax > 0 && q > qmax) {
            return '«$tit»: quantidade máxima ${_nomeOpcao(op)} é $qmax.';
          }
          if (!_grupoPermiteRepetir(g) && q > 1) {
            return '«$tit»: não é permitido repetir mais de uma unidade de ${_nomeOpcao(op)}.';
          }
          if (!_opPermiteRepetir(op) && q > 1) {
            return '«$tit»: ${_nomeOpcao(op)} admite no máximo 1 unidade.';
          }
        }
      }
    }
    return _erroVariacoesObrigatorias();
  }

  String? _erroVariacoesObrigatorias() {
    for (var gi = 0; gi < _grupos.length; gi++) {
      final g = _grupos[gi];
      final tipo = _normTipo(g);
      final opcoes = _opcoesDe(g);
      final st = _sel[gi];
      bool ativa(int oi) {
        if (oi < 0 || oi >= opcoes.length) return false;
        switch (tipo) {
          case 'unica_obrigatoria':
          case 'unica_opcional':
            return st.unicaIdx == oi;
          case 'multipla_opcional':
            return st.multiIdx.contains(oi);
          case 'multipla_quantidade':
          case 'fixo':
            return (st.qty[oi] ?? 0) > 0;
          default:
            return false;
        }
      }

      for (var oi = 0; oi < opcoes.length; oi++) {
        if (!ativa(oi)) continue;
        final op = opcoes[oi];
        final p = _produtoParaOpcao(op);
        final nome = _nomeOpcao(op);
        final v = _varsGiOi(gi, oi);
        final msg = catalogComboOpcaoVariacaoMensagemErro(
          p,
          {
            'tamanho': v['tamanho'] ?? '',
            'cor': v['cor'] ?? '',
            'extra': v['extra'] ?? '',
          },
          nome,
        );
        if (msg != null) return msg;
      }
    }
    return null;
  }

  String _nomeOpcao(Map<String, dynamic> op) {
    final p = _produtoParaOpcao(op);
    if (p != null) return (p['nome'] ?? '').toString();
    return (op[ComboConfigKeys.opNome] ?? 'Item').toString();
  }

  /// Trecho «Tam/Cor/Extra» alinhado a [ProdutoVariacaoExtra.linhaVariacoesParaSeparacao].
  String _textoVariacaoUi(int gi, int oi, Map<String, dynamic> op) {
    final p = _produtoParaOpcao(op);
    final v = _varsGiOi(gi, oi);
    var tam = (v['tamanho'] ?? '').trim();
    var cor = (v['cor'] ?? '').trim();
    final extra = (v['extra'] ?? '').trim();
    if (cor == 'sem-cor') cor = '';
    if (tam == 'sem-tamanho') tam = '';
    final corKey = cor.isEmpty ? 'sem-cor' : cor;
    final tamKey = tam.isEmpty ? 'sem-tamanho' : tam;
    final extraTipo = (extra.isNotEmpty && p != null)
        ? ProdutoVariacaoExtra.tipoParaCelula(
            p['variacoesExtraTipo'] != null
                ? asMapDeep(p['variacoesExtraTipo'])
                : null,
            tamKey,
            corKey,
            extra,
          )
        : '';
    final resumo = extra.isNotEmpty
        ? ProdutoVariacaoExtra.textoResumoExtra(
            extraTipo: extraTipo,
            extraValor: extra,
          )
        : '';
    final m = <String, dynamic>{
      'tamanho': tam,
      'cor': cor,
      if (extra.isNotEmpty) 'extraValor': extra,
      if (extraTipo.isNotEmpty) 'extraTipo': extraTipo,
      if (resumo.isNotEmpty) 'variacaoExtraResumo': resumo,
    };
    final s = ProdutoVariacaoExtra.linhaVariacoesParaSeparacao(m).trim();
    return s.isEmpty ? '' : ' ($s)';
  }

  String _nomeOpcaoComVar(int gi, int oi, Map<String, dynamic> op) {
    final base = _nomeOpcao(op);
    return '$base${_textoVariacaoUi(gi, oi, op)}';
  }

  List<Map<String, dynamic>> _montarLinhasSelecaoPorKit() {
    final out = <Map<String, dynamic>>[];
    for (var gi = 0; gi < _grupos.length; gi++) {
      final g = _grupos[gi];
      final tipo = _normTipo(g);
      final opcoes = _opcoesDe(g);
      final st = _sel[gi];
      void addLinha(int oi, int q) {
        if (q <= 0 || oi < 0 || oi >= opcoes.length) return;
        final op = opcoes[oi];
        final p = _produtoParaOpcao(op);
        final pid = (op[ComboConfigKeys.opProductId] ?? '').toString().trim();
        if (pid.isEmpty) return;
        final nome = (p?['nome'] ?? op[ComboConfigKeys.opNome] ?? '').toString();
        final slug = (p?['slug'] ?? op[ComboConfigKeys.opSlug] ?? '').toString();
        final v = _varsGiOi(gi, oi);
        final tam = (v['tamanho'] ?? '').trim();
        final cor = (v['cor'] ?? '').trim();
        final extra = (v['extra'] ?? '').trim();
        final corKey = cor.isEmpty ? 'sem-cor' : cor;
        final tamKey = tam.isEmpty ? 'sem-tamanho' : tam;
        final extraTipo = (extra.isNotEmpty && p != null)
            ? ProdutoVariacaoExtra.tipoParaCelula(
                p['variacoesExtraTipo'] != null
                    ? asMapDeep(p['variacoesExtraTipo'])
                    : null,
                tamKey,
                corKey,
                extra,
              )
            : '';
        final resumoExtra = extra.isNotEmpty
            ? ProdutoVariacaoExtra.textoResumoExtra(
                extraTipo: extraTipo,
                extraValor: extra,
              )
            : '';
        out.add({
          'nome': nome,
          'slug': slug,
          'productId': pid,
          'quantidade': q,
          'tamanho': tam,
          'cor': cor,
          if (extra.isNotEmpty) 'extraValor': extra,
          if (extraTipo.isNotEmpty) 'extraTipo': extraTipo,
          if (resumoExtra.isNotEmpty) 'variacaoExtraResumo': resumoExtra,
        });
      }

      switch (tipo) {
        case 'unica_obrigatoria':
        case 'unica_opcional':
          final idx = st.unicaIdx;
          if (idx != null) addLinha(idx, 1);
          break;
        case 'multipla_opcional':
          for (final idx in st.multiIdx) {
            addLinha(idx, 1);
          }
          break;
        case 'multipla_quantidade':
        case 'fixo':
          st.qty.forEach((oi, q) => addLinha(oi, q));
          break;
      }
    }

    final merged = <String, Map<String, dynamic>>{};
    for (final linha in out) {
      final pid = (linha['productId'] ?? '').toString();
      final tam = (linha['tamanho'] ?? '').toString();
      final cor = (linha['cor'] ?? '').toString();
      final ex =
          (linha['extraValor'] ?? linha['variacaoExtra'] ?? '').toString();
      final key = '$pid|$tam|$cor|$ex';
      merged.update(
        key,
        (prev) {
          final pq = (prev['quantidade'] as num).toInt() +
              (linha['quantidade'] as num).toInt();
          return {...prev, 'quantidade': pq};
        },
        ifAbsent: () => Map<String, dynamic>.from(linha),
      );
    }
    return merged.values.toList();
  }

  String _montarResumoLegivel() {
    final buf = StringBuffer();
    for (var gi = 0; gi < _grupos.length; gi++) {
      final g = _grupos[gi];
      final tit =
          (g[ComboConfigKeys.grupoTitulo] ?? 'Grupo').toString().trim();
      final tipo = _normTipo(g);
      final opcoes = _opcoesDe(g);
      final st = _sel[gi];
      final partes = <String>[];
      switch (tipo) {
        case 'unica_obrigatoria':
        case 'unica_opcional':
          final idx = st.unicaIdx;
          if (idx != null && idx < opcoes.length) {
            partes.add(_nomeOpcaoComVar(gi, idx, opcoes[idx]));
          } else if (tipo == 'unica_opcional') {
            partes.add('(nenhum)');
          }
          break;
        case 'multipla_opcional':
          for (final idx in st.multiIdx.toList()..sort()) {
            if (idx < opcoes.length) {
              partes.add(_nomeOpcaoComVar(gi, idx, opcoes[idx]));
            }
          }
          break;
        case 'multipla_quantidade':
        case 'fixo':
          st.qty.forEach((oi, q) {
            if (q > 0 && oi < opcoes.length) {
              final n = _nomeOpcaoComVar(gi, oi, opcoes[oi]);
              partes.add(q > 1 ? '$n ×$q' : n);
            }
          });
          break;
      }
      if (partes.isEmpty) continue;
      if (buf.isNotEmpty) buf.write(' · ');
      buf.write('$tit: ${partes.join(', ')}');
    }
    return buf.toString();
  }

  bool _estoqueOkParaLinhas(List<Map<String, dynamic>> linhasPorKit) {
    for (final linha in linhasPorKit) {
      final need = (linha['quantidade'] as num).toInt() * _qtdKits;
      if (need <= 0) continue;
      final p = _findProductById((linha['productId'] ?? '').toString());
      if (p == null) continue;
      final tam = (linha['tamanho'] ?? '').toString().trim();
      final cor = (linha['cor'] ?? '').toString().trim();
      final ex = (linha['extraValor'] ?? linha['variacaoExtra'] ?? '')
          .toString()
          .trim();
      final avail = CatalogEstoqueHelper.estoqueDisponivelVariacao(
        p,
        tam,
        cor,
        ex,
      );
      if (avail < need) {
        final nome = (linha['nome'] ?? '').toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              avail <= 0
                  ? 'Sem estoque: $nome'
                  : 'Estoque insuficiente para $nome (disponível: $avail).',
            ),
          ),
        );
        return false;
      }
    }
    return true;
  }

  Future<void> _confirmar() async {
    final err = _erroValidacao();
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    final linhasKit = _montarLinhasSelecaoPorKit();
    if (linhasKit.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione as opções do combo.')),
      );
      return;
    }
    if (!_estoqueOkParaLinhas(linhasKit)) return;

    final selecao = <Map<String, dynamic>>[];
    for (final linha in linhasKit) {
      final m = Map<String, dynamic>.from(linha);
      final q = (m['quantidade'] as num).toInt() * _qtdKits;
      m['quantidade'] = q;
      selecao.add(m);
    }

    final preco = _precoFinalUnidadeKit;
    final img = safeListString(widget.comboProduct['imagens']).isNotEmpty
        ? safeListString(widget.comboProduct['imagens']).first
        : safeStr(widget.comboProduct['imageUrl']);
    final resumo = _montarResumoLegivel();
    final item = {
      'produtosId': widget.comboProduct['id'],
      'id': widget.comboProduct['id'],
      'nome': widget.comboProduct['nome'],
      'preco': preco,
      'percentualDescontoPix': safeDouble(widget.comboProduct['percentualDescontoPix']),
      'divideSemJuros': safeBool(widget.comboProduct['divideSemJuros']),
      'maxParcelasSemJuros': safeInt(widget.comboProduct['maxParcelasSemJuros'], 12),
      if (widget.comboProduct['jurosParcelamento'] != null)
        'jurosParcelamento': widget.comboProduct['jurosParcelamento'],
      'quantidade': _qtdKits,
      'imageUrl': img,
      'url_foto': img,
      'slug': widget.comboProduct['slug'],
      'peso': safeDouble(widget.comboProduct['peso']),
      'tipoEmbalagem': safeStr(widget.comboProduct['tipoEmbalagem'], 'padrao'),
      'tamanho': '',
      'cor': '',
      'itensComboComSelecao': selecao,
      if (resumo.isNotEmpty) 'comboConfiguravelResumo': resumo,
    };
    final added = widget.onAdd(item);
    if (!added) return;

    final onCart = widget.onAbrirCarrinho;
    final onSilent = widget.onAfterSilentAddWhenAdded;
    if (!widget.showAfterAddChoiceDialog) {
      if (!mounted) return;
      Navigator.of(context).pop();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        scheduleMicrotask(() {
          onSilent?.call();
        });
      });
      return;
    }
    final irCarrinho = await showCatalogAfterAddChoiceDialog(context);
    if (!mounted) return;
    Navigator.of(context).pop();
    // Pós-pop: frame + microtask evita corrida com overlay/route (web/desktop).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduleMicrotask(() {
        if (irCarrinho && onCart != null) {
          onCart();
        } else if (!irCarrinho && onSilent != null) {
          onSilent();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final precoUn = _precoFinalUnidadeKit;
    final precoTotal = precoUn * _qtdKits;
    final pctPix = _percentualDescontoPix;
    final precoPix = pctPix > 0 ? precoTotal * (1 - pctPix / 100) : precoTotal;
    final sheetH = MediaQuery.sizeOf(context).height * 0.88;
    final linhasKitPreview = _montarLinhasSelecaoPorKit();
    final capKitsEstoque = linhasKitPreview.isEmpty
        ? null
        : CatalogEstoqueHelper.maxKitsMontaveisParaReceitaCatalogo(
            catalogProducts: widget.todosProdutos,
            linhasPorKit: linhasKitPreview,
          );
    if (capKitsEstoque != null &&
        capKitsEstoque > 0 &&
        _qtdKits > capKitsEstoque) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _qtdKits = capKitsEstoque);
      });
    }

    return SafeArea(
      child: SizedBox(
        height: sheetH,
        child: Material(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.tune, color: theme.colorScheme.primary, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Montar combo',
                            style: theme.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Escolha as opções de cada grupo',
                            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
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
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var gi = 0; gi < _grupos.length; gi++)
                        _buildGrupoCard(gi, theme),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Text('Quantidade de kits'),
                          const Spacer(),
                          IconButton(
                            onPressed: _qtdKits > 1
                                ? () => setState(() => _qtdKits--)
                                : null,
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          Text('$_qtdKits', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                          IconButton(
                            onPressed: () {
                              if (capKitsEstoque != null &&
                                  capKitsEstoque > 0 &&
                                  _qtdKits >= capKitsEstoque) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'No máximo $capKitsEstoque kit(s) para esta montagem (estoque).',
                                    ),
                                  ),
                                );
                                return;
                              }
                              if (capKitsEstoque == 0 &&
                                  linhasKitPreview.isNotEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Sem estoque suficiente para esta montagem.',
                                    ),
                                  ),
                                );
                                return;
                              }
                              setState(() => _qtdKits++);
                            },
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        ],
                      ),
                      if (linhasKitPreview.isNotEmpty) ...[
                        if (capKitsEstoque != null && capKitsEstoque > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'Com esta montagem: até $capKitsEstoque kit(s) conforme estoque.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[700],
                              ),
                            ),
                          )
                        else if (capKitsEstoque == 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'Estoque insuficiente para os itens desta montagem.',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.35),
                  border: Border(
                    top: BorderSide(color: theme.dividerColor.withOpacity(0.5)),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total', style: TextStyle(fontWeight: FontWeight.w700)),
                        Text(
                          'R\$ ${_fmt2(precoTotal)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    if (pctPix > 0) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.pix, size: 18, color: Colors.green[700]),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'ou R\$ ${_fmt2(precoPix)} no PIX (${pctPix == pctPix.truncateToDouble() ? pctPix.toInt() : _fmt2(pctPix)}% off)',
                              style: TextStyle(
                                color: Colors.green[700],
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      _textoParcelamento(precoTotal),
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => unawaited(_confirmar()),
                      child: const Text('Adicionar ao carrinho'),
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

  Widget _buildGrupoCard(int gi, ThemeData theme) {
    final g = _grupos[gi];
    final tipo = _normTipo(g);
    final opcoes = _opcoesDe(g);
    final st = _sel[gi];
    final tit =
        (g[ComboConfigKeys.grupoTitulo] ?? 'Grupo ${gi + 1}').toString();
    final obs = (g[ComboConfigKeys.grupoObservacao] ?? '').toString().trim();
    final primary = theme.colorScheme.primary;
    final comboId = '${widget.comboProduct['id'] ?? 'combo'}';

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: primary.withOpacity(0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tit,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            Text(
              _labelTipoCliente(tipo),
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            if (obs.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(obs, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
            ],
            const SizedBox(height: 10),
            if (tipo == 'unica_obrigatoria' || tipo == 'unica_opcional') ...[
              ...List.generate(opcoes.length, (oi) {
                final nome = _nomeOpcao(opcoes[oi]);
                final preco = _linhaUnitaria(gi, oi, opcoes[oi]);
                final ativa = st.unicaIdx == oi;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RadioListTile<int>(
                      dense: true,
                      value: oi,
                      groupValue: st.unicaIdx ?? -1,
                      title: Text('$nome (+ R\$ ${_fmt2(preco)})'),
                      onChanged: (v) => setState(() {
                        _varPorOp.removeWhere((k, _) => k.startsWith('$gi.'));
                        st.unicaIdx = v;
                      }),
                    ),
                    if (ativa)
                      CatalogComboOpcaoVariacaoBlock(
                        produto: _produtoParaOpcao(opcoes[oi]),
                        comboProductId: comboId,
                        fieldSuffix: '${gi}_$oi',
                        tamanho: _varsGiOi(gi, oi)['tamanho'] ?? '',
                        cor: _varsGiOi(gi, oi)['cor'] ?? '',
                        extra: _varsGiOi(gi, oi)['extra'] ?? '',
                        onChanged:
                            ({required tamanho, required cor, required extra}) {
                          setState(() {
                            _setVarsGiOi(gi, oi,
                                tamanho: tamanho,
                                cor: cor,
                                extra: extra);
                          });
                        },
                      ),
                  ],
                );
              }),
              if (tipo == 'unica_opcional')
                RadioListTile<int>(
                  dense: true,
                  value: -1,
                  groupValue: st.unicaIdx ?? -1,
                  title: const Text('Nenhuma'),
                  onChanged: (v) => setState(() {
                    _varPorOp.removeWhere((k, _) => k.startsWith('$gi.'));
                    st.unicaIdx = (v != null && v >= 0) ? v : null;
                  }),
                ),
            ],
            if (tipo == 'multipla_opcional')
              ...List.generate(opcoes.length, (oi) {
                final sel = st.multiIdx.contains(oi);
                final nome = _nomeOpcao(opcoes[oi]);
                final preco = _linhaUnitaria(gi, oi, opcoes[oi]);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CheckboxListTile(
                      dense: true,
                      value: sel,
                      title: Text('$nome (+ R\$ ${_fmt2(preco)})'),
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            final maxS = _grupoSelecaoMax(g);
                            if (maxS > 0 && st.multiIdx.length >= maxS) {
                              return;
                            }
                            st.multiIdx.add(oi);
                          } else {
                            st.multiIdx.remove(oi);
                            _varPorOp.remove(_vk(gi, oi));
                          }
                        });
                      },
                    ),
                    if (sel)
                      CatalogComboOpcaoVariacaoBlock(
                        produto: _produtoParaOpcao(opcoes[oi]),
                        comboProductId: comboId,
                        fieldSuffix: '${gi}_$oi',
                        tamanho: _varsGiOi(gi, oi)['tamanho'] ?? '',
                        cor: _varsGiOi(gi, oi)['cor'] ?? '',
                        extra: _varsGiOi(gi, oi)['extra'] ?? '',
                        onChanged:
                            ({required tamanho, required cor, required extra}) {
                          setState(() {
                            _setVarsGiOi(gi, oi,
                                tamanho: tamanho,
                                cor: cor,
                                extra: extra);
                          });
                        },
                      ),
                  ],
                );
              }),
            if (tipo == 'multipla_quantidade' || tipo == 'fixo')
              ...List.generate(opcoes.length, (oi) {
                final op = opcoes[oi];
                final nome = _nomeOpcao(op);
                final unit = _linhaUnitaria(gi, oi, op);
                final q = st.qty[oi] ?? 0;
                final maxOp = _opQtdMax(op);
                final podeInc = maxOp == 0 || q < maxOp;
                final grupoRep = _grupoPermiteRepetir(g);
                final opRep = _opPermiteRepetir(op);
                final limiteUm = !grupoRep || !opRep;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(nome),
                      subtitle: Text('R\$ ${_fmt2(unit)} / un.'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (tipo != 'fixo')
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: q > 0
                                  ? () => setState(() {
                                        final nq = q - 1;
                                        if (nq <= 0) {
                                          st.qty.remove(oi);
                                          _varPorOp.remove(_vk(gi, oi));
                                        } else {
                                          st.qty[oi] = nq;
                                        }
                                      })
                                  : null,
                            ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              '$q',
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () {
                              if (limiteUm && q >= 1) return;
                              if (!podeInc) return;
                              setState(() {
                                st.qty[oi] = q + 1;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    if (q > 0)
                      CatalogComboOpcaoVariacaoBlock(
                        produto: _produtoParaOpcao(op),
                        comboProductId: comboId,
                        fieldSuffix: '${gi}_$oi',
                        tamanho: _varsGiOi(gi, oi)['tamanho'] ?? '',
                        cor: _varsGiOi(gi, oi)['cor'] ?? '',
                        extra: _varsGiOi(gi, oi)['extra'] ?? '',
                        onChanged:
                            ({required tamanho, required cor, required extra}) {
                          setState(() {
                            _setVarsGiOi(gi, oi,
                                tamanho: tamanho,
                                cor: cor,
                                extra: extra);
                          });
                        },
                      ),
                  ],
                );
              }),
 ],
        ),
      ),
    );
  }

  static String _labelTipoCliente(String tipo) {
    switch (tipo) {
      case 'unica_obrigatoria':
        return 'Escolha uma opção';
      case 'unica_opcional':
        return 'Opcional: até uma opção';
      case 'multipla_opcional':
        return 'Pode marcar várias opções';
      case 'multipla_quantidade':
        return 'Quantidade por opção';
      case 'fixo':
        return 'Itens inclusos no kit';
      default:
        return tipo;
    }
  }
}
