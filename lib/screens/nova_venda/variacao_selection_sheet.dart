// lib/screens/nova_venda/variacao_selection_sheet.dart
// Modal de seleção de tamanho/cor por boxes (estilo catálogo) para Nova Venda

import 'package:flutter/material.dart';
import '../../models/produto.dart';

/// Sheet para selecionar variação (tamanho/cor) ao adicionar produto na Nova Venda.
/// Usa boxes clicáveis como no catálogo.
class NovaVendaVariacaoSheet extends StatefulWidget {
  final Produto produto;
  final double preco;
  final void Function(String tamanho, String cor, int quantidade) onConfirmar;

  const NovaVendaVariacaoSheet({
    super.key,
    required this.produto,
    required this.preco,
    required this.onConfirmar,
  });

  static Future<void> show(
    BuildContext context, {
    required Produto produto,
    required double preco,
    required void Function(String tamanho, String cor, int quantidade) onConfirmar,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NovaVendaVariacaoSheet(
        produto: produto,
        preco: preco,
        onConfirmar: onConfirmar,
      ),
    );
  }

  @override
  State<NovaVendaVariacaoSheet> createState() => _NovaVendaVariacaoSheetState();
}

class _NovaVendaVariacaoSheetState extends State<NovaVendaVariacaoSheet> {
  String _tamanhoSelecionado = '';
  String _corSelecionada = '';
  int _quantidade = 1;

  String _fmt2(num v) => v.toStringAsFixed(2).replaceAll('.', ',');

  bool get _temVariacoes =>
      widget.produto.usaVariacoes ||
      widget.produto.estoquePorTamanho.isNotEmpty;

  /// Só tamanho: exibe seleção de tamanho (exclui sem-tamanho)
  bool get _mostrarTamanho =>
      widget.produto.temVariacaoSoloTamanho || widget.produto.estoquePorTamanho.isNotEmpty ||
      widget.produto.temVariacaoTamanhoECor;

  /// Só cor: exibe seleção de cor
  bool get _mostrarCor =>
      widget.produto.temVariacaoSoloCor || widget.produto.temVariacaoTamanhoECor;

  Map<String, int> get _tamanhosDisponiveis {
    if (widget.produto.usaVariacoes && widget.produto.variacoes != null) {
      final result = <String, int>{};
      widget.produto.variacoes!.forEach((tamanho, cores) {
        if (tamanho == 'sem-tamanho') return;
        if (cores is Map) {
          int total = 0;
          for (final qtd in cores.values) {
            total += (qtd as num?)?.toInt() ?? 0;
          }
          if (total > 0) result[tamanho.toString()] = total;
        }
      });
      if (result.isNotEmpty) return result;
    }
    return widget.produto.estoquePorTamanho;
  }

  Map<String, int> get _coresDisponiveis {
    if (widget.produto.temVariacaoSoloCor) {
      return widget.produto.estoquePorCor;
    }
    if (widget.produto.usaVariacoes &&
        widget.produto.variacoes != null &&
        _tamanhoSelecionado.isNotEmpty) {
      final mapaTamanho = widget.produto.variacoes![_tamanhoSelecionado];
      if (mapaTamanho is Map) {
        return Map<String, int>.from(
          mapaTamanho.map((k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0)),
        );
      }
    }
    return {};
  }

  bool get _podeConfirmar {
    if (_mostrarTamanho && _tamanhosDisponiveis.isNotEmpty && _tamanhoSelecionado.isEmpty) {
      return false;
    }
    if (_mostrarCor && _coresDisponiveis.isNotEmpty && _corSelecionada.isEmpty) {
      return false;
    }
    return _quantidade >= 1;
  }

  int get _estoqueDisponivel {
    if (widget.produto.temVariacaoSoloCor && _corSelecionada.isNotEmpty) {
      return widget.produto.obterEstoqueVariacao('', _corSelecionada);
    }
    if (widget.produto.usaVariacoes && _tamanhoSelecionado.isNotEmpty) {
      final corKey = _corSelecionada.isEmpty ? 'sem-cor' : _corSelecionada;
      return widget.produto.obterEstoqueVariacao(_tamanhoSelecionado, corKey);
    }
    if (_tamanhoSelecionado.isNotEmpty) {
      return widget.produto.estoquePorTamanho[_tamanhoSelecionado] ?? 0;
    }
    return widget.produto.quantidade;
  }

