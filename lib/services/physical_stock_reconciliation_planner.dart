/// Local dry-run planner for explicit physical-count stock reconciliation.
/// Production execution is hard-disabled in this ticket.
library;

const bool kPhysicalReconciliationExecutionAuthorized = false;
const String kPhysicalInventoryReason = 'PHYSICAL_INVENTORY_RECONCILIATION';
const String kReconcileOperationKind = 'reconcile';
const String kMetaCusto = '__custoUnitario';
const String kSemExtra = '_sem_extra';

String physicalNormKey(String raw) =>
    raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

bool _isMeta(String key) => physicalNormKey(key) == kMetaCusto;

class PhysicalVariationIdentity {
  const PhysicalVariationIdentity({
    required this.size,
    this.color = '',
    this.extra = '',
  });

  final String size;
  final String color;
  final String extra;

  bool get isSimple => size.trim().isEmpty && color.trim().isEmpty && extra.trim().isEmpty;
}

class PhysicalRemoteSnapshot {
  const PhysicalRemoteSnapshot({
    required this.productId,
    required this.stockKind,
    this.stockRevision,
    this.quantidade = 0,
    this.variacoes = const {},
    this.estoquePorTamanho = const {},
    this.stockUpdatedAt,
    this.stockOperationId,
  });

  final String productId;
  final String stockKind;
  final int? stockRevision;
  final int quantidade;
  final Map<String, dynamic> variacoes;
  final Map<String, int> estoquePorTamanho;
  final DateTime? stockUpdatedAt;
  final String? stockOperationId;
}

class PhysicalReconciliationInput {
  const PhysicalReconciliationInput({
    required this.snapshot,
    required this.expectedRevision,
    required this.identity,
    required this.confirmedPhysicalQty,
    required this.countedAt,
    required this.reconciliationId,
    this.expectedStockOperationId,
    this.existingAppliedReconciliationIds = const {},
  });

  final PhysicalRemoteSnapshot snapshot;
  final int? expectedRevision;
  final PhysicalVariationIdentity identity;
  final Object? confirmedPhysicalQty;
  final DateTime? countedAt;
  final String reconciliationId;
  final String? expectedStockOperationId;
  final Set<String> existingAppliedReconciliationIds;
}

class PhysicalReconciliationPlan {
  const PhysicalReconciliationPlan({
    required this.ok,
    this.code,
    this.message,
    this.alreadyApplied = false,
    this.beforeQty,
    this.afterQty,
    this.delta,
    this.canonicalCellsChanged = const [],
    this.estoquePorTamanho = const {},
    this.expectedRevision,
    this.resultingRevision,
    this.audit,
    this.createsSale = false,
    this.createsFinancialEntry = false,
    this.otherVariationsUnchanged = true,
  });

  final bool ok;
  final String? code;
  final String? message;
  final bool alreadyApplied;
  final int? beforeQty;
  final int? afterQty;
  final int? delta;
  final List<String> canonicalCellsChanged;
  final Map<String, int> estoquePorTamanho;
  final int? expectedRevision;
  final int? resultingRevision;
  final Map<String, Object?>? audit;
  final bool createsSale;
  final bool createsFinancialEntry;
  final bool otherVariationsUnchanged;
}

class PhysicalStockReconciliationPlanner {
  const PhysicalStockReconciliationPlanner();

  Never execute(PhysicalReconciliationInput input) {
    throw StateError(
      'RECONCILIATION_EXECUTION_AUTHORIZED=$kPhysicalReconciliationExecutionAuthorized',
    );
  }

