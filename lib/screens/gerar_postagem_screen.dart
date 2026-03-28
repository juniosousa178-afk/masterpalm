// lib/screens/gerar_postagem_screen.dart
// Criador automático de postagens: produto, campanha ou produto parado.
// Reaproveita AiLojaService, IaUsoLimiteService e CatalogShareService.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/hive_box_names.dart';
import '../models/dashboard_insight.dart';
import '../models/produto.dart';
import '../services/ai_loja_service.dart';
import '../services/catalog_share_service.dart';
import '../services/dashboard_insights_service.dart';
import '../services/ia_uso_limite_service.dart';
import '../services/loja_id_service.dart';

class GerarPostagemScreen extends StatefulWidget {
  const GerarPostagemScreen({super.key});

  @override
  State<GerarPostagemScreen> createState() => _GerarPostagemScreenState();
}

class _GerarPostagemScreenState extends State<GerarPostagemScreen> {
  final _nomeCtrl = TextEditingController();
  final _categoriaCtrl = TextEditingController();
  final _precoCtrl = TextEditingController();
  final _descricaoCtrl = TextEditingController();
  final _promocaoCtrl = TextEditingController();
  final _campanhaCtrl = TextEditingController();
  final _publicoCtrl = TextEditingController();

  String _modo = 'produto'; // produto | produto_parado | campanha
  String? _sugestaoParadoNome;
  bool _loadingSugestao = false;
  bool _gerando = false;
  String? _erro;
  String? _legendaInstagram;
  String? _legendaCurta;
  String? _mensagemWhatsApp;
  String? _chamadaPromocional;

  List<Produto> _produtos = [];
  TextEditingController? _autocompleteController;

  @override
  void initState() {
    super.initState();
    _carregarSugestaoParado();
    _carregarProdutos();
  }

  void _syncNomeFromAutocomplete() {
    final c = _autocompleteController;
    if (c != null && _nomeCtrl.text != c.text) {
      _nomeCtrl.text = c.text;
      if (mounted) setState(() {});
    }
  }

