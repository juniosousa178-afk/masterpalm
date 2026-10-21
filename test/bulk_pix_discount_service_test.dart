import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/screens/public_catalog/checkout_total_helper.dart';
import 'package:master_palm/services/bulk_pix_discount_service.dart';
import 'package:master_palm/services/produto_remote_sync_guard.dart';
import 'package:master_palm/services/stock_catalog_backend_service.dart';

BulkPixCandidato c(String id, double pix, {int key = 0, String nome = ''}) =>
    BulkPixCandidato(
        hiveKey: key, docId: id, nome: nome.isEmpty ? id : nome, percentualDescontoPix: pix);

Produto produto(String id, double pix, {double preco = 100}) => Produto(
      nome: id,
      custoReal: 40,
      frete: 0,
      gastosFixos: 0,
      gastosVariaveis: 0,
      precoSugerido: preco,
      precoFinal: preco,
      quantidade: 3,
      precoUnitario: preco,
      categoria: 'Religiosos',
      dataEntrada: DateTime(2026, 1, 1),
      idFirebase: id,
      emPromocao: true,
      percentualPromo: 20,
      percentualDescontoPix: pix,
    );

/// In-memory stand-in for the server: same counting rules, records every payload.
class FakeServer {
  FakeServer(this.pix);
  final Map<String, double> pix;
  final payloads = <Map<String, dynamic>>[];
  final applied = <String, Map<String, dynamic>>{};
  Object? Function(Map<String, dynamic> payload, int call)? fail;

  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> data) async {
    expect(name, 'stockCatalogCommand');
    payloads.add(data);
    final injected = fail?.call(data, payloads.length);
    if (injected != null) throw injected;
    final op = data['operationId'] as String;
    if (applied.containsKey(op)) return {...applied[op]!, 'alreadyApplied': true};
    final ids = (data['productIds'] as List).cast<String>();
    for (final id in ids) {
      if (!pix.containsKey(id)) {
        throw FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'Product unavailable',
          details: {'code': 'BULK_PIX_PRODUCT_UNAVAILABLE', 'reason': 'NOT_FOUND', 'productId': id},
        );
      }
    }
    final updated = ids.where((id) => pix[id]! > 0).toList()..sort();
    final noop = ids.where((id) => pix[id]! <= 0).toList()..sort();
    for (final id in updated) {
      pix[id] = 0;
    }
    final result = {
      'alreadyApplied': false,
      'operationId': op,
      'updatedProductIds': updated,
      'noopProductIds': noop,
      'updatedCount': updated.length,
      'noopCount': noop.length,
      'failedCount': 0,
    };
    applied[op] = result;
    return result;
  }
}