  PhysicalReconciliationPlan plan(PhysicalReconciliationInput input) {
    final id = input.reconciliationId.trim();
    if (id.isEmpty) {
      return _fail('MISSING_RECONCILIATION_ID', 'reconciliationId required');
    }
    if (input.existingAppliedReconciliationIds.contains(id)) {
      return PhysicalReconciliationPlan(
        ok: true,
        alreadyApplied: true,
        code: 'ALREADY_APPLIED',
        message: 'Duplicate reconciliationId is idempotent',
        expectedRevision: input.snapshot.stockRevision,
        resultingRevision: input.snapshot.stockRevision,
        createsSale: false,
        createsFinancialEntry: false,
      );
    }
    if (input.countedAt == null) {
      return _fail('COUNTED_AT_REQUIRED', 'countedAt required');
    }
    final qty = _parseQty(input.confirmedPhysicalQty);
    if (qty is String) return _fail(qty, qty);
    final confirmed = qty as int;

    if (input.snapshot.stockUpdatedAt != null &&
        input.snapshot.stockUpdatedAt!.isAfter(input.countedAt!)) {
      return _fail(
        'REMOTE_MOVEMENT_AFTER_COUNT',
        'stockUpdatedAt is after countedAt',
      );
    }
    if (input.expectedStockOperationId != null &&
        input.snapshot.stockOperationId != null &&
        input.expectedStockOperationId != input.snapshot.stockOperationId) {
      return _fail(
        'REMOTE_MOVEMENT_AFTER_COUNT',
        'stockOperationId changed after count',
      );
    }
    if (input.snapshot.stockRevision != input.expectedRevision) {
      return _fail(
        'RECONCILIATION_STALE_REMOTE_CONFLICT',
        'expectedRevision does not match remote stockRevision',
      );
    }

    if (input.snapshot.stockKind == 'simple' || input.identity.isSimple) {
      if (input.snapshot.stockKind != 'simple' || !input.identity.isSimple) {
        return _fail('IDENTITY_AMBIGUOUS', 'simple identity required for simple product');
      }
      return _success(
        input: input,
        confirmed: confirmed,
        beforeQty: input.snapshot.quantidade,
        afterVariacoes: Map<String, dynamic>.from(input.snapshot.variacoes),
        cellsChanged: const ['quantidade'],
        ept: const {},
        aggregate: confirmed,
      );
    }

    if (input.snapshot.variacoes.isEmpty) {
      return _fail('IDENTITY_AMBIGUOUS', 'canonical variation map is empty');
    }

    final resolved = _resolveCell(input.snapshot.variacoes, input.identity);
    if (resolved.error != null) {
      return _fail(resolved.error!, resolved.error!);
    }

    final after = _deepCopy(input.snapshot.variacoes);
    _writeCell(after, resolved.sizeKey!, resolved.colorKey!, resolved.extraKey, confirmed);
    final ept = _projectEpt(after);
    final aggregate = ept.values.fold<int>(0, (sum, v) => sum + v);
    final before = resolved.beforeQty!;
    return _success(
      input: input,
      confirmed: confirmed,
      beforeQty: before,
      afterVariacoes: after,
      cellsChanged: [
        [
          resolved.sizeKey,
          resolved.colorKey,
          if (resolved.extraKey != null) resolved.extraKey,
        ].join('/'),
      ],
      ept: ept,
      aggregate: aggregate,
    );
  }

  List<PhysicalReconciliationPlan> planConfirmedOnly(
    List<PhysicalReconciliationInput> inputs,
  ) {
    return [
      for (final input in inputs)
        if (input.confirmedPhysicalQty != null) plan(input),
    ];
  }

  PhysicalReconciliationPlan _success({
    required PhysicalReconciliationInput input,
    required int confirmed,
    required int beforeQty,
    required Map<String, dynamic> afterVariacoes,
    required List<String> cellsChanged,
    required Map<String, int> ept,
    required int aggregate,
  }) {
    final resulting = (input.snapshot.stockRevision ?? 0) + 1;
    return PhysicalReconciliationPlan(
      ok: true,
      beforeQty: beforeQty,
      afterQty: confirmed,
      delta: confirmed - beforeQty,
      canonicalCellsChanged: cellsChanged,
      estoquePorTamanho: ept,
      expectedRevision: input.snapshot.stockRevision,
      resultingRevision: resulting,
      createsSale: false,
      createsFinancialEntry: false,
      otherVariationsUnchanged: true,
      audit: {
        'operationType': 'physical_stock_reconciliation',
        'kind': kReconcileOperationKind,
        'reason': kPhysicalInventoryReason,
        'productId': input.snapshot.productId,
        'variationKey': cellsChanged.isEmpty ? '' : cellsChanged.first,
        'previousCanonicalQty': beforeQty,
        'confirmedPhysicalQty': confirmed,
        'delta': confirmed - beforeQty,
        'expectedRevision': input.snapshot.stockRevision,
        'resultingRevision': resulting,
        'countedAt': input.countedAt!.toUtc().toIso8601String(),
        'reconciliationId': input.reconciliationId,
        'aggregateAfter': aggregate,
        'createsSale': false,
        'createsFinancialEntry': false,
        'executionAuthorized': kPhysicalReconciliationExecutionAuthorized,
      },
    );
  }

  PhysicalReconciliationPlan _fail(String code, String message) =>
      PhysicalReconciliationPlan(ok: false, code: code, message: message);

  Object _parseQty(Object? raw) {
    if (raw == null) return 'MISSING_COUNT';
    if (raw is double) return 'DECIMAL_REJECTED';
    if (raw is String) {
      final text = raw.trim();
      if (text.isEmpty) return 'MISSING_COUNT';
      if (text.contains('.') || text.contains(',')) return 'DECIMAL_REJECTED';
      final parsed = int.tryParse(text);
      if (parsed == null) return 'AMBIGUOUS_COUNT';
      if (parsed < 0) return 'NEGATIVE_REJECTED';
      return parsed;
    }
    if (raw is! int) return 'AMBIGUOUS_COUNT';
    if (raw < 0) return 'NEGATIVE_REJECTED';
    return raw;
  }
}

