/// Modelos do módulo Consignados. Sem acoplamento com Venda/PDV.
class ConsignmentReseller {
  const ConsignmentReseller({
    required this.resellerId,
    required this.displayName,
    this.active = true,
    this.notes = '',
    this.phone = '',
    this.storeId = '',
  });

  final String resellerId;
  final String displayName;
  final bool active;
  final String notes;
  final String phone;
  final String storeId;

  factory ConsignmentReseller.fromMap(String id, Map<String, dynamic> data) {
    return ConsignmentReseller(
      resellerId: (data['resellerId'] ?? id).toString(),
      displayName: (data['displayName'] ?? id).toString(),
      active: data['active'] == true,
      notes: (data['notes'] ?? '').toString(),
      phone: (data['phone'] ?? '').toString(),
      storeId: (data['storeId'] ?? '').toString(),
    );
  }
}

class ConsignmentVariationKey {
  const ConsignmentVariationKey({
    this.size = '',
    this.color = '',
    this.extra = '',
  });

  final String size;
  final String color;
  final String extra;

  Map<String, dynamic> toMap() => {'size': size, 'color': color, 'extra': extra};

  factory ConsignmentVariationKey.fromMap(dynamic raw) {
    if (raw is Map) {
      return ConsignmentVariationKey(
        size: (raw['size'] ?? '').toString(),
        color: (raw['color'] ?? '').toString(),
        extra: (raw['extra'] ?? '').toString(),
      );
    }
    return const ConsignmentVariationKey();
  }

  bool get isEmpty => size.isEmpty && color.isEmpty && extra.isEmpty;
}

class ConsignmentDraftLine {
  ConsignmentDraftLine({
    required this.productId,
    required this.productName,
    required this.productType,
    required this.qtySent,
    required this.unitSalePrice,
    this.variationKey = const ConsignmentVariationKey(),
    this.commissionType = 'SEM_COMISSAO',
    this.commissionValue = 0,
    this.expectedStockRevision,
    double? listUnitPrice,
  }) : listUnitPrice = listUnitPrice ?? unitSalePrice;

  final String productId;
  final String productName;
  final String productType;
  int qtySent;
  /// Consigned unit price; becomes `unitSalePriceSnapshot` on the server.
  double unitSalePrice;
  /// Price of the selected variation when the line was picked. Client-only (the server
  /// rejects unknown line keys); lets the UI tell a manual price edit from the original.
  final double listUnitPrice;
  ConsignmentVariationKey variationKey;
  String commissionType;
  double commissionValue;
  int? expectedStockRevision;

  int get _unitCents => (unitSalePrice * 100).round();

  bool get hasManualPrice => _unitCents != (listUnitPrice * 100).round();

  double get lineSubtotal => qtySent * _unitCents / 100;

  Map<String, dynamic> toPayload() => {
        'productId': productId,
        'qtySent': qtySent,
        'unitSalePrice': unitSalePrice,
        'commissionType': commissionType,
        'commissionValue': commissionValue,
        if (productType != 'simple') 'variationKey': variationKey.toMap(),
        if (expectedStockRevision != null) 'expectedStockRevision': expectedStockRevision,
      };
}

int _lineInt(Map<String, dynamic> line, String key) {
  final v = line[key];
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? 0;
}

/// Pieces originally issued on the line; withdrawals never rewrite it.
int consignmentLineSent(Map<String, dynamic> line) {
  final s = _lineInt(line, 'qtySent');
  return s < 0 ? 0 : s;
}

/// Pieces taken back by the store before settlement (append-only server field).
int consignmentLineWithdrawn(Map<String, dynamic> line) {
  final w = _lineInt(line, 'qtyWithdrawn');
  return w < 0 ? 0 : w;
}

/// Pieces of the line still in the settlement universe (sent minus withdrawn).
int consignmentLineOutstanding(Map<String, dynamic> line) {
  final o = consignmentLineSent(line) - consignmentLineWithdrawn(line);
  return o < 0 ? 0 : o;
}

/// Canonical server statuses (functions/src/consignmentProtocol.js `STATUS`).
const kConsignmentOpenStatuses = <String>{'DRAFT', 'ISSUED'};
const kConsignmentClosedStatuses = <String>{'SETTLED', 'CANCELLED'};

double consignmentLineUnitPrice(Map<String, dynamic> line) {
  final v = line['unitSalePriceSnapshot'];
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}') ?? 0;
}

/// qtySent × the line's own snapshot price, in cents.
double consignmentLineSentAmount(Map<String, dynamic> line) =>
    _lineInt(line, 'qtySent') * (consignmentLineUnitPrice(line) * 100).round() / 100;

