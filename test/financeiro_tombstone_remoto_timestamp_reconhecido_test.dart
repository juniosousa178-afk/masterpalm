import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/financeiro_firestore_service.dart';

void main() {
  test('deletedAt Timestamp reconhece tombstone remoto', () {
    expect(
      FinanceiroFirestoreService.lancamentoRemotoExcluidoOuEstornadoVisivel({
        'deletedAt': Timestamp.fromDate(DateTime(2026, 6, 21, 16, 27)),
        'status': 'excluido',
        'estornado': false,
      }),
      isTrue,
    );
  });

  test('status estornado reconhece tombstone mesmo sem deletedAt', () {
    expect(
      FinanceiroFirestoreService.lancamentoRemotoExcluidoOuEstornadoVisivel({
        'status': 'estornado',
        'estornado': true,
      }),
      isTrue,
    );
  });
}
