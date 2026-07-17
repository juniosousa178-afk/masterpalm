// M3.9 Sprint4-R4.2 — VENDA-PERF-1..5

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/nova_venda_pos_save_ui_policy.dart';
import 'package:master_palm/core/nova_venda_ui_release_policy.dart';

void main() {
  group('VENDA-PERF', () {
    test('VENDA-PERF-1 Libera UI após persistência local confirmada', () {
      expect(
        canReleaseUiAfterLocalPersist(
          hivePersisted: true,
          journalCompleted: true,
          isFiado: false,
          fiadoReceivableReady: false,
          saleIntentPersistedOrSkipped: true,
        ),
        isTrue,
      );
    });

    test('VENDA-PERF-2 Sync/campanha são secundários (não bloqueiam política)', () {
      expect(isSecondaryPostPersistWork('sync_begin'), isTrue);
      expect(isSecondaryPostPersistWork('campaign'), isTrue);
      expect(isSecondaryPostPersistWork('hive_ok'), isFalse);
    });

    test('VENDA-PERF-3 Sem Hive/Journal não libera UI', () {
      expect(
        canReleaseUiAfterLocalPersist(
          hivePersisted: false,
          journalCompleted: true,
          isFiado: false,
          fiadoReceivableReady: false,
          saleIntentPersistedOrSkipped: true,
        ),
        isFalse,
      );
      expect(
        canReleaseUiAfterLocalPersist(
          hivePersisted: true,
          journalCompleted: false,
          isFiado: false,
          fiadoReceivableReady: false,
          saleIntentPersistedOrSkipped: true,
        ),
        isFalse,
      );
    });

    test('VENDA-PERF-4 Fiado só libera após ContaReceber', () {
      expect(
        canReleaseUiAfterLocalPersist(
          hivePersisted: true,
          journalCompleted: true,
          isFiado: true,
          fiadoReceivableReady: false,
          saleIntentPersistedOrSkipped: true,
        ),
        isFalse,
      );
      expect(
        canReleaseUiAfterLocalPersist(
          hivePersisted: true,
          journalCompleted: true,
          isFiado: true,
          fiadoReceivableReady: true,
          saleIntentPersistedOrSkipped: true,
        ),
        isTrue,
      );
    });

    test('VENDA-PERF-5 Falha real mantém erro (não sucesso)', () {
      final d = decideNovaVendaPosSaveUi(
        ok: false,
        mensagemErro: 'Falha de estoque',
        mounted: true,
      );
      expect(d.action, NovaVendaPosSaveUiAction.showErrorDialog);
      expect(d.errorMessage, contains('estoque'));
    });
  });
}
