// M3.8 S2-R6 — carrinho do Catálogo Interno (maps compatíveis com NovaVendaModal).

/// Item do carrinho interno → mesma shape de `produtosSelecionados` na Nova Venda.
class CatalogoInternoCartItem {
  CatalogoInternoCartItem({
    required this.productId,
    required this.nome,
    required this.preco,
    this.quantidade = 1,
    this.tamanho = '',
    this.cor = '',
    this.extraValor = '',
    this.variacaoExtraResumo = '',
    this.observacao = '',
    this.imagemUrl = '',
  });

  final String productId;
  final String nome;
  double preco;
  int quantidade;
  String tamanho;
  String cor;
  String extraValor;
  String variacaoExtraResumo;
  String observacao;
  String imagemUrl;

  String get lineKey =>
      '$productId|${tamanho.trim()}|${cor.trim()}|${extraValor.trim()}';

  double get subtotalLinha =>
      preco * (quantidade < 1 ? 1 : quantidade);

  Map<String, dynamic> toNovaVendaMap() => {
        'produto': nome,
        'preco': preco,
        'quantidade': quantidade < 1 ? 1 : quantidade,
        'tamanho': tamanho,
        'cor': cor,
        'extraValor': extraValor,
        'variacaoExtraResumo': variacaoExtraResumo,
        if (productId.trim().isNotEmpty) 'productId': productId,
      };

  CatalogoInternoCartItem copyWith({
    int? quantidade,
    double? preco,
    String? observacao,
  }) {
    return CatalogoInternoCartItem(
      productId: productId,
      nome: nome,
      preco: preco ?? this.preco,
      quantidade: quantidade ?? this.quantidade,
      tamanho: tamanho,
      cor: cor,
      extraValor: extraValor,
      variacaoExtraResumo: variacaoExtraResumo,
      observacao: observacao ?? this.observacao,
      imagemUrl: imagemUrl,
    );
  }
}

abstract final class CatalogoInternoCartLogic {
  static double subtotal(Iterable<CatalogoInternoCartItem> items) {
    var t = 0.0;
    for (final i in items) {
      t += i.subtotalLinha;
    }
    return t;
  }

  /// Agrupa itens iguais (mesma chave) somando quantidade.
  static List<CatalogoInternoCartItem> addOrMerge(
    List<CatalogoInternoCartItem> cart,
    CatalogoInternoCartItem incoming,
  ) {
    final out = List<CatalogoInternoCartItem>.from(cart);
    final idx = out.indexWhere((e) => e.lineKey == incoming.lineKey);
    if (idx < 0) {
      out.add(incoming);
      return out;
    }
    final cur = out[idx];
    out[idx] = cur.copyWith(
      quantidade: cur.quantidade + incoming.quantidade,
    );
    return out;
  }

  static List<CatalogoInternoCartItem> setQuantity(
    List<CatalogoInternoCartItem> cart,
    String lineKey,
    int quantidade,
  ) {
    if (quantidade < 1) {
      return cart.where((e) => e.lineKey != lineKey).toList();
    }
    return [
      for (final e in cart)
        if (e.lineKey == lineKey) e.copyWith(quantidade: quantidade) else e,
    ];
  }

  static List<CatalogoInternoCartItem> remove(
    List<CatalogoInternoCartItem> cart,
    String lineKey,
  ) =>
      cart.where((e) => e.lineKey != lineKey).toList();

  static List<Map<String, dynamic>> toNovaVendaItens(
    Iterable<CatalogoInternoCartItem> items,
  ) =>
      [
        for (final i in items)
          if (i.nome.trim().isNotEmpty) i.toNovaVendaMap(),
      ];

  static String joinObservacoes(Iterable<CatalogoInternoCartItem> items) {
    final parts = <String>[];
    for (final i in items) {
      final o = i.observacao.trim();
      if (o.isEmpty) continue;
      parts.add('${i.nome}: $o');
    }
    return parts.join('\n');
  }
}
