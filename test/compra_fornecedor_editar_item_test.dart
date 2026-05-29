import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/models/compra_fornecedor.dart';
import 'package:master_palm/models/compra_fornecedor_constants.dart';
import 'package:master_palm/models/compra_fornecedor_item.dart';
import 'package:master_palm/models/conta_pagar.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/compra_fornecedor_item_estorno_service.dart';
import 'package:master_palm/services/compra_revenda_detalhamento_service.dart';
import 'package:master_palm/services/conta_pagar_hive_store.dart';
import 'package:master_palm/services/conta_pagar_service.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/utils/compra_fornecedor_rateio.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const lojaId = 'loja_edit_item_test';
  const produtoId = 'prod-edit-1';

  late Directory hiveDir;
  late FakeFirebaseFirestore fakeFs;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    hiveDir = await Directory.systemTemp.createTemp('hive_edit_item_');
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

  Produto _produtoHive({required int quantidade, double custoReal = 10}) {
    return Produto(
      nome: 'Produto Edit',
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

  CompraFornecedor _compraRevenda({
    List<CompraFornecedorItem>? itens,
    String id = 'compra-edit-rev',
  }) {
    return CompraFornecedor(
      id: id,
      lojaId: lojaId,
      fornecedorHiveKey: 1,
      fornecedorNome: 'Forn',
      dataCompra: DateTime(2026, 3, 1),
      tipoCompra: CompraFornecedorTipo.revendaDetalharDepois,
      valorInformado: 300,
      statusCompra: CompraFornecedorStatusCompra.confirmada,
      statusDetalhamentoProdutos:
          CompraFornecedorStatusDetalhamento.aguardandoDetalhamento,
      itens: itens,
    );
  }

  Future<void> _seedFirestoreEstoque(int quantidade, {double custo = 10}) async {
    if (quantidade < 0) quantidade = 0;
    await fakeFs
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.estoqueProdutosCol)
        .doc(produtoId)
        .set({
      'nome': 'Produto Edit',
      'slug': produtoId,
      'quantidade': quantidade,
      'custoReal': custo,
      'lojaId': lojaId,
    });
  }

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

  group('Compra rascunho — lista local', () {
    test('editar quantidade/custo recalcula subtotal e rateio', () {
      final itens = [
        CompraFornecedorItem(
          produtoNome: 'A',
          quantidade: 2,
          custoUnitario: 10,
          itemCompraId: 'i1',
        ),
      ];
      itens[0] = itens[0].copyWith(quantidade: 5, custoUnitario: 12);
      final compra = CompraFornecedor(
        id: 'rasc',
        lojaId: lojaId,
        fornecedorHiveKey: 1,
        fornecedorNome: 'F',
        dataCompra: DateTime(2026, 1, 1),
        tipoCompra: CompraFornecedorTipo.produtosEstoque,
        statusCompra: CompraFornecedorStatusCompra.rascunho,
        itens: itens,
        frete: 10,
      );
      final rateada = CompraFornecedorRateio.aplicar(compra);
      expect(rateada.itensOuVazio.first.quantidade, 5);
      expect(rateada.itensOuVazio.first.subtotal, 60);
      expect(rateada.valorTotalFinanceiro, greaterThan(60));
    });

    test('excluir item e manter outro na lista', () {
      var itens = [
        CompraFornecedorItem(
          produtoNome: 'A',
          quantidade: 1,
          custoUnitario: 10,
          itemCompraId: 'i1',
        ),
        CompraFornecedorItem(
          produtoNome: 'B',
          quantidade: 2,
          custoUnitario: 20,
          itemCompraId: 'i2',
        ),
      ];
      itens = List.of(itens)..removeAt(0);
      itens.add(
        CompraFornecedorItem(
          produtoNome: 'C',
          quantidade: 3,
          custoUnitario: 5,
          itemCompraId: 'i3',
        ),
      );
      expect(itens.length, 2);
      expect(itens.first.produtoNome, 'B');
      expect(itens.last.produtoNome, 'C');
    });
  });

  group('Revenda detalhar — editar/excluir item', () {
    test('vincular e editar item antes de conferir recalcula totais', () async {
      await _seedFirestoreEstoque(0);
      final prodBox = await _openProdutoBox();
      await prodBox.clear();
      final p = _produtoHive(quantidade: 0);
      await prodBox.add(p);

      final compraBox = await _openCompraBox();
      final compra = _compraRevenda();
      await compraBox.put(compra.id, compra);

      final v1 = await CompraRevendaDetalhamentoService.vincularProdutoExistente(
        lojaId: lojaId,
        compra: compra,
        produto: p,
        quantidade: 4,
        custoUnitario: 25,
      );
      expect(v1.sucesso, isTrue);
      final itemId = v1.compraAtualizada!.itensOuVazio.single.itemCompraId;
      await _seedFirestoreEstoque(4, custo: 25);

      final pAtual = prodBox.values.firstWhere((x) => x.idFirebase == produtoId);
      final edit = await CompraRevendaDetalhamentoService.editarItemDetalhadoCompra(
        lojaId: lojaId,
        compra: v1.compraAtualizada!,
        itemCompraId: itemId,
        produto: pAtual,
        quantidade: 2,
        custoUnitario: 30,
      );
      expect(edit.sucesso, isTrue);
      expect(edit.compraAtualizada!.itensOuVazio.single.quantidade, 2);
      expect(edit.compraAtualizada!.valorProdutosDetalhados, 60);
      expect(pAtual.quantidade, 2);
    });

    test('excluir item salvo estorna estoque', () async {
      await _seedFirestoreEstoque(0);
      final prodBox = await _openProdutoBox();
      await prodBox.clear();
      final p = _produtoHive(quantidade: 0);
      await prodBox.add(p);

      final compra = _compraRevenda(id: 'excl-est');
      final v1 = await CompraRevendaDetalhamentoService.vincularProdutoExistente(
        lojaId: lojaId,
        compra: compra,
        produto: p,
        quantidade: 5,
        custoUnitario: 10,
      );
      expect(v1.sucesso, isTrue);
      final itemId = v1.compraAtualizada!.itensOuVazio.single.itemCompraId;
      await _seedFirestoreEstoque(5);

      final ex = await CompraRevendaDetalhamentoService.excluirItemDetalhadoCompra(
        lojaId: lojaId,
        compra: v1.compraAtualizada!,
        itemCompraId: itemId,
      );
      expect(ex.sucesso, isTrue);
      expect(ex.compraAtualizada!.itensOuVazio, isEmpty);
      final pPos = prodBox.values.first;
      expect(pPos.quantidade, 0);
    });

    test('estoque insuficiente bloqueia edição', () async {
      await _seedFirestoreEstoque(1);
      final prodBox = await _openProdutoBox();
      await prodBox.clear();
      final p = _produtoHive(quantidade: 1);
      await prodBox.add(p);

      final item = CompraFornecedorItem(
        produtoNome: p.nome,
        quantidade: 5,
        custoUnitario: 10,
        productId: produtoId,
        itemCompraId: 'item-bloq',
        estoqueEntradaRegistrada: true,
        estoqueSnapshotOk: true,
        estoqueAnterior: 0,
        custoAnterior: 5,
        custoEntradaRegistrado: 10,
      );

      final pre = await CompraFornecedorItemEstornoService.validarPodeEstornarItemCompra(
        lojaId: lojaId,
        item: item,
        produtosBox: prodBox,
      );
      expect(pre, isNotNull);
      expect(pre!.sucesso, isFalse);
      expect(
        pre.mensagem,
        CompraFornecedorItemEstornoService.msgEstoqueInsuficienteEdicao,
      );
    });

    test('editar/excluir não cria CP nem LF', () async {
      await _seedFirestoreEstoque(10);
      final prodBox = await _openProdutoBox();
      await prodBox.clear();
      await prodBox.add(_produtoHive(quantidade: 10));

      final compra = _compraRevenda(id: 'sem-fin');
      await ContaPagarService.gerarParcelasCompra(
        lojaId: lojaId,
        compra: compra,
        numeroParcelas: 2,
        primeiroVencimento: DateTime(2026, 4, 1),
      );

      final cpAntes = (await ContaPagarHiveStore.openBox(lojaId))!.length;
      final lfBoxName = HiveBoxNames.lancamentosFinanceiros(lojaId);
      final lfAntes =
          Hive.isBoxOpen(lfBoxName) ? Hive.box<LancamentoFinanceiro>(lfBoxName).length : 0;

      final v1 = await CompraRevendaDetalhamentoService.vincularProdutoExistente(
        lojaId: lojaId,
        compra: compra,
        produto: prodBox.values.first,
        quantidade: 2,
        custoUnitario: 15,
      );
      final itemId = v1.compraAtualizada!.itensOuVazio.single.itemCompraId;

      await CompraRevendaDetalhamentoService.excluirItemDetalhadoCompra(
        lojaId: lojaId,
        compra: v1.compraAtualizada!,
        itemCompraId: itemId,
      );

      final cpDepois = (await ContaPagarHiveStore.openBox(lojaId))!.length;
      final lfDepois =
          Hive.isBoxOpen(lfBoxName) ? Hive.box<LancamentoFinanceiro>(lfBoxName).length : 0;

      expect(cpDepois, cpAntes);
      expect(lfDepois, lfAntes);
    });

    test('produto novo excluído fica inativo sem apagar registro', () async {
      final prodBox = await _openProdutoBox();
      await prodBox.clear();
      final p = _produtoHive(quantidade: 3);
      p.ativoNoRascunho = true;
      await prodBox.add(p);

      final item = CompraFornecedorItem(
        produtoNome: p.nome,
        quantidade: 3,
        custoUnitario: 12,
        productId: produtoId,
        itemCompraId: 'novo-1',
        produtoNovoNaCompra: true,
        estoqueEntradaRegistrada: false,
      );

      final compra = _compraRevenda(itens: [item]);
      final ex = await CompraRevendaDetalhamentoService.excluirItemDetalhadoCompra(
        lojaId: lojaId,
        compra: compra,
        itemCompraId: 'novo-1',
      );
      expect(ex.sucesso, isTrue);
      expect(ex.compraAtualizada!.itensOuVazio, isEmpty);
      final pPos = prodBox.values.first;
      expect(pPos.ativoNoRascunho, isFalse);
      expect(prodBox.length, 1);
    });
  });

  group('Compra financeira', () {
    test('continua sem movimentar estoque ao editar lista local', () {
      final c = CompraFornecedor(
        id: 'fin',
        lojaId: lojaId,
        fornecedorHiveKey: 1,
        fornecedorNome: 'X',
        dataCompra: DateTime(2026, 1, 1),
        tipoCompra: CompraFornecedorTipo.financeira,
        valorInformado: 100,
        statusCompra: CompraFornecedorStatusCompra.rascunho,
      );
      expect(c.movimentaEstoque, isFalse);
    });
  });
}
