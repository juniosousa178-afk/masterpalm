import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/bulk_promocao_service.dart';
import 'package:master_palm/services/produto_promocao.dart';
import 'package:master_palm/services/produto_remote_sync_guard.dart';
import 'package:master_palm/services/stock_catalog_backend_service.dart';

BulkPromoCandidato c(String id, bool promo, {int key = 0, String loja = 'lojaA', String nome = ''}) =>
    BulkPromoCandidato(
        hiveKey: key, docId: id, nome: nome.isEmpty ? id : nome, lojaId: loja, emPromocao: promo);

final inicio = DateTime(2026, 10, 1);
final fim = DateTime(2026, 12, 31);

Produto produto(
  String id, {
  bool promo = true,
  double preco = 100,
  int qtd = 7,
  String loja = 'lojaA',
  Map<String, dynamic>? variacoes,
}) =>
    Produto(
      nome: id,
      custoReal: 40,
      frete: 0,
      gastosFixos: 0,
      gastosVariaveis: 0,
      precoSugerido: preco,
      precoFinal: preco,
      quantidade: qtd,
      precoUnitario: preco,
      categoria: 'Religiosos',
      subcategoria: 'Terços',
      dataEntrada: DateTime(2026, 1, 1),
      idFirebase: id,
      lojaId: loja,
      sku: 'SKU-$id',
      codigoBarras: '789$id',
      imagens: const ['https://example.test/a.jpg'],
      publicadoNoCatalogo: true,
      percentualDescontoPix: 5,
      emPromocao: promo,
      percentualPromo: promo ? 20 : null,
      dataInicioPromo: promo ? inicio : null,
      dataFimPromo: promo ? fim : null,
      variacoes: variacoes,
    );

/// In-memory stand-in for `stockCatalogCommand` editorial: one product per command,
/// replays by operationId, records every payload and the merged editorial per product.
class FakeServer {
  FakeServer(Iterable<String> produtos) {
    for (final id in produtos) {
      docs[id] = {'emPromocao': true, 'percentualPromo': 20.0, 'preco': 100.0, 'quantidade': 7};
    }
  }

  final docs = <String, Map<String, dynamic>>{};
  final payloads = <Map<String, dynamic>>[];
  final applied = <String, Map<String, dynamic>>{};
  Object? Function(String productId, int callForProduct)? fail;
  final _calls = <String, int>{};

  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> data) async {
    expect(name, 'stockCatalogCommand');
    payloads.add(data);
    final items = (data['items'] as List).cast<Map>();
    expect(items, hasLength(1), reason: 'editorial command requires one product');
    final id = items.single['productId'] as String;
    final n = _calls[id] = (_calls[id] ?? 0) + 1;
    final injected = fail?.call(id, n);
    if (injected != null) throw injected;
    final op = data['operationId'] as String;
    if (applied.containsKey(op)) return {...applied[op]!, 'alreadyApplied': true};
    final doc = docs[id];
    if (doc == null) {
      throw FirebaseFunctionsException(code: 'failed-precondition', message: 'Canonical product required');
    }
    doc.addAll(Map<String, dynamic>.from(data['editorial'] as Map));
    return applied[op] = {'alreadyApplied': false, 'operationId': op};
  }
}

