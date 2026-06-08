import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/produto_estoque_grade_canonical_guard.dart';
import 'package:master_palm/core/produto_form_grade_hydration.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _lojaId = 'loja-grade-canonica';
const _docId = 'anel-cora-o-meigo-rose-canon';

Map<String, dynamic> _gradeRemotaAnelMeigoRoseSemCor() => {
      'id': _docId,
      'nome': 'Anel Coração Meigo Rose',
      'descricao': 'Antiga',
      'quantidade': 4,
      'variacoes': {
        '20': {'sem-cor': 1},
        '22': {'sem-cor': 1},
      },
      'estoquePorTamanho': {'13': 1, '18': 1, '20': 1, '22': 1},
      'tamanhos': ['13', '18', '20', '22'],
      'variacoesExtraTipo': {
        '13': {
          'sem-cor': {'_sem_extra': 'Modelo'},
        },
        '18': {
          'sem-cor': {'_sem_extra': 'Modelo'},
        },
        '20': {
          'sem-cor': {'_sem_extra': 'Modelo'},
        },
        '22': {
          'sem-cor': {'_sem_extra': 'Modelo'},
        },
      },
      'custoReal': 20,
      'updatedAt': Timestamp.fromDate(DateTime(2026, 6, 7, 15, 0)),
    };

Map<String, dynamic> _gradeRemotaCompleta() => {
      'id': _docId,
      'nome': 'Anel Coração Meigo Rose',
      'descricao': 'Antiga',
      'quantidade': 4,
      'variacoes': {
        '20': {'rosa': 1},
        '22': {'rosa': 1},
      },
      'estoquePorTamanho': {'20': 1, '22': 1},
      'tamanhos': ['13', '18', '20', '22'],
      'variacoesExtraTipo': {
        '20': {
          'rosa': {'_sem_extra': 'Modelo'},
        },
        '22': {
          'rosa': {'_sem_extra': 'Modelo'},
        },
      },
      'custoReal': 20,
      'updatedAt': Timestamp.fromDate(DateTime(2026, 6, 7, 15, 0)),
    };

Produto _produtoComGradeParcialNoPush({
  String descricao = 'TESTE FIRESTORE PATH 20260608',
}) {
  return Produto(
    nome: 'Anel Coração Meigo Rose',
    custoReal: 20,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 0,
    precoFinal: 89.9,
    quantidade: 2,
    precoUnitario: 89.9,
    categoria: 'Anel',
    dataEntrada: DateTime(2026, 3, 8),
    descricao: descricao,
    lojaId: _lojaId,
    idFirebase: _docId,
    slug: _docId,
    tamanhos: const ['20', '22'],
    variacoes: null,
    estoquePorTamanho: const {},
    variacoesExtraTipo: {
      '20': {
        'rosa': {'_sem_extra': 'Modelo'},
      },
      '22': {
        'rosa': {'_sem_extra': 'Modelo'},
      },
    },
    updatedAt: DateTime(2026, 6, 8, 22, 0),
    custoEditadoNoCadastro: true,
    publicadoNoCatalogo: true,
  );
}

