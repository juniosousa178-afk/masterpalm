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
    this.enviandoEmail = false,
    this.onOpenCatalog,
    this.onWhatsApp,
    this.onEmail,
    this.onCopyLink,
    this.onCopyInfo,
  });

  final CarrinhoAbandonadoCatalogoItem item;
  final String linkCatalogo;
  final bool enviandoEmail;
  final VoidCallback? onOpenCatalog;
  final VoidCallback? onWhatsApp;
  final VoidCallback? onEmail;
  final VoidCallback? onCopyLink;
  final VoidCallback? onCopyInfo;

  RecuperacaoScoreResult get _score {
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

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy HH:mm');
    final agora = DateTime.now();
    final ref = item.ultimoUpdate ?? item.criadoEm ?? agora;
    final tempo = agora.difference(ref);
    final subtotal = totalCarrinhoProdutos(item.produtos);
    final total = item.totalOverride ?? (subtotal + item.frete - item.desconto);
    final score = _score;
    final statusLabel = labelStatusCarrinhoAbandonado(item.status);
    final wa = item.telefoneEfetivo;

    return Material(
      color: Colors.white,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Detalhe do carrinho',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: score.badgeColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${score.emojiBadge} ${score.label}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: score.badgeColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text('Cliente', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            _kv('Nome', item.clienteNome.isEmpty ? '—' : item.clienteNome),
            _kv('Telefone', item.clienteTelefone.isEmpty ? '—' : item.clienteTelefone),
            _kv('WhatsApp', wa.isEmpty ? '—' : wa),
            _kv('Email', item.clienteEmail.isEmpty ? '—' : item.clienteEmail),
            _kv('Endereço',
                item.enderecoCompleto.isEmpty ? '—' : item.enderecoCompleto),
            _kv('CPF', item.clienteCpf.isEmpty ? '—' : item.clienteCpf),
            const SizedBox(height: 14),
            Text('Produtos', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            if (item.produtos.isEmpty)
              Text('—', style: TextStyle(color: Colors.grey[600]))
            else
              ...item.produtos.map(_produtoTile),
            const Divider(height: 24),
            _kv('Subtotal', _money(subtotal)),
            _kv('Cupom', item.cupom.isEmpty ? '—' : item.cupom),
            _kv('Desconto', _money(item.desconto)),
            _kv('Frete', _money(item.frete)),
            _kv('Total', _money(total)),
            const SizedBox(height: 12),
            Text('Datas / status', style: Theme.of(context).textTheme.titleMedium),
            _kv(
              'Data',
              item.criadoEm == null ? '—' : df.format(item.criadoEm!),
            ),
            _kv(
              'Última atualização',
              item.ultimoUpdate == null ? '—' : df.format(item.ultimoUpdate!),
            ),
            _kv('Tempo abandonado', formatarTempoAbandonado(tempo)),
            _kv('Status', statusLabel),
            if (score.motivos.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                score.motivos.join(' · '),
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _actionChip(
                  icon: Icons.chat,
                  label: 'WhatsApp',
                  onPressed: wa.trim().length < 10
                      ? null
                      : (onWhatsApp ??
                          () => _open(
                                context,
                                whatsappUrlFromTelefone(wa),
                              )),
                ),
                _actionChip(
                  icon: enviandoEmail ? null : Icons.email_outlined,
                  label: enviandoEmail ? 'Enviando…' : 'E-mail',
                  onPressed: !enviandoEmail && onEmail != null ? onEmail : null,
                  loading: enviandoEmail,
                ),
                _actionChip(
                  icon: Icons.link,
                  label: 'Copiar link',
                  onPressed: onCopyLink ??
                      () => _copy(context, 'Link', linkCatalogo),
                ),
                _actionChip(
                  icon: Icons.open_in_new,
                  label: 'Abrir catálogo',
                  onPressed: onOpenCatalog ??
                      () => _open(context, linkCatalogo),
                ),
                _actionChip(
                  icon: Icons.copy_all,
                  label: 'Copiar informações',
                  onPressed: onCopyInfo ??
                      () => _copy(context, 'Informações', _resumoTexto()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionChip({
    IconData? icon,
    required String label,
    VoidCallback? onPressed,
    bool loading = false,
  }) {
    return ActionChip(
      avatar: loading
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon ?? Icons.circle, size: 16),
      label: Text(label),
      onPressed: onPressed,
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
    final lineTotal = (p['total'] as num?)?.toDouble() ?? (preco * q);
    final img = (p['imagem'] ?? p['imageUrl'] ?? p['url_foto'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: img.isEmpty
                ? Container(
                    width: 52,
                    height: 52,
                    color: Colors.grey.shade200,
                    child: const Icon(Icons.shopping_bag_outlined),
                  )
                : Image.network(
                    img,
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 52,
                      height: 52,
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.broken_image),
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nome, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  [
                    'Qtd $q',
                    if (cor.isNotEmpty) 'Cor $cor',
                    if (tam.isNotEmpty) 'Tam $tam',
                    'Unit. ${_money(preco)}',
                    'Sub ${_money(lineTotal)}',
                  ].join(' · '),
                  style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _resumoTexto() {
    final buf = StringBuffer();
    buf.writeln(item.clienteNome);
    buf.writeln(item.telefoneEfetivo);
    buf.writeln(item.clienteEmail);
    buf.writeln(item.clienteCpf);
    buf.writeln(item.enderecoCompleto);
    for (final p in item.produtos) {
      buf.writeln(
        '- ${p['nome'] ?? p['name']} x${p['quantidade'] ?? 1} '
        'cor=${p['cor'] ?? ''} tam=${p['tamanho'] ?? ''}',
      );
    }
    buf.writeln('Cupom: ${item.cupom}');
    buf.writeln('Frete: ${_money(item.frete)}');
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
            width: 130,
            child: Text(k, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          ),
          Expanded(
            child: Text(
              v,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
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
