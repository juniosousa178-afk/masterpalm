import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/models/compra_fornecedor.dart';
import 'package:master_palm/models/compra_fornecedor_constants.dart';
import 'package:master_palm/models/compra_fornecedor_item.dart';
import 'package:master_palm/models/conta_pagar.dart';
import 'package:master_palm/services/compra_para_pipeline_service.dart';
import 'package:master_palm/services/compra_revenda_detalhamento_service.dart';
import 'package:master_palm/services/conta_pagar_hive_store.dart';
import 'package:master_palm/services/conta_pagar_service.dart';

void main() {
  const lojaId = 'loja_revenda_test';

  CompraFornecedor _compraRevenda({
    String id = 'compra-rev-1',
    double valorInformado = 900,
    List<CompraFornecedorItem>? itens,
    String statusDetalhamento = CompraFornecedorStatusDetalhamento.aguardandoDetalhamento,
  }) {
    return CompraFornecedor(
      id: id,
      lojaId: lojaId,
      fornecedorHiveKey: 20,
      fornecedorNome: 'Forn Revenda',
      dataCompra: DateTime(2026, 3, 15),
      tipoCompra: CompraFornecedorTipo.revendaDetalharDepois,
      valorInformado: valorInformado,
      statusCompra: CompraFornecedorStatusCompra.confirmada,
      statusDetalhamentoProdutos: statusDetalhamento,
      itens: itens,
    );
  }

  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('hive_revenda_det_');
    Hive.init(hiveDir.path);
    ContaPagarHiveStore.ensureAdapterRegistered();
    if (!Hive.isAdapterRegistered(32)) {
      Hive.registerAdapter(CompraFornecedorAdapter());
    }
    if (!Hive.isAdapterRegistered(33)) {
      Hive.registerAdapter(CompraFornecedorItemAdapter());
    }
  });

  tearDownAll(() async {
    await Hive.close();
    if (await hiveDir.exists()) {
      await hiveDir.delete(recursive: true);
    }
  });

  setUp(() async {
    final name = HiveBoxNames.contasPagar(lojaId);
    if (Hive.isBoxOpen(name)) {
      await Hive.box<ContaPagar>(name).clear();
    }
  });

  group('Compra revenda_detalhar_depois — modelo', () {
    test('pode ser salva sem itens com valor informado', () {
      final c = _compraRevenda();
      expect(c.itensOuVazio, isEmpty);
      expect(c.valorTotalFinanceiro, 900);
      expect(c.movimentaEstoque, isFalse);
      expect(c.ehCompraRevendaDetalharDepois, isTrue);
    });

    test('pipeline de estoque ignora compra revenda', () {
      final c = _compraRevenda();
      expect(c.movimentaEstoque, isFalse);
      // Não deve lançar — retorno antecipado no serviço.
      expect(
        () => CompraParaPipelineService.sincronizarItensCompraConfirmada(c),
        returnsNormally,
      );
    });

    test('compra financeira continua sem estoque', () {
      final c = CompraFornecedor(
        id: 'fin',
        lojaId: lojaId,
        fornecedorHiveKey: 1,
        fornecedorNome: 'X',
        dataCompra: DateTime(2026, 1, 1),
        tipoCompra: CompraFornecedorTipo.financeira,
        valorInformado: 100,
      );
      expect(c.movimentaEstoque, isFalse);
    });

    test('compra produtos_estoque continua movimentando estoque', () {
      final c = CompraFornecedor(
        id: 'pe',
        lojaId: lojaId,
        fornecedorHiveKey: 1,
        fornecedorNome: 'X',
        dataCompra: DateTime(2026, 1, 1),
        tipoCompra: CompraFornecedorTipo.produtosEstoque,
        itens: [
          CompraFornecedorItem(
            produtoNome: 'P',
            quantidade: 1,
            custoUnitario: 10,
          ),
        ],
      );
      expect(c.movimentaEstoque, isTrue);
    });
  });

  group('Contas a pagar — revenda parcelada', () {
    test('R\$ 900 em 3x gera 3 contas sem itens', () async {
      final compra = _compraRevenda();
      final r = await ContaPagarService.gerarParcelasCompra(
        lojaId: lojaId,
        compra: compra,
        numeroParcelas: 3,
        primeiroVencimento: DateTime(2026, 4, 10),
      );
      expect(r.criadas, 3);
      expect(r.erro, isNull);

      final box = await ContaPagarHiveStore.openBox(lojaId);
      expect(box, isNotNull);
      expect(ContaPagarService.contarParcelasParaCompra(box!, compra.id), 3);
    });

    test('regerar parcelas não duplica CP', () async {
      final compra = _compraRevenda(id: 'rev-dup');
      final first = await ContaPagarService.gerarParcelasCompra(
        lojaId: lojaId,
        compra: compra,
        numeroParcelas: 3,
        primeiroVencimento: DateTime(2026, 4, 10),
      );
      expect(first.criadas, 3);

      final second = await ContaPagarService.gerarParcelasCompra(
        lojaId: lojaId,
        compra: compra,
        numeroParcelas: 3,
        primeiroVencimento: DateTime(2026, 4, 10),
      );
      expect(second.criadas, 0);
      expect(second.jaExistiam, isTrue);
    });
  });

  group('Detalhamento — status e conferência', () {
    test('status muda de aguardando para detalhado quando soma bate', () {
      final base = _compraRevenda();
      final comItens = base.copyWith(
        itens: [
          CompraFornecedorItem(
            produtoNome: 'Camiseta',
            quantidade: 30,
            custoUnitario: 30,
          ),
        ],
      );
      final r = CompraRevendaDetalhamentoService.recalcularCamposDetalhamento(comItens);
      expect(r.statusDetalhamentoProdutos,
          CompraFornecedorStatusDetalhamento.detalhado);
      expect(r.quantidadeItensDetalhados, 1);
    });

    test('item de detalhamento marca origem revenda', () {
      final c = _compraRevenda(
        itens: [
          CompraFornecedorItem(
            produtoNome: 'X',
            quantidade: 2,
            custoUnitario: 10,
            observacaoItem: 'origem:compra_revenda_detalhar_depois',
          ),
        ],
      );
      expect(
        c.itensOuVazio.first.observacaoItem,
        contains('origem:compra_revenda_detalhar_depois'),
      );
    });

    test('listar pendentes ignora compras já conferidas', () async {
      final boxName = HiveBoxNames.comprasFornecedor(lojaId);
      if (Hive.isBoxOpen(boxName)) await Hive.box<CompraFornecedor>(boxName).close();
      final box = await Hive.openBox<CompraFornecedor>(boxName);
      await box.clear();

      await box.put('p1', _compraRevenda(id: 'p1'));
      await box.put(
        'p2',
        _compraRevenda(
          id: 'p2',
          statusDetalhamento: CompraFornecedorStatusDetalhamento.conferido,
        ),
      );

      final pendentes = CompraRevendaDetalhamentoService.listarPendentesDetalhamento(
        box,
        lojaId,
      ).toList();
      expect(pendentes.length, 1);
      expect(pendentes.first.id, 'p1');
    });
  });
}
