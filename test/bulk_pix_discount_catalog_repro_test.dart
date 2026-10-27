import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/catalog/data/firestore_catalog_impl.dart';
import 'package:master_palm/services/bulk_editorial_service.dart';
import 'package:master_palm/services/catalog_pre_pedido_compute.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';

import 'support/bulk_editorial_fixture.dart';

// Repro: "Definir desconto no Pix em lote" (EstoqueScreen._descontoPixLote) vs save individual.
const _loja = BulkEditorialFixture.lojaId;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BulkEditorialFixture f;

  setUp(() async {
    f = await BulkEditorialFixture.create(ids: ['p1', 'p2']);
  });
  tearDown(() => f.dispose());

  List<BulkEditorialCandidato> candidatos(List<String> ids) => [
        for (final id in ids) BulkEditorialCandidato.fromProduto(f.keys[id]!, f.box.get(f.keys[id])!),
      ];

  Future<BulkEditorialResultado> bulk(BulkEditorialPlano plano, List<String> ids) async {
    final cs = candidatos(ids);
    final r = await BulkEditorialService.executar(
      plano: plano,
      lojaId: _loja,
      bulkId: 'edbulk_repro',
      candidatos: cs,
    );
    await BulkEditorialService.aplicarNoHive(
      box: f.box,
      plano: plano,
      candidatos: cs,
      docIdsConfirmados: r.confirmados,
    );
    return r;
  }

  Future<Map<String, dynamic>> catalogo(String id) async {
    final produtos = await FirestoreCatalogProductSource(db: f.db).getProducts(_loja);
    return produtos.singleWhere((p) => p['id'] == id);
  }

  double precoPixCheckout(Map<String, dynamic> produto) => computeCatalogPrePedidoMoneySnapshot(
        items: [
          {...produto, 'productId': produto['id'], 'quantidade': 1}
        ],
        entrega: const {},
        pagamento: 'PIX',
      ).itensList.single['precoUnitario'] as double;

  test('lote de 10%: Hive, estoque, draft e live = 10 e o catálogo mostra o preço Pix', () async {
    final r = await bulk(BulkEditorialPlano.descontoPix(10), ['p1']);
    expect(r.confirmados, {'p1'});
    expect(r.sucessoTotal, isTrue);

    expect(f.box.get(f.keys['p1'])!.percentualDescontoPix, 10);
    for (final col in ['estoque_produtos', 'draft_produtos', 'produtos']) {
      expect((await f.doc(col, 'p1'))!['percentualDescontoPix'], 10, reason: col);
    }
    final produto = await catalogo('p1');
    expect(produto['percentualDescontoPix'], 10);
    expect(produto['preco'], 100.0);
    expect(precoPixCheckout(produto), closeTo(90, 1e-9));

    final cmd = f.commands.single;
    expect(cmd['name'], 'stockCatalogCommand');
    expect(cmd['kind'], 'editorial');
    expect(cmd['items'], [
      {'productId': 'p1'}
    ]);
    expect(cmd['editorial'], {'percentualDescontoPix': 10.0}, reason: 'só o Pix viaja no patch');
    expect(cmd.containsKey('definition'), isFalse, reason: 'editorial não mexe em estoque');

    // O produto não selecionado fica intacto.
    expect((await f.doc('produtos', 'p2'))!['percentualDescontoPix'], 0.0);
    expect(f.box.get(f.keys['p2'])!.percentualDescontoPix, 0);
  });

  test('lote preserva estoque, revisão, custo, preço, categorias, EAN, fotos e publicação', () async {
    final antes = {
      for (final col in ['estoque_produtos', 'draft_produtos', 'produtos']) col: await f.doc(col, 'p1'),
    };
    final hiveAntes = f.box.get(f.keys['p1'])!;
    final quantidade = hiveAntes.quantidade;
    final revisao = hiveAntes.stockRevision;
    await bulk(BulkEditorialPlano.descontoPix(10), ['p1']);
    for (final col in antes.keys) {
      final depois = Map<String, dynamic>.from((await f.doc(col, 'p1'))!)..remove('percentualDescontoPix');
      final esperado = Map<String, dynamic>.from(antes[col]!)..remove('percentualDescontoPix');
      expect(depois, esperado, reason: col);
    }
    final hive = f.box.get(f.keys['p1'])!;
    expect(hive.quantidade, quantidade);
    expect(hive.stockRevision, revisao);
    expect(hive.custoReal, 40);
    expect(hive.precoFinal, 100);
    expect(hive.updatedAt, BulkEditorialFixture.t0, reason: 'sem bump que dispare o auto-sync completo');
  });

  test('guard do push continua a saltar mudança só de Pix (guard não foi relaxado)', () async {
    final p = f.box.get(f.keys['p1'])!..percentualDescontoPix = 10;
    expect(
      ProdutosFirestoreService.shouldSkipStaleProdutoPushOnAutoSync(
        local: p,
        existingData: await f.doc('estoque_produtos', 'p1'),
        bumpHiveTimestamp: true,
        updatedAtBeforeBump: DateTime(2026, 10, 27),
      ),
      isTrue,
    );
  });

  test('caminho antigo (Hive + syncProdutosPorChavesHive) segue sem chegar ao servidor', () async {
    final p = f.box.get(f.keys['p1'])!;
    p.percentualDescontoPix = 10;
    await p.save();
    await ProdutosFirestoreService.syncProdutosPorChavesHive(box: f.box, lojaId: _loja, hiveKeys: [f.keys['p1']!]);
    expect(f.commands, isEmpty, reason: 'por isso o lote deixou de usar este caminho');
    expect((await f.doc('produtos', 'p1'))!['percentualDescontoPix'], 0.0);
  });

  test('individual e lote produzem o mesmo percentualDescontoPix em estoque, draft e live', () async {
    final p1 = f.box.get(f.keys['p1'])!;
    p1.percentualDescontoPix = 10;
    await p1.save();
    final status = await ProdutosFirestoreService.syncProdutoComStatus(
      p1,
      lojaId: _loja,
      bumpHiveTimestamp: true,
      forcePushFromCadastro: true,
      enqueueOnFailure: false,
    );
    expect(status, ProdutoSyncRemotoStatus.confirmado);
    expect(f.commands.single['kind'], 'editorial');

    await bulk(BulkEditorialPlano.descontoPix(10), ['p2']);
    for (final col in ['estoque_produtos', 'draft_produtos', 'produtos']) {
      final individual = (await f.doc(col, 'p1'))!['percentualDescontoPix'];
      final lote = (await f.doc(col, 'p2'))!['percentualDescontoPix'];
      expect(individual, 10, reason: col);
      expect(lote, individual, reason: col);
    }
    expect(f.box.get(f.keys['p2'])!.percentualDescontoPix, f.box.get(f.keys['p1'])!.percentualDescontoPix);
    expect(precoPixCheckout(await catalogo('p2')), precoPixCheckout(await catalogo('p1')));
  });

  test('promoção + Pix em lote: Pix aplica sobre o preço promocional exibido', () async {
    await bulk(BulkEditorialPlano.ativarPromocao(percentual: 20), ['p1']);
    await bulk(BulkEditorialPlano.descontoPix(10), ['p1']);
    final live = (await f.doc('produtos', 'p1'))!;
    expect(live['emPromocao'], isTrue);
    expect(live['percentualPromo'], 20);
    expect(live['percentualDescontoPix'], 10);
    final produto = await catalogo('p1');
    expect(produto['preco'], closeTo(80, 1e-9), reason: 'preço exibido = promocional');
    expect(produto['precoFinal'], 100.0, reason: 'preço normal intacto');
    expect(precoPixCheckout(produto), closeTo(72, 1e-9), reason: '100 × 0,8 × 0,9');
    final hive = f.box.get(f.keys['p1'])!;
    expect(hive.emPromocao, isTrue);
    expect(hive.percentualDescontoPix, 10);
  });
}
