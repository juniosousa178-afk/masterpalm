// M2.3-R6 — probe comportamental merge HEAD (sem CatalogCartLineRejectedException).

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/catalog_cart_item_snapshot.dart';

const _nomeA = 'Colar Coração Cravejado Rosa';
const _nomeB = 'Colar Ponto de Luz Gota 45cm';
const _tam = 'variacao-b';

/// Identidade HEAD (sem productId canônico prioritário, sem variacaoId).
String headCartLineIdentity(Map<String, dynamic> item) {
  final id = '${item['id'] ?? item['produtosId'] ?? ''}';
  final tam = (item['tamanho'] ?? '').toString().trim().toLowerCase();
  final cr = (item['cor'] ?? '').toString().trim().toLowerCase();
  final ex = (item['extraValor'] ?? item['variacaoExtra'] ?? '')
      .toString()
      .trim()
      .toLowerCase();
  return '$id|$tam|$cr|$ex';
}

/// Merge HEAD: copia campos do incoming e re-freeze simplificado.
void headRefreshCatalogCartLineFromAdd(
  Map<String, dynamic> existingLine,
  Map<String, dynamic> incoming,
) {
  for (final key in [
    'id',
    'produtosId',
    'nome',
    'preco',
    'tamanho',
    'cor',
    'imageUrl',
    'slug',
  ]) {
    if (incoming.containsKey(key)) {
      existingLine[key] = incoming[key];
    }
  }
  existingLine['nomeSnapshot'] = existingLine['nome'];
  existingLine['precoUnitarioSnapshot'] = existingLine['preco'];
}

Map<String, dynamic> _lineA() => {
      'id': 'produto-a',
      'nome': _nomeA,
      'preco': 99.90,
      'quantidade': 1,
      'tamanho': _tam,
      'cor': 'cor-a',
    };

Map<String, dynamic> _incomingB() => {
      'id': 'produto-b',
      'nome': _nomeB,
      'preco': 79.90,
      'quantidade': 1,
      'tamanho': _tam,
      'cor': 'cor-b',
    };

void main() {
  test('V1 HEAD — productId integra a identidade de linha', () {
    final a = _lineA();
    final b = _incomingB();
    expect(headCartLineIdentity(a), isNot(headCartLineIdentity(b)));
    expect(headCartLineIdentity(a), 'produto-a|variacao-b|cor-a|');
    expect(headCartLineIdentity(b), 'produto-b|variacao-b|cor-b|');
  });

  test('probe HEAD — produtos distintos não mesclam por tamanho igual', () {
    final existing = _lineA();
    final incoming = _incomingB();
    expect(
      headCartLineIdentity(existing),
      isNot(headCartLineIdentity(incoming)),
    );
    final cart = [existing];
    final idx = cart.indexWhere(
      (i) => headCartLineIdentity(i) == headCartLineIdentity(incoming),
    );
    expect(idx, -1);
  });

  test('probe HEAD — mesmo productId atualiza campos via refresh', () {
    final existing = _lineA();
    existing['nomeSnapshot'] = _nomeA;
    final incoming = {
      'id': 'produto-a',
      'nome': 'Nome atualizado catálogo',
      'preco': 88.0,
      'tamanho': _tam,
      'cor': 'cor-a',
      'quantidade': 1,
    };
    expect(
      headCartLineIdentity(existing),
      headCartLineIdentity(incoming),
    );
    headRefreshCatalogCartLineFromAdd(existing, incoming);
    expect(existing['nome'], 'Nome atualizado catálogo');
    expect(existing['id'], 'produto-a');
  });

  test('pós-patch — refresh rejeita merge cross-product', () {
    final existing = _lineA();
    freezeCatalogCartLineSnapshotOnAdd(existing);
    expect(
      () => refreshCatalogCartLineFromAdd(existing, _incomingB()),
      throwsA(isA<CatalogCartLineRejectedException>()),
    );
  });
}
