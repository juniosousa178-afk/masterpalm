// lib/screens/public_catalog/widgets/catalog_combo_variation_sheet.dart
// Modal para selecionar tamanho/cor de cada produto do combo no catálogo público.

import 'package:flutter/material.dart';

import '../../../utils/safe_parse.dart' show safeDouble, safeBool, safeInt, safeListString, safeStr;
import '../../../core/safe_cast.dart' show asMap, asMapDeep;

/// Abre o sheet de seleção de variações do combo e, ao confirmar, chama [onAdd] com o item do carrinho (inclui [itensComboComSelecao]).
void showCatalogComboVariationSheet({
  required BuildContext context,
  required Map<String, dynamic> comboProduct,
  required List<Map<String, dynamic>> todosProdutos,
  required void Function(Map<String, dynamic> item) onAdd,
  VoidCallback? onAbrirCarrinho,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => CatalogComboVariationSheet(
      comboProduct: comboProduct,
      todosProdutos: todosProdutos,
      onAdd: onAdd,
      onAbrirCarrinho: onAbrirCarrinho,
    ),
  );
}

class CatalogComboVariationSheet extends StatefulWidget {
  final Map<String, dynamic> comboProduct;
  final List<Map<String, dynamic>> todosProdutos;
  final void Function(Map<String, dynamic> item) onAdd;
  final VoidCallback? onAbrirCarrinho;

  const CatalogComboVariationSheet({
    super.key,
    required this.comboProduct,
    required this.todosProdutos,
    required this.onAdd,
    this.onAbrirCarrinho,
  });

  @override
  State<CatalogComboVariationSheet> createState() => _CatalogComboVariationSheetState();
}

