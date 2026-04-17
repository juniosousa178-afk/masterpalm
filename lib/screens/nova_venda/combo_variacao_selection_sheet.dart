// lib/screens/nova_venda/combo_variacao_selection_sheet.dart
// Modal para selecionar tamanho/cor/personalização (letra) de cada produto do combo ao adicionar na venda.

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../../core/catalog_color_from_name.dart';
import '../../core/produto_variacao_extra.dart';
import '../../models/produto.dart';
import '../../widgets/variacao_extras_collapsible.dart';

class ComboVariacaoSelectionSheet extends StatefulWidget {
  final Produto combo;
  final int quantidade;
  final double preco;
  final Box<Produto> produtosBox;
  final String lojaId;
  final void Function(List<Map<String, dynamic>> selecao, int qtd, double preco) onConfirmar;

  const ComboVariacaoSelectionSheet({
    super.key,
    required this.combo,
    required this.quantidade,
    required this.preco,
    required this.produtosBox,
    required this.lojaId,
    required this.onConfirmar,
  });

  static Future<void> show(
    BuildContext context, {
    required Produto combo,
    required int quantidade,
    required double preco,
    required Box<Produto> produtosBox,
    required String lojaId,
    required void Function(List<Map<String, dynamic>> selecao, int qtd, double preco) onConfirmar,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ComboVariacaoSelectionSheet(
        combo: combo,
        quantidade: quantidade,
        preco: preco,
        produtosBox: produtosBox,
        lojaId: lojaId,
        onConfirmar: onConfirmar,
      ),
    );
  }

  @override
  State<ComboVariacaoSelectionSheet> createState() => _ComboVariacaoSelectionSheetState();
}

class _ComboVariacaoSelectionSheetState extends State<ComboVariacaoSelectionSheet> {
  /// Por índice do itensCombo: tamanho, cor, extra (personalização / letra)
  late List<Map<String, String>> _selecoes;
  int _qtd = 1;

  @override
  void initState() {
    super.initState();
    _qtd = widget.quantidade;
    final itens = widget.combo.itensCombo ?? [];
    _selecoes = List.generate(itens.length, (_) => {'tamanho': '', 'cor': '', 'extra': ''});
  }

  Produto? _produtoParaLinha(int i) {
    final itens = widget.combo.itensCombo ?? [];
    if (i < 0 || i >= itens.length) return null;
    final item = itens[i];
    final nome = (item['nome'] ?? '').toString();
    final pid = (item['productId'] ?? item['id'] ?? '').toString().trim();
    if (pid.isNotEmpty) {
      final byId = widget.produtosBox.values.firstWhereOrNull(
        (x) => x.lojaId == widget.lojaId && x.idFirebase.trim() == pid,
      );
      if (byId != null) return byId;
    }
    if (nome.isNotEmpty) {
      return widget.produtosBox.values.firstWhereOrNull(
        (x) => x.lojaId == widget.lojaId && x.nome.trim().toLowerCase() == nome.toLowerCase(),
      );
    }
    return null;
  }

  List<String> _opcoesExtra(Produto p, int i) {
    final tam = (_selecoes[i]['tamanho'] ?? '').trim();
    final cor = (_selecoes[i]['cor'] ?? '').trim();
    return ProdutoVariacaoExtra.opcoesExtraPara(p.variacoes, tam, cor);
  }

  double _precoDoProdutoParaSelecao(
    Produto p,
    String tamanho,
    String cor,
  ) {
    final base = p.precoFinal;
    final tam = tamanho.trim();
    final c = cor.trim();
    final variacoes = p.variacoes;
    if (tam.isNotEmpty && variacoes != null && variacoes[tam] is Map) {
      final mapa = variacoes[tam] as Map;
      if (c.isNotEmpty && mapa[c] != null) {
        final pv = mapa[c];
        if (pv is Map && pv['preco'] is num) {
          return (pv['preco'] as num).toDouble();
        }
      }
    }
    if ((tam.isEmpty || tam == 'sem-tamanho') &&
        variacoes != null &&
        variacoes['sem-tamanho'] is Map &&
        c.isNotEmpty) {
      final st = variacoes['sem-tamanho'] as Map;
      final pv = st[c];
      if (pv is Map && pv['preco'] is num) {
        return (pv['preco'] as num).toDouble();
      }
    }
    if (p.precoPorTamanho != null &&
        p.precoPorTamanho!.isNotEmpty &&
        tam.isNotEmpty) {
      final v = p.precoPorTamanho![tam];
      if (v != null) return v.toDouble();
    }
    return base;
  }

