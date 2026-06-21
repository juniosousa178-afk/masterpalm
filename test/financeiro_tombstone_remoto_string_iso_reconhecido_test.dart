import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/financeiro_firestore_service.dart';

void main() {
  test('deletedAt String ISO reconhece tombstone remoto', () {
    expect(
      FinanceiroFirestoreService.lancamentoRemotoExcluidoOuEstornadoVisivel({
        'deletedAt': '2026-06-21T16:27:25.404Z',
        'status': 'excluido',
        'estornado': false,
      }),
      isTrue,
    );
  });

  test('deletedAt String vazia não reconhece tombstone', () {
    expect(
      FinanceiroFirestoreService.lancamentoRemotoExcluidoOuEstornadoVisivel({
        'deletedAt': '   ',
        'status': 'pago',
        'estornado': false,
      }),
      isFalse,
    );
  });
}