  Color _getColorFromName(String nome) {
    const coresMap = {
      'preto': Colors.black,
      'branco': Colors.white,
      'vermelho': Colors.red,
      'azul': Colors.blue,
      'verde': Colors.green,
      'amarelo': Colors.yellow,
      'rosa': Colors.pink,
      'roxo': Colors.purple,
      'laranja': Colors.orange,
      'cinza': Colors.grey,
      'marrom': Colors.brown,
      'bege': Color(0xFFF5F5DC),
      'dourado': Color(0xFFFFD700),
      'prata': Color(0xFFC0C0C0),
    };
    return coresMap[nome.toLowerCase()] ?? Colors.grey;
  }

  void _confirmar() {
    if (!_podeConfirmar) return;
    if (_quantidade > _estoqueDisponivel) return;
    widget.onConfirmar(_tamanhoSelecionado, _corSelecionada, _quantidade);
    Navigator.of(context).pop((tam: _tamanhoSelecionado, cor: _corSelecionada, qtd: _quantidade));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.produto.nome,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      'R\$ ${_fmt2(widget.preco)}',
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                if (_mostrarTamanho) ...[
                  Text(
                    'Tamanho',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _tamanhosDisponiveis.entries.map((e) {
                      final tam = e.key;
                      final qtd = e.value;
                      final sel = _tamanhoSelecionado == tam;
                      final hasStock = qtd > 0;
                      return InkWell(
                        onTap: hasStock
                            ? () => setState(() {
                                  _tamanhoSelecionado = tam;
                                  if (widget.produto.usaVariacoes) {
                                    _corSelecionada = '';
                                  }
                                })
                            : null,
                        borderRadius: BorderRadius.circular(10),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: sel
                                ? theme.colorScheme.primary
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: sel
                                  ? theme.colorScheme.primary
                                  : Colors.grey.shade300,
                              width: sel ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                tam,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: sel ? Colors.white : Colors.black87,
                                ),
                              ),
                              Text(
                                hasStock ? '$qtd un.' : 'Esgotado',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: sel
                                      ? Colors.white70
                                      : Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],

                if (_mostrarCor &&
                    _coresDisponiveis.isNotEmpty &&
                    (widget.produto.temVariacaoSoloCor || _tamanhoSelecionado.isNotEmpty)) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Cor',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _coresDisponiveis.entries.map((e) {
                      final cor = e.key;
                      final qtd = e.value;
                      final sel = _corSelecionada == cor;
                      final hasStock = qtd > 0;
                      final corVisual = _getColorFromName(cor);
                      return InkWell(
                        onTap: hasStock
                            ? () => setState(() => _corSelecionada = cor)
                            : null,
                        borderRadius: BorderRadius.circular(10),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: sel
                                ? theme.colorScheme.primary
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: sel
                                  ? theme.colorScheme.primary
                                  : Colors.grey.shade300,
                              width: sel ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: corVisual,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.grey.shade400,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                cor,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: sel ? Colors.white : Colors.black87,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '($qtd)',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: sel ? Colors.white70 : Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],

                const SizedBox(height: 20),
                Row(
                  children: [
                    Text(
                      'Quantidade:',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Row(
                      children: [
                        IconButton(
                          onPressed: _quantidade > 1
                              ? () => setState(() => _quantidade--)
                              : null,
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Text(
                          '$_quantidade',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          onPressed: _quantidade < _estoqueDisponivel
                              ? () => setState(() => _quantidade++)
                              : null,
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                    const Spacer(),
                    if (_estoqueDisponivel >= 0)
                      Text(
                        'Estoque: $_estoqueDisponivel',
                        style: TextStyle(
                          fontSize: 12,
                          color: _estoqueDisponivel < 3
                              ? Colors.orange
                              : Colors.grey[600],
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _podeConfirmar ? _confirmar : null,
                    icon: const Icon(Icons.check),
                    label: Text(
                      _temVariacoes && !_podeConfirmar
                          ? 'Selecione as opções'
                          : 'Adicionar (R\$ ${_fmt2(widget.preco * _quantidade)})',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
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
