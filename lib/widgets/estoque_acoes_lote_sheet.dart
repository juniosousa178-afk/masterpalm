import 'package:flutter/material.dart';

enum EstoqueAcaoLote {
  adicionarCatalogo,
  removerCatalogo,
  mercadoLivre,
  tiktokShop,
  shopee,
  alterarCategoria,
  alterarSubcategoria,
  dividirSemJuros,
  definirDescontoPix,
  removerDescontoPix,
  promocao,
  excluir,
}

class _Tile {
  const _Tile(this.acao, this.icon, this.titulo, this.subtitulo, this.cor, {this.divisorAntes = false});

  final EstoqueAcaoLote acao;
  final IconData icon;
  final String titulo;
  final String subtitulo;
  final Color cor;
  final bool divisorAntes;
}

const _primary = Color(0xFF6366F1);
const _success = Color(0xFF22C55E);
const _warning = Color(0xFFF59E0B);
const _error = Color(0xFFEF4444);

/// Pix actions come first so they stay visible without scrolling even with large text on small phones.
const List<_Tile> _tiles = [
  _Tile(EstoqueAcaoLote.definirDescontoPix, Icons.qr_code, 'Definir desconto no Pix em lote',
      'Aplica um % de desconto no Pix aos selecionados', _primary),
  _Tile(EstoqueAcaoLote.removerDescontoPix, Icons.money_off, 'Remover desconto no Pix',
      'Tira só o desconto no Pix; preço normal, estoque e promoções não mudam', _warning),
  _Tile(EstoqueAcaoLote.promocao, Icons.local_offer_outlined, 'Promoção em lote',
      'Ativar promoção (% ou R\$ fixo) nos selecionados', Color(0xFFFF6D00)),
  _Tile(EstoqueAcaoLote.dividirSemJuros, Icons.credit_card, 'Dividir sem juros em lote',
      'Ativar parcelamento sem juros nos selecionados', _success),
  _Tile(EstoqueAcaoLote.adicionarCatalogo, Icons.add_shopping_cart, 'Adicionar ao Catálogo',
      'Publicar produtos no catálogo web', _success,
      divisorAntes: true),
  _Tile(EstoqueAcaoLote.removerCatalogo, Icons.remove_shopping_cart, 'Remover do Catálogo',
      'Despublicar do catálogo web', _warning),
  _Tile(EstoqueAcaoLote.alterarCategoria, Icons.category, 'Alterar Categoria em Lote',
      'Definir mesma categoria para todos', _primary,
      divisorAntes: true),
  _Tile(EstoqueAcaoLote.alterarSubcategoria, Icons.label, 'Alterar Subcategoria em Lote',
      'Definir mesma subcategoria para todos', _primary),
  _Tile(EstoqueAcaoLote.mercadoLivre, Icons.shopping_bag, 'Mercado Livre', 'Adicionar ao Mercado Livre',
      Color(0xFFFFF159),
      divisorAntes: true),
  _Tile(EstoqueAcaoLote.tiktokShop, Icons.video_library, 'TikTok Shop', 'Adicionar ao TikTok Shop', Colors.black),
  _Tile(EstoqueAcaoLote.shopee, Icons.store, 'Shopee', 'Adicionar à Shopee', Color(0xFFEE4D2D)),
  _Tile(EstoqueAcaoLote.excluir, Icons.delete, 'Excluir Produtos', 'Remover permanentemente do estoque', _error,
      divisorAntes: true),
];

/// "Ações em Lote" sheet of the stock screen; resolves with the chosen action (null when closed).
class EstoqueAcoesLoteSheet extends StatefulWidget {
  const EstoqueAcoesLoteSheet({super.key, required this.rotuloSelecionados});

  final String rotuloSelecionados;

  static Future<EstoqueAcaoLote?> mostrar(BuildContext context, {required String rotuloSelecionados}) {
    return showModalBottomSheet<EstoqueAcaoLote>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => EstoqueAcoesLoteSheet(rotuloSelecionados: rotuloSelecionados),
    );
  }

  @override
  State<EstoqueAcoesLoteSheet> createState() => _EstoqueAcoesLoteSheetState();
}

class _EstoqueAcoesLoteSheetState extends State<EstoqueAcoesLoteSheet> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rotuloSelecionados = widget.rotuloSelecionados;
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.flash_on, color: _primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Ações em Lote', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Text(rotuloSelecionados, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                      ],
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: Scrollbar(
                controller: _scroll,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _scroll,
                  child: Column(
                    children: [
                      for (final t in _tiles) ...[
                        if (t.divisorAntes) const Divider(height: 1),
                        ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: t.cor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(t.icon, color: t.cor, size: 22),
                          ),
                          title: Text(t.titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(t.subtitulo, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                          trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                          onTap: () => Navigator.pop(context, t.acao),
                        ),
                      ],
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
