import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../consignment_models.dart';
import '../consignment_ui.dart';
import 'consignment_report_data.dart';

final _money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final _date = DateFormat('dd/MM/yyyy');
final _dateTime = DateFormat('dd/MM/yyyy HH:mm');

class ConsignmentReportPdfBuilder {
  ConsignmentReportPdfBuilder._();

  static Future<pw.ImageProvider?> _logo(String url) async {
    if (url.trim().isEmpty) return null;
    try {
      return await networkImage(url.trim());
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, pw.ImageProvider?>> _photos(
    Iterable<ConsignmentReportLineView> lines,
  ) async {
    final out = <String, pw.ImageProvider?>{};
    final urls = <String, String>{};
    for (final l in lines) {
      if (l.imageUrl.trim().isEmpty) continue;
      urls.putIfAbsent(l.productId, () => l.imageUrl.trim());
    }
    await Future.wait(urls.entries.map((e) async {
      try {
        out[e.key] = await networkImage(e.value);
      } catch (_) {
        out[e.key] = null;
      }
    }));
    return out;
  }

  static pw.Widget _photoCell(pw.ImageProvider? img) {
    return pw.Container(
      width: 42,
      height: 42,
      alignment: pw.Alignment.center,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
        color: PdfColors.grey100,
      ),
      child: img == null
          ? pw.Text('Sem foto', style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey600))
          : pw.Image(img, fit: pw.BoxFit.contain, width: 40, height: 40),
    );
  }

