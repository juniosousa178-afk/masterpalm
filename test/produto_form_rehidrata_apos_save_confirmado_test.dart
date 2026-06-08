import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _lojaId = 'loja-rehydrate-pos-save';
const _docId = 'anel-rehydrate-pos-save';

Produto _produtoLocalStale() {
  return Produto(
    nome: 'Anel Coração Meigo Rose',
    custoReal: 25,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 0,
    precoFinal: 89.9,
    quantidade: 1,
    precoUnitario: 89.9,
    categoria: 'Anel',
    dataEntrada: DateTime(2026, 6, 8),
    descricao: 'Descricao antiga no Hive',
    lojaId: _lojaId,
    idFirebase: _docId,
    slug: _docId,
    publicadoNoCatalogo: true,
    variacoes: null,
    estoquePorTamanho: const {},
    tamanhos: const [],
    updatedAt: DateTime(2026, 6, 7),
    custoEditadoNoCadastro: true,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory hiveDir;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    hiveDir = Directory.systemTemp.createTempSync('rehydrate_pos_save_');
    Hive.init(hiveDir.path);
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(ProdutoAdapter());
    }
  });

  tearDown(() {
    ProdutosFirestoreService.debugFirestoreOverride = null;
  });

  tearDownAll(() {
    try {
      hiveDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<Produto> _adicionarEmBox(Produto template) async {
    final box = await Hive.openBox<Produto>('produtos_$_lojaId');
    await box.clear();
    await box.add(template);
    return box.getAt(0)!;
  }

  test('reidrata Hive com documento remoto canônico preservando grade', () async {
    final fake = FakeFirebaseFirestore();
    ProdutosFirestoreService.debugFirestoreOverride = fake;

    final p = await _adicionarEmBox(_produtoLocalStale());

    const descricaoRemota = 'TESTE FIRESTORE PATH 20260608 20:30';
    await fake
        .collection('lojas')
        .doc(_lojaId)
        .collection('estoque_produtos')
        .doc(_docId)
        .set({
      'id': _docId,
      'nome': p.nome,
      'descricao': descricaoRemota,
      'quantidade': 4,
      'preco': 89.9,
      'custoReal': 25,
      'custoEditadoNoCadastro': true,
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
      },
      'publicadoNoCatalogo': true,
      'updatedAt': Timestamp.fromDate(DateTime(2026, 6, 8, 20, 30)),
    });

    final result = await ProdutosFirestoreService
        .rehydrateProdutoConfirmadoFromEstoqueRemoto(
      p,
      lojaId: _lojaId,
    );

    expect(result.sucesso, isTrue);
    expect(p.descricao, descricaoRemota);
    expect(p.quantidade, 4);
    expect(p.variacoes?['20']?['rosa'], 1);
    expect(p.variacoes?['22']?['rosa'], 1);
    expect(p.estoquePorTamanho['20'], 1);
    expect(p.estoquePorTamanho['22'], 1);
    expect(p.tamanhos, containsAll(['20', '22']));
    expect(p.custoReal, 25);
    expect(p.updatedAt, DateTime(2026, 6, 8, 20, 30));
  });

  test('reidratação com doc ausente retorna aviso não bloqueante', () async {
    final fake = FakeFirebaseFirestore();
    ProdutosFirestoreService.debugFirestoreOverride = fake;
    final p = await _adicionarEmBox(_produtoLocalStale());

    final result = await ProdutosFirestoreService
        .rehydrateProdutoConfirmadoFromEstoqueRemoto(
      p,
      lojaId: _lojaId,
    );

    expect(result.sucesso, isFalse);
    expect(result.aviso, isNotNull);
    expect(p.descricao, 'Descricao antiga no Hive');
  });

  test('produto simples sem grade reidrata descricao e quantidade', () async {
    final fake = FakeFirebaseFirestore();
    ProdutosFirestoreService.debugFirestoreOverride = fake;

    final template = Produto(
      nome: 'Pulseira Simples',
      custoReal: 10,
      frete: 0,
      gastosFixos: 0,
      gastosVariaveis: 0,
      precoSugerido: 0,
      precoFinal: 40,
      quantidade: 1,
      precoUnitario: 40,
      categoria: 'Pulseira',
      dataEntrada: DateTime(2026, 6, 8),
      descricao: 'Antiga',
      lojaId: _lojaId,
      idFirebase: 'pulseira-simples',
      slug: 'pulseira-simples',
      updatedAt: DateTime(2026, 6, 7),
      custoEditadoNoCadastro: true,
    );
    final p = await _adicionarEmBox(template);

    await fake
        .collection('lojas')
        .doc(_lojaId)
        .collection('estoque_produtos')
        .doc('pulseira-simples')
        .set({
      'id': 'pulseira-simples',
      'nome': p.nome,
      'descricao': 'Nova descricao simples',
      'quantidade': 7,
      'preco': 40,
      'custoReal': 10,
      'updatedAt': Timestamp.fromDate(DateTime(2026, 6, 8, 21)),
    });

    final result = await ProdutosFirestoreService
        .rehydrateProdutoConfirmadoFromEstoqueRemoto(
      p,
      lojaId: _lojaId,
    );

    expect(result.sucesso, isTrue);
    expect(p.descricao, 'Nova descricao simples');
    expect(p.quantidade, 7);
  });
}
