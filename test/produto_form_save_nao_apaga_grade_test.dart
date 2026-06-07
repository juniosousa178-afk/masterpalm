import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/produto_form_grade_hydration.dart';
import 'package:master_palm/core/produto_variacao_extra.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _lojaId = 'loja-save-grade-guard';
const _productId = 'anel-meigo-rose-guard';

Produto _produtoComVariacoes({
  String descricao = 'Descricao original',
  double custoReal = 20,
  Map<String, double>? precoPorTamanho,
}) {
  return Produto(
    nome: 'Anel Coração Meigo Rose',
    custoReal: custoReal,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 0,
    precoFinal: 89.9,
    quantidade: 4,
    precoUnitario: 89.9,
    categoria: 'Anel',
    subcategoria: 'Anel Prata 925',
    dataEntrada: DateTime(2026, 3, 8),
    descricao: descricao,
    lojaId: _lojaId,
    idFirebase: _productId,
    slug: _productId,
    tamanhos: const ['13', '18', '20', '22'],
    estoquePorTamanho: const {'20': 1, '22': 1},
    variacoes: {
      '20': {'rosa': 1},
      '22': {'rosa': 1},
    },
    variacoesExtraTipo: {
      '20': {
        'rosa': {'_sem_extra': 'Modelo'},
      },
    },
    precoPorTamanho: precoPorTamanho ?? const {'20': 95.0},
    updatedAt: DateTime(2026, 6, 7, 16, 0),
    custoEditadoNoCadastro: true,
    publicadoNoCatalogo: true,
  );
}

