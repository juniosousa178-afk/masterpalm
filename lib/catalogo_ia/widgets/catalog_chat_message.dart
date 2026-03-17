// lib/catalogo_ia/widgets/catalog_chat_message.dart
// Componente de mensagem do chat do catálogo.
// Etapa 2: botão WhatsApp real com mensagem pronta; fallback elegante.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const Color _userBg = Color(0xFF6366F1);
const Color _assistantBg = Color(0xFF1E293B);
const Color _cardBg = Color(0xFF0F172A);

/// Mensagem do usuário ou do assistente.
class CatalogChatMessage extends StatelessWidget {
  final bool isUser;
  final String text;
  final List<Map<String, dynamic>>? produtos;
  final void Function(Map<String, dynamic> produto)? onProdutoTap;
  /// Telefone ou URL do WhatsApp (extrai dígitos para wa.me).
  final String? whatsappPhone;
  /// Mensagem pronta para enviar no WhatsApp.
  final String? mensagemWhatsapp;

  const CatalogChatMessage({
    super.key,
    required this.isUser,
    required this.text,
    this.produtos,
    this.onProdutoTap,
    this.whatsappPhone,
    this.mensagemWhatsapp,
  });

  static String _extrairDigitos(String? s) {
    if (s == null || s.trim().isEmpty) return '';
    return s.replaceAll(RegExp(r'[^\d]'), '').trim();
  }

  Future<void> _abrirWhatsapp() async {
    final phone = _extrairDigitos(whatsappPhone);
    if (phone.length < 10) return;
    final msg = mensagemWhatsapp?.trim() ?? 'Olá! Vim pelo catálogo e gostaria de saber mais.';
    final url = Uri.parse(
      'https://wa.me/$phone?text=${Uri.encodeComponent(msg)}',
    );
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final temWhatsapp = _extrairDigitos(whatsappPhone).length >= 10;
    final mostraBotaoWhatsapp = !isUser && (temWhatsapp || produtos != null);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        child: Column(
          crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? _userBg : _assistantBg,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
              ),
              child: SelectableText(
                text,
                style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
              ),
            ),
            if (!isUser && produtos != null && produtos!.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 100,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: produtos!.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final p = produtos![i];
                    return _ProdutoChip(
                      produto: p,
                      onTap: () => onProdutoTap?.call(p),
                    );
                  },
                ),
              ),
            ],
            if (mostraBotaoWhatsapp && produtos != null && produtos!.isNotEmpty) ...[
              const SizedBox(height: 8),
              temWhatsapp
                  ? OutlinedButton.icon(
                      onPressed: _abrirWhatsapp,
                      icon: const Icon(Icons.chat, size: 16),
                      label: const Text('Falar no WhatsApp'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF25D366),
                        side: const BorderSide(color: Color(0xFF25D366)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    )
                  : Tooltip(
                      message: 'Configure o WhatsApp nas configurações da loja.',
                      child: Opacity(
                        opacity: 0.6,
                        child: OutlinedButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.chat_outlined, size: 16),
                          label: const Text('Falar no WhatsApp'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF25D366),
                            side: const BorderSide(color: Color(0xFF25D366), width: 1),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                      ),
                    ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProdutoChip extends StatelessWidget {
  final Map<String, dynamic> produto;
  final VoidCallback? onTap;

  const _ProdutoChip({required this.produto, this.onTap});

  @override
  Widget build(BuildContext context) {
    final nome = (produto['nome'] ?? 'Produto').toString();
    final img = produto['imageUrl'] ?? produto['imagens']?[0];
    final preco = produto['preco'] ?? produto['precoFinal'] ?? produto['priceMin'];
    final precoStr = preco is num
        ? 'R\$ ${preco.toStringAsFixed(2).replaceAll('.', ',')}'
        : '';
    final emPromocao = produto['emPromocao'] == true;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 90,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: emPromocao ? const Color(0xFF4ADE80).withValues(alpha: 0.5) : Colors.white12,
            width: emPromocao ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            if (emPromocao)
              Container(
                margin: const EdgeInsets.only(bottom: 2),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFF4ADE80).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('Promoção', style: TextStyle(color: Color(0xFF4ADE80), fontSize: 8, fontWeight: FontWeight.w600)),
              ),
            if (img != null && img.toString().isNotEmpty)
              (img.toString().startsWith('blob:'))
                  ? Container(
                      height: 48,
                      width: 78,
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.image_not_supported, color: Colors.white38, size: 20),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(
                        img.toString(),
                        height: 48,
                        width: 78,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          height: 48,
                          color: Colors.white10,
                          child: const Icon(Icons.image_not_supported, color: Colors.white38, size: 20),
                        ),
                      ),
                    )
            else
              Container(
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.inventory_2_outlined, color: Colors.white38, size: 20),
              ),
            const SizedBox(height: 4),
            Text(
              nome.length > 12 ? '${nome.substring(0, 12)}…' : nome,
              style: const TextStyle(color: Colors.white, fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            if (precoStr.isNotEmpty)
              Text(
                precoStr,
                style: const TextStyle(color: Color(0xFF4ADE80), fontSize: 10, fontWeight: FontWeight.w600),
              ),
          ],
        ),
      ),
    );
  }
}
