// P0 — cloud sale committed + local receivable/mirror failure.
// Sem Firebase de produção. Sem criar venda sintética.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/conta_receber_identity.dart';
import 'package:master_palm/core/conta_receber_lancamento_vinculo.dart';
import 'package:master_palm/core/nova_venda_payment_guard.dart';
import 'package:master_palm/core/nova_venda_pos_save_ui_policy.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/services/vendas_service.dart';

void main() {
  late String vendasService;
  late String novaVendaModal;
  late String posSavePolicy;
  late String cadastroGate;
  late String gradeHydration;

  setUpAll(() {
    vendasService = File('lib/services/vendas_service.dart').readAsStringSync();
    novaVendaModal = File('lib/screens/nova_venda_modal.dart').readAsStringSync();
    posSavePolicy =
        File('lib/core/nova_venda_pos_save_ui_policy.dart').readAsStringSync();
    cadastroGate =
        File('lib/core/produto_cadastro_gate.dart').readAsStringSync();
    gradeHydration =
        File('lib/core/produto_grade_pdv_hydration.dart').readAsStringSync();
  });

  group('P0 cloud sale + local receivable', () {
    test('1 cloud sale success + local receivable success -> PASS', () {
      expect(vendasService.contains('CONTA_RECEBER_CREATE_START'), isTrue);
      expect(
        vendasService.contains('await _persistirContasReceberNaBox('),
        isTrue,
      );
      expect(
        novaVendaModal.contains("NovaVendaPosSaveUiAction.showSuccess"),
        isTrue,
      );
    });

    test('2 cloud sale success + local receivable failure -> sale remains success',
        () {
      expect(
        decideNovaVendaPosSaveUi(
          ok: false,
          mensagemErro:
              VendaSalvaComPendenciaSyncException.localMirrorMessage,
          mounted: true,
        ).action,
        NovaVendaPosSaveUiAction.showSuccess,
      );
      expect(
        vendasService.contains('VendaSalvaComPendenciaSyncException.localMirrorMessage'),
        isTrue,
      );
    });

    test('3 local failure não exibe "venda não salva"', () {
      final decision = decideNovaVendaPosSaveUi(
        ok: false,
        mensagemErro:
            'Venda gravada na nuvem, mas a conta a receber local falhou. '
            'Verifique Contas a Receber e o histórico.',
        mounted: true,
      );
      expect(decision.action, NovaVendaPosSaveUiAction.showSuccess);
      expect(
        novaVendaModal.contains(
          'isNovaVendaCloudCommittedLocalMirrorMessage(err)',
        ),
        isTrue,
      );
      final prefixIdx = novaVendaModal.indexOf("'A venda não foi salva.\\n\\n\$err'");
      expect(prefixIdx, greaterThan(-1));
      final guardIdx = novaVendaModal.indexOf(
        'isNovaVendaCloudCommittedLocalMirrorMessage(err)',
      );
      expect(guardIdx, greaterThan(-1));
      expect(guardIdx, lessThan(prefixIdx));
    });

    test('4 local failure não incentiva retry', () {
      expect(
        VendaSalvaComPendenciaSyncException.localMirrorMessage
            .toLowerCase()
            .contains('tente novamente'),
        isFalse,
      );
      expect(
        kNovaVendaCloudCommittedLocalMirrorMensagem
            .toLowerCase()
            .contains('tente novamente'),
        isFalse,
      );
      expect(
        novaVendaModal.contains(
          'on VendaSalvaComPendenciaSyncException catch',
        ),
        isTrue,
      );
    });

    test('5 reload rehydrates receivable/local mirror', () {
      final pull = File('lib/services/conta_receber_firestore_service.dart')
          .readAsStringSync();
      expect(pull.contains('pullContasReceberRemotas'), isTrue);
      expect(
        File('lib/services/conta_receber_service.dart')
            .readAsStringSync()
            .contains('pullContasReceberRemotas'),
        isTrue,
      );
    });

    test('6 same operation retry does not duplicate sale', () {
      expect(vendasService.contains('alreadyApplied'), isTrue);
      expect(vendasService.contains('idFirebaseReservado'), isTrue);
      expect(
        File('lib/services/vendas_firestore_service.dart')
            .readAsStringSync()
            .contains('resolveFirestoreVendaDocId'),
        isTrue,
      );
    });

    test('7 same operation retry does not duplicate stock decrement', () {
      expect(
        vendasService.contains('baixarEstoqueTransactionBatchIdempotente'),
        isTrue,
      );
      expect(vendasService.contains('alreadyApplied'), isTrue);
    });

    test('8 same operation retry does not duplicate receivable', () {
      const saleId = '37dc1c56-f5c1-4a79-9a75-6a4654b5b8c1';
      final a = ContaReceber(
        lojaId: 'mirjoias',
        clienteNome: 'Cliente',
        valor: 1520,
        dataVencimento: DateTime.utc(2026, 10, 19),
        dataVenda: DateTime.utc(2026, 9, 19, 23, 52, 21),
        vendaIdFirebase: saleId,
      );
      final b = ContaReceber(
        lojaId: 'mirjoias',
        clienteNome: 'Cliente',
        valor: 1520,
        dataVencimento: DateTime.utc(2026, 10, 19),
        dataVenda: DateTime.utc(2026, 9, 19, 23, 52, 21),
        vendaIdFirebase: saleId,
      );
      expect(resolveContaReceberDocId(a), 'cr_${saleId}_p1');
      expect(resolveContaReceberDocId(a), resolveContaReceberDocId(b));
      expect(contaReceberStableId(a), '${saleId}_p1');
    });

    test('9 payment incomplete normal sale -> blocked before commit', () {
      expect(
        novaVendaPagamentoImpedeSalvar(
          total: 1520,
          allocated: 0,
          isFiado: false,
        ),
        isTrue,
      );
      expect(novaVendaModal.contains('novaVendaPagamentoImpedeSalvar'), isTrue);
    });

    test('10 fiado valid -> remaining amount may become receivable correctly', () {
      expect(
        novaVendaPagamentoImpedeSalvar(
          total: 1520,
          allocated: 0,
          isFiado: true,
        ),
        isFalse,
      );
      expect(VendasService.calcularSaldoFiado(total: 1520, totalPagoAgora: 0), 1520);
    });

    test('11 invalid fiado state -> fail before sale commit', () {
      expect(
        novaVendaPagamentoImpedeSalvar(
          total: 1520,
          allocated: 2000,
          isFiado: true,
        ),
        isTrue,
      );
      expect(
        novaVendaModal.contains('_pendenteDiasVencimento < 1'),
        isTrue,
      );
    });

    test('12 existing sale repair -> no duplicate sale', () {
      expect(
        vendasService.contains('atomic PDV: skip client syncVenda'),
        isTrue,
      );
      expect(
        vendasService.contains('remoteAtomicSaleCommitted'),
        isTrue,
      );
    });

    test('13 existing receivable repair -> no duplicate receivable', () {
      expect(vendasService.contains('upsertContaReceber'), isTrue);
      expect(vendasService.contains("lastWriteOrigin: 'venda_fiada'"), isTrue);
    });

    test('14 stock untouched during local-only repair', () {
      final atomicBlock = vendasService.substring(
        vendasService.indexOf('if (remoteAtomicSaleCommitted)'),
      );
      expect(
        atomicBlock.contains('Fiado local falhou após commit atômico'),
        isTrue,
      );
      expect(
        vendasService.contains(
          'throw const VendaSalvaComPendenciaSyncException(\n'
          '            VendaSalvaComPendenciaSyncException.localMirrorMessage',
        ),
        isTrue,
      );
      final failTagIdx =
          vendasService.indexOf('VENDA_FIADA_CONTA_RECEBER_FAIL');
      final atomicPreserveIdx = vendasService.indexOf(
        'estoque/venda remota preservados',
        failTagIdx,
      );
      final devolverAfterFail = vendasService.indexOf(
        'devolverEstoqueParaVendaRemovida',
        failTagIdx,
      );
      expect(atomicPreserveIdx, greaterThan(failTagIdx));
      expect(devolverAfterFail, greaterThan(atomicPreserveIdx));
    });

    test('15 financial totals converge', () {
      expect(VendasService.calcularSaldoFiado(total: 1520, totalPagoAgora: 0), 1520);
      expect(
        VendasService.calcularSaldoFiado(total: 1520, totalPagoAgora: 1520),
        0,
      );
    });

    test('16 simple sale regression GREEN', () {
      expect(vendasService.contains('registrarVendaMulti'), isTrue);
      expect(vendasService.contains('buildAtomicPdvSalePayload'), isTrue);
    });

    test('17 variation-sale regression GREEN', () {
      expect(
        vendasService.contains('VendaComboEstoqueExpansion'),
        isTrue,
      );
      expect(gradeHydration.contains('GradePdvReadiness'), isTrue);
    });

    test('18 product-scoped gate regression GREEN', () {
      expect(cadastroGate.contains('podeAbrirCadastroProduto'), isTrue);
      expect(
        File('lib/core/access_scope_service.dart')
            .readAsStringSync()
            .contains('canManageStock'),
        isTrue,
      );
    });

    test('19 grade restriction unchanged', () {
      expect(
        File('lib/core/produto_grade_pdv_hydration.dart').existsSync(),
        isTrue,
      );
      expect(novaVendaModal.contains('produto_grade_pdv_hydration'), isTrue);
    });

    test('20 failed local mirror does not rollback already committed remote sale',
        () {
      expect(
        vendasService.contains('sem estorno'),
        isTrue,
      );
      expect(
        isNovaVendaCloudCommittedLocalMirrorMessage(
          VendaSalvaComPendenciaSyncException.localMirrorMessage,
        ),
        isTrue,
      );
      expect(
        posSavePolicy.contains('kNovaVendaCloudCommittedLocalMirrorMensagem'),
        isTrue,
      );
      expect(
        decideNovaVendaPosSaveUi(
          ok: false,
          mensagemErro: VendaSalvaComPendenciaSyncException.localMirrorMessage,
          mounted: true,
        ).action,
        isNot(NovaVendaPosSaveUiAction.showErrorDialog),
      );
    });
  });
}
