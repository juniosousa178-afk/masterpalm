// lib/screens/public_catalog/widgets/carrinho_sheet_web.dart
// Carrinho/checkout em bottom sheet – extraído do public_catalog_screen.

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:hive/hive.dart';

import 'package:flutter/services.dart';

import '../../../core/logger.dart';
import '../../../core/safe_cast.dart';
import '../../../utils/http_client_helper.dart';
import '../../../utils/keyboard_utils.dart';
import '../../../models/cupom.dart';
import '../../../models/cupom_cliente.dart';
import '../../../services/cliente_auth_service.dart';
import '../../../services/cupom_desconto_service.dart';
import '../../../services/cupons_service.dart';
import '../../../services/frete_service.dart';
import '../../../widgets/selecionar_cupom_modal.dart';
import '../../../widgets/roleta_web_widget_v3.dart';
import '../../auth/login_screen_cliente.dart';
import 'catalog_image_placeholder.dart';
import '../catalog_estoque_helper.dart';

// ==================== CARRINHO (BottomSheet) ====================

class CarrinhoSheetWeb extends StatefulWidget {
  final String lojaId; // 👈 NOVO
  final List<Map<String, dynamic>> items;
  final List<Map<String, dynamic>> fretes;
  final List<Map<String, dynamic>> cupons;
  final void Function(int index) onRemove;

  final Color primary;
  final Color buttonText;
  final Color textColor;
  final Color cardColor;

  // 🔹 NOVAS CORES OPCIONAIS DO CHECKOUT
  final Color? checkoutCardColor;
  final Color? checkoutFieldBg;
  final Color? checkoutFieldBorder;
  final Color? checkoutFieldTextColor;
  final Color? checkoutLabelColor;
  final Color? checkoutTotalColor;

  // 🔹 NOVAS CORES PARA ITENS
  final Color? productNameColor;
  final Color? productPriceColor;

  // Gateway e PIX
  final String checkoutGateway;
  final String checkoutButtonLabel;
  final String pixKey;
  final String freightToken;

  final Future<void> Function({
    required Map<String, dynamic> customer,
    required Map<String, dynamic> entrega,
    required String pagamento,
    String observacao,
    String? cupomRoletaCodigo,
    double? cupomRoletaDesconto,
    String? premioRoletaDescricao,
    Future<void> Function(String? pedidoId)? onSuccess,
    void Function(String message)? showErrorInCart,
  }) onCheckoutWhatsapp;

  final Future<void> Function({
    required Map<String, dynamic> customer,
    required Map<String, dynamic> entrega,
    required String pagamento,
    String observacao,
    String? cupomRoletaCodigo,
    double? cupomRoletaDesconto,
    String? premioRoletaDescricao,
    void Function(String message)? showErrorInCart,
  }) onCheckoutMercadoPago;

  /// Callback para PIX manual (chave PIX da loja) - gera QR com valor e mostra dialog.
  final Future<void> Function({
    required Map<String, dynamic> customer,
    required Map<String, dynamic> entrega,
    required double valorTotal,
    String observacao,
    String? cupomRoletaCodigo,
    double? cupomRoletaDesconto,
    String? premioRoletaDescricao,
    void Function(String message)? showErrorInCart,
  })? onCheckoutPix;

  final void Function(String message) showSnack;

  /// Estado persistente da roleta (do parent) — prevalece ao fechar/reabrir carrinho
  final bool initialRoletaJaGirada;
  final String? initialCupomRoletaCodigo;
  final double? initialCupomRoletaDesconto;
  final String? initialPremioRoletaDescricao;
  final bool initialFreteGratisRoleta;

  /// Callback para persistir no parent quando o cliente ganha na roleta
  final void Function({
    required bool jaGirada,
    String? codigo,
    double? desconto,
    String? descricao,
    required bool freteGratis,
  })? onRoletaPremioGanho;

  /// Dados iniciais do formulário (restaurados ao reabrir o carrinho)
  final Map<String, dynamic>? initialFormData;

  /// Chamado ao fechar o sheet com os dados atuais para persistir
  final void Function(Map<String, dynamic> formData)? onFormDataToSave;

  const CarrinhoSheetWeb({
    super.key,
    required this.lojaId,
    required this.items,
    required this.fretes,
    required this.cupons,
    required this.primary,
    required this.buttonText,
    required this.textColor,
    required this.cardColor,
    this.checkoutCardColor,
    this.checkoutFieldBg,
    this.checkoutFieldBorder,
    this.checkoutFieldTextColor,
    this.checkoutLabelColor,
    this.checkoutTotalColor,
    this.productNameColor,
    this.productPriceColor,
    required this.checkoutGateway,
    required this.checkoutButtonLabel,
    required this.pixKey,
    required this.freightToken,
    required this.onRemove,
    required this.showSnack,
    required this.onCheckoutWhatsapp,
    required this.onCheckoutMercadoPago,
    this.onCheckoutPix,
    this.initialRoletaJaGirada = false,
    this.initialCupomRoletaCodigo,
    this.initialCupomRoletaDesconto,
    this.initialPremioRoletaDescricao,
    this.initialFreteGratisRoleta = false,
    this.onRoletaPremioGanho,
    this.initialFormData,
    this.onFormDataToSave,
  });

  @override
  State<CarrinhoSheetWeb> createState() => _CarrinhoSheetWebState();
}

class _CarrinhoSheetWebState extends State<CarrinhoSheetWeb> {
  // Cadastro completo
  final _nome = TextEditingController();
  final _cpf = TextEditingController();
  final _email = TextEditingController();
  final _tel = TextEditingController();
  final _cep = TextEditingController();
  final _rua = TextEditingController();
  final _numero = TextEditingController();
  final _bairro = TextEditingController();
  final _cidade = TextEditingController();
  final _estado = TextEditingController();
  final _complemento = TextEditingController();
  final _obs = TextEditingController();

  // cupom
  final _cupomCtrl = TextEditingController();
  Map<String, dynamic>? _cupomAplicado;

  // ✨ ROLETA
  String? _campanhaAtivaId; // Campanha (sorteio com número da sorte) — independente da roleta
  bool _roletaAtiva = false; // Roleta (girar e concorrer a prêmios) — config/roleta_sorte
  double _valorMinimoRoleta = 0.0; // Valor mínimo para liberar a roleta
  late bool _roletaJaGirada;
  bool _todosOsDadosPreenchidos = false;
  int _quantidadeProdutosAoMostrarRoleta = 0;
  late String? _cupomRoletaCodigo; // Código do cupom ganho na roleta
  late double? _cupomRoletaDesconto; // Desconto (%) do cupom da roleta
  late String? _premioRoletaDescricao; // Descrição do prêmio (brinde, mimo, etc)
  late bool _freteGratisRoleta; // Frete grátis ganho na roleta

  // ✅ Flag para evitar duplicação de pedidos
  bool _processandoCheckout = false;

  /// Erro de pagamento exibido na tela do carrinho (não no catálogo)
  String? _checkoutError;

  // Validação visual: campos com erro ficam vermelhos
  String? _erroValidacao;
  final Set<String> _camposComErro = {};

  late List<Map<String, dynamic>> _fretesLocal;

  String _fmt2(num v) => v.toStringAsFixed(2).replaceAll('.', ',');

  String _pagamento = 'PIX';
  int _freteIndex = 0;

  double get _subtotal => widget.items.fold<double>(
        0.0,
        (s, e) {
          final price = (e['preco'] as num?)?.toDouble() ??
              0.0; // ✅ CORRIGIDO: 'preco' em vez de 'price'
          final qty =
              CatalogEstoqueHelper.parseCartItemQuantidade(e['quantidade']);
          return s + price * qty;
        },
      );

  /// Subtotal com desconto PIX aplicado (quando produto tem percentualDescontoPix)
  double get _subtotalPix => widget.items.fold<double>(
        0.0,
        (s, e) {
          final price = (e['preco'] as num?)?.toDouble() ?? 0.0;
          final qty =
              CatalogEstoqueHelper.parseCartItemQuantidade(e['quantidade']);
          final pctPix =
              (e['percentualDescontoPix'] as num?)?.toDouble() ?? 0.0;
          final precoEfetivo = pctPix > 0 ? price * (1 - pctPix / 100) : price;
          return s + precoEfetivo * qty;
        },
      );

  /// Subtotal conforme forma de pagamento (PIX aplica desconto quando disponível)
  double get _subtotalConformePagamento =>
      _pagamento.toUpperCase() == 'PIX' ? _subtotalPix : _subtotal;

  double get _descontoCupomProdutos {
    if (_cupomAplicado == null) return 0.0;

    final tipo = (_cupomAplicado!['tipo'] ?? '').toString();
    final valor = (_cupomAplicado!['valor'] as num?)?.toDouble() ?? 0.0;
    final aplicarEm = (_cupomAplicado!['aplicarEm'] ?? 'produtos').toString();

    // base: produtos ou total (produtos + frete) - usa subtotal conforme pagamento (PIX com desconto)
    double base;
    if (aplicarEm == 'total') {
      if (_fretesLocal.isEmpty) {
        base = _subtotalConformePagamento;
      } else {
        final frete =
            _fretesLocal[_freteIndex.clamp(0, _fretesLocal.length - 1)];
        final double freteVal = (frete['valor'] as num?)?.toDouble() ?? 0.0;
        base = _subtotalConformePagamento + (_freteGratis ? 0.0 : freteVal);
      }
    } else {
      base = _subtotalConformePagamento;
    }

    if (tipo == 'percent') {
      final d = base * (valor / 100);
      return d.clamp(0.0, base);
    }
    if (tipo == 'valor') {
      return valor.clamp(0.0, base);
    }
    // frete_gratis não dá desconto em valor, só na flag _freteGratis
    return 0.0;
  }

