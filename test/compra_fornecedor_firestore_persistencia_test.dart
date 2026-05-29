import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/models/compra_fornecedor.dart';
import 'package:master_palm/models/compra_fornecedor_constants.dart';
import 'package:master_palm/models/compra_fornecedor_item.dart';
import 'package:master_palm/models/conta_pagar.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/compra_fornecedor_firestore_service.dart';
import 'package:master_palm/services/compra_revenda_detalhamento_service.dart';
import 'package:master_palm/services/conta_pagar_hive_store.dart';
import 'package:master_palm/services/conta_pagar_service.dart';
import 'package:master_palm/services/conta_receber_recebimento_caixa_service.dart';
import 'package:master_palm/services/estoque_service.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/services/financeiro_firestore_service.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const lojaId = 'loja_fs_persist';
  const produtoId = 'prod-fs-1';
  const compraId = 'compra-fs-rev';

  late Directory hiveDir;
  late FakeFirebaseFirestore fakeFs;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    hiveDir = await Directory.systemTemp.createTemp('hive_fs_persist_');
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
    CompraFornecedorFirestoreService.debugFirestoreOverride = null;
    EstoqueTransactionService.debugFirestoreOverride = null;
    EstoqueService.debugFirestoreOverride = null;
    ProdutosFirestoreService.debugFirestoreOverride = null;
    FinanceiroFirestoreService.debugFirestoreOverride = null;
    await Hive.close();
    if (await hiveDir.exists()) {
      await hiveDir.delete(recursive: true);
    }
  });

  setUp(() {
    fakeFs = FakeFirebaseFirestore();
    CompraFornecedorFirestoreService.debugFirestoreOverride = fakeFs;
    EstoqueTransactionService.debugFirestoreOverride = fakeFs;
    EstoqueService.debugFirestoreOverride = fakeFs;
    ProdutosFirestoreService.debugFirestoreOverride = fakeFs;
    FinanceiroFirestoreService.debugFirestoreOverride = fakeFs;
  });

  tearDown(() async {
    CompraFornecedorFirestoreService.debugFirestoreOverride = null;
    EstoqueTransactionService.debugFirestoreOverride = null;
    EstoqueService.debugFirestoreOverride = null;
    ProdutosFirestoreService.debugFirestoreOverride = null;
    FinanceiroFirestoreService.debugFirestoreOverride = null;
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

  CompraFornecedor compraRevendaBase() {
    return CompraFornecedor(
      id: compraId,
      lojaId: lojaId,
      fornecedorHiveKey: 3,
      fornecedorNome: 'Forn FS',
      dataCompra: DateTime(2026, 4, 1),
      tipoCompra: CompraFornecedorTipo.revendaDetalharDepois,
      valorInformado: 500,
      statusCompra: CompraFornecedorStatusCompra.confirmada,
      statusDetalhamentoProdutos:
          CompraFornecedorStatusDetalhamento.aguardandoDetalhamento,
    );
  }

  CompraFornecedorItem itemDetalhado({
    String itemId = 'item-fs-1',
    int qtd = 4,
    double custo = 25,
    int estoqueAnterior = 2,
  }) {
    return CompraFornecedorItem(
      produtoNome: 'Prod FS',
      quantidade: qtd,
      custoUnitario: custo,
      productId: produtoId,
      itemCompraId: itemId,
      observacaoItem: 'origem:compra_revenda_detalhar_depois',
      estoqueEntradaRegistrada: true,
      estoqueSnapshotOk: true,
      estoqueAnterior: estoqueAnterior,
      custoAnterior: 10,
      custoEntradaRegistrado: custo,
      tamanhoEntrada: 'M',
      corEntrada: 'Azul',
    );
  }

  Produto produtoHive({int qtd = 6, double custo = 25}) {
    return Produto(
      nome: 'Prod FS',
      custoReal: custo,
      frete: 0,
      gastosFixos: 0,
      gastosVariaveis: 0,
      precoSugerido: 0,
      precoFinal: 0,
      quantidade: qtd,
      precoUnitario: 0,
      categoria: 'Teste',
      dataEntrada: DateTime(2026, 1, 1),
      lojaId: lojaId,
      idFirebase: produtoId,
      slug: produtoId,
    );
  }

  Future<void> seedEstoqueRemoto(int qtd, {double custo = 25}) async {
    await fakeFs
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.estoqueProdutosCol)
        .doc(produtoId)
        .set({
      'nome': 'Prod FS',
      'slug': produtoId,
      'quantidade': qtd,
      'custoReal': custo,
      'lojaId': lojaId,
    });
  }

  group('CompraFornecedor — serialização Firestore', () {
    test('revenda detalhar depois salva tipo e status no Firestore', () async {
      final compra = compraRevendaBase();
      await CompraFornecedorFirestoreService.upsertCompra(compra);

      final remota = await CompraFornecedorFirestoreService.lerCompra(
        lojaId,
        compraId,
      );
      expect(remota, isNotNull);
      expect(remota!.tipoCompra, CompraFornecedorTipo.revendaDetalharDepois);
      expect(
        remota.statusDetalhamentoProdutos,
        CompraFornecedorStatusDetalhamento.aguardandoDetalhamento,
      );
      expect(remota.valorInformado, 500);

      final raw = await CompraFornecedorFirestoreService.docRef(lojaId, compraId)
          .get();
      expect(raw.data()?['schemaVersion'], 3);
    });

    test('item detalhado persiste snapshot completo no Firestore', () async {
      final item = itemDetalhado();
      final compra = compraRevendaBase().copyWith(
        itens: [item],
        valorProdutosDetalhados: 100,
        quantidadeItensDetalhados: 1,
      );
      await CompraFornecedorFirestoreService.upsertCompra(compra);

      final rawItem = (await CompraFornecedorFirestoreService.docRef(
        lojaId,
        compraId,
      ).get())
          .data()!
          .cast<String, dynamic>()['itens']
          .first as Map<String, dynamic>;

      expect(rawItem['productId'], produtoId);
      expect(rawItem['estoqueEntradaRegistrada'], isTrue);
      expect(rawItem['estoqueSnapshotOk'], isTrue);
      expect(rawItem['estoqueAnterior'], 2);
      expect(rawItem['estoqueDepois'], 6);
      expect(rawItem['custoEntradaRegistrado'], 25);
      expect(rawItem['tamanhoEntrada'], 'M');
      expect(rawItem['corEntrada'], 'Azul');
      expect(rawItem['itemCompraId'], 'item-fs-1');

      final remota = await CompraFornecedorFirestoreService.lerCompra(
        lojaId,
        compraId,
      );
      final lido = remota!.itensOuVazio.single;
      expect(lido.estoqueSnapshotOk, isTrue);
      expect(lido.tamanhoEntrada, 'M');
      expect(lido.observacaoItem, contains('revenda_detalhar_depois'));
    });

    test('cancelamento persiste status e campos de cancelamento', () async {
      final cancelada = compraRevendaBase().copyWith(
        statusCompra: CompraFornecedorStatusCompra.cancelada,
        canceladaEm: DateTime(2026, 4, 10, 14, 30),
        canceladaMotivo: 'Erro operacional',
        cancelamentoEstoqueAplicado: true,
      );
      await CompraFornecedorFirestoreService.upsertCompra(cancelada);

      final remota = await CompraFornecedorFirestoreService.lerCompra(
        lojaId,
        compraId,
      );
      expect(remota!.statusCompra, CompraFornecedorStatusCompra.cancelada);
      expect(remota.canceladaMotivo, 'Erro operacional');
      expect(remota.cancelamentoEstoqueAplicado, isTrue);
      expect(remota.canceladaEm, isNotNull);
    });

    test('round-trip preserva dados para cancelar/editar depois', () async {
      final original = compraRevendaBase().copyWith(
        itens: [itemDetalhado()],
      );
      await CompraFornecedorFirestoreService.upsertCompra(original);
      final remota = await CompraFornecedorFirestoreService.lerCompra(
        lojaId,
        compraId,
      );

      expect(remota!.itensOuVazio.single.estoqueEntradaRegistrada, isTrue);
      expect(remota.itensOuVazio.single.itemCompraId, 'item-fs-1');
      expect(remota.ehCompraRevendaDetalharDepois, isTrue);
    });
  });

  group('Revenda detalhar — fluxo com Firestore', () {
    test('vincular produto persiste compra e estoque no Firestore', () async {
      await seedEstoqueRemoto(0);
      final prodBox = await Hive.openBox<Produto>(HiveBoxNames.produtos(lojaId));
      await prodBox.clear();
      await prodBox.add(produtoHive(qtd: 0));

      final compraBox =
          await Hive.openBox<CompraFornecedor>(HiveBoxNames.comprasFornecedor(lojaId));
      await compraBox.clear();
      final compra = compraRevendaBase();
      await compraBox.put(compra.id, compra);

      final r = await CompraRevendaDetalhamentoService.vincularProdutoExistente(
        lojaId: lojaId,
        compra: compra,
        produto: prodBox.values.first,
        quantidade: 3,
        custoUnitario: 20,
      );
      expect(r.sucesso, isTrue);

      final remota = await CompraFornecedorFirestoreService.lerCompra(
        lojaId,
        compraId,
      );
      expect(remota!.itensOuVazio.length, 1);
      expect(remota.itensOuVazio.first.quantidade, 3);

      final estDoc = await fakeFs
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(produtoId)
          .get();
      expect((estDoc.data()?['quantidade'] as num?)?.toInt(), 3);
    });

    test('editar item detalhado atualiza compra no Firestore', () async {
      await seedEstoqueRemoto(4);
      final prodBox = await Hive.openBox<Produto>(HiveBoxNames.produtos(lojaId));
      await prodBox.clear();
      await prodBox.add(produtoHive(qtd: 4));

      final compra = compraRevendaBase().copyWith(
        itens: [itemDetalhado(qtd: 4, estoqueAnterior: 0)],
      );
      await CompraFornecedorFirestoreService.upsertCompra(compra);

      final edit = await CompraRevendaDetalhamentoService.editarItemDetalhadoCompra(
        lojaId: lojaId,
        compra: compra,
        itemCompraId: 'item-fs-1',
        produto: prodBox.values.first,
        quantidade: 2,
        custoUnitario: 30,
        tamanho: 'M',
        cor: 'Azul',
      );
      expect(edit.sucesso, isTrue);

      final remota = await CompraFornecedorFirestoreService.lerCompra(
        lojaId,
        compraId,
      );
      expect(remota!.itensOuVazio.single.quantidade, 2);
      expect(remota.itensOuVazio.single.custoEntradaRegistrado, 30);
    });

    test('excluir item detalhado remove da compra no Firestore', () async {
      await seedEstoqueRemoto(4);
      final prodBox = await Hive.openBox<Produto>(HiveBoxNames.produtos(lojaId));
      await prodBox.clear();
      await prodBox.add(produtoHive(qtd: 4));

      final compra = compraRevendaBase().copyWith(
        itens: [itemDetalhado(qtd: 4, estoqueAnterior: 0)],
      );
      await CompraFornecedorFirestoreService.upsertCompra(compra);

      final ex = await CompraRevendaDetalhamentoService.excluirItemDetalhadoCompra(
        lojaId: lojaId,
        compra: compra,
        itemCompraId: 'item-fs-1',
      );
      expect(ex.sucesso, isTrue);

      final remota = await CompraFornecedorFirestoreService.lerCompra(
        lojaId,
        compraId,
      );
      expect(remota!.itensOuVazio, isEmpty);
    });

    test('editar/excluir item não cria CP extra no Hive', () async {
      await seedEstoqueRemoto(10);
      final prodBox = await Hive.openBox<Produto>(HiveBoxNames.produtos(lojaId));
      await prodBox.clear();
      await prodBox.add(produtoHive(qtd: 10));

      final compra = compraRevendaBase();
      await ContaPagarService.gerarParcelasCompra(
        lojaId: lojaId,
        compra: compra,
        numeroParcelas: 2,
        primeiroVencimento: DateTime(2026, 5, 1),
      );
      final cpAntes = (await ContaPagarHiveStore.openBox(lojaId))!.length;

      await CompraRevendaDetalhamentoService.vincularProdutoExistente(
        lojaId: lojaId,
        compra: compra,
        produto: prodBox.values.first,
        quantidade: 1,
        custoUnitario: 15,
      );
      final cpDepois = (await ContaPagarHiveStore.openBox(lojaId))!.length;
      expect(cpDepois, cpAntes);
    });
  });

  group('Financeiro — recebimento CR idempotente no Firestore', () {
    test('segundo recebimento não duplica LF remoto', () async {
      final finBox =
          await Hive.openBox<LancamentoFinanceiro>(
        HiveBoxNames.lancamentosFinanceiros(lojaId),
      );
      await finBox.clear();

      final id1 = await ContaReceberRecebimentoCaixaService.registrarRecebimento(
        lojaId: lojaId,
        valor: 150,
        formaPagamento: 'pix',
        clienteNome: 'Cliente FS',
        contaHiveKey: 42,
        parcelaNumero: 1,
        dataRecebimento: DateTime(2026, 4, 15),
      );
      expect(id1, isNotNull);

      final id2 = await ContaReceberRecebimentoCaixaService.registrarRecebimento(
        lojaId: lojaId,
        valor: 150,
        formaPagamento: 'pix',
        clienteNome: 'Cliente FS',
        contaHiveKey: 42,
        parcelaNumero: 1,
        dataRecebimento: DateTime(2026, 4, 15),
      );
      expect(id2, id1);

      final snaps = await fakeFs
          .collection('lojas')
          .doc(lojaId)
          .collection('lancamentos_financeiros')
          .get();
      expect(snaps.docs.length, 1);
      expect(
        snaps.docs.first.data()['status'],
        FinanceiroStatusLancamento.pago,
      );
    });
  });
}