class _CatalogComboVariationSheetState extends State<CatalogComboVariationSheet> {
  /// Por índice do itensCombo: {tamanho, cor}
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
      final id = (e['id'] ?? e['produtoId'] ?? '').toString().trim();
      list.add({
        'nome': nome,
        'slug': slug,
        'quantidade': (e['quantidade'] is num) ? (e['quantidade'] as num).toInt() : int.tryParse('${e['quantidade']}') ?? 1,
        if (id.isNotEmpty) 'id': id,
      });
    }
    return list;
  }

  @override
  void initState() {
    super.initState();
    _selecoes = List.generate(_itensCombo.length, (_) => {'tamanho': '', 'cor': ''});
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

  /// Resolve o produto do catálogo para um item do combo (por id, depois nome, depois slug).
  Map<String, dynamic>? _produtoParaItem(Map<String, dynamic> item) {
    final id = (item['id'] ?? '').toString().trim();
    if (id.isNotEmpty) {
      final byId = _findProductById(id);
      if (byId != null) return byId;
    }
    final nome = (item['nome'] ?? '').toString().trim();
    final slug = (item['slug'] ?? '').toString().trim();
    return _findProductByNomeOuSlug(nome, slug);
  }

  /// Preço de um produto para a seleção atual (tamanho/cor). Usa precoPorTamanho ou preço base.
  double _precoDoProdutoParaSelecao(Map<String, dynamic> p, String tamanho, String cor) {
    final base = safeDouble(p['preco']);
    if (tamanho.trim().isEmpty) return base;
    final ppt = p['precoPorTamanho'];
    if (ppt is Map && ppt.isNotEmpty) {
      final v = ppt[tamanho];
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
      final temTamanhos = estoquePorTamanho.isNotEmpty || (variacoes.isNotEmpty && variacoes.keys.isNotEmpty);

      if (!temTamanhos) continue;

      final tam = (_selecoes[i]['tamanho'] ?? '').trim();
      if (tam.isEmpty) return false;

      if (variacoes.isNotEmpty && variacoes.containsKey(tam)) {
        final mapaCor = variacoes[tam];
        if (mapaCor is Map && mapaCor.isNotEmpty) {
          final cor = (_selecoes[i]['cor'] ?? '').trim();
          if (cor.isEmpty) return false;
        }
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
      resultado.add({
        'nome': nome,
        'slug': slug,
        'quantidade': qtdBase * _qtd,
        'tamanho': (_selecoes[i]['tamanho'] ?? '').trim(),
        'cor': (_selecoes[i]['cor'] ?? '').trim(),
        if (pid.isNotEmpty) 'productId': pid,
      });
    }
    return resultado;
  }

  static Color _getColorFromName(String nome) {
    const coresMap = {
      'preto': Colors.black, 'branco': Colors.white, 'vermelho': Colors.red,
      'azul': Colors.blue, 'verde': Colors.green, 'amarelo': Colors.yellow,
      'rosa': Colors.pink, 'roxo': Colors.purple, 'laranja': Colors.orange,
      'cinza': Colors.grey, 'marrom': Colors.brown, 'bege': Color(0xFFF5F5DC),
      'dourado': Color(0xFFFFD700), 'prata': Color(0xFFC0C0C0),
    };
    return coresMap[nome.toLowerCase()] ?? Colors.grey;
  }

  void _confirmar() {
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
    widget.onAdd(item);
    Navigator.of(context).pop();
    widget.onAbrirCarrinho?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final itens = _itensCombo;
    final precoUnidade = _precoFinalUnidade;
    final precoTotal = precoUnidade * _qtd;
    String fmt2(num v) => v.toStringAsFixed(2).replaceAll('.', ',');

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
                        'Selecione tamanho e cor de cada item',
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
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...List.generate(itens.length, (i) {
                    final item = itens[i];
                    final nome = (item['nome'] ?? '').toString();
                    final p = _produtoParaItem(item);

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
                          if (e.value is Map) {
                            int total = 0;
                            for (final v in (e.value as Map).values) {
                              total += v is num ? v.truncate() : 0;
                            }
                            if (total > 0) {
                              tamanhosDisponiveis[e.key.toString()] = total;
                            }
                          }
                        }
                        temTamanhos = tamanhosDisponiveis.isNotEmpty;
                        final tamSel = _selecoes[i]['tamanho'] ?? '';
                        if (tamSel.isNotEmpty && variacoes.containsKey(tamSel)) {
                          final mapa = variacoes[tamSel];
                          if (mapa is Map) {
                            mapa.forEach((k, v) {
                              final q = v is num ? v.truncate() : 0;
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
                        side: BorderSide(color: primaryColor.withValues(alpha:0.3), width: 1.5),
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
                                    color: primaryColor.withValues(alpha:0.2),
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
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha:0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.amber.shade700, width: 1),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.info_outline, size: 18, color: Colors.amber.shade800),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Produto não encontrado no catálogo. Será adicionado com opção padrão.',
                                        style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ] else ...[
                              const SizedBox(height: 14),
                              Text('Tamanho', style: labelStyle),
                              const SizedBox(height: 8),
                              if (temTamanhos)
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
                                        });
                                      },
                                      selectedColor: primaryColor.withValues(alpha:0.25),
                                      checkmarkColor: primaryColor,
                                      side: BorderSide(
                                        color: sel ? primaryColor : theme.dividerColor,
                                        width: sel ? 2 : 1,
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    );
                                  }).toList(),
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: theme.dividerColor.withValues(alpha:0.3),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Único (sem variação)',
                                    style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withValues(alpha:0.7)),
                                  ),
                                ),
                              if (coresDisponiveis.isNotEmpty) ...[
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
                                        backgroundColor: _getColorFromName(e.key),
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
                                        });
                                      },
                                      selectedColor: primaryColor.withValues(alpha:0.25),
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
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Quantidade:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
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
                      const Spacer(),
                        Text(
                        'Total: R\$ ${fmt2(precoTotal)}',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: theme.colorScheme.primary),
                      ),
                      if (_descontoComboValor > 0 || _descontoComboPercentual > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Subtotal: R\$ ${fmt2(_subtotalUnidade * _qtd)} → com desconto',
                            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _podeConfirmar ? _confirmar : null,
                      icon: const Icon(Icons.shopping_cart_checkout, size: 22),
                      label: const Text('Adicionar kit ao carrinho'),
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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

