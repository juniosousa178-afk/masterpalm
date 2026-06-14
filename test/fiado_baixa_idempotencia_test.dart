// Idempotência cross-device: vendaIdFirebase + parcela (não Hive key).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/conta_receber_lancamento_vinculo.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/conta_receber_recebimento_caixa_service.dart';
import 'package:master_palm/services/financeiro_hive_store.dart';

void main() {
  const lojaId = 'loja-fiado-idempotencia';
  const vendaId = '11112222-3333-4444-5555-666677778888';

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_fiado_idem_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(29)) {
      Hive.registerAdapter(ContaReceberAdapter());
    }
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
  });

  setUp(() async {
    final box = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    await box!.clear();
  });

  test('mesmo vendaIdFirebase com Hive keys diferentes não duplica financeiro', () async {
    const valor = 120.0;
    final data = DateTime(2026, 6, 14);
    final contaDesktop = ContaReceber(
      lojaId: lojaId,
      clienteNome: 'Maria',
      valor: valor,
      dataVencimento: data,
      dataVenda: data,
      vendaIdFirebase: vendaId,
      parcelaNumero: 1,
    );
    final contaMobile = ContaReceber(
      lojaId: lojaId,
      clienteNome: 'Maria',
      valor: valor,
      dataVencimento: data,
      dataVenda: data,
      vendaIdFirebase: vendaId,
      parcelaNumero: 1,
    );

    final idDesktop = await ContaReceberRecebimentoCaixaService.registrarRecebimento(
      lojaId: lojaId,
      valor: valor,
      formaPagamento: 'Pix',
      clienteNome: 'Maria',
      conta: contaDesktop,
      contaHiveKey: 3,
      dataRecebimento: data,
    );
    final idMobile = await ContaReceberRecebimentoCaixaService.registrarRecebimento(
      lojaId: lojaId,
      valor: valor,
      formaPagamento: 'Pix',
      clienteNome: 'Maria',
      conta: contaMobile,
      contaHiveKey: 99,
      dataRecebimento: data,
    );

    expect(idDesktop, isNotNull);
    expect(idMobile, idDesktop);

    final finBox = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    final pagos = finBox!.values.where(
      (l) =>
          l.lojaId == lojaId &&
          l.origem == FinanceiroOrigemLancamento.contaReceberFiado &&
          l.status == FinanceiroStatusLancamento.pago,
    );
    expect(pagos.length, 1);
    expect(pagos.first.referenciaExterna, startsWith('cr_receb2:'));
  });

  test('referenciaExterna estável deriva de vendaIdFirebase', () {
    final conta = ContaReceber(
      lojaId: lojaId,
      clienteNome: 'X',
      valor: 50,
      dataVencimento: DateTime(2026, 6, 1),
      dataVenda: DateTime(2026, 6, 1),
      vendaIdFirebase: vendaId,
      parcelaNumero: 2,
    );
    expect(contaReceberStableId(conta), '${vendaId}_p2');
  });
}
