import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/bulk_editorial_service.dart';
import 'package:master_palm/services/produto_desconto_pix.dart';
import 'package:master_palm/services/produto_remote_sync_guard.dart';

import 'support/bulk_editorial_fixture.dart';

const _loja = BulkEditorialFixture.lojaId;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProdutoDescontoPix (regra única: formulário e lote)', () {
    test('lote aceita 0, valor normal e o máximo; recusa negativo, NaN, texto e acima do máximo', () {
      expect(ProdutoDescontoPix.parse('0'), 0);
      expect(ProdutoDescontoPix.parse('10'), 10);
      expect(ProdutoDescontoPix.parse(' 7,5 '), 7.5);
      expect(ProdutoDescontoPix.parse('100'), 100);
      for (final bad in ['-1', 'NaN', 'dez', '', '100.01', 'Infinity']) {
        expect(ProdutoDescontoPix.parse(bad), isNull, reason: bad);
      }
      expect(() => BulkEditorialPlano.descontoPix(double.nan), throwsArgumentError);
      expect(() => BulkEditorialPlano.descontoPix(101), throwsArgumentError);
      expect(() => BulkEditorialPlano.descontoPix(-0.5), throwsArgumentError);
    });

    test('formulário mantém o comportamento (texto => 0, fora da faixa => limite) e nunca sai da regra', () {
      expect(ProdutoDescontoPix.normalizarFormulario('12'), 12);
      expect(ProdutoDescontoPix.normalizarFormulario('abc'), 0);
      expect(ProdutoDescontoPix.normalizarFormulario('-3'), 0);
      expect(ProdutoDescontoPix.normalizarFormulario('150'), 100);
      expect(ProdutoDescontoPix.normalizarFormulario('NaN'), 0);
      for (final raw in ['0', '10', '100', '-1', 'NaN', 'x', '101']) {
        expect(ProdutoDescontoPix.valido(ProdutoDescontoPix.normalizarFormulario(raw)), isTrue, reason: raw);
        final lote = ProdutoDescontoPix.parse(raw);
        if (lote != null) expect(lote, ProdutoDescontoPix.normalizarFormulario(raw), reason: raw);
      }
    });
  });

  group('operationId', () {
    final plano = BulkEditorialPlano.descontoPix(10);
    String id(String loja, String bulk, String doc, [BulkEditorialPlano? p]) =>
        BulkEditorialService.operationId(plano: p ?? plano, lojaId: loja, bulkId: bulk, docId: doc);

    test('vetor fixo compartilhado com o teste Node (Dart == JS)', () {
      expect(id('loja1', 'edbulk_vec', 'abc'),
          'pixset_0c3122196e6cc92cebc19976d5c232c3a5d67a5a2a0fda91fe95098bdcdb359f');
    });

    test('determinístico por loja + operação + produto; distinto entre ações', () {
      expect(id('a', 'b', 'c'), id('a', 'b', 'c'));
      expect(id('a', 'b', 'c'), isNot(id('x', 'b', 'c')));
      expect(id('a', 'b', 'c'), isNot(id('a', 'x', 'c')));
      expect(id('a', 'b', 'c'), isNot(id('a', 'b', 'x')));
      expect(id('a', 'b', 'c'), isNot(id('a', 'b', 'c', BulkEditorialPlano.dividirSemJuros(6))));
      expect(id('a', 'b', 'c').startsWith('pixset_'), isTrue);
    });
  });

  group('validarLoja (fail-closed)', () {
    BulkEditorialCandidato c(String loja) =>
        BulkEditorialCandidato(hiveKey: 1, docId: 'p1', nome: 'P', lojaId: loja);
    String? v({String atual = _loja, String tela = _loja, List<BulkEditorialCandidato>? cs}) =>
        BulkEditorialService.validarLoja(
          lojaIdAtual: atual,
          lojaIdTela: tela,
          nomeBox: 'produtos_$_loja',
          candidatos: cs ?? [c(_loja)],
        );

    test('loja coerente passa; qualquer divergência ou loja vazia bloqueia', () {
      expect(v(), isNull);
      expect(v(atual: ''), isNotNull);
      expect(v(tela: ''), isNotNull);
      expect(v(atual: BulkEditorialFixture.outraLoja), isNotNull);
      expect(v(cs: [c(_loja), c(BulkEditorialFixture.outraLoja)]), isNotNull);
    });
  });

  group('executar + aplicarNoHive', () {
    late BulkEditorialFixture f;

    setUp(() async {
      f = await BulkEditorialFixture.create(ids: ['p1', 'p2', 'p3']);
    });
    tearDown(() => f.dispose());

    List<BulkEditorialCandidato> todos() => [
          for (final id in ['p1', 'p2', 'p3'])
            BulkEditorialCandidato.fromProduto(f.keys[id]!, f.box.get(f.keys[id])!),
        ];

    Future<BulkEditorialResultado> run(
      BulkEditorialPlano plano, {
      List<BulkEditorialCandidato>? cs,
      Iterable<String>? somente,
    }) async {
      final candidatos = cs ?? todos();
      final r = await BulkEditorialService.executar(
        plano: plano,
        lojaId: _loja,
        bulkId: 'edbulk_t',
        candidatos: candidatos,
        somenteDocIds: somente,
      );
      await BulkEditorialService.aplicarNoHive(
        box: f.box,
        plano: plano,
        candidatos: candidatos,
        docIdsConfirmados: r.confirmados,
      );
      return r;
    }

    double pixHive(String id) => f.box.get(f.keys[id])!.percentualDescontoPix;

    test('tudo confirmado: mensagem de sucesso com a contagem do servidor', () async {
      final r = await run(BulkEditorialPlano.descontoPix(10));
      expect(r.totalSelecionados, 3);
      expect(r.confirmados, {'p1', 'p2', 'p3'});
      expect(r.falhas, isEmpty);
      expect(r.ignorados, 0);
      expect(r.sucessoTotal, isTrue);
      expect(r.mensagemSucesso, 'Desconto no Pix de 10% aplicado em 3 produtos.');
      expect(f.commands, hasLength(3));
      expect(ProdutoRemoteSyncGuard.applyingRemoteToHive, isFalse);
    });

    test('falha parcial: só os confirmados mudam no Hive; nova tentativa reenvia só o que falhou', () async {
      f.failIds.add('p2');
      f.failWith = () => FirebaseFunctionsException(code: 'unavailable', message: 'offline');
      final plano = BulkEditorialPlano.descontoPix(10);
      final r = await run(plano);
      expect(r.confirmados, {'p1', 'p3'});
      expect(r.falhas.single.docId, 'p2');
      expect(r.falhas.single.podeTentarDeNovo, isTrue);
      expect(r.sucessoTotal, isFalse);
      expect(r.titulo, 'Desconto no Pix: aplicado em parte');
      expect(r.linhas, contains('2 produtos atualizados'));
      expect(r.linhas, contains('1 falhou'));
      expect(pixHive('p1'), 10);
      expect(pixHive('p2'), 0, reason: 'sem confirmação do servidor, o Hive não muda');
      expect(pixHive('p3'), 10);
      expect((await f.doc('produtos', 'p2'))!['percentualDescontoPix'], 0.0);
      final opIdP2 = f.commands.firstWhere((c) => (c['items'] as List).single['productId'] == 'p2')['operationId'];

      f.failIds.clear();
      f.commands.clear();
      final retry = await run(plano, somente: r.idsParaNovaTentativa);
      expect(f.commands, hasLength(1), reason: 'confirmados não são reenviados');
      expect((f.commands.single['items'] as List).single['productId'], 'p2');
      expect(f.commands.single['operationId'], opIdP2, reason: 'mesmo opId => replay seguro no servidor');
      expect(retry.sucessoTotal, isTrue);
      expect(retry.totalSelecionados, 1);
      expect(pixHive('p2'), 10);
      expect((await f.doc('produtos', 'p2'))!['percentualDescontoPix'], 10);
    });

    test('falha não recuperável não oferece nova tentativa', () async {
      f.failIds.add('p1');
      f.failWith = () => FirebaseFunctionsException(code: 'permission-denied', message: 'no');
      final r = await run(BulkEditorialPlano.descontoPix(10));
      expect(r.falhas.single.podeTentarDeNovo, isFalse);
      expect(r.idsParaNovaTentativa, isEmpty);
      expect(r.falhas.single.mensagem, contains('permissão'));
    });

    test('tudo falhou: título sem sucesso e Hive intacto', () async {
      f.failIds.addAll(['p1', 'p2', 'p3']);
      final r = await run(BulkEditorialPlano.descontoPix(10));
      expect(r.confirmados, isEmpty);
      expect(r.falhas, hasLength(3));
      expect(r.titulo, 'Desconto no Pix: nada foi aplicado');
      expect(r.linhas, contains('0 produtos atualizados'));
      for (final id in ['p1', 'p2', 'p3']) {
        expect(pixHive(id), 0, reason: id);
      }
    });

    test('produto nunca sincronizado é ignorado (contado à parte) e não é enviado', () async {
      final cs = [
        ...todos().take(1),
        const BulkEditorialCandidato(hiveKey: 999, docId: '', nome: 'Local', lojaId: _loja),
      ];
      final r = await run(BulkEditorialPlano.descontoPix(10), cs: cs);
      expect(r.totalSelecionados, 2);
      expect(r.confirmados, {'p1'});
      expect(r.ignorados, 1);
      expect(f.commands, hasLength(1));
      expect(r.linhas.last, contains('ainda não foi sincronizado'));
    });

    test('nenhum sincronizado: nada é aplicado nem anunciado como sucesso', () async {
      final r = await run(BulkEditorialPlano.descontoPix(10), cs: const [
        BulkEditorialCandidato(hiveKey: 999, docId: '', nome: 'Local', lojaId: _loja),
      ]);
      expect(r.sucessoTotal, isFalse);
      expect(r.titulo, 'Desconto no Pix: nada foi aplicado');
      expect(f.commands, isEmpty);
    });

    test('Hive já com o valor não é motivo para saltar: o servidor é sempre consultado', () async {
      final p = f.box.get(f.keys['p1'])!..percentualDescontoPix = 10;
      await p.save();
      final r = await run(BulkEditorialPlano.descontoPix(10), cs: todos().take(1).toList());
      expect(f.commands, hasLength(1));
      expect(r.confirmados, {'p1'});
      expect((await f.doc('produtos', 'p1'))!['percentualDescontoPix'], 10);
    });

    test('dividir sem juros: patch só com os campos de parcelamento, refletido no catálogo', () async {
      final r = await run(BulkEditorialPlano.dividirSemJuros(6), cs: todos().take(1).toList());
      expect(r.sucessoTotal, isTrue);
      expect(f.commands.single['editorial'], {'divideSemJuros': true, 'maxParcelasSemJuros': 6});
      for (final col in ['estoque_produtos', 'draft_produtos', 'produtos']) {
        final d = (await f.doc(col, 'p1'))!;
        expect(d['divideSemJuros'], isTrue, reason: col);
        expect(d['maxParcelasSemJuros'], 6, reason: col);
        expect(d['percentualDescontoPix'], 0.0, reason: col);
      }
      final h = f.box.get(f.keys['p1'])!;
      expect(h.divideSemJuros, isTrue);
      expect(h.maxParcelasSemJuros, 6);
      expect(r.mensagemSucesso, 'Dividir sem juros em até 6x aplicado em 1 produto.');
    });

    test('ativar promoção: patch com os campos do formulário; período vazio é limpo', () async {
      final inicio = DateTime(2026, 11, 1);
      final r = await run(BulkEditorialPlano.ativarPromocao(valor: 15, inicio: inicio),
          cs: todos().take(1).toList());
      expect(r.sucessoTotal, isTrue);
      expect(f.commands.single['editorial'], {
        'emPromocao': true,
        'percentualPromo': null,
        'valorPromo': 15.0,
        'dataInicioPromo': inicio.toIso8601String(),
        'dataFimPromo': null,
      });
      expect((await f.doc('produtos', 'p1'))!['emPromocao'], isTrue);
      final h = f.box.get(f.keys['p1'])!;
      expect(h.emPromocao, isTrue);
      expect(h.valorPromo, 15);
      expect(h.percentualPromo, isNull);
      expect(h.dataInicioPromo, inicio);
      expect(h.dataFimPromo, isNull);
      expect(() => BulkEditorialPlano.ativarPromocao(), throwsArgumentError);
      expect(() => BulkEditorialPlano.ativarPromocao(percentual: 0), throwsArgumentError);
      expect(() => BulkEditorialPlano.ativarPromocao(percentual: 10, valor: 5), throwsArgumentError);
    });

    test('produto não publicado: estoque e draft atualizados, sem publicar', () async {
      await f.dispose();
      f = await BulkEditorialFixture.create(ids: ['nopub'], naoPublicados: {'nopub'});
      final cs = [BulkEditorialCandidato.fromProduto(f.keys['nopub']!, f.box.get(f.keys['nopub'])!)];
      final r = await run(BulkEditorialPlano.descontoPix(5), cs: cs);
      expect(r.sucessoTotal, isTrue);
      expect((await f.doc('estoque_produtos', 'nopub'))!['percentualDescontoPix'], 5);
      expect((await f.doc('draft_produtos', 'nopub'))!['percentualDescontoPix'], 5);
      expect(await f.doc('produtos', 'nopub'), isNull);
    });
  });
}
