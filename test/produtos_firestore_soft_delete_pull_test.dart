import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';

void main() {
  group('isEstoqueDocPendingSoftDelete', () {
    test('retorna true quando pendingSoftDelete é true', () {
      expect(
        ProdutosFirestoreService.isEstoqueDocPendingSoftDelete({
          ProdutosFirestoreService.fieldEstoquePendingSoftDelete: true,
          'nome': 'X',
        }),
        true,
      );
    });

    test('retorna false quando ausente ou false', () {
      expect(ProdutosFirestoreService.isEstoqueDocPendingSoftDelete({}), false);
      expect(
        ProdutosFirestoreService.isEstoqueDocPendingSoftDelete({
          ProdutosFirestoreService.fieldEstoquePendingSoftDelete: false,
        }),
        false,
      );
    });

    test('documento “normal” com outros campos não é tratado como pendente', () {
      expect(
        ProdutosFirestoreService.isEstoqueDocPendingSoftDelete({
          'quantidade': 5,
          'nome': 'Produto',
        }),
        false,
      );
    });
  });
}
