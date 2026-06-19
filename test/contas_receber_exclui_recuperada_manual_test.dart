// Rafaela Abelha — Venda recuperada manualmente após perda durante edição.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/conta_receber_recuperada_manual.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/services/conta_receber_exclusao_service.dart';
import 'package:master_palm/services/conta_receber_service.dart';

void main() {
  const lojaId = 'loja-cr-exc-rafaela';

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('hive_cr_exc_rafa')).path);
    if (!Hive.isAdapterRegistered(29)) {
      Hive.registerAdapter(ContaReceberAdapter());
    }
  });

  tearDown(() async {
    final name = HiveBoxNames.contasReceber(lojaId);
    if (Hive.isBoxOpen(name)) await Hive.box<ContaReceber>(name).close();
    try {
      await Hive.deleteBoxFromDisk(name);
    } catch (_) {}
  });

  test('exclui conta Rafaela recuperada manualmente', () async {
    final box = await ContaReceberService.openBoxLoja(lojaId);
    final conta = ContaReceber(
      lojaId: lojaId,
      clienteNome: 'Rafaela Abelha',
      valor: 85.50,
      valorOriginal: 85.50,
      dataVencimento: DateTime(2026, 7, 15),
      dataVenda: DateTime(2026, 6, 1),
      observacao:
          'Venda recuperada manualmente após perda durante edição',
    );
    await box.add(conta);

    expect(contaReceberMostrarAcaoExcluir(conta), isTrue);
    expect(contaReceberTemMarcadorRecuperacao(conta), isTrue);

    final r =
        await ContaReceberExclusaoService.excluirContaReceberManualOuRecuperada(
      lojaId: lojaId,
      conta: conta,
    );

    expect(r.sucesso, isTrue);
    expect(box.length, 0);
    expect(
      ContaReceberService.listar(
        contas: box.values,
        lojaId: lojaId,
        filtro: 'pendentes',
      ),
      isEmpty,
    );
  });
}
