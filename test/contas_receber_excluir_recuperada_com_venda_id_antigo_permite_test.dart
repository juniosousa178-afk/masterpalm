import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/services/conta_receber_exclusao_service.dart';
import 'package:master_palm/services/conta_receber_service.dart';

void main() {
  const lojaId = 'loja-cr-rec-venda-id';
  const vendaId = 'venda-antiga-rafaela';

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('hive_cr_vid')).path);
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(VendaAdapter());
    if (!Hive.isAdapterRegistered(29)) {
      Hive.registerAdapter(ContaReceberAdapter());
    }
  });

  tearDown(() async {
    for (final name in [
      HiveBoxNames.contasReceber(lojaId),
      HiveBoxNames.vendas(lojaId),
    ]) {
      if (Hive.isBoxOpen(name)) {
        try {
          await Hive.box<ContaReceber>(name).close();
        } catch (_) {
          await Hive.box<Venda>(name).close();
        }
      }
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (_) {}
    }
  });

  test('Rafaela com vendaIdFirebase antigo permite excluir', () async {
    final vendaBox = await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId));
    await vendaBox.add(
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
        idFirebase: vendaId,
      ),
    );

    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    final conta = ContaReceber(
      lojaId: lojaId,
      clienteNome: 'Rafaela Abelha',
      valor: 85.50,
      dataVencimento: DateTime(2026, 7, 15),
      dataVenda: DateTime(2026, 6, 1),
      vendaIdFirebase: vendaId,
      observacao:
          'Venda recuperada manualmente após perda durante edição',
    );
    await crBox.add(conta);

    final diag = await ContaReceberExclusaoService.diagnosticar(
      lojaId: lojaId,
      conta: conta,
    );
    expect(diag.podeExcluir, isTrue);

    final r =
        await ContaReceberExclusaoService.excluirContaReceberManualOuRecuperada(
      lojaId: lojaId,
      conta: conta,
    );
    expect(r.sucesso, isTrue);
    expect(crBox.length, 0);
  });
}
