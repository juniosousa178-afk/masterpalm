import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/nova_venda_payment_guard.dart';

void main() {
  group('novaVendaPagamentoImpedeSalvar', () {
    test('pagamento incompleto bloqueia persistência', () {
      expect(
        novaVendaPagamentoImpedeSalvar(
          total: 6889,
          allocated: 0,
          isFiado: false,
        ),
        isTrue,
      );
      expect(kNovaVendaPagamentoIncompletoMensagem, contains('forma de pagamento'));
    });

    test('pagamento igual ao total não bloqueia', () {
      expect(
        novaVendaPagamentoImpedeSalvar(
          total: 6889,
          allocated: 6889,
          isFiado: false,
        ),
        isFalse,
      );
    });

    test('fiado com saldo em aberto não bloqueia', () {
      expect(
        novaVendaPagamentoImpedeSalvar(
          total: 6889,
          allocated: 0,
          isFiado: true,
        ),
        isFalse,
      );
    });

    test('fiado com pagamento maior que o total bloqueia', () {
      expect(
        novaVendaPagamentoImpedeSalvar(
          total: 100,
          allocated: 150,
          isFiado: true,
        ),
        isTrue,
      );
    });
  });
}
