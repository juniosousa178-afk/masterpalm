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

const _lojaId = 'loja-catalogo-wa-test';

Produto _produtoHive({
  required String id,
  required String nome,
  Map<String, dynamic>? variacoes,
}) {
  return Produto(
    nome: nome,
    custoReal: 10,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 0,
    precoFinal: 50,
    quantidade: 5,
    precoUnitario: 50,
    categoria: 'Joias',
    dataEntrada: DateTime(2026, 6, 9),
    lojaId: _lojaId,
    idFirebase: id,
    slug: id,
    variacoes: variacoes,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Catálogo/WhatsApp — baixa por productId e variação', () {
    late FakeFirebaseFirestore db;
    late Box<Produto> box;

    setUpAll(() async {
      Hive.init('catalogo_wa_baixa_${DateTime.now().millisecondsSinceEpoch}');
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

    test('monta txItems com productId estável (não depende de nomeSnapshot)', () {
      final p = _produtoHive(
        id: 'doc-estavel-123',
        nome: 'Nome Antigo No Snapshot',
        variacoes: {'sem-tamanho': {'Pink': 3}},
      );
      final itens = [
        VendaItem(
          produtoNome: 'Nome Diferente Snapshot',
          quantidade: 1,
          precoUnitario: 50,
          cor: 'Pink',
          lojaId: _lojaId,
          productId: 'doc-estavel-123',
        ),
      ];
      final tx = VendaComboEstoqueExpansion.montarTxItemsParaBaixaEstoque(
        itensParaEstoque: itens,
        produtosEncontrados: [p],
      );
      expect(tx.single['productId'], 'doc-estavel-123');
      expect(tx.single['cor'], 'Pink');
    });

    test('baixa batch reduz estoque remoto após confirmação (fluxo PosPagamento)', () async {
      const docId = 'wa-prod-1';
      await db
          .collection('lojas')
          .doc(_lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(docId)
          .set({
        'nome': 'Brinco Coração',
        'quantidade': 4,
        'variacoes': {
          'sem-tamanho': {'Dourado': 4},
        },
        'estoquePorTamanho': {'sem-tamanho': 4},
      });

      final p = _produtoHive(
        id: docId,
        nome: 'Brinco Coração',
        variacoes: {'sem-tamanho': {'Dourado': 4}},
      );
      await box.add(p);

      final txItems = VendaComboEstoqueExpansion.montarTxItemsParaBaixaEstoque(
        itensParaEstoque: [
          VendaItem(
            produtoNome: 'Outro Nome No Pedido',
            quantidade: 2,
            precoUnitario: 40,
            cor: 'Dourado',
            lojaId: _lojaId,
            productId: docId,
          ),
        ],
        produtosEncontrados: [p],
      );

      final results = await EstoqueTransactionService.baixarEstoqueTransactionBatch(
        lojaId: _lojaId,
        itens: txItems,
      );
      expect(results.single.quantidadeTotalAtualizada, 2);

      final snap = await db
          .collection('lojas')
          .doc(_lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(docId)
          .get();
      expect(snap.data()?['quantidade'], 2);
      final vars = snap.data()?['variacoes'] as Map?;
      expect(vars?['sem-tamanho']?['Dourado'], 2);
    });
  });
}