class ConsignmentReturnLine {
  const ConsignmentReturnLine({
    required this.lineId,
    required this.productId,
    required this.variationKey,
    required this.qty,
  });

  final String lineId;
  final String productId;
  final ConsignmentVariationKey variationKey;
  final int qty;

  Map<String, dynamic> toPayload() => {
        'lineId': lineId,
        'productId': productId,
        'variationKey': variationKey.toMap(),
        'qty': qty,
      };
}

class ConsignmentDoc {
  const ConsignmentDoc({
    required this.id,
    required this.storeId,
    required this.resellerId,
    required this.resellerName,
    required this.status,
    required this.lines,
    required this.totalItemsSent,
    required this.totalItemsSold,
    required this.totalItemsReturned,
    required this.grossSoldAmount,
    required this.commissionAmount,
    required this.netAmount,
    required this.potentialGrossAmount,
    this.notes = '',
    this.issuedAt,
    this.settledAt,
    this.cancelledAt,
    this.createdAt,
    this.revision = 1,
    this.additions = const [],
    this.withdrawals = const [],
    this.isDeleted = false,
    this.settlementOperationId = '',
    this.saleId,
    this.financeId,
  });

  final String id;
  final String storeId;
  final String resellerId;
  final String resellerName;
  final String status;
  final List<Map<String, dynamic>> lines;
  final List<Map<String, dynamic>> additions;
  /// Append-only "retiradas antes do acerto" movements.
  final List<Map<String, dynamic>> withdrawals;
  final int totalItemsSent;
  final int totalItemsSold;
  final int totalItemsReturned;
  final double grossSoldAmount;
  final double commissionAmount;
  final double netAmount;
  final double potentialGrossAmount;
  final String notes;
  final DateTime? issuedAt;
  final DateTime? settledAt;
  final DateTime? cancelledAt;
  final DateTime? createdAt;
  final int revision;
  /// Soft delete (hidden from lists): cancelled or settled total-return consignments.
  final bool isDeleted;
  final String settlementOperationId;
  final String? saleId;
  final String? financeId;

  bool get isDraft => status == 'DRAFT';
  bool get isIssued => status == 'ISSUED';
  bool get isSettled => status == 'SETTLED';
  bool get isCancelled => status == 'CANCELLED';
  /// "Em aberto" tab; every other status belongs to "Histórico".
  bool get isOpen => kConsignmentOpenStatuses.contains(status);
  bool get canAddItems => isDraft || isIssued;
  bool get canDelete => isCancelled && !isDeleted;
  bool get canHideFromList => isTotalReturn && !isDeleted;

  DateTime? get closedAt => settledAt ?? cancelledAt ?? issuedAt ?? createdAt;

  /// Mirror of the server `totalReturnIneligibility` rule (the server re-checks before hiding):
  /// settled, nothing sold, every outstanding piece returned and every withdrawal recorded.
  bool get isTotalReturn {
    if (!isSettled || settlementOperationId.isEmpty || saleId != null || financeId != null) return false;
    if (totalItemsSold != 0 || grossSoldAmount != 0 || commissionAmount != 0 || netAmount != 0) return false;
    if (lines.isEmpty) return false;
    final withdrawnByLine = <String, int>{};
    for (final w in withdrawals) {
      final rows = w['lines'] is List ? (w['lines'] as List).whereType<Map>() : const <Map>[];
      for (final l in rows) {
        final id = '${l['lineId'] ?? ''}';
        withdrawnByLine[id] = (withdrawnByLine[id] ?? 0) + _lineInt(Map<String, dynamic>.from(l), 'qtyWithdrawn');
      }
    }
    var returned = 0;
    for (final l in lines) {
      final withdrawn = consignmentLineWithdrawn(l);
      if (_lineInt(l, 'qtySold') != 0) return false;
      if (_lineInt(l, 'qtyReturned') != _lineInt(l, 'qtySent') - withdrawn) return false;
      if ((withdrawnByLine.remove('${l['lineId'] ?? ''}') ?? 0) != withdrawn) return false;
      returned += _lineInt(l, 'qtyReturned');
    }
    return withdrawnByLine.isEmpty && returned == totalItemsReturned;
  }
  bool get canReturnItems => isIssued && !isDeleted && totalItemsOutstanding > 0;
  bool get hasWithdrawals => withdrawals.isNotEmpty || totalItemsWithdrawn > 0;

  int get totalItemsWithdrawn =>
      lines.fold(0, (s, l) => s + consignmentLineWithdrawn(l));

