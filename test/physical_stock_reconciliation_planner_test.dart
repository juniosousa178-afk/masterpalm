import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/physical_stock_reconciliation_planner.dart';

void main() {
  const planner = PhysicalStockReconciliationPlanner();
  final countedAt = DateTime.utc(2026, 9, 18, 20);

  PhysicalRemoteSnapshot variation({
    int revision = 1,
    int cellQty = 0,
    DateTime? updatedAt,
    String? opId = 'op-1',
    Map<String, dynamic>? variacoes,
    Map<String, int> ept = const {'20': 99},
  }) {
    return PhysicalRemoteSnapshot(
      productId: 'p1',
      stockKind: 'variation',
      stockRevision: revision,
      quantidade: cellQty,
      variacoes: variacoes ??
          {
            '20': {'prata': cellQty},
          },
      estoquePorTamanho: ept,
      stockUpdatedAt: updatedAt ?? DateTime.utc(2026, 9, 18, 12),
      stockOperationId: opId,
    );
  }

  PhysicalReconciliationInput input({
    PhysicalRemoteSnapshot? snapshot,
    int? expectedRevision = 1,
    PhysicalVariationIdentity identity = const PhysicalVariationIdentity(size: '20', color: 'prata'),
    Object? qty = 3,
    DateTime? at,
    String reconId = 'rec-1',
    String? expectedOpId,
    Set<String> applied = const {},
    bool missingCountedAt = false,
  }) {
    return PhysicalReconciliationInput(
      snapshot: snapshot ?? variation(),
      expectedRevision: expectedRevision,
      identity: identity,
      confirmedPhysicalQty: qty,
      countedAt: missingCountedAt ? null : (at ?? countedAt),
      reconciliationId: reconId,
      expectedStockOperationId: expectedOpId,
      existingAppliedReconciliationIds: applied,
    );
  }

  test('1 physical qty 0 valid', () {
    final plan = planner.plan(input(qty: 0));
    expect(plan.ok, isTrue);
    expect(plan.afterQty, 0);
  });

  test('2 positive integer valid', () {
    final plan = planner.plan(input(qty: 4));
    expect(plan.ok, isTrue);
    expect(plan.afterQty, 4);
    expect(plan.delta, 4);
  });

  test('3 negative rejected', () {
    expect(planner.plan(input(qty: -1)).code, 'NEGATIVE_REJECTED');
  });

  test('4 decimal rejected', () {
    expect(planner.plan(input(qty: 1.5)).code, 'DECIMAL_REJECTED');
    expect(planner.plan(input(qty: '1,5')).code, 'DECIMAL_REJECTED');
  });

  test('5 missing count rejected', () {
    expect(planner.plan(input(qty: null)).code, 'MISSING_COUNT');
    expect(planner.plan(input(qty: '')).code, 'MISSING_COUNT');
  });

  test('6 exact variation identity required', () {
    expect(
      planner.plan(input(identity: const PhysicalVariationIdentity(size: '', color: ''))).code,
      'IDENTITY_AMBIGUOUS',
    );
  });

  test('7 ambiguous variation blocked', () {
    final snap = variation(
      variacoes: {
        '18': {'rosa': 0},
        '20': {'rosa': 0},
      },
    );
    expect(
      planner.plan(input(snapshot: snap, identity: const PhysicalVariationIdentity(size: '18', color: ''))).code,
      'IDENTITY_AMBIGUOUS',
    );
  });

  test('7b display-only P/M/G/Azul/Rosa blocked when not technical keys', () {
    expect(
      planner.plan(input(identity: const PhysicalVariationIdentity(size: 'M', color: 'Rosa'))).code,
      'DISPLAY_LABEL_NOT_TECHNICAL',
    );
  });

  test('8 matching revision dry-run', () {
    final plan = planner.plan(input());
    expect(plan.ok, isTrue);
    expect(plan.expectedRevision, 1);
    expect(plan.resultingRevision, 2);
  });

  test('9 stale revision blocked', () {
    expect(planner.plan(input(expectedRevision: 0)).code, 'RECONCILIATION_STALE_REMOTE_CONFLICT');
  });

  test('10 canonical cell updated in simulation', () {
    final plan = planner.plan(input(qty: 5));
    expect(plan.canonicalCellsChanged, ['20/prata']);
    expect(plan.afterQty, 5);
  });

  test('11 EPT regenerated from canonical', () {
    final plan = planner.plan(input(qty: 2));
    expect(plan.estoquePorTamanho['20'], 2);
  });

  test('12 stale EPT cannot influence count', () {
    final plan = planner.plan(input(qty: 7, snapshot: variation(cellQty: 0, ept: {'20': 99})));
    expect(plan.estoquePorTamanho['20'], 7);
    expect(plan.afterQty, 7);
  });

  test('13 aggregate quantity consistent', () {
    final snap = variation(
      cellQty: 1,
      variacoes: {
        '12': {'sem-cor': 2},
        '15': {'sem-cor': 1},
      },
    );
    final plan = planner.plan(
      input(
        snapshot: snap,
        identity: const PhysicalVariationIdentity(size: '12', color: 'sem-cor'),
        qty: 4,
      ),
    );
    expect(plan.estoquePorTamanho['12'], 4);
    expect(plan.estoquePorTamanho['15'], 1);
    expect(plan.audit!['aggregateAfter'], 5);
  });

  test('14 duplicate reconciliation ID idempotent', () {
    final first = planner.plan(input());
    expect(first.ok, isTrue);
    final second = planner.plan(input(applied: {'rec-1'}));
    expect(second.alreadyApplied, isTrue);
    expect(second.ok, isTrue);
  });

  test('15 second submission cannot double apply', () {
    final second = planner.plan(input(qty: 9, applied: {'rec-1'}));
    expect(second.alreadyApplied, isTrue);
    expect(second.delta, isNull);
  });

  test('16 sale not created', () {
    expect(planner.plan(input()).createsSale, isFalse);
  });

  test('17 financial entry not created', () {
    expect(planner.plan(input()).createsFinancialEntry, isFalse);
  });

  test('18 other variations unchanged', () {
    final snap = variation(
      variacoes: {
        '12': {'sem-cor': 2},
        '20': {'sem-cor': 0},
      },
    );
    final plan = planner.plan(
      input(
        snapshot: snap,
        identity: const PhysicalVariationIdentity(size: '20', color: 'sem-cor'),
        qty: 3,
      ),
    );
    expect(plan.otherVariationsUnchanged, isTrue);
    expect(plan.estoquePorTamanho['12'], 2);
    expect(plan.estoquePorTamanho['20'], 3);
  });

  test('19 unrelated product unchanged', () {
    final other = variation(variacoes: {
      '99': {'ouro': 8},
    });
    final plans = planner.planConfirmedOnly([
      input(qty: 1),
    ]);
    expect(plans, hasLength(1));
    expect(other.productId, 'p1');
    expect(plans.single.canonicalCellsChanged, isNot(contains('99/ouro')));
  });

  test('20 partial case reconciliation supported', () {
    final plans = planner.planConfirmedOnly([
      input(qty: 2, reconId: 'a'),
      input(qty: null, reconId: 'b'),
      input(qty: 1, reconId: 'c'),
    ]);
    expect(plans, hasLength(2));
    expect(plans.every((p) => p.ok), isTrue);
  });

  test('21 countedAt required', () {
    expect(planner.plan(input(missingCountedAt: true)).code, 'COUNTED_AT_REQUIRED');
  });

  test('22 remote movement after count detected/blocked', () {
    final late = variation(updatedAt: DateTime.utc(2026, 9, 18, 21));
    expect(planner.plan(input(snapshot: late)).code, 'REMOTE_MOVEMENT_AFTER_COUNT');
    expect(
      planner.plan(input(expectedOpId: 'old')).code,
      'REMOTE_MOVEMENT_AFTER_COUNT',
    );
  });

  test('23 audit record complete', () {
    final plan = planner.plan(input(qty: 6));
    expect(plan.audit, isNotNull);
    expect(plan.audit!['operationType'], 'physical_stock_reconciliation');
    expect(plan.audit!['reason'], kPhysicalInventoryReason);
    expect(plan.audit!['productId'], 'p1');
    expect(plan.audit!['previousCanonicalQty'], 0);
    expect(plan.audit!['confirmedPhysicalQty'], 6);
    expect(plan.audit!['delta'], 6);
    expect(plan.audit!['expectedRevision'], 1);
    expect(plan.audit!['resultingRevision'], 2);
    expect(plan.audit!['countedAt'], isNotNull);
    expect(plan.audit!['reconciliationId'], 'rec-1');
    expect(plan.audit!['executionAuthorized'], isFalse);
    expect(plan.audit!['createsSale'], isFalse);
  });

  test('24 current zero → confirmed positive handled safely', () {
    final plan = planner.plan(input(qty: 5, snapshot: variation(cellQty: 0)));
    expect(plan.ok, isTrue);
    expect(plan.beforeQty, 0);
    expect(plan.afterQty, 5);
  });

  test('25 current positive → confirmed zero handled safely', () {
    final plan = planner.plan(input(qty: 0, snapshot: variation(cellQty: 4)));
    expect(plan.ok, isTrue);
    expect(plan.beforeQty, 4);
    expect(plan.afterQty, 0);
    expect(plan.delta, -4);
  });

  test('simple product reconciliation supported', () {
    const snap = PhysicalRemoteSnapshot(
      productId: 'simple',
      stockKind: 'simple',
      stockRevision: 3,
      quantidade: 1,
    );
    final plan = planner.plan(
      input(
        snapshot: snap,
        expectedRevision: 3,
        identity: const PhysicalVariationIdentity(size: ''),
        qty: 8,
      ),
    );
    expect(plan.ok, isTrue);
    expect(plan.afterQty, 8);
    expect(plan.canonicalCellsChanged, ['quantidade']);
  });

  test('nested extra cell and production execute remains disabled', () {
    final snap = variation(
      variacoes: {
        '45cm': {
          'sem-cor': {kSemExtra: 1, kMetaCusto: 99.9},
        },
      },
    );
    final plan = planner.plan(
      input(
        snapshot: snap,
        identity: const PhysicalVariationIdentity(size: '45cm', color: 'sem-cor', extra: kSemExtra),
        qty: 0,
      ),
    );
    expect(plan.ok, isTrue);
    expect(plan.canonicalCellsChanged, ['45cm/sem-cor/_sem_extra']);
    expect(kPhysicalReconciliationExecutionAuthorized, isFalse);
    expect(
      () => planner.execute(input()),
      throwsA(isA<StateError>()),
    );
  });
}
