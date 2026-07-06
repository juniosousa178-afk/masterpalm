// Unitários SaleIntentService (FakeFirebaseFirestore).

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/sale_intent_service.dart';

const _loja = 'loja-sale-intent-unit';
const _hashX = 'hash-stock-effect-x';
const _hashY = 'hash-stock-effect-y';
const _origin = SaleIntentOrigins.pdvManual;

void main() {
  late FakeFirebaseFirestore firestore;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    SaleIntentService.debugFirestoreOverride = firestore;
  });

  tearDown(() {
    SaleIntentService.debugClearOverride();
  });

  Future<SaleIntentReservation> reserve({
    required String intentId,
    String hash = _hashX,
    String origin = _origin,
  }) {
    return SaleIntentService.reserveOrJoin(
      lojaId: _loja,
      saleIntentId: intentId,
      origin: origin,
      stockEffectHash: hash,
    );
  }

  group('SaleIntentService — SIT', () {
    test('SIT-1 reserve ausente → created + operationId', () async {
      final r = await reserve(intentId: 'intent-sit-1');
      expect(r.reserveStatus, SaleIntentReserveStatus.created);
      expect(r.status, SaleIntentStatus.reserved);
      expect(r.operationId, isNotEmpty);
      expect(r.saleIntentId, 'intent-sit-1');
    });

    test('SIT-2 join mesma intent/hash/origin → mesmo operationId', () async {
      const id = 'intent-sit-2';
      final a = await reserve(intentId: id);
      final b = await reserve(intentId: id);
      expect(b.reserveStatus, SaleIntentReserveStatus.joined);
      expect(b.operationId, a.operationId);
    });

    test('SIT-3 hash divergente → SaleIntentIdentityConflictException', () async {
      const id = 'intent-sit-3';
      await reserve(intentId: id, hash: _hashX);
      await expectLater(
        reserve(intentId: id, hash: _hashY),
        throwsA(isA<SaleIntentIdentityConflictException>()),
      );
    });

    test('SIT-4 origin divergente → conflito fail-closed (ORIGIN-A)', () async {
      const id = 'intent-sit-4';
      await reserve(intentId: id, origin: SaleIntentOrigins.pdvManual);
      await expectLater(
        reserve(intentId: id, origin: SaleIntentOrigins.orderReview),
        throwsA(isA<SaleIntentIdentityConflictException>()),
      );
    });

    test('SIT-5 operationId nunca regenerado em joins', () async {
      const id = 'intent-sit-5';
      final first = await reserve(intentId: id);
      for (var i = 0; i < 3; i++) {
        final j = await reserve(intentId: id);
        expect(j.operationId, first.operationId);
      }
    });

    test('SIT-6 reserved → stock_applied', () async {
      const id = 'intent-sit-6';
      final created = await reserve(intentId: id);
      final next = await SaleIntentService.markStockApplied(
        lojaId: _loja,
        saleIntentId: id,
        operationId: created.operationId,
      );
      expect(next.status, SaleIntentStatus.stockApplied);
    });

    test('SIT-7 stock_applied → sale_persisted', () async {
      const id = 'intent-sit-7';
      final created = await reserve(intentId: id);
      await SaleIntentService.markStockApplied(
        lojaId: _loja,
        saleIntentId: id,
        operationId: created.operationId,
      );
      final next = await SaleIntentService.markSalePersisted(
        lojaId: _loja,
        saleIntentId: id,
        operationId: created.operationId,
      );
      expect(next.status, SaleIntentStatus.salePersisted);
    });

    test('SIT-8 sale_persisted → completed', () async {
      const id = 'intent-sit-8';
      final created = await reserve(intentId: id);
      final op = created.operationId;
      await SaleIntentService.markStockApplied(
        lojaId: _loja,
        saleIntentId: id,
        operationId: op,
      );
      await SaleIntentService.markSalePersisted(
        lojaId: _loja,
        saleIntentId: id,
        operationId: op,
      );
      final done = await SaleIntentService.complete(
        lojaId: _loja,
        saleIntentId: id,
        operationId: op,
      );
      expect(done.status, SaleIntentStatus.completed);
    });

    test('SIT-9 completed → reserved proibido', () async {
      const id = 'intent-sit-9';
      final created = await reserve(intentId: id);
      final op = created.operationId;
      await SaleIntentService.markStockApplied(
        lojaId: _loja,
        saleIntentId: id,
        operationId: op,
      );
      await SaleIntentService.markSalePersisted(
        lojaId: _loja,
        saleIntentId: id,
        operationId: op,
      );
      await SaleIntentService.complete(
        lojaId: _loja,
        saleIntentId: id,
        operationId: op,
      );
      await expectLater(
        SaleIntentService.markStockApplied(
          lojaId: _loja,
          saleIntentId: id,
          operationId: op,
        ),
        throwsA(isA<SaleIntentInvalidStateTransitionException>()),
      );
    });

    test('SIT-10 reverted terminal', () async {
      const id = 'intent-sit-10';
      final created = await reserve(intentId: id);
      await SaleIntentService.revert(
        lojaId: _loja,
        saleIntentId: id,
        operationId: created.operationId,
      );
      await expectLater(
        SaleIntentService.markStockApplied(
          lojaId: _loja,
          saleIntentId: id,
          operationId: created.operationId,
        ),
        throwsA(isA<SaleIntentInvalidStateTransitionException>()),
      );
    });

    test('SIT-11 critical terminal', () async {
      const id = 'intent-sit-11';
      final created = await reserve(intentId: id);
      await SaleIntentService.markCritical(
        lojaId: _loja,
        saleIntentId: id,
        operationId: created.operationId,
      );
      await expectLater(
        reserve(intentId: id),
        throwsA(isA<SaleIntentCriticalStateException>()),
      );
    });

    test('SIT-12 operationId divergente em transition → conflito', () async {
      const id = 'intent-sit-12';
      final created = await reserve(intentId: id);
      await expectLater(
        SaleIntentService.markStockApplied(
          lojaId: _loja,
          saleIntentId: id,
          operationId: '00000000-0000-4000-8000-000000000099',
        ),
        throwsA(isA<SaleIntentIdentityConflictException>()),
      );
      expect(created.operationId, isNot('00000000-0000-4000-8000-000000000099'));
    });

    test('SIT-13 schema remoto inválido → fail-closed', () async {
      const id = 'intent-sit-13';
      await firestore
          .collection('lojas')
          .doc(_loja)
          .collection('sale_intents')
          .doc(id)
          .set({
        'protocolVersion': 99,
        'saleIntentId': id,
        'lojaId': _loja,
        'origin': _origin,
        'operationId': 'op-invalid',
        'status': 'reserved',
        'stockEffectHash': _hashX,
        'createdAt': DateTime.now(),
        'updatedAt': DateTime.now(),
      });
      await expectLater(
        reserve(intentId: id),
        throwsA(isA<SaleIntentInvalidSchemaException>()),
      );
    });

    test('SIT-14 completed join preserva operationId/status', () async {
      const id = 'intent-sit-14';
      final created = await reserve(intentId: id);
      final op = created.operationId;
      await SaleIntentService.markStockApplied(
        lojaId: _loja,
        saleIntentId: id,
        operationId: op,
      );
      await SaleIntentService.markSalePersisted(
        lojaId: _loja,
        saleIntentId: id,
        operationId: op,
      );
      await SaleIntentService.complete(
        lojaId: _loja,
        saleIntentId: id,
        operationId: op,
      );
      final joined = await reserve(intentId: id);
      expect(joined.operationId, op);
      expect(joined.status, SaleIntentStatus.completed);
      expect(joined.reserveStatus, SaleIntentReserveStatus.joined);
    });

    test('SIT-15 duas intents + mesmo hash → operationIds distintos', () async {
      final a = await reserve(intentId: 'intent-a-hash-x');
      final b = await reserve(intentId: 'intent-b-hash-x');
      expect(a.operationId, isNot(equals(b.operationId)));
      final snapA = await firestore
          .collection('lojas')
          .doc(_loja)
          .collection('sale_intents')
          .doc('intent-a-hash-x')
          .get();
      final snapB = await firestore
          .collection('lojas')
          .doc(_loja)
          .collection('sale_intents')
          .doc('intent-b-hash-x')
          .get();
      expect(snapA.exists, isTrue);
      expect(snapB.exists, isTrue);
      expect(snapA.data()?['status'], 'reserved');
      expect(snapB.data()?['status'], 'reserved');
    });

    test('SIT-16 saleIntentId não é derivado de stockEffectHash', () async {
      const intentId = 'my-explicit-intent-uuid-001';
      expect(intentId, isNot(_hashX));
      final r = await reserve(intentId: intentId);
      expect(r.saleIntentId, intentId);
      expect(r.stockEffectHash, _hashX);
    });

    test('SIT-R1 reverted → reserveOrJoin mesmo intent → reserved + mesmo operationId',
        () async {
      const id = 'intent-sit-r1';
      final created = await reserve(intentId: id);
      final op = created.operationId;
      await SaleIntentService.markStockApplied(
        lojaId: _loja,
        saleIntentId: id,
        operationId: op,
      );
      await SaleIntentService.revert(
        lojaId: _loja,
        saleIntentId: id,
        operationId: op,
      );
      final retry = await reserve(intentId: id);
      expect(retry.reserveStatus, SaleIntentReserveStatus.joined);
      expect(retry.status, SaleIntentStatus.reserved);
      expect(retry.operationId, op);
      final snap = await firestore
          .collection('lojas')
          .doc(_loja)
          .collection('sale_intents')
          .doc(id)
          .get();
      expect(snap.data()?['status'], 'reserved');
    });

    test('SIT-R2 reverted → reserveOrJoin hash diferente → conflito', () async {
      const id = 'intent-sit-r2';
      final created = await reserve(intentId: id, hash: _hashX);
      await SaleIntentService.revert(
        lojaId: _loja,
        saleIntentId: id,
        operationId: created.operationId,
      );
      await expectLater(
        reserve(intentId: id, hash: _hashY),
        throwsA(isA<SaleIntentIdentityConflictException>()),
      );
    });

    test('SIT-R3 reverted → reserveOrJoin origin diferente → conflito', () async {
      const id = 'intent-sit-r3';
      final created = await reserve(intentId: id, origin: SaleIntentOrigins.pdvManual);
      await SaleIntentService.revert(
        lojaId: _loja,
        saleIntentId: id,
        operationId: created.operationId,
      );
      await expectLater(
        reserve(intentId: id, origin: SaleIntentOrigins.orderReview),
        throwsA(isA<SaleIntentIdentityConflictException>()),
      );
    });

    test('SIT-R4 critical → reserveOrJoin → falha', () async {
      const id = 'intent-sit-r4';
      final created = await reserve(intentId: id);
      await SaleIntentService.markCritical(
        lojaId: _loja,
        saleIntentId: id,
        operationId: created.operationId,
      );
      await expectLater(
        reserve(intentId: id),
        throwsA(isA<SaleIntentCriticalStateException>()),
      );
    });

    test('SIT-R5 completed → reserveOrJoin → completed, não reserved', () async {
      const id = 'intent-sit-r5';
      final created = await reserve(intentId: id);
      final op = created.operationId;
      await SaleIntentService.markStockApplied(
        lojaId: _loja,
        saleIntentId: id,
        operationId: op,
      );
      await SaleIntentService.markSalePersisted(
        lojaId: _loja,
        saleIntentId: id,
        operationId: op,
      );
      await SaleIntentService.complete(
        lojaId: _loja,
        saleIntentId: id,
        operationId: op,
      );
      final joined = await reserve(intentId: id);
      expect(joined.status, SaleIntentStatus.completed);
      expect(joined.operationId, op);
    });

    test('SIT-R6 reverted retry não gera novo operationId', () async {
      const id = 'intent-sit-r6';
      final created = await reserve(intentId: id);
      final op = created.operationId;
      await SaleIntentService.revert(
        lojaId: _loja,
        saleIntentId: id,
        operationId: op,
      );
      final r1 = await reserve(intentId: id);
      final r2 = await reserve(intentId: id);
      expect(r1.operationId, op);
      expect(r2.operationId, op);
    });
  });
}
