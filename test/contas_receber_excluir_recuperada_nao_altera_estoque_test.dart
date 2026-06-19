import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/conta_receber_exclusao_service.dart';
import 'package:master_palm/services/conta_receber_service.dart';

void main() {
  const lojaId = 'loja-cr-exc-estoque';

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('hive_cr_exc_est')).path);
    if (!Hive.isAdapterRegistered(29)) {
      Hive.registerAdapter(ContaReceberAdapter());
    }
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(ProdutoAdapter());
    }
  });

  tearDown(() async {
    for (final name in [
      HiveBoxNames.contasReceber(lojaId),
      HiveBoxNames.produtos(lojaId),
    ]) {
      if (Hive.isBoxOpen(name)) {
        try {
          await Hive.box<ContaReceber>(name).close();
        } catch (_) {
          try {
            await Hive.box<Produto>(name).close();
          } catch (_) {
            await Hive.box(name).close();
          }
        }
      }
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (_) {}
    }
  });

  test('excluir conta recuperada não altera estoque', () async {
    final prodBox = await Hive.openBox<Produto>(HiveBoxNames.produtos(lojaId));
    await prodBox.put(
      'anel-teste',
      Produto(
        nome: 'Anel',
        custoReal: 10,
        frete: 0,
        gastosFixos: 0,
        gastosVariaveis: 0,
        precoSugerido: 50,
        precoFinal: 50,
        quantidade: 10,
        precoUnitario: 50,
        categoria: 'Aneis',
        dataEntrada: DateTime(2026, 6, 1),
        lojaId: lojaId,
        slug: 'anel-teste',
      ),
    );

    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    final conta = ContaReceber(
      lojaId: lojaId,
      clienteNome: 'Rafaela Abelha',
      valor: 85.50,
      dataVencimento: DateTime(2026, 7, 1),
      dataVenda: DateTime(2026, 6, 1),
      observacao: 'Venda recuperada manualmente após perda durante edição',
    );
    await crBox.add(conta);

    final r =
        await ContaReceberExclusaoService.excluirContaReceberManualOuRecuperada(
      lojaId: lojaId,
      conta: conta,
    );

    expect(r.sucesso, isTrue);
    expect(prodBox.get('anel-teste')?.quantidade, 10);
    expect(prodBox.length, 1);
  });
}
