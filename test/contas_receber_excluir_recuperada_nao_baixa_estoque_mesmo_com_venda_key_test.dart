import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/services/conta_receber_exclusao_service.dart';
import 'package:master_palm/services/conta_receber_service.dart';

void main() {
  const lojaId = 'loja-cr-rec-nao-estoque';

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('hive_cr_ne')).path);
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(VendaAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ProdutoAdapter());
    if (!Hive.isAdapterRegistered(29)) {
      Hive.registerAdapter(ContaReceberAdapter());
    }
  });

  tearDown(() async {
    for (final name in [
      HiveBoxNames.contasReceber(lojaId),
      HiveBoxNames.vendas(lojaId),
      HiveBoxNames.produtos(lojaId),
    ]) {
      if (Hive.isBoxOpen(name)) {
        try {
          await Hive.box<ContaReceber>(name).close();
        } catch (_) {
          try {
            await Hive.box<Venda>(name).close();
          } catch (_) {
            await Hive.box<Produto>(name).close();
          }
        }
      }
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (_) {}
    }
  });

  test('excluir recuperada não baixa estoque mesmo com vendaKey', () async {
    final prodBox = await Hive.openBox<Produto>(HiveBoxNames.produtos(lojaId));
    await prodBox.put(
      'anel',
      Produto(
        nome: 'Anel',
        custoReal: 10,
        frete: 0,
        gastosFixos: 0,
        gastosVariaveis: 0,
        precoSugerido: 85.50,
        precoFinal: 85.50,
        quantidade: 5,
        precoUnitario: 85.50,
        categoria: 'Aneis',
        dataEntrada: DateTime(2026, 6, 1),
        lojaId: lojaId,
        slug: 'anel',
      ),
    );

    final vendaBox = await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId));
    final vendaKey = await vendaBox.add(
      Venda(
        preco: 85.50,
        produtosDescricao: 'Anel',
        quantidade: 1,
        clienteNome: 'Rafaela Abelha',
        total: 85.50,
        formasPagamento: 'Fiado',
        data: DateTime(2026, 6, 1),
        tamanho: '',
        desconto: 0,
        frete: 0,
        vendedor: '',
        observacao: '',
        lojaId: lojaId,
        idFirebase: 'venda-rafa',
      ),
    );

    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    final conta = ContaReceber(
      lojaId: lojaId,
      clienteNome: 'Rafaela Abelha',
      valor: 85.50,
      dataVencimento: DateTime(2026, 7, 1),
      dataVenda: DateTime(2026, 6, 1),
      vendaKey: vendaKey,
      vendaIdFirebase: 'venda-rafa',
      observacao:
          'Venda recuperada manualmente após perda durante edição',
    );
    await crBox.add(conta);

    await ContaReceberExclusaoService.excluirContaReceberManualOuRecuperada(
      lojaId: lojaId,
      conta: conta,
    );

    expect(prodBox.get('anel')?.quantidade, 5);
    expect(vendaBox.length, 1);
  });
}
