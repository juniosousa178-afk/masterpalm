import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../consignment_models.dart';
import '../consignment_service.dart';
import '../consignment_validation.dart';

/// Read-only report filters. Never mutates stock/consignment.
enum ConsignmentReportPeriodPreset {
  today,
  yesterday,
  last7Days,
  thisMonth,
  previousMonth,
  custom,
}

class ConsignmentReportDateRange {
  const ConsignmentReportDateRange(this.start, this.end);
  final DateTime start;
  final DateTime end;

  static ConsignmentReportDateRange fromPreset(
    ConsignmentReportPeriodPreset preset, {
    DateTime? customStart,
    DateTime? customEnd,
    DateTime? now,
  }) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    switch (preset) {
      case ConsignmentReportPeriodPreset.today:
        return ConsignmentReportDateRange(today, today.add(const Duration(days: 1)));
      case ConsignmentReportPeriodPreset.yesterday:
        final y = today.subtract(const Duration(days: 1));
        return ConsignmentReportDateRange(y, today);
      case ConsignmentReportPeriodPreset.last7Days:
        return ConsignmentReportDateRange(today.subtract(const Duration(days: 6)), today.add(const Duration(days: 1)));
      case ConsignmentReportPeriodPreset.thisMonth:
        return ConsignmentReportDateRange(DateTime(n.year, n.month, 1), DateTime(n.year, n.month + 1, 1));
      case ConsignmentReportPeriodPreset.previousMonth:
        final first = DateTime(n.year, n.month - 1, 1);
        return ConsignmentReportDateRange(first, DateTime(n.year, n.month, 1));
      case ConsignmentReportPeriodPreset.custom:
        final s = customStart ?? today;
        final e = customEnd ?? today;
        final start = DateTime(s.year, s.month, s.day);
        final end = DateTime(e.year, e.month, e.day).add(const Duration(days: 1));
        return ConsignmentReportDateRange(start, end);
    }
  }
}

class ConsignmentStoreProfile {
  const ConsignmentStoreProfile({
    required this.lojaId,
    required this.name,
    this.cnpj = '',
    this.phone = '',
    this.whatsapp = '',
    this.instagram = '',
    this.address = '',
    this.logoUrl = '',
  });

  final String lojaId;
  final String name;
  final String cnpj;
  final String phone;
  final String whatsapp;
  final String instagram;
  final String address;
  final String logoUrl;
}

class ConsignmentProductReportMeta {
  const ConsignmentProductReportMeta({
    this.productCode = '',
    this.imageUrl = '',
  });
  final String productCode;
  final String imageUrl;
}

class ConsignmentReportLineView {
  const ConsignmentReportLineView({
    required this.productId,
    required this.productName,
    required this.productCode,
    required this.variationLabel,
    required this.qtySent,
    required this.qtySold,
    required this.qtyReturned,
    required this.unitPrice,
    required this.lineGrossSold,
    required this.lineCommission,
    required this.lineNet,
    required this.linePotentialGross,
    required this.commissionType,
    required this.commissionValue,
    this.imageUrl = '',
  });

  final String productId;
  final String productName;
  final String productCode;
  final String variationLabel;
  final int qtySent;
  final int qtySold;
  final int qtyReturned;
  final double unitPrice;
  final double lineGrossSold;
  final double lineCommission;
  final double lineNet;
  final double linePotentialGross;
  final String commissionType;
  final double commissionValue;
  final String imageUrl;

  int get qtyPending {
    final p = qtySent - qtySold - qtyReturned;
    return p < 0 ? 0 : p;
  }

  double get lineConsignedValue => _money(qtySent * unitPrice);
}

double _money(num v) => (v * 100).round() / 100;

String consignmentReportVariationLabel(Map<String, dynamic> line) {
  final vk = ConsignmentVariationKey.fromMap(line['variationKey']);
  final parts = <String>[];
  if (vk.size.isNotEmpty) parts.add('Tamanho: ${vk.size}');
  if (vk.color.isNotEmpty) parts.add('Cor: ${vk.color}');
  if (vk.extra.isNotEmpty) parts.add(vk.extra);
  return parts.join(' · ');
}

