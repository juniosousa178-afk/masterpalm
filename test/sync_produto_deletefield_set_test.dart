import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/core/produto_variacao_extra.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/firestore_payload_sanitizer.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

bool _payloadContainsDeleteSentinel(dynamic value) {
  if (FirestorePayloadSanitizer.isDeleteFieldValue(value)) return true;
  if (value is Map) {
    for (final e in value.values) {
      if (_payloadContainsDeleteSentinel(e)) return true;
    }
  }
  if (value is Iterable && value is! Map) {
    for (final e in value) {
      if (_payloadContainsDeleteSentinel(e)) return true;
    }
  }
  return false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const lojaId = 'nathy-pratas-e-folheados';
  late FakeFirebaseFirestore firestore;
  late String hivePath;
  late Box<Produto> produtosBox;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_deletefield_set_');
    hivePath = dir.path;
    Hive.init(hivePath);
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ProdutoAdapter());
  });

  tearDownAll(() async {
    try {
      await Directory(hivePath).delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ProdutosFirestoreService.debugForceSyncFailureRemaining = 0;
    ProdutosFirestoreService.ultimoErroSyncSanitizado = null;
    firestore = FakeFirebaseFirestore();
    ProdutosFirestoreService.debugFirestoreOverride = firestore;
    final s = DateTime.now().microsecondsSinceEpoch;
    produtosBox = await Hive.openBox<Produto>('p_deletefield_$s');
  });

  tearDown(() async {
    ProdutosFirestoreService.debugFirestoreOverride = null;
    await produtosBox.close();
  });

  Produto _novoSimples({
    String nome = 'TesteSimples',
    String id = 'nathy-pratas-e-folheados-teste-simples',
  }) {
    return Produto.vazio()
      ..nome = nome
      ..slug = id
      ..idFirebase = id
      ..lojaId = lojaId
      ..categoria = 'Aneis'
      ..subcategoria = 'Prata'
      ..quantidade = 1
      ..precoFinal = 10
      ..precoUnitario = 10
      ..custoReal = 5
      ..precoSugerido = 10
      ..updatedAt = DateTime.now();
  }

  group('applyVariationFields e buildFinalDocumentPayloadForSet', () {
    test('produto simples sem variações não coloca deleteField no patch', () {
      final patch = <String, dynamic>{'nome': 'X'};
      final removeKeys = <String>{};
      ProdutosFirestoreService.applyVariationFieldsToFirestorePayload(
        patch,
        variacoes: const {},
        variacoesExtraTipo: const {},
        estoquePorTamanho: const {},
        variationKeysToRemove: removeKeys,
      );

      expect(patch.containsKey('variacoesExtraTipo'), isFalse);
      expect(patch.containsKey('variacoes'), isFalse);
      expect(_payloadContainsDeleteSentinel(patch), isFalse);
      expect(
        removeKeys,
        containsAll(ProdutosFirestoreService.variationFirestoreFieldKeys
            .where((k) => k != 'precoPorTamanho')),
      );
    });

    test('payload final para set() não contém delete sentinel', () {
      final patch = <String, dynamic>{'nome': 'Novo'};
      final removeKeys = <String>{};
      ProdutosFirestoreService.applyVariationFieldsToFirestorePayload(
        patch,
        variacoes: const {},
        variacoesExtraTipo: const {},
        estoquePorTamanho: const {},
        variationKeysToRemove: removeKeys,
      );

      final finalPayload = ProdutosFirestoreService.buildFinalDocumentPayloadForSet(
        existingData: {
          'nome': 'Antigo',
          'variacoesExtraTipo': {'M': {'Azul': 'tipo'}},
          'variacoes': {'M': {'Azul': 1}},
          'estoquePorTamanho': {'M': 1},
          'precoPorTamanho': {'M': 9.9},
        },
        patch: patch,
        forceRemoveKeys: removeKeys,
      );

      expect(_payloadContainsDeleteSentinel(finalPayload), isFalse);
      expect(finalPayload.containsKey('variacoesExtraTipo'), isFalse);
      expect(finalPayload.containsKey('variacoes'), isFalse);
      expect(finalPayload.containsKey('estoquePorTamanho'), isFalse);
      expect(finalPayload.containsKey('precoPorTamanho'), isFalse);
      expect(finalPayload['nome'], 'Novo');
    });

    test('sanitizer remove deleteField legado de payload full-set', () {
      final r = FirestorePayloadSanitizer.sanitizeMap(
        {
          'variacoesExtraTipo': FieldValue.delete(),
          'nome': 'Ok',
        },
        rootPath: 'estoque_produtos/x',
        forFullDocumentSet: true,
      );
      expect(r.payload.containsKey('variacoesExtraTipo'), isFalse);
      expect(r.payload['nome'], 'Ok');
      expect(r.adjustedPaths.single, contains('variacoesExtraTipo'));
      expect(_payloadContainsDeleteSentinel(r.payload), isFalse);
    });
  });

  group('sync remoto', () {
    test('produto simples sincroniza em estoque_produtos sem invalid-argument',
        () async {
      final p = _novoSimples();
      await produtosBox.add(p);

      final status = await ProdutosFirestoreService.syncProdutoComStatus(
        p,
        lojaId: lojaId,
      );
      expect(status, ProdutoSyncRemotoStatus.confirmado);

      final snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(p.idFirebase)
          .get();
      expect(snap.exists, isTrue);
      expect(snap.data()?['nome'], p.nome);
      expect(snap.data()?.containsKey('variacoesExtraTipo'), isFalse);
    });

    test('remover variações apaga campos antigos no doc remoto', () async {
      const productId = 'nathy-pratas-e-folheados-var-clear';
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(productId)
          .set({
        'id': productId,
        'nome': 'Com grade',
        'updatedAt': Timestamp.fromDate(DateTime(2020, 1, 1)),
        'variacoes': {
          'M': {
            'Azul': {ProdutoVariacaoExtra.kSemExtraKey: 2},
          },
        },
        'variacoesExtraTipo': {
          'M': {
            'Azul': {'extra': 'x'},
          },
        },
        'estoquePorTamanho': {'M': 2},
        'precoPorTamanho': {'M': 10.0},
      });

      final p = _novoSimples(id: productId, nome: 'Sem grade');
      p.variacoes = null;
      p.variacoesExtraTipo = null;
      p.estoquePorTamanho = {};
      p.precoPorTamanho = null;

      final status = await ProdutosFirestoreService.syncProdutoComStatus(
        p,
        lojaId: lojaId,
        bumpHiveTimestamp: false,
      );
      expect(status, ProdutoSyncRemotoStatus.confirmado);

      final snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(productId)
          .get();
      final data = snap.data()!;
      expect(data.containsKey('variacoes'), isFalse);
      expect(data.containsKey('variacoesExtraTipo'), isFalse);
      expect(data.containsKey('estoquePorTamanho'), isFalse);
      expect(data.containsKey('precoPorTamanho'), isFalse);
    });

    test('doc público não mantém custoReal após sync de produto publicado',
        () async {
      const productId = 'nathy-pratas-e-folheados-publico-strip';
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('produtos')
          .doc(productId)
          .set({
        'nome': 'Legado',
        'custoReal': 99,
        'variacoesExtraTipo': {'P': {}},
      });

      final p = _novoSimples(id: productId, nome: 'Publicado');
      p.publicadoNoCatalogo = true;

      final status = await ProdutosFirestoreService.syncProdutoComStatus(
        p,
        lojaId: lojaId,
        bumpHiveTimestamp: false,
      );
      expect(status, ProdutoSyncRemotoStatus.confirmado);

      final snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('produtos')
          .doc(productId)
          .get();
      final data = snap.data()!;
      expect(data.containsKey('custoReal'), isFalse);
      expect(data.containsKey('variacoesExtraTipo'), isFalse);
    });
  });
}
