// M2.3-R3 — casos adversariais A–F: enrich/freeze sem preço como identidade.

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/screens/public_catalog/catalog_estoque_helper.dart';
import 'package:master_palm/services/catalog_cart_item_snapshot.dart';

const _nomeA = 'Colar Coração';
const _nomeB = 'Colar Gota';
const _precoPix = 75.91;
const _precoBase = 79.90;

Map<String, dynamic> _produtoA() => {
      'id': 'produto-a',
      'nome': _nomeA,
      'preco': _precoPix,
      'percentualDescontoPix': 0.0,
    };

Map<String, dynamic> _produtoB() => {
      'id': 'produto-b',
      'nome': _nomeB,
      'preco': _precoBase,
      'percentualDescontoPix': 5.0,
    };

Map<String, dynamic> _linhaBValida() {
  final line = {
    'id': 'produto-b',
    'nome': _nomeB,
    'preco': _precoBase,
    'percentualDescontoPix': 5.0,
    'quantidade': 1,
    'tamanho': '45cm-v12',
    'cor': 'sem-cor',
  };
  freezeCatalogCartLineSnapshotOnAdd(line);
  return line;
}

void main() {
  final catalog = [_produtoA(), _produtoB()];

  group('Caso A — dois produtos com o mesmo preço PIX', () {
    test('enrich não corrige nome contaminado por coincidência de preço', () {
      final contaminada = {
        'schemaVersion': catalogCartItemSchemaVersion,
        'productId': 'produto-b',
        'id': 'produto-b',
        'nome': _nomeA,
        'nomeSnapshot': _nomeA,
        'preco': _precoPix,
        'precoUnitarioSnapshot': _precoPix,
        'quantidade': 1,
        'tamanho': 'coracao-rosa',
        'cor': 'sem-cor',
      };

      final enriched = enrichCatalogCartLineSnapshot(
        line: contaminada,
        catalogProducts: catalog,
        pagamento: 'PIX',
      );

      expect(enriched['productId'], 'produto-b');
      expect(enriched['nomeSnapshot'], _nomeA);
      expect(enriched['nome'], _nomeA);
      expect(enriched['nomeSnapshot'], isNot(_nomeB));
    });
  });

  group('Caso B — preço alterado depois da inclusão', () {
    test('enrich preserva preço histórico e identidade B', () {
      final line = _linhaBValida();
      final precoHistorico =
          (line['precoUnitarioSnapshot'] as num).toDouble();

      final catalogNovo = [
        {
          ..._produtoB(),
          'preco': 120.0,
          'percentualDescontoPix': 0.0,
        },
      ];

      final enriched = enrichCatalogCartLineSnapshot(
        line: Map<String, dynamic>.from(line),
        catalogProducts: catalogNovo,
        pagamento: 'PIX',
      );

      expect(enriched['productId'], 'produto-b');
      expect(enriched['nomeSnapshot'], _nomeB);
      expect(
        (enriched['precoUnitarioSnapshot'] as num).toDouble(),
        closeTo(precoHistorico, 0.01),
      );
      expect(
        (enriched['preco'] as num).toDouble(),
        closeTo(precoHistorico, 0.01),
      );
    });
  });

  group('Caso C — operação offline', () {
    test('enrich sem catálogo preserva snapshot selado', () {
      final line = _linhaBValida();
      final before = Map<String, dynamic>.from(line);

      final enriched = enrichCatalogCartLineSnapshot(
        line: line,
        catalogProducts: const [],
        pagamento: 'PIX',
      );

      expect(enriched['productId'], before['productId']);
      expect(enriched['nomeSnapshot'], before['nomeSnapshot']);
      expect(enriched['imagemSnapshot'] ?? '', before['imagemSnapshot'] ?? '');
      expect(enriched['tamanho'], before['tamanho']);
      expect(enriched['cor'], before['cor']);
      expect(
        (enriched['precoUnitarioSnapshot'] as num).toDouble(),
        (before['precoUnitarioSnapshot'] as num).toDouble(),
      );
    });
  });

  group('Caso D — produto inexistente no catálogo atual', () {
    test('preserva snapshot histórico sem substituir por semelhante', () {
      final line = _linhaBValida();
      line['nomeSnapshot'] = 'Nome histórico removido';

      final enriched = enrichCatalogCartLineSnapshot(
        line: line,
        catalogProducts: [_produtoA()],
        pagamento: 'PIX',
      );

      expect(enriched['productId'], 'produto-b');
      expect(enriched['nomeSnapshot'], 'Nome histórico removido');
      expect(enriched['nome'], 'Nome histórico removido');
    });
  });

  group('Caso E — variações com mesmo texto, variacaoId diferente', () {
    test('identidade usa productId + variacaoId, não só o rótulo', () {
      final a = {
        'productId': 'produto-a',
        'variacaoId': 'var-001',
        'tamanho': '45cm',
        'cor': 'sem-cor',
      };
      final b = {
        'productId': 'produto-b',
        'variacaoId': 'var-002',
        'tamanho': '45cm',
        'cor': 'sem-cor',
      };
      expect(CatalogEstoqueHelper.cartLineIdentity(a),
          isNot(CatalogEstoqueHelper.cartLineIdentity(b)));
      expect(CatalogEstoqueHelper.cartLineIdentity(a), 'produto-a|vid|var-001');
      expect(CatalogEstoqueHelper.cartLineIdentity(b), 'produto-b|vid|var-002');
    });
  });

  group('Caso F — selo sobre linha contaminada', () {
    test('selo coerente internamente não prova identidade semântica', () {
      final seal = catalogCartCommitSeal(
        productId: 'produto-b',
        nome: _nomeA,
        tamanho: 'coracao-rosa',
        cor: 'sem-cor',
        preco: _precoPix,
      );
      final contaminada = {
        'id': 'produto-b',
        'nome': _nomeA,
        'preco': _precoPix,
        'quantidade': 1,
        'tamanho': 'coracao-rosa',
        'cor': 'sem-cor',
        '_catalogCommitSeal': seal,
      };

      freezeCatalogCartLineSnapshotOnAdd(contaminada);

      expect(contaminada['productId'], 'produto-b');
      expect(contaminada['nomeSnapshot'], _nomeA);
      expect(contaminada['nomeSnapshot'], isNot(_nomeB));
      expect(
        catalogCartLineStructuralRejectionCode(contaminada),
        isNull,
        reason: 'selo/hash interno não substitui validação semântica offline',
      );
    });

    test('productIdSnapshot conflitante rejeita linha', () {
      final line = {
        'productId': 'produto-b',
        'productIdSnapshot': 'produto-a',
        'nome': _nomeB,
        'preco': _precoBase,
      };
      expect(
        catalogCartLineStructuralRejectionCode(line),
        'snapshot_product_conflict',
      );
    });
  });
}