String consignmentReportCommissionLabel(String type, double value) {
  switch (type) {
    case 'PERCENTUAL':
      return 'Comissão cadastrada: ${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2)}%';
    case 'VALOR_FIXO_POR_UNIDADE':
      return 'Comissão cadastrada: ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(value)}/un';
    default:
      return '';
  }
}

/// Pure aggregation helpers — no I/O, no writes.
class ConsignmentReportAggregator {
  static bool inRange(ConsignmentDoc doc, ConsignmentReportDateRange range) {
    final anchor = doc.issuedAt ?? doc.createdAt ?? doc.settledAt;
    if (anchor == null) return false;
    final local = anchor.toLocal();
    return !local.isBefore(range.start) && local.isBefore(range.end);
  }

  static bool matchesFilters({
    required ConsignmentDoc doc,
    required String lojaId,
    String? resellerId,
    String? status,
    ConsignmentReportDateRange? range,
  }) {
    if (doc.storeId.isNotEmpty && doc.storeId != lojaId) return false;
    if (resellerId != null && resellerId.isNotEmpty && doc.resellerId != resellerId) {
      return false;
    }
    if (status != null && status.isNotEmpty && doc.status != status) return false;
    if (range != null && !inRange(doc, range)) return false;
    return true;
  }

  static List<ConsignmentReportLineView> linesOf(
    ConsignmentDoc doc, {
    Map<String, ConsignmentProductReportMeta> meta = const {},
  }) {
    return [
      for (final raw in doc.lines)
        () {
          final line = Map<String, dynamic>.from(raw);
          final productId = (line['productId'] ?? '').toString();
          final m = meta[productId] ?? const ConsignmentProductReportMeta();
          final qtySent = (line['qtySent'] is num)
              ? (line['qtySent'] as num).toInt()
              : int.tryParse('${line['qtySent']}') ?? 0;
          final qtySold = (line['qtySold'] is num)
              ? (line['qtySold'] as num).toInt()
              : int.tryParse('${line['qtySold']}') ?? 0;
          final qtyReturned = (line['qtyReturned'] is num)
              ? (line['qtyReturned'] as num).toInt()
              : int.tryParse('${line['qtyReturned']}') ?? 0;
          final unit = (line['unitSalePriceSnapshot'] is num)
              ? (line['unitSalePriceSnapshot'] as num).toDouble()
              : double.tryParse('${line['unitSalePriceSnapshot']}') ?? 0;
          final type = (line['commissionType'] ?? 'SEM_COMISSAO').toString();
          final cval = (line['commissionValueSnapshot'] is num)
              ? (line['commissionValueSnapshot'] as num).toDouble()
              : double.tryParse('${line['commissionValueSnapshot']}') ?? 0;
          final soldAmounts = consignmentLineAmounts(
            qty: qtySold,
            unitPrice: unit,
            commissionType: type,
            commissionValue: cval,
          );
          final persistedGross = (line['lineGrossAmount'] is num)
              ? (line['lineGrossAmount'] as num).toDouble()
              : null;
          final persistedCommission = (line['lineCommissionAmount'] is num)
              ? (line['lineCommissionAmount'] as num).toDouble()
              : null;
          final persistedNet = (line['lineNetAmount'] is num)
              ? (line['lineNetAmount'] as num).toDouble()
              : null;
          final potential = (line['potentialGrossAmount'] is num)
              ? (line['potentialGrossAmount'] as num).toDouble()
              : _money(qtySent * unit);
          return ConsignmentReportLineView(
            productId: productId,
            productName: (line['productNameSnapshot'] ?? productId).toString(),
            productCode: m.productCode,
            variationLabel: consignmentReportVariationLabel(line),
            qtySent: qtySent,
            qtySold: qtySold,
            qtyReturned: qtyReturned,
            unitPrice: unit,
            lineGrossSold: persistedGross ?? soldAmounts.gross,
            lineCommission: persistedCommission ?? soldAmounts.commission,
            lineNet: persistedNet ?? soldAmounts.net,
            linePotentialGross: potential,
            commissionType: type,
            commissionValue: cval,
            imageUrl: m.imageUrl,
          );
        }()
    ];
  }

