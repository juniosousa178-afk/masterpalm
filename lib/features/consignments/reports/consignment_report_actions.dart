import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../consignment_models.dart';
import 'consignment_report_data.dart';
import 'consignment_report_pdf.dart';

enum ConsignmentReportKind { order, settlement, general, addition }

/// Read-only PDF actions — never mutate consignments/stock.
class ConsignmentReportActions {
  ConsignmentReportActions._();

  static Future<Uint8List> buildOrderBytes({
    required String lojaId,
    required ConsignmentDoc doc,
    ConsignmentReseller? reseller,
  }) async {
    final store = await ConsignmentReportDataService.loadStoreProfile(lojaId);
    final meta = await ConsignmentReportDataService.loadProductMeta(
      lojaId: lojaId,
      productIds: doc.lines.map((e) => (e['productId'] ?? '').toString()),
    );
    final lines = ConsignmentReportAggregator.linesOf(doc, meta: meta);
    return ConsignmentReportPdfBuilder.buildOrderPdf(
      store: store,
      doc: doc,
      lines: lines,
      reseller: reseller,
    );
  }

  static Future<Uint8List> buildSettlementBytes({
    required String lojaId,
    required ConsignmentDoc doc,
    ConsignmentReseller? reseller,
  }) async {
    final store = await ConsignmentReportDataService.loadStoreProfile(lojaId);
    final meta = await ConsignmentReportDataService.loadProductMeta(
      lojaId: lojaId,
      productIds: doc.lines.map((e) => (e['productId'] ?? '').toString()),
    );
    final lines = ConsignmentReportAggregator.linesOf(doc, meta: meta);
    return ConsignmentReportPdfBuilder.buildSettlementPdf(
      store: store,
      doc: doc,
      lines: lines,
      reseller: reseller,
    );
  }

  static Future<Uint8List> buildGeneralBytes({
    required String lojaId,
    required ConsignmentReportDateRange range,
    String? resellerId,
    String? status,
    String statusFilterLabel = 'Todos',
  }) async {
    final store = await ConsignmentReportDataService.loadStoreProfile(lojaId);
    final docs = await ConsignmentReportDataService.loadFilteredConsignments(
      lojaId: lojaId,
      resellerId: resellerId,
      status: status,
      range: range,
    );
    final byReseller = <String, List<ConsignmentDoc>>{};
    for (final d in docs) {
      byReseller.putIfAbsent(d.resellerId, () => []).add(d);
    }
    final rows = <Map<String, dynamic>>[];
    for (final entry in byReseller.entries) {
      final roll = ConsignmentReportAggregator.resellerRollup(entry.value);
      rows.add({
        ...roll,
        'resellerId': entry.key,
        'name': entry.value.first.resellerName,
      });
    }
    rows.sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
    final totals = ConsignmentReportAggregator.generalTotals(rows);
    return ConsignmentReportPdfBuilder.buildGeneralPdf(
      store: store,
      range: range,
      statusFilterLabel: statusFilterLabel,
      resellerRows: rows,
      totals: totals,
    );
  }

  static Future<Uint8List> buildAdditionBytes({
    required String lojaId,
    required ConsignmentDoc doc,
    required String additionId,
    ConsignmentReseller? reseller,
  }) async {
    final store = await ConsignmentReportDataService.loadStoreProfile(lojaId);
    final addition = doc.additions.cast<Map<String, dynamic>?>().firstWhere(
          (a) => a != null && '${a['additionId']}' == additionId,
          orElse: () => null,
        );
    final rawLines = addition == null
        ? const <Map<String, dynamic>>[]
        : ((addition['lines'] is List)
            ? (addition['lines'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
            : const <Map<String, dynamic>>[]);
    final meta = await ConsignmentReportDataService.loadProductMeta(
      lojaId: lojaId,
      productIds: rawLines.map((e) => (e['productId'] ?? '').toString()),
    );
    final lines = ConsignmentReportAggregator.additionLinesOf(
      rawLines,
      meta: meta,
    );
    return ConsignmentReportPdfBuilder.buildAdditionPdf(
      store: store,
      doc: doc,
      additionId: additionId,
      lines: lines,
      reseller: reseller,
      createdAt: addition?['createdAt'],
    );
  }

  static Future<void> previewPdf(Uint8List bytes, {String? fileName}) async {
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: fileName ?? 'relatorio.pdf');
  }

  static Future<void> sharePdf(Uint8List bytes, {required String fileName}) async {
    if (kIsWeb) {
      await Printing.sharePdf(bytes: bytes, filename: fileName);
      return;
    }
    await Share.shareXFiles(
      [XFile.fromData(bytes, mimeType: 'application/pdf', name: fileName)],
      fileNameOverrides: [fileName],
    );
  }
}