  double get _subtotalUnidade {
    final itens = widget.combo.itensCombo ?? [];
    var soma = 0.0;
    for (var i = 0; i < itens.length; i++) {
      final p = _produtoParaLinha(i);
      if (p == null) continue;
      final qtdBase = (itens[i]['quantidade'] is num)
          ? (itens[i]['quantidade'] as num).toInt()
          : int.tryParse('${itens[i]['quantidade']}') ?? 1;
      if (qtdBase <= 0) continue;
      final tam = (_selecoes[i]['tamanho'] ?? '').trim();
      final cor = (_selecoes[i]['cor'] ?? '').trim();
      soma += _precoDoProdutoParaSelecao(p, tam, cor) * qtdBase;
    }
    return soma;
  }

  double get _precoFinalUnidade {
    // Nova venda não possui hoje campos nativos de desconto de combo no modelo Produto.
    // Mantemos compatível: preço por seleção (tam/cor) + quantidades base do kit.
    return _subtotalUnidade > 0 ? _subtotalUnidade : widget.preco;
  }

  bool get _podeConfirmar {
    final itens = widget.combo.itensCombo ?? [];
    for (var i = 0; i < itens.length; i++) {
      final p = _produtoParaLinha(i);
      if (p == null) continue;

      final nome = (itens[i]['nome'] ?? '').toString();
      final pid = (itens[i]['productId'] ?? itens[i]['id'] ?? '').toString().trim();
      if (nome.isEmpty && pid.isEmpty) continue;

      final qtdBase = (itens[i]['quantidade'] is num)
          ? (itens[i]['quantidade'] as num).toInt()
          : int.tryParse('${itens[i]['quantidade']}') ?? 1;
      if (qtdBase <= 0) continue;

      final need = qtdBase * _qtd;
      final tam = (_selecoes[i]['tamanho'] ?? '').trim();
      final cor = (_selecoes[i]['cor'] ?? '').trim();
      final extra = (_selecoes[i]['extra'] ?? '').trim();

      final usaVariacoes = p.usaVariacoes && p.variacoes != null && p.variacoes!.isNotEmpty;
      final temTamanhos =
          p.estoquePorTamanho.isNotEmpty || (usaVariacoes && !p.temVariacaoSoloCor && p.variacoes!.keys.any((k) => k.toString() != 'sem-tamanho'));

      if (p.temVariacaoSoloCor) {
        if (cor.isEmpty) return false;
      } else {
        if (temTamanhos && tam.isEmpty) return false;
        if (usaVariacoes && tam.isNotEmpty) {
          final mapaTamanho = p.variacoes![tam];
          if (mapaTamanho is Map && mapaTamanho.isNotEmpty) {
            final keysComEstoque = mapaTamanho.keys
                .map((k) => k.toString())
                .where((k) => ProdutoVariacaoExtra.somarCelula(mapaTamanho[k]) > 0)
                .toList();
            if (keysComEstoque.length > 1 || (keysComEstoque.length == 1 && keysComEstoque.first != 'sem-cor')) {
              if (cor.isEmpty) return false;
            }
          }
        }
      }

      final extras = _opcoesExtra(p, i);
      if (extras.isNotEmpty && extra.isEmpty) return false;

      int disponivel = 0;
      if (usaVariacoes) {
        disponivel = p.obterEstoqueVariacao(
          p.temVariacaoSoloCor ? '' : tam,
          p.temVariacaoSoloCor ? cor : cor,
          extra,
        );
      } else if (p.estoquePorTamanho.isNotEmpty) {
        disponivel = p.estoquePorTamanho[tam] ?? 0;
      } else {
        disponivel = p.quantidade;
      }
      if (disponivel < need) return false;
    }
    return _qtd >= 1;
  }

