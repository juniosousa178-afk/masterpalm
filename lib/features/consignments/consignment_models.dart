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
  });

  final String productId;
  final String productName;
  final String productType;
  int qtySent;
  double unitSalePrice;
  ConsignmentVariationKey variationKey;
  String commissionType;
  double commissionValue;
  int? expectedStockRevision;

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

/// Pieces taken back by the store before settlement (append-only server field).
int consignmentLineWithdrawn(Map<String, dynamic> line) {
  final w = _lineInt(line, 'qtyWithdrawn');
  return w < 0 ? 0 : w;
}

/// Pieces of the line still in the settlement universe (sent minus withdrawn).
int consignmentLineOutstanding(Map<String, dynamic> line) {
  final o = _lineInt(line, 'qtySent') - consignmentLineWithdrawn(line);
  return o < 0 ? 0 : o;
}

double consignmentLineUnitPrice(Map<String, dynamic> line) {
  final v = line['unitSalePriceSnapshot'];
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}') ?? 0;
}

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
    this.createdAt,
    this.revision = 1,
    this.additions = const [],
    this.withdrawals = const [],
    this.isDeleted = false,
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
  final DateTime? createdAt;
  final int revision;
  /// Soft delete (hidden from lists); only cancelled consignments can carry it.
  final bool isDeleted;

  bool get isDraft => status == 'DRAFT';
  bool get isIssued => status == 'ISSUED';
  bool get isSettled => status == 'SETTLED';
  bool get isCancelled => status == 'CANCELLED';
  bool get canAddItems => isDraft || isIssued;
  bool get canDelete => isCancelled && !isDeleted;
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

  /// Consolidated qty by productId + variation identity (ignores addition lot suffix).
  List<Map<String, dynamic>> get consolidatedLines {
    final map = <String, Map<String, dynamic>>{};
    for (final line in lines) {
      final productId = '${line['productId'] ?? ''}';
      final vk = ConsignmentVariationKey.fromMap(line['variationKey']);
      final key = '$productId::${vk.size}\u001e${vk.color}\u001e${vk.extra}';
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
      createdAt: ts(data['createdAt']),
      revision: n(data['revision']).toInt() == 0 ? 1 : n(data['revision']).toInt(),
      isDeleted: data['isDeleted'] == true,
    );
  }
}
