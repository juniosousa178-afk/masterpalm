// lib/screens/public_catalog/widgets/carrinho_sheet_web.dart
// Carrinho/checkout em bottom sheet – extraído do public_catalog_screen.
//
// ÚNICO checkout do catálogo PÚBLICO (PublicCatalogScreen): loja online /loja/…,
// preview /loja_preview, app mobile. Não confundir com CatalogoScreen (rota /catalogo),
// que usa modal legado em catalago_screen.dart.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:hive/hive.dart';
import 'package:diacritic/diacritic.dart';

import 'package:flutter/services.dart';

import '../../../core/combo_configuravel_resumo.dart';
import '../../../core/logger.dart';
import '../../../core/safe_cast.dart';
import '../../../utils/http_client_helper.dart';
import '../../../utils/platform_adaptive.dart';
import '../../../utils/keyboard_utils.dart';
import '../../../models/cupom.dart';
import '../../../models/cupom_cliente.dart';
import '../../../services/cliente_auth_service.dart';
import '../../../services/cupom_desconto_service.dart';
import '../../../services/cupons_service.dart';
import '../../../services/frete_service.dart';
import '../../../widgets/selecionar_cupom_modal.dart'
    show mostrarModalSelecionarCupom;
import '../../../widgets/roleta_web_widget_v3.dart';
import 'package:master_palm/screens/auth/cadastro_screen_cliente.dart';
import 'catalog_cart_line_quantity_section.dart';
import 'catalog_image_placeholder.dart';
import '../catalog_estoque_helper.dart';
import '../catalog_cart_checkout_visual_config.dart';
import '../checkout_total_helper.dart';
import '../catalog_checkout_summary_tokens.dart';
import '../catalog_helpers.dart'
    show catalogIsPlausibleMpBuyerEmail, catalogIsValidCpfForMpPayer;
import 'catalog_first_purchase_coupon_dialog.dart';

// ==================== CARRINHO (BottomSheet) ====================

class CarrinhoSheetWeb extends StatefulWidget {
  final String lojaId; // 👈 NOVO
  final List<Map<String, dynamic>> items;

  /// Lista de produtos do catálogo (para teto de estoque e botões +/-).
  final List<Map<String, dynamic>> catalogProducts;
  final List<Map<String, dynamic>> fretes;
  final List<Map<String, dynamic>> cupons;
  final void Function(int index) onRemove;

  /// Altera a quantidade da linha [index]; retorna false se estoque insuficiente.
  final bool Function(int index, int newQuantity) onSetItemQuantity;

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
  final String freteMelhorEnvioModoExibicao;

  final Future<void> Function({
    required Map<String, dynamic> customer,
    required Map<String, dynamic> entrega,
    required String pagamento,
    String observacao,
    String? cupomRoletaCodigo,
    double? cupomRoletaDesconto,
    String? premioRoletaDescricao,
    String? cupomCodigo,
    String? cupomFreteCodigo,
    required double descontoCupom,
    required double valorTotalCheckout,
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
    String? cupomCodigo,
    String? cupomFreteCodigo,
    required double descontoCupom,
    required double valorTotalCheckout,
    void Function(String message)? showErrorInCart,
  }) onCheckoutMercadoPago;

  /// Callback para PIX manual (chave PIX da loja) - gera QR com valor e mostra dialog.
  /// [onPedidoCriado] chamado após criar pedido (para registrar uso de cupom).
  final Future<void> Function({
    required Map<String, dynamic> customer,
    required Map<String, dynamic> entrega,
    required double valorTotal,
    String observacao,
    String? cupomCodigo,
    String? cupomFreteCodigo,
    double desconto,
    String? cupomRoletaCodigo,
    double? cupomRoletaDesconto,
    String? premioRoletaDescricao,
    void Function(String message)? showErrorInCart,
    Future<void> Function(String? pedidoId)? onPedidoCriado,
  })? onCheckoutPix;

  /// Quando a loja tem MP no `payments` público, o fluxo de PIX é o do Mercado Pago
  /// (não o botão de chave estática, mesmo com gateway `whatsapp` + chave cadastrada).
  final bool pixPreferMercadoPago;

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

  /// Cores do card escuro de resumo (subtotal, frete, total). Se null, deriva dos demais checkout colors.
  final CatalogCheckoutSummaryTokens? checkoutSummaryStyle;

  /// Tokens visuais do carrinho (uiColors). Se null, deriva dos campos legacy [checkoutCardColor], etc.
  final CatalogCartUiTokens? cartUiTokens;

  /// Cupom de primeira compra (config + modal). Null = desligado.
  final CatalogFirstPurchaseCouponOffer? firstPurchaseCoupon;