  /// Lines for a single addition batch receipt (uses qtyAdded when present).
  static List<ConsignmentReportLineView> additionLinesOf(
    List<Map<String, dynamic>> rawLines, {
    Map<String, ConsignmentProductReportMeta> meta = const {},
  }) {
    return [
      for (final raw in rawLines)
        () {
          final line = Map<String, dynamic>.from(raw);
          final productId = (line['productId'] ?? '').toString();
          final m = meta[productId] ?? const ConsignmentProductReportMeta();
          final qty = (line['qtyAdded'] is num)
              ? (line['qtyAdded'] as num).toInt()
              : (line['qtySent'] is num)
                  ? (line['qtySent'] as num).toInt()
                  : int.tryParse('${line['qtyAdded'] ?? line['qtySent']}') ?? 0;
          final unit = (line['unitSalePriceSnapshot'] is num)
              ? (line['unitSalePriceSnapshot'] as num).toDouble()
              : double.tryParse('${line['unitSalePriceSnapshot']}') ?? 0;
          final type = (line['commissionType'] ?? 'SEM_COMISSAO').toString();
          final cval = (line['commissionValueSnapshot'] is num)
              ? (line['commissionValueSnapshot'] as num).toDouble()
              : double.tryParse('${line['commissionValueSnapshot']}') ?? 0;
          final potential = _money(qty * unit);
          return ConsignmentReportLineView(
            productId: productId,
            productName: (line['productNameSnapshot'] ?? productId).toString(),
            productCode: (line['productCodeSnapshot'] ?? m.productCode).toString(),
            variationLabel: consignmentReportVariationLabel(line),
            qtySent: qty,
            qtySold: 0,
            qtyReturned: 0,
            unitPrice: unit,
            lineGrossSold: 0,
            lineCommission: 0,
            lineNet: 0,
            linePotentialGross: potential,
            commissionType: type,
            commissionValue: cval,
            imageUrl: m.imageUrl,
          );
        }()
    ];
  }

  static Map<String, dynamic> resellerRollup(List<ConsignmentDoc> docs) {
    var consignments = 0;
    var sent = 0, sold = 0, returned = 0;
    var consigned = 0.0, gross = 0.0, commission = 0.0, net = 0.0;
    DateTime? lastSettle;
    var hasIssued = false;
    var hasSettled = false;
    for (final d in docs) {
      if (d.isCancelled || d.isDraft) continue;
      consignments += 1;
      sent += d.totalItemsSent;
      sold += d.totalItemsSold;
      returned += d.totalItemsReturned;
      consigned += d.potentialGrossAmount;
      gross += d.grossSoldAmount;
      commission += d.commissionAmount;
      net += d.netAmount;
      if (d.isIssued) hasIssued = true;
      if (d.isSettled) {
        hasSettled = true;
        if (d.settledAt != null &&
            (lastSettle == null || d.settledAt!.isAfter(lastSettle))) {
          lastSettle = d.settledAt;
        }
      }
    }
    final pending = sent - sold - returned;
    String status;
    if (hasIssued && hasSettled) {
      status = 'Misto';
    } else if (hasIssued) {
      status = 'Em consignação';
    } else if (hasSettled) {
      status = 'Acertado';
    } else {
      status = '—';
    }
    return {
      'consignments': consignments,
      'sent': sent,
      'sold': sold,
      'returned': returned,
      'pending': pending < 0 ? 0 : pending,
      'consigned': _money(consigned),
      'gross': _money(gross),
      'commission': _money(commission),
      'net': _money(net),
      'received': hasSettled ? _money(net) : 0.0,
      'balance': hasIssued ? _money(0) : 0.0,
      'lastSettle': lastSettle,
      'status': status,
    };
  }