void main() {
  tearDown(() => StockCatalogBackendService.debugTransport = null);

  group('preview (§4)', () {
    test('fixture A/B/C: 2 com desconto, 1 sem', () {
      final p = BulkPixPreview.calcular([c('A', 10), c('B', 5), c('C', 0)]);
      expect(p.titulo, 'Remover desconto no Pix de 3 produtos?');
      expect(p.selecionados, 3);
      expect(p.comDescontoPix, 2);
      expect(p.semDescontoPix, 1);
      expect(p.docIds, ['A', 'B', 'C']);
      expect(p.podeExecutar, isTrue);
    });

    test('20 selecionados: mensagem exata do contrato', () {
      final list = [
        for (var i = 0; i < 16; i++) c('com$i', 10),
        for (var i = 0; i < 4; i++) c('sem$i', 0),
      ];
      final p = BulkPixPreview.calcular(list);
      expect(p.titulo, 'Remover desconto no Pix de 20 produtos?');
      expect(p.linhas, contains('16 produtos terão o desconto no Pix removido.'));
      expect(p.linhas, contains('4 já estão sem desconto e não serão alterados.'));
      expect(p.linhas.last, contains('preço normal'));
    });

    test('não sincronizados ficam fora do envio e são avisados; fora do filtro é explícito', () {
      final p = BulkPixPreview.calcular([c('A', 10), c('', 10), c('A', 10)], foraDoFiltro: 2);
      expect(p.selecionados, 3);
      expect(p.naoSincronizados, 1);
      expect(p.docIds, ['A'], reason: 'dedup + unsynced excluded');
      expect(p.linhas.any((l) => l.contains('não foi sincronizado')), isTrue);
      expect(p.linhas.any((l) => l.contains('2 produtos selecionados não aparecem no filtro atual')), isTrue);
    });

    test('nada sincronizado: ação desabilitada', () {
      expect(BulkPixPreview.calcular([c('', 10)]).podeExecutar, isFalse);
    });

    test('singular', () {
      final p = BulkPixPreview.calcular([c('A', 10)]);
      expect(p.titulo, 'Remover desconto no Pix de 1 produto?');
      expect(p.linhas.first, '1 produto terá o desconto no Pix removido.');
    });
  });

  group('lotes e operationId (§8, §9)', () {
    test('seleção acima do limite é dividida sem truncar', () {
      final ids = [for (var i = 0; i < 65; i++) 'p${i.toString().padLeft(3, '0')}'];
      final batches = BulkPixDiscountService.lotes(ids.reversed);
      expect(batches.map((b) => b.length), [30, 30, 5]);
      expect(batches.expand((b) => b).toList(), ids);
      expect(kMaxProdutosPorOperacaoPix, 30);
    });

    test('operationId determinístico, independente da ordem, no namespace do servidor', () {
      final a = BulkPixDiscountService.operationId(lojaId: 'l', bulkId: 'b', productIds: ['x', 'y']);
      final b = BulkPixDiscountService.operationId(lojaId: 'l', bulkId: 'b', productIds: ['y', 'x']);
      final other = BulkPixDiscountService.operationId(lojaId: 'l', bulkId: 'b2', productIds: ['x', 'y']);
      expect(a, b);
      expect(a, isNot(other));
      expect(RegExp(r'^pixrm_[A-Za-z0-9_-]{8,120}$').hasMatch(a), isTrue);
    });
  });

  group('execução (§6, §19)', () {
    test('fixture A/B/C: UPDATED=2 NOOP=1, payload só com IDs', () async {
      final server = FakeServer({'A': 10, 'B': 5, 'C': 0});
      StockCatalogBackendService.debugTransport = server.call;
      final progress = <String>[];
      final r = await BulkPixDiscountService.executar(
        lojaId: 'loja1',
        docIds: ['A', 'B', 'C'],
        bulkId: 'pixbulk_t1',
        onProgresso: (d, t) => progress.add('$d/$t'),
      );
      expect(r.atualizados, {'A', 'B'});
      expect(r.semAlteracao, {'C'});
      expect(r.sucessoTotal, isTrue);
      expect(r.titulo, 'Desconto no Pix removido');
      expect(r.linhas, ['2 produtos atualizados', '1 já estava sem desconto', '0 falhas']);
      expect(progress, ['0/3', '3/3']);
      final payload = server.payloads.single;
      expect(payload.keys.toSet().difference({'clientBuild'}),
          {'protocolVersion', 'lojaId', 'operationId', 'kind', 'productIds', 'bulkId'});
      expect(payload['kind'], 'removePixDiscount');
      expect(payload.toString(), isNot(contains('percentualDescontoPix')));
      expect(payload.toString(), isNot(contains('preco')));
    });

    test('muitos produtos: um operationId por lote, progresso por lote', () async {
      final pix = {for (var i = 0; i < 61; i++) 'p${i.toString().padLeft(2, '0')}': i.isEven ? 10.0 : 0.0};
      final server = FakeServer(pix);
      StockCatalogBackendService.debugTransport = server.call;
      final progress = <int>[];
      final r = await BulkPixDiscountService.executar(
        lojaId: 'loja1', docIds: pix.keys.toList(), bulkId: 'pixbulk_t2', onProgresso: (d, _) => progress.add(d));
      expect(server.payloads.length, 3);
      expect(server.payloads.map((p) => p['operationId']).toSet().length, 3);
      expect(progress, [0, 30, 60, 61]);
      expect(r.atualizados.length, 31);
      expect(r.semAlteracao.length, 30);
    });

    test('lote rejeitado: contagem exata, sem sucesso falso, nova tentativa sem o produto indisponível', () async {
      final pix = {for (var i = 0; i < 35; i++) 'p${i.toString().padLeft(2, '0')}': 10.0};
      pix.remove('p05');
      final server = FakeServer(pix);
      StockCatalogBackendService.debugTransport = server.call;
      final ids = [for (var i = 0; i < 35; i++) 'p${i.toString().padLeft(2, '0')}'];
      final r = await BulkPixDiscountService.executar(
          lojaId: 'loja1', docIds: ids, bulkId: 'pixbulk_t3', nomes: {'p05': 'Colar Cruz'});
      expect(r.sucessoTotal, isFalse);
      expect(r.atualizados.length, 5, reason: 'second batch applied');
      expect(r.produtosComFalha, 30);
      expect(r.titulo, 'Desconto no Pix removido em parte');
      expect(r.linhas.last, '30 falhas');
      expect(r.falhas.single.mensagem, contains('"Colar Cruz" não foi encontrado'));
      expect(r.falhas.single.mensagem, contains('Nenhum produto deste lote foi alterado'));
      expect(r.idsParaNovaTentativa.length, 29);
      expect(r.idsParaNovaTentativa, isNot(contains('p05')));

      final retry = await BulkPixDiscountService.executar(
          lojaId: 'loja1', docIds: r.idsParaNovaTentativa, bulkId: 'pixbulk_t3');
      expect(retry.sucessoTotal, isTrue);
      expect(retry.atualizados.length, 29);
    });

    test('falha de rede: repetição usa o mesmo operationId (replay seguro)', () async {
      final server = FakeServer({'A': 10});
      server.fail = (payload, call) => call == 1
          ? FirebaseFunctionsException(code: 'unavailable', message: 'network')
          : null;
      StockCatalogBackendService.debugTransport = server.call;
      final r = await BulkPixDiscountService.executar(lojaId: 'loja1', docIds: ['A'], bulkId: 'pixbulk_t4');
      expect(r.sucessoTotal, isTrue);
      expect(server.payloads.length, 2);
      expect(server.payloads[0]['operationId'], server.payloads[1]['operationId']);
    });

    test('mesmo lote reenviado após commit incerto: servidor responde replay', () async {
      final server = FakeServer({'A': 10, 'B': 0});
      StockCatalogBackendService.debugTransport = server.call;
      final first = await BulkPixDiscountService.executar(lojaId: 'l', docIds: ['A', 'B'], bulkId: 'pixbulk_t5');
      final again = await BulkPixDiscountService.executar(lojaId: 'l', docIds: ['B', 'A'], bulkId: 'pixbulk_t5');
      expect(server.payloads[0]['operationId'], server.payloads[1]['operationId']);
      expect(again.atualizados, first.atualizados);
      expect(again.semAlteracao, first.semAlteracao);
    });

    test('servidor antigo sem o comando: mensagem clara, nada alterado', () async {
      StockCatalogBackendService.debugTransport = (name, data) async =>
          throw FirebaseFunctionsException(code: 'invalid-argument', message: 'Unknown or protected command field');
      final r = await BulkPixDiscountService.executar(lojaId: 'l', docIds: ['A'], bulkId: 'pixbulk_t6');
      expect(r.sucessoTotal, isFalse);
      expect(r.titulo, 'Desconto no Pix não removido');
      expect(r.falhas.single.mensagem, contains('servidor ainda não oferece'));
    });

    test('outra loja / sem permissão', () {
      final m = BulkPixDiscountService.mensagemErro(
          FirebaseFunctionsException(code: 'permission-denied', message: 'x'));
      expect(m, contains('não tem permissão'));
      final del = BulkPixDiscountService.mensagemErro(FirebaseFunctionsException(
          code: 'failed-precondition', message: 'x',
          details: {'code': 'BULK_PIX_PRODUCT_UNAVAILABLE', 'reason': 'DELETED', 'productId': 'p'}));
      expect(del, contains('foi excluído'));
    });
  });

  group('Hive (§10, §18)', () {
    late Directory dir;
    late Box<Produto> box;

    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('hive_bulk_pix_');
      Hive.init(dir.path);
      if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ProdutoAdapter());
    });

    tearDownAll(() async {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });

    setUp(() async {
      box = await Hive.openBox<Produto>('bulk_pix_${DateTime.now().microsecondsSinceEpoch}');
    });

    tearDown(() async => box.close());

    test('aplica 0 só no Pix, sem disparar auto-sync, preserva o resto', () async {
      final kA = await box.add(produto('A', 10, preco: 100));
      final kB = await box.add(produto('B', 5, preco: 200));
      final kC = await box.add(produto('C', 0, preco: 150));
      final guardAtEvent = <bool>[];
      final sub = box.watch().listen((_) => guardAtEvent.add(ProdutoRemoteSyncGuard.applyingRemoteToHive));
      final n = await BulkPixDiscountService.aplicarNoHive(
        box: box,
        hiveKeysPorDocId: {'A': [kA], 'B': [kB], 'C': [kC]},
        docIds: ['A', 'B', 'C'],
      );
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(n, 2, reason: 'C already without discount is not rewritten');
      expect(guardAtEvent, [true, true]);
      expect(ProdutoRemoteSyncGuard.applyingRemoteToHive, isFalse);
      final a = box.get(kA)!;
      expect(a.percentualDescontoPix, 0);
      expect(a.precoFinal, 100);
      expect(a.quantidade, 3);
      expect(a.emPromocao, isTrue);
      expect(a.percentualPromo, 20);
      expect(a.categoria, 'Religiosos');
      expect(box.get(kB)!.precoFinal, 200);
    });

    test('estado "sem desconto" (0) é o que app/catálogo antigos já entendem', () {
      // Firestore devolve 0 inteiro; todo leitor converte via num e testa > 0.
      final remote = <String, dynamic>{'percentualDescontoPix': 0};
      final lido = (remote['percentualDescontoPix'] is num)
          ? (remote['percentualDescontoPix'] as num).toDouble()
          : 99.0;
      expect(lido, 0.0);
      expect(Produto.vazio().percentualDescontoPix, 0.0);
      final semPix = computeCatalogCheckoutTotals(
        items: [
          {'preco': 100, 'quantidade': 1, 'percentualDescontoPix': 0},
        ],
        pagamento: 'PIX',
        fretesParaCalculo: const [],
        freteIndex: 0,
        freteGratisRoleta: false,
      );
      expect(semPix.total, 100, reason: 'Pix price equals normal price after removal');
      final comPix = computeCatalogCheckoutTotals(
        items: [
          {'preco': 100, 'quantidade': 1, 'percentualDescontoPix': 10},
        ],
        pagamento: 'PIX',
        fretesParaCalculo: const [],
        freteIndex: 0,
        freteGratisRoleta: false,
      );
      expect(comPix.total, 90);
    });
  });
}
