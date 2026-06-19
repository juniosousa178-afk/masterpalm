import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/services/conta_receber_exclusao_service.dart';
import 'package:master_palm/services/conta_receber_service.dart';

void main() {
  const lojaId = 'loja-cr-rec-script-vinc';
  const vendaId = 'venda-script-elidiane';

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('hive_cr_script')).path);
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

  test('recuperacao_script com vínculo antigo permite excluir', () async {
    final vendaBox = await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId));
    await vendaBox.add(
      Venda(
        preco: 420.60,
        produtosDescricao: 'Colar',
        quantidade: 1,
        clienteNome: 'Elidiane Silva Quaresma',
        total: 420.60,
        formasPagamento: 'Fiado',
        data: DateTime(2026, 4, 10),
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
      clienteNome: 'Elidiane Silva Quaresma',
      valor: 420.60,
      dataVencimento: DateTime(2026, 8, 1),
      dataVenda: DateTime(2026, 4, 10),
      vendaIdFirebase: vendaId,
      observacao:
          '[recuperacao_script_elidiane_20260410] Recuperação assistida. Sem baixa de estoque.',
    );
    await crBox.add(conta);

    expect(
      (await ContaReceberExclusaoService.diagnosticar(
        lojaId: lojaId,
        conta: conta,
      ))
          .podeExcluir,
      isTrue,
    );
    expect(
      (await ContaReceberExclusaoService.excluirContaReceberManualOuRecuperada(
        lojaId: lojaId,
        conta: conta,
      ))
          .sucesso,
      isTrue,
    );
    expect(crBox.length, 0);
  });
}