  static pw.Widget _storeHeader(ConsignmentStoreProfile store, pw.ImageProvider? logo) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (logo != null)
          pw.Container(
            width: 56,
            height: 56,
            margin: const pw.EdgeInsets.only(right: 12),
            child: pw.Image(logo, fit: pw.BoxFit.contain),
          ),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(store.name, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              if (store.cnpj.isNotEmpty) pw.Text('CNPJ/CPF: ${store.cnpj}', style: const pw.TextStyle(fontSize: 9)),
              if (store.phone.isNotEmpty) pw.Text('Tel: ${store.phone}', style: const pw.TextStyle(fontSize: 9)),
              if (store.whatsapp.isNotEmpty && store.whatsapp != store.phone)
                pw.Text('WhatsApp: ${store.whatsapp}', style: const pw.TextStyle(fontSize: 9)),
              if (store.instagram.isNotEmpty)
                pw.Text('Instagram: ${store.instagram}', style: const pw.TextStyle(fontSize: 9)),
              if (store.address.isNotEmpty)
                pw.Text(store.address, style: const pw.TextStyle(fontSize: 9)),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _signatures({required String declaration}) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 28),
        pw.Text(declaration, style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 36),
        pw.Row(
          children: [
            pw.Expanded(
              child: pw.Column(children: [
                pw.Divider(thickness: 0.8),
                pw.SizedBox(height: 4),
                pw.Text('Responsável pela loja', style: const pw.TextStyle(fontSize: 9)),
              ]),
            ),
            pw.SizedBox(width: 28),
            pw.Expanded(
              child: pw.Column(children: [
                pw.Divider(thickness: 0.8),
                pw.SizedBox(height: 4),
                pw.Text('Revendedor', style: const pw.TextStyle(fontSize: 9)),
              ]),
            ),
          ],
        ),
      ],
    );
  }

  static String _footer(ConsignmentStoreProfile store, pw.Context ctx) {
    return '${store.name} · MasterPalm · ${_dateTime.format(DateTime.now())} · Página ${ctx.pageNumber} de ${ctx.pagesCount}';
  }

  static Future<Uint8List> buildOrderPdf({
    required ConsignmentStoreProfile store,
    required ConsignmentDoc doc,
    required List<ConsignmentReportLineView> lines,
    ConsignmentReseller? reseller,
  }) async {
    final logo = await _logo(store.logoUrl);
    final photos = await _photos(lines);

    final pdf = pw.Document(title: 'Pedido consignação ${doc.id}');
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 36),
        footer: (ctx) => pw.Text(_footer(store, ctx), style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
        build: (ctx) => [
          _storeHeader(store, logo),
          pw.SizedBox(height: 12),
          ..._orderBody(
            title: 'RELATÓRIO DE CONSIGNAÇÃO / PEDIDO',
            doc: doc,
            lines: lines,
            photos: photos,
            reseller: reseller,
          ),
          _signatures(
            declaration:
                'Declaro que recebi as peças relacionadas acima nas quantidades e condições descritas neste documento.',
          ),
          ..._deliveryHistory(doc),
        ],
      ),
    );
    return pdf.save();
  }

  /// Body of the single order report (identification, items table and totals box).
  static List<pw.Widget> _orderBody({
    required String title,
    required ConsignmentDoc doc,
    required List<ConsignmentReportLineView> lines,
    required Map<String, pw.ImageProvider?> photos,
    ConsignmentReseller? reseller,
  }) {
    final models = lines.length;
    final pieces = lines.fold<int>(0, (s, l) => s + l.qtySent);
    final total = lines.fold<double>(0, (s, l) => s + l.lineConsignedValue);
    final commissionHints = lines
        .map((l) => consignmentReportCommissionLabel(l.commissionType, l.commissionValue))
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    return [
          pw.Text(title,
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Text('Nº ${doc.id}', style: const pw.TextStyle(fontSize: 10)),
          if (doc.issuedAt != null || doc.createdAt != null)
            pw.Text(
              'Data: ${_dateTime.format((doc.issuedAt ?? doc.createdAt)!.toLocal())}',
              style: const pw.TextStyle(fontSize: 10),
            ),
          pw.Text('Status: ${consignmentStatusLabel(doc.status)}', style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 6),
          pw.Text('Revendedor: ${doc.resellerName}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          if ((reseller?.phone ?? '').isNotEmpty) pw.Text('Telefone: ${reseller!.phone}', style: const pw.TextStyle(fontSize: 10)),
          pw.Text('ID revendedor: ${doc.resellerId}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          if (doc.notes.trim().isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text('Observação: ${doc.notes}', style: const pw.TextStyle(fontSize: 10)),
          ],
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: ['Foto', 'Código', 'Produto', 'Variação', 'Qtd', 'Unit.', 'Total'],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
            cellStyle: const pw.TextStyle(fontSize: 8),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellAlignments: {
              0: pw.Alignment.center,
              4: pw.Alignment.center,
              5: pw.Alignment.centerRight,
              6: pw.Alignment.centerRight,
            },
            columnWidths: {
              0: const pw.FixedColumnWidth(48),
              1: const pw.FlexColumnWidth(1.1),
              2: const pw.FlexColumnWidth(2.4),
              3: const pw.FlexColumnWidth(1.4),
              4: const pw.FixedColumnWidth(28),
              5: const pw.FlexColumnWidth(1.1),
              6: const pw.FlexColumnWidth(1.1),
            },
            data: [
              for (final l in lines)
                [
                  _photoCell(photos[l.productId]),
                  l.productCode.isEmpty ? '—' : l.productCode,
                  l.productName,
                  l.variationLabel.isEmpty ? '—' : l.variationLabel,
                  '${l.qtySent}',
                  _money.format(l.unitPrice),
                  _money.format(l.lineConsignedValue),
                ],
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400),
              color: PdfColors.grey50,
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('TOTAL DE MODELOS: $models', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                pw.Text('TOTAL DE PEÇAS: $pieces', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                pw.Text('VALOR TOTAL CONSIGNADO: ${_money.format(total)}',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                for (final h in commissionHints) pw.Text(h, style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
          ),
          ..._withdrawalsSection(doc),
    ];
  }

  /// Only rendered when the store took pieces back before settlement; original lines stay above.
  static List<pw.Widget> _withdrawalsSection(ConsignmentDoc doc) {
    final rows = ConsignmentReportAggregator.withdrawalsOf(doc);
    if (rows.isEmpty) return const [];
    final pieces = rows.fold<int>(0, (s, r) => s + r.qty);
    final total = rows.fold<double>(0, (s, r) => s + r.total);
    return [
      pw.SizedBox(height: 14),
      pw.Text('RETIRADAS ANTES DO ACERTO',
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 6),
      pw.TableHelper.fromTextArray(
        headers: ['Data', 'Código', 'Produto', 'Variação', 'Qtd', 'Unit.', 'Total'],
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
        cellStyle: const pw.TextStyle(fontSize: 8),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
        cellAlignments: {
          4: pw.Alignment.center,
          5: pw.Alignment.centerRight,
          6: pw.Alignment.centerRight,
        },
        data: [
          for (final r in rows)
            [
              r.date == null ? '-' : _date.format(r.date!.toLocal()),
              r.productCode.isEmpty ? '-' : r.productCode,
              r.productName,
              r.variationLabel.isEmpty ? '-' : r.variationLabel,
              '${r.qty}',
              _money.format(r.unitPrice),
              _money.format(r.total),
            ],
        ],
      ),
      pw.SizedBox(height: 6),
      pw.Text('TOTAL RETIRADO: $pieces ${pieces == 1 ? 'peça' : 'peças'} · ${_money.format(total)}',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
      if (doc.isIssued)
        pw.Text(
          'COM A REVENDEDORA: ${doc.totalItemsOutstanding} peças · ${_money.format(doc.outstandingGrossAmount)}',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
        ),
      pw.Text('Peças retiradas voltaram ao estoque da loja e não entram no acerto da revendedora.',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
    ];
  }

  static List<pw.Widget> _deliveryHistory(ConsignmentDoc doc) {
    return [
          if (doc.additions.isNotEmpty) ...[
            pw.SizedBox(height: 18),
            pw.Text('HISTÓRICO DE ENTREGAS',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            for (final raw in doc.additions)
              () {
                final a = Map<String, dynamic>.from(raw as Map);
                final kind = '${a['kind'] ?? 'ADDITION'}';
                final label = kind == 'INITIAL' ? 'Envio inicial' : 'Acréscimo';
                final lines = (a['lines'] is List)
                    ? (a['lines'] as List).whereType<Map>().toList()
                    : const <Map>[];
                final parts = <String>[];
                for (final l in lines) {
                  final name = '${l['productNameSnapshot'] ?? l['productId'] ?? ''}';
                  final qty = l['qtyAdded'] ?? l['qtySent'] ?? 0;
                  parts.add('$name=$qty');
                }
                return pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4),
                  child: pw.Text(
                    '$label · ${parts.join(' · ')}',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                );
              }(),
          ],
    ];
  }

  static Future<Uint8List> buildAdditionPdf({
    required ConsignmentStoreProfile store,
    required ConsignmentDoc doc,
    required String additionId,
    required List<ConsignmentReportLineView> lines,
    ConsignmentReseller? reseller,
    dynamic createdAt,
  }) async {
    final logo = await _logo(store.logoUrl);
    DateTime? when;
    if (createdAt is DateTime) {
      when = createdAt;
    } else if (createdAt != null) {
      try {
        final seconds = createdAt.seconds;
        if (seconds is int) {
          when = DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
        }
      } catch (_) {
        when = DateTime.tryParse('$createdAt');
      }
    }
    when ??= DateTime.now();
    final pieces = lines.fold<int>(0, (s, l) => s + l.qtySent);
    final total = lines.fold<double>(0, (s, l) => s + l.lineConsignedValue);
    final pdf = pw.Document(title: 'Acréscimo consignação ${doc.id}');
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 36),
        footer: (ctx) => pw.Text(_footer(store, ctx), style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
        build: (ctx) => [
          _storeHeader(store, logo),
          pw.SizedBox(height: 12),
          pw.Text('COMPROVANTE DE ACRÉSCIMO DE CONSIGNAÇÃO',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Text('Consignação: ${doc.id}', style: const pw.TextStyle(fontSize: 10)),
          pw.Text('Acréscimo: $additionId', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          pw.Text('Data: ${_dateTime.format(when!.toLocal())}', style: const pw.TextStyle(fontSize: 10)),
          pw.Text('Revendedor: ${doc.resellerName}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          if ((reseller?.phone ?? '').isNotEmpty)
            pw.Text('Telefone: ${reseller!.phone}', style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: ['Produto', 'Variação', 'Qtd', 'Unit.', 'Total'],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            data: [
              for (final l in lines)
                [
                  l.productName,
                  l.variationLabel.isEmpty ? '—' : l.variationLabel,
                  '${l.qtySent}',
                  _money.format(l.unitPrice),
                  _money.format(l.lineConsignedValue),
                ],
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Text('TOTAL DE PEÇAS: $pieces', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          pw.Text('VALOR DESTE ACRÉSCIMO: ${_money.format(total)}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
          _signatures(
            declaration:
                'Declaro que recebi as peças deste acréscimo nas quantidades e condições descritas neste documento.',
          ),
        ],
      ),
    );
    return pdf.save();
  }

  static Future<Uint8List> buildSettlementPdf({
    required ConsignmentStoreProfile store,
    required ConsignmentDoc doc,
    required List<ConsignmentReportLineView> lines,
    ConsignmentReseller? reseller,
  }) async {
    final logo = await _logo(store.logoUrl);
    final photos = await _photos(lines);
    final pending = lines.fold<int>(0, (s, l) => s + l.qtyPending);
    final pdf = pw.Document(title: 'Acerto consignação ${doc.id}');
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(24, 24, 24, 32),
        footer: (ctx) => pw.Text(_footer(store, ctx), style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
        build: (ctx) => [
          _storeHeader(store, logo),
          pw.SizedBox(height: 10),
          pw.Text('RELATÓRIO DE ACERTO DE CONSIGNAÇÃO',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Text('Acerto / Consignação nº ${doc.id}', style: const pw.TextStyle(fontSize: 10)),
          if (doc.issuedAt != null)
            pw.Text('Data do envio: ${_dateTime.format(doc.issuedAt!.toLocal())}', style: const pw.TextStyle(fontSize: 10)),
          if (doc.settledAt != null)
            pw.Text('Data do acerto: ${_dateTime.format(doc.settledAt!.toLocal())}', style: const pw.TextStyle(fontSize: 10)),
          pw.Text('Revendedor: ${doc.resellerName}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          if ((reseller?.phone ?? '').isNotEmpty) pw.Text('Telefone: ${reseller!.phone}', style: const pw.TextStyle(fontSize: 10)),
          pw.Text('Status: ${consignmentStatusLabel(doc.status)}', style: const pw.TextStyle(fontSize: 10)),
          if (doc.notes.trim().isNotEmpty) pw.Text('Observações: ${doc.notes}', style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: [
              'Foto',
              'Código',
              'Produto',
              'Var.',
              'Env',
              'Vend',
              'Dev',
              'Pend',
              'Unit.',
              'Total vend.',
              'Comissão',
              'Líquido',
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7),
            cellStyle: const pw.TextStyle(fontSize: 7),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellAlignments: {
              0: pw.Alignment.center,
              4: pw.Alignment.center,
              5: pw.Alignment.center,
              6: pw.Alignment.center,
              7: pw.Alignment.center,
              8: pw.Alignment.centerRight,
              9: pw.Alignment.centerRight,
              10: pw.Alignment.centerRight,
              11: pw.Alignment.centerRight,
            },
            data: [
              for (final l in lines)
                [
                  _photoCell(photos[l.productId]),
                  l.productCode.isEmpty ? '—' : l.productCode,
                  l.productName,
                  l.variationLabel.isEmpty ? '—' : l.variationLabel,
                  '${l.qtySent}',
                  '${l.qtySold}',
                  '${l.qtyReturned}',
                  '${l.qtyPending}',
                  _money.format(l.unitPrice),
                  _money.format(l.lineGrossSold),
                  _money.format(l.lineCommission),
                  _money.format(l.lineNet),
                ],
            ],
          ),
          ..._withdrawalsSection(doc),
          pw.SizedBox(height: 12),
          _settlementSummary(doc, pending),
          _signatures(
            declaration:
                'Declaro estar de acordo com as quantidades, vendas, devoluções, comissão e valores apresentados neste acerto.',
          ),
        ],
      ),
    );
    return pdf.save();
  }

  static pw.Widget _settlementSummary(ConsignmentDoc doc, int pending) {
    return pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey500),
              color: PdfColors.grey50,
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('RESUMO DO ACERTO', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                pw.SizedBox(height: 4),
                pw.Text('Peças enviadas: ${doc.totalItemsSent}'),
                if (doc.totalItemsWithdrawn > 0)
                  pw.Text('Peças retiradas antes do acerto: ${doc.totalItemsWithdrawn}'),
                pw.Text('Peças vendidas: ${doc.totalItemsSold}'),
                pw.Text('Peças devolvidas: ${doc.totalItemsReturned}'),
                pw.Text('Peças pendentes: $pending'),
                pw.SizedBox(height: 4),
                pw.Text('Valor bruto vendido: ${_money.format(doc.grossSoldAmount)}'),
                pw.Text('Comissão: ${_money.format(doc.commissionAmount)}'),
                pw.Text('Valor líquido da loja: ${_money.format(doc.netAmount)}'),
                if (doc.isSettled) ...[
                  pw.Text('Forma de pagamento: Consignação'),
                  if (doc.settledAt != null)
                    pw.Text('Data do pagamento: ${_date.format(doc.settledAt!.toLocal())}'),
                  pw.Text('Valor recebido: ${_money.format(doc.netAmount)}'),
                  pw.Text('Saldo pendente: ${_money.format(0)}'),
                  pw.SizedBox(height: 4),
                  pw.Text('STATUS DO ACERTO: PAGO', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                ],
              ],
            ),
          );
  }

  /// Several consignments of the same reseller in one PDF: cover, one independent section per
  /// consignment (each starting on a new page, same body as the single order report) and a
  /// general summary. Sections are never merged or deduplicated.
  static Future<Uint8List> buildCombinedPdf({
    required ConsignmentStoreProfile store,
    required List<ConsignmentCombinedSection> sections,
    ConsignmentReseller? reseller,
    DateTime? generatedAt,
  }) async {
    final logo = await _logo(store.logoUrl);
    final photos = await _photos(sections.expand((s) => s.lines));
    final summary = ConsignmentCombinedReportPlanner.summarize(sections);
    final first = sections.first.doc;
    final when = generatedAt ?? DateTime.now();
    final n = sections.length;
    const margin = pw.EdgeInsets.fromLTRB(28, 28, 28, 36);
    pw.Widget footer(pw.Context ctx) =>
        pw.Text(_footer(store, ctx), style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600));
    pw.Widget bold(String text, {double size = 10}) =>
        pw.Text(text, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: size));
    const small = pw.TextStyle(fontSize: 10);

    final pdf = pw.Document(title: 'Relatório consolidado de consignações');
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: margin,
        footer: footer,
        build: (ctx) => [
          _storeHeader(store, logo),
          pw.SizedBox(height: 12),
          bold('RELATÓRIO CONSOLIDADO DE CONSIGNAÇÕES', size: 14),
          pw.SizedBox(height: 8),
          pw.Text('Revendedor: ${first.resellerName}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          if ((reseller?.phone ?? '').isNotEmpty) pw.Text('Telefone: ${reseller!.phone}', style: small),
          pw.Text('ID revendedor: ${first.resellerId}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          pw.Text('Emissão: ${_dateTime.format(when)}', style: small),
          pw.SizedBox(height: 10),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400), color: PdfColors.grey50),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                bold('CONSIGNAÇÕES SELECIONADAS: $n'),
                bold('TOTAL DE PEÇAS: ${summary.piecesSent}'),
                bold('VALOR TOTAL CONSIGNADO: ${_money.format(summary.consignedValue)}', size: 11),
                if (summary.settledCount > 0)
                  pw.Text('Comissão (consignações acertadas): ${_money.format(summary.commission)}', style: small),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: ['#', 'Consignação', 'Data', 'Status', 'Peças', 'Valor consignado'],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
            cellStyle: const pw.TextStyle(fontSize: 8),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellAlignments: {0: pw.Alignment.center, 4: pw.Alignment.center, 5: pw.Alignment.centerRight},
            data: [
              for (var i = 0; i < n; i++)
                [
                  '${i + 1}',
                  sections[i].doc.id,
                  () {
                    final d = sections[i].doc.issuedAt ?? sections[i].doc.createdAt;
                    return d == null ? '-' : _date.format(d.toLocal());
                  }(),
                  consignmentStatusLabel(sections[i].doc.status),
                  '${sections[i].pieces}',
                  _money.format(sections[i].consignedValue),
                ],
            ],
          ),
        ],
      ),
    );
    for (var i = 0; i < n; i++) {
      final s = sections[i];
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: margin,
          footer: footer,
          build: (ctx) => [
            ..._orderBody(
              title: 'CONSIGNAÇÃO ${i + 1} DE $n',
              doc: s.doc,
              lines: s.lines,
              photos: photos,
              reseller: reseller,
            ),
            if (s.doc.isSettled) ...[
              pw.SizedBox(height: 12),
              _settlementSummary(s.doc, s.pending),
            ],
            ..._deliveryHistory(s.doc),
          ],
        ),
      );
    }
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: margin,
        footer: footer,
        build: (ctx) => [
          bold('RESUMO GERAL', size: 14),
          pw.SizedBox(height: 4),
          pw.Text('Revendedor: ${first.resellerName}', style: small),
          pw.SizedBox(height: 10),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey500), color: PdfColors.grey50),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                bold('Consignações selecionadas: ${summary.consignments}'),
                for (final e in summary.byStatus.entries)
                  pw.Text('${consignmentStatusLabel(e.key)}: ${e.value}', style: small),
                pw.SizedBox(height: 4),
                pw.Text('Total de modelos (linhas): ${summary.models}', style: small),
                bold('Total de peças enviadas: ${summary.piecesSent}'),
                bold('Valor total consignado: ${_money.format(summary.consignedValue)}', size: 11),
                if (summary.settledCount > 0) ...[
                  pw.SizedBox(height: 6),
                  bold('Consignações acertadas (${summary.settledCount})'),
                  pw.Text('Peças vendidas: ${summary.piecesSold}', style: small),
                  pw.Text('Peças devolvidas: ${summary.piecesReturned}', style: small),
                  pw.Text('Valor bruto vendido: ${_money.format(summary.grossSold)}', style: small),
                  pw.Text('Comissão: ${_money.format(summary.commission)}', style: small),
                  pw.Text('Valor líquido da loja: ${_money.format(summary.net)}', style: small),
                ],
                pw.Text('Peças pendentes: ${summary.piecesPending}', style: small),
              ],
            ),
          ),
          _signatures(
            declaration:
                'Declaro que recebi as peças relacionadas nas consignações deste relatório, nas quantidades e condições descritas.',
          ),
        ],
      ),
    );
    return pdf.save();
  }

  static Future<Uint8List> buildGeneralPdf({
    required ConsignmentStoreProfile store,
    required ConsignmentReportDateRange range,
    required String statusFilterLabel,
    required List<Map<String, dynamic>> resellerRows,
    required Map<String, dynamic> totals,
  }) async {
    final logo = await _logo(store.logoUrl);
    final pdf = pw.Document(title: 'Relatório geral consignados');
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(24, 24, 24, 32),
        footer: (ctx) => pw.Text(_footer(store, ctx), style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
        build: (ctx) => [
          _storeHeader(store, logo),
          pw.SizedBox(height: 10),
          pw.Text('RELATÓRIO GERAL DE CONSIGNADOS',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.Text(
            'Período: ${_date.format(range.start)} — ${_date.format(range.end.subtract(const Duration(days: 1)))}',
            style: const pw.TextStyle(fontSize: 10),
          ),
          pw.Text('Emissão: ${_dateTime.format(DateTime.now())}', style: const pw.TextStyle(fontSize: 10)),
          pw.Text('Filtro de status: $statusFilterLabel', style: const pw.TextStyle(fontSize: 10)),
          pw.Text('Revendedores: ${resellerRows.length}', style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 10),
          pw.Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              _kpi('Peças em consignação', '${totals['pending']}'),
              _kpi('Peças vendidas', '${totals['sold']}'),
              _kpi('Peças devolvidas', '${totals['returned']}'),
              _kpi('Valor consignado', _money.format(totals['consigned'])),
              _kpi('Valor vendido', _money.format(totals['gross'])),
              _kpi('Comissões', _money.format(totals['commission'])),
              _kpi('Líquido loja', _money.format(totals['net'])),
              _kpi('Recebido', _money.format(totals['received'])),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: [
              'Revendedor',
              'Cons.',
              'Env.',
              'Vend.',
              'Dev.',
              'Pend.',
              'Consignado',
              'Bruto',
              'Comissão',
              'Líquido',
              'Recebido',
              'Últ. acerto',
              'Status',
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7),
            cellStyle: const pw.TextStyle(fontSize: 7),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellAlignments: {
              1: pw.Alignment.center,
              2: pw.Alignment.center,
              3: pw.Alignment.center,
              4: pw.Alignment.center,
              5: pw.Alignment.center,
              6: pw.Alignment.centerRight,
              7: pw.Alignment.centerRight,
              8: pw.Alignment.centerRight,
              9: pw.Alignment.centerRight,
              10: pw.Alignment.centerRight,
            },
            data: [
              for (final r in resellerRows)
                [
                  r['name'],
                  '${r['consignments']}',
                  '${r['sent']}',
                  '${r['sold']}',
                  '${r['returned']}',
                  '${r['pending']}',
                  _money.format(r['consigned']),
                  _money.format(r['gross']),
                  _money.format(r['commission']),
                  _money.format(r['net']),
                  _money.format(r['received']),
                  r['lastSettle'] is DateTime
                      ? _date.format((r['lastSettle'] as DateTime).toLocal())
                      : '—',
                  r['status'],
                ],
              [
                'TOTAL GERAL',
                '${totals['consignments']}',
                '${totals['sent']}',
                '${totals['sold']}',
                '${totals['returned']}',
                '${totals['pending']}',
                _money.format(totals['consigned']),
                _money.format(totals['gross']),
                _money.format(totals['commission']),
                _money.format(totals['net']),
                _money.format(totals['received']),
                '',
                '',
              ],
            ],
          ),
        ],
      ),
    );
    return pdf.save();
  }

  static pw.Widget _kpi(String label, String value) {
    return pw.Container(
      width: 120,
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
          pw.Text(value, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }
}