class _ResolvedCell {
  const _ResolvedCell({
    this.sizeKey,
    this.colorKey,
    this.extraKey,
    this.beforeQty,
    this.error,
  });
  final String? sizeKey;
  final String? colorKey;
  final String? extraKey;
  final int? beforeQty;
  final String? error;
}

_ResolvedCell _resolveCell(
  Map<String, dynamic> variacoes,
  PhysicalVariationIdentity identity,
) {
  const displayOnly = {'p', 'm', 'g', 'azul', 'rosa'};
  final sizeWanted = physicalNormKey(identity.size);
  if (sizeWanted.isEmpty) {
    return const _ResolvedCell(error: 'VARIATION_IDENTITY_REQUIRED');
  }
  if (displayOnly.contains(sizeWanted) &&
      !variacoes.keys.any((k) => physicalNormKey(k) == sizeWanted)) {
    return const _ResolvedCell(error: 'DISPLAY_LABEL_NOT_TECHNICAL');
  }
  final sizeKey = _uniqueKey(variacoes.keys, identity.size);
  if (sizeKey == null) {
    return const _ResolvedCell(error: 'IDENTITY_AMBIGUOUS');
  }
  final colorsRaw = variacoes[sizeKey];
  if (colorsRaw is! Map) {
    return const _ResolvedCell(error: 'IDENTITY_AMBIGUOUS');
  }
  final colors = colorsRaw.map((k, v) => MapEntry(k.toString(), v));
  final colorKey = _uniqueKey(
    colors.keys.where((k) => !_isMeta(k)),
    identity.color,
  );
  if (colorKey == null) {
    return const _ResolvedCell(error: 'IDENTITY_AMBIGUOUS');
  }
  final cell = colors[colorKey];
  if (cell is int) {
    if (identity.extra.trim().isNotEmpty &&
        physicalNormKey(identity.extra) != kSemExtra) {
      return const _ResolvedCell(error: 'IDENTITY_AMBIGUOUS');
    }
    return _ResolvedCell(
      sizeKey: sizeKey,
      colorKey: colorKey,
      beforeQty: cell,
    );
  }
  if (cell is Map) {
    final extras = cell.map((k, v) => MapEntry(k.toString(), v));
    final extraWanted = identity.extra.trim().isEmpty ? kSemExtra : identity.extra;
    final extraKey = _uniqueKey(
      extras.keys.where((k) => !_isMeta(k)),
      extraWanted,
    );
    if (extraKey == null || extras[extraKey] is! int) {
      return const _ResolvedCell(error: 'IDENTITY_AMBIGUOUS');
    }
    return _ResolvedCell(
      sizeKey: sizeKey,
      colorKey: colorKey,
      extraKey: extraKey,
      beforeQty: extras[extraKey] as int,
    );
  }
  return const _ResolvedCell(error: 'IDENTITY_AMBIGUOUS');
}

String? _uniqueKey(Iterable<String> keys, String wanted) {
  final exact = keys.where((k) => k == wanted).toList();
  if (exact.length == 1) return exact.first;
  final n = physicalNormKey(wanted);
  if (n.isEmpty) return null;
  final fuzzy = keys.where((k) => physicalNormKey(k) == n).toList();
  if (fuzzy.length == 1) return fuzzy.first;
  return null;
}

Map<String, dynamic> _deepCopy(Map<String, dynamic> raw) {
  final out = <String, dynamic>{};
  for (final e in raw.entries) {
    final v = e.value;
    if (v is Map) {
      out[e.key] = _deepCopy(v.map((k, val) => MapEntry(k.toString(), val)));
    } else {
      out[e.key] = v;
    }
  }
  return out;
}

void _writeCell(
  Map<String, dynamic> variacoes,
  String size,
  String color,
  String? extra,
  int qty,
) {
  final colors = Map<String, dynamic>.from(variacoes[size] as Map);
  if (extra == null) {
    colors[color] = qty;
  } else {
    final cell = Map<String, dynamic>.from(colors[color] as Map);
    cell[extra] = qty;
    colors[color] = cell;
  }
  variacoes[size] = colors;
}

Map<String, int> _projectEpt(Map<String, dynamic> variacoes) {
  final ept = <String, int>{};
  for (final sizeEntry in variacoes.entries) {
    final colors = sizeEntry.value;
    if (colors is! Map) continue;
    var sum = 0;
    for (final colorEntry in colors.entries) {
      if (_isMeta(colorEntry.key.toString())) continue;
      sum += _cellTotal(colorEntry.value);
    }
    ept[sizeEntry.key] = sum;
  }
  return ept;
}

int _cellTotal(Object? value) {
  if (value is int) return value;
  if (value is Map) {
    var sum = 0;
    for (final e in value.entries) {
      if (_isMeta(e.key.toString())) continue;
      sum += _cellTotal(e.value);
    }
    return sum;
  }
  return 0;
}
