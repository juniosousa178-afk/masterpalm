import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/models/venda_item.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:master_palm/services/venda_combo_estoque_expansion.dart';

const _lojaId = 'nathy-pratas-e-folheados';
const _docId = 'nathy-pratas-e-folheados-colar-cora-o-tiffany';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Catálogo/WhatsApp Tiffany — estado real Firestore', () {
    late FakeFirebaseFirestore db;
    late Box<Produto> box;

    setUpAll(() async {
      Hive.init('catalogo_wa_tiffany_real_${DateTime.now().millisecondsSinceEpoch}');
      if (!Hive.isAdapterRegistered(2)) {
        Hive.registerAdapter(ProdutoAdapter());
      }
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = FakeFirebaseFirestore();
      EstoqueTransactionService.debugFirestoreOverride = db;
      ProdutosFirestoreService.debugFirestoreOverride = db;
      final name = HiveBoxNames.produtos(_lojaId);
      if (Hive.isBoxOpen(name)) await Hive.box<Produto>(name).close();
      box = await Hive.openBox<Produto>(name);
      await box.clear();
    });

    tearDown(() async {
      EstoqueTransactionService.debugFirestoreOverride = null;
      ProdutosFirestoreService.debugFirestoreOverride = null;
      if (box.isOpen) await box.close();
    });

    test('produto simples qty=3 baixa com tamanho/cor vazios (WhatsApp)', () async {
      await db
          .collection('lojas')
          .doc(_lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(_docId)
          .set({
        'nome': 'Colar Coração Tiffany',
        'slug': _docId,
        'quantidade': 3,
        'tamanhos': ['45cm V 12'],
      });

      // Hive stale com grade antiga (simula cache local desatualizado)
      final stale = Produto(
        nome: 'Colar Coração Tiffany',
        custoReal: 10,
        frete: 0,
        gastosFixos: 0,
        gastosVariaveis: 0,
        precoSugerido: 0,
        precoFinal: 89.2,
        quantidade: 1,
        precoUnitario: 89.2,
        categoria: 'Colares',
        dataEntrada: DateTime(2026, 6, 1),
        lojaId: _lojaId,
        idFirebase: _docId,
        slug: _docId,
        variacoes: {'45cm': {'sem-cor': 1}},
        estoquePorTamanho: {'45cm': 1},
      );
      await box.add(stale);

      await ProdutosFirestoreService.ensureEstoqueProdutoDocsInHive(
        lojaId: _lojaId,
        produtosBox: box,
        firebaseDocIds: [_docId],
        forceRefreshFromRemoto: true,
      );

      final refreshed = box.values.firstWhere((p) => p.idFirebase == _docId);
      expect(refreshed.usaVariacoes, isFalse);
      expect(refreshed.quantidade, 3);
      expect(refreshed.exigeSelecaoTamanhoNaVenda, isFalse);

      final itens = [
        VendaItem(
          produtoNome: 'Colar Coração Tiffany',
          quantidade: 1,
          precoUnitario: 89.2,
          tamanho: '',
          cor: '',
          lojaId: _lojaId,
          productId: _docId,
        ),
      ];
      VendaComboEstoqueExpansion.validarExpansaoParaBaixaFirestore(
        itensParaEstoque: itens,
        produtosEncontrados: [refreshed],
      );

      final txItems = VendaComboEstoqueExpansion.montarTxItemsParaBaixaEstoque(
        itensParaEstoque: itens,
        produtosEncontrados: [refreshed],
      );

      final results = await EstoqueTransactionService.baixarEstoqueTransactionBatch(
        lojaId: _lojaId,
        itens: txItems,
      );
      expect(results.single.quantidadeTotalAtualizada, 2);
    });

    test('45cm/sem-cor baixa quando Firestore usa 45 cm na grade', () async {
      await db
          .collection('lojas')
          .doc(_lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(_docId)
          .set({
        'nome': 'Colar Coração Tiffany',
        'slug': _docId,
        'quantidade': 2,
        'variacoes': {'45 cm': {'sem-cor': 2}},
        'estoquePorTamanho': {'45 cm': 2},
      });

      final p = Produto(
        nome: 'Colar Coração Tiffany',
        custoReal: 10,
        frete: 0,
        gastosFixos: 0,
        gastosVariaveis: 0,
        precoSugerido: 0,
        precoFinal: 89.2,
        quantidade: 2,
        precoUnitario: 89.2,
        categoria: 'Colares',
        dataEntrada: DateTime(2026, 6, 1),
        lojaId: _lojaId,
        idFirebase: _docId,
        slug: _docId,
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
            productId: _docId,
          ),
        ],
        produtosEncontrados: [p],
      );

      final results = await EstoqueTransactionService.baixarEstoqueTransactionBatch(
        lojaId: _lojaId,
        itens: txItems,
      );
      expect(results.single.quantidadeTotalAtualizada, 1);
    });

    test('estoque 0 retorna mensagem de estoque insuficiente', () async {
      await db
          .collection('lojas')
          .doc(_lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(_docId)
          .set({
        'nome': 'Colar Coração Tiffany',
        'quantidade': 0,
      });

      final p = Produto(
        nome: 'Colar Coração Tiffany',
        custoReal: 10,
        frete: 0,
        gastosFixos: 0,
        gastosVariaveis: 0,
        precoSugerido: 0,
        precoFinal: 89.2,
        quantidade: 0,
        precoUnitario: 89.2,
        categoria: 'Colares',
        dataEntrada: DateTime(2026, 6, 1),
        lojaId: _lojaId,
        idFirebase: _docId,
        slug: _docId,
      );
      await box.add(p);

      final txItems = VendaComboEstoqueExpansion.montarTxItemsParaBaixaEstoque(
        itensParaEstoque: [
          VendaItem(
            produtoNome: 'Colar Coração Tiffany',
            quantidade: 1,
            precoUnitario: 89.2,
            lojaId: _lojaId,
            productId: _docId,
          ),
        ],
        produtosEncontrados: [p],
      );

      expect(
        () => EstoqueTransactionService.baixarEstoqueTransactionBatch(
          lojaId: _lojaId,
          itens: txItems,
        ),
        throwsA(
          predicate(
            (e) => e.toString().toLowerCase().contains('estoque insuficiente'),
          ),
        ),
      );
    });
  });
}
