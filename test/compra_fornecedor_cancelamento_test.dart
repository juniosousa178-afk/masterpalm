import 'dart:io';



import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:hive/hive.dart';

import 'package:master_palm/core/hive_box_names.dart';

import 'package:master_palm/models/compra_fornecedor.dart';

import 'package:master_palm/models/compra_fornecedor_constants.dart';

import 'package:master_palm/models/compra_fornecedor_item.dart';

import 'package:master_palm/models/conta_pagar.dart';
import 'package:master_palm/models/conta_pagar_constants.dart';

import 'package:master_palm/models/lancamento_financeiro.dart';

import 'package:master_palm/models/produto.dart';

import 'package:master_palm/services/compra_fornecedor_cancelamento_service.dart';

import 'package:master_palm/services/compra_fornecedor_estorno_snapshot.dart';

import 'package:master_palm/services/conta_pagar_hive_store.dart';

import 'package:master_palm/services/conta_pagar_service.dart';

import 'package:master_palm/services/estoque_service.dart';

import 'package:master_palm/services/estoque_transaction_service.dart';

import 'package:master_palm/services/financeiro_hive_store.dart';

import 'package:master_palm/services/firestore_paths.dart';

import 'package:shared_preferences/shared_preferences.dart';



void main() {

  const lojaId = 'loja_canc_test';

  const produtoId = 'prod-estorno-1';



  late Directory hiveDir;

  late FakeFirebaseFirestore fakeFs;



  setUpAll(() async {

    TestWidgetsFlutterBinding.ensureInitialized();

    SharedPreferences.setMockInitialValues({});

    hiveDir = await Directory.systemTemp.createTemp('hive_canc_compra_');

    Hive.init(hiveDir.path);

    ContaPagarHiveStore.ensureAdapterRegistered();

    if (!Hive.isAdapterRegistered(32)) {

      Hive.registerAdapter(CompraFornecedorAdapter());

    }

    if (!Hive.isAdapterRegistered(33)) {

      Hive.registerAdapter(CompraFornecedorItemAdapter());

    }

    if (!Hive.isAdapterRegistered(2)) {

      Hive.registerAdapter(ProdutoAdapter());

    }

    if (!Hive.isAdapterRegistered(30)) {

      Hive.registerAdapter(LancamentoFinanceiroAdapter());

    }

  });



  tearDownAll(() async {

    EstoqueTransactionService.debugFirestoreOverride = null;

    await Hive.close();

    if (await hiveDir.exists()) {

      await hiveDir.delete(recursive: true);

    }

  });



  setUp(() {

    fakeFs = FakeFirebaseFirestore();

    EstoqueTransactionService.debugFirestoreOverride = fakeFs;

  });



  tearDown(() async {
    EstoqueTransactionService.debugFirestoreOverride = null;
    Future<void> clearBox<T>(String name) async {
      if (!Hive.isBoxOpen(name)) return;
      await Hive.box<T>(name).clear();
    }

    await clearBox<CompraFornecedor>(HiveBoxNames.comprasFornecedor(lojaId));
    await clearBox<ContaPagar>(HiveBoxNames.contasPagar(lojaId));
    await clearBox<Produto>(HiveBoxNames.produtos(lojaId));
    await clearBox<LancamentoFinanceiro>(
      HiveBoxNames.lancamentosFinanceiros(lojaId),
    );
  });

  Future<Box<CompraFornecedor>> _openCompraBox() async {
    final name = HiveBoxNames.comprasFornecedor(lojaId);
    if (Hive.isBoxOpen(name)) return Hive.box<CompraFornecedor>(name);
    return Hive.openBox<CompraFornecedor>(name);
  }

  Future<Box<Produto>> _openProdutoBox() async {
    final name = HiveBoxNames.produtos(lojaId);
    if (Hive.isBoxOpen(name)) return Hive.box<Produto>(name);
    return Hive.openBox<Produto>(name);
  }

  Produto _produtoNoBox(Box<Produto> box) =>
      box.values.firstWhere((p) => p.idFirebase == produtoId);



  Future<void> _seedFirestoreEstoque({

    required int quantidade,

    double custoReal = 0,

  }) async {

    await fakeFs

        .collection('lojas')

        .doc(lojaId)

        .collection(FSPaths.estoqueProdutosCol)

        .doc(produtoId)

        .set({

      'nome': 'Produto Estorno',

      'slug': produtoId,

      'quantidade': quantidade,

      'custoReal': custoReal,

      'lojaId': lojaId,

    });

  }



  Produto _produtoHive({required int quantidade, double custoReal = 0}) {

    return Produto(

      nome: 'Produto Estorno',

      custoReal: custoReal,

      frete: 0,

      gastosFixos: 0,

      gastosVariaveis: 0,

      precoSugerido: 0,

      precoFinal: 0,

      quantidade: quantidade,

      precoUnitario: 0,

      categoria: 'Teste',

      dataEntrada: DateTime(2026, 1, 1),

      lojaId: lojaId,

      idFirebase: produtoId,

      slug: produtoId,

    );

  }



  CompraFornecedorItem _itemComEntrada({

    int quantidade = 3,

    double custoEntrada = 15,

    double custoAnterior = 10,

    int estoqueAnterior = 5,

  }) {

    return CompraFornecedorItem(

      produtoNome: 'Produto Estorno',

      quantidade: quantidade,

      custoUnitario: custoEntrada,

      productId: produtoId,

      itemCompraId: 'item-1',

      estoqueEntradaRegistrada: true,

      estoqueSnapshotOk: true,

      estoqueAnterior: estoqueAnterior,

      custoAnterior: custoAnterior,

      custoEntradaRegistrado: custoEntrada,

    );

  }



  CompraFornecedor _compraBase({

    required String id,

    String tipo = CompraFornecedorTipo.financeira,

    List<CompraFornecedorItem>? itens,

    bool estoqueIntegrado = false,

  }) {

    return CompraFornecedor(

      id: id,

      lojaId: lojaId,

      fornecedorHiveKey: 1,

      fornecedorNome: 'Forn',

      dataCompra: DateTime(2026, 3, 1),

      tipoCompra: tipo,

      valorInformado: 300,

      statusCompra: CompraFornecedorStatusCompra.confirmada,

      itens: itens,

      estoqueIntegrado: estoqueIntegrado,

    );

  }



  group('CompraFornecedorEstornoSnapshot', () {

    test('estoque insuficiente quando saldo menor que entrada', () {

      final p = _produtoHive(quantidade: 2);

      final item = _itemComEntrada(quantidade: 5);

      expect(

        CompraFornecedorEstornoSnapshot.estoqueSuficienteParaEstorno(p, item),

        isFalse,

      );

    });



    test('pode restaurar custo quando atual igual ao custoEntrada', () {

      final p = _produtoHive(quantidade: 10, custoReal: 15);

      final item = _itemComEntrada(custoEntrada: 15, custoAnterior: 10);

      expect(

        CompraFornecedorEstornoSnapshot.podeRestaurarCusto(item, p),

        isTrue,

      );

    });



    test('não restaura custo quando houve alteração posterior', () {

      final p = _produtoHive(quantidade: 10, custoReal: 22);

      final item = _itemComEntrada(custoEntrada: 15, custoAnterior: 10);

      expect(

        CompraFornecedorEstornoSnapshot.podeRestaurarCusto(item, p),

        isFalse,

      );

    });

  });



  group('EstoqueService — operação estorno_compra', () {

    test('aceita estorno_compra e mensagem não é baixa manual', () async {

      await _seedFirestoreEstoque(quantidade: 10);

      final prodBox = await _openProdutoBox();

      prodBox.add(_produtoHive(quantidade: 10));



      final r = await EstoqueService.atualizarEstoque(

        produtosBox: prodBox,

        lojaId: lojaId,

        produtoId: produtoId,

        tamanho: '',

        cor: '',

        quantidade: 2,

        operacao: EstoqueOperacaoCompra.estornoCompra,

      );



      expect(r.sucesso, isTrue);

      expect(r.mensagem, contains('Estorno de compra aplicado'));

      expect(r.mensagem, isNot(contains('baixado com sucesso')));

    });

  });



  group('CompraFornecedorCancelamentoService', () {

    test('financeira cancelada não exige aviso de estorno', () {

      final c = _compraBase(id: 'fin-1');

      expect(

        CompraFornecedorCancelamentoService.exigeAvisoEstornoNaConfirmacao(c),

        isFalse,

      );

    });



    test('revenda sem detalhamento cancela sem estorno', () async {

      final box = await _openCompraBox();

      await box.put(

        'rev-sem-det',

        _compraBase(

          id: 'rev-sem-det',

          tipo: CompraFornecedorTipo.revendaDetalharDepois,

          itens: const [],

        ),

      );



      final r = await CompraFornecedorCancelamentoService.cancelar(

        lojaId: lojaId,

        compraId: 'rev-sem-det',

      );

      expect(r.sucesso, isTrue);

      expect(r.estoqueEstornado, isFalse);

      expect(box.get('rev-sem-det')!.estaCancelada, isTrue);

    });



    test('revenda com item sem snapshot bloqueia estorno automático', () async {

      final box = await _openCompraBox();

      await box.put(

        'rev-sem-snap',

        _compraBase(

          id: 'rev-sem-snap',

          tipo: CompraFornecedorTipo.revendaDetalharDepois,

          itens: [

            CompraFornecedorItem(

              produtoNome: 'X',

              quantidade: 2,

              custoUnitario: 10,

              estoqueEntradaRegistrada: true,

              estoqueSnapshotOk: false,

            ),

          ],

        ),

      );



      final r = await CompraFornecedorCancelamentoService.cancelar(

        lojaId: lojaId,

        compraId: 'rev-sem-snap',

      );

      expect(r.sucesso, isFalse);

      expect(r.mensagem, contains('dados suficientes'));

      expect(box.get('rev-sem-snap')!.estaCancelada, isFalse);

    });



    test('estoque insuficiente bloqueia cancelamento e mantém CP', () async {

      final compraBox = await _openCompraBox();

      final prodBox = await _openProdutoBox();

      await _seedFirestoreEstoque(quantidade: 2);

      prodBox.add(_produtoHive(quantidade: 2));



      final compra = _compraBase(

        id: 'est-insuf',

        tipo: CompraFornecedorTipo.revendaDetalharDepois,

        itens: [_itemComEntrada(quantidade: 5)],

      );

      await compraBox.put(compra.id, compra);



      await ContaPagarService.gerarParcelasCompra(

        lojaId: lojaId,

        compra: compra,

        numeroParcelas: 2,

        primeiroVencimento: DateTime(2026, 4, 1),

      );



      final r = await CompraFornecedorCancelamentoService.cancelar(

        lojaId: lojaId,

        compraId: compra.id,

      );



      expect(r.sucesso, isFalse);

      expect(r.mensagem, contains('movimentados/vendidos'));

      expect(compraBox.get(compra.id)!.estaCancelada, isFalse);



      final cpBox = await ContaPagarHiveStore.openBox(lojaId);

      final parcelas =

          ContaPagarService.listar(cpBox!, lojaId, compraId: compra.id);

      expect(

        parcelas.any((c) => c.status != ContaPagarStatus.cancelado),

        isTrue,

      );

      expect(_produtoNoBox(prodBox).quantidade, 2);

    });



    test('estoque suficiente estorna e cancela CP', () async {

      final compraBox = await _openCompraBox();

      final prodBox = await _openProdutoBox();

      await _seedFirestoreEstoque(quantidade: 10, custoReal: 15);

      final prod = _produtoHive(quantidade: 10, custoReal: 15);

      prodBox.add(prod);

      await prod.save();



      final compra = _compraBase(

        id: 'est-ok',

        tipo: CompraFornecedorTipo.revendaDetalharDepois,

        itens: [_itemComEntrada(quantidade: 3, custoEntrada: 15, custoAnterior: 10)],

      );

      await compraBox.put(compra.id, compra);



      await ContaPagarService.gerarParcelasCompra(

        lojaId: lojaId,

        compra: compra,

        numeroParcelas: 2,

        primeiroVencimento: DateTime(2026, 4, 1),

      );



      final r = await CompraFornecedorCancelamentoService.cancelar(

        lojaId: lojaId,

        compraId: compra.id,

      );



      expect(r.sucesso, isTrue);

      expect(r.estoqueEstornado, isTrue);

      expect(r.parcelasCanceladas, 2);

      expect(compraBox.get(compra.id)!.estaCancelada, isTrue);

      expect(_produtoNoBox(prodBox).quantidade, 7);

      expect(_produtoNoBox(prodBox).custoReal, closeTo(10, 0.01));

      expect(r.custosNaoRestaurados, isEmpty);



      final fsSnap = await fakeFs

          .collection('lojas')

          .doc(lojaId)

          .collection(FSPaths.estoqueProdutosCol)

          .doc(produtoId)

          .get();

      expect((fsSnap.data()?['quantidade'] as num?)?.toInt(), 7);

    });



    test('custo alterado depois não é sobrescrito no cancelamento', () async {

      final compraBox = await _openCompraBox();

      final prodBox = await _openProdutoBox();

      await _seedFirestoreEstoque(quantidade: 10, custoReal: 22);

      final prod = _produtoHive(quantidade: 10, custoReal: 22);

      prodBox.add(prod);

      await prod.save();



      final compra = _compraBase(

        id: 'custo-nao-rest',

        tipo: CompraFornecedorTipo.revendaDetalharDepois,

        itens: [_itemComEntrada(custoEntrada: 15, custoAnterior: 10)],

      );

      await compraBox.put(compra.id, compra);



      final r = await CompraFornecedorCancelamentoService.cancelar(

        lojaId: lojaId,

        compraId: compra.id,

      );



      expect(r.sucesso, isTrue);

      expect(r.estoqueEstornado, isTrue);

      expect(_produtoNoBox(prodBox).custoReal, closeTo(22, 0.01));

      expect(r.custosNaoRestaurados, contains('Produto Estorno'));

      expect(r.mensagem, contains('Custo não restaurado'));

    });



    test('parcelada cancelada cancela CP vinculadas', () async {

      final box = await _openCompraBox();

      final compra = _compraBase(id: 'cp-canc', tipo: CompraFornecedorTipo.financeira);

      await box.put(compra.id, compra);



      await ContaPagarService.gerarParcelasCompra(

        lojaId: lojaId,

        compra: compra,

        numeroParcelas: 3,

        primeiroVencimento: DateTime(2026, 4, 1),

      );



      final r = await CompraFornecedorCancelamentoService.cancelar(

        lojaId: lojaId,

        compraId: compra.id,

      );

      expect(r.sucesso, isTrue);

      expect(r.parcelasCanceladas, 3);



      final cpBox = await ContaPagarHiveStore.openBox(lojaId);

      final list = ContaPagarService.listar(cpBox!, lojaId, compraId: compra.id);

      expect(list.every((c) => c.status == ContaPagarStatus.cancelado), isTrue);

    });



    test('revenda detalhada cancelada não cria LF extra', () async {

      final compraBox = await _openCompraBox();

      final prodBox = await _openProdutoBox();

      await _seedFirestoreEstoque(quantidade: 8);

      prodBox.add(_produtoHive(quantidade: 8));



      final compra = _compraBase(

        id: 'rev-lf',

        tipo: CompraFornecedorTipo.revendaDetalharDepois,

        itens: [_itemComEntrada(quantidade: 2)],

      );

      await compraBox.put(compra.id, compra);



      await ContaPagarService.gerarParcelasCompra(

        lojaId: lojaId,

        compra: compra,

        numeroParcelas: 2,

        primeiroVencimento: DateTime(2026, 5, 1),

      );



      final finBox = await FinanceiroHiveStore.openLancamentosBox(lojaId);

      final lfAntes = finBox?.length ?? 0;



      final r = await CompraFornecedorCancelamentoService.cancelar(

        lojaId: lojaId,

        compraId: compra.id,

      );



      expect(r.sucesso, isTrue);

      expect(finBox?.length ?? 0, lfAntes);

    });



    test('parse tam/cor da observação revenda', () {

      final p = CompraFornecedorEstornoSnapshot.parseTamCorObservacao(

        'origem:compra_revenda_detalhar_depois · tam:M · cor:Azul',

      );

      expect(p.tam, 'M');

      expect(p.cor, 'Azul');

    });



    test('operacao de estorno não é baixa', () {

      expect(EstoqueOperacaoCompra.estornoCompra, 'estorno_compra');

      expect(EstoqueOperacaoCompra.estornoCompra, isNot('baixa'));

    });

  });

}


