// M2.3-R4 — refreshCatalogCartLineFromAdd (M1–M5).

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/catalog_cart_item_snapshot.dart';

const _nomeA = 'Colar A';
const _nomeB = 'Colar B';
const _precoA = 99.90;
const _precoB = 79.90;
const _tamA = 'coracao-rosa';
const _tamB = '45cm-v12';

Map<String, dynamic> _lineA({String tamanho = _tamA}) => {
      'id': 'produto-a',
      'produtosId': 'produto-a',
      'nome': _nomeA,
      'preco': _precoA,
      'quantidade': 1,
      'tamanho': tamanho,
      'cor': 'sem-cor',
    };

Map<String, dynamic> _lineB({String tamanho = _tamB}) => {
      'id': 'produto-b',
      'produtosId': 'produto-b',
      'nome': _nomeB,
      'preco': _precoB,
      'quantidade': 1,
      'tamanho': tamanho,
      'cor': 'sem-cor',
    };

void main() {
  test('M1 — incoming completo e coerente permanece coerente', () {
    final existing = _lineA();
    freezeCatalogCartLineSnapshotOnAdd(existing);
    final incoming = {
      'id': 'produto-a',
      'nome': 'Colar A atualizado',
      'preco': 88.0,
      'quantidade': 1,
      'tamanho': _tamA,
      'cor': 'sem-cor',
    };
    refreshCatalogCartLineFromAdd(existing, incoming);
    expect(existing['productId'], 'produto-a');
    expect(existing['nomeSnapshot'], 'Colar A atualizado');
    expect((existing['preco'] as num).toDouble(), 88.0);
  });

  test('M2 — incoming sem nome preserva nome existente (merge parcial explícito)', () {
    final existing = _lineA();
    freezeCatalogCartLineSnapshotOnAdd(existing);
    final incoming = {
      'id': 'produto-a',
      'preco': 50.0,
      'quantidade': 1,
      'tamanho': _tamA,
      'cor': 'sem-cor',
    };
    refreshCatalogCartLineFromAdd(existing, incoming);
    expect(existing['nomeSnapshot'], _nomeA);
    expect((existing['preco'] as num).toDouble(), 50.0);
  });

  test('M3 — incoming sem preço preserva preço existente', () {
    final existing = _lineA();
    freezeCatalogCartLineSnapshotOnAdd(existing);
    final incoming = {
      'id': 'produto-a',
      'nome': 'Novo nome',
      'quantidade': 1,
      'tamanho': _tamA,
      'cor': 'sem-cor',
    };
    refreshCatalogCartLineFromAdd(existing, incoming);
    expect(existing['nomeSnapshot'], 'Novo nome');
    expect((existing['preco'] as num).toDouble(), _precoA);
  });

  test('M4 — incoming productId diferente não atualiza linha existente', () {
    final existing = _lineA();
    freezeCatalogCartLineSnapshotOnAdd(existing);
    final before = Map<String, dynamic>.from(existing);
    final incoming = _lineB();
    expect(
      () => refreshCatalogCartLineFromAdd(existing, incoming),
      throwsA(isA<CatalogCartLineRejectedException>()),
    );
    expect(existing['nomeSnapshot'], before['nomeSnapshot']);
    expect(existing['productId'], before['productId']);
  });

  test('M5 — mesma variação textual produto diferente não mescla', () {
    final existing = _lineA(tamanho: '45cm-v12');
    freezeCatalogCartLineSnapshotOnAdd(existing);
    final incoming = _lineB(tamanho: '45cm-v12');
    expect(
      () => refreshCatalogCartLineFromAdd(existing, incoming),
      throwsA(isA<CatalogCartLineRejectedException>()),
    );
  });
}
