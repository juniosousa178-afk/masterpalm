// Tombstone filter denylist semantics + corruption classifier.
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/produto_exclusao_tombstone_service.dart';

const _loja = 'nathy-pratas-e-folheados';
const _doc = 'nathy-pratas-e-folheados-anel-lacinho-encanto';
const _op = '449fc83e-9a5e-4544-9bee-93348123a2dd';

Produto _p({
  required String nome,
  required int quantidade,
  required int stockRevision,
  required String confirmedStockOperationId,
  String idFirebase = _doc,
  Map<String, dynamic>? variacoes,
  Map<String, int> estoquePorTamanho = const {},
}) {
  return Produto(
    idFirebase: idFirebase,
    nome: nome,
    custoReal: 0,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 0,
    precoFinal: 0,
    quantidade: quantidade,
    precoUnitario: 0,
    categoria: 'anel',
    dataEntrada: DateTime(2026, 1, 1),
    lojaId: _loja,
    stockRevision: stockRevision,
    confirmedStockOperationId: confirmedStockOperationId,
    variacoes: variacoes,
    estoquePorTamanho: estoquePorTamanho,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ProdutoExclusaoTombstoneService.resetCacheForTests();
  });

  tearDown(() {
    ProdutoExclusaoTombstoneService.resetCacheForTests();
  });

  Map<String, dynamic> remoteLacinho() => {
        'quantidade': 1,
        'stockRevision': 9,
        'stockOperationId': _op,
        'stockKind': 'variation',
        'variacoes': {
          '15': {'sem-cor': 0},
          '22': {'sem-cor': 1},
        },
        'estoquePorTamanho': {'15': 0, '22': 1},
      };

  group('filtrarMapVariacoes denylist', () {
    test('A no tombstone retains all variations', () {
      final m = {
        '15': {'sem-cor': 1},
        '22': {'prata': 2},
      };
      final out = ProdutoExclusaoTombstoneService.filtrarMapVariacoes(
        _loja,
        _doc,
        m,
      );
      expect(out.keys, containsAll(['15', '22']));
    });

    test('B p=false unrelated V tombstone retains others', () {
      ProdutoExclusaoTombstoneService.debugPutVarKeysCache(
        lojaId: _loja,
        estoqueDocId: _doc,
        keys: {
          ProdutoExclusaoTombstoneService.vKeyCelula('99', 'ouro'),
        },
      );
      final m = {
        '15': {'sem-cor': 1},
        '22': {'sem-cor': 1},
      };
      final out = ProdutoExclusaoTombstoneService.filtrarMapVariacoes(
        _loja,
        _doc,
        m,
      );
      expect(out['15'], isNotNull);
      expect(out['22'], isNotNull);
    });

    test('C V::20|prata KEEP when remote/local cell qty > 0', () {
      ProdutoExclusaoTombstoneService.debugPutVarKeysCache(
        lojaId: _loja,
        estoqueDocId: _doc,
        keys: {
          ProdutoExclusaoTombstoneService.vKeyCelula('20', 'prata'),
        },
      );
      final m = {
        '15': {'sem-cor': 1},
        '20': {'prata': 1, 'ouro': 1},
        '22': {'sem-cor': 1},
      };
      final out = ProdutoExclusaoTombstoneService.filtrarMapVariacoes(
        _loja,
        _doc,
        m,
      );
      expect(out['15'], isNotNull);
      expect(out['22'], isNotNull);
      // Live positive cell wins over stale V tombstone.
      expect((out['20'] as Map)['prata'], 1);
      expect((out['20'] as Map)['ouro'], 1);
    });

    test('C2 V::20|prata removes only ZERO cell', () {
      ProdutoExclusaoTombstoneService.debugPutVarKeysCache(
        lojaId: _loja,
        estoqueDocId: _doc,
        keys: {
          ProdutoExclusaoTombstoneService.vKeyCelula('20', 'prata'),
        },
      );
      final m = {
        '20': {'prata': 0, 'ouro': 1},
      };
      final out = ProdutoExclusaoTombstoneService.filtrarMapVariacoes(
        _loja,
        _doc,
        m,
      );
      expect((out['20'] as Map).containsKey('prata'), isFalse);
      expect((out['20'] as Map)['ouro'], 1);
    });

    test('D T::20 KEEP when size still has positive qty', () {
      ProdutoExclusaoTombstoneService.debugPutVarKeysCache(
        lojaId: _loja,
        estoqueDocId: _doc,
        keys: {
          ProdutoExclusaoTombstoneService.tKeySoloTamanho('20'),
        },
      );
      final vars = {
        '15': {'sem-cor': 1},
        '20': {'prata': 1},
        '22': {'sem-cor': 1},
      };
      final ept = {'15': 1, '20': 1, '22': 1};
      final outV = ProdutoExclusaoTombstoneService.filtrarMapVariacoes(
        _loja,
        _doc,
        vars,
      );
      final outE = ProdutoExclusaoTombstoneService.filtrarEstoquePorTamanho(
        _loja,
        _doc,
        ept,
      );
      expect(outV.keys, containsAll(['15', '20', '22']));
      expect(outE.keys, containsAll(['15', '20', '22']));
    });

    test('D2 T::20 removes zero-only size', () {
      ProdutoExclusaoTombstoneService.debugPutVarKeysCache(
        lojaId: _loja,
        estoqueDocId: _doc,
        keys: {
          ProdutoExclusaoTombstoneService.tKeySoloTamanho('20'),
        },
      );
      final vars = {
        '15': {'sem-cor': 1},
        '20': {'prata': 0},
        '22': {'sem-cor': 1},
      };
      final ept = {'15': 1, '20': 0, '22': 1};
      final outV = ProdutoExclusaoTombstoneService.filtrarMapVariacoes(
        _loja,
        _doc,
        vars,
      );
      final outE = ProdutoExclusaoTombstoneService.filtrarEstoquePorTamanho(
        _loja,
        _doc,
        ept,
      );
      expect(outV.keys, containsAll(['15', '22']));
      expect(outV.containsKey('20'), isFalse);
      expect(outE.keys, containsAll(['15', '22']));
      expect(outE.containsKey('20'), isFalse);
    });

    test('E Lacinho fixture: tombstone 20 preserves 15/22', () {
      ProdutoExclusaoTombstoneService.debugPutVarKeysCache(
        lojaId: _loja,
        estoqueDocId: _doc,
        keys: {
          ProdutoExclusaoTombstoneService.tKeySoloTamanho('20'),
          ProdutoExclusaoTombstoneService.vKeyCelula('20', 'prata'),
        },
      );
      final remote = remoteLacinho();
      final filtered =
          ProdutoExclusaoTombstoneService.filtrarDocEstoqueParaPull(
        _loja,
        _doc,
        remote,
      );
      final v = filtered['variacoes'] as Map;
      expect(v['15'], isNotNull);
      expect(v['22'], isNotNull);
      expect(v.containsKey('20'), isFalse);
      expect((filtered['estoquePorTamanho'] as Map).keys, containsAll(['15', '22']));
    });

    test('H product tombstone p=true clears maps', () {
      ProdutoExclusaoTombstoneService.debugPutVarKeysCache(
        lojaId: _loja,
        estoqueDocId: _doc,
        keys: const {},
        produtoCheio: true,
      );
      final out = ProdutoExclusaoTombstoneService.filtrarMapVariacoes(
        _loja,
        _doc,
        {
          '15': {'sem-cor': 1},
        },
      );
      expect(out, isEmpty);
    });

    test('I zero cells retained when not tombstoned', () {
      ProdutoExclusaoTombstoneService.debugPutVarKeysCache(
        lojaId: _loja,
        estoqueDocId: _doc,
        keys: {
          ProdutoExclusaoTombstoneService.tKeySoloTamanho('20'),
        },
      );
      final out = ProdutoExclusaoTombstoneService.filtrarMapVariacoes(
        _loja,
        _doc,
        {
          '15': {'sem-cor': 0},
          '22': {'sem-cor': 0},
        },
      );
      expect((out['15'] as Map)['sem-cor'], 0);
      expect((out['22'] as Map)['sem-cor'], 0);
    });

    test('J V::15|sem-cor KEEP positive; remove zero', () {
      ProdutoExclusaoTombstoneService.debugPutVarKeysCache(
        lojaId: _loja,
        estoqueDocId: _doc,
        keys: {
          ProdutoExclusaoTombstoneService.vKeyCelula('15', 'sem-cor'),
        },
      );
      final positive = ProdutoExclusaoTombstoneService.filtrarMapVariacoes(
        _loja,
        _doc,
        {
          '15': {'sem-cor': 2},
          '22': {'sem-cor': 1},
        },
      );
      expect(positive.containsKey('15'), isTrue);
      expect(positive['22'], isNotNull);

      final zeroed = ProdutoExclusaoTombstoneService.filtrarMapVariacoes(
        _loja,
        _doc,
        {
          '15': {'sem-cor': 0},
          '22': {'sem-cor': 1},
        },
      );
      expect(zeroed.containsKey('15'), isFalse);
      expect(zeroed['22'], isNotNull);
    });
  });

  group('broken allowlist + corruption classifier', () {
    test('F old broken projection empties Lacinho remote', () {
      final bloq = {
        ProdutoExclusaoTombstoneService.tKeySoloTamanho('20'),
        ProdutoExclusaoTombstoneService.vKeyCelula('20', 'prata'),
      };
      final remote = remoteLacinho();
      final broken =
          ProdutoExclusaoTombstoneService.filtrarMapVariacoesBrokenAllowlist(
        Map<String, dynamic>.from(remote['variacoes'] as Map),
        bloq,
      );
      expect(broken, isEmpty);
    });

    test('F/G classifier: Lacinho collapse is corruption; untracked is not',
        () {
      ProdutoExclusaoTombstoneService.debugPutVarKeysCache(
        lojaId: _loja,
        estoqueDocId: _doc,
        keys: {
          ProdutoExclusaoTombstoneService.tKeySoloTamanho('20'),
          ProdutoExclusaoTombstoneService.vKeyCelula('20', 'prata'),
        },
      );
      final remote = remoteLacinho();
      final corrupted = _p(
        nome: 'Anel Lacinho Encanto',
        quantidade: 1,
        stockRevision: 9,
        confirmedStockOperationId: _op,
      );
      expect(
        ProdutoExclusaoTombstoneService.isTombstoneFilterProjectionCorruption(
          lojaId: _loja,
          estoqueDocId: _doc,
          local: corrupted,
          remoteUnfiltered: remote,
        ),
        isTrue,
      );

      // Genuine untracked: same rev/op but local structure is NOT broken projection
      // (still has remote-like grade with different qty).
      final untracked = _p(
        nome: 'Colar Veneziana Cruz 50cm',
        quantidade: 1,
        stockRevision: 9,
        confirmedStockOperationId: _op,
        variacoes: {
          '15': {'sem-cor': 0},
          '22': {'sem-cor': 1},
        },
        estoquePorTamanho: {'15': 0, '22': 1},
      );
      // bloq present but local already matches corrected filter → not corruption
      expect(
        ProdutoExclusaoTombstoneService.isTombstoneFilterProjectionCorruption(
          lojaId: _loja,
          estoqueDocId: _doc,
          local: untracked,
          remoteUnfiltered: remote,
        ),
        isFalse,
      );
    });

    test('G genuine local untracked without tombstone keys not classified', () {
      final remote = {
        'quantidade': 0,
        'stockRevision': 3,
        'stockOperationId': _op,
        'variacoes': {
          'U': {'prata': 0},
        },
        'estoquePorTamanho': {'U': 0},
      };
      final local = _p(
        idFirebase: 'colar',
        nome: 'Colar',
        quantidade: 1,
        stockRevision: 3,
        confirmedStockOperationId: _op,
      );
      expect(
        ProdutoExclusaoTombstoneService.isTombstoneFilterProjectionCorruption(
          lojaId: _loja,
          estoqueDocId: 'colar',
          local: local,
          remoteUnfiltered: remote,
        ),
        isFalse,
      );
    });
  });
}
