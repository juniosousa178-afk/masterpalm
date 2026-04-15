// lib/screens/public_catalog/widgets/catalog_product_details_sheet.dart
// Modal de detalhes do produto – extraído do public_catalog_screen.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/produto_variacao_extra.dart';
import '../../../utils/platform_adaptive.dart';
import '../../../services/catalog_share_service.dart';
import '../../../services/ai_loja_service.dart';
import '../../../services/ia_uso_limite_service.dart';

/// Lista de itens do combo/kit: cada mapa com nome, slug?, quantidade, tamanho?, cor?
typedef ItensComboList = List<Map<String, dynamic>>;

class CatalogProductDetailsSheet extends StatelessWidget {
  final String name;
  final String descricao;
  final double price;
  final double? priceMin;
  final double? priceMax;
  final String? catalogShareUrl;
  final double? precoOriginal;
  final bool emPromocao;
  final double percentualPromo;
  final double valorPromo;
  final List<String> imagens;
  final int quantidade;
  final Map<String, int>? estoquePorTamanho;
  /// Cores com quantidade (ex.: sem tamanho ou híbrido).
  final Map<String, int>? estoquePorCor;
  /// Mapa tamanho → cor → quantidade (ou preço aninhado).
  final Map<String, dynamic>? variacoes;
  final String? prazoEntrega;
  final double percentualDescontoPix;
  /// Itens que compõem o kit/combo – exibidos na seção "Produtos do kit"
  final ItensComboList? itensCombo;
  /// Contexto opcional para "Dúvidas? Pergunte" (IA): nome da loja, contato, política de frete.
  final String? nomeLoja;
  final String? contatoWhatsapp;
  final String? politicaFrete;
  /// Loja do catálogo (obrigatório para IA). Usa o lojaId do contexto do catálogo, nunca LojaIdService.
  final String lojaId;

  const CatalogProductDetailsSheet({
    super.key,
    required this.name,
    required this.descricao,
    required this.price,
    this.priceMin,
    this.priceMax,
    this.precoOriginal,
    required this.emPromocao,
    required this.percentualPromo,
    required this.valorPromo,
    required this.imagens,
    required this.quantidade,
    this.estoquePorTamanho,
    this.estoquePorCor,
    this.variacoes,
    this.catalogShareUrl,
    this.prazoEntrega,
    this.percentualDescontoPix = 0.0,
    this.itensCombo,
    this.nomeLoja,
    this.contatoWhatsapp,
    this.politicaFrete,
    required this.lojaId,
  });

  bool get _temFaixaPreco =>
      priceMin != null &&
      priceMax != null &&
      (priceMin! - priceMax!).abs() > 0.001;

  String _fmt2(num v) => v.toStringAsFixed(2).replaceAll('.', ',');

