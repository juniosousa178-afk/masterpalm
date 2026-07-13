// lib/screens/carrinhos_abandonados_screen.dart
// Lista carrinhos abandonados e permite enviar lembrete por e-mail ou WhatsApp.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/carrinho_abandonado_ui.dart';
import '../widgets/carrinho_abandonado_details_panel.dart';
import '../services/carrinho_abandonado_service.dart';
import '../services/catalog_public_url_service.dart';
import '../services/loja_id_service.dart';
import '../services/public_store_link_helper.dart';

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
  int _horasAbandono = 24;
  bool _enviando = false;
  String _lojaNome = '';

  /// Mensagem sugerida pela IA por cartId (catálogo). Quando null, usa mensagem fixa.
  final Map<String, String> _mensagemSugeridaPorCartId = {};

  /// CartId para o qual a IA está carregando (evita múltiplos toques).
  String? _loadingIaCartId;

  /// Métricas de recuperação do catálogo (abandonados / recuperados).
  MetricasRecuperacaoCatalogo? _metricasCatalogo;

  /// URL pública do catálogo (hosted ou domínio próprio), carregada após resolver a loja.
  String? _catalogPublicBaseUrl;

  String _filtroStatus = 'todos';
  String _filtroTexto = '';
  String _ordenacao = 'recente';

  @override
  void initState() {
    super.initState();
    _init();
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
    setState(() {});
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

  List<CarrinhoAbandonadoCatalogoItem> get _catalogoFiltrado {
    var list = List<CarrinhoAbandonadoCatalogoItem>.from(_listaCatalogo);
    final q = _filtroTexto.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where((e) =>
              e.clienteNome.toLowerCase().contains(q) ||
              e.clienteTelefone.contains(q) ||
              e.cartId.toLowerCase().contains(q))
          .toList();
    }
    if (_filtroStatus != 'todos') {
      list = list
          .where((e) =>
              normalizarStatusCarrinhoAbandonado(e.status) == _filtroStatus)
          .toList();
    }
    list.sort((a, b) {
      final ta = totalCarrinhoProdutos(a.produtos);
      final tb = totalCarrinhoProdutos(b.produtos);
      final da = a.ultimoUpdate ?? a.criadoEm ?? DateTime.fromMillisecondsSinceEpoch(0);
      final db = b.ultimoUpdate ?? b.criadoEm ?? DateTime.fromMillisecondsSinceEpoch(0);
      switch (_ordenacao) {
        case 'valor':
          return tb.compareTo(ta);
        case 'antigo':
          return da.compareTo(db);
        default:
          return db.compareTo(da);
      }
    });
    return list;
  }

  void _abrirDetalheCatalogo(CarrinhoAbandonadoCatalogoItem item) {
    final link = _linkRecuperacaoCatalogo(item.cartId);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, __) => CarrinhoAbandonadoDetailsPanel(
          item: item,
          linkCatalogo: link,
          onOpenCatalog: () async {
            final uri = Uri.parse(link);
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          },
        ),
      ),
    );
  }

  Future<void> _carregarConfig() async {
    if (_lojaId == null) return;
    final config = await CarrinhoAbandonadoService.getConfig(_lojaId!);
    if (mounted) {
      setState(() {
        _horasAbandono = config.horasAbandono;
      });
    }
  }

  Future<void> _carregar() async {
    if (_lojaId == null) return;
    setState(() => _loading = true);
    final lista = await CarrinhoAbandonadoService.listarCarrinhosAbandonados(
      lojaId: _lojaId!,
      horasAbandono: _horasAbandono,
    );
    final listaCatalogo =
        await CarrinhoAbandonadoService.listarCarrinhosAbandonadosCatalogo(
      lojaId: _lojaId!,
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
    if (mounted) {
      setState(() {
        _lista = lista;
        _listaCatalogo = listaCatalogo;
        _metricasCatalogo = metricasCatalogo;
        _lojaNome = lojaNome;
        _loading = false;
      });
    }
  }

  Future<void> _enviarEmail(CarrinhoAbandonadoItem item) async {
    if (_lojaId == null) return;
    setState(() => _enviando = true);
    final ok = await CarrinhoAbandonadoService.enviarLembreteEmail(
      lojaId: _lojaId!,
      clienteId: item.clienteId,
      emailDestino: item.email,
      nomeCliente: item.nome,
    );
    if (mounted) {
      setState(() => _enviando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok
              ? 'E-mail enviado para ${item.email}'
              : 'Falha ao enviar e-mail'),
          backgroundColor: ok ? _successColor : Colors.red,
        ),
      );
      if (ok) _carregar();
    }
  }

  Future<void> _abrirWhatsApp(CarrinhoAbandonadoItem item) async {
    if (_lojaId == null) return;
    final link = _catalogPublicBaseUrl ??
        await CatalogPublicUrlService.montarUrlCatalogoPublicoAsync(_lojaId!);
    await CarrinhoAbandonadoService.abrirWhatsAppLembrete(
      telefone: item.telefone,
      nomeCliente: item.nome,
      link: link,
    );
  }

  String _mensagemAtualCatalogo(CarrinhoAbandonadoCatalogoItem item) {
    final link = _lojaId != null ? _linkRecuperacaoCatalogo(item.cartId) : '';
    return _mensagemSugeridaPorCartId[item.cartId] ??
        CarrinhoAbandonadoService.mensagemWhatsAppRecuperacao(
          _lojaNome.isNotEmpty ? _lojaNome : 'Loja',
          link,
        );
  }

  Future<void> _sugerirMensagemIaCatalogo(
      CarrinhoAbandonadoCatalogoItem item) async {
    if (_lojaId == null) return;
    final link = _linkRecuperacaoCatalogo(item.cartId);
    if (link.isEmpty) return;
    setState(() => _loadingIaCartId = item.cartId);
    final nomeLoja = _lojaNome.isNotEmpty ? _lojaNome : 'Loja';
    final msg =
        await CarrinhoAbandonadoService.sugerirMensagemRecuperacaoCatalogo(
      nomeLoja: nomeLoja,
      linkRecuperacao: link,
      clienteNome: item.clienteNome,
      produtos: item.produtos,
      ultimoUpdate: item.ultimoUpdate,
    );
    if (mounted) {
      setState(() {
        _mensagemSugeridaPorCartId[item.cartId] = msg;
        _loadingIaCartId = null;
      });
    }
  }

  Future<void> _abrirWhatsAppCatalogo(CarrinhoAbandonadoCatalogoItem item,
      {String? mensagem}) async {
    if (_lojaId == null) return;
    final link = _linkRecuperacaoCatalogo(item.cartId);
    if (link.isEmpty) return;
    final msg = mensagem ?? _mensagemAtualCatalogo(item);
    await CarrinhoAbandonadoService.abrirWhatsAppRecuperacaoCatalogo(
      telefone: item.clienteTelefone.isNotEmpty
          ? item.clienteTelefone
          : '5511999999999',
      nomeLoja: _lojaNome.isNotEmpty ? _lojaNome : 'Loja',
      linkRecuperacao: link,
      mensagem: msg,
    );
  }

  Future<void> _copiarLink(BuildContext context, String link) async {
    await Clipboard.setData(ClipboardData(text: link));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Link copiado'), duration: Duration(seconds: 2)),
      );
    }
  }

  Future<void> _copiarMensagem(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Mensagem copiada'), duration: Duration(seconds: 2)),
      );
    }
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
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _primaryColor))
          : _lista.isEmpty && _listaCatalogo.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shopping_cart_outlined,
                          size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        'Nenhum carrinho abandonado no momento.',
                        style: TextStyle(
                            fontSize: 16, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Clientes com itens no carrinho há mais de $_horasAbandono h aparecem aqui.',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade500),
                        textAlign: TextAlign.center,
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
                      if (_lista.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Carrinhos da loja (venda)',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade700),
                          ),
                        ),
                        ..._lista.map((item) {
                          final ultimaStr = item.ultimaAtualizacao != null
                              ? DateFormat('dd/MM/yyyy HH:mm')
                                  .format(item.ultimaAtualizacao!)
                              : '—';
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor:
                                            _primaryColor.withOpacity(0.2),
                                        child: Text(
                                          item.nome.isNotEmpty
                                              ? item.nome[0].toUpperCase()
                                              : '?',
                                          style: const TextStyle(
                                              color: _primaryColor,
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(item.nome,
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w600)),
                                            if (item.email.isNotEmpty)
                                              Text(item.email,
                                                  style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors
                                                          .grey.shade600)),
                                            if (item.telefone.isNotEmpty)
                                              Text(item.telefone,
                                                  style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors
                                                          .grey.shade600)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${item.totalItens} item(ns) · Última atualização: $ultimaStr',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600),
                                  ),
                                  if (item.lembreteEnviadoEm != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        'Lembrete enviado em ${DateFormat('dd/MM HH:mm').format(item.lembreteEnviadoEm!)}',
                                        style: const TextStyle(
                                            fontSize: 11, color: _successColor),
                                      ),
                                    ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      if (item.email.trim().isNotEmpty)
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: _enviando
                                                ? null
                                                : () => _enviarEmail(item),
                                            icon: _enviando
                                                ? const SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child:
                                                        CircularProgressIndicator(
                                                            strokeWidth: 2))
                                                : const Icon(
                                                    Icons.email_outlined,
                                                    size: 18),
                                            label: const Text('Enviar e-mail'),
                                            style: OutlinedButton.styleFrom(
                                                foregroundColor: _primaryColor),
                                          ),
                                        ),
                                      if (item.email.trim().isNotEmpty &&
                                          item.telefone.trim().isNotEmpty)
                                        const SizedBox(width: 8),
                                      if (item.telefone.trim().isNotEmpty)
                                        Expanded(
                                          child: FilledButton.icon(
                                            onPressed: () =>
                                                _abrirWhatsApp(item),
                                            icon: const Icon(
                                                Icons.chat_outlined,
                                                size: 18),
                                            label: const Text('WhatsApp'),
                                            style: FilledButton.styleFrom(
                                                backgroundColor: _successColor),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                        if (_listaCatalogo.isNotEmpty)
                          const SizedBox(height: 20),
                      ],
                      if (_listaCatalogo.isNotEmpty ||
                          _metricasCatalogo != null) ...[
                        if (_metricasCatalogo != null &&
                            _metricasCatalogo!.total > 0)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Card(
                              margin: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              color: _primaryColor.withOpacity(0.08),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                child: Row(
                                  children: [
                                    const Icon(Icons.insights_outlined,
                                        size: 20, color: _primaryColor),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Abandonados: ${_metricasCatalogo!.abandonados}',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade800),
                                    ),
                                    const SizedBox(width: 16),
                                    Text(
                                      'Recuperados: ${_metricasCatalogo!.recuperados}',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade800),
                                    ),
                                    const SizedBox(width: 16),
                                    Text(
                                      'Taxa: ${_metricasCatalogo!.taxaRecuperacaoPercent.toStringAsFixed(0)}%',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: _primaryColor),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Carrinhos do catálogo',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade700),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Column(
                            children: [
                              TextField(
                                decoration: const InputDecoration(
                                  isDense: true,
                                  prefixIcon: Icon(Icons.search, size: 20),
                                  labelText: 'Filtrar cliente / telefone',
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (v) =>
                                    setState(() => _filtroTexto = v),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      value: _filtroStatus,
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        labelText: 'Status',
                                        border: OutlineInputBorder(),
                                      ),
                                      items: const [
                                        DropdownMenuItem(
                                            value: 'todos',
                                            child: Text('Todos')),
                                        DropdownMenuItem(
                                            value: kCarrinhoUiAbandonado,
                                            child: Text('Abandonado')),
                                        DropdownMenuItem(
                                            value: kCarrinhoUiRecuperado,
                                            child: Text('Recuperado')),
                                        DropdownMenuItem(
                                            value: kCarrinhoUiVirouPedido,
                                            child: Text('Virou Pedido')),
                                        DropdownMenuItem(
                                            value: kCarrinhoUiVirouVenda,
                                            child: Text('Virou Venda')),
                                      ],
                                      onChanged: (v) => setState(
                                          () => _filtroStatus = v ?? 'todos'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      value: _ordenacao,
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        labelText: 'Ordenar',
                                        border: OutlineInputBorder(),
                                      ),
                                      items: const [
                                        DropdownMenuItem(
                                            value: 'recente',
                                            child: Text('Mais recente')),
                                        DropdownMenuItem(
                                            value: 'antigo',
                                            child: Text('Mais antigo')),
                                        DropdownMenuItem(
                                            value: 'valor',
                                            child: Text('Maior valor')),
                                      ],
                                      onChanged: (v) => setState(
                                          () => _ordenacao = v ?? 'recente'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        ..._catalogoFiltrado.map((item) {
                          final link = _lojaId != null
                              ? _linkRecuperacaoCatalogo(item.cartId)
                              : '';
                          final ultimaStr = item.ultimoUpdate != null
                              ? DateFormat('dd/MM/yyyy HH:mm')
                                  .format(item.ultimoUpdate!)
                              : '—';
                          final mensagemAtual = _mensagemAtualCatalogo(item);
                          final loadingIa = _loadingIaCartId == item.cartId;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor:
                                            _primaryColor.withOpacity(0.2),
                                        child: Text(
                                          item.clienteNome.isNotEmpty
                                              ? item.clienteNome[0]
                                                  .toUpperCase()
                                              : '?',
                                          style: const TextStyle(
                                              color: _primaryColor,
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.clienteNome.isEmpty
                                                  ? 'Cliente (sem nome)'
                                                  : item.clienteNome,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w600),
                                            ),
                                            if (item.clienteTelefone.isNotEmpty)
                                              Text(item.clienteTelefone,
                                                  style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors
                                                          .grey.shade600)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${item.totalItens} item(ns) · '
                                    '${_money(totalCarrinhoProdutos(item.produtos))} · '
                                    'Última: $ultimaStr · '
                                    '${labelStatusCarrinhoAbandonado(item.status)}',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600),
                                  ),
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: OutlinedButton.icon(
                                      onPressed: () =>
                                          _abrirDetalheCatalogo(item),
                                      icon: const Icon(Icons.open_in_new,
                                          size: 16),
                                      label: const Text('Abrir detalhe'),
                                    ),
                                  ),
                                  if (link.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: SelectableText(link,
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: _primaryColor)),
                                    ),
                                  const SizedBox(height: 10),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: Colors.grey.shade300),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _mensagemSugeridaPorCartId
                                                  .containsKey(item.cartId)
                                              ? 'Mensagem sugerida (IA)'
                                              : 'Mensagem para envio',
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.grey.shade700),
                                        ),
                                        const SizedBox(height: 4),
                                        SelectableText(mensagemAtual,
                                            style:
                                                const TextStyle(fontSize: 13)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed: loadingIa
                                            ? null
                                            : () => _sugerirMensagemIaCatalogo(
                                                item),
                                        icon: loadingIa
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2))
                                            : const Icon(Icons.auto_awesome,
                                                size: 18),
                                        label: Text(loadingIa
                                            ? 'Gerando…'
                                            : 'Sugerir com IA'),
                                        style: OutlinedButton.styleFrom(
                                            foregroundColor: _primaryColor),
                                      ),
                                      const SizedBox(width: 8),
                                      OutlinedButton.icon(
                                        onPressed: () => _copiarMensagem(
                                            context, mensagemAtual),
                                        icon: const Icon(Icons.copy, size: 18),
                                        label: const Text('Copiar mensagem'),
                                        style: OutlinedButton.styleFrom(
                                            foregroundColor: _primaryColor),
                                      ),
                                    ],
                                  ),
                                  if (link.isNotEmpty)
                                    const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      if (link.isNotEmpty)
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: () =>
                                                _copiarLink(context, link),
                                            icon: const Icon(Icons.link,
                                                size: 18),
                                            label: const Text('Copiar link'),
                                            style: OutlinedButton.styleFrom(
                                                foregroundColor: _primaryColor),
                                          ),
                                        ),
                                      if (link.isNotEmpty)
                                        const SizedBox(width: 8),
                                      Expanded(
                                        child: FilledButton.icon(
                                          onPressed: () =>
                                              _abrirWhatsAppCatalogo(item),
                                          icon: const Icon(Icons.chat_outlined,
                                              size: 18),
                                          label: const Text('WhatsApp'),
                                          style: FilledButton.styleFrom(
                                              backgroundColor: _successColor),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
    );
  }
}