  List<Map<String, dynamic>> _buildSelecao() {
    final itens = widget.combo.itensCombo ?? [];
    final resultado = <Map<String, dynamic>>[];
    for (var i = 0; i < itens.length; i++) {
      final item = itens[i];
      final nome = (item['nome'] ?? '').toString();
      final slug = (item['slug'] ?? '').toString();
      final pid = (item['productId'] ?? item['id'] ?? '').toString().trim();
      final qtdBase = (item['quantidade'] is num)
          ? (item['quantidade'] as num).toInt()
          : int.tryParse('${item['quantidade']}') ?? 1;
      if (nome.isEmpty || qtdBase <= 0) continue;

      final tam = (_selecoes[i]['tamanho'] ?? '').trim();
      final cor = (_selecoes[i]['cor'] ?? '').trim();
      final extra = (_selecoes[i]['extra'] ?? '').trim();

      final p = _produtoParaLinha(i);
      final corKey = cor.isEmpty ? 'sem-cor' : cor;
      final tamKey = tam.isEmpty ? 'sem-tamanho' : tam;
      String resumo = '';
      String extraTipo = '';
      if (extra.isNotEmpty && p != null) {
        extraTipo = ProdutoVariacaoExtra.tipoParaCelula(
          p.variacoesExtraTipo,
          tamKey,
          corKey,
          extra,
        );
        resumo = ProdutoVariacaoExtra.textoResumoExtra(
          extraTipo: extraTipo,
          extraValor: extra,
        );
      }

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

  @override
  Widget build(BuildContext context) {
    final itens = widget.combo.itensCombo ?? [];
    final theme = Theme.of(context);

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
                const Icon(Icons.card_giftcard, color: Colors.orange),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Selecione as opções do combo',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
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
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...List.generate(itens.length, (i) {
                    final nome = (itens[i]['nome'] ?? '').toString();
                    if (nome.isEmpty) return const SizedBox.shrink();

                    final p = _produtoParaLinha(i);
                    if (p == null) return const SizedBox.shrink();

                    final usaVariacoes = p.usaVariacoes && p.variacoes != null && p.variacoes!.isNotEmpty;
                    final temTamanhos = p.estoquePorTamanho.isNotEmpty ||
                        (usaVariacoes && !p.temVariacaoSoloCor && p.variacoes!.keys.any((k) => k.toString() != 'sem-tamanho'));

                    Map<String, int> tamanhosDisponiveis = {};
                    Map<String, int> coresDisponiveis = {};

                    if (p.temVariacaoSoloCor && p.variacoes != null) {
                      final sm = p.variacoes!['sem-tamanho'];
                      if (sm is Map) {
                        coresDisponiveis = Map<String, int>.from(
                          sm.map(
                            (k, v) => MapEntry(
                              k.toString(),
                              ProdutoVariacaoExtra.somarCelula(v),
                            ),
                          ),
                        );
                      }
                    } else if (usaVariacoes && p.variacoes != null) {
                      for (final e in p.variacoes!.entries) {
                        if (e.key.toString() == 'sem-tamanho') continue;
                        if (e.value is Map) {
                          int total = 0;
                          for (final v in (e.value as Map).values) {
                            total += ProdutoVariacaoExtra.somarCelula(v);
                          }
                          if (total > 0) tamanhosDisponiveis[e.key.toString()] = total;
                        }
                      }
                      final tamSel = _selecoes[i]['tamanho'] ?? '';
                      if (tamSel.isNotEmpty) {
                        final mapa = p.variacoes![tamSel];
                        if (mapa is Map) {
                          coresDisponiveis = Map<String, int>.from(
                            mapa.map(
                              (k, v) => MapEntry(
                                k.toString(),
                                ProdutoVariacaoExtra.somarCelula(v),
                              ),
                            ),
                          );
                        }
                      }
                    } else if (p.estoquePorTamanho.isNotEmpty) {
                      tamanhosDisponiveis = Map.from(p.estoquePorTamanho);
                    }

                    final extras = _opcoesExtra(p, i);
                    final labelExtra = ProdutoVariacaoExtra.labelExtraParaProduto(
                      p.variacoes,
                      p.variacoesExtraTipo,
                    );

                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nome,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (temTamanhos) ...[
                              const Text('Tamanho', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: tamanhosDisponiveis.entries.map((e) {
                                  final sel = _selecoes[i]['tamanho'] == e.key;
                                  return ChoiceChip(
                                    label: Text(e.key),
                                    selected: sel,
                                    onSelected: (v) {
                                      setState(() {
                                        _selecoes[i] = Map.from(_selecoes[i]);
                                        _selecoes[i]['tamanho'] = v ? e.key : '';
                                        _selecoes[i]['cor'] = '';
                                        _selecoes[i]['extra'] = '';
                                        if (v) {
                                          final mapa = p.variacoes![e.key];
                                          if (mapa is Map) {
                                            final keys = mapa.keys
                                                .map((k) => k.toString())
                                                .where((k) => ProdutoVariacaoExtra.somarCelula(mapa[k]) > 0)
                                                .toList();
                                            if (keys.length == 1 && keys.first == 'sem-cor') {
                                              _selecoes[i]['cor'] = 'sem-cor';
                                            }
                                          }
                                        }
                                      });
                                    },
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 12),
                            ],
                            if (p.temVariacaoSoloCor && coresDisponiveis.isNotEmpty) ...[
                              const Text('Cor', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: coresDisponiveis.entries.map((e) {
                                  final sel = _selecoes[i]['cor'] == e.key;
                                  return ChoiceChip(
                                    avatar: CircleAvatar(
                                      backgroundColor: catalogColorFromName(e.key),
                                      radius: 10,
                                    ),
                                    label: Text(e.key),
                                    selected: sel,
                                    onSelected: (v) {
                                      setState(() {
                                        _selecoes[i] = Map.from(_selecoes[i]);
                                        _selecoes[i]['cor'] = v ? e.key : '';
                                        _selecoes[i]['extra'] = '';
                                      });
                                    },
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 12),
                            ] else if (!p.temVariacaoSoloCor && coresDisponiveis.isNotEmpty) ...[
                              const Text('Cor', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: coresDisponiveis.entries.map((e) {
                                  if (e.key == 'sem-cor') {
                                    return const SizedBox.shrink();
                                  }
                                  final sel = _selecoes[i]['cor'] == e.key;
                                  return ChoiceChip(
                                    avatar: CircleAvatar(
                                      backgroundColor: catalogColorFromName(e.key),
                                      radius: 10,
                                    ),
                                    label: Text(e.key),
                                    selected: sel,
                                    onSelected: (v) {
                                      setState(() {
                                        _selecoes[i] = Map.from(_selecoes[i]);
                                        _selecoes[i]['cor'] = v ? e.key : '';
                                        _selecoes[i]['extra'] = '';
                                      });
                                    },
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 12),
                            ],
                            if (extras.isNotEmpty) ...[
                              Text(
                                labelExtra,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 6),
                              VariacaoExtrasCollapsible(
                                key: ValueKey('combo_extra_$i'),
                                options: extras,
                                selectedValue: (_selecoes[i]['extra'] ?? '') as String?,
                                spacing: 8,
                                runSpacing: 8,
                                onOptionChosen: (ex) {
                                  setState(() {
                                    _selecoes[i] = Map.from(_selecoes[i]);
                                    _selecoes[i]['extra'] = ex;
                                  });
                                },
                                itemBuilder: (context, ex, _) {
                                  final sel = (_selecoes[i]['extra'] ?? '') == ex;
                                  return ChoiceChip(
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
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('Quantidade:', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: _qtd > 1 ? () => setState(() => _qtd--) : null,
                      ),
                      Text('$_qtd', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () => setState(() => _qtd++),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _podeConfirmar
                          ? () {
                              widget.onConfirmar(
                                _buildSelecao(),
                                _qtd,
                                _precoFinalUnidade,
                              );
                              Navigator.pop(context);
                            }
                          : null,
                      icon: const Icon(Icons.shopping_cart_checkout),
                      label: const Text('Adicionar combo ao carrinho'),
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
