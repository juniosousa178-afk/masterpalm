import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/screens/pre_pedidos/pre_pedido_operacional.dart';

void main() {
  group('podeExibirAtualizacaoStatusOperacional', () {
    test('inclui paid, pago e confirmado', () {
      expect(podeExibirAtualizacaoStatusOperacional('paid'), isTrue);
      expect(podeExibirAtualizacaoStatusOperacional('PAGO'), isTrue);
      expect(podeExibirAtualizacaoStatusOperacional('confirmado'), isTrue);
      expect(podeExibirAtualizacaoStatusOperacional('pendente'), isFalse);
    });
  });

  group('opcoesProximoStatusOperacional', () {
    test('paid oferece fluxo logístico completo', () {
      final op = opcoesProximoStatusOperacional('paid');
      expect(op.map((e) => e['valor']), contains('em_preparacao'));
      expect(op.map((e) => e['valor']), contains('entregue'));
    });

    test('enviado só permite entregue', () {
      final op = opcoesProximoStatusOperacional('enviado');
      expect(op.length, 1);
      expect(op.first['valor'], 'entregue');
    });
  });

  group('isPrePedidoPagamentoGatewayConcluido', () {
    test('detecta paymentId e statusPagamento aprovado', () {
      expect(
        isPrePedidoPagamentoGatewayConcluido({
          'status': 'pendente',
          'statusPagamento': 'aprovado',
          'paymentId': '123',
        }),
        isTrue,
      );
      expect(
        isPrePedidoPagamentoGatewayConcluido({'status': 'pendente'}),
        isFalse,
      );
    });
  });
}
