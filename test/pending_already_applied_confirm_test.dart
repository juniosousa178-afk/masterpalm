import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/produto_stock_revision.dart';
import 'package:master_palm/models/produto.dart';

void main() {
  test('already-applied pending confirms without requiring rev strictly greater',
      () {
    final p = Produto(
      nome: 'BR58PR',
      custoReal: 0,
      frete: 0,
      gastosFixos: 0,
      gastosVariaveis: 0,
      precoSugerido: 0,
      precoFinal: 97,
      quantidade: 1,
      precoUnitario: 97,
      categoria: 'Brinco',
      dataEntrada: DateTime(2026, 1, 1),
      stockRevision: 3,
      pendingStockOperationId:
          'editstock_de9507cc-caf2-49f3-a30d-23abb2945146_f816d96061aa0a578e0a3cc72c95159a13ffca50557d3ba6381d65a67ec3b813',
      pendingStockBaseRevision: 3,
    );
    final remote = <String, dynamic>{
      'quantidade': 0,
      'stockRevision': 4,
      'stockOperationId':
          'editstock_de9507cc-caf2-49f3-a30d-23abb2945146_f816d96061aa0a578e0a3cc72c95159a13ffca50557d3ba6381d65a67ec3b813',
      'stockKind': 'simple',
    };
    expect(tryConfirmStockFromRemote(p, remote), isTrue);
    expect(hasPendingStockMutation(p), isFalse);
    expect(p.confirmedStockOperationId, remote['stockOperationId']);
    expect(p.stockRevision, 4);
  });

  test('unrelated remote op does not auto-confirm pending', () {
    final p = Produto(
      nome: 'X',
      custoReal: 0,
      frete: 0,
      gastosFixos: 0,
      gastosVariaveis: 0,
      precoSugerido: 0,
      precoFinal: 1,
      quantidade: 1,
      precoUnitario: 1,
      categoria: 'x',
      dataEntrada: DateTime(2026, 1, 1),
      stockRevision: 1,
      pendingStockOperationId: 'pending-op-aaa',
      pendingStockBaseRevision: 1,
    );
    final remote = <String, dynamic>{
      'quantidade': 0,
      'stockRevision': 5,
      'stockOperationId': 'other-op-bbb',
    };
    expect(tryConfirmStockFromRemote(p, remote), isFalse);
    expect(hasPendingStockMutation(p), isTrue);
  });
}
