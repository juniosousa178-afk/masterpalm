import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/carrinho_abandonado_ui.dart';
import '../core/carrinho_recuperacao_score.dart';
import '../core/access_scope_service.dart';
import '../core/hive_box_names.dart';
import '../widgets/carrinho_abandonado_details_panel.dart';
import '../services/carrinho_abandonado_service.dart';
import '../services/catalog_public_url_service.dart';
import '../services/loja_id_service.dart';
import '../services/public_store_link_helper.dart';
import '../models/venda.dart';
import 'package:hive/hive.dart';

const Color _primaryColor = Color(0xFF6366F1);
const Color _successColor = Color(0xFF22C55E);
const Color _backgroundColor = Color(0xFFF8FAFC);

class CarrinhosAbandonadosScreen extends StatefulWidget {
  final String? lojaId;

  const CarrinhosAbandonadosScreen({this.lojaId, super.key});

  @override
  State<CarrinhosAbandonadosScreen> createState() =>
      _CarrinhosAbandonadosScreenState();
}

class _CarrinhosAbandonadosScreenState
    extends State<CarrinhosAbandonadosScreen> {
  bool _loading = true;
  bool _erroResolucaoLoja = false;
  String? _lojaId;
  List<CarrinhoAbandonadoItem> _lista = [];
  List<CarrinhoAbandonadoCatalogoItem> _listaCatalogo = [];
  int _minutosAbandono = 24 * 60;
  bool _enviando = false;
  String? _enviandoEmailCartId;
  String _lojaNome = '';
  MetricasRecuperacaoCatalogo? _metricasCatalogo;
  String? _catalogPublicBaseUrl;

  String _filtroStatus = 'todos';
  String _filtroTexto = '';
  String _filtroPeriodo = kCarrinhoFiltroPeriodoTodos;
  String _filtroValor = kCarrinhoFiltroValorTodos;
  String _ordenacao = 'recente';
  final TextEditingController _buscaCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    String? id = (widget.lojaId != null && widget.lojaId!.trim().isNotEmpty)
        ? widget.lojaId
        : null;
    id ??= await LojaIdService.getWithTimeout(
        timeout: const Duration(seconds: 10));
    if (!mounted) return;
    if (id == null || id.trim().isEmpty || !isValidForPublicLink(id)) {
      setState(() {
        _loading = false;
        _erroResolucaoLoja = true;
        _lojaId = null;
      });
      return;
    }
    setState(() {
      _lojaId = id;
      _loading = true;
    });
    _catalogPublicBaseUrl =
        await CatalogPublicUrlService.montarUrlCatalogoPublicoAsync(id);
    if (!mounted) return;
    await _carregarConfig();
    await _carregar();
  }

  String _catalogBaseOrFallback() {
    final id = _lojaId;
    if (id == null) return CatalogPublicUrlService.kDefaultCatalogPublicBase;
    return _catalogPublicBaseUrl ??
        '${CatalogPublicUrlService.kDefaultCatalogPublicBase}/${Uri.encodeComponent(id)}';
  }

  String _linkRecuperacaoCatalogo(String cartId) {
    final b = _catalogBaseOrFallback();
    final sep = b.contains('?') ? '&' : '?';
    return '$b${sep}cart=${Uri.encodeComponent(cartId)}';
  }

  String _money(double v) => 'R\$ ${v.toStringAsFixed(2)}';

  RecuperacaoScoreResult _scoreCatalogo(CarrinhoAbandonadoCatalogoItem item) {
    final agora = DateTime.now();
    final ref = item.ultimoUpdate ?? item.criadoEm ?? agora;
    final total = item.totalOverride ??
        (totalCarrinhoProdutos(item.produtos) + item.frete - item.desconto);
    return calcularProbabilidadeRecuperacao(
      tempoAbandonado: agora.difference(ref),
      valorCarrinho: total,
      quantidadeItens: item.totalItens,
      clienteRecorrente: item.clienteRecorrente,
      temWhatsapp: item.telefoneEfetivo.trim().length >= 10,
      temEmail: item.clienteEmail.trim().contains('@'),
      visitasCatalogo: item.visitasCatalogo,
      retornosCatalogo: item.retornosCatalogo,
    );
  }

  List<CarrinhoAbandonadoCatalogoItem> get _catalogoFiltrado {
    var list = _listaCatalogo.where((e) {
      final valor = e.totalOverride ??
          (totalCarrinhoProdutos(e.produtos) + e.frete - e.desconto);
      return carrinhoPassaFiltrosCombinados(
        query: _filtroTexto,
        filtroStatus: _filtroStatus,
        filtroPeriodo: _filtroPeriodo,
        filtroValor: _filtroValor,
        statusRaw: e.status,
        dataRef: e.ultimoUpdate ?? e.criadoEm,
        valor: valor,
        nome: e.clienteNome,
        telefone: e.clienteTelefone,
        whatsapp: e.clienteWhatsapp,
        email: e.clienteEmail,
        cpf: e.clienteCpf,
        idExtra: e.cartId,
      );
    }).toList();
    _ordenarCatalogo(list);
    return list;
  }

  List<CarrinhoAbandonadoItem> get _lojaFiltrado {
    var list = _lista.where((e) {
      return carrinhoPassaFiltrosCombinados(
        query: _filtroTexto,
        filtroStatus: _filtroStatus,
        filtroPeriodo: _filtroPeriodo,
        filtroValor: _filtroValor,
        statusRaw: kCarrinhoStatusAbandonado,
        dataRef: e.ultimaAtualizacao,
        valor: totalCarrinhoProdutos(e.itens),
        nome: e.nome,
        telefone: e.telefone,
        whatsapp: e.telefone,
        email: e.email,
        idExtra: e.clienteId,
      );
    }).toList();
    list.sort((a, b) {
      final ta = totalCarrinhoProdutos(a.itens);
      final tb = totalCarrinhoProdutos(b.itens);
      final da = a.ultimaAtualizacao ?? DateTime.fromMillisecondsSinceEpoch(0);
      final db = b.ultimaAtualizacao ?? DateTime.fromMillisecondsSinceEpoch(0);
      switch (_ordenacao) {
        case 'valor':
          return tb.compareTo(ta);
        case 'antigo':
          return da.compareTo(db);
        case 'score':
          final sa = calcularProbabilidadeRecuperacao(
            tempoAbandonado: DateTime.now().difference(da),
            valorCarrinho: ta,
            quantidadeItens: a.totalItens,
            temWhatsapp: a.telefone.trim().length >= 10,
            temEmail: a.email.trim().contains('@'),
          );
          final sb = calcularProbabilidadeRecuperacao(
            tempoAbandonado: DateTime.now().difference(db),
            valorCarrinho: tb,
            quantidadeItens: b.totalItens,
            temWhatsapp: b.telefone.trim().length >= 10,
            temEmail: b.email.trim().contains('@'),
          );
          return sb.pontos.compareTo(sa.pontos);
        default:
          return db.compareTo(da);
      }
    });
    return list;
  }

  void _ordenarCatalogo(List<CarrinhoAbandonadoCatalogoItem> list) {
    list.sort((a, b) {
      final ta = totalCarrinhoProdutos(a.produtos);
      final tb = totalCarrinhoProdutos(b.produtos);
      final da = a.ultimoUpdate ??
          a.criadoEm ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final db = b.ultimoUpdate ??
          b.criadoEm ??
          DateTime.fromMillisecondsSinceEpoch(0);
      switch (_ordenacao) {
        case 'valor':
          return tb.compareTo(ta);
        case 'antigo':
          return da.compareTo(db);
        case 'score':
          return _scoreCatalogo(b).pontos.compareTo(_scoreCatalogo(a).pontos);
        default:
          return db.compareTo(da);
      }
    });
  }

  Future<void> _abrirDetalheCatalogo(CarrinhoAbandonadoCatalogoItem item) async {
    final link = _linkRecuperacaoCatalogo(item.cartId);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.9,
              minChildSize: 0.55,
              maxChildSize: 0.98,
              builder: (_, __) => Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: CarrinhoAbandonadoDetailsPanel(
                  item: item,
                  linkCatalogo: link,
                  enviandoEmail: _enviandoEmailCartId == item.cartId,
                  onOpenCatalog: () async {
                    final uri = Uri.parse(link);
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  },
                  onWhatsApp: () => _abrirWhatsAppCatalogo(item),
                  onEmail: () async {
                    setModal(() {});
                    await _enviarEmailCatalogo(item, setModal: setModal);
                  },
                  onCopyLink: () => _copiarTexto(link, 'Link copiado'),
                  onCopyInfo: () => _copiarTexto(
                    _infoCatalogo(item, link),
                    'Informações copiadas',
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _infoCatalogo(CarrinhoAbandonadoCatalogoItem item, String link) {
    final buf = StringBuffer();
    buf.writeln('Nome: ${item.clienteNome}');
    buf.writeln('Telefone: ${item.clienteTelefone}');
    buf.writeln('WhatsApp: ${item.telefoneEfetivo}');
    buf.writeln('Email: ${item.clienteEmail}');
    buf.writeln('CPF: ${item.clienteCpf}');
    buf.writeln('Endereço: ${item.enderecoCompleto}');
    buf.writeln('Status: ${labelStatusCarrinhoAbandonado(item.status)}');
    buf.writeln('Cupom: ${item.cupom}');
    buf.writeln('Frete: ${_money(item.frete)}');
    for (final p in item.produtos) {
      buf.writeln(
        '- ${p['nome'] ?? p['name']} x${p['quantidade'] ?? 1} '
        'cor=${p['cor'] ?? ''} tam=${p['tamanho'] ?? ''}',
      );
    }
    buf.writeln(link);
    return buf.toString();
  }

  Future<void> _abrirDetalheCliente(CarrinhoAbandonadoItem item) async {
    final catalogItem = CarrinhoAbandonadoCatalogoItem(
      cartId: item.clienteId,
      lojaId: _lojaId ?? '',
      produtos: item.itens,
      clienteNome: item.nome,
      clienteTelefone: item.telefone,
      clienteWhatsapp: item.telefone,
      clienteEmail: item.email,
      criadoEm: item.ultimaAtualizacao,
      ultimoUpdate: item.ultimaAtualizacao,
      status: kCarrinhoStatusAbandonado,
    );
    final link = _catalogBaseOrFallback();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        minChildSize: 0.55,
        maxChildSize: 0.98,
        builder: (_, __) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: CarrinhoAbandonadoDetailsPanel(
            item: catalogItem,
            linkCatalogo: link,
            enviandoEmail: _enviando,
            onOpenCatalog: () async {
              final uri = Uri.parse(link);
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            },
            onWhatsApp: () => _abrirWhatsApp(item),
            onEmail: () => _enviarEmail(item),
            onCopyLink: () => _copiarTexto(link, 'Link copiado'),
            onCopyInfo: () => _copiarTexto(
              '${item.nome}\n${item.telefone}\n${item.email}\n$link',
              'Informações copiadas',
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _carregarConfig() async {
    if (_lojaId == null) return;
    final config = await CarrinhoAbandonadoService.getConfig(_lojaId!);
    if (mounted) {
      setState(() => _minutosAbandono = config.minutosAbandono);
    }
  }

  Future<void> _carregar() async {
    if (_lojaId == null) return;
    setState(() => _loading = true);
    final lista = await CarrinhoAbandonadoService.listarCarrinhosAbandonados(
      lojaId: _lojaId!,
      minutosAbandono: _minutosAbandono,
    );
    final listaCatalogo =
        await CarrinhoAbandonadoService.listarCarrinhosAbandonadosCatalogo(
      lojaId: _lojaId!,
      minutosAbandono: _minutosAbandono,
    );
    final metricasCatalogo =
        await CarrinhoAbandonadoService.getMetricasRecuperacaoCatalogo(
            _lojaId!);
    String lojaNome = '';
    try {
      final doc = await FirebaseFirestore.instance
          .collection('lojas')
          .doc(_lojaId)
          .get();
      final d = doc.data();
      lojaNome = (d?['nome_loja'] ?? d?['nomeLoja'] ?? d?['nome'] ?? '')
          .toString()
          .trim();
    } catch (_) {}

    final scope = await AccessScopeService.loadIdentity();
    var wallet = <String>{};
    if (scope.isSeller) {
      try {
        final boxName = HiveBoxNames.vendas(_lojaId!);
        Box<Venda>? box;
        if (Hive.isBoxOpen(boxName)) {
          box = Hive.box<Venda>(boxName);
        } else {
          box = await Hive.openBox<Venda>(boxName);
        }
        wallet = AccessScopeService.buildSellerWalletKeys(
          id: scope,
          sales: box.values,
          lojaId: _lojaId,
        );
      } catch (_) {}
    }

    List<CarrinhoAbandonadoItem> listaScoped = lista;
    List<CarrinhoAbandonadoCatalogoItem> listaCatalogoScoped = listaCatalogo;
    MetricasRecuperacaoCatalogo? metricasScoped = metricasCatalogo;
    if (scope.isSeller) {
      listaScoped = lista
          .where(
            (e) => AccessScopeService.canSeeCart(
              id: scope,
              walletCustomerKeys: wallet,
              customerKey: e.clienteId,
              customerName: e.nome,
            ),
          )
          .toList();
      listaCatalogoScoped = listaCatalogo
          .where((e) {
            final raw = e.raw;
            return AccessScopeService.canSeeCart(
              id: scope,
              walletCustomerKeys: wallet,
              createdByUid: (raw['createdByUid'] ??
                      raw['criadoPorUid'] ??
                      raw['vendedorUid'] ??
                      '')
                  .toString(),
              createdByEmail: (raw['createdByEmail'] ??
                      raw['criadoPorEmail'] ??
                      raw['vendedor'] ??
                      '')
                  .toString(),
              customerName: e.clienteNome,
              customerKey: (raw['clienteId'] ?? '').toString(),
            );
          })
          .toList();
      // Métricas de loja não são exibidas ao vendedor.
      metricasScoped = null;
    }

    if (mounted) {
      setState(() {
        _lista = listaScoped;
        _listaCatalogo = listaCatalogoScoped;
        _metricasCatalogo = metricasScoped;
        _lojaNome = lojaNome;
        _loading = false;
      });
    }
    // Enriquecimento somente leitura: completa e-mail/CPF/endereço a partir de clientes.
    unawaited(_enriquecerCatalogoComClientes(listaCatalogoScoped));
  }

  Future<void> _enriquecerCatalogoComClientes(
    List<CarrinhoAbandonadoCatalogoItem> base,
  ) async {
    if (_lojaId == null || base.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('lojas')
          .doc(_lojaId)
          .collection('clientes')
          .get();
      String digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');
      final byPhone = <String, Map<String, dynamic>>{};
      for (final doc in snap.docs) {
        final d = doc.data();
        final tel = digits((d['telefone'] ?? d['whatsapp'] ?? '').toString());
        if (tel.length >= 10) byPhone[tel] = d;
      }
      final enriched = <CarrinhoAbandonadoCatalogoItem>[];
      for (final item in base) {
        final tel = digits(item.telefoneEfetivo);
        final c = tel.length >= 10 ? byPhone[tel] : null;
        if (c == null) {
          enriched.add(item);
          continue;
        }
        final email = item.clienteEmail.trim().isNotEmpty
            ? item.clienteEmail
            : (c['email'] ?? '').toString();
        final cpf = item.clienteCpf.trim().isNotEmpty
            ? item.clienteCpf
            : (c['cpf'] ?? '').toString();
        var end = item.enderecoCompleto;
        if (end.trim().isEmpty) {
          end = (c['endereco'] ?? '').toString();
        }
        final recorrente = item.clienteRecorrente ||
            ((c['quantidadeCompras'] as num?)?.toInt() ?? 0) > 1 ||
            c['recorrente'] == true;
        enriched.add(
          CarrinhoAbandonadoCatalogoItem(
            cartId: item.cartId,
            lojaId: item.lojaId,
            produtos: item.produtos,
            clienteNome: item.clienteNome.isNotEmpty
                ? item.clienteNome
                : (c['nome'] ?? '').toString(),
            clienteTelefone: item.clienteTelefone,
            clienteWhatsapp: item.clienteWhatsapp,
            clienteEmail: email,
            clienteCpf: cpf,
            enderecoCompleto: end,
            cupom: item.cupom,
            frete: item.frete,
            desconto: item.desconto,
            totalOverride: item.totalOverride,
            visitasCatalogo: item.visitasCatalogo,
            retornosCatalogo: item.retornosCatalogo,
            clienteRecorrente: recorrente,
            criadoEm: item.criadoEm,
            ultimoUpdate: item.ultimoUpdate,
            status: item.status,
            raw: item.raw,
          ),
        );
      }
      if (mounted) setState(() => _listaCatalogo = enriched);
    } catch (_) {}
  }

  Future<void> _enviarEmail(CarrinhoAbandonadoItem item) async {
    if (_lojaId == null) return;
    setState(() => _enviando = true);
    final result = await CarrinhoAbandonadoService.enviarLembreteEmail(
      lojaId: _lojaId!,
      clienteId: item.clienteId,
      emailDestino: item.email,
      nomeCliente: item.nome,
      nomeLoja: _lojaNome.isNotEmpty ? _lojaNome : null,
      telefone: item.telefone,
      itens: item.itens,
    );
    if (mounted) {
      setState(() => _enviando = false);
      _snack(result.mensagem, ok: result.ok);
      if (result.ok) _carregar();
    }
  }

  Future<void> _enviarEmailCatalogo(
    CarrinhoAbandonadoCatalogoItem item, {
    void Function(void Function())? setModal,
  }) async {
    if (_lojaId == null) return;
    setState(() => _enviandoEmailCartId = item.cartId);
    setModal?.call(() {});
    final link = _linkRecuperacaoCatalogo(item.cartId);
    final result = await CarrinhoAbandonadoService.enviarLembreteEmailCatalogo(
      lojaId: _lojaId!,
      cartId: item.cartId,
      emailDestino: item.clienteEmail,
      nomeCliente: item.clienteNome,
      linkRecuperacao: link,
      nomeLoja: _lojaNome.isNotEmpty ? _lojaNome : null,
      telefone: item.clienteTelefone,
      whatsapp: item.clienteWhatsapp,
      produtos: item.produtos,
      raw: item.raw,
    );
    if (mounted) {
      setState(() => _enviandoEmailCartId = null);
      setModal?.call(() {});
      _snack(result.mensagem, ok: result.ok);
      if (result.ok) _carregar();
    }
  }

  Future<void> _abrirWhatsApp(CarrinhoAbandonadoItem item) async {
    if (_lojaId == null) return;
    if (item.telefone.replaceAll(RegExp(r'[^0-9]'), '').length < 10) {
      _snack('Telefone inválido para WhatsApp', ok: false);
      return;
    }
    final link = _catalogPublicBaseUrl ??
        await CatalogPublicUrlService.montarUrlCatalogoPublicoAsync(_lojaId!);
    final ok = await CarrinhoAbandonadoService.abrirWhatsAppLembrete(
      telefone: item.telefone,
      nomeCliente: item.nome,
      link: link,
    );
    if (!ok) _snack('Não foi possível abrir o WhatsApp', ok: false);
  }

  Future<void> _abrirWhatsAppCatalogo(CarrinhoAbandonadoCatalogoItem item) async {
    if (_lojaId == null) return;
    final tel = item.telefoneEfetivo.replaceAll(RegExp(r'[^0-9]'), '');
    if (tel.length < 10) {
      _snack('Telefone/WhatsApp inválido', ok: false);
      return;
    }
    final link = _linkRecuperacaoCatalogo(item.cartId);
    final msg = CarrinhoAbandonadoService.mensagemWhatsAppRecuperacao(
      _lojaNome.isNotEmpty ? _lojaNome : 'Loja',
      link,
    );
    final ok = await CarrinhoAbandonadoService.abrirWhatsAppRecuperacaoCatalogo(
      telefone: item.telefoneEfetivo,
      nomeLoja: _lojaNome.isNotEmpty ? _lojaNome : 'Loja',
      linkRecuperacao: link,
      mensagem: msg,
    );
    if (!ok) _snack('Não foi possível abrir o WhatsApp', ok: false);
  }

  Future<void> _copiarTexto(String text, String feedback) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) _snack(feedback);
  }

  void _snack(String msg, {bool ok = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: ok ? _successColor : Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_erroResolucaoLoja) {
      return Scaffold(
        backgroundColor: _backgroundColor,
        appBar: AppBar(
          backgroundColor: _primaryColor,
          foregroundColor: Colors.white,
          title: const Text('Carrinhos abandonados',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.store_mall_directory_outlined,
                    size: 64, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text(
                  'Não foi possível identificar a loja.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      _loading = true;
                      _erroResolucaoLoja = false;
                      _lojaId = null;
                    });
                    _init();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Tentar novamente'),
                  style: FilledButton.styleFrom(backgroundColor: _primaryColor),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_loading || _lojaId == null) {
      return Scaffold(
        backgroundColor: _backgroundColor,
        appBar: AppBar(
          backgroundColor: _primaryColor,
          foregroundColor: Colors.white,
          title: const Text('Carrinhos abandonados',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        body: const Center(
            child: CircularProgressIndicator(color: _primaryColor)),
      );
    }

    final catalogo = _catalogoFiltrado;
    final loja = _lojaFiltrado;
    final temBase = _lista.isNotEmpty || _listaCatalogo.isNotEmpty;
    final temFiltroAtivo = _filtroTexto.trim().isNotEmpty ||
        _filtroStatus != 'todos' ||
        _filtroPeriodo != kCarrinhoFiltroPeriodoTodos ||
        _filtroValor != kCarrinhoFiltroValorTodos;

    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        title: const Text('Carrinhos abandonados',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _carregar,
          ),
        ],
      ),
      body: !temBase
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shopping_cart_outlined,
                      size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text(
                    'Nenhum carrinho abandonado no momento.',
                    style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _carregar,
              color: _primaryColor,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_metricasCatalogo != null &&
                      _metricasCatalogo!.total > 0)
                    _metricasCard(),
                  _filtrosCatalogo(),
                  if (loja.isEmpty && catalogo.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Text(
                        temFiltroAtivo
                            ? 'Nenhum carrinho com os filtros atuais.'
                            : 'Nenhum carrinho abandonado no momento.',
                        style: TextStyle(color: Colors.grey.shade600),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  if (loja.isNotEmpty) ...[
                    _sectionTitle(
                        'Carrinhos da loja (venda) · ${loja.length}'),
                    ...loja.map(_cardCliente),
                    const SizedBox(height: 12),
                  ],
                  if (catalogo.isNotEmpty ||
                      (_listaCatalogo.isNotEmpty && temFiltroAtivo)) ...[
                    _sectionTitle(
                        'Carrinhos do catálogo · ${catalogo.length}'),
                    if (catalogo.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'Nenhum carrinho do catálogo com os filtros atuais.',
                          style: TextStyle(color: Colors.grey.shade600),
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      ...catalogo.map(_cardCatalogo),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          t,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade700,
          ),
        ),
      );

  Widget _metricasCard() {
    final m = _metricasCatalogo!;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: _primaryColor.withOpacity(0.08),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.insights_outlined, size: 20, color: _primaryColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Abandonados: ${m.abandonados} · Recuperados: ${m.recuperados} · '
                'Taxa: ${m.taxaRecuperacaoPercent.toStringAsFixed(0)}%',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filtrosCatalogo() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          TextField(
            controller: _buscaCtrl,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _filtroTexto.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _buscaCtrl.clear();
                        setState(() => _filtroTexto = '');
                      },
                    ),
              labelText: 'Pesquisar nome, telefone, WhatsApp, e-mail',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onChanged: (v) => setState(() => _filtroTexto = v),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _filtroStatus,
                  isExpanded: true,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: 'Status',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'todos', child: Text('Todos')),
                    DropdownMenuItem(
                        value: kCarrinhoUiAbandonado, child: Text('Abandonado')),
                    DropdownMenuItem(
                        value: kCarrinhoUiRecuperado, child: Text('Recuperado')),
                    DropdownMenuItem(
                        value: kCarrinhoUiVirouPedido,
                        child: Text('Virou Pedido')),
                    DropdownMenuItem(
                        value: kCarrinhoUiVirouVenda, child: Text('Virou Venda')),
                  ],
                  onChanged: (v) =>
                      setState(() => _filtroStatus = v ?? 'todos'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _filtroPeriodo,
                  isExpanded: true,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: 'Data',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: kCarrinhoFiltroPeriodoTodos,
                        child: Text('Todas')),
                    DropdownMenuItem(
                        value: kCarrinhoFiltroPeriodoHoje, child: Text('Hoje')),
                    DropdownMenuItem(
                        value: kCarrinhoFiltroPeriodo7d,
                        child: Text('Últimos 7 dias')),
                    DropdownMenuItem(
                        value: kCarrinhoFiltroPeriodo30d,
                        child: Text('Últimos 30 dias')),
                  ],
                  onChanged: (v) => setState(
                      () => _filtroPeriodo = v ?? kCarrinhoFiltroPeriodoTodos),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _filtroValor,
                  isExpanded: true,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: 'Valor',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: kCarrinhoFiltroValorTodos, child: Text('Todos')),
                    DropdownMenuItem(
                        value: kCarrinhoFiltroValorAte100,
                        child: Text('Até R\$ 100')),
                    DropdownMenuItem(
                        value: kCarrinhoFiltroValor100a300,
                        child: Text('R\$ 100–300')),
                    DropdownMenuItem(
                        value: kCarrinhoFiltroValorAcima300,
                        child: Text('Acima de R\$ 300')),
                  ],
                  onChanged: (v) => setState(
                      () => _filtroValor = v ?? kCarrinhoFiltroValorTodos),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _ordenacao,
                  isExpanded: true,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: 'Ordenação',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 'recente', child: Text('Mais recente')),
                    DropdownMenuItem(
                        value: 'antigo', child: Text('Mais antigo')),
                    DropdownMenuItem(
                        value: 'valor', child: Text('Maior valor')),
                    DropdownMenuItem(
                        value: 'score', child: Text('Maior score')),
                  ],
                  onChanged: (v) =>
                      setState(() => _ordenacao = v ?? 'recente'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cardCliente(CarrinhoAbandonadoItem item) {
    final ultimaStr = item.ultimaAtualizacao != null
        ? DateFormat('dd/MM/yyyy HH:mm').format(item.ultimaAtualizacao!)
        : '—';
    final score = calcularProbabilidadeRecuperacao(
      tempoAbandonado: item.ultimaAtualizacao == null
          ? const Duration(days: 3)
          : DateTime.now().difference(item.ultimaAtualizacao!),
      valorCarrinho: totalCarrinhoProdutos(item.itens),
      quantidadeItens: item.totalItens,
      temWhatsapp: item.telefone.trim().length >= 10,
      temEmail: item.email.trim().contains('@'),
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _abrirDetalheCliente(item),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: _primaryColor.withOpacity(0.15),
                    child: Text(
                      item.nome.isNotEmpty ? item.nome[0].toUpperCase() : '?',
                      style: const TextStyle(
                          color: _primaryColor, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.nome,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        if (item.telefone.isNotEmpty)
                          Text(item.telefone,
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                  _scoreBadge(score),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _infoChip('${item.totalItens} itens'),
                  _infoChip(_money(totalCarrinhoProdutos(item.itens))),
                  _infoChip(ultimaStr),
                  _infoChip(score.label),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (item.telefone.trim().length >= 10)
                    _miniAction('WhatsApp', Icons.chat, () => _abrirWhatsApp(item)),
                  _miniAction('E-mail', Icons.email_outlined, () => _enviarEmail(item)),
                  _miniAction('Detalhes', Icons.info_outline,
                      () => _abrirDetalheCliente(item)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cardCatalogo(CarrinhoAbandonadoCatalogoItem item) {
    final score = _scoreCatalogo(item);
    final ultimaStr = item.ultimoUpdate != null
        ? DateFormat('dd/MM/yyyy HH:mm').format(item.ultimoUpdate!)
        : '—';
    final valor = item.totalOverride ??
        (totalCarrinhoProdutos(item.produtos) + item.frete - item.desconto);
    final tempo = formatarTempoAbandonado(
      DateTime.now().difference(
        item.ultimoUpdate ?? item.criadoEm ?? DateTime.now(),
      ),
    );
    final link = _linkRecuperacaoCatalogo(item.cartId);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _abrirDetalheCatalogo(item),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: _primaryColor.withOpacity(0.15),
                    child: Text(
                      item.clienteNome.isNotEmpty
                          ? item.clienteNome[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                          color: _primaryColor, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.clienteNome.isEmpty
                              ? 'Cliente (sem nome)'
                              : item.clienteNome,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (item.telefoneEfetivo.isNotEmpty)
                              item.telefoneEfetivo,
                            if (item.clienteEmail.isNotEmpty) item.clienteEmail,
                          ].join(' · '),
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  _scoreBadge(score),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _infoChip('${item.totalItens} itens'),
                  _infoChip(_money(valor)),
                  _infoChip(labelStatusCarrinhoAbandonado(item.status)),
                  _infoChip(tempo),
                  _infoChip(ultimaStr),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _miniAction('WhatsApp', Icons.chat,
                      () => _abrirWhatsAppCatalogo(item)),
                  _miniAction(
                    'E-mail',
                    Icons.email_outlined,
                    () => _enviarEmailCatalogo(item),
                  ),
                  _miniAction(
                      'Copiar link', Icons.link, () => _copiarTexto(link, 'Link copiado')),
                  _miniAction('Catálogo', Icons.open_in_new, () async {
                    await launchUrl(Uri.parse(link),
                        mode: LaunchMode.externalApplication);
                  }),
                  _miniAction(
                    'Copiar infos',
                    Icons.copy_all,
                    () => _copiarTexto(
                      _infoCatalogo(item, link),
                      'Informações copiadas',
                    ),
                  ),
                  _miniAction('Detalhes', Icons.info_outline,
                      () => _abrirDetalheCatalogo(item)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scoreBadge(RecuperacaoScoreResult score) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: score.badgeColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '${score.emojiBadge} ${score.label.split(' ').first}',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: score.badgeColor,
        ),
      ),
    );
  }

  Widget _infoChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: const TextStyle(fontSize: 11)),
    );
  }

  Widget _miniAction(String label, IconData icon, VoidCallback? onTap) {
    return ActionChip(
      avatar: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: onTap,
    );
  }
}
