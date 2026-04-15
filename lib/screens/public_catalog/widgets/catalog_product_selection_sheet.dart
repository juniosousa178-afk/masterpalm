// lib/screens/public_catalog/widgets/catalog_product_selection_sheet.dart
// Modal de seleção de tamanho/cor – extraído do public_catalog_screen.

import 'package:flutter/material.dart';

import '../../../core/catalog_color_from_name.dart';
import '../../../core/produto_variacao_extra.dart';
import '../../../widgets/smart_image.dart';
import '../../../widgets/variacao_extras_collapsible.dart';
import '../catalog_variation_filter.dart';

class CatalogProductSelectionSheet extends StatefulWidget {
  final String name;
  final double price;
  final double? precoOriginal;
  final bool emPromocao;
  final String imageUrl;
  final Map<String, int> estoquePorTamanho;
  final Map<String, int> estoquePorCor;
  final Map<String, dynamic>? variacoes;
  /// { tamanho: { cor: { extraValor: extraTipo } } } — opcional, só para rótulo do eixo extra.
  final Map<String, dynamic>? variacoesExtraTipo;
  final Map<String, double>? precoPorTamanho;
  final void Function(
    String? tamanho,
    String? cor,
    double preco,
    String extraValor,
    String extraTipo,
  ) onAddToCart;
  final double percentualDescontoPix;
  /// Se true, exibe "X un."; se false, exibe "Disponível" (como no botão Ver).
  final bool mostrarQuantidadeNoCatalogo;
  /// Pré-seleção alinhada ao filtro/`xv` do catálogo (quando compatível com tam/cor).
  final String? initialExtraValor;
  /// Sincroniza filtro global e query `xv` na Web ao mudar a personalização.
  final void Function(String? value)? onCatalogVariacaoExtraChanged;

  const CatalogProductSelectionSheet({
    super.key,
    required this.name,
    required this.price,
    this.precoOriginal,
    required this.emPromocao,
    required this.imageUrl,
    required this.estoquePorTamanho,
    required this.estoquePorCor,
    this.variacoes,
    this.variacoesExtraTipo,
    this.precoPorTamanho,
    required this.onAddToCart,
    this.percentualDescontoPix = 0.0,
    this.mostrarQuantidadeNoCatalogo = false,
    this.initialExtraValor,
    this.onCatalogVariacaoExtraChanged,
  });

  @override
  State<CatalogProductSelectionSheet> createState() =>
      _CatalogProductSelectionSheetState();
}