  static Map<String, dynamic> generalTotals(List<Map<String, dynamic>> rows) {
    var sent = 0, sold = 0, returned = 0, pending = 0, consignments = 0;
    var consigned = 0.0, gross = 0.0, commission = 0.0, net = 0.0, received = 0.0;
    for (final r in rows) {
      consignments += (r['consignments'] as int?) ?? 0;
      sent += (r['sent'] as int?) ?? 0;
      sold += (r['sold'] as int?) ?? 0;
      returned += (r['returned'] as int?) ?? 0;
      pending += (r['pending'] as int?) ?? 0;
      consigned += (r['consigned'] as num?)?.toDouble() ?? 0;
      gross += (r['gross'] as num?)?.toDouble() ?? 0;
      commission += (r['commission'] as num?)?.toDouble() ?? 0;
      net += (r['net'] as num?)?.toDouble() ?? 0;
      received += (r['received'] as num?)?.toDouble() ?? 0;
    }
    return {
      'consignments': consignments,
      'sent': sent,
      'sold': sold,
      'returned': returned,
      'pending': pending,
      'consigned': _money(consigned),
      'gross': _money(gross),
      'commission': _money(commission),
      'net': _money(net),
      'received': _money(received),
      'balance': _money(0),
    };
  }
}

class ConsignmentReportDataService {
  ConsignmentReportDataService._();

  @visibleForTesting
  static FirebaseFirestore? debugFirestore;

  static FirebaseFirestore get _db => debugFirestore ?? FirebaseFirestore.instance;

