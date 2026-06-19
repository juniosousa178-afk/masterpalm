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
  const lojaId = 'loja-cr-exc-bloq-venda';
  const vendaId = 'venda-ativa-bloq-uuid';

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('hive_cr_bloq_venda')).path);
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
          try {
            await Hive.box<Venda>(name).close();
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

  test('conta fiada com venda ativa é bloqueada', () async {
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

    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    final conta = ContaReceber(
      lojaId: lojaId,
      clienteNome: 'Cliente Fiado',
      valor: 200,
      valorOriginal: 200,
      dataVencimento: DateTime(2026, 8, 1),
      dataVenda: DateTime(2026, 6, 10),
      vendaKey: vendaKey,
      vendaIdFirebase: vendaId,
      observacao: 'Venda fiada',
    );
    await crBox.add(conta);

    expect(contaReceberMostrarAcaoExcluir(conta), isFalse);

    final diag = await ContaReceberExclusaoService.diagnosticar(
      lojaId: lojaId,
      conta: conta,
    );
    expect(diag.podeExcluir, isFalse);

    final r =
        await ContaReceberExclusaoService.excluirContaReceberManualOuRecuperada(
      lojaId: lojaId,
      conta: conta,
    );
    expect(r.sucesso, isFalse);
    expect(crBox.length, 1);
  });

  test('conta recuperada com venda ativa vinculada é bloqueada', () async {
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
      dataVencimento: DateTime(2026, 7, 1),
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
    expect(diag.temVendaAtiva, isTrue);
    expect(diag.podeExcluir, isFalse);
  });
}
