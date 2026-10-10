// P0 Nathy — letras (3º nível de variação) não podem sumir na hidratação.
// Grade A=1 B=2 C=0 D=1, qty agregada 4. Sem Firestore real.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/produto_effective_stock.dart';
import 'package:master_palm/core/produto_pending_stock_reconciliation.dart';
import 'package:master_palm/core/produto_variacao_extra.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:master_palm/services/venda_estoque_remoto_prep_service.dart';
import 'package:master_palm/services/venda_produto_stock_hydrate_service.dart';

const _loja = 'loja-letras';
const _tam = '45cm';
const _cor = 'sem-cor';

Map<String, dynamic> _remote({
  Map<String, int> letras = const {'A': 1, 'B': 2, 'C': 0, 'D': 1},
  int rev = 3,
  bool withStockKind = true,
  String tam = _tam,
}) {
  final qty = letras.values.fold<int>(0, (a, b) => a + b);
  return {
    'quantidade': qty,
    if (withStockKind) 'stockKind': 'variation',
    'stockRevision': rev,
    'stockOperationId': 'op-$rev',
    'tamanhos': [tam],
    'cores': <String>[],
    'estoquePorTamanho': {tam: qty},
    'variacoes': {
      tam: {_cor: Map<String, int>.from(letras)},
    },
    'variacoesExtraTipo': {
      tam: {
        _cor: {for (final k in letras.keys) k: 'letra'},
      },
    },
  };
}

Produto _local({
  required int qty,
  Map<String, dynamic>? variacoes,
  String? pending,
  int rev = 3,
}) =>
    Produto(
      nome: 'Colar Letrinha',
      custoReal: 0,
      frete: 0,
      gastosFixos: 0,
      gastosVariaveis: 0,
      precoSugerido: 0,
      precoFinal: 49.9,
      quantidade: qty,
      precoUnitario: 49.9,
      categoria: 'Colar',
      dataEntrada: DateTime(2026, 1, 1),
      codigoBarras: '',
      idFirebase: 'colar-letrinha',
      lojaId: _loja,
      stockRevision: rev,
      pendingStockOperationId: pending,
      pendingStockBaseRevision: pending == null ? null : rev,
      tamanhos: variacoes == null ? const [] : const [_tam],
      estoquePorTamanho: variacoes == null ? {} : {_tam: qty},
      variacoes: variacoes,
    );

Map<String, dynamic> _deep(Map<String, dynamic> m) =>
    ProdutosFirestoreService.parseVariacoesFromFirestore(m)!;

List<String> _letrasVendaveis(Produto p, {String tam = _tam}) =>
    ProdutoVariacaoExtra.opcoesExtraPara(p.variacoes, tam, _cor);

Map<String, int> _celula(Produto p, {String tam = _tam}) {
  final cell = (p.variacoes?[tam] as Map?)?[_cor];
  expect(cell, isA<Map>(), reason: 'letras achatadas em int: $cell');
  return {
    for (final e in (cell as Map).entries)
      e.key.toString(): ProdutoVariacaoExtra.valorFirestoreComoInt(e.value),
  };
}

Future<SaleVariationRouteResult> _route(
  Produto p,
  Map<String, dynamic>? Function() remote,
) {
  VendaProdutoStockHydrateService.debugRemoteReader =
      (l, d) async => remote();
  return VendaProdutoStockHydrateService.resolveSaleVariationRoute(
    lojaId: _loja,
    produto: p,
  );
}

void _expectGradeABCD(Produto p, {Map<String, int>? letras}) {
  final esperado = letras ?? const {'A': 1, 'B': 2, 'C': 0, 'D': 1};
  expect(_celula(p), esperado);
  final soma = esperado.values.fold<int>(0, (a, b) => a + b);
  expect(p.quantidade, soma, reason: 'AGGREGATE_EQUALS_VARIATION_SUM');
  expect(
    _letrasVendaveis(p),
    esperado.entries.where((e) => e.value > 0).map((e) => e.key).toList(),
    reason: 'ZERO_QTY_VARIATION_POLICY: letra 0 oculta no picker',
  );
}