  bool get _freteGratis {
    // 1) frete grátis ganho na roleta
    if (_freteGratisRoleta) {
      return true;
    }
    // 2) cupom frete grátis (tipo ou flag)
    if (_cupomAplicado != null &&
        (_cupomAplicado!['tipo'] == 'frete_gratis' ||
            _cupomAplicado!['freteGratis'] == true)) {
      return true;
    }
    // 3) frete marcado como grátis na configuração
    if (_fretesLocal.isNotEmpty &&
        _fretesLocal[_freteIndex]['freteGratis'] == true) {
      return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _fretesLocal =
        widget.fretes.map((e) => asMapDeep(e)).toList();

    // Restaurar dados do formulário salvos anteriormente
    final init = widget.initialFormData;
    if (init != null && init.isNotEmpty) {
      _nome.text = (init['nome'] ?? '').toString();
      _cpf.text = (init['cpf'] ?? '').toString();
      _email.text = (init['email'] ?? '').toString();
      _tel.text = (init['tel'] ?? '').toString();
      _cep.text = (init['cep'] ?? '').toString();
      _rua.text = (init['rua'] ?? '').toString();
      _numero.text = (init['numero'] ?? '').toString();
      _bairro.text = (init['bairro'] ?? '').toString();
      _cidade.text = (init['cidade'] ?? '').toString();
      _estado.text = (init['estado'] ?? '').toString();
      _complemento.text = (init['complemento'] ?? '').toString();
      _obs.text = (init['obs'] ?? '').toString();
      _cupomCtrl.text = (init['cupomCodigo'] ?? '').toString();
      final savedFrete = (init['freteIndex'] as int?) ?? 0;
      final maxFrete = _fretesLocal.isEmpty ? 0 : _fretesLocal.length - 1;
      _freteIndex = savedFrete.clamp(0, maxFrete);
      _pagamento = (init['pagamento'] ?? 'PIX').toString();
    }

    // Estado persistente da roleta (do parent — prevalece ao fechar/reabrir)
    _roletaJaGirada = widget.initialRoletaJaGirada;
    _cupomRoletaCodigo = widget.initialCupomRoletaCodigo;
    _cupomRoletaDesconto = widget.initialCupomRoletaDesconto;
    _premioRoletaDescricao = widget.initialPremioRoletaDescricao;
    _freteGratisRoleta = widget.initialFreteGratisRoleta;

    // 🔍 Debug: Mostrar fretes iniciais
    logD(
        '🛒 [CARRINHO] initState - Fretes recebidos: ${widget.fretes.length}');
    logD(
        '📊 [CARRINHO] _fretesLocal inicial: ${_fretesLocal.length} itens');
    for (int i = 0; i < _fretesLocal.length; i++) {
      final f = _fretesLocal[i];
      logD(
          '   [$i] ${f['nome']} - R\$ ${f['valor']} (tipo: ${f['tipo']})');
    }

    _verificarCampanhaAtiva();
    _verificarRoletaAtiva();
    _preencherDadosClienteLogado().then((_) {
      // Se CEP já estiver preenchido (ex.: cliente logado), calcular frete para mostrar opções das APIs
      if (!mounted) return;
      final cep = _cep.text.replaceAll(RegExp(r'[^0-9]'), '');
      if (cep.length == 8 && widget.items.isNotEmpty) {
        _recalcularFreteSelecionado();
      }
    });

    // Adicionar listeners para verificar quando os dados mudarem
    _nome.addListener(_atualizarEstadoRoleta);
    _email.addListener(_atualizarEstadoRoleta);
    _tel.addListener(_atualizarEstadoRoleta);
    _cep.addListener(_atualizarEstadoRoleta);
    _rua.addListener(_atualizarEstadoRoleta);
    _numero.addListener(_atualizarEstadoRoleta);
    _bairro.addListener(_atualizarEstadoRoleta);
    _cidade.addListener(_atualizarEstadoRoleta);
    _estado.addListener(_atualizarEstadoRoleta);
  }

  /// Preenche automaticamente os dados do cliente logado.
  /// Retorna: 'no_login' | 'no_address' | 'success_full' | 'success_partial' | 'success_partial_cf_falhou' | 'error'
  Future<String> _preencherDadosClienteLogado() async {
    try {
      final cliente = await ClienteAuthService.getClienteLogado();
      if (cliente == null) return 'no_login';

      logD('👤 Preenchendo dados do cliente logado: ${cliente['email']}');

      final email = (cliente['email'] ?? '').toString().trim();
      if (email.isEmpty) {
        _nome.text = cliente['nome'] ?? '';
        _email.text = cliente['email'] ?? '';
        _tel.text = cliente['telefone'] ?? '';
        if (mounted) setState(() {});
        return 'success_partial';
      }
      final dados = await ClienteAuthService.getDadosCompletos(
        lojaId: widget.lojaId,
        clienteId: cliente['clienteId'],
        email: email,
      );

      if (dados == null) {
        if (kDebugMode) {
          debugPrint('carrinho_sheet_web: getDadosCompletos retornou null (CF pode ter falhado)');
        }
        _nome.text = cliente['nome'] ?? '';
        _email.text = cliente['email'] ?? '';
        _tel.text = cliente['telefone'] ?? '';
        if (mounted) setState(() {});
        return 'success_partial_cf_falhou';
      }

      _nome.text = dados['nome'] ?? '';
      _email.text = dados['email'] ?? '';
      _tel.text = dados['telefone'] ?? '';

      Map<String, dynamic> endereco = asMap(dados['endereco']);
      if (endereco.isEmpty) {
        try {
          final portalToken = (dados['portalToken'] ??
                  cliente['portalToken'] ??
                  '')
              .toString()
              .trim();
          if (portalToken.isNotEmpty) {
            endereco = await ClienteAuthService.getUltimoEnderecoIndexado(
                  lojaId: widget.lojaId,
                  portalToken: portalToken,
                ) ??
                <String, dynamic>{};
          }
          if (endereco.isEmpty) {
            final email = (dados['email'] ?? cliente['email'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
            if (email.isNotEmpty) {
              final result = await ClienteAuthService.getPedidosDoCliente(
                lojaId: widget.lojaId,
                email: email,
                clienteId: cliente['clienteId']?.toString(),
              );
              if (result.pedidos.isNotEmpty) {
                final cl = asMap(result.pedidos.first['cliente']);
                endereco = asMap(cl['endereco']);
              }
            }
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('carrinho_sheet_web: erro ao buscar endereço de pedido anterior (type=${e.runtimeType})');
          }
        }
      }
      if (endereco.isNotEmpty) {
        _cep.text = endereco['cep'] ?? '';
        _rua.text = endereco['rua'] ?? '';
        _numero.text = endereco['numero'] ?? '';
        _bairro.text = endereco['bairro'] ?? '';
        _cidade.text = endereco['cidade'] ?? '';
        _estado.text = endereco['estado'] ?? '';
        _complemento.text = endereco['complemento'] ?? '';
        if (mounted) setState(() {});
        logD('✅ Dados e endereço preenchidos');
        return 'success_full';
      }

      if (mounted) setState(() {});
      logD('✅ Dados preenchidos (sem endereço salvo)');
      return 'no_address';
    } catch (e, st) {
      logE('❌ Erro ao preencher dados do cliente (type=${e.runtimeType})', error: e, st: st);
      return 'error';
    }
  }

  @override
  void didUpdateWidget(covariant CarrinhoSheetWeb oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.initialRoletaJaGirada != widget.initialRoletaJaGirada ||
        oldWidget.initialCupomRoletaCodigo != widget.initialCupomRoletaCodigo ||
        oldWidget.initialFreteGratisRoleta != widget.initialFreteGratisRoleta) {
      _roletaJaGirada = widget.initialRoletaJaGirada;
      _cupomRoletaCodigo = widget.initialCupomRoletaCodigo;
      _cupomRoletaDesconto = widget.initialCupomRoletaDesconto;
      _premioRoletaDescricao = widget.initialPremioRoletaDescricao;
      _freteGratisRoleta = widget.initialFreteGratisRoleta;
      setState(() {});
    }

    if (oldWidget.fretes != widget.fretes) {
      _fretesLocal =
          widget.fretes.map((e) => asMapDeep(e)).toList();

      if (_fretesLocal.isEmpty) {
        _freteIndex = 0;
      } else if (_freteIndex >= _fretesLocal.length) {
        _freteIndex = 0;
      }

      setState(() {});
      _atualizarEstadoRoleta(); // Atualizar quando mudar o frete
    }

    // Verificar se os produtos mudaram
    if (oldWidget.items.length != widget.items.length) {
      _atualizarEstadoRoleta();
    }
  }

  Future<void> _verificarCampanhaAtiva() async {
    try {
      logD('🔍 Verificando campanha ativa para loja: ${widget.lojaId}');

      final snapshot = await FirebaseFirestore.instance
          .collection('lojas')
          .doc(widget.lojaId)
          .collection('campanhas_sorteio')
          .where('ativa', isEqualTo: true)
          .where('dataFim', isGreaterThanOrEqualTo: Timestamp.now())
          .limit(1)
          .get();

      logD('📊 Campanhas encontradas: ${snapshot.docs.length}');

      if (snapshot.docs.isNotEmpty) {
        final campanha = snapshot.docs.first;
        logD('✅ Campanha ativa encontrada: ${campanha.id}');
        logD('   Nome: ${campanha.data()['nome']}');
        logD('   Valor mínimo: ${campanha.data()['valorMinimo']}');

        if (mounted) {
          setState(() {
            _campanhaAtivaId = campanha.id;
            _valorMinimoRoleta =
                (campanha.data()['valorMinimo'] as num?)?.toDouble() ?? 0.0;
          });
          logD('✅ _campanhaAtivaId setado: $_campanhaAtivaId');
          logD('✅ _valorMinimoRoleta setado: $_valorMinimoRoleta');
        }
      } else {
        logW('⚠️ Nenhuma campanha ativa encontrada');
        if (mounted) {
          setState(() {
            _campanhaAtivaId = null;
            _valorMinimoRoleta = 0.0;
          });
        }
      }
    } catch (e, st) {
      logE('❌ Erro ao verificar campanha (type=${e.runtimeType})', error: e, st: st);
      if (mounted) {
        setState(() {
          _campanhaAtivaId = null;
          _valorMinimoRoleta = 0.0;
        });
      }
    }
  }

  /// Roleta é função separada da campanha: lojas/{id}/config/roleta_sorte (ativa, valorMinimo).
  /// Só exibe roleta no catálogo quando roleta ativa; campanha (sorteio) é outra função.
  Future<void> _verificarRoletaAtiva() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('lojas')
          .doc(widget.lojaId)
          .collection('config')
          .doc('roleta_sorte')
          .get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final ativa = data['ativa'] == true;
        final vm = (data['valorMinimo'] as num?)?.toDouble() ?? 0.0;
        if (mounted) {
          setState(() {
            _roletaAtiva = ativa;
            _valorMinimoRoleta = vm;
          });
        }
        logD('✅ Roleta ativa: $_roletaAtiva, valorMín: $_valorMinimoRoleta');
      } else {
        if (mounted) {
          setState(() {
            _roletaAtiva = false;
            _valorMinimoRoleta = 0.0;
          });
        }
        logW('⚠️ Config roleta_sorte não encontrada');
      }
    } catch (e, st) {
      logE('❌ Erro ao verificar roleta (type=${e.runtimeType})', error: e, st: st);
      if (mounted) {
        setState(() {
          _roletaAtiva = false;
          _valorMinimoRoleta = 0.0;
        });
      }
    }
  }

  /// Verifica se todos os dados necessários foram preenchidos para mostrar a roleta
  bool _verificarDadosCompletos() {
    final nomeOk = _nome.text.trim().isNotEmpty;
    final emailOk = _email.text.trim().isNotEmpty;
    final telOk = _tel.text.trim().isNotEmpty;

    // Se for retirada, não precisa de endereço
    final freteAtual =
        _fretesLocal.isNotEmpty ? _fretesLocal[_freteIndex] : null;
    final tipoFrete = freteAtual?['tipo'] ?? '';

    bool enderecoOk = true;
    if (tipoFrete != 'retirada') {
      enderecoOk = _cep.text.trim().isNotEmpty &&
          _rua.text.trim().isNotEmpty &&
          _numero.text.trim().isNotEmpty &&
          _bairro.text.trim().isNotEmpty &&
          _cidade.text.trim().isNotEmpty &&
          _estado.text.trim().isNotEmpty;
    }

    final pagamentoOk = _pagamento.isNotEmpty;

    return nomeOk && emailOk && telOk && enderecoOk && pagamentoOk;
  }

  /// Atualiza o estado de dados completos e verifica se pode mostrar roleta
  void _atualizarEstadoRoleta() {
    final dadosCompletos = _verificarDadosCompletos();

    if (dadosCompletos && !_todosOsDadosPreenchidos) {
      // Primeira vez que todos os dados foram preenchidos
      setState(() {
        _todosOsDadosPreenchidos = true;
        _quantidadeProdutosAoMostrarRoleta = widget.items.length;
      });
    } else if (!dadosCompletos && _todosOsDadosPreenchidos) {
      // Dados foram alterados e ficaram incompletos
      setState(() {
        _todosOsDadosPreenchidos = false;
      });
    }
  }

  /// Verifica se a roleta pode ser exibida (só quando roleta ativa, não campanha)
  bool get _podeExibirRoleta {
    if (!_roletaAtiva) return false;
    if (_roletaJaGirada) return false;
    if (!_todosOsDadosPreenchidos) return false;
    if (_subtotal < _valorMinimoRoleta) return false; // ✅ Verifica valor mínimo

    // Se a quantidade de produtos mudou (usuário adicionou/removeu produtos)
    // Perde a chance, a não ser que tenha ADICIONADO produtos
    if (widget.items.length != _quantidadeProdutosAoMostrarRoleta) {
      if (widget.items.length > _quantidadeProdutosAoMostrarRoleta) {
        // Adicionou produtos - atualiza a quantidade e mantém a chance
        _quantidadeProdutosAoMostrarRoleta = widget.items.length;
        return true;
      } else {
        // Removeu produtos - perde a chance
        return false;
      }
    }

    return true;
  }

  Map<String, dynamic> _getFormDataMap() {
    return {
      'nome': _nome.text,
      'cpf': _cpf.text,
      'email': _email.text,
      'tel': _tel.text,
      'cep': _cep.text,
      'rua': _rua.text,
      'numero': _numero.text,
      'bairro': _bairro.text,
      'cidade': _cidade.text,
      'estado': _estado.text,
      'complemento': _complemento.text,
      'obs': _obs.text,
      'cupomCodigo': _cupomCtrl.text,
      'freteIndex': _freteIndex,
      'pagamento': _pagamento,
    };
  }

  @override
  void dispose() {
    widget.onFormDataToSave?.call(_getFormDataMap());
    _nome.dispose();
    _cpf.dispose();
    _email.dispose();
    _tel.dispose();
    _cep.dispose();
    _rua.dispose();
    _numero.dispose();
    _bairro.dispose();
    _cidade.dispose();
    _estado.dispose();
    _complemento.dispose();
    _obs.dispose();
    _cupomCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic> _customerPayload() {
    final enderecoFmt =
        'CEP ${_cep.text.trim()} - ${_rua.text.trim()}, ${_numero.text.trim()} - ${_bairro.text.trim()}, ${_cidade.text.trim()}'
        '${_complemento.text.trim().isNotEmpty ? ' (${_complemento.text.trim()})' : ''}';
    // Email em lowercase para bater com a query do perfil (getPedidosDoCliente)
    final email = _email.text.trim();
    return {
      'nome': _nome.text.trim(),
      'cpf': _cpf.text.trim(),
      'email': email.isEmpty ? '' : email.toLowerCase(),
      'telefone': _tel.text.trim(),
      'endereco': {
        'cep': _cep.text.trim(),
        'rua': _rua.text.trim(),
        'numero': _numero.text.trim(),
        'bairro': _bairro.text.trim(),
        'cidade': _cidade.text.trim(),
        'estado': _estado.text.trim(),
        'complemento': _complemento.text.trim(),
      },
      'enderecoFormatado': enderecoFmt,
    };
  }

  void _limparErroCampo(String campo) {
    if (_camposComErro.contains(campo)) {
      setState(() {
        _camposComErro.remove(campo);
        if (_camposComErro.isEmpty) _erroValidacao = null;
      });
    }
  }

  bool _validarCampos() {
    _camposComErro.clear();
    _erroValidacao = null;

    final obrigatorios = <String>[];
    final cpf = _cpf.text.replaceAll(RegExp(r'[^0-9]'), '');
    final cep = _cep.text.replaceAll(RegExp(r'[^0-9]'), '');
    final tel = _tel.text.replaceAll(RegExp(r'[^0-9]'), '');

    if (_nome.text.trim().isEmpty) {
      _camposComErro.add('nome');
      obrigatorios.add('Nome');
    }
    if (_cpf.text.trim().isEmpty) {
      _camposComErro.add('cpf');
      obrigatorios.add('CPF');
    } else if (cpf.length != 11) {
      _camposComErro.add('cpf');
      _erroValidacao = 'CPF deve ter 11 dígitos.';
    }
    if (_tel.text.trim().isEmpty) {
      _camposComErro.add('tel');
      obrigatorios.add('Telefone');
    } else if (tel.length < 10) {
      _camposComErro.add('tel');
      _erroValidacao ??= 'Telefone deve ter no mínimo 10 dígitos.';
    }
    if (_cep.text.trim().isEmpty) {
      _camposComErro.add('cep');
      obrigatorios.add('CEP');
    } else if (cep.length != 8) {
      _camposComErro.add('cep');
      _erroValidacao ??= 'CEP deve ter 8 dígitos.';
    }
    if (_rua.text.trim().isEmpty) {
      _camposComErro.add('rua');
      obrigatorios.add('Rua');
    }
    if (_numero.text.trim().isEmpty) {
      _camposComErro.add('numero');
      obrigatorios.add('Número');
    }
    if (_bairro.text.trim().isEmpty) {
      _camposComErro.add('bairro');
      obrigatorios.add('Bairro');
    }
    if (_cidade.text.trim().isEmpty) {
      _camposComErro.add('cidade');
      obrigatorios.add('Cidade');
    }
    if (_estado.text.trim().isEmpty) {
      _camposComErro.add('estado');
      obrigatorios.add('UF');
    }

    if (_erroValidacao == null && obrigatorios.isNotEmpty) {
      _erroValidacao = obrigatorios.length == 1
          ? 'Preencha o campo ${obrigatorios.first}.'
          : 'Preencha todos os campos obrigatórios: ${obrigatorios.join(', ')}.';
    }

    if (_camposComErro.isNotEmpty) {
      widget
          .showSnack(_erroValidacao ?? 'Verifique os dados e tente novamente.');
      setState(() {});
      return false;
    }
    return true;
  }

  /// Converte modelo Cupom para o mapa usado em _cupomAplicado (inclui id para registrarUso).
  Map<String, dynamic> _cupomMapFromCupom(Cupom c) {
    return {
      'id': c.id,
      'codigo': c.codigo,
      'code': c.codigo,
      'tipo': c.tipo == 'percentual' ? 'percent' : 'valor',
      'valor': c.valor,
      'aplicarEm': c.aplicarEm,
      'freteGratis': c.freteGratis,
      'valorMinimo': c.valorMinimo,
      'dataFim': c.dataFim,
      'ativo': c.ativo,
    };
  }

  Future<void> _aplicarCupom() async {
    final code = _cupomCtrl.text.trim().toUpperCase();
    if (code.isEmpty) {
      widget.showSnack('Digite um cupom para aplicar.');
      return;
    }

    // ✨ Cupons de prêmio NÃO podem ser usados na mesma compra
    if (code.startsWith('PREMIO-')) {
      widget.showSnack(
        '⚠️ Cupons de prêmio só podem ser usados em compras futuras!\n\n'
        'Finalize esta compra primeiro e use o cupom na próxima.',
      );
      return;
    }

    // 1) Tenta cupom normal da loja (Firestore/config)
    Map<String, dynamic>? found;
    for (final c in widget.cupons) {
      final cod =
          (c['codigo'] ?? c['code'] ?? '').toString().toUpperCase().trim();
      final ativo = c['ativo'] != false;
      if (ativo && cod == code) {
        found = c;
        break;
      }
    }

    // 2) Se não encontrou, tenta cupom da roleta no perfil do cliente (clientes_catalogo)
    if (found == null) {
      final clienteLogado = await ClienteAuthService.getClienteLogado();
      if (clienteLogado != null) {
        final email = (clienteLogado['email'] ?? '').toString().trim();
        if (email.isNotEmpty) {
          final cuponsRoleta = await ClienteAuthService.getCuponsRoleta(
            lojaId: widget.lojaId,
            email: email,
          );
          for (final c in cuponsRoleta) {
            final cod = (c['codigo'] ?? '').toString().toUpperCase().trim();
            final usado = c['usado'] == true;
            if (!usado && cod == code) {
              final tipo = (c['tipo'] ?? 'desconto').toString();
              final valor = (c['desconto'] as num?)?.toDouble() ?? 0.0;
              found = {
                'codigo': c['codigo'],
                'code': c['codigo'],
                'tipo': tipo == 'frete_gratis' ? 'frete_gratis' : 'percent',
                'valor': valor,
                'aplicarEm': 'total',
                'freteGratis': tipo == 'frete_gratis',
                'dataExpiracao': c['dataExpiracao'],
                'origem': 'roleta_sorte',
              };
              break;
            }
          }
        }
      }
    }

    // 3) Cupom de indicação (cupons_clientes) – destinatário ganha na 1ª compra, usa na próxima
    if (found == null) {
      final clienteLogado = await ClienteAuthService.getClienteLogado();
      final clienteIdCatalogo = (clienteLogado?['clienteId'] ?? '').toString().trim();
      if (clienteIdCatalogo.isNotEmpty) {
        final cuponsCliente = await CuponsService.buscarCuponsValidos(
          lojaId: widget.lojaId,
          clienteId: clienteIdCatalogo,
        );
        for (final c in cuponsCliente) {
          if ((c.codigo).toUpperCase().trim() == code) {
            final tipo = c.tipo == TipoCupom.freteGratis
                ? 'frete_gratis'
                : (c.tipo == TipoCupom.descontoFixo ? 'valor' : 'percent');
            final valor = c.valorDesconto ?? 0.0;
            found = {
              'id': c.id,
              'codigo': c.codigo,
              'code': c.codigo,
              'tipo': tipo,
              'valor': valor,
              'aplicarEm': 'total',
              'freteGratis': c.tipo == TipoCupom.freteGratis,
              'dataValidade': c.dataValidade,
              'origem': 'cupom_cliente',
            };
            break;
          }
        }
      }
    }

    if (found == null) {
      widget.showSnack('Cupom inválido, inativo ou expirado.');
      return;
    }

    // Validar data de validade ao aplicar (evita uso de cupom expirado)
    final now = DateTime.now();
    final df = found['dataFim'] ?? found['validade'] ?? found['dataValidade'] ?? found['dataExpiracao'];
    if (df != null) {
      DateTime? fim;
      if (df is Timestamp) {
        fim = df.toDate();
      } else if (df is DateTime) {
        fim = df;
      } else if (df is String) {
        fim = DateTime.tryParse(df);
      }
      if (fim != null && now.isAfter(fim)) {
        widget.showSnack(
            'Cupom expirado. Validade: ${fim.toString().substring(0, 10)}.');
        return;
      }
    }

    // Validar valor mínimo do cupom (se existir)
    final vMin = found['valorMinimo'] ?? found['valor_minimo'];
    final valorMinimo = (vMin is num) ? vMin.toDouble() : null;
    if (valorMinimo != null && valorMinimo > 0 && _subtotal < valorMinimo) {
      widget.showSnack(
          'Cupom exige compra mínima de R\$ ${valorMinimo.toStringAsFixed(2)}.');
      return;
    }

    setState(() {
      _cupomAplicado = asMapDeep(found);
    });
    // Se o cupom veio do config (sem id), buscar id no Firestore para poder registrar uso depois (só cupons da loja)
    if (_cupomAplicado!['id'] == null && _cupomAplicado!['origem'] != 'roleta_sorte') {
      final cupom = await CupomDescontoService().buscarPorCodigo(widget.lojaId, code);
      if (cupom != null && mounted) {
        setState(() {
          _cupomAplicado!['id'] = cupom.id;
        });
      }
    }

    widget.showSnack('Cupom aplicado: $code');
  }

  @override
  Widget build(BuildContext context) {
    if (_fretesLocal.isEmpty) {
      return const Center(
        child: Text(
          'Nenhuma opção de frete configurada.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    // ✅ segurança: garante índice válido mesmo após atualizar a lista
    if (_freteIndex < 0 || _freteIndex >= _fretesLocal.length) {
      _freteIndex = 0;
    }

    final frete = _fretesLocal[_freteIndex];

    // 🔍 DEBUG: Log do frete selecionado
    logD(
        '💰 [TOTAL] Frete selecionado (índice $_freteIndex): ${frete['nome']}');
    logD('💰 [TOTAL] Frete completo: $frete');
    logD(
        '💰 [TOTAL] Campo valor bruto: ${frete['valor']} (tipo: ${frete['valor'].runtimeType})');

    final double valorFreteOriginal =
        (frete['valor'] as num?)?.toDouble() ?? 0.0;
    final double valorFreteFinal = _freteGratis ? 0.0 : valorFreteOriginal;

    logD('💰 [TOTAL] Valor frete original: R\$ $valorFreteOriginal');
    logD(
        '💰 [TOTAL] Valor frete final: R\$ $valorFreteFinal (frete grátis: $_freteGratis)');
    logD('💰 [TOTAL] Subtotal: R\$ $_subtotal (PIX: R\$ $_subtotalPix)');

    final double descontoProdutos = _descontoCupomProdutos;
    final double total =
        ((_subtotalConformePagamento + valorFreteFinal) - descontoProdutos)
            .clamp(0.0, double.infinity);

    logD(
        '💰 [TOTAL] Total calculado: R\$ $_subtotalConformePagamento + R\$ $valorFreteFinal - R\$ $descontoProdutos = R\$ $total');

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (_, c) {
            final isWide = c.maxWidth > 1040;
            return SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1300),
                  child: isWide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _left(context)),
                            const SizedBox(width: 18),
                            Expanded(child: _centerForm(context)),
                            const SizedBox(width: 18),
                            SizedBox(
                              width: 420,
                              child: _right(
                                context,
                                total,
                                frete,
                                valorFreteOriginal,
                                descontoProdutos,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            _left(context),
                            const SizedBox(height: 16),
                            _centerForm(context),
                            const SizedBox(height: 16),
                            _right(
                              context,
                              total,
                              frete,
                              valorFreteOriginal,
                              descontoProdutos,
                            ),
                          ],
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Calcula peso total do carrinho com seleção inteligente de embalagem
  /// Retorna: {'pesoTotal': double, 'embalagem': Map, 'pesoEmbalagem': double}
  Future<Map<String, dynamic>> _calcularPesoComEmbalagem(
      List<Map<String, dynamic>> items) async {
    // 1. Carregar configurações de embalagens
    List<Map<String, dynamic>> embalagens = [];
    try {
      if (!Hive.isBoxOpen('config')) {
        await Hive.openBox('config');
      }
      final configBox = Hive.box('config');
      final rawEmbalagens = configBox.get('embalagens');

      if (rawEmbalagens is List && rawEmbalagens.isNotEmpty) {
        embalagens = rawEmbalagens.map<Map<String, dynamic>>((e) {
          if (e is Map) {
            return {
              'id': e['id']?.toString() ?? '',
              'nome': e['nome']?.toString() ?? '',
              'peso': (e['peso'] is num) ? (e['peso'] as num).toDouble() : 0.0,
              'tamanho':
                  (e['tamanho'] is num) ? (e['tamanho'] as num).toInt() : 0,
              'altura':
                  (e['altura'] is num) ? (e['altura'] as num).toDouble() : 10.0,
              'largura': (e['largura'] is num)
                  ? (e['largura'] as num).toDouble()
                  : 20.0,
              'comprimento': (e['comprimento'] is num)
                  ? (e['comprimento'] as num).toDouble()
                  : 30.0,
            };
          }
          return {
            'id': '',
            'nome': '',
            'peso': 0.0,
            'tamanho': 0,
            'altura': 10.0,
            'largura': 20.0,
            'comprimento': 30.0,
          };
        }).toList();
      } else {
        // Embalagens padrão
        embalagens = [
          {
            'id': 'padrao',
            'nome': 'Padrão',
            'peso': 50.0,
            'tamanho': 1,
            'altura': 10.0,
            'largura': 20.0,
            'comprimento': 30.0
          },
          {
            'id': 'pequena',
            'nome': 'Pequena',
            'peso': 100.0,
            'tamanho': 2,
            'altura': 15.0,
            'largura': 25.0,
            'comprimento': 35.0
          },
          {
            'id': 'media',
            'nome': 'Média',
            'peso': 200.0,
            'tamanho': 3,
            'altura': 20.0,
            'largura': 30.0,
            'comprimento': 40.0
          },
          {
            'id': 'grande',
            'nome': 'Grande',
            'peso': 350.0,
            'tamanho': 4,
            'altura': 25.0,
            'largura': 35.0,
            'comprimento': 45.0
          },
        ];
      }
    } catch (e, st) {
      logE('❌ Erro ao carregar embalagens (type=${e.runtimeType})', error: e, st: st);
      embalagens = [
        {
          'id': 'padrao',
          'nome': 'Padrão',
          'peso': 50.0,
          'tamanho': 1,
          'altura': 10.0,
          'largura': 20.0,
          'comprimento': 30.0
        },
      ];
    }

    // 2. Calcular peso total dos produtos
    double pesoProdutos = 0.0;
    int maiorTamanho = 0;
    Map<String, dynamic>? embalagemMaior;

    for (final item in items) {
      final qty =
          CatalogEstoqueHelper.parseCartItemQuantidade(item['quantidade']);
      final peso = (item['peso'] as num?)?.toDouble() ?? 0.0;
      final tipoEmb = item['tipoEmbalagem'] as String? ?? 'padrao';

      // Soma peso dos produtos
      pesoProdutos += peso * qty;

      // Encontra embalagem deste produto
      final emb = embalagens.firstWhere(
        (e) => e['id'] == tipoEmb,
        orElse: () => embalagens.first,
      );

      final tamanho = safeInt(emb['tamanho']);
      if (tamanho > maiorTamanho) {
        maiorTamanho = tamanho;
        embalagemMaior = emb;
      }
    }

    // 3. Usa embalagem padrão se nenhuma foi encontrada
    if (embalagemMaior == null && embalagens.isNotEmpty) {
      embalagemMaior = embalagens.first;
    }

    final pesoEmbalagem = safeDouble(embalagemMaior?['peso'], fallback: 50.0);
    final alturaEmb = safeDouble(embalagemMaior?['altura'], fallback: 10.0);
    final larguraEmb = safeDouble(embalagemMaior?['largura'], fallback: 20.0);
    final comprimentoEmb = safeDouble(embalagemMaior?['comprimento'], fallback: 30.0);
    final pesoTotal = pesoProdutos + pesoEmbalagem;

    logD(
        '📦 [PESO] Produtos: ${pesoProdutos}g + Embalagem ${embalagemMaior?['nome']}: ${pesoEmbalagem}g = Total: ${pesoTotal}g');
    logD(
        '📏 [DIMENSÕES] Embalagem ${embalagemMaior?['nome']}: ${alturaEmb}cm (A) x ${larguraEmb}cm (L) x ${comprimentoEmb}cm (C)');
    logD(
        '📏 [DIMENSÕES DETALHADAS] Altura: $alturaEmb | Largura: $larguraEmb | Comprimento: $comprimentoEmb');

    return {
      'pesoTotal': pesoTotal,
      'pesoProdutos': pesoProdutos,
      'pesoEmbalagem': pesoEmbalagem,
      'altura': alturaEmb,
      'largura': larguraEmb,
      'comprimento': comprimentoEmb,
      'embalagem': embalagemMaior,
    };
  }

  // -------------------------------------------------------------
// MODAL PARA SELECIONAR FRETE
// -------------------------------------------------------------
  Future<void> _mostrarOpcoesDeFrete(BuildContext context) async {
    // Se CEP já tem 8 dígitos e só temos fretes manuais, recalcular para buscar Melhor Envio/SuperFrete
    final cep = _cep.text.replaceAll(RegExp(r'[^0-9]'), '');
    // Considerar "só manuais" quando nenhum item veio de API (melhor_envio, frenet, correios, superfrete)
    final soManuais = _fretesLocal.every((f) {
      final plat = (f['plataforma'] ?? '').toString();
      return plat.isEmpty || !['melhor_envio', 'frenet', 'correios', 'superfrete'].contains(plat);
    });
    if (cep.length == 8 && soManuais && widget.items.isNotEmpty) {
      await _recalcularFreteSelecionado();
      if (!mounted) return;
      setState(() {});
    }
    if (!context.mounted) return;

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgModal = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textoPrincipal = isDark ? Colors.white : Colors.black87;
    final textoSecundario = isDark ? Colors.white70 : Colors.black54;
    final borderColor = isDark ? Colors.white12 : Colors.black12;
    final selectedBg =
        isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF5F5F5);
    final selectedBorder = theme.colorScheme.primary;

    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: bgModal,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.65,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Título
                  Row(
                    children: [
                      Icon(Icons.local_shipping,
                          color: textoPrincipal, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Selecione a forma de entrega',
                          style: TextStyle(
                            color: textoPrincipal,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Lista de opções de frete (com altura limitada e scroll)
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(_fretesLocal.length, (i) {
                          final f = _fretesLocal[i];
                          final nome =
                              (f['nome'] ?? f['label'] ?? 'Frete').toString();
                          final valor = (f['valor'] as num?)?.toDouble() ?? 0.0;
                          final prazo = (f['prazo'] ?? '').toString();
                          final plataforma =
                              (f['plataforma'] ?? f['tipo'] ?? '').toString();
                          final bool isSelected = i == _freteIndex;

                          // ✅ se o cupom dá frete grátis, mostra "Grátis" para o frete selecionado
                          final bool showGratis = isSelected
                              ? _freteGratis
                              : (f['freteGratis'] == true);
                          final precoTexto =
                              showGratis ? 'GRÁTIS' : 'R\$ ${_fmt2(valor)}';

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: InkWell(
                              onTap: () async {
                                // 🔍 DEBUG: Log da seleção
                                logD(
                                    '🖱️ [SELEÇÃO] Usuário clicou no frete: $nome (índice $i)');
                                logD(
                                    '🖱️ [SELEÇÃO] Valor do frete: R\$ $valor');
                                logD('🖱️ [SELEÇÃO] Frete completo: $f');

                                // Atualizar seleção
                                setState(() => _freteIndex = i);
                                setModalState(() {}); // Atualiza o modal também

                                logD(
                                    '✅ [SELEÇÃO] _freteIndex atualizado para: $_freteIndex');

                                // Recalcular frete
                                await _recalcularFreteSelecionado();
                                if (!mounted) return;
                                setState(() {});

                                // Fechar modal
                                if (!ctx.mounted) return;
                                Navigator.of(ctx).pop();
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected
                                        ? selectedBorder
                                        : borderColor,
                                    width: isSelected ? 2 : 1,
                                  ),
                                  color: isSelected
                                      ? selectedBg
                                      : Colors.transparent,
                                ),
                                child: Row(
                                  children: [
                                    // Ícone
                                    Icon(
                                      valor == 0 || showGratis
                                          ? Icons.store_outlined
                                          : Icons.local_shipping_outlined,
                                      color: isSelected
                                          ? selectedBorder
                                          : textoSecundario,
                                      size: 28,
                                    ),
                                    const SizedBox(width: 16),

                                    // Informações
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  nome,
                                                  style: TextStyle(
                                                    color: textoPrincipal,
                                                    fontSize: 16,
                                                    fontWeight: isSelected
                                                        ? FontWeight.w700
                                                        : FontWeight.w600,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: plataforma ==
                                                          'melhor_envio'
                                                      ? Colors.green.shade100
                                                      : plataforma == 'frenet'
                                                          ? Colors.blue.shade100
                                                          : plataforma ==
                                                                  'correios'
                                                              ? Colors.orange
                                                                  .shade100
                                                              : plataforma ==
                                                                      'superfrete'
                                                                  ? Colors.teal
                                                                      .shade100
                                                                  : Colors.grey
                                                                      .shade200,
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  plataforma == 'melhor_envio'
                                                      ? 'ME'
                                                      : plataforma == 'frenet'
                                                          ? 'FR'
                                                          : plataforma ==
                                                                  'correios'
                                                              ? 'COR'
                                                              : plataforma ==
                                                                      'superfrete'
                                                                  ? 'SF'
                                                                  : 'MAN',
                                                  style: TextStyle(
                                                    color: plataforma ==
                                                            'melhor_envio'
                                                        ? Colors.green.shade800
                                                        : plataforma == 'frenet'
                                                            ? Colors
                                                                .blue.shade800
                                                            : plataforma ==
                                                                    'correios'
                                                                ? Colors.orange
                                                                    .shade800
                                                                : plataforma ==
                                                                        'superfrete'
                                                                    ? Colors
                                                                        .teal
                                                                        .shade800
                                                                    : Colors
                                                                        .grey
                                                                        .shade700,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          if (prazo.isNotEmpty)
                                            Text(
                                              prazo,
                                              style: TextStyle(
                                                color: textoSecundario,
                                                fontSize: 13,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                        ],
                                      ),
                                    ),

                                    // Preço
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          precoTexto,
                                          style: TextStyle(
                                            color: showGratis
                                                ? Colors.green
                                                : textoPrincipal,
                                            fontSize: 17,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        if (isSelected)
                                          Container(
                                            margin:
                                                const EdgeInsets.only(top: 4),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: selectedBorder,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: const Text(
                                              'Selecionado',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // -------------------------------------------------------------
// FRETE DINÂMICO (Melhor Envio / Correios / Frenet via FreteService)
// -------------------------------------------------------------
  Future<void> _recalcularFreteSelecionado() async {
    final cepDestino = _cep.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (cepDestino.length < 8) {
      // CEP ainda incompleto -> não chama API
      return;
    }

    if (widget.items.isEmpty) return;

    try {
      // ✅ Calcular peso total com seleção inteligente de embalagem
      final pesoCalc = await _calcularPesoComEmbalagem(widget.items);
      double pesoTotal = pesoCalc['pesoTotal'] as double;

      // ✅ Pegar dimensões da embalagem maior selecionada
      double altura = (pesoCalc['altura'] as num?)?.toDouble() ?? 10.0;
      double largura = (pesoCalc['largura'] as num?)?.toDouble() ?? 20.0;
      double comprimento =
          (pesoCalc['comprimento'] as num?)?.toDouble() ?? 30.0;

      // Calcular valor total do carrinho
      double valorTotal = 0.0;
      for (final item in widget.items) {
        final qty =
            CatalogEstoqueHelper.parseCartItemQuantidade(item['quantidade']);
        final price =
            (item['preco'] as num?)?.toDouble() ?? 0.0; // ✅ CORRIGIDO: 'preco'
        valorTotal += price * qty;
      }

      // ✅ Garantir peso mínimo
      if (pesoTotal < 300) pesoTotal = 300.0;

      logD(
          '🚚 [CATALOGO] Calculando frete - CEP: $cepDestino, Peso: ${pesoTotal}g, Valor: R\$ $valorTotal');
      logD(
          '📦 [CATALOGO] Dimensões: ${altura}cm (A) x ${largura}cm (L) x ${comprimento}cm (C)');

      // ✅ Chamar FreteService.calcularFrete()
      final opcoesFretes = await FreteService.calcularFrete(
        lojaId: widget.lojaId,
        cep: cepDestino,
        peso: pesoTotal,
        valorDeclarado: valorTotal,
        altura: altura,
        largura: largura,
        comprimento: comprimento,
      );

      // ✅ Limpar e reconstruir _fretesLocal
      _fretesLocal.clear();

      // ✅ FIX: Não adicionar fretes manuais do widget.fretes aqui, pois o FreteService
      // já retorna os fretes manuais junto com as opções das APIs.
      // Isso evita duplicação de "Retirada" e "Entrega local"

      // Adicionar todas as opções retornadas pela API (que já inclui manuais)
      if (opcoesFretes.isNotEmpty) {
        logD(
            '📦 [CATALOGO] Processando ${opcoesFretes.length} opções da API:');
        for (int idx = 0; idx < opcoesFretes.length; idx++) {
          final opcao = opcoesFretes[idx];
          final nome = opcao['nome'] ?? 'Frete';

          // ✅ FIX: Conversão robusta do valor
          // DEBUG: Dump completo do objeto opcao
          logD('   [$idx] DUMP COMPLETO da opção: $opcao');

          double valor = 0.0;
          final valorRaw = opcao['valor'];
          logD(
              '   [$idx] Valor bruto recebido: $valorRaw (tipo: ${valorRaw.runtimeType})');

          if (valorRaw is num) {
            valor = valorRaw.toDouble();
            logD('   [$idx] ✅ Convertido de num para double: $valor');
          } else if (valorRaw is String) {
            valor = double.tryParse(valorRaw) ?? 0.0;
            logD('   [$idx] ✅ Convertido de String para double: $valor');
          } else {
            logD('   [$idx] ❌ Tipo desconhecido! Usando 0.0');
          }

          final prazo = opcao['prazo'] ?? 0;
          final empresa = opcao['empresa'] ?? '';
          final plataforma = opcao['plataforma'] ?? 'manual';

          logD(
              '   [$idx] API retornou: $nome - R\$ $valor - $prazo dias - $empresa - Plataforma: $plataforma');

          // ⚠️ ALERTA: Se o valor for zero, pode indicar erro na API
          if (valor == 0.0 && plataforma != 'manual') {
            logW('   ⚠️⚠️⚠️ [$idx] ATENÇÃO: Valor zero detectado!');
            logW('   ⚠️ Opção completa: $opcao');
            logW('   ⚠️ Campo \'valor\': ${opcao['valor']}');
            logW('   ⚠️ Todos os campos: ${opcao.keys.toList()}');
          }

          // Usar o campo 'plataforma' diretamente (mais confiável)
          String tipoNormalizado = plataforma;

          final freteItem = {
            'nome': nome,
            'label': nome,
            'valor': valor,
            'prazo': prazo > 0 ? '$prazo dias úteis' : '',
            'tipo': tipoNormalizado,
            'empresa': empresa,
            'plataforma': plataforma,
            'freteGratis': false,
            if (opcao['service_id'] != null) 'service_id': opcao['service_id'],
          };

          // ✅ Filtrar fretes zerados de APIs (exceto manuais que podem ser retirada grátis)
          if (valor == 0.0 && plataforma != 'manual') {
            logW(
                '   [$idx] ⚠️ IGNORANDO frete zerado da API: $nome ($plataforma)');
            continue; // Pula este frete
          }

          logD(
              '   [$idx] Adicionando: ${freteItem['nome']} - R\$ ${freteItem['valor']} (${freteItem['plataforma']})');
          _fretesLocal.add(freteItem);
        }
      }

      // ✅ Manter índice selecionado pelo usuário, ou selecionar primeira opção de API
      // Só resetar o índice se for o primeiro cálculo (índice ainda não foi setado pelo usuário)
      if (_freteIndex < 0 || _freteIndex >= _fretesLocal.length) {
        _freteIndex = 0;
        for (int i = 0; i < _fretesLocal.length; i++) {
          final plat = (_fretesLocal[i]['plataforma'] ?? 'manual').toString();
          if (plat != 'manual') {
            _freteIndex = i;
            logD(
                '📍 [CATALOGO] Selecionando primeira opção de API: ${_fretesLocal[i]['nome']} (índice $i)');
            break;
          }
        }

        // Se todas forem manuais, fica no índice 0
        if (_freteIndex == 0 &&
            _fretesLocal.isNotEmpty &&
            (_fretesLocal.first['plataforma'] ?? 'manual') == 'manual') {
          logD(
              '📍 [CATALOGO] Todas as opções são manuais. Mantendo índice 0.');
        }
      } else {
        logD(
            '📍 [CATALOGO] Mantendo seleção do usuário: ${_fretesLocal[_freteIndex]['nome']} (índice $_freteIndex)');
      }

      logD(
          '✅ [CATALOGO] Frete calculado com sucesso! Opções: ${opcoesFretes.length}');
      logD(
          '📊 [CATALOGO] _fretesLocal após atualização: ${_fretesLocal.length} itens');
      logD('📍 [CATALOGO] _freteIndex: $_freteIndex');
      for (int i = 0; i < _fretesLocal.length; i++) {
        final f = _fretesLocal[i];
        logD('   [$i] ${f['nome']} - R\$ ${f['valor']} (${f['tipo']})');
      }

      if (!mounted) return;
      setState(() {});
    } catch (e, st) {
      logE('❌ [CATALOGO] Erro ao calcular frete (type=${e.runtimeType})', error: e, st: st);
      widget.showSnack('Erro ao calcular frete. Usando valor padrão.');
    }
  }

  Future<void> _removeItemAndRefresh(int index) async {
    // remove no pai (seu _removeFromCart)
    widget.onRemove(index);

    if (!mounted) return;

    // força rebuild do BottomSheet (senão ele não atualiza)
    setState(() {});

    // se CEP já estiver completo, recalcula frete automaticamente
    final cepDestino = _cep.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (cepDestino.length == 8 && widget.items.isNotEmpty) {
      await _recalcularFreteSelecionado();
      if (!mounted) return;
      setState(() {});
    }
  }

// ---------------------------------------------------------------------
// BUSCAR ENDEREÇO AUTOMATICAMENTE PELO CEP (ViaCEP)
// ---------------------------------------------------------------------
  Future<void> _buscarEnderecoPorCep() async {
    final cep = _cep.text.replaceAll(RegExp(r'[^0-9]'), '');

    if (cep.length != 8) return;

    try {
      logD('🔍 [VIACEP] Buscando endereço para CEP: $cep');

      final response = await HttpClientHelper.get(
        Uri.parse('https://viacep.com.br/ws/$cep/json/'),
        timeout: HttpTimeouts.external,
      );

      if (response.statusCode == 200) {
        final data = asMap(jsonDecode(response.body));

        // Verificar se CEP é válido (API retorna "erro": true se inválido)
        if (data['erro'] == true || data['erro'] == 'true') {
          logD('❌ [VIACEP] CEP não encontrado');
          widget.showSnack('CEP não encontrado. Verifique o número digitado.');
          return;
        }

        // Preencher campos automaticamente
        setState(() {
          _rua.text = data['logradouro'] ?? '';
          _bairro.text = data['bairro'] ?? '';
          _cidade.text = data['localidade'] ?? '';
          _estado.text = data['uf'] ?? '';
        });

        logD(
            '✅ [VIACEP] Endereço preenchido: ${data['logradouro']}, ${data['bairro']}, ${data['localidade']}-${data['uf']}');
        widget.showSnack('Endereço preenchido automaticamente!');

        // Calcular frete automaticamente após preencher endereço
        if (widget.items.isNotEmpty) {
          await _recalcularFreteSelecionado();
        }
      } else {
        logW('⚠️ [VIACEP] Erro na API: ${response.statusCode}');
        widget.showSnack('Erro ao buscar CEP. Digite manualmente.');
      }
    } catch (e, st) {
      logE('❌ [VIACEP] Erro ao buscar endereço (type=${e.runtimeType})', error: e, st: st);
      widget.showSnack('Erro ao buscar CEP. Verifique sua conexão.');
    }
  }

// ---------------------------------------------------------------------
// COLUNA ESQUERDA – ITENS DO CARRINHO (visual premium)
// ---------------------------------------------------------------------
  Widget _left(BuildContext context) {
    final theme = Theme.of(context);
    final textStyleTitle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
      color: widget.textColor,
    );

    final productNameColor = widget.productNameColor ?? widget.textColor;
    final productPriceColor = widget.productPriceColor ?? widget.primary;

    return Card(
      color: widget.checkoutCardColor ?? widget.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha:0.45),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.primary.withValues(alpha:0.15),
                  ),
                  child: Icon(
                    Icons.shopping_bag_outlined,
                    size: 20,
                    color: widget.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Text('Itens do carrinho', style: textStyleTitle),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        widget.primary.withValues(alpha:0.24),
                        widget.primary.withValues(alpha:0.14),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${widget.items.length} item${widget.items.length == 1 ? '' : 's'}',
                    style: TextStyle(
                      color: widget.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Divider(
              height: 1,
              color: Colors.white.withValues(alpha:0.06),
            ),
            const SizedBox(height: 10),

            if (widget.items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 22),
                child: Row(
                  children: [
                    Icon(
                      Icons.remove_shopping_cart_outlined,
                      color: widget.textColor.withValues(alpha:0.5),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Seu carrinho está vazio.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: widget.textColor.withValues(alpha:0.7),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: widget.items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final item = widget.items[i];
                  final name = (item['name'] ?? item['nome'] ?? '').toString();

                  final rawImageUrl =
                      (item['imageUrl'] ?? '').toString().trim();
                  final imagensRaw = item['imagens'];

                  String fixedImageUrl = rawImageUrl;
                  if (fixedImageUrl.isEmpty &&
                      imagensRaw is List &&
                      imagensRaw.isNotEmpty) {
                    fixedImageUrl = imagensRaw.first.toString();
                  }

                  final qty = CatalogEstoqueHelper.parseCartItemQuantidade(
                      item['quantidade']);
                  final price = (item['preco'] as num?)?.toDouble() ??
                      0.0; // ✅ CORRIGIDO: 'preco'
                  final pctPix =
                      (item['percentualDescontoPix'] as num?)?.toDouble() ??
                          0.0;
                  final precoEfetivo =
                      (_pagamento.toUpperCase() == 'PIX' && pctPix > 0)
                          ? price * (1 - pctPix / 100)
                          : price;
                  final total = precoEfetivo * qty;

                  return Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withValues(alpha:0.06),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          widget.cardColor.withValues(alpha:0.98),
                          widget.cardColor.withValues(alpha:0.92),
                        ],
                      ),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(18),
                          ),
                          child: SizedBox(
                            width: 76,
                            height: 76,
                            child: CatalogImagePlaceholder(
                              url: fixedImageUrl,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 10,
                              horizontal: 2,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    color: productNameColor,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius:
                                            BorderRadius.circular(999),
                                        color: Colors.white
                                            .withValues(alpha:0.05),
                                      ),
                                      child: Text(
                                        'Qtd: $qty',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: widget.textColor
                                              .withValues(alpha:0.7),
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      'R\$ ${_fmt2(total)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14.5,
                                        color: productPriceColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remover item',
                          icon: Icon(
                            Icons.delete_outline,
                            color: Colors.redAccent.withValues(alpha:0.9),
                          ),
                          onPressed: () => _removeItemAndRefresh(i),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

// ---------------------------------------------------------------------
// COLUNA CENTRAL – DADOS DO CLIENTE (premium)
// ---------------------------------------------------------------------
  Widget _centerForm(BuildContext context) {
    final theme = Theme.of(context);

    InputDecoration deco(String label, {String? hint, String? campoKey}) {
      final hasError = campoKey != null && _camposComErro.contains(campoKey);
      const erroColor = Color(0xFFEF4444);
      return InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(
          color: Colors.white.withValues(alpha:0.5),
        ),
        labelStyle: TextStyle(
          color: hasError ? erroColor : Colors.white.withValues(alpha:0.8),
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        filled: true,
        fillColor: hasError
            ? erroColor.withValues(alpha:0.08)
            : (widget.checkoutFieldBg ??
                widget.cardColor.withValues(alpha:0.9)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: hasError ? erroColor : Colors.white.withValues(alpha:0.16),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: hasError ? erroColor : Colors.white.withValues(alpha:0.12),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: hasError ? erroColor : widget.primary,
            width: 1.5,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 10,
        ),
      );
    }

    return Theme(
      data: Theme.of(context).copyWith(
        textTheme: Theme.of(context).textTheme.apply(
              bodyColor: Colors.white,
              displayColor: Colors.white,
            ),
      ),
      child: Card(
        color: widget.checkoutCardColor ?? widget.cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
        ),
        elevation: 10,
        shadowColor: const Color.fromARGB(255, 9, 9, 9).withValues(alpha:0.55),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_erroValidacao != null) ...[
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha:0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFFEF4444).withValues(alpha:0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: Color(0xFFEF4444), size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _erroValidacao!,
                          style: const TextStyle(
                            color: Color(0xFFEF4444),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              // título
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.primary.withValues(alpha:0.15),
                    ),
                    child: Icon(
                      Icons.person_outline,
                      size: 20,
                      color: widget.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Dados do cliente',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: widget.textColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Nome + CPF
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _nome,
                      style: const TextStyle(color: Colors.white),
                      decoration: deco('Nome completo *', campoKey: 'nome'),
                      onChanged: (_) => _limparErroCampo('nome'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _cpf,
                      style: const TextStyle(color: Colors.white),
                      keyboardType: kKeyboardDecimal,
                      decoration: deco('CPF *', campoKey: 'cpf'),
                      onChanged: (_) => _limparErroCampo('cpf'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Email + Telefone
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: deco('E-mail (opcional)'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _tel,
                      keyboardType: TextInputType.phone,
                      decoration:
                          deco('Telefone / WhatsApp *', campoKey: 'tel'),
                      onChanged: (_) => _limparErroCampo('tel'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Endereço de entrega',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: widget.textColor.withValues(alpha:0.9),
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      setState(() {}); // Feedback imediato ao toque
                      final resultado = await _preencherDadosClienteLogado();
                      if (!mounted) return;
                      final String msg;
                      switch (resultado) {
                        case 'no_login':
                          msg = 'Faça login para usar seu último endereço.';
                          break;
                        case 'no_address':
                          msg =
                              'Nenhum endereço encontrado. É seu primeiro pedido nesta loja? Preencha o endereço abaixo.';
                          break;
                        case 'success_full':
                          msg =
                              'Dados preenchidos com o último endereço salvo.';
                          break;
                        case 'success_partial':
                          msg =
                              'Nome, e-mail e telefone preenchidos. Nenhum endereço salvo ainda — preencha o endereço abaixo.';
                          break;
                        case 'success_partial_cf_falhou':
                          msg =
                              'Dados básicos preenchidos. Não foi possível carregar o endereço salvo — verifique sua conexão ou preencha abaixo.';
                          break;
                        case 'error':
                        default:
                          msg =
                              'Não foi possível carregar os dados. Tente novamente ou preencha manualmente.';
                      }
                      // Sempre usar showSnack do catálogo para a mensagem aparecer no contexto correto (sheet em overlay)
                      widget.showSnack(msg);
                    },
                    icon: const Icon(Icons.history, size: 18),
                    label: const Text('Usar último endereço'),
                    style: TextButton.styleFrom(
                      foregroundColor: widget.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // CEP + Botão Calcular Frete
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _cep,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(8),
                      ],
                      onChanged: (v) {
                        _limparErroCampo('cep');
                        final cep = v.replaceAll(RegExp(r'[^0-9]'), '');
                        if (cep.length == 8) {
                          _buscarEnderecoPorCep();
                        }
                      },
                      keyboardType: kKeyboardDecimal,
                      decoration: deco('CEP *', campoKey: 'cep'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      final cep = _cep.text.replaceAll(RegExp(r'[^0-9]'), '');
                      if (cep.length == 8) {
                        await _recalcularFreteSelecionado();
                        if (!mounted) return;
                        setState(() {});
                        logD(
                            '🚚 [CATALOGO] Fretes disponíveis: ${_fretesLocal.length}');
                        if (_fretesLocal.isNotEmpty) {
                          widget.showSnack(
                              'Frete calculado! ${_fretesLocal.length} opções disponíveis.');
                        } else {
                          widget
                              .showSnack('Nenhuma opção de frete disponível.');
                        }
                      } else {
                        widget.showSnack('Digite um CEP válido com 8 dígitos');
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.local_shipping, size: 18),
                        SizedBox(width: 6),
                        Text('Calcular\nFrete',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Rua + Número
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _rua,
                      decoration: deco('Rua *', campoKey: 'rua'),
                      onChanged: (_) => _limparErroCampo('rua'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _numero,
                      keyboardType: kKeyboardDecimal,
                      decoration: deco('Número *', campoKey: 'numero'),
                      onChanged: (_) => _limparErroCampo('numero'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Bairro + Cidade + UF
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _bairro,
                      decoration: deco('Bairro *', campoKey: 'bairro'),
                      onChanged: (_) => _limparErroCampo('bairro'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _cidade,
                      decoration: deco('Cidade *', campoKey: 'cidade'),
                      onChanged: (_) => _limparErroCampo('cidade'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _estado,
                      decoration: deco('UF *', campoKey: 'estado'),
                      onChanged: (_) => _limparErroCampo('estado'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              TextField(
                controller: _complemento,
                decoration: deco('Complemento'),
              ),
              const SizedBox(height: 10),

              TextField(
                controller: _obs,
                maxLines: 2,
                decoration: deco('Observações (opcional)'),
              ),
            ],
          ),
        ),
      ),
    );
  }

// ---------------------------------------------------------------------
// COLUNA DIREITA – RESUMO + FRETE + PAGAMENTO + CUPOM (premium)
// ---------------------------------------------------------------------
  Widget _right(
    BuildContext context,
    double total,
    Map<String, dynamic> frete,
    double valorFreteOriginal,
    double descontoProdutos,
  ) {
    final theme = Theme.of(context);
    final freteLabel = _freteGratis
        ? 'Cupom de frete grátis'
        : (frete['nome'] ?? frete['label'] ?? 'Entrega').toString();

    // ✅ sempre usa o valor final (0 se grátis)
    final double valorFreteFinal = _freteGratis ? 0.0 : valorFreteOriginal;

    // ======================================================================
    // CORES DO CARRINHO — 100% configuráveis
    // ======================================================================
    final Color resumoBg = widget.checkoutCardColor ?? const Color(0xFF020617);

    final Color campoBg = widget.checkoutFieldBg ?? const Color(0xFF0F172A);

    final Color bordaCampo = widget.checkoutFieldBorder ?? Colors.white24;

    final Color textoCampo = widget.checkoutFieldTextColor ?? Colors.white;

    final Color textoLabel = widget.checkoutLabelColor ?? Colors.white;

    final Color textoTotal =
        widget.checkoutTotalColor ?? const Color(0xFF22C55E);

    final Color textoMutado = textoCampo.withValues(alpha:0.7);

    return Card(
      color: resumoBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
      ),
      elevation: 10,
      shadowColor: const Color.fromARGB(255, 9, 9, 9).withValues(alpha:0.55),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // HEADER + TOTAL
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: textoTotal,
                  ),
                  child: Text(
                    'Total R\$ ${_fmt2(total)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: Colors.white,
                    ),
                  ),
                ),
                const Spacer(),
              ],
            ),

            const SizedBox(height: 16),

            // BLOCO RESUMO
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF0F172A),
                    resumoBg.withValues(alpha:0.95),
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_pagamento.toUpperCase() == 'PIX' &&
                      _subtotalPix < _subtotal) ...[
                    _resumeRow('Subtotal (cartão)', _subtotal),
                    _resumeRow('Desconto PIX', -(_subtotal - _subtotalPix),
                        strOverride: '- R\$ ${_fmt2(_subtotal - _subtotalPix)}',
                        color: Colors.greenAccent),
                    _resumeRow('Subtotal produtos', _subtotalPix),
                  ] else
                    _resumeRow('Subtotal', _subtotalConformePagamento),

                  if (descontoProdutos > 0)
                    _resumeRow(
                      'Descontos',
                      -descontoProdutos,
                      highlight: true,
                      color: Colors.redAccent,
                    ),

                  // ✅ frete com label e valor corretos
                  _resumeRow(
                    freteLabel,
                    valorFreteFinal,
                    strOverride: _freteGratis
                        ? 'R\$ 0,00'
                        : 'R\$ ${_fmt2(valorFreteFinal)}',
                  ),

                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        'Total a pagar',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: textoCampo,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'R\$ ${_fmt2(total)}',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: textoTotal,
                          fontWeight: FontWeight.w800,
                          fontSize: 22,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ENTREGA
            Text(
              'Entrega',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: textoLabel,
              ),
            ),
            const SizedBox(height: 6),

            // ✅ Botão para abrir modal com opções de frete
            if (_fretesLocal.isNotEmpty)
              InkWell(
                onTap: () => _mostrarOpcoesDeFrete(context),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: bordaCampo),
                    color: campoBg,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.local_shipping_outlined,
                          color: textoCampo, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: () {
                          if (_freteIndex >= 0 &&
                              _freteIndex < _fretesLocal.length) {
                            final f = _fretesLocal[_freteIndex];
                            final nome =
                                (f['nome'] ?? f['label'] ?? '').toString();
                            final valor =
                                (f['valor'] as num?)?.toDouble() ?? 0.0;
                            final prazo = (f['prazo'] ?? '').toString();
                            final precoTexto =
                                _freteGratis ? 'Grátis' : 'R\$ ${_fmt2(valor)}';

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  nome,
                                  style: TextStyle(
                                    color: textoCampo,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$precoTexto${prazo.isNotEmpty ? ' • $prazo' : ''}',
                                  style: TextStyle(
                                    color: textoCampo.withValues(alpha:0.7),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            );
                          }
                          return Text(
                            'Selecionar frete',
                            style: TextStyle(color: textoCampo, fontSize: 15),
                          );
                        }(),
                      ),
                      Icon(Icons.keyboard_arrow_down,
                          color: textoCampo, size: 24),
                    ],
                  ),
                ),
              ),

            // ✅ Mensagem quando não há opções de frete
            if (_fretesLocal.isEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: bordaCampo),
                  color: campoBg,
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: textoCampo.withValues(alpha:0.6), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Calcule o frete digitando seu CEP acima',
                        style: TextStyle(
                            color: textoCampo.withValues(alpha:0.7),
                            fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 16),

            // PAGAMENTO
            Text(
              'Forma de pagamento',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: textoLabel,
              ),
            ),
            const SizedBox(height: 6),

            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: bordaCampo),
                color: campoBg,
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _pagamento,
                  isExpanded: true,
                  borderRadius: BorderRadius.circular(16),
                  dropdownColor: campoBg,
                  iconEnabledColor: textoCampo,
                  style: TextStyle(color: textoCampo),
                  items: const [
                    DropdownMenuItem(
                      value: 'PIX',
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text('PIX'),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'CARTAO',
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text('Cartão de crédito / débito'),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'DINHEIRO',
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text('Dinheiro'),
                      ),
                    ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _pagamento = v);
                  },
                ),
              ),
            ),

            const SizedBox(height: 18),

            // CUPOM
            Text(
              'Cupom de desconto',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: textoLabel,
              ),
            ),
            const SizedBox(height: 6),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _cupomCtrl,
                    style: TextStyle(color: textoCampo),
                    decoration: InputDecoration(
                      hintText: 'Digite o cupom',
                      hintStyle: TextStyle(color: textoMutado),
                      filled: true,
                      fillColor: campoBg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: bordaCampo),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: bordaCampo),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: widget.primary,
                          width: 1.4,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _aplicarCupom,
                  style: FilledButton.styleFrom(
                    backgroundColor: widget.primary,
                    foregroundColor: widget.buttonText,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text('Aplicar'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final cliente = await ClienteAuthService.getClienteLogado();
                final clienteId = cliente?['clienteId']?.toString();
                if (clienteId == null || clienteId.isEmpty) {
                  widget.showSnack(
                    'Faça login para escolher um cupom da lista de cupons ativos.',
                  );
                  return;
                }
                final valorPedido = _subtotalConformePagamento;
                if (!context.mounted) return;
                final cupomEscolhido = await mostrarModalSelecionarCupom(
                  context: context,
                  lojaId: widget.lojaId,
                  clienteId: clienteId,
                  valorPedido: valorPedido,
                );
                if (!mounted) return;
                if (cupomEscolhido != null) {
                  setState(() {
                    if (cupomEscolhido is Cupom) {
                      _cupomAplicado = _cupomMapFromCupom(cupomEscolhido);
                    } else if (cupomEscolhido is Map) {
                      _cupomAplicado =
                          Map<String, dynamic>.from(cupomEscolhido);
                    }
                  });
                  final codigo = cupomEscolhido is Cupom
                      ? cupomEscolhido.codigo
                      : (cupomEscolhido is Map
                              ? (cupomEscolhido['codigo']?.toString() ?? '')
                              : '');
                  widget.showSnack(
                    codigo.isNotEmpty
                        ? 'Cupom aplicado: $codigo'
                        : 'Cupom aplicado.',
                  );
                }
              },
              icon: const Icon(Icons.local_offer_outlined, size: 20),
              label: const Text('Selecionar cupom'),
              style: OutlinedButton.styleFrom(
                foregroundColor: widget.primary,
                side: BorderSide(color: widget.primary),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),

            if (_cupomAplicado != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    Icons.check_circle,
                    size: 18,
                    color: widget.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Cupom aplicado: '
                              '${(_cupomAplicado!['codigo'] ?? _cupomAplicado!['code'] ?? '')}'
                          .toString()
                          .toUpperCase(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: textoCampo,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            // Cupom da roleta (quando ganhou mas não está em cupom aplicado)
            if (_cupomRoletaCodigo != null && _cupomRoletaCodigo!.isNotEmpty && _cupomAplicado == null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.stars, size: 18, color: Colors.amber[700]),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Cupom da roleta: ${_cupomRoletaCodigo!.toUpperCase()}',
                      style: theme.textTheme.bodySmall?.copyWith(color: textoCampo),
                    ),
                  ),
                ],
              ),
            ],

            // ✨ ROLETA — só aparece quando ROLETA ativa (config/roleta_sorte). Campanha é função separada.
            Builder(
              builder: (context) {
                if (!_roletaAtiva) {
                  return const SizedBox.shrink();
                }
                logD('🎰 Verificando exibição da roleta:');
                logD('   _roletaAtiva: $_roletaAtiva');
                logD('   _roletaJaGirada: $_roletaJaGirada');
                logD(
                    '   _todosOsDadosPreenchidos: $_todosOsDadosPreenchidos');
                logD('   _podeExibirRoleta: $_podeExibirRoleta');

                if (_podeExibirRoleta) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 16),

                      // Aviso de que a roleta está disponível
                          Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.stars,
                                    color: Colors.black, size: 24),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Você completou seus dados! Gire a roleta e concorra a prêmios!',
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          RoletaWebWidgetV3(
                        lojaId: widget
                            .lojaId, // Usa widget.lojaId (dentro do _CarrinhoSheetWebState)
                        totalCarrinho: _subtotal,
                        clienteEmail: _email.text.trim().isEmpty
                            ? null
                            : _email.text.trim(),
                        onCupomGerado: () {
                          setState(() => _roletaJaGirada = true);
                          widget.onRoletaPremioGanho?.call(
                            jaGirada: true,
                            codigo: _cupomRoletaCodigo,
                            desconto: _cupomRoletaDesconto,
                            descricao: _premioRoletaDescricao,
                            freteGratis: _freteGratisRoleta,
                          );
                          widget.showSnack(
                              '🎉 Cupom gerado! Use na próxima compra.');
                        },
                        onCupomGeradoComDados: (codigo, desconto) {
                          final freteGratis = codigo == 'FRETE_GRATIS';
                          setState(() {
                            _roletaJaGirada = true;
                            _cupomRoletaCodigo = codigo;
                            _cupomRoletaDesconto = desconto;
                            if (freteGratis) _freteGratisRoleta = true;
                            if (freteGratis) {
                              widget.showSnack(
                                  '🎉 Frete grátis aplicado nesta compra!');
                            }
                          });
                          widget.onRoletaPremioGanho?.call(
                            jaGirada: true,
                            codigo: codigo,
                            desconto: desconto,
                            descricao: _premioRoletaDescricao,
                            freteGratis: freteGratis,
                          );
                          logD(
                              '💾 Cupom da roleta salvo: $codigo ($desconto%)');
                        },
                        onPremioGanho: (codigo, desconto, descricao) {
                          final freteGratis = codigo == 'FRETE_GRATIS';
                          setState(() {
                            _roletaJaGirada = true;
                            _cupomRoletaCodigo = codigo;
                            _cupomRoletaDesconto = desconto;
                            _premioRoletaDescricao = descricao;
                            if (freteGratis) _freteGratisRoleta = true;
                          });
                          widget.onRoletaPremioGanho?.call(
                            jaGirada: true,
                            codigo: codigo,
                            desconto: desconto,
                            descricao: descricao,
                            freteGratis: freteGratis,
                          );
                          logD(
                              '💾 Prêmio da roleta salvo: $codigo - $descricao');
                        },
                      ),
                    ],
                  );
                } else {
                  // Roleta ativa mas ainda não pode girar (falta preencher dados ou valor mínimo)
                  final atingiuValorMinimo = _subtotal >= _valorMinimoRoleta;

                  if (!_todosOsDadosPreenchidos && atingiuValorMinimo) {
                    // Atingiu valor mínimo mas precisa preencher dados
                    return Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              color: Colors.blue.shade700, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Complete todos os dados acima para liberar a Roleta da Sorte e concorrer a prêmios!',
                              style: TextStyle(
                                color: Colors.blue.shade700,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                }
                return const SizedBox.shrink();
              },
            ),

            const SizedBox(height: 22),

            // Banner de erro de pagamento (visível na tela do carrinho)
            if (_checkoutError != null && _checkoutError!.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline,
                        color: Colors.red.shade700, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _checkoutError!,
                        style:
                            TextStyle(color: Colors.red.shade900, fontSize: 14),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => setState(() => _checkoutError = null),
                    ),
                  ],
                ),
              ),
            ],

            // BOTÃO WHATSAPP
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: _processandoCheckout
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const FaIcon(
                        FontAwesomeIcons.whatsapp,
                        size: 18,
                      ),
                label: Text(_processandoCheckout
                    ? 'Processando...'
                    : 'Finalizar pelo WhatsApp'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                onPressed: _processandoCheckout
                    ? null
                    : () async {
                        // ⭐ VERIFICAR LOGIN OBRIGATÓRIO
                        final cliente =
                            await ClienteAuthService.getClienteLogado();
                        if (!mounted) return;
                        if (!context.mounted) return;
                        if (cliente == null) {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Login Necessário'),
                              content: const Text(
                                'Para finalizar sua compra, você precisa fazer login ou criar uma conta.\n\n'
                                'Assim você poderá:\n'
                                '• Receber cupons de desconto\n'
                                '• Concorrer a prêmios com números da sorte\n'
                                '• Acompanhar seus pedidos',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Cancelar'),
                                ),
                                ElevatedButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    if (!context.mounted) return;
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => LoginScreenCliente(
                                            lojaId: widget.lojaId),
                                      ),
                                    );
                                  },
                                  child: const Text('Fazer Login'),
                                ),
                              ],
                            ),
                          );
                          return;
                        }

                        if (!_validarCampos()) return;

                        // ✅ MARCA COMO PROCESSANDO
                        setState(() {
                          _processandoCheckout = true;
                        });
                        await Future.delayed(Duration.zero);

                        final cupomId = _cupomAplicado?['id'] as String?;
                          final clienteLogado = await ClienteAuthService.getClienteLogado();
                          final clienteId = clienteLogado?['clienteId']?.toString();

                          try {
                            final customer = _customerPayload();

                            // ✅ Pega o frete selecionado completo
                            final freteSelecionado = _fretesLocal.isNotEmpty &&
                                    _freteIndex >= 0 &&
                                    _freteIndex < _fretesLocal.length
                                ? _fretesLocal[_freteIndex]
                                : {
                                    'nome': 'Entrega',
                                    'valor': 0.0,
                                    'tipo': 'padrao'
                                  };

                            final nomeFretePedido = _freteGratis
                                ? 'Cupom de frete grátis'
                                : (freteSelecionado['nome'] ?? freteSelecionado['label'] ?? 'Entrega').toString();
                            final entrega = {
                              'nome': nomeFretePedido,
                              'valor': _freteGratis ? 0.0 : valorFreteOriginal,
                              'freteGratis': _freteGratis,
                              'tipo': freteSelecionado['tipo'] ?? 'padrao',
                              if (freteSelecionado['plataforma'] != null)
                                'plataforma': freteSelecionado['plataforma'],
                              if (freteSelecionado['service_id'] != null)
                                'service_id': freteSelecionado['service_id'],
                            };

                            await widget.onCheckoutWhatsapp(
                              customer: customer,
                              entrega: entrega,
                              pagamento: _pagamento,
                              observacao: _obs.text.trim(),
                              cupomRoletaCodigo: _cupomRoletaCodigo,
                              cupomRoletaDesconto: _cupomRoletaDesconto,
                              premioRoletaDescricao: _premioRoletaDescricao,
                              onSuccess: (String? pedidoId) async {
                                if (mounted) Navigator.pop(context);
                                if (cupomId != null &&
                                    clienteId != null &&
                                    cupomId.isNotEmpty &&
                                    clienteId.isNotEmpty) {
                                  CupomDescontoService().registrarUso(
                                    lojaId: widget.lojaId,
                                    cupomId: cupomId,
                                    clienteId: clienteId,
                                  );
                                }
                                // Cupom da roleta (perfil): marcar como usado para não poder usar de novo
                                if (_cupomAplicado != null &&
                                    _cupomAplicado!['origem'] == 'roleta_sorte') {
                                  final email = (clienteLogado?['email'] ?? '').toString().trim();
                                  final codigo = (_cupomAplicado!['codigo'] ?? _cupomAplicado!['code'] ?? '').toString();
                                  if (email.isNotEmpty && codigo.isNotEmpty) {
                                    await ClienteAuthService.marcarCupomRoletaComoUsado(
                                      lojaId: widget.lojaId,
                                      email: email,
                                      codigo: codigo,
                                    );
                                  }
                                }
                                // Cupom de indicação (cupons_clientes): marcar como usado e ativar cupom do indicador
                                if (_cupomAplicado != null &&
                                    _cupomAplicado!['origem'] == 'cupom_cliente') {
                                  final cupomClienteId = (_cupomAplicado!['id'] ?? '').toString();
                                  if (cupomClienteId.isNotEmpty && (pedidoId ?? '').isNotEmpty) {
                                    await CuponsService.usarCupom(
                                      lojaId: widget.lojaId,
                                      cupomId: cupomClienteId,
                                      pedidoId: pedidoId!,
                                    );
                                  }
                                }
                              },
                              showErrorInCart: (msg) {
                                if (mounted) setState(() => _checkoutError = msg);
                              },
                            );
                          } finally {
                          // ✅ DESMARCA APÓS PROCESSAMENTO
                          if (mounted) {
                            setState(() {
                              _processandoCheckout = false;
                            });
                          }
                        }
                      },
              ),
            ),

            // BOTÃO PAGAR COM PIX (chave PIX da loja - gateway pix ou whatsapp)
            if ((widget.checkoutGateway == 'pix' ||
                    widget.checkoutGateway == 'whatsapp') &&
                widget.pixKey.trim().isNotEmpty &&
                widget.onCheckoutPix != null &&
                _pagamento.toUpperCase() == 'PIX') ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: _processandoCheckout
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.pix),
                  label: Text(_processandoCheckout
                      ? 'Processando...'
                      : 'Pagar com PIX'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.teal,
                    side: const BorderSide(color: Colors.teal, width: 1.3),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onPressed: _processandoCheckout
                      ? null
                      : () async {
                          setState(() {
                            _processandoCheckout = true;
                            _checkoutError = null;
                          });
                          await Future.delayed(Duration.zero);
                          try {
                            final cliente =
                                await ClienteAuthService.getClienteLogado();
                            if (!mounted) return;
                            if (!context.mounted) return;
                            if (cliente == null) {
                              showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Login Necessário'),
                                  content: const Text(
                                    'Para finalizar sua compra, você precisa fazer login ou criar uma conta.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: const Text('Cancelar'),
                                    ),
                                    ElevatedButton(
                                      onPressed: () {
                                        Navigator.pop(ctx);
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => LoginScreenCliente(
                                                lojaId: widget.lojaId),
                                          ),
                                        );
                                      },
                                      child: const Text('Fazer Login'),
                                    ),
                                  ],
                                ),
                              );
                              return;
                            }
                            if (!_validarCampos()) return;
                            final customer = _customerPayload();
                            final freteSelecionado = _fretesLocal.isNotEmpty &&
                                    _freteIndex >= 0 &&
                                    _freteIndex < _fretesLocal.length
                                ? _fretesLocal[_freteIndex]
                                : {
                                    'nome': 'Entrega',
                                    'valor': 0.0,
                                    'tipo': 'padrao'
                                  };
                            final nomeFretePedidoPix = _freteGratis
                                ? 'Cupom de frete grátis'
                                : (freteSelecionado['nome'] ?? freteSelecionado['label'] ?? 'Entrega').toString();
                            final entrega = {
                              'nome': nomeFretePedidoPix,
                              'valor': _freteGratis ? 0.0 : valorFreteOriginal,
                              'freteGratis': _freteGratis,
                              'tipo': freteSelecionado['tipo'] ?? 'padrao',
                              if (freteSelecionado['plataforma'] != null)
                                'plataforma': freteSelecionado['plataforma'],
                              if (freteSelecionado['service_id'] != null)
                                'service_id': freteSelecionado['service_id'],
                            };
                            await widget.onCheckoutPix!(
                              customer: customer,
                              entrega: entrega,
                              valorTotal: total,
                              observacao: _obs.text.trim(),
                              cupomRoletaCodigo: _cupomRoletaCodigo,
                              cupomRoletaDesconto: _cupomRoletaDesconto,
                              premioRoletaDescricao: _premioRoletaDescricao,
                              showErrorInCart: (msg) {
                                if (mounted) {
                                  setState(() => _checkoutError = msg);
                                }
                              },
                            );
                            // Cupom da roleta (perfil): marcar como usado
                            if (_cupomAplicado != null &&
                                _cupomAplicado!['origem'] == 'roleta_sorte') {
                              final clientePix = await ClienteAuthService.getClienteLogado();
                              final emailPix = (clientePix?['email'] ?? '').toString().trim();
                              final codigoPix = (_cupomAplicado!['codigo'] ?? _cupomAplicado!['code'] ?? '').toString();
                              if (emailPix.isNotEmpty && codigoPix.isNotEmpty) {
                                await ClienteAuthService.marcarCupomRoletaComoUsado(
                                  lojaId: widget.lojaId,
                                  email: emailPix,
                                  codigo: codigoPix,
                                );
                              }
                            }
                          } finally {
                            if (mounted) {
                              setState(() => _processandoCheckout = false);
                            }
                          }
                        },
                ),
              ),
            ],
            // BOTÃO MERCADO PAGO / OUTROS GATEWAYS (mp, pagseguro, ton, infinitepay)
            if (widget.checkoutGateway != 'whatsapp' &&
                widget.checkoutGateway != 'pix' &&
                _pagamento.toUpperCase() != 'DINHEIRO') ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: _processandoCheckout
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _pagamento.toUpperCase() == 'PIX'
                              ? Icons.pix
                              : Icons.payment,
                        ),
                  label: Text(
                    _processandoCheckout
                        ? 'Processando...'
                        : (_pagamento.toUpperCase() == 'PIX'
                            ? 'Pagar com PIX'
                            : widget.checkoutButtonLabel),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: widget.textColor,
                    side: BorderSide(
                      color: widget.primary.withValues(alpha:0.8),
                      width: 1.3,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onPressed: _processandoCheckout
                      ? null
                      : () async {
                          // ⭐ EVITA MÚLTIPLAS VENDAS: desabilita botão durante processamento
                          setState(() {
                            _processandoCheckout = true;
                            _checkoutError = null;
                          });
                          // Força o Flutter a repintar o loading antes de iniciar o processamento pesado
                          await Future.delayed(Duration.zero);
                          try {
                            // ⭐ VERIFICAR LOGIN OBRIGATÓRIO
                            final cliente =
                                await ClienteAuthService.getClienteLogado();
                            if (!mounted) return;
                            if (!context.mounted) return;
                            if (cliente == null) {
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Login Necessário'),
                                  content: const Text(
                                    'Para finalizar sua compra, você precisa fazer login ou criar uma conta.\n\n'
                                    'Assim você poderá:\n'
                                    '• Receber cupons de desconto\n'
                                    '• Concorrer a prêmios com números da sorte\n'
                                    '• Acompanhar seus pedidos',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('Cancelar'),
                                    ),
                                    ElevatedButton(
                                      onPressed: () {
                                        Navigator.pop(context);
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => LoginScreenCliente(
                                                lojaId: widget.lojaId),
                                          ),
                                        );
                                      },
                                      child: const Text('Fazer Login'),
                                    ),
                                  ],
                                ),
                              );
                              return;
                            }

                            if (!_validarCampos()) return;
                            final customer = _customerPayload();

                            // ✅ Pega o frete selecionado completo
                            final freteSelecionado = _fretesLocal.isNotEmpty &&
                                    _freteIndex >= 0 &&
                                    _freteIndex < _fretesLocal.length
                                ? _fretesLocal[_freteIndex]
                                : {
                                    'nome': 'Entrega',
                                    'valor': 0.0,
                                    'tipo': 'padrao'
                                  };

                            final nomeFretePedidoMp = _freteGratis
                                ? 'Cupom de frete grátis'
                                : (freteSelecionado['nome'] ?? freteSelecionado['label'] ?? 'Entrega').toString();
                            final entrega = {
                              'nome': nomeFretePedidoMp,
                              'valor': _freteGratis ? 0.0 : valorFreteOriginal,
                              'freteGratis': _freteGratis,
                              'tipo': freteSelecionado['tipo'] ?? 'padrao',
                              if (freteSelecionado['plataforma'] != null)
                                'plataforma': freteSelecionado['plataforma'],
                              if (freteSelecionado['service_id'] != null)
                                'service_id': freteSelecionado['service_id'],
                            };

                            await widget.onCheckoutMercadoPago(
                              customer: customer,
                              entrega: entrega,
                              pagamento: _pagamento,
                              observacao: _obs.text.trim(),
                              cupomRoletaCodigo: _cupomRoletaCodigo,
                              cupomRoletaDesconto: _cupomRoletaDesconto,
                              premioRoletaDescricao: _premioRoletaDescricao,
                              showErrorInCart: (msg) {
                                if (mounted) {
                                  setState(() => _checkoutError = msg);
                                }
                              },
                            );
                            // Cupom da roleta (perfil): marcar como usado
                            if (_cupomAplicado != null &&
                                _cupomAplicado!['origem'] == 'roleta_sorte') {
                              final emailMp = (cliente['email'] ?? '').toString().trim();
                              final codigoMp = (_cupomAplicado!['codigo'] ?? _cupomAplicado!['code'] ?? '').toString();
                              if (emailMp.isNotEmpty && codigoMp.isNotEmpty) {
                                await ClienteAuthService.marcarCupomRoletaComoUsado(
                                  lojaId: widget.lojaId,
                                  email: emailMp,
                                  codigo: codigoMp,
                                );
                              }
                            }
                          } finally {
                            if (mounted) {
                              setState(() => _processandoCheckout = false);
                            }
                          }
                        },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // pequena linha do resumo numérico
  Widget _resumeRow(
    String label,
    double valor, {
    bool highlight = false,
    Color? color,
    String? strOverride,
  }) {
    final c = color ?? Colors.white.withValues(alpha:0.85);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha:0.7),
            ),
          ),
          const Spacer(),
          Text(
            strOverride ?? 'R\$ ${_fmt2(valor)}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
              color: c,
            ),
          ),
        ],
      ),
    );
  }
}