  Future<void> _carregarProdutos() async {
    final lojaId = await LojaIdService.get();
    if (lojaId == null || lojaId.isEmpty) return;
    try {
      final boxName = HiveBoxNames.produtos(lojaId);
      Box<Produto> box;
      if (Hive.isBoxOpen(boxName)) {
        box = Hive.box<Produto>(boxName);
      } else {
        box = await Hive.openBox<Produto>(boxName);
      }
      if (mounted) {
        setState(() {
          _produtos = box.values
              .where((p) => p.lojaId.isEmpty || p.lojaId == lojaId)
              .toList();
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _autocompleteController?.removeListener(_syncNomeFromAutocomplete);
    _nomeCtrl.dispose();
    _categoriaCtrl.dispose();
    _precoCtrl.dispose();
    _descricaoCtrl.dispose();
    _promocaoCtrl.dispose();
    _campanhaCtrl.dispose();
    _publicoCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregarSugestaoParado() async {
    final lojaId = await LojaIdService.get();
    if (lojaId == null || lojaId.isEmpty) return;
    setState(() => _loadingSugestao = true);
    try {
      final result = await DashboardInsightsService.loadInsights(lojaId: lojaId);
      String? nomeParado;
      for (final i in result.insights) {
        if (i.type == DashboardInsightType.produtoParado && i.data != null && i.data!['nome'] != null) {
          nomeParado = i.data!['nome']?.toString().trim();
          break;
        }
      }
      if (mounted) {
        setState(() {
          _sugestaoParadoNome = nomeParado;
          _loadingSugestao = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingSugestao = false);
    }
  }

  String get _nome => _nomeCtrl.text.trim();
  String get _precoTexto {
    final p = _precoCtrl.text.trim().replaceAll(',', '.');
    final v = double.tryParse(p);
    if (v == null) return _precoCtrl.text.trim().isEmpty ? '' : _precoCtrl.text.trim();
    return 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  Future<void> _gerar() async {
    final lojaId = await LojaIdService.get();
    if (lojaId == null || lojaId.isEmpty) {
      setState(() => _erro = 'Loja não identificada.');
      return;
    }
    if (!await IaUsoLimiteService.canUse(lojaId, TipoUsoIa.perguntas)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(IaUsoLimiteService.messageLimitExcedido(TipoUsoIa.perguntas)),
            backgroundColor: Colors.orange.shade700,
          ),
        );
      }
      return;
    }

    String nome = _nome;
    if (_modo == 'produto_parado' && (_sugestaoParadoNome ?? '').isNotEmpty) {
      nome = _sugestaoParadoNome!;
      _nomeCtrl.text = nome;
    }
    if (nome.isEmpty) {
      setState(() => _erro = 'Informe o nome do produto ou use a sugestão de produto parado.');
      return;
    }

    setState(() {
      _gerando = true;
      _erro = null;
      _legendaInstagram = null;
      _legendaCurta = null;
      _mensagemWhatsApp = null;
      _chamadaPromocional = null;
    });

    final categoria = _categoriaCtrl.text.trim();
    final descricao = _descricaoCtrl.text.trim();
    final promocao = _promocaoCtrl.text.trim();
    final campanha = _campanhaCtrl.text.trim();
    final publico = _publicoCtrl.text.trim();
    final precoTexto = _precoTexto;

    try {
      String? legendaIg;
      String? legendaCurta;
      String? msgWa;
      String? chamada;

      if (_modo == 'produto_parado' && (_sugestaoParadoNome ?? '').isNotEmpty) {
        try {
          final sugestao = await AiLojaService.sugerirPromocaoEstoqueParado(
            produtos: [{'nome': _sugestaoParadoNome}],
          );
          if (sugestao.trim().isNotEmpty) {
            msgWa = sugestao;
            chamada = sugestao.trim();
          }
        } catch (_) {
          msgWa = _fallbackMensagemWhatsApp(nome, precoTexto);
          chamada = _fallbackChamadaPromo(nome);
        }
        try {
          legendaIg = await AiLojaService.sugerirLegendaInstagram(produtoNome: nome, descricao: descricao.isNotEmpty ? descricao : null);
        } catch (_) {
          legendaIg = _fallbackLegenda(nome);
        }
        final legenda = legendaIg;
        legendaCurta = legenda;
      } else {
        try {
          legendaIg = await AiLojaService.sugerirLegendaInstagram(produtoNome: nome, descricao: descricao.isNotEmpty ? descricao : null);
        } catch (_) {
          legendaIg = _fallbackLegenda(nome);
        }
        final legenda = legendaIg;
        legendaCurta = legenda;

        try {
          final contexto = [
            if (categoria.isNotEmpty) 'Categoria: $categoria',
            if (precoTexto.isNotEmpty) precoTexto,
            if (promocao.isNotEmpty) 'Promoção: $promocao',
            if (campanha.isNotEmpty) 'Campanha: $campanha',
            if (publico.isNotEmpty) 'Público: $publico',
          ].join(' | ');
          msgWa = await AiLojaService.sugerirMensagemWhatsApp(
            tipo: 'promocao',
            contexto: contexto.isEmpty ? nome : '$nome — $contexto',
          );
        } catch (_) {
          msgWa = _fallbackMensagemWhatsApp(nome, precoTexto);
        }
        chamada = _fallbackChamadaPromo(nome);
      }

      if (mounted) {
        IaUsoLimiteService.recordUse(lojaId, TipoUsoIa.perguntas);
        setState(() {
          _legendaInstagram = legendaIg;
          _legendaCurta = legendaCurta ?? legendaIg;
          _mensagemWhatsApp = msgWa;
          _chamadaPromocional = chamada;
          _gerando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _gerando = false;
          _legendaInstagram = _fallbackLegenda(nome);
          _legendaCurta = _legendaInstagram;
          _mensagemWhatsApp = _fallbackMensagemWhatsApp(nome, precoTexto);
          _chamadaPromocional = _fallbackChamadaPromo(nome);
          _erro = AiLojaService.messageForUser(e);
        });
      }
    }
  }

  static String _fallbackLegenda(String nome) {
    return 'Confira $nome! 💫 Produto especial para você.';
  }

  static String _fallbackMensagemWhatsApp(String nome, String precoTexto) {
    final p = precoTexto.isEmpty ? '' : ' - $precoTexto';
    return 'Olá! Quero te mostrar: $nome$p. Se quiser, já me chame para fazer seu pedido.';
  }

  static String _fallbackChamadaPromo(String nome) {
    return 'Promoção: $nome. Aproveite!';
  }

  void _copiar(String? texto) {
    if (texto == null || texto.isEmpty) return;
    Clipboard.setData(ClipboardData(text: texto));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Texto copiado para a área de transferência')),
    );
  }

  Future<void> _abrirWhatsApp(String? texto) async {
    if (texto == null || texto.isEmpty) return;
    final uri = Uri.parse('https://wa.me/?text=${CatalogShareService.encodeForWhatsApp(texto)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o WhatsApp')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Criar postagem'),
      ),
      body: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Origem', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  RadioListTile<String>(
                    title: const Text('Produto (manual)'),
                    value: 'produto',
                    // ignore: deprecated_member_use
                    groupValue: _modo,
                    // ignore: deprecated_member_use
                    onChanged: (v) => setState(() => _modo = v!),
                  ),
                  RadioListTile<String>(
                    title: const Text('Produto parado (sugerido)'),
                    value: 'produto_parado',
                    // ignore: deprecated_member_use
                    groupValue: _modo,
                    // ignore: deprecated_member_use
                    onChanged: (v) => setState(() => _modo = v!),
                  ),
                  if (_loadingSugestao)
                    const Padding(
                      padding: EdgeInsets.only(left: 16),
                      child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  else if (_sugestaoParadoNome != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Text('Sugestão: "$_sugestaoParadoNome"', style: theme.textTheme.bodySmall),
                    ),
                  RadioListTile<String>(
                    title: const Text('Campanha'),
                    value: 'campanha',
                    // ignore: deprecated_member_use
                    groupValue: _modo,
                    // ignore: deprecated_member_use
                    onChanged: (v) => setState(() => _modo = v!),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Autocomplete<Produto>(
            displayStringForOption: (p) => p.nome,
            optionsBuilder: (TextEditingValue textEditingValue) {
              final query = textEditingValue.text.trim().toLowerCase();
              if (query.isEmpty) return const Iterable<Produto>.empty();
              return _produtos
                  .where((p) => p.nome.toLowerCase().contains(query))
                  .take(10);
            },
            onSelected: (Produto p) {
              _nomeCtrl.text = p.nome;
              _categoriaCtrl.text = p.categoria.trim();
              _precoCtrl.text = (p.precoComPromocao > 0
                      ? p.precoComPromocao
                      : (p.precoFinal > 0 ? p.precoFinal : p.precoUnitario))
                  .toStringAsFixed(2)
                  .replaceAll('.', ',');
              _descricaoCtrl.text = p.descricao.trim();
              setState(() {});
            },
            fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
              if (_autocompleteController != controller) {
                _autocompleteController?.removeListener(_syncNomeFromAutocomplete);
                _autocompleteController = controller;
                controller.addListener(_syncNomeFromAutocomplete);
              }
              return TextField(
                controller: controller,
                focusNode: focusNode,
                decoration: const InputDecoration(
                  labelText: 'Nome do produto / item',
                  hintText: 'Digite para buscar produto do cadastro',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (_) => setState(() {}),
              );
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _categoriaCtrl,
            decoration: const InputDecoration(
              labelText: 'Categoria (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _precoCtrl,
            decoration: const InputDecoration(
              labelText: 'Preço (opcional)',
              hintText: 'Ex: 49,90',
              border: OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _descricaoCtrl,
            decoration: const InputDecoration(
              labelText: 'Descrição (opcional)',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _promocaoCtrl,
            decoration: const InputDecoration(
              labelText: 'Promoção (opcional)',
              hintText: 'Ex: 20% off',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _campanhaCtrl,
            decoration: const InputDecoration(
              labelText: 'Nome da campanha (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _publicoCtrl,
            decoration: const InputDecoration(
              labelText: 'Público-alvo (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
          if (_erro != null) ...[
            const SizedBox(height: 12),
            Text(_erro!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _gerando ? null : _gerar,
            icon: _gerando
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome),
            label: Text(_gerando ? 'Gerando…' : 'Gerar textos'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
          if (_legendaInstagram != null || _mensagemWhatsApp != null) ...[
            const SizedBox(height: 24),
            if (_legendaInstagram != null) _buildBlocoSaida(theme, 'Instagram', _legendaInstagram!),
            if (_legendaCurta != null && _legendaCurta != _legendaInstagram)
              _buildBlocoSaida(theme, 'Legenda curta', _legendaCurta!),
            if (_mensagemWhatsApp != null) _buildBlocoSaida(theme, 'WhatsApp', _mensagemWhatsApp!, isWhatsApp: true),
            if (_chamadaPromocional != null) _buildBlocoSaida(theme, 'Chamada promocional', _chamadaPromocional!, isWhatsApp: true),
          ],
        ],
      ),
    );
  }

  Widget _buildBlocoSaida(ThemeData theme, String titulo, String texto, {bool isWhatsApp = false}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha:0.5),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(titulo, style: theme.textTheme.titleMedium),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.copy),
                      onPressed: () => _copiar(texto),
                      tooltip: 'Copiar',
                    ),
                    if (isWhatsApp)
                      IconButton(
                        icon: const Icon(Icons.chat),
                        onPressed: () => _abrirWhatsApp(texto),
                        tooltip: 'Abrir no WhatsApp',
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(texto, style: const TextStyle(height: 1.4)),
          ],
        ),
      ),
    );
  }
}
