// Baixa parcial de contas a receber.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/conta_receber_service.dart';
import 'package:master_palm/services/financeiro_hive_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const lojaId = 'loja-cr-parcial-20260602';

  late String hivePath;
  late Box<ContaReceber> crBox;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_cr_parcial_');
    hivePath = dir.path;
    Hive.init(hivePath);
    if (!Hive.isAdapterRegistered(29)) {
      Hive.registerAdapter(ContaReceberAdapter());
    }
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
  });

  tearDownAll(() async {
    try {
      await Directory(hivePath).delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    crBox = await Hive.openBox<ContaReceber>(
      'cr_parcial_${DateTime.now().microsecondsSinceEpoch}',
    );
    await FinanceiroHiveStore.openLancamentosBox(lojaId);
  });

  tearDown(() async {
    await crBox.close();
  });

  ContaReceber novaConta({required double valor}) {
    return ContaReceber(
      lojaId: lojaId,
      clienteNome: 'Maria',
      valor: valor,
      valorOriginal: valor,
      dataVencimento: DateTime.now().add(const Duration(days: 10)),
      dataVenda: DateTime.now(),
    );
  }

  group('ContaReceberService.validarValorBaixa', () {
    test('bloqueia zero e negativo', () {
      expect(
        () => ContaReceberService.validarValorBaixa(
          valorRecebido: 0,
          saldoRestante: 180,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => ContaReceberService.validarValorBaixa(
          valorRecebido: -10,
          saldoRestante: 180,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('bloqueia pagamento maior que saldo', () {
      expect(
        () => ContaReceberService.validarValorBaixa(
          valorRecebido: 181,
          saldoRestante: 180,
        ),
        throwsA(
          predicate<ArgumentError>(
            (e) => e.message.toString().contains('maior que o saldo'),
          ),
        ),
      );
    });
  });

  group('ContaReceberService.aplicarBaixaNaConta', () {
    test('R\$ 180 recebe R\$ 120 → parcial, saldo R\$ 60', () {
      final c = novaConta(valor: 180);
      ContaReceberService.aplicarBaixaNaConta(
        conta: c,
        valorRecebido: 120,
        formaPagamento: 'Pix',
        dataRecebimento: DateTime(2026, 6, 2),
      );
      expect(c.valorOriginal, closeTo(180, 0.01));
      expect(c.valorPago, closeTo(120, 0.01));
      expect(c.saldoRestante, closeTo(60, 0.01));
      expect(c.status, ContaReceberStatus.parcial);
      expect(c.pago, isFalse);
    });

    test('parcial R\$ 60 depois R\$ 60 → paga, saldo 0', () {
      final c = novaConta(valor: 180);
      ContaReceberService.aplicarBaixaNaConta(
        conta: c,
        valorRecebido: 120,
        formaPagamento: 'Pix',
        dataRecebimento: DateTime(2026, 6, 1),
      );
      ContaReceberService.aplicarBaixaNaConta(
        conta: c,
        valorRecebido: 60,
        formaPagamento: 'Dinheiro',
        dataRecebimento: DateTime(2026, 6, 10),
      );
      expect(c.saldoRestante, closeTo(0, 0.01));
      expect(c.valorPago, closeTo(180, 0.01));
      expect(c.status, ContaReceberStatus.paga);
      expect(c.pago, isTrue);
    });

    test('baixa total antiga continua funcionando', () {
      final c = novaConta(valor: 50);
      ContaReceberService.aplicarBaixaNaConta(
        conta: c,
        valorRecebido: 50,
        formaPagamento: 'Cartão',
        dataRecebimento: DateTime(2026, 6, 2),
      );
      expect(c.pago, isTrue);
      expect(c.status, ContaReceberStatus.paga);
    });

    test('histórico registra recebimentos', () {
      final c = novaConta(valor: 180);
      ContaReceberService.aplicarBaixaNaConta(
        conta: c,
        valorRecebido: 120,
        formaPagamento: 'Pix',
        dataRecebimento: DateTime(2026, 6, 2),
      );
      final hist = c.historicoPagamentos();
      expect(hist.length, 1);
      expect((hist.first['valor'] as num).toDouble(), closeTo(120, 0.01));
      expect(hist.first['forma'], 'Pix');
    });

    test('conta vencida parcial mantém saldo em aberto', () {
      final c = ContaReceber(
        lojaId: lojaId,
        clienteNome: 'João',
        valor: 200,
        valorOriginal: 200,
        dataVencimento: DateTime.now().subtract(const Duration(days: 5)),
        dataVenda: DateTime.now().subtract(const Duration(days: 30)),
      );
      ContaReceberService.aplicarBaixaNaConta(
        conta: c,
        valorRecebido: 80,
        formaPagamento: 'Pix',
        dataRecebimento: DateTime.now(),
      );
      expect(c.pago, isFalse);
      expect(c.saldoRestante, closeTo(120, 0.01));
      expect(c.status, ContaReceberStatus.parcial);
    });
  });

  group('ContaReceberService.registrarBaixa', () {
    test('persiste baixa parcial e registra caixa', () async {
      await crBox.add(novaConta(valor: 180));
      final c = crBox.values.first;
      final key = c.key as int;

      final r = await ContaReceberService.registrarBaixa(
        conta: c,
        valorRecebido: 120,
        formaPagamento: 'Pix',
        lojaId: lojaId,
        contaHiveKey: key,
      );

      expect(r.sucesso, isTrue);
      expect(r.quitado, isFalse);
      expect(r.saldoRestante, closeTo(60, 0.01));
      expect(c.status, ContaReceberStatus.parcial);

      final finBox = await FinanceiroHiveStore.openLancamentosBox(lojaId);
      expect(finBox, isNotNull);
      final entradas = finBox!.values.where(
        (l) =>
            l.origem == FinanceiroOrigemLancamento.contaReceberFiado &&
            l.status == FinanceiroStatusLancamento.pago,
      );
      expect(entradas.length, 1);
      expect(entradas.first.valor, closeTo(120, 0.01));
    });
  });
}
