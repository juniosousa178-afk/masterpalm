// lib/catalogo_ia/widgets/catalog_chat_widget.dart
// Chat do assistente do catálogo (Etapa 2: busca local + sugestões + WhatsApp).

import 'package:flutter/material.dart';

import '../services/catalog_ia_service.dart';
import 'catalog_chat_message.dart';

const Color _primaryColor = Color(0xFF6366F1);
const Color _surfaceDark = Color(0xFF1E293B);
const Color _cardDark = Color(0xFF0F172A);

/// Chat do assistente do catálogo. Botão flutuante que abre o painel.
class CatalogChatWidget extends StatefulWidget {
  /// Produtos já carregados do catálogo (sem leitura extra).
  final List<Map<String, dynamic>> produtos;

  /// Se false, retorna SizedBox.shrink().
  final bool habilitado;

  /// Telefone ou URL do WhatsApp (extrai dígitos). Fallback: rodape['whatsapp'] ou whatsapp_vendedor.
  final String? whatsappUrl;

  /// Callback quando o usuário toca em um produto sugerido.
  final void Function(Map<String, dynamic> produto)? onProdutoTap;

  const CatalogChatWidget({
    super.key,
    required this.produtos,
    this.habilitado = false,
    this.whatsappUrl,
    this.onProdutoTap,
  });

  @override
  State<CatalogChatWidget> createState() => _CatalogChatWidgetState();
}

class _CatalogChatWidgetState extends State<CatalogChatWidget> {
  bool _aberto = false;
  final _controller = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _mensagens = <_Msg>[];

  static String _montarMensagemWhatsapp(List<Map<String, dynamic>> produtos) {
    if (produtos.isEmpty) return 'Olá! Vim pelo catálogo e gostaria de saber mais.';
    final nomes = produtos.take(5).map((p) => (p['nome'] ?? 'Produto').toString()).join(', ');
    return 'Olá! Vim pelo catálogo e gostaria de saber mais sobre: $nomes';
  }

  @override
  void initState() {
    super.initState();
    _mensagens.add(_Msg(
      isUser: false,
      texto: 'Olá! Pergunte sobre os produtos. Ex: "qual é mais barato?", "tem colar?", "qual está em promoção?", "combo" ou "presente para presente".',
      produtos: null,
      mensagemWhatsapp: null,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _enviar() {
    final t = _controller.text.trim();
    if (t.isEmpty) return;
    _controller.clear();

    setState(() {
      _mensagens.add(_Msg(isUser: true, texto: t, produtos: null, mensagemWhatsapp: null));
    });

    final resp = CatalogIaService.responder(widget.produtos, t);
    final todosProdutos = [
      ...resp.produtos,
      ...resp.sugestoesRelacionadas.take(2),
      ...resp.emPromocaoDestaque.take(2),
      ...resp.combosSugeridos.take(2),
    ];
    final unicos = <Map<String, dynamic>>[];
    final ids = <String>{};
    for (final p in todosProdutos) {
      final id = (p['id'] ?? p['nome'] ?? '').toString();
      if (!ids.contains(id)) {
        ids.add(id);
        unicos.add(p);
      }
    }
    final produtosExibir = unicos.take(8).toList();
    final msg = resp.produtos.isNotEmpty
        ? _montarMensagemWhatsapp(resp.produtos)
        : null;

    setState(() {
      _mensagens.add(_Msg(
        isUser: false,
        texto: resp.texto,
        produtos: produtosExibir.isNotEmpty ? produtosExibir : null,
        mensagemWhatsapp: msg,
      ));
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.habilitado) return const SizedBox.shrink();

    if (!_aberto) {
      return Positioned(
        right: 16,
        bottom: 100,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(28),
          child: InkWell(
            onTap: () => setState(() => _aberto = true),
            borderRadius: BorderRadius.circular(28),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: _primaryColor,
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(Icons.chat_bubble_outline, color: Colors.white, size: 28),
            ),
          ),
        ),
      );
    }

    return Positioned(
      right: 16,
      bottom: 16,
      child: Material(
        elevation: 12,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 340,
          height: 420,
          decoration: BoxDecoration(
            color: _surfaceDark,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, color: _primaryColor, size: 20),
                  const SizedBox(width: 8),
                  const Text('Assistente', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  IconButton(
                    onPressed: () => setState(() => _aberto = false),
                    icon: const Icon(Icons.close, color: Colors.white70),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: Colors.white.withOpacity(0.1)),
            Expanded(
              child: ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _mensagens.length,
                itemBuilder: (_, i) {
                  final m = _mensagens[i];
                  return CatalogChatMessage(
                    isUser: m.isUser,
                    text: m.texto,
                    produtos: m.produtos,
                    whatsappPhone: widget.whatsappUrl,
                    mensagemWhatsapp: m.mensagemWhatsapp,
                    onProdutoTap: m.produtos != null ? widget.onProdutoTap : null,
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: _cardDark,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      onSubmitted: (_) => _enviar(),
                      decoration: InputDecoration(
                        hintText: 'Pergunte sobre produtos…',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.08),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _enviar,
                    icon: const Icon(Icons.send, size: 20),
                    style: IconButton.styleFrom(
                      backgroundColor: _primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                  ),
                ],
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Msg {
  final bool isUser;
  final String texto;
  final List<Map<String, dynamic>>? produtos;
  final String? mensagemWhatsapp;

  _Msg({
    required this.isUser,
    required this.texto,
    this.produtos,
    this.mensagemWhatsapp,
  });
}
