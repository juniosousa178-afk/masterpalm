// M2.3-R5 — merge M4/M5 comportamento pós-correção (baseline documentado).

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/catalog_cart_item_snapshot.dart';

const _nomeA = 'Colar A';
const _nomeB = 'Colar B';
const _tam = '45cm-v12';

Map<String, dynamic> _lineA() => {
      'id': 'produto-a',
      'nome': _nomeA,
      'preco': 99.90,
      'quantidade': 1,
      'tamanho': _tam,
      'cor': 'sem-cor',
    };

Map<String, dynamic> _lineB() => {
      'id': 'produto-b',
      'nome': _nomeB,
      'preco': 79.90,
      'quantidade': 1,
      'tamanho': _tam,
      'cor': 'sem-cor',
    };

void main() {
  test('M4 — incoming B não atualiza linha existente A', () {
    final existing = _lineA();
    freezeCatalogCartLineSnapshotOnAdd(existing);
    final before = Map<String, dynamic>.from(existing);
    expect(
      () => refreshCatalogCartLineFromAdd(existing, _lineB()),
      throwsA(isA<CatalogCartLineRejectedException>()),
    );
    expect(existing['nomeSnapshot'], before['nomeSnapshot']);
    expect(existing['productId'], 'produto-a');
  });

  test('M5 — mesma variação textual, produtos diferentes, não mescla', () {
    final existing = _lineA();
    freezeCatalogCartLineSnapshotOnAdd(existing);
    expect(
      () => refreshCatalogCartLineFromAdd(existing, _lineB()),
      throwsA(isA<CatalogCartLineRejectedException>()),
    );
  });
}
