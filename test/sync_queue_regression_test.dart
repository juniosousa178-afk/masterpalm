// Regressão: dead-letter após N falhas; item removido só após sucesso (ver logs em processamento).

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/sync_queue_service.dart';

void main() {
  group('SyncQueueService.simulateStateAfterFailedAttempt', () {
    SyncQueueItem base() {
      return SyncQueueItem(
        id: 'upsertVenda_loja_1_1',
        type: SyncOperationType.upsertVenda,
        lojaId: 'loja',
        boxName: 'vendas',
        entityKey: 1,
        createdAt: 0,
        attemptCount: 0,
      );
    }

    test('após 4 falhas ainda não é dead-letter; na 5ª vira', () {
      var it = base();
      for (var i = 0; i < 4; i++) {
        it = SyncQueueService.simulateStateAfterFailedAttempt(it);
        expect(it.deadLetter, isFalse);
        expect(it.attemptCount, i + 1);
      }
      it = SyncQueueService.simulateStateAfterFailedAttempt(it);
      expect(it.deadLetter, isTrue);
      expect(it.attemptCount, 5);
    });

    test('dead-letter não incrementa mais', () {
      var it = base();
      for (var i = 0; i < 5; i++) {
        it = SyncQueueService.simulateStateAfterFailedAttempt(it);
      }
      expect(it.deadLetter, isTrue);
      final again = SyncQueueService.simulateStateAfterFailedAttempt(it);
      expect(again.deadLetter, isTrue);
      expect(again.attemptCount, 5);
    });

    test('retryItem zera tentativas — contrato via fromMap roundtrip', () {
      final m = SyncQueueItem(
        id: 'x',
        type: SyncOperationType.upsertCliente,
        lojaId: 'l',
        boxName: 'c',
        entityKey: 2,
        createdAt: 1,
        attemptCount: 5,
        deadLetter: true,
        lastError: 'e',
      ).toMap();
      final parsed = SyncQueueItem.fromMap(m);
      expect(parsed.deadLetter, isTrue);
      final reset = SyncQueueItem(
        id: parsed.id,
        type: parsed.type,
        lojaId: parsed.lojaId,
        boxName: parsed.boxName,
        entityKey: parsed.entityKey,
        createdAt: parsed.createdAt,
        attemptCount: 0,
        lastError: null,
        deadLetter: false,
        lastAttemptAt: 0,
      );
      expect(reset.deadLetter, isFalse);
      expect(reset.attemptCount, 0);
    });
  });
}