  static String _pickString(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = (m[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  static String _imageFromMap(Map<String, dynamic> m) {
    final direct = _pickString(m, ['imageUrl', 'imagem_principal', 'imagem', 'url_foto', 'foto']);
    if (direct.isNotEmpty) return direct;
    final fotos = m['fotos'] ?? m['imagens'] ?? m['images'] ?? m['imgs'];
    if (fotos is List && fotos.isNotEmpty) {
      final first = fotos.first;
      if (first is String && first.trim().isNotEmpty) return first.trim();
      if (first is Map) {
        final u = _pickString(Map<String, dynamic>.from(first), ['url', 'src', 'imageUrl']);
        if (u.isNotEmpty) return u;
      }
    }
    return '';
  }

  static String _codeFromMap(Map<String, dynamic> m) {
    return _pickString(m, ['codigoBarras', 'sku', 'codigo', 'codigoProduto', 'productCode']);
  }

  static Future<ConsignmentStoreProfile> loadStoreProfile(String lojaId) async {
    final snap = await _db.collection('lojas').doc(lojaId).get();
    final data = snap.data() ?? <String, dynamic>{};
    final logos = data['logos'] is Map ? Map<String, dynamic>.from(data['logos'] as Map) : null;
    final rodape = data['rodape'] is Map ? Map<String, dynamic>.from(data['rodape'] as Map) : null;
    final empresa = data['empresa'] is Map ? Map<String, dynamic>.from(data['empresa'] as Map) : null;
    final name = _pickString(data, [
          'nome',
          'nomeLoja',
          'nomeFantasia',
          'razaoSocial',
          'name',
          'titulo',
        ]).isNotEmpty
        ? _pickString(data, ['nome', 'nomeLoja', 'nomeFantasia', 'razaoSocial', 'name', 'titulo'])
        : lojaId;
    final logoUrl = _pickString(data, ['logoUrl', 'logoDesktopUrl', 'logoMobileUrl']);
    final logoFromNested = logos == null
        ? ''
        : _pickString(logos, ['logoUrl', 'desktop', 'mobile', 'logoDesktopUrl']);
    return ConsignmentStoreProfile(
      lojaId: lojaId,
      name: name,
      cnpj: _pickString(data, ['cnpj']).isNotEmpty
          ? _pickString(data, ['cnpj'])
          : _pickString(rodape ?? {}, ['cnpj']).isNotEmpty
              ? _pickString(rodape ?? {}, ['cnpj'])
              : _pickString(empresa ?? {}, ['cnpj']),
      phone: _pickString(data, ['telefone', 'phone', 'whatsapp']),
      whatsapp: _pickString(data, ['whatsapp', 'store_whatsapp', 'telefone']),
      instagram: _pickString(data, ['instagram']),
      address: _pickString(data, ['endereco', 'address']),
      logoUrl: logoUrl.isNotEmpty ? logoUrl : logoFromNested,
    );
  }

  static Future<Map<String, ConsignmentProductReportMeta>> loadProductMeta({
    required String lojaId,
    required Iterable<String> productIds,
  }) async {
    final ids = productIds.where((e) => e.trim().isNotEmpty).toSet().toList();
    final out = <String, ConsignmentProductReportMeta>{};
    if (ids.isEmpty) return out;
    // Batch get — avoid N+1 round trips where possible (chunks of 10 via getAll pattern).
    final stockCol = _db.collection('lojas').doc(lojaId).collection('estoque_produtos');
    final draftCol = _db.collection('lojas').doc(lojaId).collection('draft_produtos');
    for (var i = 0; i < ids.length; i += 30) {
      final chunk = ids.sublist(i, i + 30 > ids.length ? ids.length : i + 30);
      final stockRefs = chunk.map(stockCol.doc).toList();
      final draftRefs = chunk.map(draftCol.doc).toList();
      final stockSnaps = await Future.wait(stockRefs.map((r) => r.get()));
      final draftSnaps = await Future.wait(draftRefs.map((r) => r.get()));
      for (var j = 0; j < chunk.length; j++) {
        final id = chunk[j];
        final stock = stockSnaps[j].data() ?? <String, dynamic>{};
        final draft = draftSnaps[j].data() ?? <String, dynamic>{};
        final code = _codeFromMap(stock).isNotEmpty ? _codeFromMap(stock) : _codeFromMap(draft);
        final image = _imageFromMap(draft).isNotEmpty ? _imageFromMap(draft) : _imageFromMap(stock);
        out[id] = ConsignmentProductReportMeta(productCode: code, imageUrl: image);
      }
    }
    return out;
  }

  static Future<List<ConsignmentDoc>> loadFilteredConsignments({
    required String lojaId,
    String? resellerId,
    String? status,
    ConsignmentReportDateRange? range,
  }) async {
    final all = await ConsignmentService.watchConsignments(lojaId).first;
    return all
        .where(
          (d) => ConsignmentReportAggregator.matchesFilters(
            doc: d,
            lojaId: lojaId,
            resellerId: resellerId,
            status: status,
            range: range,
          ),
        )
        .toList();
  }

  static String sanitizeFileName(String input) {
    final cleaned = input
        .trim()
        .replaceAll(RegExp(r'[<>:"/\\|?*]+'), '')
        .replaceAll(RegExp(r'\s+'), '_');
    return cleaned.isEmpty ? 'Relatorio' : cleaned;
  }

  static String orderFileName(ConsignmentDoc doc, {DateTime? now}) {
    final d = now ?? DateTime.now();
    final day = DateFormat('yyyy-MM-dd').format(d);
    final name = sanitizeFileName(doc.resellerName);
    return 'Pedido_Consignacao_${name}_$day.pdf';
  }

  static String settlementFileName(ConsignmentDoc doc, {DateTime? now}) {
    final d = doc.settledAt?.toLocal() ?? now ?? DateTime.now();
    final day = DateFormat('yyyy-MM-dd').format(d);
    final name = sanitizeFileName(doc.resellerName);
    return 'Acerto_${name}_$day.pdf';
  }

  static String additionFileName(ConsignmentDoc doc, String additionId, {DateTime? now}) {
    final d = now ?? DateTime.now();
    final day = DateFormat('yyyy-MM-dd').format(d);
    final name = sanitizeFileName(doc.resellerName);
    final short = sanitizeFileName(additionId.length > 12 ? additionId.substring(0, 12) : additionId);
    return 'Acrescimo_Consignacao_${name}_${short}_$day.pdf';
  }

  static String generalFileName({DateTime? now}) {
    final d = now ?? DateTime.now();
    return 'Relatorio_Geral_Consignados_${DateFormat('yyyy-MM').format(d)}.pdf';
  }
}
