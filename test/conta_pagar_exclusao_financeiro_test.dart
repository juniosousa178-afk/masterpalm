import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/conta_pagar_lancamento_vinculo.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/models/compra_fornecedor.dart';
import 'package:master_palm/models/compra_fornecedor_constants.dart';
import 'package:master_palm/models/compra_fornecedor_item.dart';
import 'package:master_palm/models/conta_pagar.dart';
import 'package:master_palm/models/conta_pagar_constants.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/compra_fornecedor_hive_store.dart';
import 'package:master_palm/services/conta_pagar_financeiro_exclusao_service.dart';
import 'package:master_palm/services/conta_pagar_hive_store.dart';
import 'package:master_palm/services/conta_pagar_service.dart';
import 'package:master_palm/services/financeiro_hive_store.dart';
import 'package:master_palm/services/financeiro_service.dart';

void main() {
  const lojaId = 'loja_cp_excl';

  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('hive_cp_excl_');
    Hive.init(hiveDir.path);
    ContaPagarHiveStore.ensureAdapterRegistered();
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
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

  Future<void> _seedCompra(String compraId) async {
    final box = await CompraFornecedorHiveStore.openBox(lojaId);
    if (box == null) return;
    await box.put(
      compraId,
      CompraFornecedor(
        id: compraId,
        lojaId: lojaId,
        fornecedorHiveKey: 1,
        fornecedorNome: 'Forn',
        dataCompra: DateTime(2026, 3, 1),
        tipoCompra: CompraFornecedorTipo.financeira,
        valorInformado: 900,
        valorPago: 300,
        statusPagamento: CompraFornecedorStatusPagamento.parcial,
      ),
    );
  }

  ContaPagar _conta({
    required String id,
    String status = ContaPagarStatus.pendente,
    String lancId = '',
  }) {
    return ContaPagar(
      id: id,
      lojaId: lojaId,
      fornecedorId: 1,
      fornecedorNome: 'Forn',
      compraId: 'compra-excl',
      descricao: 'Parcela teste',
      valorTotalCompra: 900,
      valorParcela: 300,
      parcelaNumero: 1,
      parcelaTotal: 3,
      dataVencimento: DateTime(2026, 4, 10),
      dataCompra: DateTime(2026, 3, 1),
      status: status,
      lancamentoFinanceiroId: lancId,
      dataPagamento:
          status == ContaPagarStatus.pago ? DateTime(2026, 4, 1) : null,
    );
  }

  setUp(() async {
    final cpName = HiveBoxNames.contasPagar(lojaId);
    if (Hive.isBoxOpen(cpName)) {
      await Hive.box<ContaPagar>(cpName).clear();
    }
    final finName = HiveBoxNames.lancamentosFinanceiros(lojaId);
    if (Hive.isBoxOpen(finName)) {
      await Hive.box<LancamentoFinanceiro>(finName).clear();
    }
    await _seedCompra('compra-excl');
  });

  group('Exclusão sincronizada CP ↔ Financeiro', () {
    test('pendente: cancela só ContaPagar', () async {
      final cpBox = await ContaPagarHiveStore.openBox(lojaId);
      await cpBox!.put('cp_p1', _conta(id: 'cp_p1'));

      final r = await ContaPagarFinanceiroExclusaoService.cancelarContaPagar(
        lojaId: lojaId,
        conta: cpBox.get('cp_p1')!,
      );

      expect(r.contaCancelada, isTrue);
      expect(r.lancamentoExcluido, isFalse);
      expect(cpBox.get('cp_p1')!.status, ContaPagarStatus.cancelado);

      final finBox = await FinanceiroHiveStore.openLancamentosBox(lojaId);
      expect(finBox!.values, isEmpty);
    });

    test('paga: cancela ContaPagar e LancamentoFinanceiro', () async {
      final lancId = lancamentoFinanceiroDocIdParaContaPagar('cp_p2');
      final finBox = await FinanceiroHiveStore.openLancamentosBox(lojaId);
      await finBox!.put(
        lancId,
        LancamentoFinanceiro(
          id: lancId,
          lojaId: lojaId,
          descricao: 'Pagamento teste',
          valor: 300,
          tipo: FinanceiroTipoLancamento.compraMercadoria,
          categoria: 'compra_produtos',
          subcategoria: '',
          status: FinanceiroStatusLancamento.pago,
          formaPagamento: 'PIX',
          fornecedor: 'Forn',
          dataLancamento: DateTime(2026, 3, 1),
          dataPagamento: DateTime(2026, 4, 1),
          competenciaMes: 3,
          competenciaAno: 2026,
          origem: FinanceiroOrigemLancamento.contaPagarCompra,
          referenciaExterna: referenciaExternaContaPagar(
            contaPagarId: 'cp_p2',
            compraId: 'compra-excl',
          ),
        ),
      );

      final cpBox = await ContaPagarHiveStore.openBox(lojaId);
      await cpBox!.put(
        'cp_p2',
        _conta(id: 'cp_p2', status: ContaPagarStatus.pago, lancId: lancId),
      );

      final r = await ContaPagarFinanceiroExclusaoService.cancelarContaPagar(
        lojaId: lojaId,
        conta: cpBox.get('cp_p2')!,
      );

      expect(r.contaCancelada, isTrue);
      expect(r.lancamentoExcluido, isTrue);
      expect(cpBox.get('cp_p2')!.status, ContaPagarStatus.cancelado);
      expect(finBox.get(lancId), isNull);
    });

    test('excluir LF vinculado cancela ContaPagar', () async {
      const cpId = 'cp_p3';
      final lancId = lancamentoFinanceiroDocIdParaContaPagar(cpId);
      final finBox = await FinanceiroHiveStore.openLancamentosBox(lojaId);
      await finBox!.put(
        lancId,
        LancamentoFinanceiro(
          id: lancId,
          lojaId: lojaId,
          descricao: 'LF',
          valor: 300,
          tipo: FinanceiroTipoLancamento.compraMercadoria,
          categoria: 'compra_produtos',
          subcategoria: '',
          status: FinanceiroStatusLancamento.pago,
          formaPagamento: 'PIX',
          fornecedor: 'Forn',
          dataLancamento: DateTime(2026, 3, 1),
          dataPagamento: DateTime(2026, 4, 1),
          competenciaMes: 3,
          competenciaAno: 2026,
          origem: FinanceiroOrigemLancamento.contaPagarCompra,
          referenciaExterna: referenciaExternaContaPagar(
            contaPagarId: cpId,
            compraId: 'compra-excl',
          ),
        ),
      );

      final cpBox = await ContaPagarHiveStore.openBox(lojaId);
      await cpBox!.put(
        cpId,
        _conta(id: cpId, status: ContaPagarStatus.pago, lancId: lancId),
      );

      await ContaPagarFinanceiroExclusaoService.excluirLancamentoImediato(
        lojaId: lojaId,
        lancamentoId: lancId,
      );
      await ContaPagarFinanceiroExclusaoService.cancelarContaPagarPorId(
        lojaId: lojaId,
        contaPagarId: cpId,
        excluirLancamentoVinculado: false,
      );

      expect(finBox.get(lancId), isNull);
      expect(cpBox.get(cpId)!.status, ContaPagarStatus.cancelado);
    });

    test('resumo financeiro não soma LF excluído', () async {
      final lancId = lancamentoFinanceiroDocIdParaContaPagar('cp_p4');
      final finBox = await FinanceiroHiveStore.openLancamentosBox(lojaId);
      await finBox!.put(
        lancId,
        LancamentoFinanceiro(
          id: lancId,
          lojaId: lojaId,
          descricao: 'LF',
          valor: 500,
          tipo: FinanceiroTipoLancamento.compraMercadoria,
          categoria: 'compra_produtos',
          subcategoria: '',
          status: FinanceiroStatusLancamento.pago,
          formaPagamento: 'PIX',
          fornecedor: 'Forn',
          dataLancamento: DateTime(2026, 4, 15),
          dataPagamento: DateTime(2026, 4, 15),
          competenciaMes: 4,
          competenciaAno: 2026,
          origem: FinanceiroOrigemLancamento.contaPagarCompra,
        ),
      );

      final inicio = DateTime(2026, 4, 1);
      final fim = DateTime(2026, 4, 30, 23, 59, 59, 999);
      var resumo = FinanceiroService.resumoPeriodo(
        box: finBox,
        lojaId: lojaId,
        inicio: inicio,
        fim: fim,
      );
      expect(resumo.totalCompraMercadoria, 500);

      await ContaPagarFinanceiroExclusaoService.excluirLancamentoImediato(
        lojaId: lojaId,
        lancamentoId: lancId,
      );

      resumo = FinanceiroService.resumoPeriodo(
        box: finBox,
        lojaId: lojaId,
        inicio: inicio,
        fim: fim,
      );
      expect(resumo.totalCompraMercadoria, 0);
    });

    test('resumo CP não soma parcela cancelada', () async {
      final cpBox = await ContaPagarHiveStore.openBox(lojaId);
      await cpBox!.put('cp_a', _conta(id: 'cp_a'));
      await cpBox.put(
        'cp_b',
        _conta(id: 'cp_b', status: ContaPagarStatus.pago, lancId: 'x'),
      );

      await ContaPagarFinanceiroExclusaoService.cancelarContaPagar(
        lojaId: lojaId,
        conta: cpBox.get('cp_b')!,
        excluirLancamentoVinculado: false,
      );

      final resumo = ContaPagarService.resumo(
        contas: cpBox.values,
        ano: 2026,
        mes: 4,
      );
      expect(resumo.totalAberto, 300);
      expect(resumo.totalPagoNoMes, 0);
    });

    test('CompraFornecedor valorPago recalculado após cancelar paga', () async {
      final cpBox = await ContaPagarHiveStore.openBox(lojaId);
      await cpBox!.put(
        'cp_p5',
        _conta(id: 'cp_p5', status: ContaPagarStatus.pago, lancId: 'mp_cp_cp_p5'),
      );

      await ContaPagarFinanceiroExclusaoService.cancelarContaPagar(
        lojaId: lojaId,
        conta: cpBox.get('cp_p5')!,
        excluirLancamentoVinculado: false,
      );

      final compraBox = await CompraFornecedorHiveStore.openBox(lojaId);
      expect(compraBox, isNotNull);
      final compra = compraBox!.get('compra-excl')!;
      expect(compra.valorPago, 0);
      expect(compra.statusPagamento, CompraFornecedorStatusPagamento.pendente);
    });

    test('cancelar duas vezes é idempotente', () async {
      final cpBox = await ContaPagarHiveStore.openBox(lojaId);
      await cpBox!.put('cp_dup', _conta(id: 'cp_dup'));

      final c1 = await ContaPagarFinanceiroExclusaoService.cancelarContaPagar(
        lojaId: lojaId,
        conta: cpBox.get('cp_dup')!,
      );
      final c2 = await ContaPagarFinanceiroExclusaoService.cancelarContaPagar(
        lojaId: lojaId,
        conta: cpBox.get('cp_dup')!,
      );

      expect(c1.contaCancelada, isTrue);
      expect(c2.contaCancelada, isTrue);
      expect(c2.jaEstavaCancelada, isTrue);
    });

    test('parcelas canceladas não bloqueiam nova geração', () async {
      final cpBox = await ContaPagarHiveStore.openBox(lojaId);
      await cpBox!.put(
        'compra-excl_p1',
        _conta(id: 'compra-excl_p1', status: ContaPagarStatus.cancelado),
      );

      expect(
        ContaPagarService.existeParcelasParaCompra(cpBox, 'compra-excl'),
        isFalse,
      );
    });
  });
}
