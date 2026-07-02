import 'package:flutter_test/flutter_test.dart';

import 'support/pdv_v1_combo_cap_contract.dart';

/// Contrato combo cap — NÃO implementação real.
void main() {
  group('PDV V1 — combo cap contract harness (Fase 6.4)', () {
    test('conclusão Fase 6.4: subestado journal obrigatório (B)', () {
      expect(
        pdvV1ComboCapConclusaoFase64,
        PdvV1ComboCapClass.postProcessWithSubstate,
      );
    });

    test('recovery não chama baixa principal — só cap sem delta repetido', () {
      const state = PdvV1ComboCapState(
        comboSkuQty: 5,
        maxKitsMontaveis: 3,
        substateCompleted: false,
        operationId: 'op-cap-1',
      );
      expect(
        pdvV1DecidirComboCapRecovery(
          state: state,
          baixaPrincipalConcluida: true,
          journalIntegro: true,
        ),
        PdvV1ComboCapRecoveryDecision.reapplyCapWithoutMainBaixa,
      );
    });

    test('subestado completed + mesmo operationId → skip', () {
      const state = PdvV1ComboCapState(
        comboSkuQty: 3,
        maxKitsMontaveis: 3,
        substateCompleted: true,
        operationId: 'op-cap-1',
        lastCapOperationId: 'op-cap-1',
      );
      expect(
        pdvV1DecidirComboCapRecovery(
          state: state,
          baixaPrincipalConcluida: true,
          journalIntegro: true,
        ),
        PdvV1ComboCapRecoveryDecision.skipAlreadyApplied,
      );
    });

    test('dupla aplicação segura quando qty já no teto', () {
      expect(
        pdvV1ComboCapDuplaAplicacaoSegura(
          comboQtyAfterFirstCap: 3,
          maxKits: 3,
        ),
        isTrue,
      );
      expect(
        pdvV1ComboCapDuplaAplicacaoSegura(
          comboQtyAfterFirstCap: 5,
          maxKits: 3,
        ),
        isFalse,
      );
    });

    test('sem journal → manual', () {
      const state = PdvV1ComboCapState(
        comboSkuQty: 5,
        maxKitsMontaveis: 2,
        substateCompleted: false,
        operationId: 'op-1',
      );
      expect(
        pdvV1DecidirComboCapRecovery(
          state: state,
          baixaPrincipalConcluida: true,
          journalIntegro: false,
        ),
        PdvV1ComboCapRecoveryDecision.manualInterventionRequired,
      );
    });

    test('declaração de escopo', () {
      expect(
        true,
        isTrue,
        reason:
            'Contrato: combo cap derivado de maxKitsMontaveis; recovery via TX secundária '
            'com operationId:combo_cap. NÃO prova: idempotência do código atual '
            '(aplicarTeto chama baixarEstoqueTransactionBatch sem operationId). '
            'Código atual: best-effort via SemAbortarVenda.',
      );
    });
  });
}
