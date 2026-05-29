// lib/models/conta_pagar_constants.dart
// Valores persistidos — não renomear sem migração.

abstract class ContaPagarStatus {
  static const String pendente = 'pendente';
  static const String pago = 'pago';
  static const String vencido = 'vencido';
  static const String cancelado = 'cancelado';

  static const List<String> todos = [pendente, pago, vencido, cancelado];

  static String ouPadrao(String s) =>
      todos.contains(s) ? s : pendente;

  static String legivel(String s) {
    switch (s) {
      case pendente:
        return 'Pendente';
      case pago:
        return 'Pago';
      case vencido:
        return 'Vencido';
      case cancelado:
        return 'Cancelado';
      default:
        return s;
    }
  }
}
