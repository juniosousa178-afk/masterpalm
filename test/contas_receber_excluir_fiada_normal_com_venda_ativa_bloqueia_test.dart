import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/conta_receber_recuperada_manual.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/services/conta_receber_exclusao_service.dart';
import 'package:master_palm/services/conta_receber_service.dart';

void main() {
  const lojaId = 'loja-cr-fiada-bloq';
  const vendaId = 'venda-fiada-ativa';

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('hive_cr_fiada_b')).path);
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

  test('conta fiada normal com venda ativa bloqueia exclusão', () async {
    final vendaBox = await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId));
    final vendaKey = await vendaBox.add(
      Venda(
        preco: 200,
        produtosDescricao: 'Produto',
        quantidade: 1,
        clienteNome: 'Cliente Fiado',
        total: 200,
        formasPagamento: 'Fiado - R\$ 200,00',
        data: DateTime(2026, 6, 10),
        tamanho: '',
        desconto: 0,
        frete: 0,
        vendedor: '',
        observacao: '',
        lojaId: lojaId,
        idFirebase: vendaId,
      ),
    );

    final conta = ContaReceber(
      lojaId: lojaId,
      clienteNome: 'Cliente Fiado',
      valor: 200,
      dataVencimento: DateTime(2026, 8, 1),
      dataVenda: DateTime(2026, 6, 10),
      vendaKey: vendaKey,
      vendaIdFirebase: vendaId,
      observacao: 'Venda fiada',
    );
    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    await crBox.add(conta);

    expect(contaReceberMostrarAcaoExcluir(conta), isFalse);
    expect(
      (await ContaReceberExclusaoService.diagnosticar(
        lojaId: lojaId,
        conta: conta,
      ))
          .podeExcluir,
      isFalse,
    );
  });
}
