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
  });

  final String id;
  final String storeId;
  final String resellerId;
  final String resellerName;
  final String status;
  final List<Map<String, dynamic>> lines;
  final List<Map<String, dynamic>> additions;
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

  bool get isDraft => status == 'DRAFT';
  bool get isIssued => status == 'ISSUED';
  bool get isSettled => status == 'SETTLED';
  bool get isCancelled => status == 'CANCELLED';
  bool get canAddItems => isDraft || isIssued;

  /// Consolidated qty by productId + variation identity (ignores addition lot suffix).
  List<Map<String, dynamic>> get consolidatedLines {
    final map = <String, Map<String, dynamic>>{};
    for (final line in lines) {
      final productId = '${line['productId'] ?? ''}';
      final vk = ConsignmentVariationKey.fromMap(line['variationKey']);
      final key = '$productId::${vk.size}\u001e${vk.color}\u001e${vk.extra}';
      final existing = map[key];
      final qty = (line['qtySent'] is num) ? (line['qtySent'] as num).toInt() : 0;
      if (existing == null) {
        map[key] = Map<String, dynamic>.from(line)..['qtySent'] = qty;
      } else {
        existing['qtySent'] = ((existing['qtySent'] as num?)?.toInt() ?? 0) + qty;
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
    );
  }
}