Produto _produtoSimples() {
  return Produto(
    nome: 'Pulseira Simples',
    custoReal: 10,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 0,
    precoFinal: 30,
    quantidade: 3,
    precoUnitario: 30,
    categoria: 'Pulseira',
    dataEntrada: DateTime(2026, 3, 8),
    lojaId: _lojaId,
    idFirebase: 'prod-simples-canon',
    slug: 'prod-simples-canon',
    updatedAt: DateTime(2026, 6, 7, 12, 0),
    custoEditadoNoCadastro: true,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProdutoEstoqueGradeCanonicalGuard — unitário', () {
    test('baseline com grade não permite push sem variacoes', () {
      final baseline = ProdutoFormGradeBaseline.capture(
        Produto(
          nome: 'Com grade',
          custoReal: 1,
          frete: 0,
          gastosFixos: 0,
          gastosVariaveis: 0,
          precoSugerido: 0,
          precoFinal: 10,
          quantidade: 2,
          precoUnitario: 10,
          categoria: 'A',
          dataEntrada: DateTime(2026, 1, 1),
          lojaId: _lojaId,
          variacoes: {'20': {'rosa': 1}},
          estoquePorTamanho: const {'20': 1},
          tamanhos: const ['20'],
        ),
      );

      final completed = ProdutoEstoqueGradeCanonicalGuard.completeForEstoquePush(
        lojaId: _lojaId,
        produtoId: _docId,
        variacoesPush: {},
        variacoesExtraPush: {},
        estoquePorTamPush: {},
        tamanhosPush: const ['20'],
        quantidade: 2,
        baseline: baseline,
      );

      expect(completed.variacoes.containsKey('20'), isTrue);
      expect(completed.estoquePorTamanho['20'], 1);
      expect(completed.acao, 'preserve');
    });

    test('baseline com grade não permite push sem estoquePorTamanho', () {
      final baseline = ProdutoFormGradeBaseline.capture(
        Produto(
          nome: 'Com grade',
          custoReal: 1,
          frete: 0,
          gastosFixos: 0,
          gastosVariaveis: 0,
          precoSugerido: 0,
          precoFinal: 10,
          quantidade: 2,
          precoUnitario: 10,
          categoria: 'A',
          dataEntrada: DateTime(2026, 1, 1),
          lojaId: _lojaId,
          variacoes: {
            '20': {'rosa': 1},
            '22': {'rosa': 1},
          },
          estoquePorTamanho: const {'20': 1, '22': 1},
        ),
      );

      final completed = ProdutoEstoqueGradeCanonicalGuard.completeForEstoquePush(
        lojaId: _lojaId,
        produtoId: _docId,
        variacoesPush: Map<String, dynamic>.from(baseline.variacoes!),
        variacoesExtraPush: {},
        estoquePorTamPush: {},
        tamanhosPush: const ['20', '22'],
        quantidade: 2,
        baseline: baseline,
      );

      expect(completed.estoquePorTamanho['20'], 1);
      expect(completed.estoquePorTamanho['22'], 1);
    });

    test('extra+tamanhos+quantidade reconstrói 20/rosa e 22/rosa', () {
      final completed = ProdutoEstoqueGradeCanonicalGuard.completeForEstoquePush(
        lojaId: _lojaId,
        produtoId: _docId,
        variacoesPush: {},
        variacoesExtraPush: {
          '20': {
            'rosa': {'_sem_extra': 'Modelo'},
          },
          '22': {
            'rosa': {'_sem_extra': 'Modelo'},
          },
        },
        estoquePorTamPush: {},
        tamanhosPush: const ['20', '22'],
        quantidade: 2,
      );

      expect(completed.acao, 'reconstruct');
      expect(completed.variacoes['20']?['rosa'], 1);
      expect(completed.variacoes['22']?['rosa'], 1);
      expect(completed.estoquePorTamanho['20'], 1);
      expect(completed.estoquePorTamanho['22'], 1);
    });

    test('produto simples continua simples', () {
      final completed = ProdutoEstoqueGradeCanonicalGuard.completeForEstoquePush(
        lojaId: _lojaId,
        produtoId: 'prod-simples-canon',
        variacoesPush: {},
        variacoesExtraPush: {},
        estoquePorTamPush: {},
        tamanhosPush: const [],
        quantidade: 3,
      );
      expect(completed.variacoes, isEmpty);
      expect(completed.estoquePorTamanho, isEmpty);
      expect(completed.acao, isNull);
    });

    test('save normal não remove grade total quando remoto tinha grade', () {
      final remote = _gradeRemotaCompleta();
      final completed = ProdutoEstoqueGradeCanonicalGuard.completeForEstoquePush(
        lojaId: _lojaId,
        produtoId: _docId,
        variacoesPush: {},
        variacoesExtraPush: remote['variacoesExtraTipo'] as Map<String, dynamic>,
        estoquePorTamPush: {},
        tamanhosPush: const ['20', '22'],
        quantidade: 2,
        existingEstoqueData: remote,
      );

      expect(completed.variacoes.containsKey('20'), isTrue);
      expect(completed.variacoes.containsKey('22'), isTrue);
      expect(completed.estoquePorTamanho['20'], 1);
      expect(completed.estoquePorTamanho['22'], 1);
      expect(completed.acao, 'preserve');
    });

    test('reidratação não substitui Hive por grade remota incompleta', () {
      final local = Produto(
        nome: 'Anel',
        custoReal: 20,
        frete: 0,
        gastosFixos: 0,
        gastosVariaveis: 0,
        precoSugerido: 0,
        precoFinal: 89.9,
        quantidade: 2,
        precoUnitario: 89.9,
        categoria: 'Anel',
        dataEntrada: DateTime(2026, 3, 8),
        lojaId: _lojaId,
        idFirebase: _docId,
        slug: _docId,
        variacoes: {
          '20': {'rosa': 1},
          '22': {'rosa': 1},
        },
        estoquePorTamanho: const {'20': 1, '22': 1},
        tamanhos: const ['20', '22'],
        descricao: 'Local completa',
      );

      final remoteIncompleto = {
        'descricao': 'Remota nova',
        'quantidade': 2,
        'tamanhos': ['20', '22'],
        'variacoesExtraTipo': {
          '20': {
            'rosa': {'_sem_extra': 'Modelo'},
          },
        },
      };

      final decision = ProdutoEstoqueGradeCanonicalGuard.resolveForRehydrate(
        local: local,
        remoteData: remoteIncompleto,
      );

      expect(decision.aplicarGradeRemota, isFalse);
      expect(decision.aviso, ProdutoEstoqueGradeCanonicalGuard.avisoGradeRemotaIncompleta);
      expect(decision.variacoes?['20']?['rosa'], 1);
      expect(decision.estoquePorTamanho?['22'], 1);
    });

    test('custoReal não é alterado pelo guard', () {
      final p = _produtoComGradeParcialNoPush();
      final custoAntes = p.custoReal;
      ProdutoEstoqueGradeCanonicalGuard.completeForEstoquePush(
        lojaId: _lojaId,
        produtoId: _docId,
        variacoesPush: {},
        variacoesExtraPush: Map<String, dynamic>.from(p.variacoesExtraTipo!),
        estoquePorTamPush: {},
        tamanhosPush: List<String>.from(p.tamanhos),
        quantidade: p.quantidade,
        existingEstoqueData: _gradeRemotaCompleta(),
      );
      expect(p.custoReal, custoAntes);
    });

    test('20/rosa 1→2 na tela vence remoto e recalcula estoquePorTamanho', () {
      final remote = _gradeRemotaCompleta();
      final completed = ProdutoEstoqueGradeCanonicalGuard.completeForEstoquePush(
        lojaId: _lojaId,
        produtoId: _docId,
        variacoesPush: {
          '20': {'rosa': 2},
          '22': {'rosa': 1},
        },
        variacoesExtraPush: {},
        estoquePorTamPush: const {},
        tamanhosPush: const ['20', '22'],
        quantidade: 3,
        existingEstoqueData: remote,
      );

      expect(completed.origem, 'push_variacoes_tela');
      expect(completed.variacoes['20']?['rosa'], 2);
      expect(completed.variacoes['22']?['rosa'], 1);
      expect(completed.estoquePorTamanho['20'], 2);
      expect(completed.estoquePorTamanho['22'], 1);
      expect(
        ProdutoEstoqueGradeCanonicalGuard.quantidadeTotalFromVariacoes(
          completed.variacoes,
        ),
        3,
      );
    });

    test('baseline/remoto antigo não sobrescreve variacoes editadas localmente', () {
      final baseline = ProdutoFormGradeBaseline.capture(
        Produto(
          nome: 'Com grade',
          custoReal: 1,
          frete: 0,
          gastosFixos: 0,
          gastosVariaveis: 0,
          precoSugerido: 0,
          precoFinal: 10,
          quantidade: 2,
          precoUnitario: 10,
          categoria: 'A',
          dataEntrada: DateTime(2026, 1, 1),
          lojaId: _lojaId,
          variacoes: {
            '20': {'rosa': 1},
            '22': {'rosa': 1},
          },
          estoquePorTamanho: const {'20': 1, '22': 1},
        ),
      );

      final completed = ProdutoEstoqueGradeCanonicalGuard.completeForEstoquePush(
        lojaId: _lojaId,
        produtoId: _docId,
        variacoesPush: {
          '20': {'rosa': 2},
          '22': {'rosa': 1},
        },
        variacoesExtraPush: {},
        estoquePorTamPush: const {},
        tamanhosPush: const ['20', '22'],
        quantidade: 3,
        existingEstoqueData: _gradeRemotaCompleta(),
        baseline: baseline,
      );

      expect(completed.variacoes['20']?['rosa'], 2);
      expect(completed.estoquePorTamanho['20'], 2);
      expect(completed.origem, 'push_variacoes_tela');
    });

    test('duas variações no mesmo tamanho somam estoquePorTamanho', () {
      final completed = ProdutoEstoqueGradeCanonicalGuard.completeForEstoquePush(
        lojaId: _lojaId,
        produtoId: _docId,
        variacoesPush: {
          '20': {
            'rosa': 2,
            'azul': 1,
          },
        },
        variacoesExtraPush: {},
        estoquePorTamPush: const {},
        tamanhosPush: const ['20'],
        quantidade: 3,
      );

      expect(completed.estoquePorTamanho['20'], 3);
      expect(completed.variacoes['20']?['rosa'], 2);
      expect(completed.variacoes['20']?['azul'], 1);
    });

    test('editar só 20/sem-cor 1→2 preserva 13/sem-cor e 18/sem-cor no push', () {
      final remote = _gradeRemotaAnelMeigoRoseSemCor();
      final completed = ProdutoEstoqueGradeCanonicalGuard.completeForEstoquePush(
        lojaId: _lojaId,
        produtoId: _docId,
        variacoesPush: {
          '20': {'sem-cor': 2},
          '22': {'sem-cor': 1},
        },
        variacoesExtraPush: {},
        estoquePorTamPush: const {},
        tamanhosPush: const ['20', '22'],
        quantidade: 3,
        existingEstoqueData: remote,
      );

      expect(completed.variacoes['13']?['sem-cor'], 1);
      expect(completed.variacoes['18']?['sem-cor'], 1);
      expect(completed.variacoes['20']?['sem-cor'], 2);
      expect(completed.variacoes['22']?['sem-cor'], 1);
      expect(completed.estoquePorTamanho['13'], 1);
      expect(completed.estoquePorTamanho['18'], 1);
      expect(completed.estoquePorTamanho['20'], 2);
      expect(completed.estoquePorTamanho['22'], 1);
      expect(
        ProdutoEstoqueGradeCanonicalGuard.quantidadeTotalFromVariacoes(
          completed.variacoes,
        ),
        5,
      );
    });

    test('reidratação pós-save com local parcial mescla remoto completo', () {
      final local = Produto(
        nome: 'Anel',
        custoReal: 20,
        frete: 0,
        gastosFixos: 0,
        gastosVariaveis: 0,
        precoSugerido: 0,
        precoFinal: 89.9,
        quantidade: 3,
        precoUnitario: 89.9,
        categoria: 'Anel',
        dataEntrada: DateTime(2026, 3, 8),
        lojaId: _lojaId,
        idFirebase: _docId,
        slug: _docId,
        variacoes: {
          '20': {'sem-cor': 2},
          '22': {'sem-cor': 1},
        },
        estoquePorTamanho: const {'20': 2, '22': 1},
        tamanhos: const ['20', '22'],
      );

      final remoteCompleto = {
        'variacoes': {
          '13': {'sem-cor': 1},
          '18': {'sem-cor': 1},
          '20': {'sem-cor': 2},
          '22': {'sem-cor': 1},
        },
        'estoquePorTamanho': {'13': 1, '18': 1, '20': 2, '22': 1},
        'tamanhos': ['13', '18', '20', '22'],
        'quantidade': 5,
      };

      final decision = ProdutoEstoqueGradeCanonicalGuard.resolveForRehydrate(
        local: local,
        remoteData: remoteCompleto,
      );

      expect(decision.aplicarGradeRemota, isFalse);
      expect(decision.variacoes?['13']?['sem-cor'], 1);
      expect(decision.variacoes?['18']?['sem-cor'], 1);
      expect(decision.variacoes?['20']?['sem-cor'], 2);
      expect(decision.variacoes?['22']?['sem-cor'], 1);
      expect(decision.estoquePorTamanho?['13'], 1);
      expect(decision.estoquePorTamanho?['18'], 1);
      expect(decision.estoquePorTamanho?['20'], 2);
      expect(decision.tamanhos, containsAll(['13', '18', '20', '22']));
    });

    test('hidratação UI suplementa tamanhos ausentes via estoquePorTamanho', () {
      final p = Produto(
        nome: 'Anel',
        custoReal: 20,
        frete: 0,
        gastosFixos: 0,
        gastosVariaveis: 0,
        precoSugerido: 0,
        precoFinal: 89.9,
        quantidade: 5,
        precoUnitario: 89.9,
        categoria: 'Anel',
        dataEntrada: DateTime(2026, 3, 8),
        lojaId: _lojaId,
        variacoes: {
          '20': {'sem-cor': 2},
          '22': {'sem-cor': 1},
        },
        estoquePorTamanho: const {'13': 1, '18': 1, '20': 2, '22': 1},
        tamanhos: const ['13', '18', '20', '22'],
      );

      final hydration = produtoFormHydrateGradeRows(p);
      final tamanhosNaUi = hydration.rows
          .map((r) => r['tamanho'] ?? '')
          .where((t) => t.isNotEmpty)
          .toSet();

      expect(hydration.source, ProdutoFormGradeHydrationSource.variacoes);
      expect(tamanhosNaUi, containsAll(['13', '18', '20', '22']));
    });

    test('reidratação mantém quantidade local quando remoto diverge', () {
      final local = Produto(
        nome: 'Anel',
        custoReal: 20,
        frete: 0,
        gastosFixos: 0,
        gastosVariaveis: 0,
        precoSugerido: 0,
        precoFinal: 89.9,
        quantidade: 3,
        precoUnitario: 89.9,
        categoria: 'Anel',
        dataEntrada: DateTime(2026, 3, 8),
        lojaId: _lojaId,
        idFirebase: _docId,
        slug: _docId,
        variacoes: {
          '20': {'rosa': 2},
          '22': {'rosa': 1},
        },
        estoquePorTamanho: const {'20': 2, '22': 1},
        tamanhos: const ['20', '22'],
      );

      final remoteCompleto = {
        'variacoes': {
          '20': {'rosa': 1},
          '22': {'rosa': 1},
        },
        'estoquePorTamanho': {'20': 1, '22': 1},
        'quantidade': 2,
      };

      final decision = ProdutoEstoqueGradeCanonicalGuard.resolveForRehydrate(
        local: local,
        remoteData: remoteCompleto,
      );

      expect(decision.aplicarGradeRemota, isFalse);
      expect(decision.variacoes?['20']?['rosa'], 2);
      expect(decision.estoquePorTamanho?['20'], 2);
    });
  });

  group('sync estoque_produtos — grade canônica integrada', () {
    late Directory hiveDir;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      hiveDir = Directory.systemTemp.createTempSync('grade_canonica_hive_');
      Hive.init(hiveDir.path);
      if (!Hive.isAdapterRegistered(2)) {
        Hive.registerAdapter(ProdutoAdapter());
      }
    });

    tearDown(() {
      ProdutosFirestoreService.debugFirestoreOverride = null;
      try {
        Hive.close();
      } catch (_) {}
    });

    tearDownAll(() {
      try {
        hiveDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('caso real: push parcial preserva variacoes do remoto anterior', () async {
      final firestore = FakeFirebaseFirestore();
      ProdutosFirestoreService.debugFirestoreOverride = firestore;

      await firestore
          .collection('lojas')
          .doc(_lojaId)
          .collection('estoque_produtos')
          .doc(_docId)
          .set(_gradeRemotaCompleta());

      final box = await Hive.openBox<Produto>('produtos_grade_canon');
      final p = _produtoComGradeParcialNoPush();
      await box.add(p);
      final salvo = box.getAt(0)!;

      final status = await ProdutosFirestoreService.syncProdutoComStatus(
        salvo,
        lojaId: _lojaId,
        forcePushFromCadastro: true,
        writeOrigin: 'produto_form.save',
        enqueueOnFailure: false,
      );
      expect(status, ProdutoSyncRemotoStatus.confirmado);

      final snap = await firestore
          .collection('lojas')
          .doc(_lojaId)
          .collection('estoque_produtos')
          .doc(_docId)
          .get();
      final data = snap.data()!;
      expect(data['descricao'], contains('TESTE FIRESTORE PATH'));
      expect(data['variacoes'], isNotNull);
      expect((data['variacoes'] as Map)['20']?['rosa'], 1);
      expect((data['variacoes'] as Map)['22']?['rosa'], 1);
      expect(data['estoquePorTamanho'], isNotNull);
      expect((data['estoquePorTamanho'] as Map)['20'], 1);
      expect((data['estoquePorTamanho'] as Map)['22'], 1);
      expect(data['custoReal'], 20);
      await box.close();
    });

    test('produto simples não cria grade falsa no estoque', () async {
      final firestore = FakeFirebaseFirestore();
      ProdutosFirestoreService.debugFirestoreOverride = firestore;

      final box = await Hive.openBox<Produto>('produtos_simples_canon');
      final p = _produtoSimples();
      await box.add(p);
      final salvo = box.getAt(0)!;

      final status = await ProdutosFirestoreService.syncProdutoComStatus(
        salvo,
        lojaId: _lojaId,
        forcePushFromCadastro: true,
        enqueueOnFailure: false,
      );
      expect(status, ProdutoSyncRemotoStatus.confirmado);

      final snap = await firestore
          .collection('lojas')
          .doc(_lojaId)
          .collection('estoque_produtos')
          .doc('prod-simples-canon')
          .get();
      final data = snap.data()!;
      expect(data.containsKey('variacoes'), isFalse);
      expect(data.containsKey('estoquePorTamanho'), isFalse);
      await box.close();
    });

    test('sync persiste quantidade editada 20/rosa 2 no estoque_produtos', () async {
      final firestore = FakeFirebaseFirestore();
      ProdutosFirestoreService.debugFirestoreOverride = firestore;

      await firestore
          .collection('lojas')
          .doc(_lojaId)
          .collection('estoque_produtos')
          .doc(_docId)
          .set(_gradeRemotaCompleta());

      final box = await Hive.openBox<Produto>('produtos_qty_edit');
      final p = Produto(
        nome: 'Anel Coração Meigo Rose',
        custoReal: 20,
        frete: 0,
        gastosFixos: 0,
        gastosVariaveis: 0,
        precoSugerido: 0,
        precoFinal: 89.9,
        quantidade: 3,
        precoUnitario: 89.9,
        categoria: 'Anel',
        dataEntrada: DateTime(2026, 3, 8),
        descricao: 'Qty editada',
        lojaId: _lojaId,
        idFirebase: _docId,
        slug: _docId,
        tamanhos: const ['20', '22'],
        variacoes: {
          '20': {'rosa': 2},
          '22': {'rosa': 1},
        },
        estoquePorTamanho: const {'20': 2, '22': 1},
        updatedAt: DateTime(2026, 6, 8, 23, 0),
        custoEditadoNoCadastro: true,
        publicadoNoCatalogo: true,
      );
      await box.add(p);
      final salvo = box.getAt(0)!;

      final status = await ProdutosFirestoreService.syncProdutoComStatus(
        salvo,
        lojaId: _lojaId,
        forcePushFromCadastro: true,
        writeOrigin: 'produto_form.save',
        enqueueOnFailure: false,
      );
      expect(status, ProdutoSyncRemotoStatus.confirmado);

      final snap = await firestore
          .collection('lojas')
          .doc(_lojaId)
          .collection('estoque_produtos')
          .doc(_docId)
          .get();
      final data = snap.data()!;
      expect((data['variacoes'] as Map)['20']?['rosa'], 2);
      expect((data['variacoes'] as Map)['22']?['rosa'], 1);
      expect((data['estoquePorTamanho'] as Map)['20'], 2);
      expect((data['estoquePorTamanho'] as Map)['22'], 1);
      expect(data['quantidade'], 3);
      expect(data['custoReal'], 20);
      await box.close();
    });

    test('reidratação pós-save com remoto incompleto mantém grade local', () async {
      final firestore = FakeFirebaseFirestore();
      ProdutosFirestoreService.debugFirestoreOverride = firestore;

      final box = await Hive.openBox<Produto>('produtos_rehydrate_canon');
      final local = Produto(
        nome: 'Anel',
        custoReal: 20,
        frete: 0,
        gastosFixos: 0,
        gastosVariaveis: 0,
        precoSugerido: 0,
        precoFinal: 89.9,
        quantidade: 2,
        precoUnitario: 89.9,
        categoria: 'Anel',
        dataEntrada: DateTime(2026, 3, 8),
        lojaId: _lojaId,
        idFirebase: _docId,
        slug: _docId,
        variacoes: {
          '20': {'rosa': 1},
          '22': {'rosa': 1},
        },
        estoquePorTamanho: const {'20': 1, '22': 1},
        tamanhos: const ['20', '22'],
        descricao: 'Local antes',
      );
      await box.add(local);
      final p = box.getAt(0)!;

      await firestore
          .collection('lojas')
          .doc(_lojaId)
          .collection('estoque_produtos')
          .doc(_docId)
          .set({
        'descricao': 'Remota incompleta',
        'quantidade': 2,
        'tamanhos': ['20', '22'],
        'variacoesExtraTipo': {
          '20': {
            'rosa': {'_sem_extra': 'Modelo'},
          },
        },
        'custoReal': 20,
      });

      final result =
          await ProdutosFirestoreService.rehydrateProdutoConfirmadoFromEstoqueRemoto(
        p,
        lojaId: _lojaId,
      );

      expect(result.sucesso, isTrue);
      expect(result.aviso, ProdutoEstoqueGradeCanonicalGuard.avisoGradeRemotaIncompleta);
      expect(p.descricao, 'Remota incompleta');
      expect(p.variacoes?['20']?['rosa'], 1);
      expect(p.variacoes?['22']?['rosa'], 1);
      expect(p.estoquePorTamanho['22'], 1);
      await box.close();
    });
  });
}
