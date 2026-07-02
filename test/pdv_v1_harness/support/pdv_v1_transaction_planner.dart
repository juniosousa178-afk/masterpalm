// Planner conceitual da transação PDV V1 — valida pureza e idempotência lógica.
// NÃO executa Firestore real; espelha contrato futuro (estoque + marcador atômico).

class PdvV1PlannedWrite {
  const PdvV1PlannedWrite({
    required this.collection,
    required this.docId,
    required this.op,
  });

  final String collection;
  final String docId;
  final String op; // get | update | set_create | set_merge

  String get key => '$collection/$docId/$op';
}

class PdvV1TransactionPlan {
  const PdvV1TransactionPlan({
    required this.reads,
    required this.writes,
    required this.skipStockBecauseMarker,
  });

  final List<PdvV1PlannedWrite> reads;
  final List<PdvV1PlannedWrite> writes;
  final bool skipStockBecauseMarker;

  int get distinctStockDocs => writes
      .where((w) => w.collection == 'estoque_produtos')
      .map((w) => w.docId)
      .toSet()
      .length;
}

class PdvV1SideEffectCounters {
  int hiveWrites = 0;
  int journalWrites = 0;
  int queueWrites = 0;
  int uuidGenerated = 0;
  int networkCalls = 0;
  int logs = 0;

  void reset() {
    hiveWrites = 0;
    journalWrites = 0;
    queueWrites = 0;
    uuidGenerated = 0;
    networkCalls = 0;
    logs = 0;
  }

  int get total =>
      hiveWrites + journalWrites + queueWrites + uuidGenerated + networkCalls;
}

/// Planner puro: entradas já capturadas fora do callback.
PdvV1TransactionPlan pdvV1PlanStockTransaction({
  required String lojaId,
  required String operationId,
  required String txItemsHash,
  required List<String> estoqueDocIds,
  required bool markerAlreadyApplied,
  required String markerTxHash,
}) {
  final reads = <PdvV1PlannedWrite>[];
  final writes = <PdvV1PlannedWrite>[];

  reads.add(PdvV1PlannedWrite(
    collection: 'estoque_baixa_pagamento',
    docId: operationId,
    op: 'get',
  ));

  if (markerAlreadyApplied && markerTxHash == txItemsHash) {
    return PdvV1TransactionPlan(
      reads: reads,
      writes: const [],
      skipStockBecauseMarker: true,
    );
  }

  for (final docId in estoqueDocIds) {
    reads.add(PdvV1PlannedWrite(
      collection: 'estoque_produtos',
      docId: docId,
      op: 'get',
    ));
    writes.add(PdvV1PlannedWrite(
      collection: 'estoque_produtos',
      docId: docId,
      op: 'update',
    ));
    writes.add(PdvV1PlannedWrite(
      collection: 'estoque_produtos',
      docId: docId,
      op: 'set_merge',
    ));
    writes.add(PdvV1PlannedWrite(
      collection: 'produtos',
      docId: docId,
      op: 'set_merge',
    ));
  }

  writes.add(PdvV1PlannedWrite(
    collection: 'estoque_baixa_pagamento',
    docId: operationId,
    op: 'set_create',
  ));

  return PdvV1TransactionPlan(
    reads: reads,
    writes: writes,
    skipStockBecauseMarker: false,
  );
}

/// Simula execução do callback 3× — side effects externos devem permanecer zero.
({List<PdvV1TransactionPlan> plans, PdvV1SideEffectCounters sideEffects})
    pdvV1RunPurityHarness({
  required String lojaId,
  required String operationId,
  required String txItemsHash,
  required List<String> estoqueDocIds,
  bool markerAlreadyApplied = false,
}) {
  final sideEffects = PdvV1SideEffectCounters();
  final plans = <PdvV1TransactionPlan>[];

  for (var i = 0; i < 3; i++) {
    sideEffects.reset();
    final plan = pdvV1PlanStockTransaction(
      lojaId: lojaId,
      operationId: operationId,
      txItemsHash: txItemsHash,
      estoqueDocIds: estoqueDocIds,
      markerAlreadyApplied: markerAlreadyApplied,
      markerTxHash: txItemsHash,
    );
    plans.add(plan);
  }

  return (plans: plans, sideEffects: sideEffects);
}

bool pdvV1PlansAreIdentical(List<PdvV1TransactionPlan> plans) {
  if (plans.length < 2) return true;
  final firstReads = plans.first.reads.map((r) => r.key).toList();
  final firstWrites = plans.first.writes.map((w) => w.key).toList();
  for (final p in plans.skip(1)) {
    final r = p.reads.map((e) => e.key).toList();
    final w = p.writes.map((e) => e.key).toList();
    if (r.toString() != firstReads.toString() ||
        w.toString() != firstWrites.toString() ||
        p.skipStockBecauseMarker != plans.first.skipStockBecauseMarker) {
      return false;
    }
  }
  return true;
}
