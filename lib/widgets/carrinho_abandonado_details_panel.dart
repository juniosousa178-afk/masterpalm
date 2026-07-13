import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/carrinho_abandonado_ui.dart';
import '../core/carrinho_recuperacao_score.dart';
import '../core/pedido_cliente_snapshot_helpers.dart';
import '../services/carrinho_abandonado_service.dart';

/// Detalhe completo de um carrinho abandonado (somente leitura + ações seguras).
class CarrinhoAbandonadoDetailsPanel extends StatelessWidget {
  const CarrinhoAbandonadoDetailsPanel({
    super.key,
    required this.item,
    required this.linkCatalogo,
    this.clienteEmail = '',
    this.cupom,
    this.frete,
    this.desconto,
    this.totalOverride,
    this.visitasCatalogo = 0,
    this.retornosCatalogo = 0,
    this.onOpenCatalog,
  });

  final CarrinhoAbandonadoCatalogoItem item;
  final String linkCatalogo;
  final String clienteEmail;
  final String? cupom;
  final double? frete;
  final double? desconto;
  final double? totalOverride;
  final int visitasCatalogo;
  final int retornosCatalogo;
  final VoidCallback? onOpenCatalog;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy HH:mm');
    final agora = DateTime.now();
    final ref = item.ultimoUpdate ?? item.criadoEm ?? agora;
    final tempo = agora.difference(ref);
    final subtotal = totalCarrinhoProdutos(item.produtos);
    final freteV = frete ?? 0;
    final descV = desconto ?? 0;
    final total = totalOverride ?? (subtotal + freteV - descV);
    final score = calcularProbabilidadeRecuperacao(
      tempoAbandonado: tempo,
      valorCarrinho: total,
      visitasCatalogo: visitasCatalogo,
      retornosCatalogo: retornosCatalogo,
    );
    final statusLabel = labelStatusCarrinhoAbandonado(item.status);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cliente', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          _kv('Nome', item.clienteNome),
          _kv('Telefone', item.clienteTelefone),
          _kv('WhatsApp', item.clienteTelefone),
          _kv('Email', clienteEmail.isEmpty ? '—' : clienteEmail),
          const SizedBox(height: 12),
          Text('Carrinho', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          ...item.produtos.map(_produtoTile),
          const Divider(height: 24),
          _kv('Subtotal', _money(subtotal)),
          _kv('Cupom', (cupom ?? '').isEmpty ? '—' : cupom!),
          _kv('Desconto', _money(descV)),
          _kv('Frete', _money(freteV)),
          _kv('Total', _money(total)),
          const SizedBox(height: 12),
          Text('Datas', style: Theme.of(context).textTheme.titleMedium),
          _kv(
            'Criado',
            item.criadoEm == null ? '—' : df.format(item.criadoEm!),
          ),
          _kv(
            'Última alteração',
            item.ultimoUpdate == null ? '—' : df.format(item.ultimoUpdate!),
          ),
          _kv('Tempo abandonado', formatarTempoAbandonado(tempo)),
          _kv('Status', statusLabel),
          const SizedBox(height: 8),
          Chip(
            avatar: Icon(
              score.categoria == RecuperacaoProbabilidade.alta
                  ? Icons.trending_up
                  : score.categoria == RecuperacaoProbabilidade.media
                      ? Icons.trending_flat
                      : Icons.trending_down,
              size: 16,
            ),
            label: Text('Recuperação: ${score.label} (${score.pontos} pts)'),
          ),
          if (score.motivos.isNotEmpty)
            Text(
              score.motivos.join(' · '),
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                avatar: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Abrir catálogo'),
                onPressed: onOpenCatalog ??
                    () => _open(context, linkCatalogo),
              ),
              ActionChip(
                avatar: const Icon(Icons.chat, size: 16),
                label: const Text('WhatsApp'),
                onPressed: () => _open(
                  context,
                  whatsappUrlFromTelefone(item.clienteTelefone),
                ),
              ),
              ActionChip(
                avatar: const Icon(Icons.link, size: 16),
                label: const Text('Copiar link'),
                onPressed: () => _copy(context, 'Link', linkCatalogo),
              ),
              ActionChip(
                avatar: const Icon(Icons.copy_all, size: 16),
                label: const Text('Copiar carrinho'),
                onPressed: () => _copy(context, 'Carrinho', _resumoTexto()),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Recuperar venda: disponível em sprint futura (estrutura preparada).',
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _produtoTile(Map<String, dynamic> p) {
    final nome = (p['nome'] ?? p['name'] ?? 'Produto').toString();
    final q = (p['quantidade'] as num?)?.toInt() ?? 1;
    final cor = (p['cor'] ?? '').toString();
    final tam = (p['tamanho'] ?? '').toString();
    final preco = (p['preco'] as num?)?.toDouble() ??
        (p['precoUnitario'] as num?)?.toDouble() ??
        0;
    final img = (p['imagem'] ?? p['imageUrl'] ?? p['url_foto'] ?? '').toString();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: img.isEmpty
          ? const CircleAvatar(child: Icon(Icons.shopping_bag_outlined))
          : ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                img,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const CircleAvatar(child: Icon(Icons.broken_image)),
              ),
            ),
      title: Text(nome, style: const TextStyle(fontSize: 13)),
      subtitle: Text(
        [
          'Qtd $q',
          if (tam.isNotEmpty) 'Tam $tam',
          if (cor.isNotEmpty) 'Cor $cor',
          _money(preco),
        ].join(' · '),
        style: const TextStyle(fontSize: 11),
      ),
    );
  }

  String _resumoTexto() {
    final buf = StringBuffer();
    buf.writeln(item.clienteNome);
    buf.writeln(item.clienteTelefone);
    for (final p in item.produtos) {
      buf.writeln(
        '- ${p['nome'] ?? p['name']} x${p['quantidade'] ?? 1}',
      );
    }
    buf.writeln(linkCatalogo);
    return buf.toString();
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(k, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          ),
          Expanded(
            child: Text(v, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  String _money(double v) => 'R\$ ${v.toStringAsFixed(2)}';

  Future<void> _copy(BuildContext context, String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copiado')),
    );
  }

  Future<void> _open(BuildContext context, String url) async {
    if (url.isEmpty) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