  int get totalItemsOutstanding =>
      lines.fold(0, (s, l) => s + consignmentLineOutstanding(l));

  double get outstandingGrossAmount {
    final cents = lines.fold<int>(
      0,
      (s, l) => s + (consignmentLineOutstanding(l) * consignmentLineUnitPrice(l) * 100).round(),
    );
    return cents / 100;
  }

  double get withdrawnGrossAmount {
    final cents = lines.fold<int>(
      0,
      (s, l) => s + (consignmentLineWithdrawn(l) * consignmentLineUnitPrice(l) * 100).round(),
    );
    return cents / 100;
  }

  /// Consolidated qty by productId + variation identity + unit price snapshot (ignores
  /// addition lot suffix). Lots priced differently stay separate so qty × price stays exact.
  List<Map<String, dynamic>> get consolidatedLines {
    final map = <String, Map<String, dynamic>>{};
    for (final line in lines) {
      final productId = '${line['productId'] ?? ''}';
      final vk = ConsignmentVariationKey.fromMap(line['variationKey']);
      final cents = (consignmentLineUnitPrice(line) * 100).round();
      final key = '$productId::${vk.size}\u001e${vk.color}\u001e${vk.extra}\u001e$cents';
      final existing = map[key];
      final qty = (line['qtySent'] is num) ? (line['qtySent'] as num).toInt() : 0;
      final withdrawn = consignmentLineWithdrawn(line);
      if (existing == null) {
        map[key] = Map<String, dynamic>.from(line)
          ..['qtySent'] = qty
          ..['qtyWithdrawn'] = withdrawn;
      } else {
        existing['qtySent'] = ((existing['qtySent'] as num?)?.toInt() ?? 0) + qty;
        existing['qtyWithdrawn'] = consignmentLineWithdrawn(existing) + withdrawn;
      }
    }
    return map.values.toList();
  }

  factory ConsignmentDoc.fromMap(String id, Map<String, dynamic> data) {
    DateTime? ts(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      try {
        final seconds = v.seconds;
        if (seconds is int) {
          return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
        }
      } catch (_) {}
      return DateTime.tryParse(v.toString());
    }

    num n(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;
    final snapshot = data['resellerSnapshot'];
    return ConsignmentDoc(
      id: (data['id'] ?? id).toString(),
      storeId: (data['storeId'] ?? '').toString(),
      resellerId: (data['resellerId'] ?? '').toString(),
      resellerName: snapshot is Map
          ? (snapshot['displayName'] ?? data['resellerId'] ?? '').toString()
          : (data['resellerId'] ?? '').toString(),
      status: (data['status'] ?? '').toString(),
      lines: (data['lines'] is List)
          ? (data['lines'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : const [],
      additions: (data['additions'] is List)
          ? (data['additions'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : const [],
      withdrawals: (data['withdrawals'] is List)
          ? (data['withdrawals'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : const [],
      totalItemsSent: n(data['totalItemsSent']).toInt(),
      totalItemsSold: n(data['totalItemsSold']).toInt(),
      totalItemsReturned: n(data['totalItemsReturned']).toInt(),
      grossSoldAmount: n(data['grossSoldAmount']).toDouble(),
      commissionAmount: n(data['commissionAmount']).toDouble(),
      netAmount: n(data['netAmount']).toDouble(),
      potentialGrossAmount: n(data['potentialGrossAmount']).toDouble(),
      notes: (data['notes'] ?? '').toString(),
      issuedAt: ts(data['issuedAt']),
      settledAt: ts(data['settledAt']),
      cancelledAt: ts(data['cancelledAt']),
      createdAt: ts(data['createdAt']),
      revision: n(data['revision']).toInt() == 0 ? 1 : n(data['revision']).toInt(),
      isDeleted: data['isDeleted'] == true,
      settlementOperationId: (data['settlementOperationId'] ?? '').toString(),
      saleId: data['saleId']?.toString(),
      financeId: data['financeId']?.toString(),
    );
  }
}

/// Splits the visible consignments into the two tabs; soft-deleted records appear in neither.
({List<ConsignmentDoc> open, List<ConsignmentDoc> history}) splitConsignmentLists(
  Iterable<ConsignmentDoc> docs,
) {
  final visible = docs.where((c) => !c.isDeleted);
  final history = visible.where((c) => !c.isOpen).toList()
    ..sort((a, b) {
      final epoch = DateTime.fromMillisecondsSinceEpoch(0);
      return (b.closedAt ?? epoch).compareTo(a.closedAt ?? epoch);
    });
  return (open: visible.where((c) => c.isOpen).toList(), history: history);
}
