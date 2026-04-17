// lib/screens/public_catalog/widgets/catalog_combo_variation_sheet.dart
// Modal para selecionar tamanho/cor/variação extra de cada item do combo no catálogo público.

import 'dart:async' show scheduleMicrotask, unawaited;
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../utils/platform_adaptive.dart';
import '../../../utils/safe_parse.dart' show safeDouble, safeBool, safeInt, safeListString, safeStr;
import '../../../core/catalog_color_from_name.dart';
import '../../../core/produto_variacao_extra.dart';
import '../../../core/safe_cast.dart' show asMap, asMapDeep;
import '../../../widgets/variacao_extras_collapsible.dart';
import '../catalog_estoque_helper.dart';
import 'catalog_after_add_choice_dialog.dart';

/// Abre o sheet legado (só [itensCombo] plano, sem [comboConfig]).
/// Para roteamento automático, use [showCatalogComboVariationSheet] em
/// `catalog_combo_configurable_sheet.dart`.
Future<void> showCatalogComboVariationSheetLegacy({
  required BuildContext context,
  required Map<String, dynamic> comboProduct,
  required List<Map<String, dynamic>> todosProdutos,
  required bool Function(Map<String, dynamic> item) onAdd,
  VoidCallback? onAbrirCarrinho,
  VoidCallback? onAfterSilentAddWhenAdded,
  bool showAfterAddChoiceDialog = true,
}) {
  if (!context.mounted) return Future.value();
  final wideChrome = usePointerFirstChrome(context);

  Widget sheetBody() {
    return CatalogComboVariationSheet(
      comboProduct: comboProduct,
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
              child: sheetBody(),
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
    builder: (_) => sheetBody(),
  );
}

class CatalogComboVariationSheet extends StatefulWidget {
  final Map<String, dynamic> comboProduct;
  final List<Map<String, dynamic>> todosProdutos;
  final bool Function(Map<String, dynamic> item) onAdd;
  final VoidCallback? onAbrirCarrinho;
  final VoidCallback? onAfterSilentAddWhenAdded;
  final bool showAfterAddChoiceDialog;

  const CatalogComboVariationSheet({
    super.key,
    required this.comboProduct,
    required this.todosProdutos,
    required this.onAdd,
    this.onAbrirCarrinho,
    this.onAfterSilentAddWhenAdded,
    this.showAfterAddChoiceDialog = true,
  });

  @override
  State<CatalogComboVariationSheet> createState() => _CatalogComboVariationSheetState();
}

class _CatalogComboVariationSheetState extends State<CatalogComboVariationSheet> {
  /// Por índice do itensCombo: {tamanho, cor, extra} (extra = estampa/letra/etc.)
  late List<Map<String, String>> _selecoes;
  int _qtd = 1;

  List<Map<String, dynamic>> get _itensCombo {
    final raw = widget.comboProduct['itensCombo'];
    if (raw is! List || raw.isEmpty) return [];
    final list = <Map<String, dynamic>>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final nome = (e['nome'] ?? e['name'] ?? '').toString().trim();
      if (nome.isEmpty) continue;
      final slug = (e['slug'] ?? '').toString().trim();
      final id = (e['id'] ?? e['produtoId'] ?? e['productId'] ?? '')
          .toString()
          .trim();
      final row = <String, dynamic>{
        'nome': nome,
        'slug': slug,
        'quantidade': (e['quantidade'] is num) ? (e['quantidade'] as num).toInt() : int.tryParse('${e['quantidade']}') ?? 1,
        if (id.isNotEmpty) 'id': id,
        if (id.isNotEmpty) 'productId': id,
      };
      for (final k in [
        'variacoes',
        'estoquePorTamanho',
        'estoquePorCor',
        'precoPorTamanho',
        'preco',
        'precoFinal',
        'tamanhos',
        'cores',
        'variacoesExtraTipo',
      ]) {
        final v = e[k];
        if (v != null) row[k] = v;
      }
      list.add(row);
    }
    return list;
  }

  @override
  void initState() {
    super.initState();
    _selecoes = List.generate(
      _itensCombo.length,
      (_) => {'tamanho': '', 'cor': '', 'extra': ''},
    );
  }

  Map<String, dynamic>? _findProductByNomeOuSlug(String nome, String slug) {
    final n = nome.trim().toLowerCase();
    final s = slug.trim();
    for (final p in widget.todosProdutos) {
      final pNome = (p['nome'] ?? '').toString().trim().toLowerCase();
      final pSlug = (p['slug'] ?? '').toString().trim();
      if (n.isNotEmpty && pNome == n) return p;
      if (s.isNotEmpty && pSlug == s) return p;
    }
    return null;
  }

  Map<String, dynamic>? _findProductById(String id) {
    final sid = id.trim();
    if (sid.isEmpty) return null;
    for (final p in widget.todosProdutos) {
      final pId = (p['id'] ?? '').toString().trim();
      if (pId == sid) return p;
    }
    return null;
  }

  /// Monta o mapa de produto a partir dos dados embutidos no item do kit (sync do vínculo).
  Map<String, dynamic>? _produtoMapDoItemVinculado(Map<String, dynamic> item) {
    final variacoes = item['variacoes'];
    final estTam = item['estoquePorTamanho'];
    final estCor = item['estoquePorCor'];
    final ppt = item['precoPorTamanho'];
    final tamanhos = item['tamanhos'];
    final hasVar = variacoes is Map && variacoes.isNotEmpty;
    final hasEstTam = estTam is Map && estTam.isNotEmpty;
    final hasEstCor = estCor is Map && estCor.isNotEmpty;
    final hasPpt = ppt is Map && ppt.isNotEmpty;
    final hasTamList = tamanhos is List && tamanhos.isNotEmpty;
    if (!hasVar && !hasEstTam && !hasEstCor && !hasPpt && !hasTamList) {
      return null;
    }
    final pid = (item['id'] ?? item['productId'] ?? item['produtoId'] ?? '')
        .toString()
        .trim();
    Map<String, double>? pptMap;
    if (ppt is Map && ppt.isNotEmpty) {
      final acc = <String, double>{};
      ppt.forEach((k, v) {
        if (v is num && v > 0) acc[k.toString()] = v.toDouble();
      });
      if (acc.isNotEmpty) pptMap = acc;
    }
    List<String>? tamanhosOut;
    if (tamanhos is List && tamanhos.isNotEmpty) {
      tamanhosOut = tamanhos.map((dynamic t) => t.toString()).toList();
    }
    return <String, dynamic>{
      'id': pid,
      'nome': item['nome'] ?? '',
      'slug': item['slug'] ?? '',
      'preco': safeDouble(item['preco'] ?? item['precoFinal']),
      if (hasVar) 'variacoes': asMapDeep(variacoes),
      if (hasEstTam) 'estoquePorTamanho': asMap(estTam),
      if (hasEstCor) 'estoquePorCor': asMap(estCor),
      if (pptMap != null) 'precoPorTamanho': pptMap,
      if (tamanhosOut != null) 'tamanhos': tamanhosOut,
      if (item['variacoesExtraTipo'] != null &&
          asMapDeep(item['variacoesExtraTipo']).isNotEmpty)
        'variacoesExtraTipo': asMapDeep(item['variacoesExtraTipo']),
    };
  }

  /// Resolve o produto do catálogo para um item do combo: dados do vínculo, depois lista pública.
  Map<String, dynamic>? _produtoParaItem(Map<String, dynamic> item) {
    final embedded = _produtoMapDoItemVinculado(item);
    if (embedded != null) return embedded;

    final id =
        (item['id'] ?? item['produtoId'] ?? item['productId'] ?? '')
            .toString()
            .trim();
    if (id.isNotEmpty) {
      final byId = _findProductById(id);
      if (byId != null) return byId;
    }
    final nome = (item['nome'] ?? '').toString().trim();
    final slug = (item['slug'] ?? '').toString().trim();
    return _findProductByNomeOuSlug(nome, slug);
  }

  /// Alinhado a [Produto.temVariacaoSoloCor] para mapas do catálogo.
  bool _mapTemVariacaoSoloCor(Map<String, dynamic> p) {
    final v = asMapDeep(p['variacoes']);
    if (v.isEmpty) return false;
    final st = v['sem-tamanho'];
    return st is Map && st.isNotEmpty;
  }

  List<String> _opcoesExtraNoIndice(int i) {
    final p = _produtoParaItem(_itensCombo[i]);
    if (p == null) return const [];
    final tam = (_selecoes[i]['tamanho'] ?? '').trim();
    final cor = (_selecoes[i]['cor'] ?? '').trim();
    return ProdutoVariacaoExtra.opcoesExtraPara(asMapDeep(p['variacoes']), tam, cor);
  }

  /// Preço de um produto para a seleção atual (tamanho/cor). Usa precoPorTamanho ou preço base.
  double _precoDoProdutoParaSelecao(Map<String, dynamic> p, String tamanho, String cor) {
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

  /// Subtotal de uma unidade do kit = soma dos preços dos itens (com variações selecionadas) × quantidade de cada item.
  double get _subtotalUnidade {
    double soma = 0;
    for (var i = 0; i < _itensCombo.length; i++) {
      final item = _itensCombo[i];
      final p = _produtoParaItem(item);
      final qtd = (item['quantidade'] is num) ? (item['quantidade'] as num).toInt() : 1;
      if (p != null) {
        final tam = (_selecoes[i]['tamanho'] ?? '').toString().trim();
        final cor = (_selecoes[i]['cor'] ?? '').toString().trim();
        soma += _precoDoProdutoParaSelecao(p, tam, cor) * qtd;
      }
    }
    return soma;
  }

  double get _descontoComboValor =>
      (widget.comboProduct['descontoComboValor'] is num)
          ? (widget.comboProduct['descontoComboValor'] as num).toDouble()
          : 0.0;
  double get _descontoComboPercentual =>
      (widget.comboProduct['descontoComboPercentual'] is num)
          ? (widget.comboProduct['descontoComboPercentual'] as num).toDouble()
          : 0.0;

  /// Preço final de uma unidade do kit (subtotal com desconto aplicado — o mais atrativo: valor ou %).
  double get _precoFinalUnidade {
    final sub = _subtotalUnidade;
    if (sub <= 0) return 0;
    final dValor = _descontoComboValor;
    final dPerc = _descontoComboPercentual;
    if (dValor <= 0 && dPerc <= 0) return sub;
    final comValor = (sub - dValor).clamp(0.0, double.infinity);
    final comPerc = sub * (1 - dPerc / 100).clamp(0.0, double.infinity);
    return comValor < comPerc ? comValor : comPerc;
  }

  bool get _podeConfirmar {
    for (var i = 0; i < _itensCombo.length; i++) {
      final item = _itensCombo[i];
      final p = _produtoParaItem(item);
      if (p == null) continue;

      final variacoes = asMapDeep(p['variacoes']);
      final estoquePorTamanho = asMap(p['estoquePorTamanho']);
      final estoquePorCor = asMap(p['estoquePorCor']);
      final usaVariacoes = variacoes.isNotEmpty;
      final temVariacaoSoloCor = _mapTemVariacaoSoloCor(p);

      var temTamanhos = estoquePorTamanho.isNotEmpty;
      if (!temTamanhos && usaVariacoes) {
        for (final e in variacoes.entries) {
          if (e.key.toString() == 'sem-tamanho') continue;
          if (e.value is Map) {
            var total = 0;
            for (final v in (e.value as Map).values) {
              total += ProdutoVariacaoExtra.somarCelula(v);
            }
            if (total > 0) {
              temTamanhos = true;
              break;
            }
          }
        }
      }

      final tam = (_selecoes[i]['tamanho'] ?? '').trim();
      final cor = (_selecoes[i]['cor'] ?? '').trim();
      final extra = (_selecoes[i]['extra'] ?? '').trim();

      if (temVariacaoSoloCor) {
        if (cor.isEmpty) return false;
      } else {
        if (temTamanhos && tam.isEmpty) return false;
        if (usaVariacoes && tam.isNotEmpty) {
          final mapaTamanho = variacoes[tam];
          if (mapaTamanho is Map && mapaTamanho.isNotEmpty) {
            final keysComEstoque = mapaTamanho.keys
                .map((k) => k.toString())
                .where((k) => ProdutoVariacaoExtra.somarCelula(mapaTamanho[k]) > 0)
                .toList();
            if (keysComEstoque.length > 1 ||
                (keysComEstoque.length == 1 &&
                    keysComEstoque.first != 'sem-cor')) {
              if (cor.isEmpty) return false;
            }
          }
        }
      }

      final extras = ProdutoVariacaoExtra.opcoesExtraPara(variacoes, tam, cor);
      if (extras.isNotEmpty && extra.isEmpty) return false;

      if (!temVariacaoSoloCor && !temTamanhos && estoquePorCor.isNotEmpty && cor.isEmpty) {
        return false;
      }
    }
    return _qtd >= 1;
  }

  List<Map<String, dynamic>> _buildSelecao() {
    final resultado = <Map<String, dynamic>>[];
    for (var i = 0; i < _itensCombo.length; i++) {
      final item = _itensCombo[i];
      final nome = (item['nome'] ?? '').toString();
      final slug = (item['slug'] ?? '').toString();
      final pid = (item['productId'] ?? item['id'] ?? '').toString().trim();
      final qtdBase = (item['quantidade'] is num) ? (item['quantidade'] as num).toInt() : 1;
      final tam = (_selecoes[i]['tamanho'] ?? '').trim();
      final cor = (_selecoes[i]['cor'] ?? '').trim();
      final extra = (_selecoes[i]['extra'] ?? '').trim();
      final p = _produtoParaItem(item);
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
      resultado.add({
        'nome': nome,
        'slug': slug,
        'quantidade': qtdBase * _qtd,
        'tamanho': tam,
        'cor': cor,
        if (extra.isNotEmpty) 'extraValor': extra,
        if (extraTipo.isNotEmpty) 'extraTipo': extraTipo,
        if (resumo.isNotEmpty) 'variacaoExtraResumo': resumo,
        if (pid.isNotEmpty) 'productId': pid,
      });
    }
    return resultado;
  }

  Future<void> _confirmar() async {
    for (var i = 0; i < _itensCombo.length; i++) {
      final item = _itensCombo[i];
      final p = _produtoParaItem(item);
      final nomeItem = (item['nome'] ?? '').toString();
      final qtdBase = (item['quantidade'] is num)
          ? (item['quantidade'] as num).toInt()
          : 1;
      final need = qtdBase * _qtd;
      if (p != null) {
        final tam = (_selecoes[i]['tamanho'] ?? '').trim();
        final cor = (_selecoes[i]['cor'] ?? '').trim();
        final extra = (_selecoes[i]['extra'] ?? '').trim();
        final avail =
            CatalogEstoqueHelper.estoqueDisponivelVariacao(p, tam, cor, extra);
        if (avail < need) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(avail <= 0
                  ? 'Sem estoque: $nomeItem'
                  : 'Estoque insuficiente para $nomeItem (disponível: $avail).'),
            ),
          );
          return;
        }
      }
    }

    final preco = _precoFinalUnidade;
    final img = safeListString(widget.comboProduct['imagens']).isNotEmpty
        ? safeListString(widget.comboProduct['imagens']).first
        : safeStr(widget.comboProduct['imageUrl']);
    final item = {
      'produtosId': widget.comboProduct['id'],
      'id': widget.comboProduct['id'],
      'nome': widget.comboProduct['nome'],
      'preco': preco,
      'percentualDescontoPix': safeDouble(widget.comboProduct['percentualDescontoPix']),
      'divideSemJuros': safeBool(widget.comboProduct['divideSemJuros']),
      'maxParcelasSemJuros': safeInt(widget.comboProduct['maxParcelasSemJuros'], 12),
      'quantidade': _qtd,
      'imageUrl': img,
      'url_foto': img,
      'slug': widget.comboProduct['slug'],
      'peso': safeDouble(widget.comboProduct['peso']),
      'tipoEmbalagem': safeStr(widget.comboProduct['tipoEmbalagem'], 'padrao'),
      'tamanho': '',
      'cor': '',
      'itensComboComSelecao': _buildSelecao(),
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
    final itens = _itensCombo;
    final precoUnidade = _precoFinalUnidade;
    final precoTotal = precoUnidade * _qtd;
    String fmt2(num v) => v.toStringAsFixed(2).replaceAll('.', ',');

    final sheetH = MediaQuery.sizeOf(context).height * 0.88;

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
                    Icon(Icons.card_giftcard, color: theme.colorScheme.primary, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Configurar kit',
                            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Tamanho, cor e personalização (estampa, letra, etc.) de cada item',
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
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ...List.generate(itens.length, (i) {
                    final item = itens[i];
                    final nome = (item['nome'] ?? '').toString();
                    final p = _produtoParaItem(item);
                    final temVariacaoSoloCor = p != null && _mapTemVariacaoSoloCor(p);
                    final extras = p != null ? _opcoesExtraNoIndice(i) : const <String>[];
                    final labelExtra = p != null
                        ? ProdutoVariacaoExtra.labelExtraParaProduto(
                            asMapDeep(p['variacoes']),
                            p['variacoesExtraTipo'] != null
                                ? asMapDeep(p['variacoesExtraTipo'])
                                : null,
                          )
                        : kVariacaoExtraLabelNeutra;

                    Map<String, int> tamanhosDisponiveis = {};
                    Map<String, int> coresDisponiveis = {};
                    Map<String, double> precoPorTamanho = {};
                    bool temTamanhos = false;
                    if (p != null) {
                      final variacoes = asMapDeep(p['variacoes']);
                      final estoqueTam = asMap(p['estoquePorTamanho']);
                      final precoTamRaw = p['precoPorTamanho'];
                      if (precoTamRaw is Map && precoTamRaw.isNotEmpty) {
                        precoTamRaw.forEach((k, v) {
                          if (v is num && v > 0) {
                            precoPorTamanho[k.toString()] = v.toDouble();
                            tamanhosDisponiveis[k.toString()] = 1;
                          }
                        });
                      }
                      if (variacoes.isNotEmpty) {
                        for (final e in variacoes.entries) {
                          if (e.key.toString() == 'sem-tamanho') continue;
                          if (e.value is Map) {
                            var total = 0;
                            for (final v in (e.value as Map).values) {
                              total += ProdutoVariacaoExtra.somarCelula(v);
                            }
                            if (total > 0) {
                              tamanhosDisponiveis[e.key.toString()] = total;
                            }
                          }
                        }
                        temTamanhos = tamanhosDisponiveis.isNotEmpty;
                        if (!temTamanhos &&
                            variacoes['sem-tamanho'] is Map) {
                          final sm = variacoes['sem-tamanho'] as Map;
                          sm.forEach((k, v) {
                            final q = ProdutoVariacaoExtra.somarCelula(v);
                            if (q > 0) {
                              coresDisponiveis[k.toString()] = q;
                            }
                          });
                        }
                        final tamSel = _selecoes[i]['tamanho'] ?? '';
                        if (tamSel.isNotEmpty && variacoes.containsKey(tamSel)) {
                          coresDisponiveis.clear();
                          final mapa = variacoes[tamSel];
                          if (mapa is Map) {
                            mapa.forEach((k, v) {
                              final q = ProdutoVariacaoExtra.somarCelula(v);
                              if (q > 0) coresDisponiveis[k.toString()] = q;
                            });
                          }
                        }
                      } else if (estoqueTam.isNotEmpty) {
                        estoqueTam.forEach((k, v) {
                          final q = v is num ? v.truncate() : 0;
                          if (q > 0) tamanhosDisponiveis[k.toString()] = q;
                        });
                        temTamanhos = tamanhosDisponiveis.isNotEmpty;
                      } else if (precoPorTamanho.isNotEmpty) {
                        temTamanhos = true;
                      }
                      if (temTamanhos && tamanhosDisponiveis.isEmpty && precoPorTamanho.isNotEmpty) {
                        precoPorTamanho.forEach((k, v) {
                          tamanhosDisponiveis[k] = 1;
                        });
                      }
                      if (!temTamanhos && tamanhosDisponiveis.isEmpty) {
                        final tamanhosList = p['tamanhos'];
                        if (tamanhosList is List && tamanhosList.isNotEmpty) {
                          for (final t in tamanhosList) {
                            final k = t.toString().trim();
                            if (k.isNotEmpty) tamanhosDisponiveis[k] = 1;
                          }
                          temTamanhos = tamanhosDisponiveis.isNotEmpty;
                        }
                      }
                      if (!temTamanhos && coresDisponiveis.isEmpty) {
                        final ec = asMap(p['estoquePorCor']);
                        ec.forEach((k, v) {
                          final q = v is num ? v.truncate() : 0;
                          if (q > 0) {
                            coresDisponiveis[k.toString()] = q;
                          }
                        });
                      }
                    }

                    final primaryColor = theme.colorScheme.primary;
                    final labelStyle = TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    );

                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: primaryColor.withOpacity(0.3), width: 1.5),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: primaryColor.withOpacity(0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    '${i + 1}',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: primaryColor,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    nome,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (p == null) ...[
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.65),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: theme.colorScheme.outlineVariant.withOpacity(0.6),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.storefront_outlined,
                                      size: 20,
                                      color: theme.colorScheme.primary,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Só no estoque da loja — não publicado como produto avulso no site. '
                                        'O kit pode ser adicionado ao carrinho; tamanhos e cores deste item '
                                        'são alinhados com a loja na separação do pedido.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          height: 1.35,
                                          color: theme.colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ] else ...[
                              const SizedBox(height: 14),
                              if (temTamanhos) ...[
                              Text('Tamanho', style: labelStyle),
                              const SizedBox(height: 8),
                              Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: tamanhosDisponiveis.entries.map((e) {
                                    final sel = (_selecoes[i]['tamanho'] ?? '') == e.key;
                                    final precoTamanho = precoPorTamanho[e.key];
                                    final label = precoTamanho != null && precoTamanho > 0
                                        ? '${e.key} (R\$ ${precoTamanho.toStringAsFixed(2).replaceAll('.', ',')})'
                                        : e.key;
                                    return FilterChip(
                                      label: Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 4),
                                        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                      ),
                                      selected: sel,
                                      onSelected: (v) {
                                        setState(() {
                                          _selecoes[i] = Map.from(_selecoes[i]);
                                          _selecoes[i]['tamanho'] = v ? e.key : '';
                                          _selecoes[i]['cor'] = '';
                                          _selecoes[i]['extra'] = '';
                                          if (v) {
                                            final variacoes = asMapDeep(p['variacoes']);
                                            final mapa = variacoes[e.key];
                                            if (mapa is Map) {
                                              final keys = mapa.keys
                                                  .map((k) => k.toString())
                                                  .where((k) =>
                                                      ProdutoVariacaoExtra.somarCelula(mapa[k]) > 0)
                                                  .toList();
                                              if (keys.length == 1 &&
                                                  keys.first == 'sem-cor') {
                                                _selecoes[i]['cor'] = 'sem-cor';
                                              }
                                            }
                                          }
                                        });
                                      },
                                      selectedColor: primaryColor.withOpacity(0.25),
                                      checkmarkColor: primaryColor,
                                      side: BorderSide(
                                        color: sel ? primaryColor : theme.dividerColor,
                                        width: sel ? 2 : 1,
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    );
                                  }).toList(),
                                ),
                              ] else if (coresDisponiveis.isEmpty)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Tamanho', style: labelStyle),
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: theme.dividerColor.withOpacity(0.3),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'Único (sem variação)',
                                        style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withOpacity(0.7)),
                                      ),
                                    ),
                                  ],
                                ),
                              if (temVariacaoSoloCor && coresDisponiveis.isNotEmpty) ...[
                                const SizedBox(height: 14),
                                Text('Cor', style: labelStyle),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: coresDisponiveis.entries.map((e) {
                                    final sel = (_selecoes[i]['cor'] ?? '') == e.key;
                                    return FilterChip(
                                      avatar: CircleAvatar(
                                        backgroundColor: catalogColorFromName(e.key),
                                        radius: 12,
                                      ),
                                      label: Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 4),
                                        child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                      ),
                                      selected: sel,
                                      onSelected: (v) {
                                        setState(() {
                                          _selecoes[i] = Map.from(_selecoes[i]);
                                          _selecoes[i]['cor'] = v ? e.key : '';
                                          _selecoes[i]['extra'] = '';
                                        });
                                      },
                                      selectedColor: primaryColor.withOpacity(0.25),
                                      checkmarkColor: primaryColor,
                                      side: BorderSide(
                                        color: sel ? primaryColor : theme.dividerColor,
                                        width: sel ? 2 : 1,
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    );
                                  }).toList(),
                                ),
                              ] else if (!temVariacaoSoloCor && coresDisponiveis.isNotEmpty) ...[
                                const SizedBox(height: 14),
                                Text('Cor', style: labelStyle),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: coresDisponiveis.entries.map((e) {
                                    if (e.key == 'sem-cor') {
                                      return const SizedBox.shrink();
                                    }
                                    final sel = (_selecoes[i]['cor'] ?? '') == e.key;
                                    return FilterChip(
                                      avatar: CircleAvatar(
                                        backgroundColor: catalogColorFromName(e.key),
                                        radius: 12,
                                      ),
                                      label: Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 4),
                                        child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                      ),
                                      selected: sel,
                                      onSelected: (v) {
                                        setState(() {
                                          _selecoes[i] = Map.from(_selecoes[i]);
                                          _selecoes[i]['cor'] = v ? e.key : '';
                                          _selecoes[i]['extra'] = '';
                                        });
                                      },
                                      selectedColor: primaryColor.withOpacity(0.25),
                                      checkmarkColor: primaryColor,
                                      side: BorderSide(
                                        color: sel ? primaryColor : theme.dividerColor,
                                        width: sel ? 2 : 1,
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    );
                                  }).toList(),
                                ),
                              ],
                              if (extras.isNotEmpty) ...[
                                const SizedBox(height: 14),
                                Text(labelExtra, style: labelStyle),
                                const SizedBox(height: 8),
                                VariacaoExtrasCollapsible(
                                  key: ValueKey('catalog_combo_extra_${widget.comboProduct['id']}_$i'),
                                  options: extras,
                                  selectedValue: (_selecoes[i]['extra'] ?? '').trim().isEmpty
                                      ? null
                                      : _selecoes[i]['extra'],
                                  spacing: 10,
                                  runSpacing: 10,
                                  onOptionChosen: (ex) {
                                    setState(() {
                                      _selecoes[i] = Map.from(_selecoes[i]);
                                      _selecoes[i]['extra'] = ex;
                                    });
                                  },
                                  itemBuilder: (context, ex, _) {
                                    final sel = (_selecoes[i]['extra'] ?? '') == ex;
                                    return FilterChip(
                                      label: Text(ex),
                                      selected: sel,
                                      onSelected: (v) {
                                        setState(() {
                                          _selecoes[i] = Map.from(_selecoes[i]);
                                          _selecoes[i]['extra'] = v ? ex : '';
                                        });
                                      },
                                    );
                                  },
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  12 + MediaQuery.paddingOf(context).bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        const Text(
                          'Quantidade:',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                        ),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: _qtd > 1 ? () => setState(() => _qtd--) : null,
                        ),
                        Text(
                          '$_qtd',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => setState(() => _qtd++),
                        ),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'Total: R\$ ${fmt2(precoTotal)}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    if (_descontoComboValor > 0 || _descontoComboPercentual > 0)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'Subtotal: R\$ ${fmt2(_subtotalUnidade * _qtd)} → com desconto',
                          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                        ),
                      ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: _podeConfirmar
                            ? () => unawaited(_confirmar())
                            : null,
                        icon: const Icon(Icons.shopping_cart_checkout, size: 22),
                        label: const Text('Adicionar kit ao carrinho'),
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
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
}

