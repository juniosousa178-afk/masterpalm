// lib/screens/nova_venda_modal.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../core/logger.dart';
import 'package:hive/hive.dart';

import '../models/cliente.dart';
import '../models/produto.dart';
import '../models/venda.dart';
import '../models/venda_item.dart';
import '../services/vendas_service.dart';
import '../services/limits_guard.dart';
import 'dart:async';
import 'dart:math';
import '../services/campanhas_sorteio_service.dart';
import '../services/sorteio_numero_service.dart';
import '../services/pos_pagamento_service.dart';
import '../utils/moeda_input_formatter.dart';
import '../utils/text_utils.dart';
import 'barcode_scanner_screen.dart';
import '../widgets/moeda_text_field.dart';
import 'nova_venda/variacao_selection_sheet.dart';
import 'nova_venda/combo_variacao_selection_sheet.dart';
import 'nova_venda/finalizar_confirmacao_dialog.dart';
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
  /// Quando informado, abre em modo edição: desfaz a venda antiga e registra nova com dados editados.
  final Venda? vendaParaEditar;

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

  /// pagamentos: {'forma': 'Pix'|'Dinheiro'|'Cartão', 'valor': double}
  List<Map<String, dynamic>> pagamentos = [
    {'forma': 'Pix', 'valor': 0.0},
  ];

  /// Quando true, a próxima finalização será registrada como venda fiada (conta a receber).
  bool _pendenteFiado = false;
  int _pendenteDiasVencimento = 30;

  /// produtos: {'produto': String, 'preco': double, 'quantidade': int, 'tamanho': String, 'cor': String}
  List<Map<String, dynamic>> produtosSelecionados = [
    {'produto': '', 'preco': 0.0, 'quantidade': 1, 'tamanho': '', 'cor': ''},
  ];

  late String lojaId;

  bool get _modoEdicao => widget.vendaParaEditar != null;

  @override
  void initState() {
    super.initState();
    lojaId = widget.lojaId;
    freteController = TextEditingController();
    descontoController = TextEditingController();
    _valorControllers.add(TextEditingController());
    _quantityControllers.add(TextEditingController(text: '1'));
    _carregarConfigRoleta();
    if (widget.vendaParaEditar != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.vendaParaEditar != null) {
          _carregarVendaParaEdicao(widget.vendaParaEditar!);
        }
      });
    }
  }

  void _carregarVendaParaEdicao(Venda v) {
    clienteController.text = v.clienteNome;
    observacaoController.text = v.observacao;
    frete = v.frete;
    desconto = v.desconto;
    freteController.text = MoedaInputFormatter.format(v.frete);
    descontoController.text = MoedaInputFormatter.format(v.desconto);

    if (v.itens != null && v.itens!.isNotEmpty) {
      produtosSelecionados = v.itens!
          .map((i) => {
                'produto': i.produtoNome,
                'preco': i.precoUnitario,
                'quantidade': i.quantidade,
                'tamanho': i.tamanho,
                'cor': i.cor,
                if (i.productId != null && i.productId!.trim().isNotEmpty) 'productId': i.productId,
              })
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
            nomeProd = idxDelim >= 0 ? rest.substring(0, idxDelim).trim() : rest.trim();
            final qtdStr = linha.substring(0, idxX).trim();
            qtdLegado = int.tryParse(qtdStr) ?? v.quantidade;
          }
        }
      } catch (_) {
        nomeProd = v.produtosDescricao.trim().isNotEmpty ? v.produtosDescricao.split('\n').first.trim() : 'Produto';
      }
      produtosSelecionados = [
        {
          'produto': nomeProd,
          'preco': precoLegado,
          'quantidade': qtdLegado < 1 ? 1 : qtdLegado,
          'tamanho': v.tamanho,
          'cor': '',
        },
      ];
    }

    pagamentos = [];
    if (v.pagamentoDinheiro > 0) pagamentos.add({'forma': 'Dinheiro', 'valor': v.pagamentoDinheiro});
    if (v.pagamentoPix > 0) pagamentos.add({'forma': 'Pix', 'valor': v.pagamentoPix});
    if (v.pagamentoCartao > 0) pagamentos.add({'forma': 'Cartão', 'valor': v.pagamentoCartao});
    if (pagamentos.isEmpty) pagamentos.add({'forma': 'Pix', 'valor': v.total});

    for (final c in _valorControllers) {
      c.dispose();
    }
    _valorControllers.clear();
    for (final p in pagamentos) {
      final val = (p['valor'] as num?)?.toDouble() ?? 0.0;
      _valorControllers.add(TextEditingController(text: MoedaInputFormatter.format(val)));
    }
    for (final c in _quantityControllers) {
      c.dispose();
    }
    _quantityControllers.clear();
    for (final item in produtosSelecionados) {
      final q = item['quantidade'] ?? 1;
      _quantityControllers.add(TextEditingController(text: (q is int ? q : int.tryParse(q.toString()) ?? 1).toString()));
    }

    setState(() {});
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
              .map<Map<String, dynamic>>(
            (p) {
              return {
                'label': p['label'] ?? '',
                'tipo': p['tipo'] ?? 'percent',
                'valor': (p['valor'] as num?)?.toDouble() ?? 0.0,
              };
            },
          ).toList();

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
        _premiosRoleta = List<Map<String, dynamic>>.from(
          _premiosRoletaDefault,
        );
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

  double _calcularTotalSemRoleta() {
    final subtotal = _calcularSubtotal();
    final descontoAplicado = subtotal * (desconto / 100);
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

  double _calcularTotal() {
    final semRoleta = _calcularTotalSemRoleta();
    final total = semRoleta - descontoRoletaValor;
    return total < 0 ? 0.0 : total;
  }

  double _precoDoProduto(Produto p) =>
      p.precoFinal > 0 ? p.precoFinal : (p.precoUnitario > 0 ? p.precoUnitario : 0.0);

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

  /// Últimas vendas do cliente (da vendasBox, por nome)
  List<Venda> _ultimasVendasCliente(String nomeCliente) {
    if (nomeCliente.trim().isEmpty) return [];
    final lower = nomeCliente.trim().toLowerCase();
    return widget.vendasBox.values
        .where((v) =>
            (v.lojaId == lojaId || v.lojaId == null) &&
            v.clienteNome.trim().toLowerCase() == lower)
        .toList()
      ..sort((a, b) => b.data.compareTo(a.data));
  }

  /// Produtos mais vendidos (para sugerir no topo)
  List<String> _produtosMaisVendidos({int limit = 5}) {
    final contagem = <String, int>{};
    for (final v in widget.vendasBox.values) {
      if (v.lojaId != null && v.lojaId != lojaId) continue;
      if (v.itens != null && v.itens!.isNotEmpty) {
        for (final item in v.itens!) {
          contagem[item.produtoNome] = (contagem[item.produtoNome] ?? 0) + item.quantidade;
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
      _valorControllers[0].selection = TextSelection.collapsed(offset: _valorControllers[0].text.length);
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
    final temVariacao = prod != null &&
        (prod.usaVariacoes || prod.estoquePorTamanho.isNotEmpty || prod.temVariacaoSoloCor);
    final tam = (item['tamanho'] ?? '').toString();
    final cor = (item['cor'] ?? '').toString();
    final sel = item['itensComboComSelecao'];
    final temComboSelecao = sel is List && sel.isNotEmpty;
    final temSelecao = tam.isNotEmpty || cor.isNotEmpty || temComboSelecao;

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
        label = [if (tam.isNotEmpty) tam, if (cor.isNotEmpty) cor].join(' / ');
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
            await ComboVariacaoSelectionSheet.show(
              context,
              combo: prod,
              quantidade: (item['quantidade'] ?? 1) as int,
              preco: (item['preco'] ?? 0.0) as double,
              produtosBox: widget.produtosBox,
              lojaId: lojaId,
              onConfirmar: (selecao, qtd, preco) {
                setState(() {
                  produtosSelecionados[index]['produto'] = prod.nome;
                  produtosSelecionados[index]['productId'] = prod.idFirebase.trim().isNotEmpty ? prod.idFirebase : null;
                  produtosSelecionados[index]['preco'] = preco;
                  produtosSelecionados[index]['quantidade'] = qtd;
                  produtosSelecionados[index]['tamanho'] = '';
                  produtosSelecionados[index]['cor'] = '';
                  produtosSelecionados[index]['itensComboComSelecao'] = selecao;
                });
              },
            );
          } else if (temVariacao) {
            await NovaVendaVariacaoSheet.show(
              context,
              produto: prod,
              preco: _precoDoProduto(prod),
              onConfirmar: (t, c, qtd) {
                setState(() {
                  produtosSelecionados[index]['tamanho'] = t;
                  produtosSelecionados[index]['cor'] = c;
                  produtosSelecionados[index]['quantidade'] = qtd;
                  produtosSelecionados[index].remove('itensComboComSelecao');
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
            border: Border.all(color: ehCombo ? Colors.orange.shade200 : Colors.blue.shade200),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: ehCombo ? Colors.orange.shade700 : Colors.blue.shade700),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(fontSize: 13, color: ehCombo ? Colors.orange.shade900 : Colors.blue.shade900, fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _obterEstoqueProduto(Produto p, String tamanho, String cor) {
    if (p.usaVariacoes && tamanho.isNotEmpty && cor.isNotEmpty) {
      return p.obterEstoqueVariacao(tamanho, cor);
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
            .map((i) => {
                  'produto': i.produtoNome,
                  'preco': i.precoUnitario,
                  'quantidade': i.quantidade,
                  'tamanho': i.tamanho,
                  'cor': i.cor,
                  if (i.productId != null && i.productId!.trim().isNotEmpty) 'productId': i.productId,
                })
            .toList();
        frete = venda.frete;
        desconto = venda.desconto;
        freteController.text = MoedaInputFormatter.format(venda.frete);
        descontoController.text = MoedaInputFormatter.format(venda.desconto);
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
          _quantityControllers.add(TextEditingController(text: (q is int ? q : int.tryParse(q.toString()) ?? 1).toString()));
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
          },
        ];
        frete = venda.frete;
        desconto = venda.desconto;
        freteController.text = MoedaInputFormatter.format(venda.frete);
        descontoController.text = MoedaInputFormatter.format(venda.desconto);
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
          _quantityControllers.add(TextEditingController(text: (q is int ? q : int.tryParse(q.toString()) ?? 1).toString()));
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
        // soma no desconto % existente
        desconto += valor;
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

  /// Extrai o erro real quando vem encapsulado (comum no app web)
  String _extrairErroReal(Object e) {
    try {
      final dyn = e as dynamic;
      if (dyn.error != null) return dyn.error.toString();
    } catch (_) {}
    return e.toString();
  }

  Future<void> _mostrarErro(String mensagem) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Atenção'),
        content: SingleChildScrollView(
          child: Text(mensagem),
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
  // 🔹 NÚMERO DA SORTE – gera e registra na campanha (SÓ SE HOUVER CAMPANHA ATIVA)
  // Retorna o numeroSorte quando registrado em campanha, senão null.
  // ---------------------------------------------------------------------------
  Future<String?> _registrarNumeroSorteio({
    required double totalCompra,
    required String nomeClienteFinal,
    String? clienteId,
    Cliente? cliente,
  }) async {
    try {
      // Gera número 5 dígitos
      final numeroSorte = SorteioNumeroService.gerarNumeroCliente();

      // Registra nas campanhas ativas da loja
      // Retorna true apenas se houver pelo menos uma campanha ativa
      final registrou = await SorteioNumeroService.registrarNumeroEmCampanhas(
        lojaId: lojaId,
        clienteNome: nomeClienteFinal,
        clienteId: clienteId ?? cliente?.idFirebase,
        valorCompra: totalCompra,
        dataCompra: DateTime.now(),
        numeroSorte: numeroSorte,
      );

      // ✅ SÓ mostra o diálogo se houver campanha ativa
      if (!registrou) {
        logD('ℹ️ [SORTEIO] Nenhuma campanha ativa - número da sorte não exibido');
        return null;
      }

      if (!mounted) return null;

      // Mostra pro vendedor/cliente
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
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
              const Text(
                'Número da sorte:',
                style: TextStyle(fontSize: 13),
              ),
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
      return numeroSorte;
    } catch (e, st) {
      if (!mounted) return null;
      logE('❌ [VENDA] Erro ao registrar número do sorteio (type=${e.runtimeType})', error: e, st: st);
      // Não bloqueia a venda se der erro no sorteio
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Venda concluída, mas houve erro ao registrar o número do sorteio: $e',
          ),
        ),
      );
      return null;
    }
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
    // 🔹 Valida dados obrigatórios ANTES de abrir o dialog (evita bug ao voltar)
    final nomeClienteDigitado = clienteController.text.trim();
    if (nomeClienteDigitado.isEmpty) {
      await _mostrarErro('Informe o nome do cliente para finalizar a venda.');
      return;
    }

    final total = _calcularTotal();
    final resumoProdutos = produtosSelecionados
        .where((p) => (p['produto'] ?? '').toString().trim().isNotEmpty)
        .map((p) => {
              'produto': p['produto'],
              'quantidade': p['quantidade'] ?? 1,
              'preco': p['preco'] ?? 0.0,
            })
        .toList();

    if (resumoProdutos.isEmpty) {
      await _mostrarErro('Adicione pelo menos um produto.');
      return;
    }

    final subtotal = _calcularSubtotal();
    final descontoValor = subtotal * (desconto / 100);

    // Sincroniza valores dos controllers com pagamentos e quantidades antes de abrir o dialog
    for (var i = 0; i < pagamentos.length && i < _valorControllers.length; i++) {
      final v = MoedaInputFormatter.parse(_valorControllers[i].text);
      pagamentos[i]['valor'] = v;
    }
    for (var i = 0; i < produtosSelecionados.length && i < _quantityControllers.length; i++) {
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
      initialPagamentos: pagamentos.map((p) => {
        'forma': p['forma'],
        'valor': (p['valor'] as num?)?.toDouble() ?? 0.0,
      }).toList(),
    );

    if (result == null || !mounted) return;

    if (result.isFiado) {
      _pendenteFiado = true;
      _pendenteDiasVencimento = result.diasVencimento;
      pagamentos = [];
    } else {
      _pendenteFiado = false;
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
          content: Text('Troco a dar: R\$ ${result.trocoTotal.toStringAsFixed(2).replaceAll('.', ',')}'),
          backgroundColor: Colors.green,
        ),
      );
    }

    await _executarFinalizacaoVenda();
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

    // 2) Validação do valor pago (dispensada quando venda fiada)
    if (!_pendenteFiado && (totalPago - total).abs() > 0.01) {
      await _mostrarErro(
        'O valor pago (R\$ ${totalPago.toStringAsFixed(2)}) '
        'não bate com o total (R\$ ${total.toStringAsFixed(2)}).',
      );
      return;
    }

    // 3) Validação dos produtos (estoque + produto não cadastrado + tamanho + cor)
    for (var i = 0; i < produtosSelecionados.length; i++) {
      final item = produtosSelecionados[i];
      final nome = (item['produto'] ?? '').toString().trim();
      final qtd = (item['quantidade'] ?? 1) as int;
      final tamanho = (item['tamanho'] ?? '').toString().trim();
      final cor = (item['cor'] ?? '').toString().trim();

      if (nome.isEmpty || qtd <= 0) {
        await _mostrarErro('Preencha os produtos corretamente.');
        return;
      }

      // 🔥 Buscar produto da loja atual — prefer productId para evitar falso "sem estoque"
      final productId = (item['productId'] as String?)?.trim();
      Produto prod = Produto.vazio();
      if (productId != null && productId.isNotEmpty) {
        try {
          prod = widget.produtosBox.values.firstWhere(
            (p) =>
                p.lojaId == lojaId &&
                (p.idFirebase == productId || p.key?.toString() == productId),
            orElse: () => Produto.vazio(),
          );
        } catch (_) {}
      }
      if (prod.nome.isEmpty) {
        prod = widget.produtosBox.values.firstWhere(
          (p) =>
              p.lojaId == lojaId &&
              p.nome.trim().toLowerCase() == nome.trim().toLowerCase(),
          orElse: () => Produto.vazio(),
        );
      }

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
          // Abre a tela de Estoque por rota nomeada, SEM fechar o modal
          if (!mounted) return;
          await Navigator.of(context).pushNamed(
            '/estoque',
            arguments: {
              'nomeInicial': nome,
              'lojaId': lojaId,
            },
          );
        }

        // Para aqui. Depois que o usuário cadastrar, ele clica "Finalizar" de novo.
        return;
      }

      // 🔹 Validação de variações conforme tipo
      if (prod.temVariacaoSoloCor && cor.isEmpty) {
        await _mostrarErro('Informe a cor para o produto "$nome".');
        return;
      }
      if (prod.temVariacaoTamanhoECor && (tamanho.isEmpty || cor.isEmpty)) {
        await _mostrarErro('Informe tamanho e cor para o produto "$nome".');
        return;
      }
      if ((prod.temVariacaoSoloTamanho || prod.estoquePorTamanho.isNotEmpty) && tamanho.isEmpty) {
        await _mostrarErro('Informe o tamanho para o produto "$nome".');
        return;
      }

      // 🔹 Calcula estoque disponível: variações, por tamanho, ou total
      int disponivel;
      String msgEstoque = '';

      if (prod.temVariacaoSoloCor && cor.isNotEmpty) {
        disponivel = prod.obterEstoqueVariacao('', cor);
        msgEstoque = 'cor $cor';
      } else if (prod.usaVariacoes && (tamanho.isNotEmpty || cor.isNotEmpty)) {
        final tamKey = tamanho.isEmpty ? '' : tamanho;
        final corKey = cor.isEmpty ? 'sem-cor' : cor;
        disponivel = prod.obterEstoqueVariacao(tamKey, corKey);
        msgEstoque = tamanho.isNotEmpty ? 'tamanho $tamanho${cor.isEmpty ? '' : ' - cor $cor'}' : 'cor $cor';
      } else if (prod.estoquePorTamanho.isNotEmpty && tamanho.isNotEmpty) {
        disponivel = prod.estoquePorTamanho[tamanho] ?? 0;
        msgEstoque = 'tamanho $tamanho';
      } else {
        disponivel = prod.quantidade;
        msgEstoque = '';
      }

      if (disponivel < qtd) {
        final msg = msgEstoque.isNotEmpty
            ? 'Estoque insuficiente para "$nome" no $msgEstoque. Disponível: $disponivel.'
            : 'Estoque insuficiente para "$nome". Disponível: $disponivel.';

        if (!mounted) return;
        final acao = await showDialog<String>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Produto com estoque zerado'),
            content: Text(
              '$msg\n\nO que deseja fazer?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, 'remover'),
                child: const Text('Remover da venda'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, 'atualizar'),
                child: const Text('Ir para o produto'),
              ),
            ],
          ),
        );

        if (acao == 'remover') {
          produtosSelecionados.removeAt(i);
          if (produtosSelecionados.isEmpty) {
            produtosSelecionados.add({
              'produto': '',
              'preco': 0.0,
              'quantidade': 1,
              'tamanho': '',
              'cor': '',
            });
          }
          setState(() {});
          return;
        }
        if (acao == 'atualizar') {
          if (!mounted) return;
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
        return;
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
        itens.add(VendaItem(
          produtoNome: nome,
          quantidade: (m['quantidade'] ?? 1) as int,
          precoUnitario: (m['preco'] ?? 0.0) as double,
          tamanho: (m['tamanho'] ?? '').toString(),
          cor: (m['cor'] ?? '').toString(),
          lojaId: lojaId,
          productId: productId != null && productId.isNotEmpty ? productId : null,
        ));
      }
      if (itens.isEmpty) {
        await _mostrarErro('Adicione pelo menos um produto.');
        return;
      }

      double valorPagamento(dynamic v) =>
          (v is num) ? v.toDouble() : (double.tryParse(v?.toString() ?? '') ?? 0.0);

      double valorDinheiro = _pendenteFiado
          ? 0.0
          : pagamentos
              .where((p) => (p['forma'] ?? '') == 'Dinheiro')
              .fold(0.0, (s, p) => s + valorPagamento(p['valor']));

      double valorPix = _pendenteFiado
          ? 0.0
          : pagamentos
              .where((p) => (p['forma'] ?? '') == 'Pix')
              .fold(0.0, (s, p) => s + valorPagamento(p['valor']));

      double valorCartao = _pendenteFiado
          ? 0.0
          : pagamentos
              .where((p) => (p['forma'] ?? '') == 'Cartão')
              .fold(0.0, (s, p) => s + valorPagamento(p['valor']));

      logD('💰 [VENDA] Pagamentos - Dinheiro: R\$ ${valorDinheiro.toStringAsFixed(2)}, Pix: R\$ ${valorPix.toStringAsFixed(2)}, Cartão: R\$ ${valorCartao.toStringAsFixed(2)}');

      // 🔹 Nome que será usado tanto na venda quanto no número da sorte (cliente não é null aqui)
      final nomeClienteFinal = cliente.nome.isNotEmpty
          ? cliente.nome
          : (nomeClienteDigitado.isEmpty ? 'Cliente' : capitalizeWords(nomeClienteDigitado.trim()));

      // Captura referências antes de qualquer await; não usar widget/context após pop.
      final onErro = widget.onErroAoFinalizar;
      final produtosBox = widget.produtosBox;
      final clientesBox = widget.clientesBox;
      final vendasBox = widget.vendasBox;
      final vendedor = widget.vendedor;
      final vendaParaEditarRef = widget.vendaParaEditar;
      final onVendaFinalizadaRef = widget.onVendaFinalizada;

      // Só fecha o modal após o salvamento principal ter sido concluído com sucesso.
      final ok = await _salvarVendaEmBackground(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        vendedor: vendedor,
        nomeClienteFinal: nomeClienteFinal,
        cliente: cliente,
        itens: itens,
        itensComboSelecaoPorIndice: itensComboSelecaoPorIndice.isEmpty ? null : itensComboSelecaoPorIndice,
        valorDinheiro: valorDinheiro,
        valorPix: valorPix,
        valorCartao: valorCartao,
        total: total,
        observacao: observacaoController.text.trim(),
        onErro: onErro,
        isFiado: _pendenteFiado,
        diasVencimentoFiado: _pendenteDiasVencimento,
        vendaParaEditar: vendaParaEditarRef,
      );
      _pendenteFiado = false;
      if (!mounted) return;
      if (ok) {
        onVendaFinalizadaRef();
        Navigator.of(context).pop(true);
      }
    } catch (e, stackTrace) {
      if (!mounted) return;
      final erroReal = _extrairErroReal(e);
      logE('❌ [VENDA] Erro (type=${erroReal.runtimeType})', error: erroReal, st: stackTrace);
      await _mostrarErro(
        'Erro ao salvar venda. '
        'Verifique sua conexão e se o produto está no estoque. '
        'Detalhe: $erroReal',
      );
    }
  }

  /// Executa guard, registrarVendaMulti e número da sorte. Não usa widget/context.
  /// Retorna true se salvou com sucesso; false em caso de erro (onErro já chamado).
  Future<bool> _salvarVendaEmBackground({
    required Box<Produto> produtosBox,
    required Box<Cliente> clientesBox,
    required Box<Venda> vendasBox,
    required String vendedor,
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
    Venda? vendaParaEditar,
  }) async {
    try {
      String? idFirebaseToReuse;
      if (vendaParaEditar != null) {
        idFirebaseToReuse = vendaParaEditar.idFirebase;
        await VendasService.desfazerVenda(
          produtosBox: produtosBox,
          clientesBox: clientesBox,
          vendasBox: vendasBox,
          venda: vendaParaEditar,
        );
      }

      final guard = LimitsGuard();
      final podeVenda = await guard.canAddVenda(lojaId);
      if (!podeVenda) {
        onErro?.call(
          'Limite de vendas do mês atingido no plano Free. Faça upgrade para registrar mais vendas.',
        );
        return false;
      }

      final venda = await VendasService.registrarVendaMulti(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: nomeClienteFinal,
        itens: itens,
        dinheiro: valorDinheiro,
        pix: valorPix,
        cartao: valorCartao,
        vendedor: vendedor,
        observacao: observacao,
        frete: frete,
        descontoPct: desconto,
        lojaId: lojaId,
        clienteExistente: cliente,
        idFirebaseToReuse: idFirebaseToReuse,
        onSyncError: onErro,
        isFiado: isFiado,
        dataVencimentoFiado: isFiado ? DateTime.now().add(Duration(days: diasVencimentoFiado)) : null,
        itensComboSelecaoPorIndice: itensComboSelecaoPorIndice,
      );

      final numeroSorte = await _registrarNumeroSorteio(
        totalCompra: total,
        nomeClienteFinal: nomeClienteFinal,
        clienteId: null,
        cliente: cliente,
      );

      // Enviar número da sorte ao cliente por WhatsApp e e-mail (quando houver contato)
      if (numeroSorte != null) {
        final email = (cliente?.email ?? '').trim();
        final telefone = (cliente?.telefone ?? '').trim();
        if (email.isNotEmpty || telefone.isNotEmpty) {
          final vendaId = venda.key.toString();
          final customer = <String, dynamic>{
            'nome': nomeClienteFinal,
            'email': email,
            'telefone': telefone,
          };
          await PosPagamentoService.enviarNotificacaoNumeroSorte(
            lojaId: lojaId,
            vendaId: vendaId,
            customer: customer,
            numeroSorte: numeroSorte,
            valorTotal: total,
          );
        }
      }
      return true;
    } catch (e, stackTrace) {
      final erroReal = _extrairErroReal(e);
      logE('❌ [VENDA] Erro ao salvar em background (type=${erroReal.runtimeType})', error: erroReal, st: stackTrace);
      onErro?.call(
        'Erro ao salvar venda. Verifique conexão e estoque. $erroReal',
      );
      return false;
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
            color: Colors.black.withValues(alpha:0.08),
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
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Cliente (autocomplete)
                    Autocomplete<String>(
                  initialValue: TextEditingValue(text: clienteController.text),
                  optionsBuilder: (textEditingValue) {
                    if (textEditingValue.text.isEmpty) {
                      return const Iterable<String>.empty();
                    }
                    final lower = textEditingValue.text.toLowerCase().trim();
                    return widget.clientesBox.values
                        .where((c) =>
                            c.lojaId == lojaId &&
                            c.nome.toLowerCase().contains(lower))
                        .map((c) => c.nome)
                        .toSet()
                        .toList()
                      ..sort();
                  },
                  onSelected: (value) {
                    clienteController.text = value;
                    setState(() {});
                  },
                  fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                    return TextFormField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: InputDecoration(
                        labelText: 'Cliente',
                        hintText: 'Buscar clientes cadastrados',
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (v) {
                        clienteController.text = v;
                        setState(() {});
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
                        final vendasCliente = _ultimasVendasCliente(nomeCliente);
                        if (vendasCliente.isEmpty) return const SizedBox.shrink();
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
                                  Icon(Icons.history, size: 20, color: Colors.blue.shade700),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Última: R\$ ${ultima.total.toStringAsFixed(2)} ? ${ultima.data.day.toString().padLeft(2, '0')}/${ultima.data.month}',
                                      style: TextStyle(fontSize: 13, color: Colors.blue.shade900),
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
                                padding: const EdgeInsets.symmetric(vertical: 12),
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
                      final precoStr = 'R\$ ${precoVal.toDouble().toStringAsFixed(2).replaceAll('.', ',')}';

                      return Container(
                        key: ValueKey('produto_row_$index'),
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha:0.04),
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
                                    key: ValueKey('dropdown_produto_$index'),
                                    valorAtual: valorAtual,
                                    produtos: produtosDaLoja,
                                    lojaId: lojaId,
                                    produtosFavoritos: _produtosMaisVendidos(limit: 8),
                                    precoDoProduto: _precoDoProduto,
                                    onChanged: (nome, preco) {
                                      setState(() {
                                        produtosSelecionados[index]['produto'] = nome;
                                        produtosSelecionados[index]['preco'] = preco;
                                        produtosSelecionados[index]['tamanho'] = '';
                                        produtosSelecionados[index]['cor'] = '';
                                        produtosSelecionados[index].remove('itensComboComSelecao');
                                        produtosSelecionados[index]['quantidade'] = 1;
                                      });
                                    },
                                    onProductIsCombo: (combo) async {
                                      await ComboVariacaoSelectionSheet.show(
                                        context,
                                        combo: combo,
                                        quantidade: 1,
                                        preco: _precoDoProduto(combo),
                                        produtosBox: widget.produtosBox,
                                        lojaId: lojaId,
                                        onConfirmar: (selecao, qtd, preco) {
                                          setState(() {
                                            produtosSelecionados[index]['produto'] = combo.nome;
                                            produtosSelecionados[index]['productId'] = combo.idFirebase.trim().isNotEmpty ? combo.idFirebase : null;
                                            produtosSelecionados[index]['preco'] = preco;
                                            produtosSelecionados[index]['quantidade'] = qtd;
                                            produtosSelecionados[index]['tamanho'] = '';
                                            produtosSelecionados[index]['cor'] = '';
                                            produtosSelecionados[index]['itensComboComSelecao'] = selecao;
                                          });
                                        },
                                      );
                                    },
                                    onProductNeedsVariation: (produto) async {
                                      await NovaVendaVariacaoSheet.show(
                                        context,
                                        produto: produto,
                                        preco: _precoDoProduto(produto),
                                        onConfirmar: (tam, cor, qtd) {
                                          setState(() {
                                            produtosSelecionados[index]['produto'] = produto.nome;
                                            produtosSelecionados[index]['productId'] = produto.idFirebase.trim().isNotEmpty ? produto.idFirebase : null;
                                            produtosSelecionados[index]['preco'] = _precoDoProduto(produto);
                                            produtosSelecionados[index]['tamanho'] = tam;
                                            produtosSelecionados[index]['cor'] = cor;
                                            produtosSelecionados[index]['quantidade'] = qtd;
                                            produtosSelecionados[index].remove('itensComboComSelecao');
                                          });
                                        },
                                      );
                                    },
                                    onTextChanged: (v) {
                                      setState(() {
                                        produtosSelecionados[index]['produto'] = v;
                                        final p = produtosDaLoja.firstWhereOrNull(
                                          (x) => x.nome.toLowerCase() == v.trim().toLowerCase(),
                                        );
                                        if (p != null) {
                                          produtosSelecionados[index]['preco'] = _precoDoProduto(p);
                                          produtosSelecionados[index]['productId'] = p.idFirebase.trim().isNotEmpty ? p.idFirebase : null;
                                        } else {
                                          produtosSelecionados[index].remove('productId');
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
                                      icon: Icon(Icons.qr_code_scanner, color: Colors.grey[700]),
                                      onPressed: () async {
                                        final messenger = ScaffoldMessenger.of(context);
                                        final navigator = Navigator.of(context);
                                        final code = await BarcodeScannerScreen.scan(context);
                                        if (code == null || code.isEmpty || !mounted) return;
                                        final prod = widget.produtosBox.values.firstWhereOrNull(
                                          (p) => p.lojaId == lojaId &&
                                              p.codigoBarras.isNotEmpty &&
                                              normalizeText(p.codigoBarras) == normalizeText(code),
                                        );
                                        if (prod == null) {
                                          if (!mounted) return;
                                          messenger.showSnackBar(
                                            const SnackBar(content: Text('Nenhum produto encontrado com esse código de barras')),
                                          );
                                          return;
                                        }
                                        if (prod.ehCombo) {
                                          await ComboVariacaoSelectionSheet.show(
                                            navigator.context,
                                            combo: prod,
                                            quantidade: 1,
                                            preco: _precoDoProduto(prod),
                                            produtosBox: widget.produtosBox,
                                            lojaId: lojaId,
                                            onConfirmar: (selecao, qtd, preco) {
                                              if (!mounted) return;
                                              setState(() {
                                                produtosSelecionados[index]['produto'] = prod.nome;
                                                produtosSelecionados[index]['productId'] = prod.idFirebase.trim().isNotEmpty ? prod.idFirebase : null;
                                                produtosSelecionados[index]['preco'] = preco;
                                                produtosSelecionados[index]['quantidade'] = qtd;
                                                produtosSelecionados[index]['tamanho'] = '';
                                                produtosSelecionados[index]['cor'] = '';
                                                produtosSelecionados[index]['itensComboComSelecao'] = selecao;
                                              });
                                            },
                                          );
                                        } else if (prod.usaVariacoes || prod.estoquePorTamanho.isNotEmpty) {
                                          await NovaVendaVariacaoSheet.show(
                                            navigator.context,
                                            produto: prod,
                                            preco: _precoDoProduto(prod),
                                            onConfirmar: (tam, cor, qtd) {
                                              if (!mounted) return;
                                              setState(() {
                                                produtosSelecionados[index]['produto'] = prod.nome;
                                                produtosSelecionados[index]['productId'] = prod.idFirebase.trim().isNotEmpty ? prod.idFirebase : null;
                                                produtosSelecionados[index]['preco'] = _precoDoProduto(prod);
                                                produtosSelecionados[index]['tamanho'] = tam;
                                                produtosSelecionados[index]['cor'] = cor;
                                                produtosSelecionados[index]['quantidade'] = qtd;
                                              });
                                            },
                                          );
                                        } else {
                                          setState(() {
                                            produtosSelecionados[index]['produto'] = prod.nome;
                                            produtosSelecionados[index]['productId'] = prod.idFirebase.trim().isNotEmpty ? prod.idFirebase : null;
                                            produtosSelecionados[index]['preco'] = _precoDoProduto(prod);
                                            produtosSelecionados[index]['tamanho'] = '';
                                            produtosSelecionados[index]['cor'] = '';
                                          });
                                        }
                                      },
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.add_circle, color: Colors.green.shade600),
                                      onPressed: () {
                                        setState(() {
                                          produtosSelecionados.add({
                                            'produto': '',
                                            'preco': 0.0,
                                            'quantidade': 1,
                                            'tamanho': '',
                                            'cor': '',
                                          });
                                          _quantityControllers.add(TextEditingController(text: '1'));
                                        });
                                      },
                                    ),
                                    if (produtosSelecionados.length > 1)
                                      IconButton(
                                        icon: Icon(Icons.remove_circle_outline, color: Colors.red.shade400),
                                        onPressed: () {
                                          setState(() {
                                            if (index < _quantityControllers.length) {
                                              _quantityControllers[index].dispose();
                                              _quantityControllers.removeAt(index);
                                            }
                                            produtosSelecionados.removeAt(index);
                                          });
                                        },
                                      ),
                                  ],
                                ),
                              ],
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
                                    controller: index < _quantityControllers.length
                                        ? _quantityControllers[index]
                                        : null,
                                    key: index < _quantityControllers.length
                                        ? null
                                        : ValueKey('qtd_$index'),
                                    initialValue: index < _quantityControllers.length
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
                                        produtosSelecionados[index]['quantidade'] = qtd < 1 ? 1 : qtd;
                                      });
                                    },
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.primary.withValues(alpha:0.08),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    precoStr,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Theme.of(context).colorScheme.primary,
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
                                    final nomeProd = (item['produto'] ?? '').toString().trim();
                                    if (nomeProd.isEmpty) return const SizedBox.shrink();
                                    final prod = produtosDaLoja.firstWhereOrNull(
                                      (p) => p.lojaId == lojaId && p.nome.toLowerCase() == nomeProd.toLowerCase(),
                                    );
                                    if (prod == null) return const SizedBox.shrink();
                                    final tam = (item['tamanho'] ?? '').toString();
                                    final cor = (item['cor'] ?? '').toString();
                                    final disp = _obterEstoqueProduto(prod, tam, cor);
                                    final isBaixo = disp < 3 && disp > 0;
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: disp == 0 ? Colors.red.shade50 : (isBaixo ? Colors.orange.shade50 : Colors.grey.shade100),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'Est. $disp${isBaixo ? ' ⚠' : ''}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: disp == 0 ? Colors.red.shade700 : (isBaixo ? Colors.orange.shade800 : Colors.grey.shade700),
                                          fontWeight: isBaixo ? FontWeight.w600 : FontWeight.normal,
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
                            child: MoedaTextField(
                              controller: descontoController,
                              labelText: 'Desconto (%)',
                              hintText: 'Ex: 10',
                              onChanged: (value) => desconto = value,
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
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
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
                                  initialValue: item['forma'],
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
                                icon: Icon(Icons.remove_circle, color: Colors.red.shade400),
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
                              icon: Icon(Icons.add, color: Colors.green.shade600, size: 18),
                              label: const Text('Adicionar forma'),
                              onPressed: () {
                                _valorControllers.add(TextEditingController());
                                setState(() => pagamentos.add({'forma': 'Pix', 'valor': 0.0}));
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
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
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
                                      color: Colors.white.withValues(alpha:0.8),
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
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    onPressed: roletaPremioAplicado ? null : _abrirRoleta,
                                    icon: const Icon(Icons.casino),
                                    label: Text(
                                      roletaPremioAplicado ? 'Prêmio já aplicado' : 'Girar roleta',
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
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'R\$ ${total.toStringAsFixed(2).replaceAll('.', ',')}',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
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
                                (p) => (p['produto'] ?? '').toString().trim().isNotEmpty,
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
                                        onPressed: () => Navigator.pop(ctx, false),
                                        child: const Text('Continuar editando'),
                                      ),
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx, true),
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
                            onPressed: _finalizarVenda,
                            icon: const Icon(Icons.check_circle, size: 20),
                            label: Text(_modoEdicao ? 'Salvar alterações' : 'Finalizar venda'),
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
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
                        colors: [
                          Color(0xFF22C55E),
                          Color(0xFF6366F1),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          blurRadius: 16,
                          spreadRadius: 2,
                          color: Colors.black.withValues(alpha:0.6),
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
          child: const Text(
            'Fechar',
            style: TextStyle(color: Colors.white70),
          ),
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
  final void Function(String nome, double preco) onChanged;
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
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: valorAtual),
      optionsBuilder: (textEditingValue) {
        if (textEditingValue.text.isEmpty) {
          final favs = produtosFavoritos.where((n) => todosNomes.contains(n)).toList();
          final resto = todosNomes.where((n) => !favs.contains(n)).toList();
          return [...favs, ...resto];
        }
        final lower = textEditingValue.text.toLowerCase();
        final filtrados = todosNomes.where((n) => n.toLowerCase().contains(lower)).toList();
        final favsFiltrados = produtosFavoritos.where((n) => filtrados.contains(n)).toList();
        final restoFiltrados = filtrados.where((n) => !favsFiltrados.contains(n)).toList();
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
        } else if ((p.usaVariacoes || p.estoquePorTamanho.isNotEmpty) && onProductNeedsVariation != null) {
          await onProductNeedsVariation!(p);
        } else {
          onChanged(value, precoDoProduto(p));
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

