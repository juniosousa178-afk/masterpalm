// Elidiane Silva Quaresma — [recuperacao_script_elidiane_20260410].

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/conta_receber_recuperada_manual.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/services/conta_receber_exclusao_service.dart';
import 'package:master_palm/services/conta_receber_service.dart';

void main() {
  const lojaId = 'loja-cr-exc-elidiane';

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('hive_cr_exc_eli')).path);
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

  test('exclui conta Elidiane recuperacao_script', () async {
    final box = await ContaReceberService.openBoxLoja(lojaId);
    final conta = ContaReceber(
      lojaId: lojaId,
      clienteNome: 'Elidiane Silva Quaresma',
      valor: 420.60,
      valorOriginal: 420.60,
      dataVencimento: DateTime(2026, 8, 1),
      dataVenda: DateTime(2026, 4, 10),
      observacao:
          '[recuperacao_script_elidiane_20260410] Recuperação assistida. Sem baixa de estoque.',
    );
    await box.add(conta);

    expect(contaReceberTemMarcadorRecuperacao(conta), isTrue);

    final r =
        await ContaReceberExclusaoService.excluirContaReceberManualOuRecuperada(
      lojaId: lojaId,
      conta: conta,
    );

    expect(r.sucesso, isTrue);
    expect(box.length, 0);
  });
}