void main() {
  tearDown(VendaProdutoStockHydrateService.resetForTests);

  group('CANONICAL_VARIATION_HYDRATION_WINS — letras preservadas', () {
    test('cold open: Hive sem grade + remoto ok → picker com A,B,D', () async {
      final p = _local(qty: 4);
      final r = await _route(p, () => _remote());
      expect(r.decision, SaleVariationRouteDecision.openVariationPicker);
      _expectGradeABCD(r.produto);
      expect(r.produto.variacoesExtraTipo?[_tam]?[_cor]?['A'], 'letra');
    });

    test('warm cache: Hive com letras + remoto ok → letras não achatam',
        () async {
      final p = _local(qty: 4, variacoes: _deep(_remote()['variacoes']));
      final r = await _route(p, () => _remote());
      expect(r.decision, SaleVariationRouteDecision.openVariationPicker);
      _expectGradeABCD(r.produto);
    });

    test('pending local: só estrutura, letras preservadas, qty local mantida',
        () async {
      final p = _local(qty: 4, pending: 'op-local');
      final r = await _route(p, () => _remote());
      expect(r.decision, SaleVariationRouteDecision.openVariationPicker);
      expect(_celula(r.produto), {'A': 1, 'B': 2, 'C': 0, 'D': 1});
      expect(r.produto.pendingStockOperationId, 'op-local');
    });

    test('edição do produto: remoto novo (A=3) vence o Hive antigo', () async {
      final p = _local(qty: 4, variacoes: _deep(_remote()['variacoes']));
      const novo = {'A': 3, 'B': 2, 'C': 0, 'D': 1};
      final r = await _route(p, () => _remote(letras: novo, rev: 4));
      _expectGradeABCD(r.produto, letras: novo);
      expect(r.produto.stockRevision, 4);
    });

    test('venda concluída: débito de B e re-hidratação mantêm A,B,D', () async {
      final p = _local(qty: 4, variacoes: _deep(_remote()['variacoes']));
      p.debitarEstoqueVariacao(_tam, '', 1, 'B');
      expect(_celula(p), {'A': 1, 'B': 1, 'C': 0, 'D': 1});
      expect(p.quantidade, 3);
      const pos = {'A': 1, 'B': 1, 'C': 0, 'D': 1};
      final r = await _route(p, () => _remote(letras: pos, rev: 4));
      _expectGradeABCD(r.produto, letras: pos);
    });

    test('projeção do catálogo / pull: applyAuthoritative mantém letras', () {
      final p = _local(qty: 4);
      expect(
        applyAuthoritativeRemoteStockToProduto(p, remote: _remote()),
        isTrue,
      );
      _expectGradeABCD(p);
    });

    test('reabrir tela: duas rotas seguidas no mesmo produto', () async {
      final p = _local(qty: 4);
      await _route(p, () => _remote());
      final r2 = await _route(p, () => _remote());
      expect(r2.decision, SaleVariationRouteDecision.openVariationPicker);
      _expectGradeABCD(r2.produto);
    });

    test('restore de sessão: instância nova a partir do mapa persistido',
        () async {
      final antes = _local(qty: 4);
      await _route(antes, () => _remote());
      final restaurado = _local(
        qty: antes.quantidade,
        variacoes: _deep(Map<String, dynamic>.from(antes.variacoes!)),
      );
      _expectGradeABCD(restaurado);
      final r = await _route(restaurado, () => _remote());
      _expectGradeABCD(r.produto);
    });

    test('soma divergente no remoto: não inventa letras (fica int canônico)',
        () {
      final remote = _remote();
      remote['estoquePorTamanho'] = {_tam: 9};
      final p = _local(qty: 4);
      applyAuthoritativeRemoteStockToProduto(p, remote: remote);
      final cell = (p.variacoes?[_tam] as Map?)?[_cor];
      if (cell is Map) {
        expect(ProdutoVariacaoExtra.somarCelula(cell), 4);
      } else {
        expect(cell, isA<int>());
      }
    });

    test('só letras (sem tamanho/cor) e sem stockKind → abre picker', () async {
      final remote = _remote(withStockKind: false, tam: 'sem-tamanho');
      final p = _local(qty: 4);
      final r = await _route(p, () => remote);
      expect(r.decision, SaleVariationRouteDecision.openVariationPicker);
      expect(_letrasVendaveis(r.produto, tam: 'sem-tamanho'), ['A', 'B', 'D']);
    });
  });

  group('preparação da venda e reconciliação de pending', () {
    tearDown(() => ProdutosFirestoreService.debugFirestoreOverride = null);

    test('prep de venda: refresh autoritativo antes da baixa mantém letras',
        () async {
      final fs = FakeFirebaseFirestore();
      ProdutosFirestoreService.debugFirestoreOverride = fs;
      await fs
          .collection('lojas')
          .doc(_loja)
          .collection(FSPaths.estoqueProdutosCol)
          .doc('colar-letrinha')
          .set(_remote());
      final p = _local(qty: 4);
      await VendaEstoqueRemotoPrepService.refreshAuthoritativeStockCacheForSale(
        lojaId: _loja,
        produto: p,
      );
      _expectGradeABCD(p);
    });

    test('prep de venda: pending real não é mascarado pelo refresh', () async {
      final fs = FakeFirebaseFirestore();
      ProdutosFirestoreService.debugFirestoreOverride = fs;
      await fs
          .collection('lojas')
          .doc(_loja)
          .collection(FSPaths.estoqueProdutosCol)
          .doc('colar-letrinha')
          .set(_remote(letras: const {'A': 9, 'B': 9, 'C': 9, 'D': 9}));
      final local = _deep(_remote()['variacoes']);
      final p = _local(qty: 4, variacoes: local, pending: 'op-local');
      await VendaEstoqueRemotoPrepService.refreshAuthoritativeStockCacheForSale(
        lojaId: _loja,
        produto: p,
      );
      expect(_celula(p), {'A': 1, 'B': 2, 'C': 0, 'D': 1});
      expect(p.quantidade, 4);
    });

    test('pending genérico (sem letras) vs remoto com letras avançado → nunca flush',
        () {
      final p = _local(qty: 4, pending: 'op-local');
      final d = classifyPendingAgainstRemote(
        local: p,
        remote: _remote(rev: 4),
      );
      expect(
        d.classification,
        PendingStockReconcileClass.supersededPendingRemoteAdvanced,
      );
      expect(d.classification.mustNeverFlush, isTrue);
      expect(applyAuthoritativeRemoteStockToProduto(p, remote: _remote(rev: 4)),
          isFalse,
          reason: 'pending local não é mascarado antes da limpeza');
      expect(d.classification.mayClearLocalPendingOnly, isTrue);
      p.pendingStockOperationId = null;
      p.pendingStockBaseRevision = null;
      expect(applyAuthoritativeRemoteStockToProduto(p, remote: _remote(rev: 4)),
          isTrue);
      _expectGradeABCD(p);
    });

    test('pending com letras já confirmado no remoto → limpa só local', () {
      final p = _local(
        qty: 4,
        variacoes: _deep(_remote()['variacoes']),
        pending: 'op-4',
      );
      final d = classifyPendingAgainstRemote(
        local: p,
        remote: _remote(rev: 4),
      );
      expect(
        d.classification,
        PendingStockReconcileClass.staleConfirmedEquivalent,
      );
      expect(d.classification.mayClearLocalPendingOnly, isTrue);
      expect(_celula(p), {'A': 1, 'B': 2, 'C': 0, 'D': 1});
    });

    test('remoto ilegível na reconciliação → ambíguo, letras locais intactas',
        () {
      final p = _local(
        qty: 4,
        variacoes: _deep(_remote()['variacoes']),
        pending: 'op-local',
      );
      final d = classifyPendingAgainstRemote(local: p, remote: null);
      expect(d.classification, PendingStockReconcileClass.ambiguousPending);
      expect(d.classification.mayClearLocalPendingOnly, isFalse);
      expect(_celula(p), {'A': 1, 'B': 2, 'C': 0, 'D': 1});
    });
  });

  group('SALE_VARIATIONS_USE_CANONICAL_STOCK — fail closed', () {
    test('leitura remota falha + Hive sem grade → failClosed (não simple)',
        () async {
      final p = _local(qty: 4);
      VendaProdutoStockHydrateService.debugRemoteReader =
          (l, d) async => throw Exception('unavailable');
      final r = await VendaProdutoStockHydrateService.resolveSaleVariationRoute(
        lojaId: _loja,
        produto: p,
      );
      expect(r.decision, SaleVariationRouteDecision.failClosed);
      expect(r.canonicalUnavailable, isTrue);
      expect(p.quantidade, 4);
      expect(p.variacoes, isNull, reason: 'NO_SYNTHETIC_VARIATION_REPAIR');
    });

    test('leitura remota falha + Hive com letras → failClosed', () async {
      final p = _local(qty: 4, variacoes: _deep(_remote()['variacoes']));
      VendaProdutoStockHydrateService.debugRemoteReader =
          (l, d) async => throw Exception('unavailable');
      final r = await VendaProdutoStockHydrateService.resolveSaleVariationRoute(
        lojaId: _loja,
        produto: p,
      );
      expect(r.decision, SaleVariationRouteDecision.failClosed);
      expect(r.canonicalUnavailable, isTrue);
      expect(_celula(p), {'A': 1, 'B': 2, 'C': 0, 'D': 1});
    });

    test('todas as letras zeradas → failClosed sem redistribuir agregado',
        () async {
      const zero = {'A': 0, 'B': 0, 'C': 0, 'D': 0};
      final p = _local(qty: 4);
      final r = await _route(p, () => _remote(letras: zero));
      expect(r.decision, SaleVariationRouteDecision.failClosed);
      expect(r.canonicalUnavailable, isFalse);
    });
  });
}
