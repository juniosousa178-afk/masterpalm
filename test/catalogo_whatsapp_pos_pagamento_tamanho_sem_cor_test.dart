import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/models/venda_item.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/venda_combo_estoque_expansion.dart';

const _lojaId = 'loja-wa-tam-sem-cor';

Produto _produtoHive({
  required String id,
  required String nome,
  Map<String, dynamic>? variacoes,
  Map<String, int> estoquePorTamanho = const {},
}) {
  return Produto(
    nome: nome,
    custoReal: 10,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 0,
    precoFinal: 89.2,
    quantidade: 3,
    precoUnitario: 89.2,
    categoria: 'Colares',
    dataEntrada: DateTime(2026, 6, 9),
    lojaId: _lojaId,
    idFirebase: id,
    slug: id,
    variacoes: variacoes,
    estoquePorTamanho: estoquePorTamanho,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Catálogo/WhatsApp — Tam 45cm + Cor sem-cor (pós-pagamento)', () {
    late FakeFirebaseFirestore db;
    late Box<Produto> box;

    setUpAll(() async {
      Hive.init('catalogo_wa_pos_${DateTime.now().millisecondsSinceEpoch}');
      if (!Hive.isAdapterRegistered(2)) {
        Hive.registerAdapter(ProdutoAdapter());
      }
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = FakeFirebaseFirestore();
      EstoqueTransactionService.debugFirestoreOverride = db;
      final name = HiveBoxNames.produtos(_lojaId);
      if (Hive.isBoxOpen(name)) {
        await Hive.box<Produto>(name).close();
      }
      box = await Hive.openBox<Produto>(name);
      await box.clear();
    });

    tearDown(() async {
      EstoqueTransactionService.debugFirestoreOverride = null;
      if (box.isOpen) await box.close();
    });

    test('baixa 45cm/sem-cor quando Firestore usa chave 45 cm (espaço)', () async {
      const docId = 'colar-tiffany';
      await db
          .collection('lojas')
          .doc(_lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(docId)
          .set({
        'nome': 'Colar Coração Tiffany',
        'quantidade': 2,
        'variacoes': {
          '45 cm': {'sem-cor': 2},
        },
        'estoquePorTamanho': {'45 cm': 2},
      });

      final p = _produtoHive(
        id: docId,
        nome: 'Colar Coração Tiffany',
        variacoes: {'45 cm': {'sem-cor': 2}},
        estoquePorTamanho: {'45 cm': 2},
      );
      await box.add(p);

      final txItems = VendaComboEstoqueExpansion.montarTxItemsParaBaixaEstoque(
        itensParaEstoque: [
          VendaItem(
            produtoNome: 'Colar Coração Tiffany',
            quantidade: 1,
            precoUnitario: 89.2,
            tamanho: '45cm',
            cor: 'sem-cor',
            lojaId: _lojaId,
            productId: docId,
          ),
        ],
        produtosEncontrados: [p],
      );

      expect(txItems.single['tamanho'], '45cm');
      expect(txItems.single['cor'], 'sem-cor');

      final results = await EstoqueTransactionService.baixarEstoqueTransactionBatch(
        lojaId: _lojaId,
        itens: txItems,
      );
      expect(results.single.quantidadeTotalAtualizada, 1);

      final snap = await db
          .collection('lojas')
          .doc(_lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(docId)
          .get();
      expect(snap.data()?['quantidade'], 1);
      final vars = snap.data()?['variacoes'] as Map?;
      expect(vars?['45 cm']?['sem-cor'], 1);
    });

    test('baixa por estoquePorTamanho quando variacoes não tem sem-cor', () async {
      const docId = 'colar-solo-tam';
      await db
          .collection('lojas')
          .doc(_lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(docId)
          .set({
        'nome': 'Colar Solo Tam',
        'quantidade': 3,
        'estoquePorTamanho': {'45cm': 3},
      });

      final results = await EstoqueTransactionService.baixarEstoqueTransaction(
        lojaId: _lojaId,
        produtoId: docId,
        quantidade: 1,
        tamanho: '45cm',
        cor: 'sem-cor',
      );

      expect(results.quantidadeTotalAtualizada, 2);
      final snap = await db
          .collection('lojas')
          .doc(_lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(docId)
          .get();
      expect(snap.data()?['estoquePorTamanho']?['45cm'], 2);
    });

    test('produto com cor real continua baixando pela cor informada', () async {
      const docId = 'anel-tam-cor';
      await db
          .collection('lojas')
          .doc(_lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(docId)
          .set({
        'nome': 'Anel',
        'quantidade': 4,
        'variacoes': {
          '18': {'Dourado': 2, 'Prata': 2},
        },
      });

      await EstoqueTransactionService.baixarEstoqueTransaction(
        lojaId: _lojaId,
        produtoId: docId,
        quantidade: 1,
        tamanho: '18',
        cor: 'Prata',
      );

      final snap = await db
          .collection('lojas')
          .doc(_lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(docId)
          .get();
      final vars = snap.data()?['variacoes'] as Map?;
      expect(vars?['18']?['Prata'], 1);
      expect(vars?['18']?['Dourado'], 2);
    });

    test('resolverChaveNoMapa alinha 45cm com 45 cm', () {
      final map = {'45 cm': 2, '60 cm': 1};
      expect(
        EstoqueTransactionService.resolverChaveNoMapaParaTeste(map, '45cm'),
        '45 cm',
      );
    });
  });
}
