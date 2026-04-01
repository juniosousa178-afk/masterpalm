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
