import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/models/compra_fornecedor.dart';
import 'package:master_palm/models/compra_fornecedor_constants.dart';
import 'package:master_palm/models/compra_fornecedor_item.dart';
import 'package:master_palm/models/conta_pagar.dart';
import 'package:master_palm/services/conta_pagar_hive_store.dart';
import 'package:master_palm/services/conta_pagar_service.dart';

void main() {
  const lojaId = 'loja_cp_test';

  CompraFornecedor _compraProdutos({
    String id = 'compra-prod-1',
    double custo = 300,
    int qtd = 3,
  }) {
    return CompraFornecedor(
      id: id,
      lojaId: lojaId,
      fornecedorHiveKey: 10,
      fornecedorNome: 'Forn Produtos',
      dataCompra: DateTime(2026, 3, 1),
      tipoCompra: CompraFornecedorTipo.produtosEstoque,
      itens: [
        CompraFornecedorItem(
          produtoNome: 'Item A',
          quantidade: qtd,
          custoUnitario: custo,
        ),
      ],
    );
  }

  CompraFornecedor _compraFinanceira({
    String id = 'compra-fin-1',
    double valorInformado = 900,
  }) {
    return CompraFornecedor(
      id: id,
      lojaId: lojaId,
      fornecedorHiveKey: 11,
      fornecedorNome: 'Forn Financeiro',
      dataCompra: DateTime(2026, 3, 1),
      tipoCompra: CompraFornecedorTipo.financeira,
      valorInformado: valorInformado,
    );
  }

  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('hive_cp_int_');
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

  Future<Box<ContaPagar>> _openCpBox() async {
    final box = await ContaPagarHiveStore.openBox(lojaId);
    expect(box, isNotNull);
    return box!;
  }

  group('gerarParcelasCompra — integração Hive', () {
    test('produtos_estoque R\$ 900 em 3x gera 3 contas', () async {
      final compra = _compraProdutos();
      expect(compra.valorTotalFinanceiro, 900);

      final r = await ContaPagarService.gerarParcelasCompra(
        lojaId: lojaId,
        compra: compra,
        numeroParcelas: 3,
        primeiroVencimento: DateTime(2026, 4, 10),
      );

      expect(r.criadas, 3);
      expect(r.jaExistiam, isFalse);
      expect(r.erro, isNull);

      final box = await _openCpBox();
      expect(ContaPagarService.contarParcelasParaCompra(box, compra.id), 3);
      final list = ContaPagarService.listar(box, lojaId, compraId: compra.id);
      expect(list.length, 3);
      expect(list.fold<double>(0, (s, c) => s + c.valorParcela), 900);
    });

    test('financeira R\$ 900 em 3x gera 3 contas sem itens', () async {
      final compra = _compraFinanceira();
      expect(compra.itensOuVazio, isEmpty);
      expect(compra.valorTotalFinanceiro, 900);

      final r = await ContaPagarService.gerarParcelasCompra(
        lojaId: lojaId,
        compra: compra,
        numeroParcelas: 3,
        primeiroVencimento: DateTime(2026, 4, 10),
      );

      expect(r.criadas, 3);
      final box = await _openCpBox();
      expect(ContaPagarService.contarParcelasParaCompra(box, compra.id), 3);
    });

    test('financeira valor zero retorna valor_invalido', () async {
      final compra = _compraFinanceira(valorInformado: 0);
      final r = await ContaPagarService.gerarParcelasCompra(
        lojaId: lojaId,
        compra: compra,
        numeroParcelas: 3,
        primeiroVencimento: DateTime(2026, 4, 10),
      );
      expect(r.criadas, 0);
      expect(r.erro, 'valor_invalido');
    });

    test('compraId vazio retorna compra_id_vazio', () async {
      final compra = _compraFinanceira(id: '  ');
      final r = await ContaPagarService.gerarParcelasCompra(
        lojaId: lojaId,
        compra: compra,
        numeroParcelas: 3,
        primeiroVencimento: DateTime(2026, 4, 10),
      );
      expect(r.criadas, 0);
      expect(r.erro, 'compra_id_vazio');
    });

    test('reexecutar geração não duplica', () async {
      final compra = _compraFinanceira(id: 'compra-dup');
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

      final box = await _openCpBox();
      expect(ContaPagarService.contarParcelasParaCompra(box, compra.id), 3);
    });

    test('filtro por compraId retorna parcelas corretas', () async {
      final c1 = _compraProdutos(id: 'c-a');
      final c2 = _compraFinanceira(id: 'c-b', valorInformado: 600);

      await ContaPagarService.gerarParcelasCompra(
        lojaId: lojaId,
        compra: c1,
        numeroParcelas: 3,
        primeiroVencimento: DateTime(2026, 5, 1),
      );
      await ContaPagarService.gerarParcelasCompra(
        lojaId: lojaId,
        compra: c2,
        numeroParcelas: 2,
        primeiroVencimento: DateTime(2026, 5, 1),
      );

      final box = await _openCpBox();
      expect(ContaPagarService.listar(box, lojaId, compraId: 'c-a').length, 3);
      expect(ContaPagarService.listar(box, lojaId, compraId: 'c-b').length, 2);
    });
  });
}
