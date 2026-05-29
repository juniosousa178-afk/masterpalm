// lib/models/compra_fornecedor_constants.dart
// Valores persistidos — não renomear sem migração.

/// Status interno da compra (não fiscal).
abstract class CompraFornecedorStatusCompra {
  static const String rascunho = 'rascunho';
  static const String confirmada = 'confirmada';
  static const String cancelada = 'cancelada';

  static const List<String> todos = [rascunho, confirmada, cancelada];

  static String ouPadrao(String s) =>
      todos.contains(s) ? s : rascunho;

  static String legivel(String s) {
    switch (s) {
      case rascunho:
        return 'Rascunho';
      case confirmada:
        return 'Confirmada';
      case cancelada:
        return 'Cancelada';
      default:
        return s;
    }
  }
}

/// Tipo operacional da compra (estoque vs apenas financeira).
abstract class CompraFornecedorTipo {
  static const String produtosEstoque = 'produtos_estoque';
  /// Mercadoria de revenda: valor total primeiro; produtos depois (sem estoque na confirmação).
  static const String revendaDetalharDepois = 'revenda_detalhar_depois';
  static const String financeira = 'financeira';

  static const List<String> todos = [
    produtosEstoque,
    revendaDetalharDepois,
    financeira,
  ];

  static String ouPadrao(String? s) {
    final t = (s ?? '').trim();
    return todos.contains(t) ? t : produtosEstoque;
  }

  /// Pipeline/estoque na confirmação — só compra com produtos informados na hora.
  static bool movimentaEstoque(String tipo) =>
      ouPadrao(tipo) == produtosEstoque;

  static bool usaItensNoTotal(String tipo) =>
      ouPadrao(tipo) == produtosEstoque;

  static bool usaValorInformadoNoTotal(String tipo) {
    final t = ouPadrao(tipo);
    return t == financeira || t == revendaDetalharDepois;
  }

  static bool ehRevendaDetalharDepois(String tipo) =>
      ouPadrao(tipo) == revendaDetalharDepois;

  static String legivel(String s) {
    switch (ouPadrao(s)) {
      case produtosEstoque:
        return 'Compra com produtos para estoque';
      case revendaDetalharDepois:
        return 'Compra para revenda — detalhar produtos depois';
      case financeira:
        return 'Compra apenas financeira';
      default:
        return s;
    }
  }
}

/// Status do detalhamento de produtos (compras revenda_detalhar_depois).
abstract class CompraFornecedorStatusDetalhamento {
  static const String naoAplicavel = 'nao_aplicavel';
  static const String aguardandoDetalhamento = 'aguardando_detalhamento';
  static const String parcialmenteDetalhado = 'parcialmente_detalhado';
  static const String detalhado = 'detalhado';
  static const String conferido = 'conferido';

  static const List<String> todos = [
    naoAplicavel,
    aguardandoDetalhamento,
    parcialmenteDetalhado,
    detalhado,
    conferido,
  ];

  static String ouPadrao(String? s) {
    final t = (s ?? '').trim();
    return todos.contains(t) ? t : naoAplicavel;
  }

  static String legivel(String s) {
    switch (ouPadrao(s)) {
      case aguardandoDetalhamento:
        return 'Aguardando detalhamento';
      case parcialmenteDetalhado:
        return 'Parcialmente detalhado';
      case detalhado:
        return 'Detalhado';
      case conferido:
        return 'Conferido';
      default:
        return '—';
    }
  }

  static bool pendente(String s) {
    final t = ouPadrao(s);
    return t == aguardandoDetalhamento || t == parcialmenteDetalhado;
  }
}

/// Status de pagamento (independente da confirmação da compra).
abstract class CompraFornecedorStatusPagamento {
  static const String pendente = 'pendente';
  static const String parcial = 'parcial';
  static const String pago = 'pago';

  static const List<String> todos = [pendente, parcial, pago];

  static String ouPadrao(String s) =>
      todos.contains(s) ? s : pendente;

  static String legivel(String s) {
    switch (s) {
      case pendente:
        return 'Pendente';
      case parcial:
        return 'Parcial';
      case pago:
        return 'Pago';
      default:
        return s;
    }
  }
}
