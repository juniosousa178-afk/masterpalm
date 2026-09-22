import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';

void main() {
  test('resolver prefers explicit stockOperationId over sale doc id', () async {
    final id = await EstoqueTransactionService.resolverSourceOperationIdParaRestore(
      lojaId: 'loja-test',
      explicitStockOperationId: 'real-stock-op-uuid-aaaa-bbbb-cccc-dddddddddddd',
      idFirebase: 'sale-doc-id-that-is-also-uuid-xxxx-yyyy-zzzz-wwwwwwwwwwww',
      vendaIdMarcadorCatalogo: null,
    );
    expect(id, 'real-stock-op-uuid-aaaa-bbbb-cccc-dddddddddddd');
  });

  test('Venda persists stockOperationId field for sync/delete', () {
    final v = Venda(
      clienteNome: 'x',
      produtosDescricao: 'y',
      quantidade: 1,
      preco: 1,
      total: 1,
      formasPagamento: 'pix',
      data: DateTime.utc(2026, 1, 1),
      vendedor: 'v',
      observacao: '',
      idFirebase: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      stockOperationId: '11111111-2222-3333-4444-555555555555',
    );
    expect(v.stockOperationId, '11111111-2222-3333-4444-555555555555');
    expect(v.idFirebase, isNot(v.stockOperationId));
  });
}
