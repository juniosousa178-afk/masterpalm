// lib/screens/nova_venda_modal.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/combo_configuravel_resumo.dart';
import '../core/dart_error_unwrap.dart';
import '../core/nova_venda_pos_save_ui_policy.dart';
import '../core/logger.dart';
import '../core/nova_venda_line_identity.dart';
import '../core/access_scope_service.dart';
import '../core/produto_cadastro_gate.dart';
import '../core/produto_variacao_extra.dart';
import '../core/strict_product_resolution.dart';
import '../core/venda_finalizacao_reentrada_guard.dart';
import '../core/pdv_sale_intent_lifecycle.dart';
import '../core/venda_metrics_filter.dart';
import 'package:hive/hive.dart';

import '../models/cliente.dart';
import '../models/produto.dart';
import '../models/venda.dart';
import '../models/venda_item.dart';
import '../services/venda_combo_estoque_expansion.dart';
import '../services/vendas_service.dart';
import '../services/limits_guard.dart';
import 'dart:async';
import 'dart:math';
import '../services/campanhas_sorteio_service.dart';
import '../utils/moeda_input_formatter.dart';
import '../utils/text_utils.dart';
import 'barcode_scanner_screen.dart';
import '../widgets/moeda_text_field.dart';
import 'nova_venda/variacao_selection_sheet.dart';
import 'nova_venda/combo_variacao_selection_sheet.dart';
import 'nova_venda/finalizar_confirmacao_dialog.dart';
import 'public_catalog/widgets/catalog_combo_configurable_sheet.dart';
import 'produto_form_screen.dart';

import 'package:flutter_fortune_wheel/flutter_fortune_wheel.dart';

class NovaVendaModal extends StatefulWidget {
  final Box<Produto> produtosBox;
  final Box<Cliente> clientesBox;
  final Box<Venda> vendasBox;
  final String vendedor;
  final String lojaId; // 🔹 loja atual (vem da VendasScreen)
  final VoidCallback onVendaFinalizada;

  /// Chamado se o salvamento falhar depois do modal fechar (venda já confirmada pelo usuário).
  final void Function(String message)? onErroAoFinalizar;

  /// Quando informado, abre em modo edição (atualização in-place via [VendasService.editarVendaMulti]).
  final Venda? vendaParaEditar;

  /// Prefill do Catálogo Interno (mesma shape de `produtosSelecionados`).
  /// Ignorado quando [vendaParaEditar] está definido.
  final List<Map<String, dynamic>>? itensIniciais;
  final String? observacaoInicial;
  final double? descontoPctInicial;

  const NovaVendaModal({
    super.key,
    required this.produtosBox,
    required this.clientesBox,
    required this.vendasBox,
    required this.vendedor,
    required this.lojaId,
    required this.onVendaFinalizada,
    this.onErroAoFinalizar,
    this.vendaParaEditar,
    this.itensIniciais,
    this.observacaoInicial,
    this.descontoPctInicial,
  });

  @override
  State<NovaVendaModal> createState() => _NovaVendaModalState();
}

class _NovaVendaModalState extends State<NovaVendaModal> {
  // 🔹 Roleta da sorte (configurável) - só aparece quando roleta ativa no config (separada da campanha)
  bool _roletaAtiva = false;
  double valorMinimoRoleta = 150.0;
  double descontoRoletaValor = 0.0;
  bool roletaPremioAplicado = false;
  Map<String, dynamic>? premioRoleta;

  // Prêmios carregados do Firebase (ou padrão)
  List<Map<String, dynamic>> _premiosRoleta = [];
  final List<Map<String, dynamic>> _premiosRoletaDefault = [
    {'label': '5% OFF', 'tipo': 'percent', 'valor': 5.0},
    {'label': '10% OFF', 'tipo': 'percent', 'valor': 10.0},
    {'label': 'R\$ 20 OFF', 'tipo': 'valor', 'valor': 20.0},
    {'label': 'Frete Grátis', 'tipo': 'frete', 'valor': 0.0},
    {'label': 'Brinde Surpresa', 'tipo': 'brinde', 'valor': 0.0},
    {'label': 'Tente Novamente', 'tipo': 'nenhum', 'valor': 0.0},
  ];

  final _formKey = GlobalKey<FormState>();
  final clienteController = TextEditingController();
  late final TextEditingController freteController;
  late final TextEditingController descontoController;
  final observacaoController = TextEditingController();
  final List<TextEditingController> _valorControllers = [];
  final List<TextEditingController> _quantityControllers = [];

  double frete = 0.0;
  double desconto = 0.0;

  /// false = valor do campo em %; true = valor do campo em R$.
  bool _descontoEmReais = false;

  /// pagamentos: {'forma': 'Pix'|'Dinheiro'|'Cartão', 'valor': double}
  List<Map<String, dynamic>> pagamentos = [
    {'forma': 'Pix', 'valor': 0.0},
  ];

  /// Quando true, a próxima finalização será registrada como venda fiada (conta a receber).
  bool _pendenteFiado = false;
  int _pendenteDiasVencimento = 30;
  int _pendenteQtdParcelasFiado = 1;
  int _pendenteIntervaloParcelasDias = 30;

  final _finalizacaoReentradaGuard = VendaFinalizacaoReentradaGuard();
  final _pdvSaleIntentLifecycle = PdvSaleIntentLifecycle();
  AccessScopeIdentity? _scope;

  @visibleForTesting
  PdvSaleIntentLifecycle get debugPdvSaleIntentLifecycle =>
      _pdvSaleIntentLifecycle;

  /// produtos: produto, preço, qtd, tamanho, cor, extraValor (técnico), variacaoExtraResumo (exibição)
  List<Map<String, dynamic>> produtosSelecionados = [novaVendaEmptyLine()];

  /// lineIds já removidos nesta sessão — impede double tap de apagar a linha seguinte.
  final Set<String> _linhasVendaJaRemovidas = <String>{};

  late String lojaId;

  bool get _modoEdicao => widget.vendaParaEditar != null;

  @override
  void initState() {
    super.initState();
    lojaId = widget.lojaId;
    AccessScopeService.loadIdentity().then((id) {
      if (mounted) setState(() => _scope = id);
    });
    freteController = TextEditingController();
    descontoController = TextEditingController();
    _valorControllers.add(TextEditingController());

    // Prefill síncrono: edição e catálogo interno no 1º frame, para o
    // Autocomplete não montar com initialValue vazio e reusar Key de índice.
    if (widget.vendaParaEditar != null) {
      _carregarVendaParaEdicao(widget.vendaParaEditar!, notify: false);
    } else {
      final pref = _normalizeItensIniciais(widget.itensIniciais);
      if (pref != null) {
        produtosSelecionados = pref;
        final obs = widget.observacaoInicial?.trim();
        if (obs != null && obs.isNotEmpty) {
          observacaoController.text = obs;
        }
        final desc = widget.descontoPctInicial;
        if (desc != null && desc > 0) {
          desconto = desc;
          _descontoEmReais = false;
          descontoController.text = _formatPercentualCampo(desc);
        }
      }
      ensureNovaVendaLineIds(produtosSelecionados);
      for (final item in produtosSelecionados) {
        final q = item['quantidade'] ?? 1;
        _quantityControllers.add(
          TextEditingController(
            text: (q is int ? q : int.tryParse(q.toString()) ?? 1).toString(),
          ),
        );
      }
    }

    _carregarConfigRoleta();
  }

  /// Normaliza maps do catálogo interno — descarta linhas sem nome de produto.
  static List<Map<String, dynamic>>? _normalizeItensIniciais(
    List<Map<String, dynamic>>? raw,
  ) {
    if (raw == null || raw.isEmpty) return null;
    final out = raw
        .map((m) => Map<String, dynamic>.from(m))
        .where((m) => (m['produto']?.toString() ?? '').trim().isNotEmpty)
        .toList();
    return out.isEmpty ? null : out;
  }

  void _carregarVendaParaEdicao(Venda v, {bool notify = true}) {
    clienteController.text = v.clienteNome;
    observacaoController.text = v.observacao;
    frete = v.frete;
    desconto = v.desconto;
    _descontoEmReais = false;
    freteController.text = MoedaInputFormatter.format(v.frete);
    descontoController.text = v.desconto > 0
        ? _formatPercentualCampo(v.desconto)
        : '';

    if (v.itens != null && v.itens!.isNotEmpty) {
      produtosSelecionados = v.itens!
          .map(
            (i) => {
              'produto': i.produtoNome,
              'preco': i.precoUnitario,
              'quantidade': i.quantidade,
              'tamanho': i.tamanho,
              'cor': i.cor,
              'extraValor': i.extraValor,
              'variacaoExtraResumo': i.variacaoExtraResumo,
              if (i.productId != null && i.productId!.trim().isNotEmpty)
                'productId': i.productId,
            },
          )
          .toList();
    } else {
      // Parsing defensivo para vendas legadas (sem itens)
      String nomeProd = '';
      int qtdLegado = v.quantidade;
      double precoLegado = v.preco;
      try {
        final linhas = v.produtosDescricao.split('\n');
        final linha = linhas.isNotEmpty ? linhas.first.trim() : '';
        if (linha.isEmpty) {
          nomeProd = 'Produto';
        } else {
          nomeProd = linha;
          final idxX = linha.indexOf(' x ');
          if (idxX >= 0) {
            final rest = linha.substring(idxX + 3);
            final idxDelim = rest.indexOf(' - R\$');
            nomeProd = idxDelim >= 0
                ? rest.substring(0, idxDelim).trim()
                : rest.trim();
            final qtdStr = linha.substring(0, idxX).trim();
            qtdLegado = int.tryParse(qtdStr) ?? v.quantidade;
          }
        }
      } catch (_) {
        nomeProd = v.produtosDescricao.trim().isNotEmpty
            ? v.produtosDescricao.split('\n').first.trim()
            : 'Produto';
      }
      produtosSelecionados = [
        {
          'produto': nomeProd,
          'preco': precoLegado,
          'quantidade': qtdLegado < 1 ? 1 : qtdLegado,
          'tamanho': v.tamanho,
          'cor': '',
          'extraValor': '',
          'variacaoExtraResumo': '',
        },
      ];
    }

    pagamentos = [];
    if (v.pagamentoDinheiro > 0) {
      pagamentos.add({'forma': 'Dinheiro', 'valor': v.pagamentoDinheiro});
    }
    if (v.pagamentoPix > 0) {
      pagamentos.add({'forma': 'Pix', 'valor': v.pagamentoPix});
    }
    if (v.pagamentoCartao > 0) {
      pagamentos.add({'forma': 'Cartão', 'valor': v.pagamentoCartao});
    }
    if (pagamentos.isEmpty) pagamentos.add({'forma': 'Pix', 'valor': v.total});

    for (final c in _valorControllers) {
      c.dispose();
    }
    _valorControllers.clear();
    for (final p in pagamentos) {
      final val = (p['valor'] as num?)?.toDouble() ?? 0.0;
      _valorControllers.add(
        TextEditingController(text: MoedaInputFormatter.format(val)),
      );
    }
    for (final c in _quantityControllers) {
      c.dispose();
    }
    _quantityControllers.clear();
    ensureNovaVendaLineIds(produtosSelecionados);
    for (final item in produtosSelecionados) {
      final q = item['quantidade'] ?? 1;
      _quantityControllers.add(
        TextEditingController(
          text: (q is int ? q : int.tryParse(q.toString()) ?? 1).toString(),
        ),
      );
    }

    if (notify && mounted) setState(() {});
  }

