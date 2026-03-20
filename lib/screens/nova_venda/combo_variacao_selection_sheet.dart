// lib/screens/nova_venda/combo_variacao_selection_sheet.dart
// Modal para selecionar tamanho/cor de cada produto do combo ao adicionar na venda.

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../../models/produto.dart';

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
  /// Por índice do itensCombo: {tamanho, cor} selecionados
  late List<Map<String, String>> _selecoes;
  int _qtd = 1;

  @override
  void initState() {
    super.initState();
    _qtd = widget.quantidade;
    final itens = widget.combo.itensCombo ?• [];
    _selecoes = List.generate(itens.length, (_) => {'tamanho': '', 'cor': ''});
  }

  bool get _podeConfirmar {
    final itens = widget.combo.itensCombo ?• [];
    for (var i = 0; i < itens.length; i++) {
      final item = itens[i];
      final nome = (item['nome'] ?• '').toString();
      final pid = (item['productId'] ?• item['id'] ?• '').toString().trim();
      if (nome.isEmpty && pid.isEmpty) continue;

      Produto• p;
      if (pid.isNotEmpty) {
        p = widget.produtosBox.values.firstWhereOrNull(
          (x) => x.lojaId == widget.lojaId && x.idFirebase.trim() == pid,
        );
      }
      if (p == null && nome.isNotEmpty) {
        p = widget.produtosBox.values.firstWhereOrNull(
          (x) => x.lojaId == widget.lojaId && x.nome.trim().toLowerCase() == nome.toLowerCase(),
        );
      }
      if (p == null) continue;

      final tam = (_selecoes[i]['tamanho'] ?• '').trim();
      final cor = (_selecoes[i]['cor'] ?• '').trim();

      final usaVariacoes = p.usaVariacoes && p.variacoes != null && p.variacoes!.isNotEmpty;
      final temTamanhos = p.estoquePorTamanho.isNotEmpty || (usaVariacoes && p.variacoes!.keys.isNotEmpty);

      if (temTamanhos && tam.isEmpty) return false;
      if (usaVariacoes && tam.isNotEmpty) {
        final mapaTamanho = p.variacoes![tam];
        if (mapaTamanho is Map && mapaTamanho.isNotEmpty && cor.isEmpty) return false;
      }
    }
    return _qtd >= 1;
  }

  List<Map<String, dynamic>> _buildSelecao() {
    final itens = widget.combo.itensCombo ?• [];
    final resultado = <Map<String, dynamic>>[];
    for (var i = 0; i < itens.length; i++) {
      final item = itens[i];
      final nome = (item['nome'] ?• '').toString();
      final slug = (item['slug'] ?• '').toString();
      final pid = (item['productId'] ?• item['id'] ?• '').toString().trim();
      final qtdBase = (item['quantidade'] is num)
          • (item['quantidade'] as num).toInt()
          : int.tryParse('${item['quantidade']}') ?• 1;
      if (nome.isEmpty || qtdBase <= 0) continue;

      resultado.add({
        'nome': nome,
        'slug': slug,
        'quantidade': qtdBase * _qtd,
        'tamanho': (_selecoes[i]['tamanho'] ?• '').trim(),
        'cor': (_selecoes[i]['cor'] ?• '').trim(),
        if (pid.isNotEmpty) 'productId': pid,
      });
    }
    return resultado;
  }

  Color _getColorFromName(String nome) {
    const coresMap = {
      'preto': Colors.black, 'branco': Colors.white, 'vermelho': Colors.red,
      'azul': Colors.blue, 'verde': Colors.green, 'amarelo': Colors.yellow,
      'rosa': Colors.pink, 'roxo': Colors.purple, 'laranja': Colors.orange,
      'cinza': Colors.grey, 'marrom': Colors.brown, 'bege': Color(0xFFF5F5DC),
      'dourado': Color(0xFFFFD700), 'prata': Color(0xFFC0C0C0),
    };
    return coresMap[nome.toLowerCase()] ?• Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final itens = widget.combo.itensCombo ?• [];
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
              color: Colors.grey.withValues(alpha:0.5),
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
                    final item = itens[i];
                    final nome = (item['nome'] ?• '').toString();
                    if (nome.isEmpty) return const SizedBox.shrink();

                    final p = widget.produtosBox.values.firstWhereOrNull(
                      (x) => x.lojaId == widget.lojaId && x.nome.trim().toLowerCase() == nome.toLowerCase(),
                    );
                    if (p == null) return const SizedBox.shrink();

                    final usaVariacoes = p.usaVariacoes && p.variacoes != null && p.variacoes!.isNotEmpty;
                    final temTamanhos = p.estoquePorTamanho.isNotEmpty ||
                        (usaVariacoes && p.variacoes!.keys.isNotEmpty);
                    Map<String, int> tamanhosDisponiveis = {};
                    Map<String, int> coresDisponiveis = {};
                    if (usaVariacoes && p.variacoes != null) {
                      for (final e in p.variacoes!.entries) {
                        if (e.value is Map) {
                          int total = 0;
                          for (final v in (e.value as Map).values) {
                            total += (v as num?)?.toInt() ?• 0;
                          }
                          if (total > 0) tamanhosDisponiveis[e.key.toString()] = total;
                        }
                      }
                      final tamSel = _selecoes[i]['tamanho'] ?• '';
                      if (tamSel.isNotEmpty) {
                        final mapa = p.variacoes![tamSel];
                        if (mapa is Map) {
                          coresDisponiveis = Map<String, int>.from(
                            mapa.map((k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?• 0)),
                          );
                        }
                      }
                    } else if (p.estoquePorTamanho.isNotEmpty) {
                      tamanhosDisponiveis = Map.from(p.estoquePorTamanho);
                    }

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
                                        _selecoes[i]['tamanho'] = v • e.key : '';
                                        _selecoes[i]['cor'] = '';
                                      });
                                    },
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 12),
                            ],
                            if (coresDisponiveis.isNotEmpty) ...[
                              const Text('Cor', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: coresDisponiveis.entries.map((e) {
                                  final sel = _selecoes[i]['cor'] == e.key;
                                  return ChoiceChip(
                                    avatar: CircleAvatar(
                                      backgroundColor: _getColorFromName(e.key),
                                      radius: 10,
                                    ),
                                    label: Text(e.key),
                                    selected: sel,
                                    onSelected: (v) {
                                      setState(() {
                                        _selecoes[i] = Map.from(_selecoes[i]);
                                        _selecoes[i]['cor'] = v • e.key : '';
                                      });
                                    },
                                  );
                                }).toList(),
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
                        onPressed: _qtd > 1
                            • () => setState(() => _qtd--)
                            : null,
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
                          • () {
                              widget.onConfirmar(_buildSelecao(), _qtd, widget.preco);
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

