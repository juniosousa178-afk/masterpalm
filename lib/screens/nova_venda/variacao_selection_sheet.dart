// lib/screens/nova_venda/variacao_selection_sheet.dart
// Modal de seleção de tamanho / cor / personalização (letra, estampa, etc.) — Nova Venda

import 'package:flutter/material.dart';

import '../../core/catalog_color_from_name.dart';
import '../../core/produto_variacao_extra.dart';
import '../../models/produto.dart';
import '../../widgets/variacao_extras_collapsible.dart';

/// Retorno ao confirmar: tamanho, cor, quantidade, extra (valor técnico), resumo para exibição/nota.
typedef NovaVendaVariacaoOnConfirm = void Function(
  String tamanho,
  String cor,
  int quantidade,
  String extraValor,
  String variacaoExtraResumo,
);

class NovaVendaVariacaoSheet extends StatefulWidget {
  final Produto produto;
  final double preco;
  final NovaVendaVariacaoOnConfirm onConfirmar;

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
    required NovaVendaVariacaoOnConfirm onConfirmar,
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
  String _extraSelecionado = '';
  int _quantidade = 1;

  String _fmt2(num v) => v.toStringAsFixed(2).replaceAll('.', ',');

  double get _precoAtualUnitario =>
      widget.produto.precoParaVariacao(_tamanhoSelecionado);

  bool get _temVariacoes =>
      widget.produto.usaVariacoes ||
      widget.produto.estoquePorTamanho.isNotEmpty;

  bool get _mostrarTamanho =>
      widget.produto.temVariacaoSoloTamanho ||
      widget.produto.estoquePorTamanho.isNotEmpty ||
      widget.produto.temVariacaoTamanhoECor;

  bool get _mostrarCor =>
      widget.produto.temVariacaoSoloCor ||
      widget.produto.temVariacaoTamanhoECor;

