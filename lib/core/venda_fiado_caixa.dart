import '../models/venda.dart';

/// Venda fiada sem valores em dinheiro/pix/cartão gravados: o caixa só entra via contas a receber.
bool vendaFiadoSemPagamentoExplicito(Venda v) {
  final explicit =
      v.pagamentoDinheiro + v.pagamentoPix + v.pagamentoCartao;
  if (explicit.abs() > 1e-6) return false;
  return v.formasPagamento.toLowerCase().contains('fiado');
}