  const CarrinhoSheetWeb({
    super.key,
    required this.lojaId,
    required this.items,
    required this.catalogProducts,
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
    this.freteMelhorEnvioModoExibicao = 'todas_transportadoras',
    required this.onRemove,
    required this.onSetItemQuantity,
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
    this.checkoutSummaryStyle,
    this.cartUiTokens,
    this.firstPurchaseCoupon,
    this.pixPreferMercadoPago = false,
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

  // cupom — até 1 de desconto (produto/total) + 1 só de frete
  final _cupomCtrl = TextEditingController();
  Map<String, dynamic>? _cupomDescontoAplicado;
  Map<String, dynamic>? _cupomFreteAplicado;

  /// Avisos que precisam ficar visíveis dentro do carrinho (não só SnackBar na loja).
  String? _avisoCheckoutPeso;
  String? _avisoCheckoutFrete;

  // ✨ ROLETA
  String?
      _campanhaAtivaId; // Campanha (sorteio com número da sorte) — independente da roleta
  bool _roletaAtiva =
      false; // Roleta (girar e concorrer a prêmios) — config/roleta_sorte
  double _valorMinimoRoleta = 0.0; // Valor mínimo para liberar a roleta
  late bool _roletaJaGirada;
  bool _todosOsDadosPreenchidos = false;
  int _quantidadeProdutosAoMostrarRoleta = 0;
  late String? _cupomRoletaCodigo; // Código do cupom ganho na roleta
  late double? _cupomRoletaDesconto; // Desconto (%) do cupom da roleta
  late String?
      _premioRoletaDescricao; // Descrição do prêmio (brinde, mimo, etc)
  late bool _freteGratisRoleta; // Frete grátis ganho na roleta

  // ✅ Flag para evitar duplicação de pedidos
  bool _processandoCheckout = false;

  /// Erro de pagamento exibido na tela do carrinho (não no catálogo)
  String? _checkoutError;

  // Validação visual: campos com erro ficam vermelhos
  String? _erroValidacao;
  final Set<String> _camposComErro = {};

  /// Debounce para persistir formulário (reduz perda ao fechar rapidamente)
  Timer? _formSaveDebounce;

  late List<Map<String, dynamic>> _fretesLocal;

  String _fmt2(num v) => v.toStringAsFixed(2).replaceAll('.', ',');

  /// Visitante: avisa benefícios do cadastro antes de pagar. Cliente logado: segue direto.
  Future<bool> _dialogBeneficioCadastroOuSeguir() async {
    final cliente = await ClienteAuthService.getClienteLogado();
    if (!mounted) return false;
    if (cliente != null) return true;

    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final maxW = math.min(
          kMaxContentWidth,
          MediaQuery.sizeOf(ctx).width - 40,
        );
        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: AlertDialog(
            title: const Text('Antes de pagar'),
            content: const SingleChildScrollView(
              child: Text(
                'Com cadastro na loja você pode acompanhar seus pedidos, cupons e '
                'sorteios quando a loja oferecer.\n\n'
                'Você também pode seguir sem cadastro: seus dados abaixo serão usados '
                'só para entrega e pagamento.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'cadastro'),
                child: const Text('Cadastrar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, 'seguir'),
                child: const Text('Seguir sem cadastro'),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted) return false;
    if (choice == 'seguir') return true;
    if (choice == 'cadastro') {
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (_) => CadastroScreenCliente(lojaId: widget.lojaId),
        ),
      );
      return false;
    }
    return false;
  }

  /// Resumo financeiro (card escuro): vem do config ou fallback dos demais checkout colors.
  CatalogCheckoutSummaryTokens get _summaryTokens =>
      widget.checkoutSummaryStyle ??
      CatalogCheckoutSummaryTokens.fallbackFromCheckoutColors(
        checkoutCardColor: widget.checkoutCardColor,
        checkoutFieldTextColor: widget.checkoutFieldTextColor,
        checkoutLabelColor: widget.checkoutLabelColor,
        checkoutTotalColor: widget.checkoutTotalColor,
      );

  /// Fallback seguro quando o parent não passa [CatalogCartUiTokens] (compatibilidade).
  CatalogCartUiTokens get _cartUi {
    final w = widget.cartUiTokens;
    if (w != null) return w;
    final card = widget.checkoutCardColor ?? widget.cardColor;
    final field = widget.checkoutFieldBg ?? card.withOpacity(0.92);
    final ft = widget.checkoutFieldTextColor ?? widget.textColor;
    final lb = widget.checkoutLabelColor ?? widget.textColor;
    final bord = widget.checkoutFieldBorder ?? Colors.white.withOpacity(0.12);
    return CatalogCartUiTokens(
      sheetBackground: Colors.transparent,
      cartCardBackground: card,
      sectionTitleColor: lb.withOpacity(0.95),
      primaryTextColor: ft,
      secondaryTextColor: ft.withOpacity(0.88),
      mutedTextColor: widget.textColor.withOpacity(0.62),
      inputBackground: field,
      inputTextColor: ft,
      inputHintColor: Colors.white.withOpacity(0.48),
      inputBorderColor: bord,
      summaryCardBackground: card,
      summaryLabelColor: lb,
      summaryValueColor: ft,
      summaryDiscountColor: Colors.redAccent,
      summaryTotalColor: widget.checkoutTotalColor ?? widget.primary,
      primaryActionBackground: widget.primary,
      primaryActionTextColor: widget.buttonText,
      secondaryActionBackground: Colors.transparent,
      secondaryActionTextColor: widget.primary,
      whatsappButtonBackground: const Color(0xFF25D366),
      whatsappButtonTextColor: Colors.white,
      pixButtonBorderColor: const Color(0xFF0D9488),
      pixButtonTextColor: const Color(0xFF0D9488),
      itemDividerColor: Colors.white.withOpacity(0.06),
      removeIconColor: Colors.redAccent.withOpacity(0.82),
    );
  }

  bool _firstPurchasePromoInFlight = false;

  String _pagamento = 'PIX';
  int _freteIndex = 0;

  String _normalizarTextoIdentificacaoFrete(String? raw) {
    if (raw == null) return '';
    var s = removeDiacritics(raw.toLowerCase().trim());
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    return s;
  }

  bool _ehOpcaoIdentificavelComoMelhorEnvio(Map<String, dynamic> f) {
    final plat = (f['plataforma'] ?? '').toString().trim();
    if (plat == 'melhor_envio') return true;
    final companyId =
        (f['company_id'] ?? f['companyId'])?.toString().trim() ?? '';
    if (companyId.isNotEmpty) return true;
    final serviceId =
        (f['service_id'] ?? f['serviceId'])?.toString().trim() ?? '';
    if (serviceId.isNotEmpty) return true;
    return false;
  }

  /// Opções identificadas como Melhor Envio tratadas como Correios (PAC/SEDEX/company).
  bool _ehOpcaoMelhorEnvioCorreios(Map<String, dynamic> f) {
    if (!_ehOpcaoIdentificavelComoMelhorEnvio(f)) return false;
    final empresa = _normalizarTextoIdentificacaoFrete(
      (f['empresa'] ?? '').toString(),
    );
    final nome = _normalizarTextoIdentificacaoFrete(
      (f['nome'] ?? f['label'] ?? '').toString(),
    );
    final companyId =
        (f['company_id'] ?? f['companyId'] ?? '').toString().trim();
    if (empresa.contains('correios')) return true;
    if (companyId == '1') return true;
    if (nome.contains('sedex')) return true;
    // "PAC" como token/palavra: aceita "PAC", "PAC Mini", "PAC Correios",
    // mas evita falso positivo em strings como ".package".
    if (RegExp(r'(^|[^a-z0-9])pac([^a-z0-9]|$)').hasMatch(nome)) return true;
    return false;
  }

  bool _deveExibirFreteNoModal(Map<String, dynamic> f) {
    final modo = widget.freteMelhorEnvioModoExibicao.trim().toLowerCase();
    final somenteCorreios = modo == 'somente_correios';
    if (!somenteCorreios) return true;
    if (!_ehOpcaoIdentificavelComoMelhorEnvio(f)) return true;
    return _ehOpcaoMelhorEnvioCorreios(f);
  }

  /// Mesma base de fretes do `build` (fallback quando vazio).
  List<Map<String, dynamic>> _fretesExibirSnapshot() {
    final list = _fretesLocal.isNotEmpty
        ? List<Map<String, dynamic>>.from(_fretesLocal)
        : widget.fretes.map((e) => asMapDeep(e)).toList();
    if (list.isEmpty) {
      list.addAll([
        {
          'nome': 'Retirada',
          'valor': 0.0,
          'tipo': 'retirada',
          'plataforma': 'manual',
          'freteGratis': true,
        },
        {
          'nome': 'Combinar com vendedor',
          'valor': 0.0,
          'tipo': 'combinar',
          'plataforma': 'manual',
          'freteGratis': true,
        },
      ]);
    }
    return list;
  }

  /// Totais alinhados ao checkout (PIX por item, cupom, frete) — ver [computeCatalogCheckoutTotals].
  CatalogCheckoutTotals get _totals {
    final fretes = _fretesExibirSnapshot();
    final idx = _freteIndex.clamp(0, fretes.isEmpty ? 0 : fretes.length - 1);
    return computeCatalogCheckoutTotals(
      items: widget.items,
      pagamento: _pagamento,
      cupomDescontoAplicado: _cupomDescontoAplicado,
      cupomFreteAplicado: _cupomFreteAplicado,
      fretesParaCalculo: fretes,
      freteIndex: idx,
      freteGratisRoleta: _freteGratisRoleta,
    );
  }

  double get _subtotal => _totals.subtotalBruto;

  /// Subtotal com desconto PIX aplicado (quando produto tem percentualDescontoPix)
  double get _subtotalPix => _totals.subtotalPix;

  /// Subtotal conforme forma de pagamento (PIX aplica desconto quando disponível)
  double get _subtotalConformePagamento => _totals.subtotalConformePagamento;

  bool get _freteGratis => _totals.freteGratis;

  /// PIX com chave na loja (WhatsApp/PIX) — o botão dedicado cobre; não exibir
  /// outro CTA de PIX (gateway). Com **cartão** ou outras formas, o MP segue visível.
  bool get _pixApenasComChaveDaLoja {
    if (_pagamento.toUpperCase() != 'PIX') return false;
    if (widget.pixPreferMercadoPago) return false;
    if (widget.pixKey.trim().isEmpty || widget.onCheckoutPix == null) {
      return false;
    }
    return widget.checkoutGateway == 'pix' ||
        widget.checkoutGateway == 'whatsapp';
  }

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      debugPrint(
        '[CART_WIDGET_RENDERED] CarrinhoSheetWeb.initState lojaId=${widget.lojaId}',
      );
    }
    _fretesLocal = widget.fretes.map((e) => asMapDeep(e)).toList();

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
      final rawFrete = init['freteIndex'];
      int savedFrete = 0;
      if (rawFrete is int) {
        savedFrete = rawFrete;
      } else if (rawFrete is num) {
        savedFrete = rawFrete.toInt();
      } else if (rawFrete is String) {
        savedFrete = int.tryParse(rawFrete) ?? 0;
      }
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

    // Linha de base para regra da roleta (evita mutação no getter durante build)
    _quantidadeProdutosAoMostrarRoleta = widget.items.length;

    // 🔍 Debug: Mostrar fretes iniciais
    logD('🛒 [CARRINHO] initState - Fretes recebidos: ${widget.fretes.length}');
    logD('📊 [CARRINHO] _fretesLocal inicial: ${_fretesLocal.length} itens');
    for (int i = 0; i < _fretesLocal.length; i++) {
      final f = _fretesLocal[i];
      logD('   [$i] ${f['nome']} - R\$ ${f['valor']} (tipo: ${f['tipo']})');
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

    _scheduleFirstPurchasePromoCheck();
  }

  void _scheduleFirstPurchasePromoCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_maybeShowFirstPurchaseCoupon());
    });
  }

  /// Detalhe do item: combo (composição + variações) ou tam/cor/extra do produto.
  String _cartItemVariantSubtitle(Map<String, dynamic> item) {
    final rich = ComboConfiguravelResumo.textoParaItemMap(item);
    if (rich.isNotEmpty) return rich;
    final combo = item['itensComboComSelecao'];
    if (combo is List && combo.isNotEmpty) {
      return '${combo.length} itens';
    }
    return '';
  }

  /// Detalhe sob o nome (combo longo, variações): mais linhas + tooltip com texto integral.
  Widget _cartItemDetailText(String sub, Map<String, dynamic> item) {
    final combo = item['itensComboComSelecao'];
    final nCombo = combo is List ? combo.length : 0;
    final nLines =
        sub.split(RegExp(r'[\r\n]+')).where((s) => s.trim().isNotEmpty).length;
    final longCombo = nCombo > 4 || sub.length > 420 || nLines > 5;
    final maxLines = longCombo ? 14 : 10;
    final body = Text(
      sub,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12,
        height: 1.35,
        color: _cartUi.mutedTextColor.withOpacity(0.88),
      ),
    );
    if (!longCombo || sub.trim().isEmpty) return body;
    return Tooltip(
      message: sub,
      waitDuration: const Duration(milliseconds: 400),
      child: body,
    );
  }

  int _quantidadeUnidadesCarrinho() {
    var n = 0;
    for (final e in widget.items) {
      n += CatalogEstoqueHelper.parseCartItemQuantidade(e['quantidade']);
    }
    return n;
  }

  Future<void> _maybeShowFirstPurchaseCoupon() async {
    final offer = widget.firstPurchaseCoupon;
    if (offer == null || !offer.enabled) return;
    if (widget.items.isEmpty) return;
    if (CatalogFirstPurchasePromoSession.wasShownForLoja(widget.lojaId)) {
      return;
    }
    if (_firstPurchasePromoInFlight) return;

    _firstPurchasePromoInFlight = true;
    try {
      if (offer.requireClienteSemPedidos) {
        final c = await ClienteAuthService.getClienteLogado();
        if (!mounted) return;
        if (c == null) return;
        final email = (c['email'] ?? '').toString().trim();
        if (email.isEmpty) return;
        final r = await ClienteAuthService.getPedidosDoCliente(
          lojaId: widget.lojaId,
          email: email,
          clienteId: c['clienteId']?.toString(),
        );
        if (!mounted) return;
        if (r.precisaReconectar) return;
        if (r.pedidos.isNotEmpty) return;
      }

      if (!mounted) return;
      CatalogFirstPurchasePromoSession.markShownForLoja(widget.lojaId);
      if (kDebugMode) {
        debugPrint(
          '[FIRST_PURCHASE_MODAL] showCatalogFirstPurchaseCouponDialog '
          '(CarrinhoSheetWeb, lojaId=${widget.lojaId})',
        );
      }
      await showCatalogFirstPurchaseCouponDialog(
        context: context,
        offer: offer,
        onUseCoupon: () {
          if (!mounted) return;
          setState(() {
            _cupomCtrl.text = offer.couponCode;
          });
          _scheduleFormSave();
          unawaited(_aplicarCupom());
        },
        onDismiss: () {},
      );
    } finally {
      _firstPurchasePromoInFlight = false;
    }
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
          debugPrint(
              'carrinho_sheet_web: getDadosCompletos retornou null (CF pode ter falhado)');
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
          final portalToken =
              (dados['portalToken'] ?? cliente['portalToken'] ?? '')
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
            debugPrint(
                'carrinho_sheet_web: erro ao buscar endereço de pedido anterior (type=${e.runtimeType})');
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
      logE('❌ Erro ao preencher dados do cliente (type=${e.runtimeType})',
          error: e, st: st);
      return 'error';
    }
  }

  @override
  void didUpdateWidget(covariant CarrinhoSheetWeb oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.items.isNotEmpty &&
        (oldWidget.items.isEmpty ||
            oldWidget.items.length != widget.items.length)) {
      _scheduleFirstPurchasePromoCheck();
    }

    if (oldWidget.items.length != widget.items.length) {
      if (widget.items.length > _quantidadeProdutosAoMostrarRoleta) {
        _quantidadeProdutosAoMostrarRoleta = widget.items.length;
      }
    }

    if (oldWidget.initialRoletaJaGirada != widget.initialRoletaJaGirada ||
        oldWidget.initialCupomRoletaCodigo != widget.initialCupomRoletaCodigo ||
        oldWidget.initialFreteGratisRoleta != widget.initialFreteGratisRoleta) {
      _roletaJaGirada = widget.initialRoletaJaGirada;
      _cupomRoletaCodigo = widget.initialCupomRoletaCodigo;
      _cupomRoletaDesconto = widget.initialCupomRoletaDesconto;
      _premioRoletaDescricao = widget.initialPremioRoletaDescricao;
      _freteGratisRoleta = widget.initialFreteGratisRoleta;
    }

    if (oldWidget.fretes != widget.fretes) {
      _fretesLocal = widget.fretes.map((e) => asMapDeep(e)).toList();

      if (_fretesLocal.isEmpty) {
        _freteIndex = 0;
      } else if (_freteIndex >= _fretesLocal.length) {
        _freteIndex = 0;
      }
    }

    final precisaAtualizarRoleta = oldWidget.fretes != widget.fretes ||
        oldWidget.items.length != widget.items.length;
    if (precisaAtualizarRoleta) {
      // Evita setState durante o update do elemento (árvore pode estar bloqueada)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _atualizarEstadoRoleta();
      });
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
      logE('❌ Erro ao verificar campanha (type=${e.runtimeType})',
          error: e, st: st);
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
      logE('❌ Erro ao verificar roleta (type=${e.runtimeType})',
          error: e, st: st);
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

  /// Verifica se a roleta pode ser exibida (só quando roleta ativa, não campanha).
  /// Sem efeitos colaterais — a contagem é sincronizada em [initState]/[didUpdateWidget].
  bool get _podeExibirRoleta {
    if (!_roletaAtiva) return false;
    if (_roletaJaGirada) return false;
    if (!_todosOsDadosPreenchidos) return false;
    if (_subtotal < _valorMinimoRoleta) return false;

    if (widget.items.length != _quantidadeProdutosAoMostrarRoleta) {
      if (widget.items.length > _quantidadeProdutosAoMostrarRoleta) {
        return true;
      }
      return false;
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
      'cupomFreteCodigo': _codigoCupomMap(_cupomFreteAplicado),
      'freteIndex': _freteIndex,
      'pagamento': _pagamento,
    };
  }

  String _codigoCupomMap(Map<String, dynamic>? m) =>
      (m == null) ? '' : (m['codigo'] ?? m['code'] ?? '').toString().trim();

  Map<String, dynamic>? _cupomPorOrigem(String origem) {
    if (_cupomDescontoAplicado?['origem'] == origem) {
      return _cupomDescontoAplicado;
    }
    if (_cupomFreteAplicado?['origem'] == origem) {
      return _cupomFreteAplicado;
    }
    return null;
  }

  @override
  void dispose() {
    _formSaveDebounce?.cancel();
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

  /// Código do cupom de desconto (produto/total) para o pré-pedido.
  String? _cupomCodigoParaPedido() {
    final c = _codigoCupomMap(_cupomDescontoAplicado);
    return c.isEmpty ? null : c;
  }

  String? _cupomFreteCodigoParaPedido() {
    final c = _codigoCupomMap(_cupomFreteAplicado);
    return c.isEmpty ? null : c;
  }

  String? _cupomFreteIdFirestore() {
    final id = _cupomFreteAplicado?['id']?.toString().trim();
    if (id == null || id.isEmpty) return null;
    if (_cupomFreteAplicado?['origem'] == 'roleta_sorte' ||
        _cupomFreteAplicado?['origem'] == 'cupom_cliente') {
      return null;
    }
    return id;
  }

  String? _cupomDescontoIdFirestore() {
    final id = _cupomDescontoAplicado?['id']?.toString().trim();
    if (id == null || id.isEmpty) return null;
    final o = _cupomDescontoAplicado?['origem']?.toString();
    if (o == 'roleta_sorte' || o == 'cupom_cliente') return null;
    return id;
  }

  Map<String, dynamic> _customerPayload() {
    final tipoFrete = (_fretesLocal.isNotEmpty &&
            _freteIndex >= 0 &&
            _freteIndex < _fretesLocal.length)
        ? (_fretesLocal[_freteIndex]['tipo'] ?? '').toString().toLowerCase()
        : '';
    final isRetirada = tipoFrete == 'retirada';
    final enderecoFmt = isRetirada
        ? 'Retirada em loja'
        : 'CEP ${_cep.text.trim()} - ${_rua.text.trim()}, ${_numero.text.trim()} - ${_bairro.text.trim()}, ${_cidade.text.trim()}'
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

  void _scheduleFormSave() {
    _formSaveDebounce?.cancel();
    _formSaveDebounce = Timer(const Duration(milliseconds: 600), () {
      widget.onFormDataToSave?.call(_getFormDataMap());
    });
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

    // Se frete for retirada, não exige endereço completo
    final tipoFrete = (_fretesLocal.isNotEmpty &&
            _freteIndex >= 0 &&
            _freteIndex < _fretesLocal.length)
        ? (_fretesLocal[_freteIndex]['tipo'] ?? '').toString().toLowerCase()
        : '';
    final isRetirada = tipoFrete == 'retirada';

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
    } else if (!catalogIsValidCpfForMpPayer(_cpf.text)) {
      _camposComErro.add('cpf');
      _erroValidacao = 'CPF inválido.';
    }
    if (_tel.text.trim().isEmpty) {
      _camposComErro.add('tel');
      obrigatorios.add('Telefone');
    } else if (tel.length < 10) {
      _camposComErro.add('tel');
      _erroValidacao ??=
          'Telefone deve ter no mínimo 10 dígitos (DDD + número).';
    }
    if (_email.text.trim().isEmpty) {
      _camposComErro.add('email');
      obrigatorios.add('E-mail');
    } else if (!catalogIsPlausibleMpBuyerEmail(_email.text)) {
      _camposComErro.add('email');
      _erroValidacao ??=
          'E-mail no formato exigido pelo pagamento (ex.: nome@dominio.com.br).';
    }
    if (!isRetirada) {
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

  /// Verifica se todos os itens têm preço válido (> 0).
  bool _validarItensComPreco() {
    for (var i = 0; i < widget.items.length; i++) {
      final item = widget.items[i];
      final price = (item['preco'] as num?)?.toDouble() ??
          (item['price'] as num?)?.toDouble() ??
          0.0;
      if (price <= 0) {
        final nome =
            (item['nome'] ?? item['name'] ?? 'Item ${i + 1}').toString();
        widget.showSnack(
            'Produto "$nome" sem preço. Remova ou verifique no catálogo.');
        return false;
      }
    }
    return true;
  }

  /// Converte modelo Cupom para o mapa usado nos slots de cupom (inclui id para registrarUso).
  Map<String, dynamic> _cupomMapFromCupom(Cupom c) {
    return {
      'id': c.id,
      'codigo': c.codigo,
      'code': c.codigo,
      'tipo': c.tipo == 'percentual' ? 'percent' : 'valor',
      'valor': c.valor,
      'aplicarEm': c.aplicarEm,
      if (c.produtoIds.isNotEmpty)
        'produtoIds': List<String>.from(c.produtoIds),
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

    // 2) Cupom roleta: clientes_catalogo (USO ESPECÍFICO, complemento)
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
      final clienteIdCatalogo =
          (clienteLogado?['clienteId'] ?? '').toString().trim();
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

    var merged = Map<String, dynamic>.from(found);
    if (merged['origem'] != 'roleta_sorte' &&
        merged['origem'] != 'cupom_cliente') {
      final cLoja =
          await CupomDescontoService().buscarPorCodigo(widget.lojaId, code);
      if (cLoja != null) {
        merged['id'] = cLoja.id;
        if (cLoja.produtoIds.isNotEmpty) {
          merged['produtoIds'] = cLoja.produtoIds;
        }
      }
    }

    if (!catalogCarrinhoCobreProdutosCupom(
      cupomAplicado: merged,
      items: widget.items,
    )) {
      widget.showSnack(
        'Este cupom só vale para o produto da promoção. Adicione esse item ao carrinho.',
      );
      return;
    }

    // Validar data de validade ao aplicar (evita uso de cupom expirado)
    final now = DateTime.now();
    final df = merged['dataFim'] ??
        merged['validade'] ??
        merged['dataValidade'] ??
        merged['dataExpiracao'] ??
        merged['expiraEm'];
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
    final vMin = merged['valorMinimo'] ?? merged['valor_minimo'];
    final valorMinimo = (vMin is num) ? vMin.toDouble() : null;
    if (valorMinimo != null && valorMinimo > 0) {
      final aplicarEm = (found['aplicarEm'] ?? 'produtos').toString();
      double baseValor = _subtotalConformePagamento;
      if ((aplicarEm == 'total' || aplicarEm == 'frete') &&
          _fretesLocal.isNotEmpty) {
        final frete =
            _fretesLocal[_freteIndex.clamp(0, _fretesLocal.length - 1)];
        baseValor +=
            _freteGratis ? 0.0 : ((frete['valor'] as num?)?.toDouble() ?? 0.0);
      }
      if (baseValor < valorMinimo) {
        widget.showSnack(
            'Cupom exige compra mínima de R\$ ${valorMinimo.toStringAsFixed(2)}.');
        return;
      }
    }

    final somenteFrete = catalogCupomSomenteFrete(merged);
    if (somenteFrete) {
      if (_cupomFreteAplicado != null &&
          _codigoCupomMap(_cupomFreteAplicado).toUpperCase() != code) {
        widget.showSnack(
          'Você já tem um cupom de frete aplicado. Remova-o antes de usar outro.',
        );
        return;
      }
      setState(() {
        _cupomFreteAplicado = asMapDeep(merged);
      });
    } else {
      if (_cupomDescontoAplicado != null &&
          _codigoCupomMap(_cupomDescontoAplicado).toUpperCase() != code) {
        widget.showSnack(
          'Você já tem um cupom de desconto aplicado. Remova-o antes de usar outro.',
        );
        return;
      }
      setState(() {
        _cupomDescontoAplicado = asMapDeep(merged);
      });
    }

    widget.showSnack('Cupom aplicado: $code');
  }

  @override
  Widget build(BuildContext context) {
    // Fallback: nunca ocultar checkout; usar widget.fretes ou padrão se _fretesLocal vazio
    final List<Map<String, dynamic>> fretesExibir = _fretesLocal.isNotEmpty
        ? List<Map<String, dynamic>>.from(_fretesLocal)
        : widget.fretes.map((e) => asMapDeep(e)).toList();
    if (fretesExibir.isEmpty) {
      fretesExibir.addAll([
        {
          'nome': 'Retirada',
          'valor': 0.0,
          'tipo': 'retirada',
          'plataforma': 'manual',
          'freteGratis': true
        },
        {
          'nome': 'Combinar com vendedor',
          'valor': 0.0,
          'tipo': 'combinar',
          'plataforma': 'manual',
          'freteGratis': true
        },
      ]);
    }
    // Restaurar _fretesLocal quando vazio para interações (modal, etc.)
    if (_fretesLocal.isEmpty && fretesExibir.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _fretesLocal.isEmpty) {
          setState(() {
            _fretesLocal.addAll(fretesExibir);
            _freteIndex = _freteIndex.clamp(0, _fretesLocal.length - 1);
          });
        }
      });
    }

    // ✅ segurança: garante índice válido
    final idxFrete = _freteIndex.clamp(0, fretesExibir.length - 1);
    final frete = fretesExibir[idxFrete];

    // 🔍 DEBUG: Log do frete selecionado
    if (kDebugMode) {
      logD(
          '💰 [TOTAL] Frete selecionado (índice $_freteIndex): ${frete['nome']}');
      logD('💰 [TOTAL] Frete completo: $frete');
      logD(
          '💰 [TOTAL] Campo valor bruto: ${frete['valor']} (tipo: ${frete['valor'].runtimeType})');
    }

    final double valorFreteOriginal =
        (frete['valor'] as num?)?.toDouble() ?? 0.0;

    final tSnap = _totals;
    final double descontoProdutos = tSnap.descontoCupomProdutos;
    final double total = tSnap.total;

    if (kDebugMode) {
      logD('💰 [TOTAL] Valor frete original: R\$ $valorFreteOriginal');
      logD(
          '💰 [TOTAL] Valor frete final: R\$ ${tSnap.valorFreteFinal} (frete grátis: $_freteGratis)');
      logD('💰 [TOTAL] Subtotal: R\$ $_subtotal (PIX: R\$ $_subtotalPix)');
      logD(
          '💰 [TOTAL] Total calculado: R\$ $_subtotalConformePagamento + R\$ ${tSnap.valorFreteFinal} - desconto prod R\$ $descontoProdutos = R\$ $total');
    }

    final sheetBg = _cartUi.sheetBackground;
    return SafeArea(
      child: ColoredBox(
        color: sheetBg.opacity == 0 ? Colors.transparent : sheetBg,
        child: LayoutBuilder(
          builder: (_, c) {
            // Checkout em 2 colunas (desktop): principal | resumo+CTA — estilo e-commerce.
            final isWide = c.maxWidth > 1080;
            final padH = c.maxWidth < 420 ? 12.0 : 16.0;
            final gapStack = c.maxWidth < 420 ? 18.0 : 22.0;
            final summaryW =
                math.min(400.0, (c.maxWidth * 0.34).clamp(300.0, 420.0));
            final mainCheckout = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _left(context),
                SizedBox(height: gapStack),
                _centerForm(context),
                SizedBox(height: gapStack),
                _checkoutFulfillmentAndPayment(context),
              ],
            );
            return Padding(
              padding: EdgeInsets.fromLTRB(padH, 10, padH, 24),
              child: SingleChildScrollView(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1280),
                    child: isWide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: mainCheckout),
                              SizedBox(width: gapStack),
                              SizedBox(
                                width: summaryW,
                                child: _right(
                                  context,
                                  tSnap,
                                  frete,
                                ),
                              ),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              mainCheckout,
                              SizedBox(height: gapStack),
                              _right(
                                context,
                                tSnap,
                                frete,
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _embalagensPadrao() => [
        {
          'id': 'padrao',
          'nome': 'Padrão',
          'peso': 50.0,
          'tamanho': 1,
          'altura': 10.0,
          'largura': 20.0,
          'comprimento': 30.0,
        },
        {
          'id': 'pequena',
          'nome': 'Pequena',
          'peso': 100.0,
          'tamanho': 2,
          'altura': 15.0,
          'largura': 25.0,
          'comprimento': 35.0,
        },
        {
          'id': 'media',
          'nome': 'Média',
          'peso': 200.0,
          'tamanho': 3,
          'altura': 20.0,
          'largura': 30.0,
          'comprimento': 40.0,
        },
        {
          'id': 'grande',
          'nome': 'Grande',
          'peso': 350.0,
          'tamanho': 4,
          'altura': 25.0,
          'largura': 35.0,
          'comprimento': 45.0,
        },
      ];

  List<Map<String, dynamic>> _parseEmbalagens(dynamic raw) {
    if (raw is! List || raw.isEmpty) return <Map<String, dynamic>>[];
    return raw.map<Map<String, dynamic>>((e) {
      if (e is! Map) {
        return {
          'id': '',
          'nome': '',
          'peso': 0.0,
          'tamanho': 0,
          'altura': 10.0,
          'largura': 20.0,
          'comprimento': 30.0,
        };
      }
      final m = Map<String, dynamic>.from(e);
      return {
        'id': m['id']?.toString() ?? '',
        'nome': m['nome']?.toString() ?? '',
        'peso': (m['peso'] is num)
            ? (m['peso'] as num).toDouble()
            : double.tryParse('${m['peso']}') ?? 0.0,
        'tamanho': (m['tamanho'] is num)
            ? (m['tamanho'] as num).toInt()
            : int.tryParse('${m['tamanho']}') ?? 0,
        'altura': (m['altura'] is num)
            ? (m['altura'] as num).toDouble()
            : double.tryParse('${m['altura']}') ?? 10.0,
        'largura': (m['largura'] is num)
            ? (m['largura'] as num).toDouble()
            : double.tryParse('${m['largura']}') ?? 20.0,
        'comprimento': (m['comprimento'] is num)
            ? (m['comprimento'] as num).toDouble()
            : double.tryParse('${m['comprimento']}') ?? 30.0,
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _carregarEmbalagensParaFrete() async {
    final lojaId = widget.lojaId.trim();
    try {
      if (!Hive.isBoxOpen('config')) {
        await Hive.openBox('config');
      }
      final configBox = Hive.box('config');

      // Fonte primária: Firestore config/fretes.embalagens (escopo da loja).
      if (lojaId.isNotEmpty) {
        try {
          var lojaDocRef =
              FirebaseFirestore.instance.collection('lojas').doc(lojaId);
          var fretesSnap =
              await lojaDocRef.collection('config').doc('fretes').get();
          if (!fretesSnap.exists) {
            final bySlug = await FirebaseFirestore.instance
                .collection('lojas')
                .where('slug', isEqualTo: lojaId.toLowerCase())
                .limit(1)
                .get();
            if (bySlug.docs.isNotEmpty) {
              lojaDocRef = bySlug.docs.first.reference;
              fretesSnap =
                  await lojaDocRef.collection('config').doc('fretes').get();
            }
          }
          final remote = _parseEmbalagens(fretesSnap.data()?['embalagens']);
          if (remote.isNotEmpty) {
            await configBox.put('embalagens_${lojaDocRef.id}', remote);
            await configBox.put('embalagens_$lojaId', remote);
            await configBox.put('embalagens', remote);
            logD(
              '📦 [FRETE/EMBALAGEM] Fonte: Firestore config/fretes '
              '(loja=${lojaDocRef.id}, itens=${remote.length})',
            );
            return remote;
          }
        } catch (e, st) {
          logW(
              '⚠️ [FRETE] Falha ao ler embalagens remotas (type=${e.runtimeType})');
          logD('$st');
        }
      }

      // Fallback 1: cache por loja (Hive).
      dynamic raw =
          lojaId.isNotEmpty ? configBox.get('embalagens_$lojaId') : null;
      var parsed = _parseEmbalagens(raw);
      if (parsed.isNotEmpty) {
        logD(
          '📦 [FRETE/EMBALAGEM] Fonte: Hive por loja '
          '(chave=embalagens_$lojaId, itens=${parsed.length})',
        );
        return parsed;
      }

      // Fallback 2: cache global.
      raw = configBox.get('embalagens');
      parsed = _parseEmbalagens(raw);
      if (parsed.isNotEmpty) {
        logD(
          '📦 [FRETE/EMBALAGEM] Fonte: Hive global '
          '(chave=embalagens, itens=${parsed.length})',
        );
        return parsed;
      }
    } catch (e, st) {
      logE(
        '❌ Erro ao carregar embalagens (type=${e.runtimeType})',
        error: e,
        st: st,
      );
    }
    final fallback = _embalagensPadrao();
    logW(
      '📦 [FRETE/EMBALAGEM] Fonte: padrão interno '
      '(itens=${fallback.length})',
    );
    return fallback;
  }

  /// Calcula peso total do carrinho com seleção inteligente de embalagem
  /// Retorna: {'pesoTotal': double, 'embalagem': Map, 'pesoEmbalagem': double}
  Future<Map<String, dynamic>> _calcularPesoComEmbalagem(
      List<Map<String, dynamic>> items) async {
    final embalagens = await _carregarEmbalagensParaFrete();

    // 2. Calcular peso total dos produtos
    double pesoProdutos = 0.0;
    int maiorTamanho = 0;
    Map<String, dynamic>? embalagemMaior;

    for (final item in items) {
      final qty =
          CatalogEstoqueHelper.parseCartItemQuantidade(item['quantidade']);
      final peso = (item['peso'] as num?)?.toDouble() ?? 0.0;
      final tipoEmb = item['tipoEmbalagem'] as String? ?? 'padrao';

      if (peso <= 0 && qty > 0) {
        logW(
            '📦 [PESO] Produto sem peso: ${item['nome'] ?? item['name'] ?? '?'}');
      }
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
    final comprimentoEmb =
        safeDouble(embalagemMaior?['comprimento'], fallback: 30.0);
    final pesoTotal = pesoProdutos + pesoEmbalagem;

    if (items.isNotEmpty && pesoProdutos <= 0) {
      return {
        'pesoTotal': 300.0,
        'pesoProdutos': 0.0,
        'pesoEmbalagem': pesoEmbalagem,
        'altura': alturaEmb,
        'largura': larguraEmb,
        'comprimento': comprimentoEmb,
        'embalagem': embalagemMaior,
        'erro': 'Produtos sem peso cadastrado. Verifique os itens no catálogo.',
      };
    }

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
    if (_fretesLocal.isEmpty) {
      final snapshot = _fretesExibirSnapshot();
      if (snapshot.isNotEmpty) {
        setState(() {
          _fretesLocal = List<Map<String, dynamic>>.from(snapshot);
          _freteIndex = _freteIndex.clamp(0, _fretesLocal.length - 1);
        });
      }
    }

    // Se CEP já tem 8 dígitos e só temos fretes manuais, recalcular para buscar Melhor Envio/SuperFrete
    final cep = _cep.text.replaceAll(RegExp(r'[^0-9]'), '');
    // Considerar "só manuais" quando nenhum item veio de API (melhor_envio, frenet, correios, superfrete)
    final soManuais = _fretesLocal.every((f) {
      final plat = (f['plataforma'] ?? '').toString();
      return plat.isEmpty ||
          !['melhor_envio', 'frenet', 'correios', 'superfrete'].contains(plat);
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
    final wideChrome = usePointerFirstChrome(context);

    Widget opcoesFreteContent(BuildContext sheetContext) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          final modalH = MediaQuery.of(context).size.height * 0.65;
          final indicesVisiveis = <int>[];
          for (var i = 0; i < _fretesLocal.length; i++) {
            if (_deveExibirFreteNoModal(_fretesLocal[i])) {
              indicesVisiveis.add(i);
            }
          }
          return SizedBox(
            height: modalH,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(
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

                  // Lista de opções de frete (altura limitada + scroll; evita Column min + Flexible)
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: indicesVisiveis.isEmpty
                            ? <Widget>[
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 32),
                                  child: Center(
                                    child: Text(
                                      'Nenhuma opção dos Correios para este CEP. '
                                      'Selecione "Todas" para ver as demais transportadoras.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: textoSecundario,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ),
                              ]
                            : List.generate(indicesVisiveis.length, (j) {
                                final i = indicesVisiveis[j];
                                final f = _fretesLocal[i];
                                final nome =
                                    (f['nome'] ?? f['label'] ?? 'Frete')
                                        .toString();
                                final valor =
                                    (f['valor'] as num?)?.toDouble() ?? 0.0;
                                final prazo = (f['prazo'] ?? '').toString();
                                final plataforma =
                                    (f['plataforma'] ?? f['tipo'] ?? '')
                                        .toString();
                                final bool isSelected = i == _freteIndex;

                                // ✅ se o cupom dá frete grátis, mostra "Grátis" para o frete selecionado
                                final bool showGratis = isSelected
                                    ? _freteGratis
                                    : (f['freteGratis'] == true);
                                final precoTexto = showGratis
                                    ? 'GRÁTIS'
                                    : 'R\$ ${_fmt2(valor)}';

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
                                      setModalState(
                                          () {}); // Atualiza o modal também

                                      logD(
                                          '✅ [SELEÇÃO] _freteIndex atualizado para: $_freteIndex');

                                      // Recalcular frete
                                      await _recalcularFreteSelecionado();
                                      if (!mounted) return;
                                      setState(() {});

                                      // Fechar modal
                                      if (!sheetContext.mounted) return;
                                      Navigator.of(sheetContext).pop();
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
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 6,
                                                          vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: plataforma ==
                                                                'melhor_envio'
                                                            ? Colors
                                                                .green.shade100
                                                            : plataforma ==
                                                                    'frenet'
                                                                ? Colors.blue
                                                                    .shade100
                                                                : plataforma ==
                                                                        'correios'
                                                                    ? Colors
                                                                        .orange
                                                                        .shade100
                                                                    : plataforma ==
                                                                            'superfrete'
                                                                        ? Colors
                                                                            .teal
                                                                            .shade100
                                                                        : Colors
                                                                            .grey
                                                                            .shade200,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(4),
                                                      ),
                                                      child: Text(
                                                        plataforma ==
                                                                'melhor_envio'
                                                            ? 'ME'
                                                            : plataforma ==
                                                                    'frenet'
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
                                                              ? Colors.green
                                                                  .shade800
                                                              : plataforma ==
                                                                      'frenet'
                                                                  ? Colors.blue
                                                                      .shade800
                                                                  : plataforma ==
                                                                          'correios'
                                                                      ? Colors
                                                                          .orange
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
                                                          fontWeight:
                                                              FontWeight.bold,
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
                                                    overflow:
                                                        TextOverflow.ellipsis,
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
                                                  margin: const EdgeInsets.only(
                                                      top: 4),
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 8,
                                                      vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: selectedBorder,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            10),
                                                  ),
                                                  child: const Text(
                                                    'Selecionado',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w600,
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
            ),
          );
        },
      );
    }

    if (wideChrome) {
      showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (sheetContext) {
          final mq = MediaQuery.of(sheetContext);
          final maxW = math.min(kMaxContentWidth, mq.size.width - 40);
          return Dialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxW,
                maxHeight: mq.size.height * 0.75,
              ),
              child: Material(
                color: bgModal,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: opcoesFreteContent(sheetContext),
              ),
            ),
          );
        },
      );
    } else {
      showModalBottomSheet(
        context: context,
        backgroundColor: bgModal,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (sheetContext) => opcoesFreteContent(sheetContext),
      );
    }
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
      final erroPeso = pesoCalc['erro'] as String?;
      if (erroPeso != null && erroPeso.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _avisoCheckoutPeso = erroPeso;
        });
        return;
      }
      if (mounted) {
        setState(() => _avisoCheckoutPeso = null);
      }
      double pesoTotal = (pesoCalc['pesoTotal'] as num?)?.toDouble() ?? 300.0;

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

      // ✅ Preservar manuais se API retornar vazio (nunca sobrescrever com lista vazia)
      final manuaisAtuais = _fretesLocal
          .where((f) => ((f['plataforma'] ?? '').toString()) == 'manual')
          .toList();
      final fallbackManuais = widget.fretes.isNotEmpty
          ? widget.fretes.map((e) => asMapDeep(e)).toList()
          : [
              {
                'nome': 'Retirada',
                'valor': 0.0,
                'tipo': 'retirada',
                'plataforma': 'manual',
                'freteGratis': true
              },
              {
                'nome': 'Combinar com vendedor',
                'valor': 0.0,
                'tipo': 'combinar',
                'plataforma': 'manual',
                'freteGratis': true
              },
            ];

      // ✅ Limpar e reconstruir _fretesLocal
      _fretesLocal.clear();

      // Adicionar opções retornadas pela API (que já inclui manuais)
      if (opcoesFretes.isNotEmpty) {
        logD('📦 [CATALOGO] Processando ${opcoesFretes.length} opções da API:');
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

      // ✅ Se API retornou vazio ou filtrou tudo: preservar manuais (nunca deixar lista vazia)
      if (_fretesLocal.isEmpty) {
        _fretesLocal
            .addAll(manuaisAtuais.isNotEmpty ? manuaisAtuais : fallbackManuais);
        logD(
            '📦 [CATALOGO] API sem opções; preservando ${_fretesLocal.length} manuais.');
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
          logD('📍 [CATALOGO] Todas as opções são manuais. Mantendo índice 0.');
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
      setState(() {
        _avisoCheckoutFrete = null;
      });
    } catch (e, st) {
      logE('❌ [CATALOGO] Erro ao calcular frete (type=${e.runtimeType})',
          error: e, st: st);
      if (mounted) {
        setState(() {
          _avisoCheckoutFrete =
              'Não foi possível atualizar o frete automaticamente. Verifique o CEP ou escolha retirada / combinar com a loja.';
        });
      }
      // Preservar lista existente; se estava vazia, restaurar de widget.fretes
      if (_fretesLocal.isEmpty && widget.fretes.isNotEmpty && mounted) {
        setState(() {
          _fretesLocal.addAll(widget.fretes.map((e) => asMapDeep(e)));
          _freteIndex = _freteIndex.clamp(0, _fretesLocal.length - 1);
        });
      } else if (_fretesLocal.isEmpty && mounted) {
        setState(() {
          _fretesLocal.addAll([
            {
              'nome': 'Retirada',
              'valor': 0.0,
              'tipo': 'retirada',
              'plataforma': 'manual',
              'freteGratis': true
            },
            {
              'nome': 'Combinar com vendedor',
              'valor': 0.0,
              'tipo': 'combinar',
              'plataforma': 'manual',
              'freteGratis': true
            },
          ]);
        });
      }
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

  Future<void> _changeLineQuantity(int index, int delta) async {
    final cur = CatalogEstoqueHelper.parseCartItemQuantidade(
        widget.items[index]['quantidade']);
    final next = cur + delta;
    if (next < 1) {
      await _removeItemAndRefresh(index);
      return;
    }
    final ok = widget.onSetItemQuantity(index, next);
    if (!ok || !mounted) return;
    setState(() {});
    final cepDestino = _cep.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (cepDestino.length == 8 && widget.items.isNotEmpty) {
      await _recalcularFreteSelecionado();
      if (mounted) setState(() {});
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
      logE('❌ [VIACEP] Erro ao buscar endereço (type=${e.runtimeType})',
          error: e, st: st);
      widget.showSnack('Erro ao buscar CEP. Verifique sua conexão.');
    }
  }

// ---------------------------------------------------------------------
// COLUNA ESQUERDA – ITENS (checkout e-commerce)
// ---------------------------------------------------------------------
  Widget _left(BuildContext context) {
    final theme = Theme.of(context);
    final cu = _cartUi;
    final mq = MediaQuery.sizeOf(context);
    final compact = mq.width < 420;
    final border = Color.alphaBlend(
      cu.inputBorderColor.withOpacity(0.38),
      cu.cartCardBackground,
    );

    final productNameColor = widget.productNameColor ?? cu.primaryTextColor;
    final productPriceColor = widget.productPriceColor ?? cu.summaryTotalColor;
    final tPedido = _totals;
    final nUnidades = _quantidadeUnidadesCarrinho();
    // Mesmo valor e formatação que "Total a pagar" no resumo lateral
    // ([computeCatalogCheckoutTotals] / [_fmt2]).
    final totalTopoFmt = 'R\$ ${_fmt2(tPedido.total)}';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cu.cartCardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 16 : 18,
          compact ? 16 : 18,
          compact ? 12 : 16,
          compact ? 16 : 18,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'ITENS DO PEDIDO',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.35,
                      color: cu.sectionTitleColor.withOpacity(0.88),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Revise produtos e quantidades',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.3,
                color: cu.mutedTextColor,
              ),
            ),
            if (widget.items.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '$nUnidades ${nUnidades == 1 ? 'item' : 'itens'} · Total a pagar $totalTopoFmt',
                style: TextStyle(
                  fontSize: compact ? 13 : 14,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                  color: productPriceColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
            SizedBox(height: compact ? 14 : 16),
            Divider(height: 1, thickness: 1, color: cu.itemDividerColor),
            SizedBox(height: compact ? 10 : 12),
            if (widget.items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 26),
                child: Row(
                  children: [
                    Icon(
                      Icons.remove_shopping_cart_outlined,
                      color: cu.mutedTextColor,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Seu carrinho está vazio.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cu.secondaryTextColor,
                          height: 1.35,
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
                separatorBuilder: (_, __) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    indent: compact ? 76 : 80,
                    color: cu.itemDividerColor,
                  ),
                ),
                itemBuilder: (_, i) {
                  final item = widget.items[i];
                  final name = (item['name'] ?? item['nome'] ?? '').toString();
                  final sub = _cartItemVariantSubtitle(item);

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
                  final price = (item['preco'] as num?)?.toDouble() ?? 0.0;
                  final pctPix =
                      (item['percentualDescontoPix'] as num?)?.toDouble() ??
                          0.0;
                  final precoEfetivo =
                      (_pagamento.toUpperCase() == 'PIX' && pctPix > 0)
                          ? price * (1 - pctPix / 100)
                          : price;
                  final total = precoEfetivo * qty;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: compact ? 64 : 68,
                            height: compact ? 64 : 68,
                            child: CatalogImagePlaceholder(
                              url: fixedImageUrl,
                              resolvedLojaId: widget.lojaId,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        SizedBox(width: compact ? 12 : 14),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 1, right: 2),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: compact ? 14 : 15,
                                    height: 1.25,
                                    letterSpacing: -0.15,
                                    color: productNameColor,
                                  ),
                                ),
                                if (sub.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  _cartItemDetailText(sub, item),
                                ],
                                SizedBox(height: compact ? 8 : 10),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    CatalogCartLineQuantitySection(
                                      items: widget.items,
                                      catalogProducts: widget.catalogProducts,
                                      lineIndex: i,
                                      onQuantityDelta: _changeLineQuantity,
                                      primaryTextColor: cu.primaryTextColor,
                                      mutedTextColor: cu.mutedTextColor,
                                      inputBorderColor: cu.inputBorderColor,
                                      inputBackground: cu.inputBackground,
                                    ),
                                    const Spacer(),
                                    Text(
                                      'R\$ ${_fmt2(total)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: compact ? 14 : 15,
                                        letterSpacing: -0.2,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
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
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          style: IconButton.styleFrom(
                            foregroundColor:
                                cu.removeIconColor.withOpacity(0.75),
                            hoverColor: cu.removeIconColor.withOpacity(0.08),
                          ),
                          tooltip: 'Remover item',
                          icon: Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: cu.removeIconColor.withOpacity(0.85),
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
// COLUNA CENTRAL – DADOS DO CLIENTE / ENTREGA (checkout e-commerce)
// ---------------------------------------------------------------------
  Widget _centerForm(BuildContext context) {
    final theme = Theme.of(context);
    final cu = _cartUi;
    final compact = MediaQuery.sizeOf(context).width < 420;
    final border = Color.alphaBlend(
      cu.inputBorderColor.withOpacity(0.38),
      cu.cartCardBackground,
    );

    InputDecoration deco(String label, {String? hint, String? campoKey}) {
      final hasError = campoKey != null && _camposComErro.contains(campoKey);
      const erroColor = Color(0xFFEF4444);
      final borderIdle = Color.alphaBlend(
        cu.inputBorderColor.withOpacity(0.65),
        cu.inputBackground,
      );
      return InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(
          color: cu.inputHintColor.withOpacity(0.88),
          fontWeight: FontWeight.w400,
          fontSize: 14,
        ),
        labelStyle: TextStyle(
          color: hasError ? erroColor : cu.secondaryTextColor,
          fontWeight: FontWeight.w600,
          fontSize: 12,
          letterSpacing: -0.1,
        ),
        filled: true,
        fillColor: hasError ? erroColor.withOpacity(0.08) : cu.inputBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: hasError ? erroColor : borderIdle,
            width: 1,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: hasError ? erroColor : borderIdle,
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: hasError ? erroColor : widget.primary,
            width: 1.5,
          ),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: compact ? 14 : 16,
          vertical: compact ? 13 : 14,
        ),
      );
    }

    return Theme(
      data: Theme.of(context).copyWith(
        textTheme: Theme.of(context).textTheme.apply(
              bodyColor: cu.primaryTextColor,
              displayColor: cu.primaryTextColor,
            ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cu.cartCardBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 16 : 18,
            compact ? 16 : 18,
            compact ? 16 : 18,
            compact ? 18 : 18,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_erroValidacao != null) ...[
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFFEF4444).withOpacity(0.5)),
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
              Text(
                'DADOS E ENTREGA',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.35,
                  color: cu.sectionTitleColor.withOpacity(0.88),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Informações para contato e envio',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.3,
                  color: cu.mutedTextColor,
                ),
              ),
              SizedBox(height: compact ? 14 : 16),

              // Largura real do painel (não a tela inteira) — evita CPF/telefone espremidos na coluna do checkout.
              LayoutBuilder(
                builder: (context, constraints) {
                  final stackContactFields = constraints.maxWidth < 640;
                  if (stackContactFields) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _nome,
                          style: TextStyle(
                            color: cu.inputTextColor,
                            fontSize: 15,
                            height: 1.25,
                          ),
                          decoration: deco('Nome completo *', campoKey: 'nome'),
                          onChanged: (_) {
                            _limparErroCampo('nome');
                            _scheduleFormSave();
                          },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _cpf,
                          style: TextStyle(
                            color: cu.inputTextColor,
                            fontSize: 15,
                            height: 1.25,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                          keyboardType: kKeyboardDecimal,
                          decoration: deco('CPF *', campoKey: 'cpf'),
                          onChanged: (_) {
                            _limparErroCampo('cpf');
                            _scheduleFormSave();
                          },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          style: TextStyle(
                            color: cu.inputTextColor,
                            fontSize: 15,
                            height: 1.25,
                          ),
                          decoration: deco('E-mail *', campoKey: 'email'),
                          onChanged: (_) {
                            _limparErroCampo('email');
                            _scheduleFormSave();
                          },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _tel,
                          keyboardType: TextInputType.phone,
                          style: TextStyle(
                            color: cu.inputTextColor,
                            fontSize: 15,
                            height: 1.25,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                          decoration:
                              deco('Telefone / WhatsApp *', campoKey: 'tel'),
                          onChanged: (_) {
                            _limparErroCampo('tel');
                            _scheduleFormSave();
                          },
                        ),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _nome,
                              style: TextStyle(
                                color: cu.inputTextColor,
                                fontSize: 15,
                                height: 1.25,
                              ),
                              decoration:
                                  deco('Nome completo *', campoKey: 'nome'),
                              onChanged: (_) {
                                _limparErroCampo('nome');
                                _scheduleFormSave();
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _cpf,
                              style: TextStyle(
                                color: cu.inputTextColor,
                                fontSize: 15,
                                height: 1.25,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                              keyboardType: kKeyboardDecimal,
                              decoration: deco('CPF *', campoKey: 'cpf'),
                              onChanged: (_) {
                                _limparErroCampo('cpf');
                                _scheduleFormSave();
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _email,
                              keyboardType: TextInputType.emailAddress,
                              style: TextStyle(
                                color: cu.inputTextColor,
                                fontSize: 15,
                                height: 1.25,
                              ),
                              decoration: deco('E-mail *', campoKey: 'email'),
                              onChanged: (_) {
                                _limparErroCampo('email');
                                _scheduleFormSave();
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _tel,
                              keyboardType: TextInputType.phone,
                              style: TextStyle(
                                color: cu.inputTextColor,
                                fontSize: 15,
                                height: 1.25,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                              decoration: deco('Telefone / WhatsApp *',
                                  campoKey: 'tel'),
                              onChanged: (_) {
                                _limparErroCampo('tel');
                                _scheduleFormSave();
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),

              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Endereço de entrega',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        letterSpacing: -0.15,
                        color: cu.secondaryTextColor,
                      ),
                    ),
                  ),
                  Flexible(
                    fit: FlexFit.loose,
                    child: TextButton.icon(
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
                        // SnackBar no messenger do overlay do carrinho (parent injeta showCartSnack).
                        widget.showSnack(msg);
                      },
                      icon: const Icon(Icons.history, size: 18),
                      label: const Text('Usar último endereço'),
                      style: TextButton.styleFrom(
                        foregroundColor: widget.primary,
                      ),
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
                        _scheduleFormSave();
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
                      onChanged: (_) {
                        _limparErroCampo('rua');
                        _scheduleFormSave();
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _numero,
                      keyboardType: kKeyboardDecimal,
                      decoration: deco('Número *', campoKey: 'numero'),
                      onChanged: (_) {
                        _limparErroCampo('numero');
                        _scheduleFormSave();
                      },
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
                      onChanged: (_) {
                        _limparErroCampo('bairro');
                        _scheduleFormSave();
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _cidade,
                      decoration: deco('Cidade *', campoKey: 'cidade'),
                      onChanged: (_) {
                        _limparErroCampo('cidade');
                        _scheduleFormSave();
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _estado,
                      decoration: deco('UF *', campoKey: 'estado'),
                      onChanged: (_) {
                        _limparErroCampo('estado');
                        _scheduleFormSave();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              TextField(
                controller: _complemento,
                decoration: deco('Complemento'),
                onChanged: (_) => _scheduleFormSave(),
              ),
              const SizedBox(height: 10),

              TextField(
                controller: _obs,
                maxLines: 2,
                decoration: deco('Observações (opcional)'),
                onChanged: (_) => _scheduleFormSave(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Painel de seção estilo checkout de loja (borda leve, sem “card boutique”).
  Widget _commercePanel({
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    final cu = _cartUi;
    final border = Color.alphaBlend(
      cu.inputBorderColor.withOpacity(0.38),
      cu.cartCardBackground,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cu.cartCardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.35,
                color: cu.sectionTitleColor.withOpacity(0.88),
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: cu.mutedTextColor,
                ),
              ),
            ],
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  /// Avisos de checkout visíveis no próprio carrinho (peso, frete, etc.).
  Widget _cartCheckoutAvisosBanner(BuildContext context) {
    final cu = _cartUi;
    final mq = MediaQuery.sizeOf(context).width;
    final pad = mq < 420 ? 12.0 : 14.0;

    Widget tile({
      required IconData icon,
      required Color accent,
      required String text,
      VoidCallback? onDismiss,
    }) {
      return Material(
        color:
            Color.alphaBlend(accent.withOpacity(0.12), cu.cartCardBackground),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.fromLTRB(pad, pad * 0.85, pad * 0.5, pad * 0.85),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: accent, size: 22),
              SizedBox(width: pad * 0.75),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    color: cu.primaryTextColor.withOpacity(0.94),
                    fontSize: 13.5,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (onDismiss != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close_rounded,
                      size: 20, color: cu.mutedTextColor),
                  onPressed: onDismiss,
                ),
            ],
          ),
        ),
      );
    }

    final children = <Widget>[];
    final peso = _avisoCheckoutPeso;
    if (peso != null && peso.isNotEmpty) {
      children.add(
        tile(
          icon: Icons.scale_outlined,
          accent: Colors.orange.shade800,
          text: peso,
          onDismiss: () => setState(() => _avisoCheckoutPeso = null),
        ),
      );
    }
    final freteA = _avisoCheckoutFrete;
    if (freteA != null && freteA.isNotEmpty) {
      if (children.isNotEmpty) children.add(const SizedBox(height: 10));
      children.add(
        tile(
          icon: Icons.local_shipping_outlined,
          accent: Colors.blue.shade800,
          text: freteA,
          onDismiss: () => setState(() => _avisoCheckoutFrete = null),
        ),
      );
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  /// Frete, pagamento, cupom e roleta — coluna principal (antes do resumo / CTAs).
  Widget _checkoutFulfillmentAndPayment(BuildContext context) {
    final theme = Theme.of(context);
    final cu = _cartUi;
    final compact = MediaQuery.sizeOf(context).width < 420;
    final Color campoBg = cu.inputBackground;
    final Color bordaCampo = cu.inputBorderColor;
    final Color textoCampo = cu.inputTextColor;
    final Color textoLabel = cu.sectionTitleColor;
    final Color textoMutado = cu.mutedTextColor;

    TextStyle checkoutSectionTitle() => TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 12.5,
          letterSpacing: 0.28,
          height: 1.35,
          color: textoLabel.withOpacity(0.92),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _commercePanel(
          title: 'ENTREGA',
          subtitle: 'Opção de envio ou retirada',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _cartCheckoutAvisosBanner(context),
              if (_fretesLocal.isNotEmpty)
                InkWell(
                  onTap: () => _mostrarOpcoesDeFrete(context),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 14 : 15,
                      vertical: compact ? 13 : 14,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Color.alphaBlend(
                          bordaCampo.withOpacity(0.55),
                          campoBg,
                        ),
                      ),
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
                              final precoTexto = _freteGratis
                                  ? 'Grátis'
                                  : 'R\$ ${_fmt2(valor)}';

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    nome,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: textoCampo,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '$precoTexto${prazo.isNotEmpty ? ' · $prazo' : ''}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: textoCampo.withOpacity(0.72),
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
              if (_fretesLocal.isEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Color.alphaBlend(
                        bordaCampo.withOpacity(0.55),
                        campoBg,
                      ),
                    ),
                    color: campoBg,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          color: textoCampo.withOpacity(0.6), size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Calcule o frete digitando seu CEP acima',
                          style: TextStyle(
                              color: textoCampo.withOpacity(0.72),
                              fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        SizedBox(height: compact ? 14 : 16),
        _commercePanel(
          title: 'PAGAMENTO E CUPOM',
          subtitle: 'Forma de pagamento e benefícios',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Forma de pagamento', style: checkoutSectionTitle()),
              const SizedBox(height: 8),
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Color.alphaBlend(
                      bordaCampo.withOpacity(0.55),
                      campoBg,
                    ),
                  ),
                  color: campoBg,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _pagamento,
                    isExpanded: true,
                    borderRadius: BorderRadius.circular(10),
                    dropdownColor: campoBg,
                    iconEnabledColor: textoCampo,
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 12 : 14,
                      vertical: 4,
                    ),
                    style: TextStyle(
                      color: textoCampo,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
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
              Text('Cupom de desconto', style: checkoutSectionTitle()),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _cupomCtrl,
                      style: TextStyle(
                        color: textoCampo,
                        fontSize: 15,
                        height: 1.25,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Digite o cupom',
                        hintStyle: TextStyle(
                          color: textoMutado.withOpacity(0.88),
                          fontSize: 14,
                        ),
                        filled: true,
                        fillColor: campoBg,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: compact ? 14 : 16,
                          vertical: compact ? 14 : 15,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: Color.alphaBlend(
                              bordaCampo.withOpacity(0.55),
                              campoBg,
                            ),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: Color.alphaBlend(
                              bordaCampo.withOpacity(0.55),
                              campoBg,
                            ),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: widget.primary,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _aplicarCupom,
                    style: FilledButton.styleFrom(
                      backgroundColor: cu.primaryActionBackground,
                      foregroundColor: cu.primaryActionTextColor,
                      elevation: 0,
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 16 : 20,
                        vertical: compact ? 14 : 15,
                      ),
                      minimumSize: Size(0, compact ? 48 : 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Aplicar',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, letterSpacing: 0.1),
                    ),
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
                      final Map<String, dynamic> m;
                      if (cupomEscolhido is Cupom) {
                        m = _cupomMapFromCupom(cupomEscolhido);
                      } else if (cupomEscolhido is Map) {
                        m = Map<String, dynamic>.from(cupomEscolhido);
                      } else {
                        m = {};
                      }
                      if (catalogCupomSomenteFrete(m)) {
                        _cupomFreteAplicado = m;
                      } else {
                        _cupomDescontoAplicado = m;
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
                label: const Text(
                  'Selecionar cupom',
                  style: TextStyle(
                      fontWeight: FontWeight.w500, letterSpacing: 0.05),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: cu.secondaryActionTextColor,
                  side: BorderSide(
                    color: cu.secondaryActionTextColor.withOpacity(0.38),
                    width: 1.05,
                  ),
                  padding: EdgeInsets.symmetric(
                    vertical: compact ? 13 : 14,
                    horizontal: 14,
                  ),
                  minimumSize: Size(0, compact ? 46 : 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              if (_cupomDescontoAplicado != null) ...[
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
                        'Desconto: '
                                '${(_cupomDescontoAplicado!['codigo'] ?? _cupomDescontoAplicado!['code'] ?? '')}'
                            .toString()
                            .toUpperCase(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: textoCampo,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remover cupom de desconto',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.close_rounded,
                          size: 20, color: textoMutado),
                      onPressed: () =>
                          setState(() => _cupomDescontoAplicado = null),
                    ),
                  ],
                ),
              ],
              if (_cupomFreteAplicado != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.local_shipping_outlined,
                      size: 18,
                      color: Colors.teal.shade700,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Frete: '
                                '${(_cupomFreteAplicado!['codigo'] ?? _cupomFreteAplicado!['code'] ?? '')}'
                            .toString()
                            .toUpperCase(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: textoCampo,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remover cupom de frete',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.close_rounded,
                          size: 20, color: textoMutado),
                      onPressed: () =>
                          setState(() => _cupomFreteAplicado = null),
                    ),
                  ],
                ),
              ],
              if (_cupomRoletaCodigo != null &&
                  _cupomRoletaCodigo!.isNotEmpty &&
                  _cupomDescontoAplicado == null &&
                  _cupomFreteAplicado == null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.stars, size: 18, color: Colors.amber[700]),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Cupom da roleta: ${_cupomRoletaCodigo!.toUpperCase()}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: textoCampo),
                      ),
                    ),
                  ],
                ),
              ],
              Builder(
                builder: (context) {
                  if (!_roletaAtiva) {
                    return const SizedBox.shrink();
                  }
                  if (kDebugMode) {
                    logD('🎰 Verificando exibição da roleta:');
                    logD('   _roletaAtiva: $_roletaAtiva');
                    logD('   _roletaJaGirada: $_roletaJaGirada');
                    logD(
                        '   _todosOsDadosPreenchidos: $_todosOsDadosPreenchidos');
                    logD('   _podeExibirRoleta: $_podeExibirRoleta');
                  }

                  if (_podeExibirRoleta) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 16),
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
                              Icon(Icons.stars, color: Colors.black, size: 24),
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
                          lojaId: widget.lojaId,
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
                    final atingiuValorMinimo = _subtotal >= _valorMinimoRoleta;

                    if (!_todosOsDadosPreenchidos && atingiuValorMinimo) {
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
              if (_checkoutError != null && _checkoutError!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
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
                          style: TextStyle(
                              color: Colors.red.shade900, fontSize: 14),
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
            ],
          ),
        ),
      ],
    );
  }

// ---------------------------------------------------------------------
// COLUNA DIREITA – RESUMO + CTAs (checkout e-commerce)
// ---------------------------------------------------------------------
  Widget _right(
    BuildContext context,
    CatalogCheckoutTotals tSnap,
    Map<String, dynamic> frete,
  ) {
    final theme = Theme.of(context);
    final total = tSnap.total;
    final descontoProdutos = tSnap.descontoCupomProdutos;
    final descontoFreteCupom = tSnap.descontoCupomFrete;
    final freteLabel = _freteGratis
        ? 'Cupom de frete grátis'
        : (frete['nome'] ?? frete['label'] ?? 'Entrega').toString();

    final double valorFreteFinal = tSnap.valorFreteFinal;

    final s = _summaryTokens;
    final cu = _cartUi;
    final compact = MediaQuery.sizeOf(context).width < 420;

    final sidebarBorder = Color.alphaBlend(
      cu.inputBorderColor.withOpacity(0.4),
      cu.summaryCardBackground,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cu.summaryCardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: sidebarBorder),
        boxShadow: [
          BoxShadow(
            color: s.cardShadowColor.withOpacity(0.12),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 16 : 18,
          compact ? 18 : 20,
          compact ? 16 : 18,
          compact ? 18 : 20,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'RESUMO DO PEDIDO',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.35,
                color: cu.sectionTitleColor.withOpacity(0.88),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Confira valores antes de finalizar',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.3,
                color: cu.mutedTextColor,
              ),
            ),

            SizedBox(height: compact ? 14 : 16),

            // Valores (visual plano, tipo checkout de loja)
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 12 : 14,
                vertical: compact ? 14 : 15,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: Color.alphaBlend(
                  s.panelGradientStart.withOpacity(0.14),
                  cu.summaryCardBackground,
                ),
                border: Border.all(
                  color: cu.inputBorderColor.withOpacity(0.28),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_pagamento.toUpperCase() == 'PIX' &&
                      _subtotalPix < _subtotal) ...[
                    _resumeRow(
                      catalogSubtotalBeforePixItemDiscountLabel(_pagamento),
                      _subtotal,
                      labelColor: cu.summaryLabelColor,
                      valueColor: cu.summaryValueColor,
                      sum: s,
                    ),
                    _resumeRow(
                      'Desconto PIX',
                      -(_subtotal - _subtotalPix),
                      strOverride: '- R\$ ${_fmt2(_subtotal - _subtotalPix)}',
                      labelColor: cu.summaryLabelColor,
                      valueColor: s.pixDiscountValueColor,
                      sum: s,
                    ),
                    _resumeRow(
                      'Subtotal produtos',
                      _subtotalPix,
                      labelColor: cu.summaryLabelColor,
                      valueColor: cu.summaryValueColor,
                      sum: s,
                    ),
                  ] else
                    _resumeRow(
                      'Subtotal',
                      _subtotalConformePagamento,
                      labelColor: cu.summaryLabelColor,
                      valueColor: cu.summaryValueColor,
                      sum: s,
                    ),

                  if (descontoProdutos > 0)
                    _resumeRow(
                      'Descontos',
                      -descontoProdutos,
                      highlight: true,
                      labelColor: cu.summaryLabelColor,
                      valueColor: cu.summaryDiscountColor,
                      sum: s,
                    ),

                  if (descontoFreteCupom > 0)
                    _resumeRow(
                      'Desconto no frete (cupom)',
                      -descontoFreteCupom,
                      highlight: true,
                      labelColor: cu.summaryLabelColor,
                      valueColor: cu.summaryDiscountColor,
                      sum: s,
                    ),

                  // ✅ frete com label e valor corretos
                  _resumeRow(
                    freteLabel,
                    valorFreteFinal,
                    strOverride: _freteGratis
                        ? 'R\$ 0,00'
                        : 'R\$ ${_fmt2(valorFreteFinal)}',
                    labelColor: cu.summaryLabelColor,
                    valueColor: cu.summaryValueColor,
                    sum: s,
                  ),

                  SizedBox(height: compact ? 12 : 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text(
                          'Total a pagar',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                            letterSpacing: -0.05,
                            color: cu.summaryLabelColor.withOpacity(0.95),
                          ),
                        ),
                      ),
                      Text(
                        'R\$ ${_fmt2(total)}',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: cu.summaryTotalColor,
                          fontWeight: FontWeight.w700,
                          fontSize: compact ? 21 : 22,
                          letterSpacing: -0.45,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            SizedBox(height: compact ? 18 : 22),

            // BOTÃO WHATSAPP
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: _processandoCheckout
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cu.whatsappButtonTextColor,
                        ),
                      )
                    : const FaIcon(
                        FontAwesomeIcons.whatsapp,
                        size: 18,
                      ),
                label: Text(
                  _processandoCheckout
                      ? 'Processando...'
                      : 'Finalizar pelo WhatsApp',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.15,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: cu.whatsappButtonBackground,
                  foregroundColor: cu.whatsappButtonTextColor,
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  padding: EdgeInsets.symmetric(
                    vertical: compact ? 15 : 16,
                  ),
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _processandoCheckout
                    ? null
                    : () async {
                        if (!_validarItensComPreco()) return;
                        if (!_validarCampos()) return;
                        if (!await _dialogBeneficioCadastroOuSeguir()) return;
                        if (!mounted) return;

                        // ✅ MARCA COMO PROCESSANDO
                        setState(() {
                          _processandoCheckout = true;
                        });
                        await Future.delayed(Duration.zero);

                        final cupomIdDesc = _cupomDescontoIdFirestore();
                        final cupomIdFrete = _cupomFreteIdFirestore();
                        final clienteLogado =
                            await ClienteAuthService.getClienteLogado();
                        final clienteId =
                            clienteLogado?['clienteId']?.toString();

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
                              : (freteSelecionado['nome'] ??
                                      freteSelecionado['label'] ??
                                      'Entrega')
                                  .toString();
                          final entrega = {
                            'nome': nomeFretePedido,
                            'valor': _totals.valorFreteFinal,
                            'freteGratis': _freteGratis,
                            'tipo': freteSelecionado['tipo'] ?? 'padrao',
                            if (freteSelecionado['plataforma'] != null)
                              'plataforma': freteSelecionado['plataforma'],
                            if (freteSelecionado['service_id'] != null)
                              'service_id': freteSelecionado['service_id'],
                            if (freteSelecionado['servico_id'] != null)
                              'servico_id': freteSelecionado['servico_id'],
                          };

                          await widget.onCheckoutWhatsapp(
                            customer: customer,
                            entrega: entrega,
                            pagamento: _pagamento,
                            observacao: _obs.text.trim(),
                            cupomRoletaCodigo: _cupomRoletaCodigo,
                            cupomRoletaDesconto: _cupomRoletaDesconto,
                            premioRoletaDescricao: _premioRoletaDescricao,
                            cupomCodigo: _cupomCodigoParaPedido(),
                            cupomFreteCodigo: _cupomFreteCodigoParaPedido(),
                            descontoCupom: _totals.descontoCupom,
                            valorTotalCheckout: _totals.total,
                            onSuccess: (String? pedidoId) async {
                              if (mounted) Navigator.pop(context);
                              if (clienteId != null && clienteId.isNotEmpty) {
                                if (cupomIdDesc != null &&
                                    cupomIdDesc.isNotEmpty) {
                                  CupomDescontoService().registrarUso(
                                    lojaId: widget.lojaId,
                                    cupomId: cupomIdDesc,
                                    clienteId: clienteId,
                                  );
                                }
                                if (cupomIdFrete != null &&
                                    cupomIdFrete.isNotEmpty) {
                                  CupomDescontoService().registrarUso(
                                    lojaId: widget.lojaId,
                                    cupomId: cupomIdFrete,
                                    clienteId: clienteId,
                                  );
                                }
                              }
                              final cRoleta = _cupomPorOrigem('roleta_sorte');
                              if (cRoleta != null) {
                                final email = (clienteLogado?['email'] ??
                                        customer['email'] ??
                                        '')
                                    .toString()
                                    .trim();
                                final codigo = _codigoCupomMap(cRoleta);
                                if (email.isNotEmpty && codigo.isNotEmpty) {
                                  await ClienteAuthService
                                      .marcarCupomRoletaComoUsado(
                                    lojaId: widget.lojaId,
                                    email: email,
                                    codigo: codigo,
                                  );
                                }
                              }
                              final cIndic = _cupomPorOrigem('cupom_cliente');
                              if (cIndic != null &&
                                  (pedidoId ?? '').isNotEmpty) {
                                final cupomClienteId =
                                    (cIndic['id'] ?? '').toString();
                                if (cupomClienteId.isNotEmpty) {
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
            if (_pixApenasComChaveDaLoja) ...[
              SizedBox(height: compact ? 10 : 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: _processandoCheckout
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: cu.pixButtonTextColor,
                          ),
                        )
                      : Icon(Icons.pix, size: 22, color: cu.pixButtonTextColor),
                  label: Text(
                    _processandoCheckout ? 'Processando...' : 'Pagar com PIX',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cu.pixButtonTextColor,
                    side: BorderSide(
                      color: cu.pixButtonBorderColor.withOpacity(0.85),
                      width: 1.1,
                    ),
                    padding: EdgeInsets.symmetric(vertical: compact ? 14 : 15),
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onPressed: _processandoCheckout
                      ? null
                      : () async {
                          if (!_validarItensComPreco()) return;
                          if (!_validarCampos()) return;
                          if (!await _dialogBeneficioCadastroOuSeguir()) return;
                          if (!mounted) return;
                          setState(() {
                            _processandoCheckout = true;
                            _checkoutError = null;
                          });
                          try {
                            await Future.delayed(Duration.zero);
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
                                : (freteSelecionado['nome'] ??
                                        freteSelecionado['label'] ??
                                        'Entrega')
                                    .toString();
                            final entrega = {
                              'nome': nomeFretePedidoPix,
                              'valor': _totals.valorFreteFinal,
                              'freteGratis': _freteGratis,
                              'tipo': freteSelecionado['tipo'] ?? 'padrao',
                              if (freteSelecionado['plataforma'] != null)
                                'plataforma': freteSelecionado['plataforma'],
                              if (freteSelecionado['service_id'] != null)
                                'service_id': freteSelecionado['service_id'],
                              if (freteSelecionado['servico_id'] != null)
                                'servico_id': freteSelecionado['servico_id'],
                            };
                            final cupomCod = _cupomCodigoParaPedido() ?? '';
                            final cupomIdDesc = _cupomDescontoIdFirestore();
                            final cupomIdFrete = _cupomFreteIdFirestore();
                            final clienteLogadoPix =
                                await ClienteAuthService.getClienteLogado();
                            final clienteIdPix =
                                clienteLogadoPix?['clienteId']?.toString();
                            await widget.onCheckoutPix!(
                              customer: customer,
                              entrega: entrega,
                              valorTotal: total,
                              observacao: _obs.text.trim(),
                              cupomCodigo: cupomCod.isEmpty ? null : cupomCod,
                              cupomFreteCodigo: _cupomFreteCodigoParaPedido(),
                              desconto: _totals.descontoCupom,
                              cupomRoletaCodigo: _cupomRoletaCodigo,
                              cupomRoletaDesconto: _cupomRoletaDesconto,
                              premioRoletaDescricao: _premioRoletaDescricao,
                              showErrorInCart: (msg) {
                                if (mounted) {
                                  setState(() => _checkoutError = msg);
                                }
                              },
                              onPedidoCriado: (pedidoId) async {
                                if (clienteIdPix != null &&
                                    clienteIdPix.isNotEmpty) {
                                  if (cupomIdDesc != null &&
                                      cupomIdDesc.isNotEmpty) {
                                    await CupomDescontoService().registrarUso(
                                      lojaId: widget.lojaId,
                                      cupomId: cupomIdDesc,
                                      clienteId: clienteIdPix,
                                    );
                                  }
                                  if (cupomIdFrete != null &&
                                      cupomIdFrete.isNotEmpty) {
                                    await CupomDescontoService().registrarUso(
                                      lojaId: widget.lojaId,
                                      cupomId: cupomIdFrete,
                                      clienteId: clienteIdPix,
                                    );
                                  }
                                }
                                final cRoleta = _cupomPorOrigem('roleta_sorte');
                                if (cRoleta != null) {
                                  final email = (clienteLogadoPix?['email'] ??
                                          customer['email'] ??
                                          '')
                                      .toString()
                                      .trim();
                                  final cod = _codigoCupomMap(cRoleta);
                                  if (email.isNotEmpty && cod.isNotEmpty) {
                                    await ClienteAuthService
                                        .marcarCupomRoletaComoUsado(
                                      lojaId: widget.lojaId,
                                      email: email,
                                      codigo: cod,
                                    );
                                  }
                                }
                                final cIndic = _cupomPorOrigem('cupom_cliente');
                                if (cIndic != null &&
                                    pedidoId != null &&
                                    pedidoId.isNotEmpty) {
                                  final cupomClienteId =
                                      (cIndic['id'] ?? '').toString();
                                  if (cupomClienteId.isNotEmpty) {
                                    await CuponsService.usarCupom(
                                      lojaId: widget.lojaId,
                                      cupomId: cupomClienteId,
                                      pedidoId: pedidoId,
                                    );
                                  }
                                }
                              },
                            );
                          } finally {
                            if (mounted) {
                              setState(() => _processandoCheckout = false);
                            }
                          }
                        },
                ),
              ),
            ],
            // MERCADO PAGO / integração: não duplicar PIX (chave já exibida acima).
            if (!_pixApenasComChaveDaLoja &&
                _pagamento.toUpperCase() != 'DINHEIRO') ...[
              SizedBox(height: compact ? 10 : 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: _processandoCheckout
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: cu.secondaryActionTextColor,
                          ),
                        )
                      : Icon(
                          _pagamento.toUpperCase() == 'PIX'
                              ? Icons.pix
                              : Icons.payment,
                          size: 22,
                          color: cu.secondaryActionTextColor,
                        ),
                  label: Text(
                    _processandoCheckout
                        ? 'Processando...'
                        : (_pagamento.toUpperCase() == 'PIX'
                            ? 'Pagar com PIX'
                            : widget.checkoutButtonLabel),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.08,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cu.secondaryActionTextColor,
                    side: BorderSide(
                      color: cu.secondaryActionTextColor.withOpacity(0.42),
                      width: 1.1,
                    ),
                    padding: EdgeInsets.symmetric(vertical: compact ? 14 : 15),
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onPressed: _processandoCheckout
                      ? null
                      : () async {
                          if (!_validarItensComPreco()) return;
                          if (!_validarCampos()) return;
                          if (!await _dialogBeneficioCadastroOuSeguir()) return;
                          if (!mounted) return;
                          setState(() {
                            _processandoCheckout = true;
                            _checkoutError = null;
                          });
                          await Future.delayed(Duration.zero);
                          try {
                            if (!mounted) return;
                            if (!context.mounted) return;
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
                                : (freteSelecionado['nome'] ??
                                        freteSelecionado['label'] ??
                                        'Entrega')
                                    .toString();
                            final entrega = {
                              'nome': nomeFretePedidoMp,
                              'valor': _totals.valorFreteFinal,
                              'freteGratis': _freteGratis,
                              'tipo': freteSelecionado['tipo'] ?? 'padrao',
                              if (freteSelecionado['plataforma'] != null)
                                'plataforma': freteSelecionado['plataforma'],
                              if (freteSelecionado['service_id'] != null)
                                'service_id': freteSelecionado['service_id'],
                              if (freteSelecionado['servico_id'] != null)
                                'servico_id': freteSelecionado['servico_id'],
                            };

                            await widget.onCheckoutMercadoPago(
                              customer: customer,
                              entrega: entrega,
                              pagamento: _pagamento,
                              observacao: _obs.text.trim(),
                              cupomRoletaCodigo: _cupomRoletaCodigo,
                              cupomRoletaDesconto: _cupomRoletaDesconto,
                              premioRoletaDescricao: _premioRoletaDescricao,
                              cupomCodigo: _cupomCodigoParaPedido(),
                              cupomFreteCodigo: _cupomFreteCodigoParaPedido(),
                              descontoCupom: _totals.descontoCupom,
                              valorTotalCheckout: _totals.total,
                              showErrorInCart: (msg) {
                                if (mounted) {
                                  setState(() => _checkoutError = msg);
                                }
                              },
                            );
                            final cRoletaMp = _cupomPorOrigem('roleta_sorte');
                            if (cRoletaMp != null) {
                              final clientePosMp =
                                  await ClienteAuthService.getClienteLogado();
                              final emailMp = (clientePosMp?['email'] ??
                                      customer['email'] ??
                                      '')
                                  .toString()
                                  .trim();
                              final codigoMp = _codigoCupomMap(cRoletaMp);
                              if (emailMp.isNotEmpty && codigoMp.isNotEmpty) {
                                await ClienteAuthService
                                    .marcarCupomRoletaComoUsado(
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
    Color? valueColor,
    Color? labelColor,
    String? strOverride,
    required CatalogCheckoutSummaryTokens sum,
  }) {
    final vc = valueColor ?? sum.rowValueColor;
    final lc = labelColor ?? sum.rowLabelColor;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                height: 1.3,
                letterSpacing: -0.05,
                color: lc.withOpacity(0.94),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            strOverride ?? 'R\$ ${_fmt2(valor)}',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 13,
              fontWeight: highlight ? FontWeight.w600 : FontWeight.w500,
              letterSpacing: -0.1,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: vc,
            ),
          ),
        ],
      ),
    );
  }
}