  static int _qtdVar(dynamic v) {
    if (v is Map && v.containsKey('qtd')) {
      final q = v['qtd'];
      if (q is num) return q.toInt();
    }
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
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
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withOpacity(0.1),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Detalhes do Produto',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (catalogShareUrl != null && catalogShareUrl!.isNotEmpty)
                  IconButton(
                    onPressed: () async {
                      final precoTexto = _temFaixaPreco
                          ? 'R\$ ${_fmt2(priceMin!)} a R\$ ${_fmt2(priceMax!)}'
                          : 'R\$ ${_fmt2(price)}';
                      final msg = CatalogShareService.buildProductShareMessage(
                        nome: name,
                        precoTexto: precoTexto,
                        descricaoCurta: descricao.trim().isEmpty ? null : descricao,
                        url: catalogShareUrl!,
                      );
                      final uri = Uri.parse(
                        'https://wa.me/?text=${CatalogShareService.encodeForWhatsApp(msg)}',
                      );
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                    icon: const Icon(Icons.share_outlined),
                    tooltip: 'Compartilhar',
                  ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  tooltip: 'Fechar',
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_temFaixaPreco)
                    Text(
                      'R\$ ${_fmt2(priceMin!)} a R\$ ${_fmt2(priceMax!)}',
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  else if (emPromocao && precoOriginal != null) ...[
                    Text(
                      'De: R\$ ${_fmt2(precoOriginal!)}',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          'Por: R\$ ${_fmt2(price)}',
                          style: TextStyle(
                            color: Colors.red[700],
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.red[700],
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            percentualPromo > 0
                                ? '-${percentualPromo.toStringAsFixed(0)}%'
                                : '-R\$ ${valorPromo.toStringAsFixed(2).replaceAll('.', ',')}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else
                    Text(
                      'R\$ ${_fmt2(price)}',
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  if (percentualDescontoPix > 0) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.pix, size: 18, color: Colors.green[700]),
                        const SizedBox(width: 6),
                        Text(
                          'ou ${_temFaixaPreco ? "a partir de " : ""}R\$ ${_fmt2((_temFaixaPreco ? priceMin! : price) * (1 - percentualDescontoPix / 100))} no PIX (${percentualDescontoPix == percentualDescontoPix.truncateToDouble() ? percentualDescontoPix.toInt() : _fmt2(percentualDescontoPix)}% off)',
                          style: TextStyle(
                            color: Colors.green[700],
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (prazoEntrega != null && prazoEntrega!.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.local_shipping_outlined, size: 18, color: Colors.grey[600]),
                        const SizedBox(width: 6),
                        Text(
                          'Entrega: $prazoEntrega',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (estoquePorTamanho != null &&
                      estoquePorTamanho!.isNotEmpty) ...[
                    Text(
                      'Estoque por tamanho',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: estoquePorTamanho!.entries.map((entry) {
                        final tamanho = entry.key;
                        final qtd = entry.value;
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: qtd > 0
                                ? Colors.green.withOpacity(0.1)
                                : Colors.red.withOpacity(0.1),
                            border: Border.all(
                              color: qtd > 0
                                  ? Colors.green[700]!
                                  : Colors.red[700]!,
                              width: 1.5,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            children: [
                              Text(
                                tamanho,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: qtd > 0
                                      ? Colors.green[700]
                                      : Colors.red[700],
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                qtd > 0 ? 'Disponível' : 'Indisponível',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  if (variacoes != null &&
                      variacoes!.isNotEmpty &&
                      (estoquePorTamanho == null ||
                          estoquePorTamanho!.isEmpty)) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Estoque por variação',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...variacoes!.entries.map((e) {
                      if (e.value is! Map) return const SizedBox.shrink();
                      final m = e.value as Map;
                      final label = e.key.toString() == 'sem-tamanho'
                          ? 'Cor (sem tamanho)'
                          : 'Tamanho: ${e.key}';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: Colors.grey[800],
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: m.entries.map((ce) {
                                final q = _qtdVar(ce.value);
                                return Chip(
                                  label: Text(
                                    '${ce.key}: ${q > 0 ? '$q un.' : '0'}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: q > 0
                                          ? Colors.green[800]
                                          : Colors.grey,
                                    ),
                                  ),
                                  backgroundColor: q > 0
                                      ? Colors.green.withOpacity(0.08)
                                      : Colors.grey.withOpacity(0.12),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                  if (estoquePorCor != null &&
                      estoquePorCor!.isNotEmpty &&
                      (estoquePorTamanho == null ||
                          estoquePorTamanho!.isEmpty) &&
                      (variacoes == null || variacoes!.isEmpty)) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Estoque por cor',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: estoquePorCor!.entries.map((entry) {
                        final qtd = entry.value;
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: qtd > 0
                                ? Colors.green.withOpacity(0.1)
                                : Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: qtd > 0
                                  ? Colors.green[700]!
                                  : Colors.red[700]!,
                            ),
                          ),
                          child: Text(
                            '${entry.key}: ${qtd > 0 ? '$qtd un.' : 'esgotado'}',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: qtd > 0
                                  ? Colors.green[800]
                                  : Colors.red[700],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  if ((estoquePorTamanho == null ||
                          estoquePorTamanho!.isEmpty) &&
                      (variacoes == null || variacoes!.isEmpty) &&
                      (estoquePorCor == null || estoquePorCor!.isEmpty)) ...[
                    Row(
                      children: [
                        Icon(
                          quantidade > 0 ? Icons.check_circle : Icons.cancel,
                          color: quantidade > 0
                              ? Colors.green[700]
                              : Colors.red[700],
                          size: 20,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          quantidade > 0
                              ? 'Produto disponível'
                              : 'Produto indisponível',
                          style: TextStyle(
                            color: quantidade > 0
                                ? Colors.green[700]
                                : Colors.red[700],
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (itensCombo != null && itensCombo!.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 22,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Produtos do kit',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.colorScheme.primary.withOpacity(0.25),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Este kit contém os seguintes itens:',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[400],
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 10),
                          ...itensCombo!.asMap().entries.map((entry) {
                            final idx = entry.key + 1;
                            final item = entry.value;
                            final nomeItem = (item['nome'] ?? item['name'] ?? '').toString();
                            final qtd = (item['quantidade'] is num)
                                ? (item['quantidade'] as num).toInt()
                                : int.tryParse('${item['quantidade']}') ?? 1;
                            final tam = (item['tamanho'] ?? '').toString().trim();
                            final cor = (item['cor'] ?? '').toString().trim();
                            final extras = <String>[];
                            if (tam.isNotEmpty) extras.add('Tamanho: $tam');
                            if (cor.isNotEmpty) extras.add('Cor: $cor');
                            final extraLinha = ProdutoVariacaoExtra
                                .resumoExtraLinhaDeItemMap(
                              Map<String, dynamic>.from(item),
                            );
                            if (extraLinha.isNotEmpty) extras.add(extraLinha);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 24,
                                    height: 24,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primary.withOpacity(0.2),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(
                                      '$idx',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          nomeItem,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                        if (extras.isNotEmpty)
                                          Text(
                                            extras.join(' ? '),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[500],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '${qtd}x',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (descricao.isNotEmpty) ...[
                    Text(
                      'Descrição',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      descricao,
                      style: TextStyle(
                        color: Colors.grey[300],
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => _abrirDuvidasPergunte(context),
                    icon: const Icon(Icons.help_outline, size: 20),
                    label: const Text('Dúvidas? Pergunte'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
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

  void _abrirDuvidasPergunte(BuildContext context) {
    final perguntaCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => _DuvidasPergunteDialog(
        produtoNome: name,
        temEstoque: quantidade > 0,
        nomeLoja: nomeLoja,
        contatoWhatsapp: contatoWhatsapp,
        politicaFrete: politicaFrete,
        perguntaCtrl: perguntaCtrl,
        lojaId: lojaId,
      ),
    );
  }
}

/// Dialog para o cliente perguntar sobre o produto (estoque, frete etc.); usa IA.
/// Usa lojaId do contexto do catálogo (passado pelo pai), nunca LojaIdService.
class _DuvidasPergunteDialog extends StatefulWidget {
  final String produtoNome;
  final bool temEstoque;
  final String? nomeLoja;
  final String? contatoWhatsapp;
  final String? politicaFrete;
  final TextEditingController perguntaCtrl;
  final String lojaId;

  const _DuvidasPergunteDialog({
    required this.produtoNome,
    required this.temEstoque,
    this.nomeLoja,
    this.contatoWhatsapp,
    this.politicaFrete,
    required this.perguntaCtrl,
    required this.lojaId,
  });

  @override
  State<_DuvidasPergunteDialog> createState() => _DuvidasPergunteDialogState();
}

class _DuvidasPergunteDialogState extends State<_DuvidasPergunteDialog> {
  bool _enviando = false;
  String? _resposta;

  Future<void> _enviar() async {
    final pergunta = widget.perguntaCtrl.text.trim();
    if (pergunta.isEmpty || _enviando) return;
    final lojaId = widget.lojaId;
    if (!await IaUsoLimiteService.canUse(lojaId, TipoUsoIa.perguntas)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(IaUsoLimiteService.messageLimitExcedido(TipoUsoIa.perguntas)), backgroundColor: Colors.orange.shade700),
      );
      return;
    }
    setState(() {
      _enviando = true;
      _resposta = null;
    });
    try {
      final contexto = <String, dynamic>{
        'produtoNome': widget.produtoNome,
        'temEstoque': widget.temEstoque,
        if (widget.nomeLoja != null && widget.nomeLoja!.trim().isNotEmpty) 'nomeLoja': widget.nomeLoja!.trim(),
        if (widget.contatoWhatsapp != null && widget.contatoWhatsapp!.trim().isNotEmpty) 'contato': widget.contatoWhatsapp!.trim(),
        if (widget.politicaFrete != null && widget.politicaFrete!.trim().isNotEmpty) 'politicaFrete': widget.politicaFrete!.trim(),
      };
      final resposta = await AiLojaService.chatAtendimentoCatalogo(
        pergunta: pergunta,
        contexto: contexto.isEmpty ? null : contexto,
      );
      if (mounted) {
        IaUsoLimiteService.recordUse(lojaId, TipoUsoIa.perguntas);
        setState(() {
          _resposta = resposta;
          _enviando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _enviando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AiLojaService.messageForUser(e)),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxW = math.min(
      kMaxContentWidth,
      MediaQuery.sizeOf(context).width - 40,
    );
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxW),
      child: AlertDialog(
      title: const Text('Dúvidas? Pergunte'),
      content: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: widget.perguntaCtrl,
              decoration: const InputDecoration(
                hintText: 'Ex: Tem em estoque? Qual o prazo de entrega?',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
              enabled: !_enviando,
            ),
            if (_resposta != null) ...[
              const SizedBox(height: 16),
              const Text('Resposta:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.35),
                child: Scrollbar(
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    child: SelectableText(_resposta!, style: const TextStyle(height: 1.4)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
        FilledButton.icon(
          onPressed: _enviando ? null : _enviar,
          icon: _enviando
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.send, size: 18),
          label: Text(_enviando ? 'Enviando…' : 'Enviar'),
        ),
      ],
      ),
    );
  }
}

