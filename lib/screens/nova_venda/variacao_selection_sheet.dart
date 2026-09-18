// lib/screens/nova_venda/variacao_selection_sheet.dart
// Modal de seleção de tamanho / cor / personalização (letra, estampa, etc.) — Nova Venda
// Binding ao vivo por productId: snapshot inicial NÃO é autoridade permanente.

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../../core/catalog_color_from_name.dart';
import '../../core/produto_grade_pdv_hydration.dart';
import '../../core/produto_variacao_extra.dart';
import '../../core/produto_variation_stock_consistency.dart';
import '../../models/produto.dart';
import '../../services/produto_grade_pdv_hydration_service.dart';
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

  /// Box Hive da loja — quando informado, a sheet reage à hidratação ao vivo.
  final Box<Produto>? produtosBox;
  final String? lojaId;

  /// Se true (padrão com box), dispara hidratação pontual ao abrir.
  final bool hydrateOnOpen;

  const NovaVendaVariacaoSheet({
    super.key,
    required this.produto,
    required this.preco,
    required this.onConfirmar,
    this.produtosBox,
    this.lojaId,
    this.hydrateOnOpen = true,
  });

  static Future<void> show(
    BuildContext context, {
    required Produto produto,
    required double preco,
    required NovaVendaVariacaoOnConfirm onConfirmar,
    Box<Produto>? produtosBox,
    String? lojaId,
    bool hydrateOnOpen = true,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NovaVendaVariacaoSheet(
        produto: produto,
        preco: preco,
        onConfirmar: onConfirmar,
        produtosBox: produtosBox,
        lojaId: lojaId,
        hydrateOnOpen: hydrateOnOpen,
      ),
    );
  }

  @override
  State<NovaVendaVariacaoSheet> createState() => _NovaVendaVariacaoSheetState();
}

class _NovaVendaVariacaoSheetState extends State<NovaVendaVariacaoSheet> {
  late Produto _liveProduto;
  late final String? _boundProductId;
  late final String _boundLojaId;

  GradePdvReadiness _readiness = GradePdvReadiness.unknown;
  bool _hydrating = false;
  String? _errorMessage;
  int _hydrateGeneration = 0;

  String _tamanhoSelecionado = '';
  String _corSelecionada = '';
  String _extraSelecionado = '';
  int _quantidade = 1;

  String _fmt2(num v) => v.toStringAsFixed(2).replaceAll('.', ',');

  Produto get _p => _liveProduto;

  double get _precoAtualUnitario => _p.precoParaVariacao(_tamanhoSelecionado);

  bool get _temVariacoes =>
      _p.usaVariacoes || _p.estoquePorTamanho.isNotEmpty;

  bool get _mostrarTamanho =>
      _p.temVariacaoSoloTamanho ||
      _p.estoquePorTamanho.isNotEmpty ||
      _p.temVariacaoTamanhoECor;

  bool get _mostrarCor =>
      _p.temVariacaoSoloCor || _p.temVariacaoTamanhoECor;