  Map<String, int> get _tamanhosDisponiveis {
    if (widget.produto.usaVariacoes && widget.produto.variacoes != null) {
      final result = <String, int>{};
      widget.produto.variacoes!.forEach((tamanho, cores) {
        if (tamanho == 'sem-tamanho') return;
        if (cores is Map) {
          int total = 0;
          for (final qtd in cores.values) {
            total += ProdutoVariacaoExtra.somarCelula(qtd);
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
          mapaTamanho.map(
            (k, v) =>
                MapEntry(k.toString(), ProdutoVariacaoExtra.somarCelula(v)),
          ),
        );
      }
    }
    return {};
  }

  List<String> get _opcoesExtra => ProdutoVariacaoExtra.opcoesExtraPara(
        widget.produto.variacoes,
        _tamanhoSelecionado,
        _corSelecionada,
      );

  String get _labelExtra => ProdutoVariacaoExtra.labelExtraParaProduto(
        widget.produto.variacoes,
        widget.produto.variacoesExtraTipo,
      );

  bool get _podeConfirmar {
    final p = widget.produto;
    if (_mostrarTamanho &&
        _tamanhosDisponiveis.isNotEmpty &&
        _tamanhoSelecionado.isEmpty) {
      return false;
    }
    if (p.temVariacaoSoloCor) {
      if (_coresDisponiveis.isNotEmpty && _corSelecionada.trim().isEmpty) {
        return false;
      }
    } else if (p.usaVariacoes && _tamanhoSelecionado.isNotEmpty) {
      final mapaTamanho = p.variacoes![_tamanhoSelecionado];
      if (mapaTamanho is Map &&
          mapaTamanho.isNotEmpty &&
          _corSelecionada.trim().isEmpty) {
        return false;
      }
    }
    if (_opcoesExtra.isNotEmpty && _extraSelecionado.trim().isEmpty) {
      return false;
    }
    return _quantidade >= 1;
  }

  int get _estoqueDisponivel {
    final ex = _extraSelecionado.trim();
    if (widget.produto.temVariacaoSoloCor && _corSelecionada.isNotEmpty) {
      return widget.produto.obterEstoqueVariacao('', _corSelecionada, ex);
    }
    if (widget.produto.usaVariacoes && _tamanhoSelecionado.isNotEmpty) {
      final corKey = _corSelecionada.isEmpty ? 'sem-cor' : _corSelecionada;
      return widget.produto
          .obterEstoqueVariacao(_tamanhoSelecionado, corKey, ex);
    }
    if (_tamanhoSelecionado.isNotEmpty) {
      return widget.produto.estoquePorTamanho[_tamanhoSelecionado] ?? 0;
    }
    return widget.produto.quantidade;
  }

  void _confirmar() {
    if (!_podeConfirmar) return;
    if (_quantidade > _estoqueDisponivel) return;

    final ex = _extraSelecionado.trim();
    final corKey = _corSelecionada.isEmpty ? 'sem-cor' : _corSelecionada;
    final tamKey =
        _tamanhoSelecionado.isEmpty ? 'sem-tamanho' : _tamanhoSelecionado;

    String resumo = '';
    if (ex.isNotEmpty) {
      final tipo = ProdutoVariacaoExtra.tipoParaCelula(
        widget.produto.variacoesExtraTipo,
        tamKey,
        corKey,
        ex,
      );
      resumo = ProdutoVariacaoExtra.textoResumoExtra(
        extraTipo: tipo,
        extraValor: ex,
      );
    }

    widget.onConfirmar(
      _tamanhoSelecionado,
      _corSelecionada,
      _quantidade,
      ex,
      resumo,
    );
    Navigator.of(context).pop();
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
                        'R\$ ${_fmt2(_precoAtualUnitario)}',
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
                                    _corSelecionada = '';
                                    _extraSelecionado = '';
                                    if (widget.produto.usaVariacoes &&
                                        widget.produto.variacoes != null) {
                                      final mapa =
                                          widget.produto.variacoes![tam];
                                      if (mapa is Map) {
                                        final keys = mapa.keys
                                            .map((k) => k.toString())
                                            .where((k) =>
                                                ProdutoVariacaoExtra
                                                    .somarCelula(mapa[k]) >
                                                0)
                                            .toList();
                                        if (keys.length == 1 &&
                                            keys.first == 'sem-cor') {
                                          _corSelecionada = 'sem-cor';
                                        }
                                      }
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
                                    color:
                                        sel ? Colors.white70 : Colors.grey[600],
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
                      (widget.produto.temVariacaoSoloCor ||
                          _tamanhoSelecionado.isNotEmpty)) ...[
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
                        if (!widget.produto.temVariacaoSoloCor &&
                            cor == 'sem-cor') {
                          return const SizedBox.shrink();
                        }
                        final qtd = e.value;
                        final sel = _corSelecionada == cor;
                        final hasStock = qtd > 0;
                        final corVisual = catalogColorFromName(cor);
                        return InkWell(
                          onTap: hasStock
                              ? () => setState(() {
                                    _corSelecionada = cor;
                                    _extraSelecionado = '';
                                  })
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
                                    color:
                                        sel ? Colors.white70 : Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  if (_opcoesExtra.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      _labelExtra,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    VariacaoExtrasCollapsible(
                      options: _opcoesExtra,
                      selectedValue: _extraSelecionado,
                      onOptionChosen: (ex) =>
                          setState(() => _extraSelecionado = ex),
                      itemBuilder: (context, ex, _) {
                        final sel = _extraSelecionado == ex;
                        final cell = _celulaAtualParaExtra();
                        final disp = cell != null
                            ? ProdutoVariacaoExtra.quantidadeNaCelula(cell, ex)
                            : 0;
                        final hasStock = disp > 0;
                        return InkWell(
                          onTap: hasStock
                              ? () => setState(() => _extraSelecionado = ex)
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
                                  ? theme.colorScheme.secondaryContainer
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: sel
                                    ? theme.colorScheme.secondary
                                    : Colors.grey.shade300,
                                width: sel ? 2 : 1,
                              ),
                            ),
                            child: Text(
                              hasStock ? '$ex ($disp)' : '$ex (0)',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: sel
                                    ? theme.colorScheme.onSecondaryContainer
                                    : Colors.black87,
                              ),
                            ),
                          ),
                        );
                      },
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
                            : 'Adicionar (R\$ ${_fmt2(_precoAtualUnitario * _quantidade)})',
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

  /// Célula atual em [variacoes] para checar estoque por opção extra.
  dynamic _celulaAtualParaExtra() {
    final v = widget.produto.variacoes;
    if (v == null) return null;
    if (widget.produto.temVariacaoSoloCor && _corSelecionada.isNotEmpty) {
      final sm = v['sem-tamanho'];
      if (sm is Map) return sm[_corSelecionada];
      return null;
    }
    if (_tamanhoSelecionado.isEmpty) return null;
    final mapa = v[_tamanhoSelecionado];
    if (mapa is! Map) return null;
    final corKey = _corSelecionada.isEmpty ? 'sem-cor' : _corSelecionada;
    return mapa[corKey];
  }
}