class _CatalogProductSelectionSheetState
    extends State<CatalogProductSelectionSheet> {
  String? _tamanhoSelecionado;
  String? _corSelecionada;
  String? _extraSelecionado;
  String? _pendingSeedExtra;

  String _fmt2(num v) => v.toStringAsFixed(2).replaceAll('.', ',');

  @override
  void initState() {
    super.initState();
    final s = widget.initialExtraValor?.trim();
    _pendingSeedExtra = (s != null && s.isNotEmpty) ? s : null;
    _scheduleTryConsumeSeedExtra();
  }

  @override
  void didUpdateWidget(covariant CatalogProductSelectionSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialExtraValor != oldWidget.initialExtraValor) {
      final s = widget.initialExtraValor?.trim();
      _pendingSeedExtra = (s != null && s.isNotEmpty) ? s : null;
      _scheduleTryConsumeSeedExtra();
    }
  }

  void _scheduleTryConsumeSeedExtra() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _tryConsumeSeedExtra();
    });
  }

  void _tryConsumeSeedExtra() {
    final seed = _pendingSeedExtra;
    if (seed == null) return;
    if (!_temEixoExtraNaCor) return;
    if (_opcoesExtra.isEmpty) return;
    String? matched;
    for (final op in _opcoesExtra) {
      if (CatalogVariationFilter.keysMatch(op, seed)) {
        matched = op;
        break;
      }
    }
    _pendingSeedExtra = null;
    if (matched != null && _extraSelecionado != matched) {
      setState(() => _extraSelecionado = matched);
      widget.onCatalogVariacaoExtraChanged?.call(matched);
    }
  }

  /// Preço para o tamanho selecionado (ou preço base se não houver precoPorTamanho).
  double get _precoAtual {
    if (_tamanhoSelecionado != null &&
        widget.precoPorTamanho != null &&
        widget.precoPorTamanho!.containsKey(_tamanhoSelecionado)) {
      return widget.precoPorTamanho![_tamanhoSelecionado]!;
    }
    return widget.price;
  }

  bool get _hasTamanhos =>
      widget.estoquePorTamanho.isNotEmpty ||
      (_tamanhosDisponiveis.isNotEmpty);

  bool get _hasCores => _coresDisponiveis.isNotEmpty;

  Map<String, int> get _tamanhosDisponiveis {
    if (widget.variacoes != null && widget.variacoes!.isNotEmpty) {
      final result = <String, int>{};
      widget.variacoes!.forEach((tamanho, cores) {
        if (tamanho == 'sem-tamanho') return;
        if (cores is Map) {
          int total = 0;
          cores.forEach((_, qtd) {
            total += ProdutoVariacaoExtra.somarCelula(qtd);
          });
          if (total > 0) {
            result[tamanho.toString()] = total;
          }
        }
      });
      if (result.isNotEmpty) return result;
    }
    return widget.estoquePorTamanho;
  }

  Map<String, int> get _coresDisponiveis {
    if (widget.variacoes != null && widget.variacoes!.containsKey('sem-tamanho')) {
      final semTam = widget.variacoes!['sem-tamanho'];
      if (semTam is Map && semTam.isNotEmpty) {
        return Map<String, int>.from(semTam.map((key, value) => MapEntry(
            key.toString(), ProdutoVariacaoExtra.somarCelula(value))));
      }
    }
    if (widget.variacoes != null && _tamanhoSelecionado != null) {
      final mapaTamanho = widget.variacoes![_tamanhoSelecionado];
      if (mapaTamanho is Map) {
        return Map<String, int>.from(mapaTamanho.map((key, value) =>
            MapEntry(key.toString(), ProdutoVariacaoExtra.somarCelula(value))));
      }
    }
    return widget.estoquePorCor;
  }

  bool get _temEixoExtraNaCor {
    if (widget.variacoes == null || _corSelecionada == null) return false;
    final tamKey = _tamanhoSelecionado ?? '';
    Map? mapaTam;
    if (tamKey.isEmpty || tamKey == 'sem-tamanho') {
      mapaTam = widget.variacoes!['sem-tamanho'] as Map?;
    } else {
      mapaTam = widget.variacoes![tamKey] as Map?;
    }
    if (mapaTam == null) return false;
    final cell = mapaTam[_corSelecionada!];
    return ProdutoVariacaoExtra.celulaTemExtrasNaoVazios(cell);
  }

  List<String> get _opcoesExtra {
    if (widget.variacoes == null || _corSelecionada == null) {
      return const [];
    }
    final tam = (_tamanhoSelecionado ?? '').trim();
    return ProdutoVariacaoExtra.opcoesExtraPara(
      widget.variacoes,
      tam,
      _corSelecionada!,
    );
  }

  String get _labelEixoExtra => ProdutoVariacaoExtra.labelExtraParaProduto(
        widget.variacoes,
        widget.variacoesExtraTipo,
      );

  bool get _podeAdicionar {
    if (_hasTamanhos && _tamanhoSelecionado == null) return false;
    if (_hasCores && _corSelecionada == null) return false;
    if (_temEixoExtraNaCor && (_extraSelecionado == null || _extraSelecionado!.trim().isEmpty)) {
      return false;
    }
    return true;
  }

  String get _textoButton {
    if (_hasTamanhos && _tamanhoSelecionado == null) {
      return 'Selecione o tamanho';
    }
    if (_hasCores && _corSelecionada == null) {
      return 'Selecione a cor';
    }
    if (_temEixoExtraNaCor &&
        (_extraSelecionado == null || _extraSelecionado!.trim().isEmpty)) {
      return 'Selecione $_labelEixoExtra';
    }
    return 'Adicionar ao carrinho';
  }

  String _extraTipoParaOpcao(String valor) {
    final v = widget.variacoesExtraTipo;
    if (v == null) return '';
    final tam = (_tamanhoSelecionado ?? '').trim();
    final chaveT = tam.isEmpty ? 'sem-tamanho' : tam;
    final cor = _corSelecionada ?? '';
    final corKey = cor.trim().isEmpty ? 'sem-cor' : cor;
    return ProdutoVariacaoExtra.tipoParaCelula(v, chaveT, corKey, valor);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withOpacity(0.1),
                  width: 1,
                ),
              ),
            ),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Selecione as opcoes',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.1),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.1),
                      ),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image(
                            image: mpImageProvider(widget.imageUrl),
                            width: 70,
                            height: 70,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              if (widget.emPromocao &&
                                  widget.precoOriginal != null)
                                Row(
                                  children: [
                                    Text(
                                      'R\$ ${_fmt2(widget.precoOriginal!)}',
                                      style: TextStyle(
                                        color: Colors.grey[500],
                                        fontSize: 12,
                                        decoration: TextDecoration.lineThrough,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.red[700],
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'R\$ ${_fmt2(_precoAtual)}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              else
                                Text(
                                  'R\$ ${_fmt2(_precoAtual)}',
                                  style: TextStyle(
                                    color: theme.colorScheme.primary,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.percentualDescontoPix > 0) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.pix, size: 16, color: Colors.green[700]),
                        const SizedBox(width: 6),
                        Text(
                          'ou R\$ ${_fmt2(_precoAtual * (1 - widget.percentualDescontoPix / 100))} no PIX',
                          style: TextStyle(
                            color: Colors.green[700],
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (_hasTamanhos) ...[
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Icon(
                          Icons.straighten,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Tamanho',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (_tamanhoSelecionado != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary
                                  .withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _tamanhoSelecionado!,
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _tamanhosDisponiveis.entries.map((entry) {
                        final tamanho = entry.key;
                        final qtd = entry.value;
                        final isSelected = _tamanhoSelecionado == tamanho;
                        final hasStock = qtd > 0;

                        return InkWell(
                          onTap: hasStock
                              ? () {
                                  setState(() {
                                    _tamanhoSelecionado = tamanho;
                                    if (widget.variacoes != null) {
                                      _corSelecionada = null;
                                      _extraSelecionado = null;
                                    }
                                  });
                                  if (widget.variacoes != null) {
                                    widget.onCatalogVariacaoExtraChanged
                                        ?.call(null);
                                    final s = widget.initialExtraValor?.trim();
                                    _pendingSeedExtra =
                                        (s != null && s.isNotEmpty) ? s : null;
                                    _scheduleTryConsumeSeedExtra();
                                  }
                                }
                              : null,
                          borderRadius: BorderRadius.circular(10),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 75,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: !hasStock
                                  ? Colors.grey.withOpacity(0.1)
                                  : isSelected
                                      ? theme.colorScheme.primary
                                      : Colors.white.withOpacity(0.05),
                              border: Border.all(
                                color: !hasStock
                                    ? Colors.grey.withOpacity(0.3)
                                    : isSelected
                                        ? theme.colorScheme.primary
                                        : Colors.white.withOpacity(0.2),
                                width: isSelected ? 2 : 1,
                              ),
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: theme.colorScheme.primary
                                            .withOpacity(0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  tamanho,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: !hasStock
                                        ? Colors.grey
                                        : isSelected
                                            ? Colors.white
                                            : theme.textTheme.bodyLarge?.color,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  hasStock ? (widget.mostrarQuantidadeNoCatalogo ? '$qtd un.' : 'Disponível') : 'Esgotado',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: !hasStock
                                        ? Colors.grey
                                        : isSelected
                                            ? Colors.white
                                                .withOpacity(0.8)
                                            : Colors.grey[500],
                                  ),
                                ),
                                if (widget.precoPorTamanho != null &&
                                    widget.precoPorTamanho!.containsKey(tamanho)) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'R\$ ${_fmt2(widget.precoPorTamanho![tamanho]!)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: !hasStock
                                          ? Colors.grey
                                          : isSelected
                                              ? Colors.white
                                              : theme.colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  if ((widget.variacoes != null &&
                          widget.variacoes!.isNotEmpty) ||
                      widget.estoquePorCor.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Icon(
                          Icons.palette,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Cor',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (_corSelecionada != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary
                                  .withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color:
                                        catalogColorFromName(_corSelecionada!),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white
                                          .withOpacity(0.5),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _corSelecionada!,
                                  style: TextStyle(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (widget.variacoes != null &&
                        widget.variacoes!.isNotEmpty &&
                        _tamanhoSelecionado == null)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.orange.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline,
                              color: Colors.orange,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Selecione um tamanho primeiro para ver as cores disponíveis',
                                style: TextStyle(
                                  color: Colors.orange.shade700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _coresDisponiveis.entries.map((entry) {
                          final cor = entry.key;
                          final qtd = entry.value;
                          final isSelected = _corSelecionada == cor;
                          final hasStock = qtd > 0;
                          final corVisual = catalogColorFromName(cor);
                          final isLight = corVisual.computeLuminance() > 0.5;

                          return InkWell(
                            onTap: hasStock
                                ? () {
                                    setState(() {
                                      _corSelecionada = cor;
                                      _extraSelecionado = null;
                                    });
                                    widget.onCatalogVariacaoExtraChanged
                                        ?.call(null);
                                    final s = widget.initialExtraValor?.trim();
                                    _pendingSeedExtra =
                                        (s != null && s.isNotEmpty) ? s : null;
                                    _scheduleTryConsumeSeedExtra();
                                  }
                                : null,
                            borderRadius: BorderRadius.circular(10),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: !hasStock
                                    ? Colors.grey.withOpacity(0.1)
                                    : isSelected
                                        ? theme.colorScheme.primary
                                        : Colors.white.withOpacity(0.05),
                                border: Border.all(
                                  color: !hasStock
                                      ? Colors.grey.withOpacity(0.3)
                                      : isSelected
                                          ? theme.colorScheme.primary
                                          : Colors.white
                                              .withOpacity(0.2),
                                  width: isSelected ? 2 : 1,
                                ),
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: theme.colorScheme.primary
                                              .withOpacity(0.3),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: corVisual,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isLight
                                            ? Colors.grey.shade400
                                            : Colors.white
                                                .withOpacity(0.3),
                                        width: 2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black
                                              .withOpacity(0.2),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: !hasStock
                                        ? Icon(
                                            Icons.close,
                                            size: 14,
                                            color: isLight
                                                ? Colors.black54
                                                : Colors.white54,
                                          )
                                        : isSelected
                                            ? Icon(
                                                Icons.check,
                                                size: 14,
                                                color: isLight
                                                    ? Colors.black
                                                    : Colors.white,
                                              )
                                            : null,
                                  ),
                                  const SizedBox(width: 10),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        cor,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: !hasStock
                                              ? Colors.grey
                                              : isSelected
                                                  ? Colors.white
                                                  : theme.textTheme.bodyLarge
                                                      ?.color,
                                        ),
                                      ),
                                      Text(
                                        hasStock ? (widget.mostrarQuantidadeNoCatalogo ? '$qtd un.' : 'Disponível') : 'Esgotado',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: !hasStock
                                              ? Colors.grey
                                              : isSelected
                                                  ? Colors.white
                                                      .withOpacity(0.8)
                                                  : Colors.grey[500],
                                        ),
                                      ),
                                      if (_tamanhoSelecionado != null &&
                                          widget.precoPorTamanho != null &&
                                          widget.precoPorTamanho!.containsKey(_tamanhoSelecionado)) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          'R\$ ${_fmt2(widget.precoPorTamanho![_tamanhoSelecionado]!)}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: !hasStock
                                                ? Colors.grey
                                                : isSelected
                                                    ? Colors.white
                                                    : theme.colorScheme.primary,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                  if (_opcoesExtra.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Icon(
                          Icons.category_outlined,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _labelEixoExtra,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (_extraSelecionado != null &&
                            _extraSelecionado!.trim().isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary
                                  .withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _extraSelecionado!,
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    VariacaoExtrasCollapsible(
                      options: _opcoesExtra,
                      selectedValue: _extraSelecionado,
                      onOptionChosen: (op) {
                        setState(() => _extraSelecionado = op);
                        widget.onCatalogVariacaoExtraChanged?.call(op);
                      },
                      itemBuilder: (context, op, _) {
                        final isSelected = _extraSelecionado == op;
                        return InkWell(
                          onTap: () {
                            setState(() => _extraSelecionado = op);
                            widget.onCatalogVariacaoExtraChanged?.call(op);
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : Colors.white.withOpacity(0.05),
                              border: Border.all(
                                color: isSelected
                                    ? theme.colorScheme.primary
                                    : Colors.white.withOpacity(0.2),
                                width: isSelected ? 2 : 1,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              op,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? Colors.white
                                    : theme.textTheme.bodyLarge?.color,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 28),
                  if (_tamanhoSelecionado != null ||
                      _corSelecionada != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary
                            .withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: theme.colorScheme.primary
                              .withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_circle,
                            color: theme.colorScheme.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              [
                                if (_tamanhoSelecionado != null)
                                  'Tamanho: $_tamanhoSelecionado',
                                if (_corSelecionada != null)
                                  'Cor: $_corSelecionada',
                                if (_extraSelecionado != null &&
                                    _extraSelecionado!.trim().isNotEmpty)
                                  ProdutoVariacaoExtra.textoResumoExtra(
                                    extraTipo: _extraTipoParaOpcao(
                                        _extraSelecionado!),
                                    extraValor: _extraSelecionado!,
                                  ),
                              ].where((s) => s.isNotEmpty).join(' | '),
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _podeAdicionar
                            ? theme.colorScheme.primary
                            : Colors.grey.shade600,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: _podeAdicionar ? 4 : 0,
                        shadowColor: theme.colorScheme.primary
                            .withOpacity(0.4),
                      ),
                      onPressed: _podeAdicionar
                          ? () {
                              final ex = (_extraSelecionado ?? '').trim();
                              final tipo = ex.isNotEmpty
                                  ? _extraTipoParaOpcao(ex)
                                  : '';
                              widget.onAddToCart(
                                _tamanhoSelecionado,
                                _corSelecionada,
                                _precoAtual,
                                ex,
                                tipo,
                              );
                            }
                          : null,
                      icon: Icon(
                        _podeAdicionar
                            ? Icons.shopping_cart_checkout
                            : Icons.touch_app,
                        size: 22,
                      ),
                      label: Text(
                        _textoButton,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
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

