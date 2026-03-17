// test/estoque_transaction_service_test.dart
// Testes de validação do EstoqueTransactionService (sem Firestore).

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';

void main() {
  group('EstoqueTransactionService – validação', () {
    test('baixarEstoqueTransaction lança quando quantidade <= 0', () async {
      expect(
        EstoqueTransactionService.baixarEstoqueTransaction(
          lojaId: 'loja_test',
          quantidade: 0,
          nome: 'Produto X',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('baixarEstoqueTransaction lança quando quantidade negativa', () async {
      expect(
        EstoqueTransactionService.baixarEstoqueTransaction(
          lojaId: 'loja_test',
          quantidade: -1,
          nome: 'Produto X',
        ),
        throwsA(isA<Exception>()),
      );
    });
  });
}
