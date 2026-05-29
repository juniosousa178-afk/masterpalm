import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/conta_pagar_lancamento_vinculo.dart';
import 'package:master_palm/core/conta_receber_lancamento_vinculo.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/financeiro/lancamento_financeiro_origem_ui.dart';
import 'package:master_palm/models/compra_fornecedor.dart';
import 'package:master_palm/models/compra_fornecedor_constants.dart';
import 'package:master_palm/models/conta_pagar.dart';
import 'package:master_palm/models/conta_pagar_constants.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/conta_pagar_hive_store.dart';
import 'package:master_palm/services/conta_receber_recebimento_caixa_service.dart';
import 'package:master_palm/services/financeiro_anti_duplicidade_service.dart';
import 'package:master_palm/services/financeiro_service.dart';

void main() {
  const lojaId = 'loja_anti_dup';

  late Directory hiveDir;
  late Box<LancamentoFinanceiro> lancBox;
  late Box<ContaPagar> cpBox;
  late Box<CompraFornecedor> compraBox;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('hive_anti_dup_');
    Hive.init(hiveDir.path);
    ContaPagarHiveStore.ensureAdapterRegistered();
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
    if (!Hive.isAdapterRegistered(32)) {
      Hive.registerAdapter(CompraFornecedorAdapter());
    }
  });

  tearDownAll(() async {
    await Hive.close();
    if (await hiveDir.exists()) {
      await hiveDir.delete(recursive: true);
    }
  });

  setUp(() async {
    final finName = HiveBoxNames.lancamentosFinanceiros(lojaId);
    if (!Hive.isBoxOpen(finName)) {
      lancBox = await Hive.openBox<LancamentoFinanceiro>(finName);
    } else {
      lancBox = Hive.box<LancamentoFinanceiro>(finName);
    }
    await lancBox.clear();

    final cpName = HiveBoxNames.contasPagar(lojaId);
    if (!Hive.isBoxOpen(cpName)) {
      cpBox = await Hive.openBox<ContaPagar>(cpName);
    } else {
      cpBox = Hive.box<ContaPagar>(cpName);
    }
    await cpBox.clear();

    final compraName = HiveBoxNames.comprasFornecedor(lojaId);
    if (!Hive.isBoxOpen(compraName)) {
      compraBox = await Hive.openBox<CompraFornecedor>(compraName);
    } else {
      compraBox = Hive.box<CompraFornecedor>(compraName);
    }
    await compraBox.clear();
  });

  LancamentoFinanceiro candidatoManual({
    double valor = 300,
    String fornecedor = 'Fornecedor X',
  }) {
    return LancamentoFinanceiro(
      id: 'novo_manual',
      lojaId: lojaId,
      descricao: 'Compra mercadoria manual',
      valor: valor,
      tipo: FinanceiroTipoLancamento.compraMercadoria,
      status: FinanceiroStatusLancamento.pago,
      fornecedor: fornecedor,
      dataLancamento: DateTime(2026, 4, 5),
      dataPagamento: DateTime(2026, 4, 5),
      origem: FinanceiroOrigemLancamento.manual,
    );
  }

  test('compra_mercadoria manual detecta ContaPagar paga parecida', () async {
    await cpBox.put(
      'cp1',
      ContaPagar(
        id: 'cp1',
        lojaId: lojaId,
        fornecedorId: 1,
        fornecedorNome: 'Fornecedor X',
        compraId: 'compra-1',
        descricao: 'Parcela 1/3',
        valorTotalCompra: 900,
        valorParcela: 300,
        parcelaNumero: 1,
        parcelaTotal: 3,
        dataVencimento: DateTime(2026, 4, 10),
        dataCompra: DateTime(2026, 4, 1),
        status: ContaPagarStatus.pago,
        dataPagamento: DateTime(2026, 4, 4),
      ),
    );

    final suspeitas = await FinanceiroAntiDuplicidadeService.suspeitasCompraMercadoria(
      lojaId: lojaId,
      candidato: candidatoManual(),
      lancamentosBox: lancBox,
      contasPagarBox: cpBox,
      comprasBox: compraBox,
    );

    expect(suspeitas.any((s) => s.fonte == 'conta_pagar'), isTrue);
  });

  test('compra_mercadoria manual detecta CompraFornecedor confirmada', () async {
    await compraBox.put(
      'compra-1',
      CompraFornecedor(
        id: 'compra-1',
        lojaId: lojaId,
        fornecedorHiveKey: 1,
        fornecedorNome: 'Fornecedor X',
        dataCompra: DateTime(2026, 4, 2),
        statusCompra: CompraFornecedorStatusCompra.confirmada,
        tipoCompra: CompraFornecedorTipo.financeira,
        valorInformado: 300,
      ),
    );

    final suspeitas = await FinanceiroAntiDuplicidadeService.suspeitasCompraMercadoria(
      lojaId: lojaId,
      candidato: candidatoManual(),
      lancamentosBox: lancBox,
      contasPagarBox: cpBox,
      comprasBox: compraBox,
    );

    expect(suspeitas.any((s) => s.fonte == 'compra_fornecedor'), isTrue);
  });

  test('lançamento automático de CP recebe etiqueta correta', () {
    final l = LancamentoFinanceiro(
      id: lancamentoFinanceiroDocIdParaContaPagar('cp-99'),
      lojaId: lojaId,
      descricao: 'Pagamento compra',
      valor: 100,
      tipo: FinanceiroTipoLancamento.compraMercadoria,
      status: FinanceiroStatusLancamento.pago,
      dataLancamento: DateTime(2026, 4, 1),
      origem: FinanceiroOrigemLancamento.contaPagarCompra,
      referenciaExterna: referenciaExternaContaPagar(
        contaPagarId: 'cp-99',
        compraId: 'c1',
      ),
    );

    expect(chipOrigemAutomaticaLancamento(l), 'Gerado por Conta a Pagar');
    expect(lancamentoVinculadoAContaPagar(l), isTrue);
  });

  test('lançamento de Conta a Receber recebe etiqueta correta', () {
    final l = LancamentoFinanceiro(
      id: 'mp_cr_5_1_10000_20260405',
      lojaId: lojaId,
      descricao: 'Recebimento',
      valor: 100,
      tipo: FinanceiroTipoLancamento.entradaExtra,
      status: FinanceiroStatusLancamento.pago,
      dataLancamento: DateTime(2026, 4, 5),
      origem: FinanceiroOrigemLancamento.contaReceberFiado,
      referenciaExterna: referenciaExternaContaReceber(
        contaHiveKey: 5,
        parcelaNumero: 1,
        valor: 100,
        dataRecebimento: DateTime(2026, 4, 5),
      ),
    );

    expect(chipOrigemAutomaticaLancamento(l), 'Gerado por Conta a Receber');
  });

  test('recebimento de ContaReceber não duplica lançamento', () async {
    const hiveKey = 42;
    const valor = 150.0;
    final data = DateTime(2026, 5, 10);

    final id1 = await ContaReceberRecebimentoCaixaService.registrarRecebimento(
      lojaId: lojaId,
      valor: valor,
      formaPagamento: 'Pix',
      clienteNome: 'Cliente Teste',
      contaHiveKey: hiveKey,
      parcelaNumero: 1,
      dataRecebimento: data,
    );
    expect(id1, isNotNull);

    final id2 = await ContaReceberRecebimentoCaixaService.registrarRecebimento(
      lojaId: lojaId,
      valor: valor,
      formaPagamento: 'Pix',
      clienteNome: 'Cliente Teste',
      contaHiveKey: hiveKey,
      parcelaNumero: 1,
      dataRecebimento: data,
    );
    expect(id2, id1);

    final pagos = lancBox.values
        .where(
          (l) =>
              l.lojaId == lojaId &&
              l.status == FinanceiroStatusLancamento.pago &&
              lancamentoVinculadoAContaReceber(l),
        )
        .length;
    expect(pagos, 1);
  });

  test('FinanceiroService.resumoPeriodo inalterado com LF de CP e CR', () async {
    final inicio = DateTime(2026, 4, 1);
    final fim = DateTime(2026, 4, 30, 23, 59, 59, 999);

    final antes = FinanceiroService.resumoPeriodo(
      box: lancBox,
      lojaId: lojaId,
      inicio: inicio,
      fim: fim,
    );

    await lancBox.put(
      'lf_cp',
      LancamentoFinanceiro(
        id: 'lf_cp',
        lojaId: lojaId,
        descricao: 'CP',
        valor: 200,
        tipo: FinanceiroTipoLancamento.compraMercadoria,
        status: FinanceiroStatusLancamento.pago,
        dataLancamento: DateTime(2026, 4, 10),
        dataPagamento: DateTime(2026, 4, 10),
        origem: FinanceiroOrigemLancamento.contaPagarCompra,
      ),
    );

    await ContaReceberRecebimentoCaixaService.registrarRecebimento(
      lojaId: lojaId,
      valor: 80,
      formaPagamento: 'Dinheiro',
      clienteNome: 'C',
      contaHiveKey: 7,
      dataRecebimento: DateTime(2026, 4, 15),
    );

    final depois = FinanceiroService.resumoPeriodo(
      box: lancBox,
      lojaId: lojaId,
      inicio: inicio,
      fim: fim,
    );

    expect(depois.totalCompraMercadoria, antes.totalCompraMercadoria + 200);
    expect(depois.totalEntradasExtras, antes.totalEntradasExtras + 80);
    expect(
      FinanceiroService.fluxoCaixaComVendas(
        somaFormasPagamentoVendas: 0,
        modulo: depois,
      ),
      FinanceiroService.fluxoCaixaComVendas(
        somaFormasPagamentoVendas: 0,
        modulo: antes,
      ) -
          200 +
          80,
    );
  });
}
