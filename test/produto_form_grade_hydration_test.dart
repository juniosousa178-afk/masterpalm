import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/produto_form_grade_hydration.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';

const _lojaId = 'loja-hydration-anel';
const _docId = 'nathy-pratas-e-folheados-anel-cora-o-meigo-rose';

Produto _produtoAnelMeigoRoseHiveParcial() {
  return Produto(
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
    lojaId: _lojaId,
    idFirebase: _docId,
    slug: _docId,
    tamanhos: const ['20', '22'],
    variacoes: {
      '20': {'sem-cor': 2},
      '22': {'sem-cor': 1},
    },
    estoquePorTamanho: const {'20': 2, '22': 1},
    variacoesExtraTipo: {
      '20': {
        'sem-cor': {'_sem_extra': 'Modelo'},
      },
      '22': {
        'sem-cor': {'_sem_extra': 'Modelo'},
      },
    },
    updatedAt: DateTime(2026, 6, 8, 23, 30),
    custoEditadoNoCadastro: true,
    publicadoNoCatalogo: true,
  );
}

Map<String, dynamic> _gradeRemotaCompletaAnel() => {
      'nome': 'Anel Coração Meigo Rose',
      'quantidade': 5,
      'variacoes': {
        '13': {'sem-cor': 1},
        '18': {'sem-cor': 1},
        '20': {'sem-cor': 2},
        '22': {'sem-cor': 1},
      },
      'estoquePorTamanho': {'13': 1, '18': 1, '20': 2, '22': 1},
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
      'updatedAt': Timestamp.fromDate(DateTime(2026, 6, 8, 23, 27, 37)),
    };

void main() {
  group('produtoFormHydrateGradeRows — Anel Meigo Rose', () {
    test('Hive parcial 20/22 monta só 2 linhas sem metadados completos', () {
      final p = _produtoAnelMeigoRoseHiveParcial();
      final h = produtoFormHydrateGradeRows(p);
      final tamanhos = h.rows
          .map((r) => r['tamanho'] ?? '')
          .where((t) => t.isNotEmpty)
          .toSet();
      expect(tamanhos, {'20', '22'});
      expect(h.rows.firstWhere((r) => r['tamanho'] == '20')['qtd'], '2');
    });

    test('Hive com grade completa monta 13/18/20/22', () {
      final remote = _gradeRemotaCompletaAnel();
      final p = Produto(
        nome: 'Anel Coração Meigo Rose',
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
        idFirebase: _docId,
        slug: _docId,
        tamanhos: List<String>.from(remote['tamanhos'] as List),
        variacoes: Map<String, dynamic>.from(remote['variacoes'] as Map),
        estoquePorTamanho: Map<String, int>.from(
          (remote['estoquePorTamanho'] as Map).map(
            (k, v) => MapEntry(k.toString(), (v as num).toInt()),
          ),
        ),
        variacoesExtraTipo:
            Map<String, dynamic>.from(remote['variacoesExtraTipo'] as Map),
      );
      final h = produtoFormHydrateGradeRows(p);
      final tamanhos = h.rows
          .map((r) => r['tamanho'] ?? '')
          .where((t) => t.isNotEmpty)
          .toList();
      expect(tamanhos, containsAll(['13', '18', '20', '22']));
      expect(tamanhos.length, 4);
      expect(h.rows.firstWhere((r) => r['tamanho'] == '13')['qtd'], '1');
      expect(h.rows.firstWhere((r) => r['tamanho'] == '20')['qtd'], '2');
    });

    test('estoque completo + variacoes parciais suplementa 13 e 18', () {
      final p = _produtoAnelMeigoRoseHiveParcial();
      p.tamanhos = const ['13', '18', '20', '22'];
      p.estoquePorTamanho = const {'13': 1, '18': 1, '20': 2, '22': 1};
      p.variacoesExtraTipo = {
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
      };
      final h = produtoFormHydrateGradeRows(p);
      final tamanhos = h.rows
          .map((r) => r['tamanho'] ?? '')
          .where((t) => t.isNotEmpty)
          .toSet();
      expect(tamanhos, containsAll(['13', '18', '20', '22']));
      expect(tamanhos.length, 4);
    });
  });

  group('refreshGradeFromEstoqueRemotoAoAbrirForm', () {
    late FakeFirebaseFirestore firestore;
    late Directory hiveDir;

    setUpAll(() async {
      hiveDir = Directory.systemTemp.createTempSync('hydration_form_hive_');
      Hive.init(hiveDir.path);
      if (!Hive.isAdapterRegistered(2)) {
        Hive.registerAdapter(ProdutoAdapter());
      }
    });

    tearDownAll(() {
      try {
        hiveDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    setUp(() {
      firestore = FakeFirebaseFirestore();
      ProdutosFirestoreService.debugFirestoreOverride = firestore;
    });

    tearDown(() {
      ProdutosFirestoreService.debugFirestoreOverride = null;
    });

    test('deveAtualizarGradeRemotaAoAbrirForm detecta Hive parcial', () {
      final local = _produtoAnelMeigoRoseHiveParcial();
      final remote = _gradeRemotaCompletaAnel();
      expect(
        ProdutosFirestoreService.deveAtualizarGradeRemotaAoAbrirForm(
          local: local,
          remoteData: remote,
        ),
        isTrue,
      );
    });

    test('refresh mescla remoto e hydration passa a ter 4 linhas', () async {
      await firestore
          .collection('lojas')
          .doc(_lojaId)
          .collection('estoque_produtos')
          .doc(_docId)
          .set(_gradeRemotaCompletaAnel());

      final box = await Hive.openBox<Produto>('produtos_hydration_open');
      final p = _produtoAnelMeigoRoseHiveParcial();
      await box.add(p);
      final salvo = box.getAt(0)!;
      final ok =
          await ProdutosFirestoreService.refreshGradeFromEstoqueRemotoAoAbrirForm(
        produto: salvo,
        lojaId: _lojaId,
      );
      expect(ok, isTrue);
      final h = produtoFormHydrateGradeRows(salvo);
      final tamanhos = h.rows
          .map((r) => r['tamanho'] ?? '')
          .where((t) => t.isNotEmpty)
          .toSet();
      expect(tamanhos, containsAll(['13', '18', '20', '22']));
      expect(salvo.variacoes?['13']?['sem-cor'], 1);
      expect(salvo.estoquePorTamanho['13'], 1);
      expect(salvo.custoReal, 20);
      await box.close();
    });
  });
}
