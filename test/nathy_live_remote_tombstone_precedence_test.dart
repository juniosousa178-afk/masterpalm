import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/produto_exclusao_tombstone_service.dart';

/// Live remote cell precedence + Nathy four-product rehydration fixtures.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const loja = 'nathy-pratas-e-folheados';

  setUp(ProdutoExclusaoTombstoneService.resetCacheForTests);
  tearDown(ProdutoExclusaoTombstoneService.resetCacheForTests);

  Produto local({
    required String id,
    required int qty,
    required int rev,
    required String op,
    Map<String, dynamic>? variacoes,
    Map<String, int> ept = const {},
  }) {
    return Produto(
      idFirebase: id,
      nome: id,
      custoReal: 0,
      frete: 0,
      gastosFixos: 0,
      gastosVariaveis: 0,
      precoSugerido: 0,
      precoFinal: 0,
      quantidade: qty,
      precoUnitario: 0,
      categoria: 'anel',
      dataEntrada: DateTime.utc(2026, 1, 1),
      lojaId: loja,
      stockRevision: rev,
      confirmedStockOperationId: op,
      variacoes: variacoes,
      estoquePorTamanho: ept,
    );
  }

  int sumVars(Map<String, dynamic>? m) {
    if (m == null) return 0;
    var s = 0;
    for (final e in m.values) {
      if (e is! Map) continue;
      for (final c in e.values) {
        if (c is num) s += c.toInt();
      }
    }
    return s;
  }

  test('four proven regressions rehydrate local totals to remote', () {
    final cases = <Map<String, dynamic>>[
      {
        'doc': 'nathy-pratas-e-folheados-anel-elos-cora-ozinho',
        'remoteQty': 5,
        'bloq': {
          ProdutoExclusaoTombstoneService.tKeySoloTamanho('19'),
          ProdutoExclusaoTombstoneService.tKeySoloTamanho('21'),
          ProdutoExclusaoTombstoneService.tKeySoloTamanho('15'),
          ProdutoExclusaoTombstoneService.vKeyCelula('15', 'sem-cor'),
        },
        'remote': {
          'quantidade': 5,
          'stockRevision': 9,
          'stockOperationId': '89315c7f-5b76-4bb5-a65e-3aa8a9c941f6',
          'variacoes': {
            '21': {'sem-cor': 2},
            '12': {'sem-cor': 2},
            '20': {'sem-cor': 0},
            '19': {'sem-cor': 1},
          },
          'estoquePorTamanho': {'19': 1, '12': 2, '21': 2},
        },
      },
      {
        'doc': 'nathy-pratas-e-folheados-anel-f',
        'remoteQty': 4,
        'bloq': {
          ProdutoExclusaoTombstoneService.tKeySoloTamanho('16'),
          ProdutoExclusaoTombstoneService.vKeyCelula('16', 'Prata'),
        },
        'remote': {
          'quantidade': 4,
          'stockRevision': 1,
          'stockOperationId': '29ddff4e-cb8e-4128-b14d-70408fbb03af',
          'variacoes': {
            '16': {'sem-cor': 1},
            '22': {'sem-cor': 1},
            '17': {'sem-cor': 1},
            '18': {'sem-cor': 1},
          },
          'estoquePorTamanho': {'18': 1, '22': 1, '17': 1, '16': 1},
        },
      },
      {
        'doc': 'nathy-pratas-e-folheados-anel-f-zirc-nias',
        'remoteQty': 5,
        'bloq': {
          ProdutoExclusaoTombstoneService.tKeySoloTamanho('23'),
          ProdutoExclusaoTombstoneService.tKeySoloTamanho('16'),
          ProdutoExclusaoTombstoneService.tKeySoloTamanho('18'),
        },
        'remote': {
          'quantidade': 5,
          'stockRevision': 1,
          'stockOperationId': '819e50b2-3676-4e2f-a846-458aa620d2a2',
          'variacoes': {
            '19': {'prata': 1},
            '17': {'prata': 1},
            '18': {'sem-cor': 1},
            '16': {'sem-cor': 1},
            '23': {'sem-cor': 1},
          },
          'estoquePorTamanho': {
            '16': 1,
            '23': 1,
            '19': 1,
            '17': 1,
            '18': 1,
          },
        },
      },
      {
        'doc': 'nathy-pratas-e-folheados-anel-solit-rio-elegante-cristal',
        'remoteQty': 2,
        'bloq': {
          ProdutoExclusaoTombstoneService.tKeySoloTamanho('14'),
          ProdutoExclusaoTombstoneService.vKeyCelula('14', 'Cristal'),
        },
        'remote': {
          'quantidade': 2,
          'stockRevision': 2,
          'stockOperationId': 'b4ed809f-7f64-4ca2-bc69-e55311c06282',
          'variacoes': {
            '18': {'Cristal': 1},
            '14': {'cristal': 1},
          },
          'estoquePorTamanho': {'14': 1, '18': 1},
        },
      },
    ];

    for (final c in cases) {
      final doc = c['doc'] as String;
      final remote = Map<String, dynamic>.from(c['remote'] as Map);
      final bloq = c['bloq'] as Set<String>;
      ProdutoExclusaoTombstoneService.debugPutVarKeysCache(
        lojaId: loja,
        estoqueDocId: doc,
        keys: bloq,
      );

      final filtered =
          ProdutoExclusaoTombstoneService.filtrarDocEstoqueParaPull(
        loja,
        doc,
        remote,
      );
      expect(
        sumVars(filtered['variacoes'] as Map<String, dynamic>?),
        c['remoteQty'],
        reason: '$doc pull must keep live cells',
      );

      // Simulate collapsed local then rehydrate path.
      final p = local(
        id: doc,
        qty: 1,
        rev: remote['stockRevision'] as int,
        op: remote['stockOperationId'] as String,
        variacoes: {'X': {'sem-cor': 1}},
        ept: {'X': 1},
      );
      p.quantidade = (filtered['quantidade'] as num).toInt();
      p.variacoes = Map<String, dynamic>.from(filtered['variacoes'] as Map);
      p.estoquePorTamanho = Map<String, int>.from(
        (filtered['estoquePorTamanho'] as Map).map(
          (k, v) => MapEntry(k.toString(), (v as num).toInt()),
        ),
      );
      ProdutoExclusaoTombstoneService.filtrarMapasLocaisDoProdutoPeloTombstone(
        loja,
        doc,
        p,
        dataRemotoCanonico: remote,
      );
      p.recalcularQuantidadeTotal();
      expect(p.quantidade, c['remoteQty'], reason: '$doc local rehydrate');
      expect(p.stockRevision, remote['stockRevision']);
      expect(p.confirmedStockOperationId, remote['stockOperationId']);
    }
  });

  test('absent remote identity is not synthesized', () {
    ProdutoExclusaoTombstoneService.debugPutVarKeysCache(
      lojaId: loja,
      estoqueDocId: 'doc',
      keys: {ProdutoExclusaoTombstoneService.tKeySoloTamanho('99')},
    );
    final remote = {
      'quantidade': 1,
      'variacoes': {
        '15': {'sem-cor': 1},
      },
      'estoquePorTamanho': {'15': 1},
    };
    final filtered =
        ProdutoExclusaoTombstoneService.filtrarDocEstoqueParaPull(
      loja,
      'doc',
      remote,
    );
    final v = filtered['variacoes'] as Map;
    expect(v.containsKey('99'), isFalse);
    expect(v['15'], isNotNull);
  });
}