  Map<String, int> get _tamanhosDisponiveis {
    if (_p.usaVariacoes && _p.variacoes != null) {
      final result = <String, int>{};
      _p.variacoes!.forEach((tamanho, cores) {
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
    return _p.estoquePorTamanho;
  }

  Map<String, int> get _coresDisponiveis {
    if (_p.temVariacaoSoloCor) {
      return _p.estoquePorCor;
    }
    if (_p.usaVariacoes &&
        _p.variacoes != null &&
        _tamanhoSelecionado.isNotEmpty) {
      final mapaTamanho = _p.variacoes![_tamanhoSelecionado];
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
        _p.variacoes,
        _tamanhoSelecionado,
        _corSelecionada,
      );

  String get _labelExtra => ProdutoVariacaoExtra.labelExtraParaProduto(
        _p.variacoes,
        _p.variacoesExtraTipo,
      );

  bool get _podeConfirmar {
    final stockConsistency = ProdutoVariationStockConsistencyEvaluator.evaluateProduto(
      _p,
      hydrating: _hydrating,
      offlinePartial: _readiness == GradePdvReadiness.offlinePartial &&
          !gradePdvHasLocalVariationSignal(_p),
    );
    if (stockConsistency.blocksPdvSale) {
      return false;
    }
    final p = _p;
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

  ProdutoVariationStockConsistency get _stockConsistency =>
      ProdutoVariationStockConsistencyEvaluator.evaluateProduto(
        _p,
        hydrating: _hydrating,
        offlinePartial: _readiness == GradePdvReadiness.offlinePartial &&
            !gradePdvHasLocalVariationSignal(_p),
      );

  int get _estoqueDisponivel {
    final ex = _extraSelecionado.trim();
    if (_p.temVariacaoSoloCor && _corSelecionada.isNotEmpty) {
      return _p.obterEstoqueVariacao('', _corSelecionada, ex);
    }
    if (_p.usaVariacoes && _tamanhoSelecionado.isNotEmpty) {
      final corKey = _corSelecionada.isEmpty ? 'sem-cor' : _corSelecionada;
      return _p.obterEstoqueVariacao(_tamanhoSelecionado, corKey, ex);
    }
    if (_tamanhoSelecionado.isNotEmpty) {
      return _p.estoquePorTamanho[_tamanhoSelecionado] ?? 0;
    }
    return _p.quantidade;
  }

  @override
  void initState() {
    super.initState();
    _liveProduto = widget.produto;
    _boundProductId = gradePdvProductId(widget.produto);
    _boundLojaId = (widget.lojaId ?? widget.produto.lojaId).trim();

    final sessionAuth = _boundProductId != null &&
        ProdutoGradePdvHydrationService.isSessionAuthoritative(
          lojaId: _boundLojaId,
          productId: _boundProductId!,
        );
    _readiness = evaluateGradePdvReadiness(
      produto: _liveProduto,
      sessionHydratedAuthoritative: sessionAuth,
      hydrating: false,
      hydrationFailedOrOfflinePartial: false,
    );

    final box = widget.produtosBox;
    if (widget.hydrateOnOpen &&
        box != null &&
        _boundProductId != null &&
        _boundLojaId.isNotEmpty) {
      // Hidratação pontual: ao concluir, setState aplica o produto vivo por productId.
      _startHydration();
    }
  }

  @override
  void dispose() {
    _hydrateGeneration++;
    super.dispose();
  }

  Future<void> _startHydration() async {
    final box = widget.produtosBox;
    final id = _boundProductId;
    if (box == null || id == null || _boundLojaId.isEmpty) return;

    final gen = ++_hydrateGeneration;
    if (mounted) {
      setState(() {
        _hydrating = true;
        _readiness = GradePdvReadiness.hydrating;
        _errorMessage = null;
      });
    }

    final result = await ProdutoGradePdvHydrationService.hydrateByProductId(
      lojaId: _boundLojaId,
      productId: id,
      produtosBox: box,
      seed: _liveProduto,
    );

    // Dispose / race: geração antiga ou productId diferente → ignorar.
    if (!mounted || gen != _hydrateGeneration) return;
    if (result.productId.trim().isNotEmpty &&
        result.productId.trim() != id) {
      return;
    }

    setState(() {
      _hydrating = false;
      if (result.produto != null) {
        _liveProduto = result.produto!;
      }
      _readiness = result.readiness == GradePdvReadiness.hydrating
          ? evaluateGradePdvReadiness(
              produto: _liveProduto,
              sessionHydratedAuthoritative:
                  ProdutoGradePdvHydrationService.isSessionAuthoritative(
                lojaId: _boundLojaId,
                productId: id,
              ),
              hydrating: false,
              hydrationFailedOrOfflinePartial: false,
            )
          : result.readiness;
      _errorMessage = result.errorMessage;
    });
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
        _p.variacoesExtraTipo,
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

  Widget _buildHydratingBody(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _p.nome,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 24),
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'Carregando variações…',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOfflinePartialBody(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _p.nome,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _errorMessage ?? 'Não foi possível carregar as variações',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _hydrating ? null : _startHydration,
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final showLoadingOnly = _readiness == GradePdvReadiness.hydrating &&
        !gradePdvHasLocalVariationSignal(_p);
    final showOfflinePartial =
        _readiness == GradePdvReadiness.offlinePartial &&
            !gradePdvHasLocalVariationSignal(_p);

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
          if (showLoadingOnly)
            _buildHydratingBody(theme)
          else if (showOfflinePartial)
            _buildOfflinePartialBody(theme)
          else
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
                            _p.nome,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (_hydrating)
                          const Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
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
                    if (_stockConsistency.isUnresolved) ...[
                      const SizedBox(height: 12),
                      Material(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.warning_amber_rounded,
                                  color: Colors.orange.shade800),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _stockConsistency.message.isNotEmpty
                                      ? _stockConsistency.message
                                      : 'Estoque inconsistente — sincronização necessária',
                                  style: TextStyle(
                                    color: Colors.orange.shade900,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
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
                                      if (_p.usaVariacoes &&
                                          _p.variacoes != null) {
                                        final mapa = _p.variacoes![tam];
                                        if (mapa is Map) {
                                          final keys = mapa.keys
                                              .map((k) => k.toString())
                                              .where(
                                                (k) =>
                                                    ProdutoVariacaoExtra
                                                        .somarCelula(
                                                      mapa[k],
                                                    ) >
                                                    0,
                                              )
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
                                      color:
                                          sel ? Colors.white : Colors.black87,
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
                        (_p.temVariacaoSoloCor ||
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
                          if (!_p.temVariacaoSoloCor && cor == 'sem-cor') {
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
                                      color:
                                          sel ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '($qtd)',
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
                              ? ProdutoVariacaoExtra.quantidadeNaCelula(
                                  cell,
                                  ex,
                                )
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
                          _stockConsistency.blocksPdvSale
                              ? 'Estoque inconsistente'
                              : _temVariacoes && !_podeConfirmar
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
    final v = _p.variacoes;
    if (v == null) return null;
    if (_p.temVariacaoSoloCor && _corSelecionada.isNotEmpty) {
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