  Future<void> _carregarConfigRoleta() async {
    try {
      // Usa config/roleta_sorte (mesmo que catálogo e tela de config) - separada da campanha
      final doc = await FirebaseFirestore.instance
          .collection('lojas')
          .doc(lojaId)
          .collection('config')
          .doc('roleta_sorte')
          .get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final vm = (data['valorMinimo'] as num?)?.toDouble() ?? 150.0;
        final premiosRaw = (data['premios'] as List?) ?? [];
        final roletaAtiva = data['ativa'] == true;

        setState(() {
          _roletaAtiva = roletaAtiva;
          valorMinimoRoleta = vm;
          _premiosRoleta = premiosRaw
              .where((p) => (p['ativo'] ?? true) == true)
              .map<Map<String, dynamic>>((p) {
                return {
                  'label': p['label'] ?? '',
                  'tipo': p['tipo'] ?? 'percent',
                  'valor': (p['valor'] as num?)?.toDouble() ?? 0.0,
                };
              })
              .toList();

          if (_premiosRoleta.isEmpty) {
            _premiosRoleta = List<Map<String, dynamic>>.from(
              _premiosRoletaDefault,
            );
          }
        });
      } else {
        setState(() {
          _roletaAtiva = false;
          valorMinimoRoleta = 150.0;
          _premiosRoleta = List<Map<String, dynamic>>.from(
            _premiosRoletaDefault,
          );
        });
      }
    } catch (e) {
      logD('⚠️ [ROLETA] Erro ao carregar config (type=${e.runtimeType})');
      setState(() {
        _roletaAtiva = false;
        valorMinimoRoleta = 150.0;
        _premiosRoleta = List<Map<String, dynamic>>.from(_premiosRoletaDefault);
      });
    }
  }

  @override
  void dispose() {
    clienteController.dispose();
    freteController.dispose();
    descontoController.dispose();
    observacaoController.dispose();
    for (final c in _valorControllers) {
      c.dispose();
    }
    for (final c in _quantityControllers) {
      c.dispose();
    }
    super.dispose();
  }

  /// Botões . e , para web (Safari iOS não mostra no teclado).

  double _somarPagamentos() {
    return pagamentos.fold(0.0, (acc, p) {
      final v = p['valor'];
      if (v is num) return acc + v.toDouble();
      return acc + (double.tryParse(v?.toString() ?? '') ?? 0.0);
    });
  }

  static double _parsePercentualBrasil(String raw) {
    final s = raw.trim().replaceAll(',', '.');
    if (s.isEmpty) return 0.0;
    return double.tryParse(s) ?? 0.0;
  }

  static String _formatPercentualCampo(double p) {
    if (p <= 0) return '';
    if ((p * 100).round() % 100 == 0) return p.round().toString();
    return p.toStringAsFixed(2).replaceAll('.', ',');
  }

  /// Valor do desconto em R$ (limitado ao subtotal), conforme tipo do campo.
  double _descontoValorAplicadoSobreSubtotal(double subtotal) {
    if (subtotal <= 0) return 0;
    if (_descontoEmReais) {
      return desconto.clamp(0.0, subtotal);
    }
    final v = subtotal * (desconto / 100);
    return v.clamp(0.0, subtotal);
  }

  void _onTrocarTipoDesconto(bool paraReais) {
    if (paraReais == _descontoEmReais) return;
    final subtotal = _calcularSubtotal();
    setState(() {
      if (paraReais) {
        final pct = desconto;
        desconto = subtotal > 0
            ? (subtotal * (pct / 100)).clamp(0.0, subtotal)
            : 0.0;
        descontoController.text = desconto > 0
            ? MoedaInputFormatter.format(desconto)
            : '';
      } else {
        final reais = desconto.clamp(0.0, subtotal > 0 ? subtotal : 0.0);
        desconto = subtotal > 0
            ? ((reais / subtotal) * 100).clamp(0.0, 100.0)
            : 0.0;
        descontoController.text = _formatPercentualCampo(desconto);
      }
      _descontoEmReais = paraReais;
    });
  }

  double _calcularTotalSemRoleta() {
    final subtotal = _calcularSubtotal();
    final descontoAplicado = _descontoValorAplicadoSobreSubtotal(subtotal);
    return subtotal - descontoAplicado + frete;
  }

  double _calcularSubtotal() {
    double subtotal = 0.0;

    for (var item in produtosSelecionados) {
      final preco = (item['preco'] ?? 0.0) as double;
      final qtd = (item['quantidade'] ?? 1) as int;
      subtotal += preco * qtd;
    }

    return subtotal;
  }

  /// [VendasService] espera %. Para desconto em R$, envia o % equivalente ao valor aplicado.
  double _descontoPctEquivalenteParaSalvar() {
    final subtotal = _calcularSubtotal();
    if (subtotal <= 0) return 0;
    final d = _descontoValorAplicadoSobreSubtotal(subtotal);
    return (d / subtotal) * 100;
  }

  double _calcularTotal() {
    final semRoleta = _calcularTotalSemRoleta();
    final total = semRoleta - descontoRoletaValor;
    return total < 0 ? 0.0 : total;
  }

  double _precoDoProduto(Produto p) => p.precoFinal > 0
      ? p.precoFinal
      : (p.precoUnitario > 0 ? p.precoUnitario : 0.0);

  double _precoDoProdutoComVariacao(Produto p, String tamanho) {
    final preco = p.precoParaVariacao(tamanho);
    return preco > 0 ? preco : _precoDoProduto(p);
  }

  /// Combo já configurado na linha — preservar [preco] definido pelo sheet (não repor pelo cadastro).
  bool _linhaComboProtegida(Map<String, dynamic> item) {
    final sel = item['itensComboComSelecao'];
    if (sel is List && sel.isNotEmpty) return true;
    if ((item['comboConfiguravelResumo'] ?? '').toString().trim().isNotEmpty) {
      return true;
    }
    return false;
  }

  Map<String, dynamic> _produtoParaCatalogMap(Produto p) {
    return <String, dynamic>{
      'id': p.idFirebase,
      'produtosId': p.idFirebase,
      'nome': p.nome,
      'slug': p.slug,
      'preco': _precoDoProduto(p),
      'precoFinal': p.precoFinal,
      'percentualDescontoPix': p.percentualDescontoPix,
      'divideSemJuros': p.divideSemJuros,
      'maxParcelasSemJuros': p.maxParcelasSemJuros,
      'peso': p.peso,
      'tipoEmbalagem': p.tipoEmbalagem,
      if (p.imagens.isNotEmpty) 'imagens': List<String>.from(p.imagens),
      if (p.variacoes != null && p.variacoes!.isNotEmpty)
        'variacoes': p.variacoes,
      if (p.variacoesExtraTipo != null && p.variacoesExtraTipo!.isNotEmpty)
        'variacoesExtraTipo': p.variacoesExtraTipo,
      if (p.precoPorTamanho != null && p.precoPorTamanho!.isNotEmpty)
        'precoPorTamanho': p.precoPorTamanho,
      if (p.estoquePorTamanho.isNotEmpty)
        'estoquePorTamanho': p.estoquePorTamanho,
      if (p.cores.isNotEmpty)
        'estoquePorCor': {
          for (final c in p.cores) c: p.obterEstoqueVariacao('', c, ''),
        },
      if (p.itensCombo != null && p.itensCombo!.isNotEmpty)
        'itensCombo': p.itensCombo,
      if (p.comboConfig != null && p.comboConfig!.isNotEmpty)
        'comboConfig': p.comboConfig,
    };
  }

  List<Map<String, dynamic>> _catalogProductsDaLoja() {
    return widget.produtosBox.values
        .where((p) => p.lojaId == lojaId)
        .map(_produtoParaCatalogMap)
        .toList();
  }

  Future<void> _abrirSeletorCombo({
    required int index,
    required Produto combo,
    required int quantidadeInicial,
    required double precoFallback,
  }) async {
    if (combo.temComboConfigEfetivo) {
      final comboMap = _produtoParaCatalogMap(combo);
      final todos = _catalogProductsDaLoja();
      Map<String, dynamic>? itemCapturado;
      await showCatalogComboVariationSheet(
        context: context,
        comboProduct: comboMap,
        todosProdutos: todos,
        showAfterAddChoiceDialog: false,
        onAdd: (item) {
          itemCapturado = Map<String, dynamic>.from(item);
          return true;
        },
        onAfterSilentAddWhenAdded: () {},
      );
      if (!mounted || itemCapturado == null) return;
      final item = itemCapturado!;
      final selecao = (item['itensComboComSelecao'] is List)
          ? List<Map<String, dynamic>>.from(
              (item['itensComboComSelecao'] as List).whereType<Map>().map(
                (e) => Map<String, dynamic>.from(
                  e.map((k, v) => MapEntry(k.toString(), v)),
                ),
              ),
            )
          : const <Map<String, dynamic>>[];
      setState(() {
        produtosSelecionados[index]['produto'] = combo.nome;
        produtosSelecionados[index]['productId'] =
            combo.idFirebase.trim().isNotEmpty ? combo.idFirebase : null;
        produtosSelecionados[index]['preco'] =
            (item['preco'] as num?)?.toDouble() ?? precoFallback;
        produtosSelecionados[index]['quantidade'] =
            (item['quantidade'] as num?)?.toInt() ?? quantidadeInicial;
        produtosSelecionados[index]['tamanho'] = '';
        produtosSelecionados[index]['cor'] = '';
        produtosSelecionados[index]['extraValor'] = '';
        produtosSelecionados[index]['variacaoExtraResumo'] = '';
        if ((item['comboConfiguravelResumo'] ?? '')
            .toString()
            .trim()
            .isNotEmpty) {
          produtosSelecionados[index]['comboConfiguravelResumo'] =
              (item['comboConfiguravelResumo'] ?? '').toString().trim();
        } else {
          produtosSelecionados[index].remove('comboConfiguravelResumo');
        }
        produtosSelecionados[index]['itensComboComSelecao'] = selecao;
      });
      return;
    }

    await ComboVariacaoSelectionSheet.show(
      context,
      combo: combo,
      quantidade: quantidadeInicial,
      preco: precoFallback,
      produtosBox: widget.produtosBox,
      lojaId: lojaId,
      onConfirmar: (selecao, qtd, preco) {
        setState(() {
          produtosSelecionados[index]['produto'] = combo.nome;
          produtosSelecionados[index]['productId'] =
              combo.idFirebase.trim().isNotEmpty ? combo.idFirebase : null;
          produtosSelecionados[index]['preco'] = preco;
          produtosSelecionados[index]['quantidade'] = qtd;
          produtosSelecionados[index]['tamanho'] = '';
          produtosSelecionados[index]['cor'] = '';
          produtosSelecionados[index]['extraValor'] = '';
          produtosSelecionados[index]['variacaoExtraResumo'] = '';
          produtosSelecionados[index].remove('comboConfiguravelResumo');
          produtosSelecionados[index]['itensComboComSelecao'] = selecao;
        });
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 🔹 BUSCAR CLIENTE PELO NOME (RESTRINGINDO POR LOJA)
  // ---------------------------------------------------------------------------
  Cliente? _buscarClientePorNome(String nome) {
    final lower = nome.trim().toLowerCase();
    for (final c in widget.clientesBox.values) {
      if (c.lojaId == lojaId && c.nome.trim().toLowerCase() == lower) {
        return c;
      }
    }
    return null;
  }

  /// Últimas vendas do cliente — só as do escopo (vendedor: próprias).
  List<Venda> _ultimasVendasCliente(String nomeCliente) {
    if (nomeCliente.trim().isEmpty) return [];
    final lower = nomeCliente.trim().toLowerCase();
    final scope = _scope;
    return widget.vendasBox.values.where((v) {
      if (!(v.lojaId == lojaId || v.lojaId == null)) return false;
      if (v.clienteNome.trim().toLowerCase() != lower) return false;
      if (scope != null && !AccessScopeService.canSeeHistory(scope, v)) {
        return false;
      }
      return true;
    }).toList()..sort((a, b) => b.data.compareTo(a.data));
  }

  /// Produtos mais vendidos (para sugerir no topo)
  List<String> _produtosMaisVendidos({int limit = 5}) {
    final contagem = <String, int>{};
    for (final v in widget.vendasBox.values) {
      if (!incluirVendaEmMetricas(v)) continue;
      if (v.lojaId != null && v.lojaId != lojaId) continue;
      if (v.itens != null && v.itens!.isNotEmpty) {
        for (final item in v.itens!) {
          contagem[item.produtoNome] =
              (contagem[item.produtoNome] ?? 0) + item.quantidade;
        }
      } else if (v.produtosDescricao.isNotEmpty) {
        final nome = v.produtosDescricao.split('\n').first.trim();
        if (nome.isNotEmpty) {
          contagem[nome] = (contagem[nome] ?? 0) + v.quantidade;
        }
      }
    }
    final ordenados = contagem.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ordenados.take(limit).map((e) => e.key).toList();
  }

  void _preencherComTotal() {
    final total = _calcularTotal();
    if (pagamentos.isEmpty) return;
    pagamentos[0]['valor'] = total;
    if (_valorControllers.isNotEmpty) {
      _valorControllers[0].text = MoedaInputFormatter.format(total);
      _valorControllers[0].selection = TextSelection.collapsed(
        offset: _valorControllers[0].text.length,
      );
    }
    setState(() {});
  }

  Widget _buildVariacaoChip({
    required int index,
    required Map<String, dynamic> item,
    required List<Produto> produtosDaLoja,
  }) {
    final nome = (item['produto'] ?? '').toString().trim();
    if (nome.isEmpty) return const SizedBox.shrink();

    final prod = produtosDaLoja.firstWhereOrNull(
      (p) => p.lojaId == lojaId && p.nome.toLowerCase() == nome.toLowerCase(),
    );
    final ehCombo = prod != null && prod.ehCombo;
    final temVariacao =
        prod != null &&
        (prod.usaVariacoes ||
            prod.estoquePorTamanho.isNotEmpty ||
            prod.temVariacaoSoloCor);
    final tam = (item['tamanho'] ?? '').toString();
    final cor = (item['cor'] ?? '').toString();
    final extraResumo = (item['variacaoExtraResumo'] ?? '').toString().trim();
    final sel = item['itensComboComSelecao'];
    final temComboSelecao = sel is List && sel.isNotEmpty;
    final temSelecao =
        tam.isNotEmpty ||
        cor.isNotEmpty ||
        extraResumo.isNotEmpty ||
        temComboSelecao;

    if (!ehCombo && !temVariacao) {
      return const SizedBox.shrink();
    }

    String label;
    IconData icon;
    if (ehCombo) {
      label = temComboSelecao ? 'Combo configurado' : 'Configurar combo';
      icon = Icons.card_giftcard;
    } else {
      if (temSelecao) {
        label = [
          if (tam.isNotEmpty) tam,
          if (cor.isNotEmpty) cor,
          if (extraResumo.isNotEmpty) extraResumo,
        ].join(' / ');
      } else {
        if (prod.temVariacaoTamanhoECor) {
          label = 'Selecionar tamanho e cor';
        } else if (prod.temVariacaoSoloCor) {
          label = 'Selecionar cor';
        } else {
          label = 'Selecionar tamanho';
        }
      }
      icon = Icons.tune;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          if (ehCombo) {
            await _abrirSeletorCombo(
              index: index,
              combo: prod,
              quantidadeInicial: (item['quantidade'] ?? 1) as int,
              precoFallback: (item['preco'] ?? 0.0) as double,
            );
          } else if (temVariacao) {
            await NovaVendaVariacaoSheet.show(
              context,
              produto: prod,
              preco: _precoDoProduto(prod),
              onConfirmar: (t, c, qtd, extraEv, extraResumo) {
                setState(() {
                  final precoLinha = _precoDoProdutoComVariacao(prod, t);
                  produtosSelecionados[index]['tamanho'] = t;
                  produtosSelecionados[index]['cor'] = c;
                  produtosSelecionados[index]['preco'] = precoLinha;
                  produtosSelecionados[index]['quantidade'] = qtd;
                  produtosSelecionados[index]['extraValor'] = extraEv;
                  produtosSelecionados[index]['variacaoExtraResumo'] =
                      extraResumo;
                  produtosSelecionados[index].remove('itensComboComSelecao');
                  produtosSelecionados[index].remove('comboConfiguravelResumo');
                });
              },
            );
          }
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: ehCombo ? Colors.orange.shade50 : Colors.blue.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: ehCombo ? Colors.orange.shade200 : Colors.blue.shade200,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: ehCombo ? Colors.orange.shade700 : Colors.blue.shade700,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: ehCombo
                      ? Colors.orange.shade900
                      : Colors.blue.shade900,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _obterEstoqueProduto(
    Produto p,
    String tamanho,
    String cor, [
    String extra = '',
  ]) {
    final ex = extra.trim();
    if (p.temVariacaoSoloCor && cor.isNotEmpty) {
      return p.obterEstoqueVariacao('', cor, ex);
    }
    if (p.usaVariacoes && (tamanho.isNotEmpty || cor.isNotEmpty)) {
      final tamKey = tamanho.isEmpty ? '' : tamanho;
      final corKey = cor.isEmpty ? 'sem-cor' : cor;
      return p.obterEstoqueVariacao(tamKey, corKey, ex);
    }
    if (p.estoquePorTamanho.isNotEmpty && tamanho.isNotEmpty) {
      return p.estoquePorTamanho[tamanho] ?? 0;
    }
    return p.quantidade;
  }

  void _duplicarUltimaVenda(Venda venda) {
    clienteController.text = venda.clienteNome;
    if (venda.itens != null && venda.itens!.isNotEmpty) {
      setState(() {
        produtosSelecionados = venda.itens!
            .map(
              (i) => {
                'produto': i.produtoNome,
                'preco': i.precoUnitario,
                'quantidade': i.quantidade,
                'tamanho': i.tamanho,
                'cor': i.cor,
                'extraValor': i.extraValor,
                'variacaoExtraResumo': i.variacaoExtraResumo,
                if (i.productId != null && i.productId!.trim().isNotEmpty)
                  'productId': i.productId,
              },
            )
            .toList();
        ensureNovaVendaLineIds(produtosSelecionados);
        frete = venda.frete;
        desconto = venda.desconto;
        _descontoEmReais = false;
        freteController.text = MoedaInputFormatter.format(venda.frete);
        descontoController.text = venda.desconto > 0
            ? _formatPercentualCampo(venda.desconto)
            : '';
        if (pagamentos.isNotEmpty) {
          pagamentos[0]['valor'] = venda.total;
          if (_valorControllers.isNotEmpty) {
            _valorControllers[0].text = MoedaInputFormatter.format(venda.total);
          }
        }
        for (final c in _quantityControllers) {
          c.dispose();
        }
        _quantityControllers.clear();
        for (final item in produtosSelecionados) {
          final q = item['quantidade'] ?? 1;
          _quantityControllers.add(
            TextEditingController(
              text: (q is int ? q : int.tryParse(q.toString()) ?? 1).toString(),
            ),
          );
        }
      });
    } else {
      setState(() {
        produtosSelecionados = [
          {
            'produto': venda.produtosDescricao.split('\n').first.trim(),
            'preco': venda.preco,
            'quantidade': venda.quantidade,
            'tamanho': venda.tamanho,
            'cor': '',
            'extraValor': '',
            'variacaoExtraResumo': '',
          },
        ];
        ensureNovaVendaLineIds(produtosSelecionados);
        frete = venda.frete;
        desconto = venda.desconto;
        _descontoEmReais = false;
        freteController.text = MoedaInputFormatter.format(venda.frete);
        descontoController.text = venda.desconto > 0
            ? _formatPercentualCampo(venda.desconto)
            : '';
        if (pagamentos.isNotEmpty) {
          pagamentos[0]['valor'] = venda.total;
          if (_valorControllers.isNotEmpty) {
            _valorControllers[0].text = MoedaInputFormatter.format(venda.total);
          }
        }
        for (final c in _quantityControllers) {
          c.dispose();
        }
        _quantityControllers.clear();
        for (final item in produtosSelecionados) {
          final q = item['quantidade'] ?? 1;
          _quantityControllers.add(
            TextEditingController(
              text: (q is int ? q : int.tryParse(q.toString()) ?? 1).toString(),
            ),
          );
        }
      });
    }
  }

  // ---------------------------------------------------------------------------
  // 🔹 ROLETA DA SORTE – aplica prêmio no total da venda + registra no Firebase
  // ---------------------------------------------------------------------------
  void _aplicarPremioRoleta(Map<String, dynamic> premio) {
    final tipo = (premio['tipo'] ?? 'nenhum').toString();
    final valor = (premio['valor'] as num?)?.toDouble() ?? 0.0;

    // total ANTES de aplicar o prêmio
    final totalAntes = _calcularTotalSemRoleta();

    setState(() {
      premioRoleta = premio;
      roletaPremioAplicado = true;

      if (tipo == 'percent') {
        final sub = _calcularSubtotal();
        if (_descontoEmReais) {
          desconto += sub * (valor / 100);
          if (sub > 0) desconto = desconto.clamp(0.0, sub);
          descontoController.text = desconto > 0
              ? MoedaInputFormatter.format(desconto)
              : '';
        } else {
          desconto += valor;
        }
      } else if (tipo == 'valor') {
        // desconto em R$ direto no total (campo separado)
        descontoRoletaValor += valor;
      } else if (tipo == 'frete') {
        frete = 0.0;
      } else if (tipo == 'brinde') {
        // apenas registro simbólico; você pode usar isso na observação depois
      } else {
        // nenhum prêmio
      }
    });

    // total DEPOIS de aplicar o prêmio
    final totalDepois = _calcularTotal();

    // 🔹 Log no Firebase (roleta_vendas)
    CampanhasSorteioService.registrarResultadoRoleta(
      lojaId: lojaId,
      premioLabel: (premio['label'] ?? '').toString(),
      premioTipo: tipo,
      premioValor: valor,
      valorCompraAntes: totalAntes,
      valorCompraDepois: totalDepois,
      clienteNome: clienteController.text.trim().isEmpty
          ? null
          : clienteController.text.trim(),
    );
  }

  Future<void> _abrirRoleta() async {
    final totalSemRoleta = _calcularTotalSemRoleta();
    if (totalSemRoleta < valorMinimoRoleta) {
      await _mostrarErro(
        'A roleta só está disponível para compras a partir de '
        'R\$ ${valorMinimoRoleta.toStringAsFixed(2)}.',
      );
      return;
    }

    if (_premiosRoleta.isEmpty) {
      await _mostrarErro(
        'Nenhum prêmio configurado para a roleta. Configure na tela de campanhas.',
      );
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RoletaPremiosDialog(
        premios: _premiosRoleta,
        onPremioSorteado: (premio) {
          _aplicarPremioRoleta(premio);
        },
      ),
    );
  }

  String? _extrairPathFirestore(String texto) {
    final m = RegExp(
      r'lojas\/[^\s,)]+',
      caseSensitive: false,
    ).firstMatch(texto);
    return m?.group(0);
  }

  String _detalharErroSalvarVenda(Object e) {
    final root = unwrapDartInteropError(e);
    final erroReal = formatDartErrorForUser(e);
    String? code;
    String? plugin;
    String? message;
    try {
      final dyn = root as dynamic;
      code = dyn.code?.toString();
      plugin = dyn.plugin?.toString();
      message = dyn.message?.toString();
    } catch (_) {}

    if (root is FirebaseException) {
      code ??= root.code;
      plugin ??= root.plugin;
      message ??= root.message;
    }

    final path = _extrairPathFirestore('$erroReal ${message ?? ''}');
    final extra = <String>[
      if (plugin != null && plugin.isNotEmpty) 'plugin=$plugin',
      if (code != null && code.isNotEmpty) 'code=$code',
      if (path != null && path.isNotEmpty) 'path=$path',
    ].join(' | ');

    if ((code ?? '').toLowerCase() == 'not-found') {
      return 'Firestore not-found${extra.isNotEmpty ? ' ($extra)' : ''}';
    }
    if (extra.isNotEmpty) return '$erroReal ($extra)';
    return erroReal;
  }

  void _logErroSalvarVenda({
    required String etapa,
    required Object erro,
    StackTrace? st,
    List<VendaItem>? itensVenda,
  }) {
    final detalhe = _detalharErroSalvarVenda(erro);
    final diag = dartErrorDiagMeta(erro);
    final itensDiag = _resumoItensVendaParaLog(itensVenda);
    logE(
      '❌ [VENDA][$etapa] $detalhe | diag=$diag${itensDiag.isEmpty ? '' : ' | itens=$itensDiag'}',
      error: unwrapDartInteropError(erro),
      st: st,
    );
  }

  /// Resumo seguro das linhas da venda (sem preço/cliente).
  String _resumoItensVendaParaLog(List<VendaItem>? itens) {
    if (itens == null || itens.isEmpty) return '';
    final parts = <String>[];
    for (var i = 0; i < itens.length && i < 8; i++) {
      final it = itens[i];
      parts.add(
        '#$i pid=${it.productId ?? '-'} q=${it.quantidade} '
        'tam=${it.tamanho.isEmpty ? '-' : it.tamanho} cor=${it.cor.isEmpty ? '-' : it.cor}',
      );
    }
    if (itens.length > 8) parts.add('…+${itens.length - 8}');
    return parts.join('; ');
  }

  Future<void> _mostrarErro(String mensagem) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        icon: Icon(Icons.error_outline, size: 48, color: Colors.red.shade700),
        title: const Text(
          'Erro ao salvar venda',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Text(mensagem, style: const TextStyle(fontSize: 16)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Dialog de sucesso bem visível ao finalizar venda.
  Future<void> _mostrarSucessoVenda() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        icon: Icon(Icons.check_circle, size: 64, color: Colors.green.shade600),
        title: const Text(
          'Venda salva com sucesso!',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        content: const Text(
          'A venda foi registrada e o estoque foi atualizado.',
          style: TextStyle(fontSize: 16),
          textAlign: TextAlign.center,
        ),
        actions: [
          Center(
            child: ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.check),
              label: const Text('OK'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Mostra dialog com número da sorte gerado pelo CampaignEngine.
  Future<void> _mostrarDialogNumeroSorte(
    String numeroSorte,
    String nomeClienteFinal,
  ) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Número da sorte gerado!',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cliente: $nomeClienteFinal',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 8),
            const Text('Número da sorte:', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 4),
            Center(
              child: Text(
                numeroSorte,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Guarde esse número. Ele será usado no sorteio da campanha.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 🔹 GARANTE CLIENTE: se não existir, abre cadastro rápido (nome/tel/email)
  // ---------------------------------------------------------------------------
  Future<Cliente?> _garantirCliente(String nome) async {
    final existente = _buscarClientePorNome(nome);
    if (existente != null) {
      // Garante que terá histórico vinculado à box de vendas
      // ignore: experimental_member_use
      existente.historico ??= HiveList(widget.vendasBox);
      await existente.save();
      return existente;
    }

    if (!mounted) return null;

    final nomeController = TextEditingController(text: nome.trim());
    final telefoneController = TextEditingController();
    final emailController = TextEditingController();

    final confirmar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Cadastrar novo cliente'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nomeController,
                  decoration: const InputDecoration(labelText: 'Nome *'),
                ),
                TextFormField(
                  controller: telefoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Telefone *'),
                ),
                TextFormField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'E-mail'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Salvar'),
            ),
          ],
        );
      },
    );

    if (confirmar != true) return null;

    final nomeFinal = nomeController.text.trim();
    final tel = telefoneController.text.trim();
    final email = emailController.text.trim();

    if (nomeFinal.isEmpty || tel.isEmpty) {
      if (!mounted) return null;
      await _mostrarErro('Nome e telefone são obrigatórios.');
      return null;
    }

    final novo = Cliente(
      nome: nomeFinal,
      telefone: tel,
      instagram: '',
      cep: '',
      cidade: '',
      lojaId: lojaId,
      historico: HiveList(widget.vendasBox), // ignore: experimental_member_use
    );

    if (email.isNotEmpty) {
      novo.email = email;
    }

    await widget.clientesBox.add(novo);
    return novo;
  }

  // ---------------------------------------------------------------------------
  // FINALIZAR VENDA
  // ---------------------------------------------------------------------------
  Future<void> _finalizarVenda() async {
    if (!_finalizacaoReentradaGuard.tentarIniciar()) return;
    if (mounted) setState(() {});
    try {
      // 🔹 Valida dados obrigatórios ANTES de abrir o dialog (evita bug ao voltar)
      final nomeClienteDigitado = clienteController.text.trim();
      if (nomeClienteDigitado.isEmpty) {
        await _mostrarErro('Informe o nome do cliente para finalizar a venda.');
        return;
      }

      final total = _calcularTotal();

      for (final item in produtosSelecionados) {
        final produtoNome = (item['produto'] ?? '').toString().trim();
        if (produtoNome.isNotEmpty) {
          final productId = (item['productId'] as String?)?.trim();
          if (productId == null || productId.isEmpty) {
            await _mostrarErro(
              'Produto não encontrado para o código informado.',
            );
            return;
          }
        }
      }

      final resumoProdutos = produtosSelecionados
          .where((p) => (p['produto'] ?? '').toString().trim().isNotEmpty)
          .map(
            (p) => {
              'produto': p['produto'],
              'quantidade': p['quantidade'] ?? 1,
              'preco': p['preco'] ?? 0.0,
            },
          )
          .toList();

      if (resumoProdutos.isEmpty) {
        await _mostrarErro('Adicione pelo menos um produto.');
        return;
      }

      final subtotal = _calcularSubtotal();
      final descontoValor = _descontoValorAplicadoSobreSubtotal(subtotal);

      // Sincroniza valores dos controllers com pagamentos e quantidades antes de abrir o dialog
      for (
        var i = 0;
        i < pagamentos.length && i < _valorControllers.length;
        i++
      ) {
        final v = MoedaInputFormatter.parse(_valorControllers[i].text);
        pagamentos[i]['valor'] = v;
      }
      for (
        var i = 0;
        i < produtosSelecionados.length && i < _quantityControllers.length;
        i++
      ) {
        final q = int.tryParse(_quantityControllers[i].text) ?? 1;
        produtosSelecionados[i]['quantidade'] = q < 1 ? 1 : q;
      }

      // Abre dialog de confirmação com pagamento split e troco
      // Passa pagamentos atuais para preservar Pix/Dinheiro/Cartão selecionado
      final result = await FinalizarVendaConfirmacaoDialog.show(
        context,
        total: total,
        resumoProdutos: resumoProdutos,
        frete: frete,
        desconto: descontoValor,
        initialPagamentos: pagamentos
            .map(
              (p) => {
                'forma': p['forma'],
                'valor': (p['valor'] as num?)?.toDouble() ?? 0.0,
              },
            )
            .toList(),
      );

      if (result == null || !mounted) return;

      if (result.isFiado) {
        _pendenteFiado = true;
        _pendenteDiasVencimento = result.diasVencimento;
        _pendenteQtdParcelasFiado = result.quantidadeParcelasFiado;
        _pendenteIntervaloParcelasDias = result.intervaloParcelasDias;
      } else {
        _pendenteFiado = false;
        _pendenteQtdParcelasFiado = 1;
        _pendenteIntervaloParcelasDias = 30;
      }

      // Atualiza pagamentos com o que veio do dialog
      pagamentos = result.pagamentos.map((p) {
        return {
          'forma': p['forma'],
          'valor': (p['valor'] as num?)?.toDouble() ?? 0.0,
        };
      }).toList();

      // Sincroniza controllers
      while (_valorControllers.length < pagamentos.length) {
        _valorControllers.add(TextEditingController());
      }
      for (var i = 0; i < pagamentos.length; i++) {
        final v = (pagamentos[i]['valor'] as num?)?.toDouble() ?? 0.0;
        pagamentos[i]['valor'] = v;
        if (i < _valorControllers.length) {
          _valorControllers[i].text = MoedaInputFormatter.format(v);
        }
      }

      // Mostra troco se houver
      if (result.trocoTotal > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Troco a dar: R\$ ${result.trocoTotal.toStringAsFixed(2).replaceAll('.', ',')}',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }

      await _executarFinalizacaoVenda();
    } finally {
      _finalizacaoReentradaGuard.liberar();
      if (mounted) setState(() {});
    }
  }

  void _sincronizarQuantidadesDosControllers() {
    for (
      var i = 0;
      i < produtosSelecionados.length && i < _quantityControllers.length;
      i++
    ) {
      final q = int.tryParse(_quantityControllers[i].text) ?? 1;
      produtosSelecionados[i]['quantidade'] = q < 1 ? 1 : q;
    }
  }

  /// Remove a linha escolhida pelo usuário (lineId / instância), não o primeiro
  /// productId nem um índice stale de double tap.
  void _removerLinhaVendaExata(Map<String, dynamic> item) {
    final lineId = novaVendaLineIdOf(item);
    if (lineId != null && _linhasVendaJaRemovidas.contains(lineId)) return;
    final idx = indexOfExactNovaVendaLine(
      produtosSelecionados,
      lineId: lineId,
      instance: item,
    );
    if (idx < 0) return;
    if (lineId != null) _linhasVendaJaRemovidas.add(lineId);
    setState(() {
      if (idx < _quantityControllers.length) {
        _quantityControllers[idx].dispose();
        _quantityControllers.removeAt(idx);
      }
      produtosSelecionados.removeAt(idx);
      if (produtosSelecionados.isEmpty) {
        produtosSelecionados.add(novaVendaEmptyLine());
        _quantityControllers.add(TextEditingController(text: '1'));
      }
    });
  }

  (List<VendaItem>, Map<int, List<Map<String, dynamic>>>?)
  _montarItensVendaAtual() {
    final itens = <VendaItem>[];
    final itensComboSelecaoPorIndice = <int, List<Map<String, dynamic>>>{};
    for (var i = 0; i < produtosSelecionados.length; i++) {
      final m = produtosSelecionados[i];
      final nome = (m['produto'] ?? '').toString().trim();
      if (nome.isEmpty) continue;
      final sel = m['itensComboComSelecao'];
      if (sel is List && sel.isNotEmpty) {
        final listaSegura = <Map<String, dynamic>>[];
        for (final e in sel) {
          if (e is Map) {
            try {
              listaSegura.add(Map<String, dynamic>.from(e));
            } catch (_) {
              logD('[VENDA] Item de combo ignorado (formato inválido)');
            }
          }
        }
        if (listaSegura.isNotEmpty) {
          itensComboSelecaoPorIndice[itens.length] = listaSegura;
        }
      }
      final productId = (m['productId'] as String?)?.trim();
      itens.add(
        VendaItem(
          produtoNome: nome,
          quantidade: (m['quantidade'] ?? 1) as int,
          precoUnitario: (m['preco'] ?? 0.0) as double,
          tamanho: (m['tamanho'] ?? '').toString(),
          cor: (m['cor'] ?? '').toString(),
          lojaId: lojaId,
          productId: productId != null && productId.isNotEmpty
              ? productId
              : null,
          variacaoExtraResumo: (m['variacaoExtraResumo'] ?? '').toString(),
          extraValor: (m['extraValor'] ?? '').toString(),
        ),
      );
    }
    return (
      itens,
      itensComboSelecaoPorIndice.isEmpty ? null : itensComboSelecaoPorIndice,
    );
  }

  Produto _resolverProdutoLinhaVenda({
    required String nome,
    String? productId,
  }) {
    Produto byId = Produto.vazio();
    final pid = (productId ?? '').trim();
    if (pid.isNotEmpty) {
      try {
        byId = widget.produtosBox.values.firstWhere(
          (p) =>
              p.lojaId == lojaId &&
              (p.idFirebase == pid || p.key?.toString() == pid),
          orElse: () => Produto.vazio(),
        );
      } catch (_) {}
    }
    final byName = widget.produtosBox.values.firstWhere(
      (p) =>
          p.lojaId == lojaId &&
          p.nome.trim().toLowerCase() == nome.trim().toLowerCase(),
      orElse: () => Produto.vazio(),
    );
    final byIdKey = byId.key?.toString() ?? '';
    final byNameKey = byName.key?.toString() ?? '';
    final choice = decideProdutoLinhaIdentity(
      hasIdCandidate: byId.nome.isNotEmpty,
      hasNameCandidate: byName.nome.isNotEmpty,
      idCandidateNameAgreesWithLine: !productIdIncoerenteComNomeExibido(
        nomeProdutoResolvido: byId.nome,
        nomeExibido: nome,
      ),
      idAndNameAreSameProduct:
          produtoLinhaStableIdsIguais(byId.idFirebase, byName.idFirebase) ||
          (byIdKey.isNotEmpty && byIdKey == byNameKey),
    );
    switch (choice) {
      case ProdutoLinhaIdentityChoice.useIdCandidate:
        return byId;
      case ProdutoLinhaIdentityChoice.useNameCandidate:
        return byName;
      case ProdutoLinhaIdentityChoice.notFound:
        return Produto.vazio();
    }
  }

  /// Retorna `false` se o usuário cancelou ou foi redirecionado (não continuar finalização).
  Future<bool> _validarEstoqueLinhaVenda({
    required Produto prod,
    required String nome,
    required int qtdExigida,
    required String tamanho,
    required String cor,
    required String extraValor,
    int? indiceRemoverNaLista,
    String? lineIdRemover,
    bool validarDisponibilidade = true,
  }) async {
    if (prod.ehCombo) {
      return true;
    }

    if (prod.temVariacaoSoloCor && cor.isEmpty) {
      await _mostrarErro('Informe a cor para o produto "$nome".');
      return false;
    }
    if (prod.temVariacaoTamanhoECor && (tamanho.isEmpty || cor.isEmpty)) {
      await _mostrarErro('Informe tamanho e cor para o produto "$nome".');
      return false;
    }
    if (prod.exigeSelecaoTamanhoNaVenda && tamanho.isEmpty) {
      await _mostrarErro('Informe o tamanho para o produto "$nome".');
      return false;
    }

    final opcoesExtra = ProdutoVariacaoExtra.opcoesExtraPara(
      prod.variacoes,
      tamanho,
      cor,
    );
    if (opcoesExtra.isNotEmpty && extraValor.isEmpty) {
      await _mostrarErro(
        'Selecione a personalização (letra, estampa, etc.) para o produto "$nome".',
      );
      return false;
    }

    if (!validarDisponibilidade) return true;

    int disponivel;
    String msgEstoque = '';

    if (prod.temVariacaoSoloCor && cor.isNotEmpty) {
      disponivel = prod.obterEstoqueVariacao('', cor, extraValor);
      msgEstoque = 'cor $cor';
    } else if (prod.usaVariacoes && (tamanho.isNotEmpty || cor.isNotEmpty)) {
      final tamKey = tamanho.isEmpty ? '' : tamanho;
      final corKey = cor.isEmpty ? 'sem-cor' : cor;
      disponivel = prod.obterEstoqueVariacao(tamKey, corKey, extraValor);
      msgEstoque = tamanho.isNotEmpty
          ? 'tamanho $tamanho${cor.isEmpty ? '' : ' - cor $cor'}'
          : 'cor $cor';
    } else if (prod.estoquePorTamanho.isNotEmpty && tamanho.isNotEmpty) {
      disponivel = prod.estoquePorTamanho[tamanho] ?? 0;
      msgEstoque = 'tamanho $tamanho';
    } else {
      disponivel = prod.quantidade;
      msgEstoque = '';
    }

    if (disponivel >= qtdExigida) return true;

    final msg = msgEstoque.isNotEmpty
        ? 'Estoque insuficiente para "$nome" no $msgEstoque. Disponível: $disponivel.'
        : 'Estoque insuficiente para "$nome". Disponível: $disponivel.';

    if (!mounted) return false;
    final scope = await AccessScopeService.loadIdentity();
    if (!mounted) return false;
    final isSeller = scope.isSeller;
    final acao = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Produto com estoque zerado'),
        content: Text(
          isSeller
              ? '$msg\n\nEste produto não está disponível para venda.'
              : '$msg\n\nO que deseja fazer?',
        ),
        actions: [
          if (indiceRemoverNaLista != null ||
              (lineIdRemover != null && lineIdRemover.trim().isNotEmpty))
            TextButton(
              onPressed: () => Navigator.pop(context, 'remover'),
              child: const Text('Remover da venda'),
            ),
          if (!isSeller)
            ElevatedButton(
              onPressed: () => Navigator.pop(context, 'atualizar'),
              child: const Text('Ir para o produto'),
            )
          else
            TextButton(
              onPressed: () => Navigator.pop(context, 'ok'),
              child: const Text('OK'),
            ),
        ],
      ),
    );

    if (acao == 'remover' &&
        (lineIdRemover != null || indiceRemoverNaLista != null)) {
      final id = lineIdRemover?.trim();
      final idx = (id != null && id.isNotEmpty)
          ? indexOfExactNovaVendaLine(produtosSelecionados, lineId: id)
          : indiceRemoverNaLista;
      if (idx != null && idx >= 0 && idx < produtosSelecionados.length) {
        if (id != null && id.isNotEmpty) {
          if (_linhasVendaJaRemovidas.contains(id)) return false;
          _linhasVendaJaRemovidas.add(id);
        }
        if (idx < _quantityControllers.length) {
          _quantityControllers[idx].dispose();
          _quantityControllers.removeAt(idx);
        }
        produtosSelecionados.removeAt(idx);
      }
      if (produtosSelecionados.isEmpty) {
        produtosSelecionados.add(novaVendaEmptyLine());
        if (_quantityControllers.isEmpty) {
          _quantityControllers.add(TextEditingController(text: '1'));
        }
      }
      setState(() {});
      return false;
    }
    if (acao == 'atualizar' && !isSeller) {
      if (!mounted) return false;
      final allowed = await ensureProdutoCadastroAccess(context);
      if (!allowed || !mounted) return false;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProdutoFormScreen(produto: prod),
          settings: const RouteSettings(
            name: '/produto_editar',
            arguments: {'returnToVenda': true},
          ),
        ),
      );
    }
    return false;
  }

  Future<bool> _validarEstoquePreSalvamentoEdicaoVenda(
    Venda vendaOriginal,
  ) async {
    final montagem = _montarItensVendaAtual();
    if (montagem.$1.isEmpty) {
      await _mostrarErro('Adicione pelo menos um produto.');
      return false;
    }

    final pre = VendasService.resolverValidacaoEstoquePreSalvamentoEdicao(
      vendaOriginal: vendaOriginal,
      itensNovos: montagem.$1,
      produtosBox: widget.produtosBox,
      lojaId: lojaId,
      itensComboSelecaoPorIndice: montagem.$2,
    );

    if (pre.pularValidacaoEstoque) return true;

    for (final linha in pre.linhasValidarBaixa) {
      final nome = (linha['nome'] ?? '').toString().trim();
      final qtdDelta = (linha['quantidade'] as num?)?.toInt() ?? 0;
      if (nome.isEmpty || qtdDelta <= 0) continue;

      final prod = _resolverProdutoLinhaVenda(
        nome: nome,
        productId: (linha['productId'] ?? '').toString(),
      );
      if (prod.nome.isEmpty) {
        await _mostrarErro('Produto não encontrado no estoque: $nome');
        return false;
      }

      final ok = await _validarEstoqueLinhaVenda(
        prod: prod,
        nome: nome,
        qtdExigida: qtdDelta,
        tamanho: (linha['tamanho'] ?? '').toString().trim(),
        cor: (linha['cor'] ?? '').toString().trim(),
        extraValor: (linha['extraValor'] ?? '').toString().trim(),
      );
      if (!ok) return false;
    }
    return true;
  }

  Future<void> _executarFinalizacaoVenda() async {
    final total = _calcularTotal();
    final totalPago = _somarPagamentos();
    final nomeClienteDigitado = clienteController.text.trim();

    // 0) Nome do cliente obrigatório – venda nunca pode ser finalizada sem cliente
    if (nomeClienteDigitado.isEmpty) {
      await _mostrarErro('Informe o nome do cliente para finalizar a venda.');
      return;
    }

    // 1) Cliente: garante cadastro rápido se não existir
    Cliente? cliente = await _garantirCliente(nomeClienteDigitado);
    if (!mounted) return;
    if (cliente == null) {
      await _mostrarErro(
        'É necessário cadastrar o cliente para finalizar. '
        'Preencha nome e telefone no cadastro rápido.',
      );
      return;
    }

    if (_pendenteFiado) {
      if (cliente.nome.trim().isEmpty) {
        await _mostrarErro('Selecione um cliente para venda fiada.');
        return;
      }
      if (total <= 0) {
        await _mostrarErro('Informe o valor da venda fiada.');
        return;
      }
      if (totalPago > total + 0.01) {
        await _mostrarErro('Pagamento informado maior que o total da venda.');
        return;
      }
      final saldoFiado = VendasService.calcularSaldoFiado(
        total: total,
        totalPagoAgora: totalPago,
      );
      if (saldoFiado > 0.01 && _pendenteDiasVencimento < 1) {
        await _mostrarErro('Informe a data de vencimento para o saldo fiado.');
        return;
      }
    }

    // 2) Validação do valor pago (dispensada quando venda fiada)
    if (!_pendenteFiado && (totalPago - total).abs() > 0.01) {
      await _mostrarErro(
        'O valor pago (R\$ ${totalPago.toStringAsFixed(2)}) '
        'não bate com o total (R\$ ${total.toStringAsFixed(2)}).',
      );
      return;
    }

    // 3) Validação dos produtos (estoque + produto não cadastrado + tamanho + cor)
    _sincronizarQuantidadesDosControllers();

    final vendaRef = widget.vendaParaEditar;
    if (vendaRef != null) {
      for (var i = 0; i < produtosSelecionados.length; i++) {
        final item = produtosSelecionados[i];
        final nome = (item['produto'] ?? '').toString().trim();
        final qtd = (item['quantidade'] ?? 1) as int;
        final tamanho = (item['tamanho'] ?? '').toString().trim();
        final cor = (item['cor'] ?? '').toString().trim();
        final extraValor = (item['extraValor'] ?? '').toString().trim();

        if (nome.isEmpty || qtd <= 0) {
          await _mostrarErro('Preencha os produtos corretamente.');
          return;
        }

        final productId = (item['productId'] as String?)?.trim();
        final prod = _resolverProdutoLinhaVenda(
          nome: nome,
          productId: productId,
        );

        if (prod.nome.isEmpty) {
          if (!mounted) return;
          final irCadastro = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Produto não cadastrado'),
              content: Text(
                'O produto "$nome" não existe no estoque desta loja.\n\n'
                'Deseja cadastrar agora?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Cadastrar'),
                ),
              ],
            ),
          );

          if (irCadastro == true) {
            if (!mounted) return;
            await Navigator.of(context).pushNamed(
              '/estoque',
              arguments: {'nomeInicial': nome, 'lojaId': lojaId},
            );
          }
          return;
        }

        if (prod.ehCombo) {
          final sel = item['itensComboComSelecao'];
          if (sel is! List || sel.isEmpty) {
            await _mostrarErro(
              'Configure o combo "$nome" antes de finalizar. '
              'Toque em "Configurar combo" e confirme tamanho, cor e personalização de cada item do kit.',
            );
            return;
          }
          var selecaoValida = true;
          for (final e in sel) {
            if (e is! Map || e.isEmpty) {
              selecaoValida = false;
              break;
            }
          }
          if (!selecaoValida) {
            await _mostrarErro(
              'A configuração do combo "$nome" está incompleta. Abra "Configurar combo" e confirme novamente.',
            );
            return;
          }
        } else {
          final okEstrutura = await _validarEstoqueLinhaVenda(
            prod: prod,
            nome: nome,
            qtdExigida: qtd,
            tamanho: tamanho,
            cor: cor,
            extraValor: extraValor,
            validarDisponibilidade: false,
          );
          if (!okEstrutura) return;
        }
      }

      final okEdicao = await _validarEstoquePreSalvamentoEdicaoVenda(vendaRef);
      if (!okEdicao) return;
    } else {
      for (var i = 0; i < produtosSelecionados.length; i++) {
        final item = produtosSelecionados[i];
        final nome = (item['produto'] ?? '').toString().trim();
        final qtd = (item['quantidade'] ?? 1) as int;
        final tamanho = (item['tamanho'] ?? '').toString().trim();
        final cor = (item['cor'] ?? '').toString().trim();
        final extraValor = (item['extraValor'] ?? '').toString().trim();

        if (nome.isEmpty || qtd <= 0) {
          await _mostrarErro('Preencha os produtos corretamente.');
          return;
        }

        final productId = (item['productId'] as String?)?.trim();
        final prod = _resolverProdutoLinhaVenda(
          nome: nome,
          productId: productId,
        );

        // Se NÃO existir, oferece cadastro no Estoque
        if (prod.nome.isEmpty) {
          if (!mounted) return;
          final irCadastro = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Produto não cadastrado'),
              content: Text(
                'O produto "$nome" não existe no estoque desta loja.\n\n'
                'Deseja cadastrar agora?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Cadastrar'),
                ),
              ],
            ),
          );

          if (irCadastro == true) {
            if (!mounted) return;
            await Navigator.of(context).pushNamed(
              '/estoque',
              arguments: {'nomeInicial': nome, 'lojaId': lojaId},
            );
          }
          return;
        }

        if (prod.ehCombo) {
          final sel = item['itensComboComSelecao'];
          if (sel is! List || sel.isEmpty) {
            await _mostrarErro(
              'Configure o combo "$nome" antes de finalizar. '
              'Toque em "Configurar combo" e confirme tamanho, cor e personalização de cada item do kit.',
            );
            return;
          }
          var selecaoValida = true;
          for (final e in sel) {
            if (e is! Map || e.isEmpty) {
              selecaoValida = false;
              break;
            }
          }
          if (!selecaoValida) {
            await _mostrarErro(
              'A configuração do combo "$nome" está incompleta. Abra "Configurar combo" e confirme novamente.',
            );
            return;
          }
        } else {
          final okEstoque = await _validarEstoqueLinhaVenda(
            prod: prod,
            nome: nome,
            qtdExigida: qtd,
            tamanho: tamanho,
            cor: cor,
            extraValor: extraValor,
            indiceRemoverNaLista: i,
            lineIdRemover: novaVendaLineIdOf(item),
          );
          if (!okEstoque) return;
        }
      }
    }

    // 4) Monta os itens - usa controller.text para garantir valor real de cada linha
    try {
      final itens = <VendaItem>[];
      final itensComboSelecaoPorIndice = <int, List<Map<String, dynamic>>>{};
      for (var i = 0; i < produtosSelecionados.length; i++) {
        final m = produtosSelecionados[i];
        final nome = (m['produto'] ?? '').toString().trim();
        if (nome.isEmpty) continue;
        final sel = m['itensComboComSelecao'];
        if (sel is List && sel.isNotEmpty) {
          final listaSegura = <Map<String, dynamic>>[];
          for (final e in sel) {
            if (e is Map) {
              try {
                listaSegura.add(Map<String, dynamic>.from(e));
              } catch (_) {
                logD('[VENDA] Item de combo ignorado (formato inválido)');
              }
            }
          }
          if (listaSegura.isNotEmpty) {
            itensComboSelecaoPorIndice[itens.length] = listaSegura;
          }
        }
        final productId = (m['productId'] as String?)?.trim();
        itens.add(
          VendaItem(
            produtoNome: nome,
            quantidade: (m['quantidade'] ?? 1) as int,
            precoUnitario: (m['preco'] ?? 0.0) as double,
            tamanho: (m['tamanho'] ?? '').toString(),
            cor: (m['cor'] ?? '').toString(),
            lojaId: lojaId,
            productId: productId != null && productId.isNotEmpty
                ? productId
                : null,
            variacaoExtraResumo: (m['variacaoExtraResumo'] ?? '').toString(),
            extraValor: (m['extraValor'] ?? '').toString(),
          ),
        );
      }
      if (itens.isEmpty) {
        await _mostrarErro('Adicione pelo menos um produto.');
        return;
      }

      double valorPagamento(dynamic v) => (v is num)
          ? v.toDouble()
          : (double.tryParse(v?.toString() ?? '') ?? 0.0);

      double valorDinheiro = pagamentos
          .where((p) => (p['forma'] ?? '') == 'Dinheiro')
          .fold(0.0, (s, p) => s + valorPagamento(p['valor']));

      double valorPix = pagamentos
          .where((p) => (p['forma'] ?? '') == 'Pix')
          .fold(0.0, (s, p) => s + valorPagamento(p['valor']));

      double valorCartao = pagamentos
          .where((p) => (p['forma'] ?? '') == 'Cartão')
          .fold(0.0, (s, p) => s + valorPagamento(p['valor']));

      logD(
        '💰 [VENDA] Pagamentos - Dinheiro: R\$ ${valorDinheiro.toStringAsFixed(2)}, Pix: R\$ ${valorPix.toStringAsFixed(2)}, Cartão: R\$ ${valorCartao.toStringAsFixed(2)}',
      );

      // 🔹 Nome que será usado tanto na venda quanto no número da sorte (cliente não é null aqui)
      final nomeClienteFinal = cliente.nome.isNotEmpty
          ? cliente.nome
          : (nomeClienteDigitado.isEmpty
                ? 'Cliente'
                : capitalizeWords(nomeClienteDigitado.trim()));

      // Captura referências antes de qualquer await; não usar widget/context após pop.
      final onErro = widget.onErroAoFinalizar;
      final produtosBox = widget.produtosBox;
      final clientesBox = widget.clientesBox;
      final vendasBox = widget.vendasBox;
      final vendedor = widget.vendedor;
      final scope = await AccessScopeService.loadIdentity();
      final vendedorUid = scope.uid.isNotEmpty ? scope.uid : null;
      final vendedorNome = scope.displayName.isNotEmpty
          ? scope.displayName
          : (vendedor.trim().isNotEmpty && !vendedor.contains('@')
                ? vendedor.trim()
                : null);
      final vendedorEmail = scope.email.isNotEmpty
          ? scope.email
          : (vendedor.contains('@') ? vendedor.trim().toLowerCase() : null);
      final vendaParaEditarRef = widget.vendaParaEditar;
      final onVendaFinalizadaRef = widget.onVendaFinalizada;

      debugPrint('[H1-TRACE] stage=ui_before_salvar_venda_background');
      // R4.2 — libera UI no checkpoint local (Hive+Journal); sync/campanha em background.
      var uiReleasedEarly = false;
      void releaseUiEarly() {
        if (uiReleasedEarly) return;
        uiReleasedEarly = true;
        debugPrint('[M39-VENDA-PERF] stage=ui-success early=true');
        _pdvSaleIntentLifecycle.clearOnSuccess();
        if (!mounted) {
          onErro?.call(
            'A venda pode ter sido concluída, mas a tela foi atualizada. '
            'Verifique o histórico de vendas.',
          );
          return;
        }
        unawaited(
          (() async {
            try {
              await _mostrarSucessoVenda();
              if (!mounted) return;
              onVendaFinalizadaRef();
              Navigator.of(context).pop(true);
            } catch (uiE, uiSt) {
              _logErroSalvarVenda(
                etapa: 'UI_POS_SUCCESS_EARLY',
                erro: uiE,
                st: uiSt,
              );
              if (mounted) {
                await _mostrarErro(
                  'A venda pode ter sido concluída, mas a tela foi atualizada. '
                  'Verifique o histórico de vendas.',
                );
              } else {
                onErro?.call(
                  'A venda pode ter sido concluída, mas a tela foi atualizada. '
                  'Verifique o histórico de vendas.',
                );
              }
            }
          })(),
        );
      }

      final (ok, numeroSorte, mensagemErro) = await _salvarVendaEmBackground(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        vendedor: vendedor,
        vendedorUid: vendedorUid,
        vendedorNome: vendedorNome,
        vendedorEmail: vendedorEmail,
        nomeClienteFinal: nomeClienteFinal,
        cliente: cliente,
        itens: itens,
        itensComboSelecaoPorIndice: itensComboSelecaoPorIndice.isEmpty
            ? null
            : itensComboSelecaoPorIndice,
        valorDinheiro: valorDinheiro,
        valorPix: valorPix,
        valorCartao: valorCartao,
        total: total,
        observacao: observacaoController.text.trim(),
        onErro: onErro,
        isFiado: _pendenteFiado,
        diasVencimentoFiado: _pendenteDiasVencimento,
        quantidadeParcelasFiado: _pendenteQtdParcelasFiado,
        intervaloParcelasDias: _pendenteIntervaloParcelasDias,
        vendaParaEditar: vendaParaEditarRef,
        saleIntentId: vendaParaEditarRef == null
            ? _pdvSaleIntentLifecycle.ensureForAttempt()
            : null,
        onLocalPersistUiReady: releaseUiEarly,
      );
      _pendenteFiado = false;
      debugPrint(
        '[H1-TRACE] stage=ui_after_salvar_venda_background '
        'ok=$ok mounted=$mounted early=$uiReleasedEarly '
        'hasMsg=${mensagemErro != null && mensagemErro.trim().isNotEmpty}',
      );

      if (uiReleasedEarly) {
        if (numeroSorte != null && numeroSorte.isNotEmpty && mounted) {
          unawaited(_mostrarDialogNumeroSorte(numeroSorte, nomeClienteFinal));
        }
        return;
      }

      final posSave = decideNovaVendaPosSaveUi(
        ok: ok,
        mensagemErro: mensagemErro,
        mounted: mounted,
      );
      switch (posSave.action) {
        case NovaVendaPosSaveUiAction.notifyParentError:
          debugPrint(
            '[H1-TRACE] stage=ui_notify_parent_error '
            'mounted=$mounted ok=$ok',
          );
          if (posSave.errorMessage != null) {
            onErro?.call(posSave.errorMessage!);
          }
          return;
        case NovaVendaPosSaveUiAction.showErrorDialog:
          await _mostrarErro(
            'A venda não foi salva.\n\n${posSave.errorMessage}',
          );
          return;
        case NovaVendaPosSaveUiAction.showSuccess:
          _pdvSaleIntentLifecycle.clearOnSuccess();
          if (mensagemErro != null &&
              VendaSalvaComPendenciaSyncException.isPendenciaMessage(
                mensagemErro,
              )) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(mensagemErro),
                  backgroundColor: Colors.orange.shade800,
                  duration: const Duration(seconds: 6),
                ),
              );
            }
          }
          if (numeroSorte != null && numeroSorte.isNotEmpty) {
            await _mostrarDialogNumeroSorte(numeroSorte, nomeClienteFinal);
          }
          if (!mounted) {
            debugPrint('[H1-TRACE] stage=ui_success_unmounted_after_sorte');
            onErro?.call(
              'A venda pode ter sido concluída, mas a tela foi atualizada. '
              'Verifique o histórico de vendas.',
            );
            return;
          }
          await _mostrarSucessoVenda();
          if (!mounted) return;
          onVendaFinalizadaRef();
          Navigator.of(context).pop(true);
      }
    } catch (e, stackTrace) {
      if (!mounted) return;
      _logErroSalvarVenda(etapa: 'UI_FINALIZAR', erro: e, st: stackTrace);
      await _mostrarErro(formatSalvarVendaErrorForUser(e));
    }
  }

  /// Executa guard, registrarVendaMulti e participação em campanha (CampaignEngine).
  /// Retorna (sucesso, numeroSorte?, mensagemErro?) — não usa widget/context.
  Future<(bool, String?, String?)> _salvarVendaEmBackground({
    required Box<Produto> produtosBox,
    required Box<Cliente> clientesBox,
    required Box<Venda> vendasBox,
    required String vendedor,
    String? vendedorUid,
    String? vendedorNome,
    String? vendedorEmail,
    required String nomeClienteFinal,
    required Cliente? cliente,
    required List<VendaItem> itens,
    Map<int, List<Map<String, dynamic>>>? itensComboSelecaoPorIndice,
    required double valorDinheiro,
    required double valorPix,
    required double valorCartao,
    required double total,
    required String observacao,
    void Function(String message)? onErro,
    bool isFiado = false,
    int diasVencimentoFiado = 30,
    int quantidadeParcelasFiado = 1,
    int intervaloParcelasDias = 30,
    Venda? vendaParaEditar,
    String? saleIntentId,
    void Function()? onLocalPersistUiReady,
  }) async {
    try {
      if (vendaParaEditar != null) {
        try {
          // Sucesso de edição = fronteira local (Hive + CR + stock se itens).
          // syncCliente/syncVenda são best-effort após o return do serviço.
          await VendasService.editarVendaMulti(
            vendaOriginal: vendaParaEditar,
            produtosBox: produtosBox,
            clientesBox: clientesBox,
            vendasBox: vendasBox,
            clienteNome: nomeClienteFinal,
            itens: itens,
            dinheiro: valorDinheiro,
            pix: valorPix,
            cartao: valorCartao,
            vendedor: vendedor,
            vendedorUid: vendedorUid,
            vendedorNome: vendedorNome,
            vendedorEmail: vendedorEmail,
            observacao: observacao,
            frete: frete,
            descontoPct: _descontoPctEquivalenteParaSalvar(),
            lojaId: lojaId,
            clienteExistente: cliente,
            onSyncError: (message) {
              if (!mounted) {
                debugPrint(
                  '[VENDA-EDICAO] sync remoto após fechar editor: $message',
                );
                return;
              }
              onErro?.call(message);
            },
            isFiado: isFiado,
            dataVencimentoFiado: isFiado
                ? DateTime.now().add(Duration(days: diasVencimentoFiado))
                : null,
            quantidadeParcelasFiado: quantidadeParcelasFiado,
            intervaloParcelasDias: intervaloParcelasDias,
            itensComboSelecaoPorIndice: itensComboSelecaoPorIndice,
          );
          return (true, null, null);
        } on VendaSalvaComPendenciaSyncException catch (e) {
          // Local sale+CR OK — aviso de sync; UI fecha como sucesso local.
          return (true, null, e.message);
        }
      }

      final guard = LimitsGuard();
      final limite = await guard.checkVendaLimit(lojaId);
      if (!limite.canAdd) {
        final msg = limite.userMessage();
        onErro?.call(msg);
        return (false, null, msg);
      }

      // ✅ ETAPA 1: Fluxo único de participação — apenas CampaignEngine (via VendasService).
      // Removido _registrarNumeroSorteio (SorteioNumeroService) para evitar duplicidade.
      String? numeroSorteRecebido;
      await VendasService.registrarVendaMulti(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: nomeClienteFinal,
        itens: itens,
        dinheiro: valorDinheiro,
        pix: valorPix,
        cartao: valorCartao,
        vendedor: vendedor,
        vendedorUid: vendedorUid,
        vendedorNome: vendedorNome,
        vendedorEmail: vendedorEmail,
        observacao: observacao,
        frete: frete,
        descontoPct: _descontoPctEquivalenteParaSalvar(),
        lojaId: lojaId,
        clienteExistente: cliente,
        onSyncError: onErro,
        isFiado: isFiado,
        dataVencimentoFiado: isFiado
            ? DateTime.now().add(Duration(days: diasVencimentoFiado))
            : null,
        quantidadeParcelasFiado: quantidadeParcelasFiado,
        intervaloParcelasDias: intervaloParcelasDias,
        itensComboSelecaoPorIndice: itensComboSelecaoPorIndice,
        onNumeroSorteGerado: (n) => numeroSorteRecebido = n,
        saleIntentId: saleIntentId,
        onLocalPersistUiReady: onLocalPersistUiReady,
      );

      return (true, numeroSorteRecebido, null);
    } on ArgumentError catch (e, stackTrace) {
      _logErroSalvarVenda(
        etapa: 'BACKGROUND_SAVE_FIADO',
        erro: e,
        st: stackTrace,
        itensVenda: itens,
      );
      final msg = e.message?.toString().trim().isNotEmpty == true
          ? e.message!.toString().trim()
          : e.toString();
      onErro?.call(msg);
      return (false, null, msg);
    } catch (e, stackTrace) {
      _logErroSalvarVenda(
        etapa: 'BACKGROUND_SAVE',
        erro: e,
        st: stackTrace,
        itensVenda: itens,
      );
      if (VendaComboEstoqueExpansion.isErroVariacaoObrigatoria(e)) {
        final msg = formatSalvarVendaErrorForUser(e);
        onErro?.call(msg);
        return (false, null, msg);
      }
      final msg = formatSalvarVendaErrorForUser(e);
      onErro?.call(msg);
      return (false, null, msg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _calcularTotal();
    final totalPago = _somarPagamentos();
    final troco = totalPago > total ? totalPago - total : 0.0;
    final falta = total > totalPago ? total - totalPago : 0.0;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Padding(
        padding: MediaQuery.of(context).viewInsets,
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height * 0.5,
              maxWidth: 500,
            ),
            child: Form(
              key: _formKey,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Handle bar
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Text(
                      _modoEdicao ? 'Editar venda' : 'Nova Venda',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                          ),
                    ),
                    const SizedBox(height: 20),

                    // Cliente (autocomplete) — pesquisa GLOBAL da loja (MULTI:
                    // vendedor também vê todos os clientes aqui para evitar
                    // cadastro duplicado; a carteira aplica-se só na lista CRM).
                    // Ao selecionar: não expor histórico/CRM de outros vendedores.
                    Autocomplete<Cliente>(
                      optionsBuilder: (textEditingValue) {
                        if (textEditingValue.text.isEmpty) {
                          return const Iterable<Cliente>.empty();
                        }
                        final lower = textEditingValue.text
                            .toLowerCase()
                            .trim();
                        return widget.clientesBox.values
                            .where((c) {
                              if (c.lojaId != lojaId) return false;
                              final blob = [
                                c.nome,
                                c.telefone,
                                c.cidade,
                                c.email ?? '',
                                c.endereco ?? '',
                                c.cep,
                              ].join(' ').toLowerCase();
                              return blob.contains(lower);
                            })
                            .take(20);
                      },
                      displayStringForOption: (c) => c.nome,
                      onSelected: (c) {
                        clienteController.text = c.nome;
                        setState(() {});
                      },
                      optionsViewBuilder: (context, onSelected, options) {
                        return Align(
                          alignment: Alignment.topLeft,
                          child: Material(
                            elevation: 4,
                            borderRadius: BorderRadius.circular(8),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 240),
                              child: ListView.builder(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                itemCount: options.length,
                                itemBuilder: (context, index) {
                                  final c = options.elementAt(index);
                                  final sub =
                                      AccessScopeService.customerSearchSubtitle(
                                        telefone: c.telefone,
                                        cidade: c.cidade,
                                        cpf: c.cep,
                                        endereco: c.endereco,
                                      );
                                  return ListTile(
                                    dense: true,
                                    title: Text(c.nome),
                                    subtitle: sub.isEmpty ? null : Text(sub),
                                    onTap: () => onSelected(c),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                      fieldViewBuilder:
                          (context, controller, focusNode, onSubmit) {
                            // Mantém sync com clienteController externo.
                            if (controller.text != clienteController.text &&
                                clienteController.text.isNotEmpty &&
                                controller.text.isEmpty) {
                              controller.text = clienteController.text;
                            }
                            return TextFormField(
                              controller: controller,
                              focusNode: focusNode,
                              decoration: InputDecoration(
                                labelText: 'Cliente',
                                hintText: 'Nome, telefone, cidade, CPF…',
                                filled: true,
                                fillColor: Colors.grey.shade50,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              onChanged: (v) {
                                clienteController.text = v;
                              },
                              onFieldSubmitted: (_) => onSubmit(),
                            );
                          },
                    ),

                    // Histórico rápido do cliente (oculto em modo edição)
                    Builder(
                      builder: (context) {
                        if (_modoEdicao) return const SizedBox.shrink();
                        final nomeCliente = clienteController.text.trim();
                        if (nomeCliente.isEmpty) return const SizedBox.shrink();
                        final vendasCliente = _ultimasVendasCliente(
                          nomeCliente,
                        );
                        if (vendasCliente.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        final ultima = vendasCliente.first;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.blue.shade100),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.history,
                                    size: 20,
                                    color: Colors.blue.shade700,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Última: R\$ ${ultima.total.toStringAsFixed(2)} ? ${ultima.data.day.toString().padLeft(2, '0')}/${ultima.data.month}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.blue.shade900,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: () => _duplicarUltimaVenda(ultima),
                              icon: const Icon(Icons.copy, size: 18),
                              label: const Text('Duplicar última venda'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.blue.shade700,
                                side: BorderSide(color: Colors.blue.shade300),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    Divider(height: 1, color: Colors.grey.shade200),

                    // Produtos
                    ...produtosSelecionados.asMap().entries.map((entry) {
                      final index = entry.key;
                      final item = entry.value;
                      final produtosDaLoja = widget.produtosBox.values
                          .where((p) => p.lojaId == lojaId)
                          .toList();
                      final valorAtual = (item['produto'] ?? '').toString();
                      final precoVal = (item['preco'] ?? 0.0) as num;
                      final precoStr =
                          'R\$ ${precoVal.toDouble().toStringAsFixed(2).replaceAll('.', ',')}';

                      return Container(
                        key: novaVendaLineWidgetKey(item, 'produto_row_'),
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _ProdutoDropdown(
                                    key: novaVendaLineWidgetKey(
                                      item,
                                      'dropdown_produto_',
                                    ),
                                    valorAtual: valorAtual,
                                    produtos: produtosDaLoja,
                                    lojaId: lojaId,
                                    produtosFavoritos: _produtosMaisVendidos(
                                      limit: 8,
                                    ),
                                    precoDoProduto: _precoDoProduto,
                                    onChanged: (nome, preco, productId) {
                                      setState(() {
                                        produtosSelecionados[index]['produto'] =
                                            nome;
                                        produtosSelecionados[index]['preco'] =
                                            preco;
                                        produtosSelecionados[index]['tamanho'] =
                                            '';
                                        produtosSelecionados[index]['cor'] = '';
                                        produtosSelecionados[index]['extraValor'] =
                                            '';
                                        produtosSelecionados[index]['variacaoExtraResumo'] =
                                            '';
                                        produtosSelecionados[index].remove(
                                          'itensComboComSelecao',
                                        );
                                        produtosSelecionados[index].remove(
                                          'comboConfiguravelResumo',
                                        );
                                        produtosSelecionados[index]['quantidade'] =
                                            1;
                                        if (productId != null &&
                                            productId.isNotEmpty) {
                                          produtosSelecionados[index]['productId'] =
                                              productId;
                                        } else {
                                          produtosSelecionados[index].remove(
                                            'productId',
                                          );
                                        }
                                      });
                                    },
                                    onProductIsCombo: (combo) async {
                                      await _abrirSeletorCombo(
                                        index: index,
                                        combo: combo,
                                        quantidadeInicial: 1,
                                        precoFallback: _precoDoProduto(combo),
                                      );
                                    },
                                    onProductNeedsVariation: (produto) async {
                                      await NovaVendaVariacaoSheet.show(
                                        context,
                                        produto: produto,
                                        preco: _precoDoProduto(produto),
                                        onConfirmar: (tam, cor, qtd, extraEv, extraResumo) {
                                          setState(() {
                                            final precoLinha =
                                                _precoDoProdutoComVariacao(
                                                  produto,
                                                  tam,
                                                );
                                            produtosSelecionados[index]['produto'] =
                                                produto.nome;
                                            produtosSelecionados[index]['productId'] =
                                                produto.idFirebase
                                                    .trim()
                                                    .isNotEmpty
                                                ? produto.idFirebase
                                                : null;
                                            produtosSelecionados[index]['preco'] =
                                                precoLinha;
                                            produtosSelecionados[index]['tamanho'] =
                                                tam;
                                            produtosSelecionados[index]['cor'] =
                                                cor;
                                            produtosSelecionados[index]['quantidade'] =
                                                qtd;
                                            produtosSelecionados[index]['extraValor'] =
                                                extraEv;
                                            produtosSelecionados[index]['variacaoExtraResumo'] =
                                                extraResumo;
                                            produtosSelecionados[index].remove(
                                              'itensComboComSelecao',
                                            );
                                            produtosSelecionados[index].remove(
                                              'comboConfiguravelResumo',
                                            );
                                          });
                                        },
                                      );
                                    },
                                    onTextChanged: (v) {
                                      setState(() {
                                        produtosSelecionados[index]['produto'] =
                                            v;
                                        final linha =
                                            produtosSelecionados[index];
                                        final pidAtual =
                                            (linha['productId'] as String?)
                                                ?.trim();
                                        if (pidAtual != null &&
                                            pidAtual.isNotEmpty) {
                                          final pPorId = produtosDaLoja
                                              .firstWhereOrNull(
                                                (x) =>
                                                    x.idFirebase.trim() ==
                                                    pidAtual,
                                              );
                                          if (pPorId != null &&
                                              productIdIncoerenteComNomeExibido(
                                                nomeProdutoResolvido:
                                                    pPorId.nome,
                                                nomeExibido: v,
                                              )) {
                                            linha.remove('productId');
                                          }
                                        }
                                        final trimmed = normalizeText(v);
                                        final p = produtosDaLoja
                                            .firstWhereOrNull(
                                              (x) =>
                                                  normalizeText(x.nome) ==
                                                      trimmed ||
                                                  (x.codigoBarras
                                                          .trim()
                                                          .isNotEmpty &&
                                                      normalizeText(
                                                            x.codigoBarras,
                                                          ) ==
                                                          trimmed),
                                            );
                                        if (_linhaComboProtegida(linha)) {
                                          if (p != null) {
                                            linha['productId'] =
                                                p.idFirebase.trim().isNotEmpty
                                                ? p.idFirebase
                                                : null;
                                          } else {
                                            linha.remove('productId');
                                          }
                                          return;
                                        }
                                        if (p != null) {
                                          linha['preco'] = _precoDoProduto(p);
                                          linha['productId'] =
                                              p.idFirebase.trim().isNotEmpty
                                              ? p.idFirebase
                                              : null;
                                          if (normalizeText(p.nome) !=
                                                  trimmed &&
                                              normalizeText(p.codigoBarras) ==
                                                  trimmed) {
                                            linha['produto'] = p.nome;
                                          }
                                        } else {
                                          linha.remove('productId');
                                          linha.remove('variationId');
                                          linha['preco'] = 0.0;
                                          linha['tamanho'] = '';
                                          linha['cor'] = '';
                                        }
                                      });
                                    },
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: 'Ler código de barras',
                                      icon: Icon(
                                        Icons.qr_code_scanner,
                                        color: Colors.grey[700],
                                      ),
                                      onPressed: () async {
                                        final messenger = ScaffoldMessenger.of(
                                          context,
                                        );
                                        final navigator = Navigator.of(context);
                                        final code =
                                            await BarcodeScannerScreen.scan(
                                              context,
                                            );
                                        if (code == null ||
                                            code.isEmpty ||
                                            !mounted) {
                                          return;
                                        }
                                        final prod = widget.produtosBox.values
                                            .firstWhereOrNull(
                                              (p) =>
                                                  p.lojaId == lojaId &&
                                                  p.codigoBarras.isNotEmpty &&
                                                  normalizeText(
                                                        p.codigoBarras,
                                                      ) ==
                                                      normalizeText(code),
                                            );
                                        if (prod == null) {
                                          if (!mounted) return;
                                          messenger.showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Nenhum produto encontrado com esse código de barras',
                                              ),
                                            ),
                                          );
                                          return;
                                        }
                                        if (prod.ehCombo) {
                                          await _abrirSeletorCombo(
                                            index: index,
                                            combo: prod,
                                            quantidadeInicial: 1,
                                            precoFallback: _precoDoProduto(
                                              prod,
                                            ),
                                          );
                                        } else if (prod.usaVariacoes ||
                                            prod.estoquePorTamanho.isNotEmpty) {
                                          await NovaVendaVariacaoSheet.show(
                                            navigator.context,
                                            produto: prod,
                                            preco: _precoDoProduto(prod),
                                            onConfirmar: (tam, cor, qtd, extraEv, extraResumo) {
                                              if (!mounted) return;
                                              setState(() {
                                                final precoLinha =
                                                    _precoDoProdutoComVariacao(
                                                      prod,
                                                      tam,
                                                    );
                                                produtosSelecionados[index]['produto'] =
                                                    prod.nome;
                                                produtosSelecionados[index]['productId'] =
                                                    prod.idFirebase
                                                        .trim()
                                                        .isNotEmpty
                                                    ? prod.idFirebase
                                                    : null;
                                                produtosSelecionados[index]['preco'] =
                                                    precoLinha;
                                                produtosSelecionados[index]['tamanho'] =
                                                    tam;
                                                produtosSelecionados[index]['cor'] =
                                                    cor;
                                                produtosSelecionados[index]['quantidade'] =
                                                    qtd;
                                                produtosSelecionados[index]['extraValor'] =
                                                    extraEv;
                                                produtosSelecionados[index]['variacaoExtraResumo'] =
                                                    extraResumo;
                                              });
                                            },
                                          );
                                        } else {
                                          setState(() {
                                            produtosSelecionados[index]['produto'] =
                                                prod.nome;
                                            produtosSelecionados[index]['productId'] =
                                                prod.idFirebase
                                                    .trim()
                                                    .isNotEmpty
                                                ? prod.idFirebase
                                                : null;
                                            produtosSelecionados[index]['preco'] =
                                                _precoDoProduto(prod);
                                            produtosSelecionados[index]['tamanho'] =
                                                '';
                                            produtosSelecionados[index]['cor'] =
                                                '';
                                            produtosSelecionados[index]['extraValor'] =
                                                '';
                                            produtosSelecionados[index]['variacaoExtraResumo'] =
                                                '';
                                          });
                                        }
                                      },
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        Icons.add_circle,
                                        color: Colors.green.shade600,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          produtosSelecionados.add(
                                            novaVendaEmptyLine(),
                                          );
                                          _quantityControllers.add(
                                            TextEditingController(text: '1'),
                                          );
                                        });
                                      },
                                    ),
                                    if (produtosSelecionados.length > 1)
                                      IconButton(
                                        icon: Icon(
                                          Icons.remove_circle_outline,
                                          color: Colors.red.shade400,
                                        ),
                                        onPressed: () =>
                                            _removerLinhaVendaExata(item),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                            Builder(
                              builder: (context) {
                                final comboTxt =
                                    ComboConfiguravelResumo.textoParaItemMap(
                                      Map<String, dynamic>.from(item),
                                    );
                                if (comboTxt.isEmpty) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(
                                    top: 6,
                                    bottom: 2,
                                  ),
                                  child: Text(
                                    comboTxt,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[800],
                                      height: 1.35,
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                SizedBox(
                                  width: 70,
                                  child: TextFormField(
                                    controller:
                                        index < _quantityControllers.length
                                        ? _quantityControllers[index]
                                        : null,
                                    key: novaVendaLineWidgetKey(item, 'qtd_'),
                                    initialValue:
                                        index < _quantityControllers.length
                                        ? null
                                        : (item['quantidade'] ?? 1).toString(),
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      labelText: 'Qtd',
                                      isDense: true,
                                      filled: true,
                                      fillColor: Colors.grey.shade50,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                    onChanged: (value) {
                                      setState(() {
                                        final qtd = int.tryParse(value) ?? 1;
                                        produtosSelecionados[index]['quantidade'] =
                                            qtd < 1 ? 1 : qtd;
                                      });
                                    },
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    precoStr,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                  ),
                                ),
                                _buildVariacaoChip(
                                  index: index,
                                  item: item,
                                  produtosDaLoja: produtosDaLoja,
                                ),
                                Builder(
                                  builder: (context) {
                                    final nomeProd = (item['produto'] ?? '')
                                        .toString()
                                        .trim();
                                    if (nomeProd.isEmpty) {
                                      return const SizedBox.shrink();
                                    }
                                    final prod = produtosDaLoja
                                        .firstWhereOrNull(
                                          (p) =>
                                              p.lojaId == lojaId &&
                                              p.nome.toLowerCase() ==
                                                  nomeProd.toLowerCase(),
                                        );
                                    if (prod == null) {
                                      return const SizedBox.shrink();
                                    }
                                    final tam = (item['tamanho'] ?? '')
                                        .toString();
                                    final cor = (item['cor'] ?? '').toString();
                                    final ex = (item['extraValor'] ?? '')
                                        .toString();
                                    final disp = _obterEstoqueProduto(
                                      prod,
                                      tam,
                                      cor,
                                      ex,
                                    );
                                    final isBaixo = disp < 3 && disp > 0;
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: disp == 0
                                            ? Colors.red.shade50
                                            : (isBaixo
                                                  ? Colors.orange.shade50
                                                  : Colors.grey.shade100),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'Est. $disp${isBaixo ? ' ⚠' : ''}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: disp == 0
                                              ? Colors.red.shade700
                                              : (isBaixo
                                                    ? Colors.orange.shade800
                                                    : Colors.grey.shade700),
                                          fontWeight: isBaixo
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),

                    // Frete e desconto
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: MoedaTextField(
                              controller: freteController,
                              labelText: 'Frete',
                              onChanged: (value) => frete = value,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Desconto',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Theme.of(
                                                context,
                                              ).hintColor,
                                            ),
                                      ),
                                    ),
                                    ChoiceChip(
                                      label: const Text('%'),
                                      labelPadding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      selected: !_descontoEmReais,
                                      onSelected: (_) =>
                                          _onTrocarTipoDesconto(false),
                                    ),
                                    const SizedBox(width: 4),
                                    ChoiceChip(
                                      label: const Text('R\$'),
                                      labelPadding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      selected: _descontoEmReais,
                                      onSelected: (_) =>
                                          _onTrocarTipoDesconto(true),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                if (_descontoEmReais)
                                  kIsWeb
                                      ? TextFormField(
                                          key: const ValueKey('desconto_reais'),
                                          controller: descontoController,
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [
                                            MoedaInputFormatter(),
                                          ],
                                          decoration: const InputDecoration(
                                            labelText: 'Valor do desconto',
                                            hintText: 'Ex: 10,00',
                                            border: OutlineInputBorder(),
                                          ),
                                          onChanged: (s) {
                                            desconto =
                                                MoedaInputFormatter.parse(s);
                                            setState(() {});
                                          },
                                        )
                                      : MoedaTextField(
                                          key: const ValueKey('desconto_reais'),
                                          controller: descontoController,
                                          labelText: 'Valor do desconto',
                                          hintText: 'Ex: 10,00',
                                          onChanged: (value) {
                                            desconto = value;
                                            setState(() {});
                                          },
                                        )
                                else
                                  TextFormField(
                                    key: const ValueKey('desconto_pct'),
                                    controller: descontoController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                        RegExp(r'[0-9.,]'),
                                      ),
                                    ],
                                    decoration: const InputDecoration(
                                      labelText: 'Percentual',
                                      hintText: 'Ex: 10',
                                      suffixText: '%',
                                    ),
                                    onChanged: (s) {
                                      desconto = _parsePercentualBrasil(s);
                                      setState(() {});
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Formas de pagamento
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Formas de Pagamento',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        ...pagamentos.asMap().entries.map((entry) {
                          final index = entry.key;
                          final item = entry.value;
                          while (_valorControllers.length < pagamentos.length) {
                            _valorControllers.add(TextEditingController());
                          }
                          final valorCtrl = _valorControllers[index];

                          return Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: DropdownButtonFormField<String>(
                                  value: item['forma'],
                                  items: const ['Pix', 'Dinheiro', 'Cartão']
                                      .map(
                                        (v) => DropdownMenuItem(
                                          value: v,
                                          child: Text(v),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) => setState(
                                    () => pagamentos[index]['forma'] = value,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: MoedaTextField(
                                  controller: valorCtrl,
                                  labelText: 'Valor',
                                  onChanged: (value) {
                                    pagamentos[index]['valor'] = value;
                                    setState(() {});
                                  },
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.remove_circle,
                                  color: Colors.red.shade400,
                                ),
                                onPressed: () {
                                  setState(() {
                                    if (index < _valorControllers.length) {
                                      _valorControllers[index].dispose();
                                      _valorControllers.removeAt(index);
                                    }
                                    pagamentos.removeAt(index);
                                  });
                                },
                              ),
                            ],
                          );
                        }),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton.icon(
                              icon: Icon(
                                Icons.add,
                                color: Colors.green.shade600,
                                size: 18,
                              ),
                              label: const Text('Adicionar forma'),
                              onPressed: () {
                                _valorControllers.add(TextEditingController());
                                setState(
                                  () => pagamentos.add({
                                    'forma': 'Pix',
                                    'valor': 0.0,
                                  }),
                                );
                              },
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.touch_app, size: 18),
                              label: const Text('Preencher total'),
                              onPressed: _preencherComTotal,
                            ),
                          ],
                        ),
                      ],
                    ),

                    // Observação
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: TextFormField(
                        controller: observacaoController,
                        decoration: InputDecoration(
                          labelText: 'Observação (opcional)',
                          hintText: 'Ex: Entregar na segunda-feira',
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        maxLines: 2,
                        minLines: 1,
                      ),
                    ),

                    // Troco / Falta
                    if (troco > 0)
                      Container(
                        margin: const EdgeInsets.only(top: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.money, color: Colors.green.shade700),
                            const SizedBox(width: 12),
                            Text(
                              'Troco: R\$ ${troco.toStringAsFixed(2).replaceAll('.', ',')}',
                              style: TextStyle(
                                color: Colors.green.shade800,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (falta > 0 && _pendenteFiado)
                      Container(
                        margin: const EdgeInsets.only(top: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.schedule, color: Colors.orange.shade800),
                            const SizedBox(width: 12),
                            Text(
                              'Saldo fiado: R\$ ${falta.toStringAsFixed(2).replaceAll('.', ',')}',
                              style: TextStyle(
                                color: Colors.orange.shade900,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (falta > 0)
                      Container(
                        margin: const EdgeInsets.only(top: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning, color: Colors.red.shade700),
                            const SizedBox(width: 12),
                            Text(
                              'Faltam: R\$ ${falta.toStringAsFixed(2).replaceAll('.', ',')}',
                              style: TextStyle(
                                color: Colors.red.shade800,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 16),

                    // Roleta da Sorte
                    Builder(
                      builder: (context) {
                        if (!_roletaAtiva) return const SizedBox.shrink();

                        final totalSemRoleta = _calcularTotalSemRoleta();
                        final habilitada = totalSemRoleta >= valorMinimoRoleta;

                        if (!habilitada) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Roleta disponível para compras acima de R\$ ${valorMinimoRoleta.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          );
                        }

                        return Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Card(
                            color: const Color(0xFF0B1120),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Text(
                                    'Roleta da Sorte 🎰',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Gire e ganhe descontos ou brindes!',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.8),
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: roletaPremioAplicado
                                          ? Colors.grey
                                          : const Color(0xFF6366F1),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    onPressed: roletaPremioAplicado
                                        ? null
                                        : _abrirRoleta,
                                    icon: const Icon(Icons.casino),
                                    label: Text(
                                      roletaPremioAplicado
                                          ? 'Prêmio já aplicado'
                                          : 'Girar roleta',
                                    ),
                                  ),
                                  if (premioRoleta != null) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'Prêmio: ${premioRoleta!['label'] ?? ''}',
                                      style: const TextStyle(
                                        color: Colors.amber,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 16),

                    // Total
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            'R\$ ${total.toStringAsFixed(2).replaceAll('.', ',')}',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Botões
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final temItens = produtosSelecionados.any(
                                (p) => (p['produto'] ?? '')
                                    .toString()
                                    .trim()
                                    .isNotEmpty,
                              );
                              if (temItens) {
                                if (!mounted) return;
                                final nav = Navigator.of(context);
                                final confirmar = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Descartar venda?'),
                                    content: const Text(
                                      'Há itens preenchidos. Deseja realmente cancelar e descartar esta venda?',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text('Continuar editando'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: const Text('Sim, descartar'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmar == true && mounted) nav.pop();
                              } else if (mounted) {
                                Navigator.pop(context);
                              }
                            },
                            icon: const Icon(Icons.close, size: 18),
                            label: const Text('Cancelar'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red.shade700,
                              side: BorderSide(color: Colors.red.shade300),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: _finalizacaoReentradaGuard.emAndamento
                                ? null
                                : _finalizarVenda,
                            icon: const Icon(Icons.check_circle, size: 20),
                            label: Text(
                              _modoEdicao
                                  ? 'Salvar alterações'
                                  : 'Finalizar venda',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade600,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// WIDGET: Diálogo da Roleta de Prêmios
// ===========================================================================
class RoletaPremiosDialog extends StatefulWidget {
  final List<Map<String, dynamic>> premios;
  final void Function(Map<String, dynamic> premio) onPremioSorteado;

  const RoletaPremiosDialog({
    super.key,
    required this.premios,
    required this.onPremioSorteado,
  });

  @override
  State<RoletaPremiosDialog> createState() => _RoletaPremiosDialogState();
}

class _RoletaPremiosDialogState extends State<RoletaPremiosDialog> {
  final StreamController<int> _controller = StreamController<int>.broadcast();
  bool _girando = false;
  Map<String, dynamic>? _premioFinal;

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  void _girar() {
    if (_girando) return;

    setState(() {
      _girando = true;
      _premioFinal = null;
    });

    final random = Random();
    final indexSorteado = random.nextInt(widget.premios.length);

    _controller.add(indexSorteado);

    Future.delayed(const Duration(seconds: 4), () {
      final premio = widget.premios[indexSorteado];
      setState(() {
        _girando = false;
        _premioFinal = premio;
      });
      widget.onPremioSorteado(premio);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF020617),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text(
        'Roleta da Sorte',
        style: TextStyle(color: Colors.white),
      ),
      content: SizedBox(
        height: 260,
        width: 260,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  FortuneWheel(
                    selected: _controller.stream,
                    animateFirst: false,
                    indicators: const <FortuneIndicator>[
                      FortuneIndicator(
                        alignment: Alignment.topCenter,
                        child: Icon(
                          Icons.arrow_drop_down,
                          size: 40,
                          color: Colors.white,
                        ),
                      ),
                    ],
                    items: [
                      for (final premio in widget.premios)
                        FortuneItem(
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Text(
                              premio['label']?.toString() ?? '',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF22C55E), Color(0xFF6366F1)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          blurRadius: 16,
                          spreadRadius: 2,
                          color: Colors.black.withOpacity(0.6),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'GIRE',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_premioFinal != null)
              Text(
                'Prêmio: ${_premioFinal!['label']}',
                style: const TextStyle(
                  color: Colors.amber,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _girando ? null : () => Navigator.pop(context),
          child: const Text('Fechar', style: TextStyle(color: Colors.white70)),
        ),
        ElevatedButton.icon(
          onPressed: _girando ? null : _girar,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF22C55E),
            foregroundColor: Colors.white,
          ),
          icon: const Icon(Icons.casino),
          label: Text(_girando ? 'Girando...' : 'Girar'),
        ),
      ],
    );
  }
}

/// Widget isolado para seleção de produto - cada instância tem estado próprio.
/// Se o produto for combo ou tiver variações, abre sheet de seleção; senão adiciona direto.
class _ProdutoDropdown extends StatelessWidget {
  final String valorAtual;
  final List<Produto> produtos;
  final String lojaId;
  final List<String> produtosFavoritos;
  final void Function(String nome, double preco, String? productId) onChanged;
  final Future<void> Function(Produto produto)? onProductNeedsVariation;
  final Future<void> Function(Produto combo)? onProductIsCombo;
  final void Function(String texto) onTextChanged;
  final double Function(Produto) precoDoProduto;

  const _ProdutoDropdown({
    super.key,
    required this.valorAtual,
    required this.produtos,
    required this.lojaId,
    this.produtosFavoritos = const [],
    required this.onChanged,
    this.onProductNeedsVariation,
    this.onProductIsCombo,
    required this.onTextChanged,
    required this.precoDoProduto,
  });

  @override
  Widget build(BuildContext context) {
    final todosNomes = produtos.map((p) => p.nome).toSet().toList();
    final codigoBarrasMap = <String, String>{};
    for (final p in produtos) {
      if (p.codigoBarras.trim().isNotEmpty) {
        codigoBarrasMap[p.codigoBarras.trim()] = p.nome;
      }
    }
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: valorAtual),
      optionsBuilder: (textEditingValue) {
        if (textEditingValue.text.isEmpty) {
          final favs = produtosFavoritos
              .where((n) => todosNomes.contains(n))
              .toList();
          final resto = todosNomes.where((n) => !favs.contains(n)).toList();
          return [...favs, ...resto];
        }
        final lower = normalizeText(textEditingValue.text);
        final filtrados = todosNomes
            .where((n) => normalizeText(n).contains(lower))
            .toList();
        final filtradosPorCodigo = codigoBarrasMap.entries
            .where((e) => normalizeText(e.key) == lower)
            .map((e) => e.value)
            .toList();
        final todosFiltrados = {...filtrados, ...filtradosPorCodigo}.toList();
        final favsFiltrados = produtosFavoritos
            .where((n) => todosFiltrados.contains(n))
            .toList();
        final restoFiltrados = todosFiltrados
            .where((n) => !favsFiltrados.contains(n))
            .toList();
        return [...favsFiltrados, ...restoFiltrados];
      },
      onSelected: (value) async {
        var p = produtos.firstWhereOrNull(
          (x) => x.lojaId == lojaId && x.nome == value,
        );
        p ??= produtos.firstWhereOrNull((x) => x.nome == value);
        if (p == null) return;

        if (p.ehCombo && onProductIsCombo != null) {
          await onProductIsCombo!(p);
        } else if ((p.usaVariacoes || p.estoquePorTamanho.isNotEmpty) &&
            onProductNeedsVariation != null) {
          await onProductNeedsVariation!(p);
        } else {
          onChanged(
            value,
            precoDoProduto(p),
            p.idFirebase.trim().isNotEmpty ? p.idFirebase.trim() : null,
          );
        }
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: 'Produto',
            hintText: 'Buscar ou selecionar',
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: (v) => onTextChanged(v),
          onFieldSubmitted: (_) => onSubmit(),
        );
      },
    );
  }
}