Produto _produtoEstoqueLegado() {
  return Produto(
    nome: 'Anel Legado',
    custoReal: 15,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 0,
    precoFinal: 50,
    quantidade: 2,
    precoUnitario: 50,
    categoria: 'Anel',
    dataEntrada: DateTime(2026, 3, 8),
    lojaId: _lojaId,
    idFirebase: 'prod-legado-estoque',
    slug: 'prod-legado-estoque',
    estoquePorTamanho: const {'19': 1, '21': 1},
    tamanhos: const ['19', '21'],
    updatedAt: DateTime(2026, 6, 7, 12, 0),
    custoEditadoNoCadastro: true,
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
    idFirebase: 'prod-simples',
    slug: 'prod-simples',
    updatedAt: DateTime(2026, 6, 7, 12, 0),
    custoEditadoNoCadastro: true,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('produto_form.save — não apaga grade sem intenção', () {
    test('baseline com variacoes + UI vazia preserva grade', () {
      final p = _produtoComVariacoes();
      final baseline = ProdutoFormGradeBaseline.capture(p);
      expect(produtoFormBaselineHadGrade(baseline), isTrue);

      final resolved = produtoFormResolveGradeForSave(
        baseline: baseline,
        uiVariacoes: {},
        uiVariacoesExtraTipo: null,
        uiEstoquePorTamanho: {},
        uiTamanhos: [],
        removedVarKeys: baseline.variacoes!.keys
            .map((k) => 'V::$k')
            .toSet(), // wipe total — não é remoção parcial
        removedTamKeys: {},
        baselineVarKeys: {'V::20', 'V::22'},
        baselineTamKeys: {'T::20', 'T::22'},
      );

      expect(resolved.preservedFromBaseline, isTrue);
      expect(resolved.variacoes.containsKey('20'), isTrue);
      expect(resolved.variacoes.containsKey('22'), isTrue);
      expect(resolved.estoquePorTamanho['20'], 1);
      expect(resolved.estoquePorTamanho['22'], 1);
    });

    test('save de descrição com variacoes preservadas no sync remoto', () async {
      SharedPreferences.setMockInitialValues({});
      final firestore = FakeFirebaseFirestore();
      ProdutosFirestoreService.debugFirestoreOverride = firestore;

      await firestore
          .collection('lojas')
          .doc(_lojaId)
          .collection('estoque_produtos')
          .doc(_productId)
          .set({
        'id': _productId,
        'nome': 'Anel Coração Meigo Rose',
        'descricao': 'Antiga',
        'quantidade': 4,
        'variacoes': {
          '20': {'rosa': 1},
          '22': {'rosa': 1},
        },
        'estoquePorTamanho': {'20': 1, '22': 1},
        'updatedAt': Timestamp.fromDate(DateTime(2026, 6, 7, 15, 0)),
      });

      final hiveDir =
          Directory.systemTemp.createTempSync('produto_save_grade_hive_');
      Hive.init(hiveDir.path);
      if (!Hive.isAdapterRegistered(2)) {
        Hive.registerAdapter(ProdutoAdapter());
      }

      try {
        final baseline = ProdutoFormGradeBaseline.capture(_produtoComVariacoes());
        final preserved = produtoFormResolveGradeForSave(
          baseline: baseline,
          uiVariacoes: {},
          uiVariacoesExtraTipo: null,
          uiEstoquePorTamanho: {},
          uiTamanhos: [],
          removedVarKeys: {'V::20', 'V::22'},
          removedTamKeys: {},
          baselineVarKeys: {'V::20', 'V::22'},
          baselineTamKeys: {'T::20', 'T::22'},
        );

        final box = await Hive.openBox<Produto>('produtos_save_grade');
        final key = await box.add(_produtoComVariacoes());
        final p = box.get(key)!;
        p
          ..descricao = 'TESTE GRADE 20260607 14:30'
          ..variacoes =
              preserved.variacoes.isNotEmpty ? preserved.variacoes : null
          ..variacoesExtraTipo = preserved.variacoesExtraTipo
          ..estoquePorTamanho = preserved.estoquePorTamanho
          ..tamanhos = preserved.tamanhos;
        await p.save();

        final status = await ProdutosFirestoreService.syncProdutoComStatus(
          p,
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
            .doc(_productId)
            .get();
        final data = snap.data()!;
        expect(data['descricao'], 'TESTE GRADE 20260607 14:30');
        expect(data['variacoes'], isNotNull);
        expect((data['variacoes'] as Map).containsKey('20'), isTrue);
        expect(data['estoquePorTamanho'], isNotNull);
        expect((data['estoquePorTamanho'] as Map)['20'], 1);
        expect(data['custoReal'], 20);
        await box.close();
      } finally {
        ProdutosFirestoreService.debugFirestoreOverride = null;
        Hive.close();
        if (hiveDir.existsSync()) hiveDir.deleteSync(recursive: true);
      }
    });

    test('estoquePorTamanho legado + UI vazia preserva e gera variacoes', () {
      final p = _produtoEstoqueLegado();
      final baseline = ProdutoFormGradeBaseline.capture(p);
      final resolved = produtoFormResolveGradeForSave(
        baseline: baseline,
        uiVariacoes: {},
        uiVariacoesExtraTipo: null,
        uiEstoquePorTamanho: {},
        uiTamanhos: [],
        removedVarKeys: {},
        removedTamKeys: {'T::19', 'T::21'},
        baselineVarKeys: {},
        baselineTamKeys: {'T::19', 'T::21'},
      );

      expect(resolved.preservedFromBaseline, isTrue);
      expect(resolved.estoquePorTamanho['19'], 1);
      expect(resolved.variacoes.containsKey('19'), isTrue);
      expect(
        ProdutoVariacaoExtra.somarCelula(resolved.variacoes['19']!['sem-cor']),
        1,
      );
    });

    test('tamanhos legado sem quantidade preserva tamanhos sem inventar qtd', () {
      final p = Produto(
        nome: 'Somente tamanhos',
        custoReal: 5,
        frete: 0,
        gastosFixos: 0,
        gastosVariaveis: 0,
        precoSugerido: 0,
        precoFinal: 40,
        quantidade: 1,
        precoUnitario: 40,
        categoria: 'Anel',
        dataEntrada: DateTime(2026, 3, 8),
        lojaId: _lojaId,
        idFirebase: 'prod-tam',
        slug: 'prod-tam',
        tamanhos: const ['P', 'M'],
        custoEditadoNoCadastro: true,
      );
      final baseline = ProdutoFormGradeBaseline.capture(p);
      final resolved = produtoFormResolveGradeForSave(
        baseline: baseline,
        uiVariacoes: {},
        uiVariacoesExtraTipo: null,
        uiEstoquePorTamanho: {},
        uiTamanhos: [],
        removedVarKeys: {},
        removedTamKeys: {},
        baselineVarKeys: {},
        baselineTamKeys: {},
      );
      expect(resolved.preservedFromBaseline, isTrue);
      expect(resolved.tamanhos, ['P', 'M']);
      expect(resolved.variacoes, isEmpty);
      expect(resolved.estoquePorTamanho, isEmpty);
    });

    test('produto simples sem grade continua sem grade', () {
      final baseline = ProdutoFormGradeBaseline.capture(_produtoSimples());
      expect(produtoFormBaselineHadGrade(baseline), isFalse);

      final resolved = produtoFormResolveGradeForSave(
        baseline: baseline,
        uiVariacoes: {},
        uiVariacoesExtraTipo: null,
        uiEstoquePorTamanho: {},
        uiTamanhos: [],
        removedVarKeys: {},
        removedTamKeys: {},
        baselineVarKeys: {},
        baselineTamKeys: {},
      );
      expect(resolved.preservedFromBaseline, isFalse);
      expect(resolved.variacoes, isEmpty);
    });

    test('precoPorTamanho do produto não é alterado pela resolução', () {
      final p = _produtoComVariacoes(precoPorTamanho: const {'20': 99.0});
      final antes = Map<String, double>.from(p.precoPorTamanho!);
      produtoFormResolveGradeForSave(
        baseline: ProdutoFormGradeBaseline.capture(p),
        uiVariacoes: {},
        uiVariacoesExtraTipo: null,
        uiEstoquePorTamanho: {},
        uiTamanhos: [],
        removedVarKeys: {'V::20', 'V::22'},
        removedTamKeys: {},
        baselineVarKeys: {'V::20', 'V::22'},
        baselineTamKeys: {},
      );
      expect(p.precoPorTamanho, equals(antes));
    });

    test('remoção parcial explícita permite UI vazia parcial', () {
      final p = _produtoComVariacoes();
      final baseline = ProdutoFormGradeBaseline.capture(p);
      final resolved = produtoFormResolveGradeForSave(
        baseline: baseline,
        uiVariacoes: {'20': {'rosa': 1}},
        uiVariacoesExtraTipo: null,
        uiEstoquePorTamanho: {'20': 1},
        uiTamanhos: ['20'],
        removedVarKeys: {'V::20|rosa'},
        removedTamKeys: {},
        baselineVarKeys: {'V::20|rosa', 'V::22|rosa'},
        baselineTamKeys: {'T::20', 'T::22'},
      );
      expect(resolved.preservedFromBaseline, isFalse);
      expect(resolved.variacoes.containsKey('20'), isTrue);
      expect(resolved.variacoes.containsKey('22'), isFalse);
    });

    test('grade preservada mantém payload não vazio para sync de catálogo', () {
      final p = _produtoComVariacoes(descricao: 'Com grade');
      final preserved = produtoFormBaselineGradePayload(
        ProdutoFormGradeBaseline.capture(p),
      );
      p
        ..variacoes = preserved.variacoes.isNotEmpty ? preserved.variacoes : null
        ..variacoesExtraTipo = preserved.variacoesExtraTipo
        ..estoquePorTamanho = preserved.estoquePorTamanho
        ..tamanhos = preserved.tamanhos
        ..descricao = 'TESTE GRADE catalogo';

      expect(p.variacoes, isNotNull);
      expect(p.variacoes!.isNotEmpty, isTrue);
      expect(p.estoquePorTamanho.isNotEmpty, isTrue);
      expect(p.estoquePorTamanho['20'], 1);
    });
  });
}