void main() {
  tearDown(() => StockCatalogBackendService.debugTransport = null);

  group('contrato único (individual == lote)', () {
    test('desativar: só os campos de promoção; período, preço, estoque e o resto ficam', () {
      final p = produto('A', variacoes: {
        'P': {'Azul': 2},
        'M': {'Azul': 5},
      });
      expect(ProdutoPromocao.desativar(p), isTrue);
      expect(p.emPromocao, isFalse);
      expect(p.percentualPromo, isNull);
      expect(p.valorPromo, isNull);
      expect(p.dataInicioPromo, inicio);
      expect(p.dataFimPromo, fim);
      expect(p.precoFinal, 100, reason: 'promotional price never becomes the normal price');
      expect(p.precoUnitario, 100);
      expect(p.custoReal, 40);
      expect(p.quantidade, 7);
      expect(p.sku, 'SKU-A');
      expect(p.codigoBarras, '789A');
      expect(p.imagens, ['https://example.test/a.jpg']);
      expect(p.categoria, 'Religiosos');
      expect(p.subcategoria, 'Terços');
      expect(p.publicadoNoCatalogo, isTrue);
      expect(p.percentualDescontoPix, 5);
      expect(p.variacoes, {
        'P': {'Azul': 2},
        'M': {'Azul': 5},
      });
      expect(p.promocaoAtiva, isFalse);
      expect(p.precoComPromocao, 100);
    });

    test('produto sem promoção: nada muda e não conta como desativado', () {
      final p = produto('B', promo: false);
      expect(ProdutoPromocao.desativar(p), isFalse);
      expect(p.emPromocao, isFalse);
      expect(p.precoFinal, 100);
    });

    test('formulário com o switch desligado grava exatamente o patch do lote', () {
      for (final tipo in ['percentual', 'fixo']) {
        final off = ProdutoPromocao.descontoParaSalvar(
            emPromocao: false, tipoDesconto: tipo, lerPercentual: () => 20, lerValor: () => 10);
        expect(
          {'emPromocao': false, 'percentualPromo': off.percentual, 'valorPromo': off.valor},
          ProdutoPromocao.camposDesativacao,
        );
      }
      final pct = ProdutoPromocao.descontoParaSalvar(
          emPromocao: true, tipoDesconto: 'percentual', lerPercentual: () => 20, lerValor: () => 10);
      expect((pct.percentual, pct.valor), (20.0, null));
      final fixo = ProdutoPromocao.descontoParaSalvar(
          emPromocao: true, tipoDesconto: 'fixo', lerPercentual: () => 20, lerValor: () => 10);
      expect((fixo.percentual, fixo.valor), (null, 10.0));
    });

    test('patch cabe no allowlist editorial e não leva preço, estoque nem datas', () {
      final keys = ProdutoPromocao.camposDesativacao.keys.toSet();
      expect(keys, {'emPromocao', 'percentualPromo', 'valorPromo'});
      expect(StockCatalogBackendService.editorialFields.containsAll(keys), isTrue);
    });

    test('formulário usa o contrato nos dois caminhos de gravação', () {
      final form = File('lib/screens/produto_form_screen.dart').readAsStringSync();
      expect(RegExp('_descontoPromoParaSalvar\\(\\);').allMatches(form).length, 2);
      expect(form, contains('ProdutoPromocao.descontoParaSalvar('));
      expect(form, isNot(contains('percentualPromo = MoedaInputFormatter.parse')));
    });
  });

  group('preview', () {
    test('1 produto', () {
      final p = BulkPromoPreview.calcular([c('A', true)]);
      expect(p.titulo, 'Desativar a promoção de 1 produto?');
      expect(p.linhas.first, '1 produto terá a promoção desativada.');
      expect(p.docIds, ['A']);
      expect(p.podeExecutar, isTrue);
    });

    test('mistura: sem promoção não é enviado e é contado; avisos obrigatórios', () {
      final p = BulkPromoPreview.calcular([
        for (var i = 0; i < 12; i++) c('com$i', true),
        for (var i = 0; i < 3; i++) c('sem$i', false),
      ]);
      expect(p.titulo, 'Desativar a promoção de 15 produtos?');
      expect(p.comPromocao, 12);
      expect(p.semPromocao, 3);
      expect(p.docIds, hasLength(12));
      expect(p.docIds.any((id) => id.startsWith('sem')), isFalse);
      expect(p.linhas, contains('3 já estão sem promoção e não serão alterados.'));
      expect(p.linhas, containsAll(
          ['O preço normal será mantido.', 'O estoque não será alterado.', 'Nenhum produto será excluído.']));
    });

    test('não sincronizado com promoção é ignorado; fora do filtro é avisado; dedup', () {
      final p = BulkPromoPreview.calcular([c('A', true), c('', true), c('A', true), c('', false)], foraDoFiltro: 2);
      expect(p.docIds, ['A']);
      expect(p.naoSincronizados, 1);
      expect(p.semPromocao, 1);
      expect(p.linhas.any((l) => l.contains('não foi sincronizado')), isTrue);
      expect(p.linhas.any((l) => l.contains('2 produtos selecionados não aparecem no filtro atual')), isTrue);
    });

    test('nenhum com promoção: botão desabilitado', () {
      expect(BulkPromoPreview.calcular([c('A', false)]).podeExecutar, isFalse);
    });
  });

  group('multi-tenant (fail closed)', () {
    const box = 'produtos_lojaa';

    test('mesma loja: liberado (nome da box comparado como o Hive guarda, minúsculo)', () {
      expect(
        BulkPromocaoService.validarLoja(
            lojaIdAtual: 'lojaA', lojaIdTela: 'lojaA', nomeBox: box, candidatos: [c('A', true), c('B', true, loja: '')]),
        isNull,
      );
      expect(HiveBoxNames.produtos('lojaA').toLowerCase(), box);
    });

    test('loja ativa trocou, box de outra loja, produto de outra loja ou loja vazia: bloqueia', () {
      String? v({String atual = 'lojaA', String tela = 'lojaA', String nomeBox = box, String loja = 'lojaA'}) =>
          BulkPromocaoService.validarLoja(
              lojaIdAtual: atual, lojaIdTela: tela, nomeBox: nomeBox, candidatos: [c('A', true, loja: loja)]);
      expect(v(atual: 'lojaB'), contains('loja ativa mudou'));
      expect(v(nomeBox: 'produtos_lojab'), contains('não pertence à loja ativa'));
      expect(v(loja: 'lojaB'), contains('pertence a outra loja'));
      expect(v(atual: ''), contains('Loja não identificada'));
      expect(v(tela: ' '), contains('Loja não identificada'));
      for (final m in [v(atual: 'lojaB'), v(nomeBox: 'x'), v(loja: 'lojaB'), v(atual: '')]) {
        expect(m, contains('Nenhuma alteração foi feita.'));
      }
    });
  });

  group('execução', () {
    test('vários produtos: um comando editorial por produto, só o patch de promoção', () async {
      final server = FakeServer(['A', 'B', 'C']);
      StockCatalogBackendService.debugTransport = server.call;
      final progresso = <String>[];
      final r = await BulkPromocaoService.executar(
        lojaId: 'lojaA',
        docIds: ['C', 'A', 'B', 'A'],
        bulkId: 'promobulk_t1',
        jaSemPromocao: 2,
        onProgresso: (d, t) => progresso.add('$d/$t'),
      );
      expect(r.sucessoTotal, isTrue);
      expect(r.desativados, {'A', 'B', 'C'});
      expect(r.linhas, ['3 promoções desativadas', '2 já estavam sem promoção', '0 falharam']);
      expect(r.mensagemSucesso, '3 promoções desativadas com sucesso. 2 já estavam sem promoção.');
      expect(progresso, ['0/3', '1/3', '2/3', '3/3']);
      expect(server.payloads, hasLength(3), reason: 'no duplicate writes');
      for (final payload in server.payloads) {
        expect(payload['kind'], 'editorial');
        expect(payload['lojaId'], 'lojaA');
        expect(payload['editorial'], ProdutoPromocao.camposDesativacao);
        final texto = payload.toString();
        for (final proibido in ['preco', 'quantidade', 'custo', 'variacoes', 'estoque', 'imagens', 'publicado', 'dataInicio']) {
          expect(texto, isNot(contains(proibido)), reason: proibido);
        }
      }
      for (final id in ['A', 'B', 'C']) {
        expect(server.docs[id]!['preco'], 100.0);
        expect(server.docs[id]!['quantidade'], 7);
        expect(server.docs[id]!['emPromocao'], isFalse);
      }
    });

    test('operationId determinístico por loja+lote+produto', () {
      final a = BulkPromocaoService.operationId(lojaId: 'l', bulkId: 'b', docId: 'x');
      expect(a, BulkPromocaoService.operationId(lojaId: 'l', bulkId: 'b', docId: 'x'));
      expect(a, isNot(BulkPromocaoService.operationId(lojaId: 'l', bulkId: 'b2', docId: 'x')));
      expect(a, isNot(BulkPromocaoService.operationId(lojaId: 'l2', bulkId: 'b', docId: 'x')));
      expect(RegExp(r'^promooff_[0-9a-f]{64}$').hasMatch(a), isTrue);
      expect(BulkPromocaoService.operationId(lojaId: 'loja1', bulkId: 'promobulk_vec', docId: 'abc'),
          'promooff_271fff0c705c06d8e31e3d2b2760f82f8c3c6cc9bfd32414e33c7f2eed1efad2',
          reason: 'same vector as functions/test/stock-bulk-promotion-deactivation.test.mjs');
    });

    test('falha parcial: os outros seguem; nova tentativa só das falhas, mesmo operationId', () async {
      final server = FakeServer(['A', 'B', 'C', 'D']);
      server.docs.remove('D');
      var redeCaiu = true;
      server.fail = (id, n) => id == 'B' && redeCaiu
          ? FirebaseFunctionsException(code: 'unavailable', message: 'network')
          : null;
      StockCatalogBackendService.debugTransport = server.call;
      final r = await BulkPromocaoService.executar(
          lojaId: 'lojaA', docIds: ['A', 'B', 'C', 'D'], bulkId: 'promobulk_t2', nomes: {'B': 'Colar', 'D': 'Terço'});
      expect(r.sucessoTotal, isFalse);
      expect(r.titulo, 'Promoções desativadas em parte');
      expect(r.desativados, {'A', 'C'});
      expect(r.linhas.last, '2 falharam');
      expect(r.falhas.firstWhere((f) => f.docId == 'B').mensagem, contains('Tentar novamente é seguro'));
      expect(r.falhas.firstWhere((f) => f.docId == 'D').mensagem, contains('"Terço" não foi encontrado'));
      expect(r.idsParaNovaTentativa, ['B'], reason: 'missing product is not retried');
      final opB = server.payloads.lastWhere((p) => (p['items'] as List).single['productId'] == 'B')['operationId'];

      redeCaiu = false;
      final antes = server.payloads.length;
      final retry = await BulkPromocaoService.executar(
          lojaId: 'lojaA', docIds: r.idsParaNovaTentativa, bulkId: 'promobulk_t2');
      expect(retry.sucessoTotal, isTrue);
      expect(retry.desativados, {'B'});
      expect(server.payloads.length - antes, 1, reason: 'A and C are not resent');
      expect(server.payloads.last['operationId'], opB);
    });

    test('commit incerto reenviado: servidor responde replay, sem segunda escrita', () async {
      final server = FakeServer(['A']);
      StockCatalogBackendService.debugTransport = server.call;
      await BulkPromocaoService.executar(lojaId: 'l', docIds: ['A'], bulkId: 'promobulk_t3');
      final again = await BulkPromocaoService.executar(lojaId: 'l', docIds: ['A'], bulkId: 'promobulk_t3');
      expect(server.payloads[0]['operationId'], server.payloads[1]['operationId']);
      expect(again.desativados, {'A'});
      expect(server.applied, hasLength(1));
    });

    test('sem permissão, excluído e dados inválidos: mensagem clara e sem nova tentativa', () {
      final perm = FirebaseFunctionsException(code: 'permission-denied', message: 'x');
      expect(BulkPromocaoService.mensagemErro(perm, nome: 'P'), contains('não tem permissão'));
      expect(BulkPromocaoService.podeTentarDeNovo(perm), isFalse);
      final del = FirebaseFunctionsException(
          code: 'failed-precondition', message: 'Product tombstone requires reconciliation');
      expect(BulkPromocaoService.mensagemErro(del, nome: 'P'), contains('foi excluído'));
      expect(BulkPromocaoService.podeTentarDeNovo(del), isFalse);
      final inval = StockCatalogProductValidationException('x');
      expect(BulkPromocaoService.mensagemErro(inval, nome: 'P'), contains('revisados no cadastro'));
      expect(BulkPromocaoService.podeTentarDeNovo(inval), isFalse);
      expect(BulkPromocaoService.podeTentarDeNovo(StateError('offline')), isTrue);
    });
  });

  group('Hive e sync', () {
    late Directory dir;

    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('hive_bulk_promo_');
      Hive.init(dir.path);
      if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ProdutoAdapter());
    });

    tearDownAll(() async {
      await Hive.close();
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });

    test('aplica só nos desativados, sem disparar auto-sync, outra loja intacta, nada excluído', () async {
      final sufixo = DateTime.now().microsecondsSinceEpoch;
      final boxA = await Hive.openBox<Produto>(HiveBoxNames.produtos('lojaA$sufixo'));
      final boxB = await Hive.openBox<Produto>(HiveBoxNames.produtos('lojaB$sufixo'));
      final kA = await boxA.add(produto('A', variacoes: {
        'P': {'Azul': 2}
      }));
      final kB = await boxA.add(produto('B'));
      final kSem = await boxA.add(produto('S', promo: false));
      final kOutra = await boxB.add(produto('A', loja: 'lojaB'));
      final guardAtEvent = <bool>[];
      final sub = boxA.watch().listen((_) => guardAtEvent.add(ProdutoRemoteSyncGuard.applyingRemoteToHive));

      final n = await BulkPromocaoService.aplicarNoHive(
        box: boxA,
        hiveKeysPorDocId: {'A': [kA], 'B': [kB], 'S': [kSem]},
        docIds: ['A', 'S'],
      );
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(n, 1, reason: 'B failed on server and S had no promotion');
      expect(guardAtEvent, [true]);
      expect(ProdutoRemoteSyncGuard.applyingRemoteToHive, isFalse);
      final a = boxA.get(kA)!;
      expect(a.emPromocao, isFalse);
      expect(a.percentualPromo, isNull);
      expect(a.precoFinal, 100);
      expect(a.quantidade, 7);
      expect(a.variacoes, {
        'P': {'Azul': 2}
      });
      expect(a.dataFimPromo, fim);
      expect(boxA.get(kB)!.emPromocao, isTrue, reason: 'failed product keeps its promotion');
      expect(boxA.length, 3, reason: 'no product deleted');
      expect(boxB.get(kOutra)!.emPromocao, isTrue, reason: 'other store untouched');
      expect(boxB.get(kOutra)!.percentualPromo, 20);
    });

    test('pull do servidor depois do lote não devolve a promoção', () {
      final local = produto('A');
      ProdutoPromocao.desativar(local);
      // Same rule as ProdutosFirestoreService.syncFirestoreToHive: keys present on the doc win.
      final remoto = <String, dynamic>{'emPromocao': false, 'percentualPromo': null, 'valorPromo': null};
      if (remoto.containsKey('emPromocao')) local.emPromocao = remoto['emPromocao'] == true;
      if (remoto.containsKey('percentualPromo')) local.percentualPromo = (remoto['percentualPromo'] as num?)?.toDouble();
      if (remoto.containsKey('valorPromo')) local.valorPromo = (remoto['valorPromo'] as num?)?.toDouble();
      expect(local.emPromocao, isFalse);
      expect(local.percentualPromo, isNull);
      expect(local.promocaoAtiva, isFalse);

      final sync = File('lib/services/produtos_firestore_service.dart').readAsStringSync();
      expect(sync, contains("if (data.containsKey('emPromocao')) {\n                p.emPromocao = data['emPromocao'] == true;"));
      expect(sync, contains("if (data.containsKey('percentualPromo')) {"));
      expect(sync, contains("if (data.containsKey('valorPromo')) {"));
    });
  });

  group('tela de estoque', () {
    final tela = File('lib/screens/estoque_screen.dart').readAsStringSync();

    String metodo(String assinatura) {
      final i = tela.indexOf(assinatura);
      expect(i, greaterThan(0), reason: assinatura);
      return tela.substring(i, tela.indexOf('\n  }\n', i));
    }

    test('"Selecionar todos" usa a listagem filtrada, que inclui o filtro "Promoção ativa"', () {
      expect(metodo('void _selecionarTodos() {'), contains('_produtosListagemEstoque(_box.values)'));
      expect(metodo('List<Produto> _produtosListagemEstoque('), contains('_passaFiltrosUiEstoque('));
      expect(metodo('bool _passaFiltrosUiEstoque('),
          contains('if (_filtroEmPromocao && !ProdutoPromocao.temPromocao(p)) return false;'));
      expect(metodo('int _contagemFiltrosAtivos() {'), contains('if (_filtroEmPromocao) n++;'));
      expect(tela, contains("title: const Text('Promoção ativa')"));
      expect(tela, contains('_filtroEmPromocao = false;'));
    });

    test('fluxo: valida loja antes de gravar, reflete no Hive, limpa seleção e avisa', () {
      final fluxo = metodo('Future<void> _desativarPromocoesLote() async {');
      expect(fluxo.indexOf('BulkPromocaoService.validarLoja('), lessThan(fluxo.indexOf('_executarDesativacaoPromocoes(')));
      expect(fluxo, contains('nomeBox: _box.name'));
      final exec = metodo('Future<void> _executarDesativacaoPromocoes({');
      expect(exec, contains('BulkPromocaoService.aplicarNoHive('));
      expect(exec, contains('docIds: resultado.desativados'));
      expect(exec, contains('_produtosSelecionados.clear();'));
      expect(exec, contains('_showSnackBar(r.mensagemSucesso);'));
      expect(exec, contains('docIds: r.idsParaNovaTentativa'));
      expect(exec, contains('bulkId: bulkId'));
      final menu = metodo('Future<void> _mostrarMenuAcoes() async {');
      expect(menu, matches(RegExp(r'case EstoqueAcaoLote\.desativarPromocao:\s+_desativarPromocoesLote\(\);')));
      expect(menu, contains('const {EstoqueAcaoLote.desativarPromocao}'));
      expect(tela, contains('const Flexible(child: ProdutoPromocaoBadge(emPromocao: true))'));
    });
  });
}
