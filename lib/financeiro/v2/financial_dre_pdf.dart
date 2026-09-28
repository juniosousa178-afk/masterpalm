// PDF da DRE. Usa o demonstrativo já calculado; não recalcula totais.

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'financial_dre.dart';

class DrePdfDocumentPlan {
  const DrePdfDocumentPlan({
    required this.statement,
    required this.rows,
    required this.fingerprint,
  });

  final DreStatement statement;
  final List<DreRenderRow> rows;
  final String fingerprint;

  factory DrePdfDocumentPlan.fromStatement(DreStatement statement) {
    return DrePdfDocumentPlan(
      statement: statement,
      rows: DrePresentation.rows(statement),
      fingerprint: DrePresentation.fingerprint(statement),
    );
  }
}

String _pdfText(String value) {
  return value
      .replaceAll('—', ' - ')
      .replaceAll('–', '-')
      .replaceAll('•', '-');
}

bool get drePdfIsA4Portrait => PdfPageFormat.a4.height > PdfPageFormat.a4.width;

Future<Uint8List> buildDrePdf(DreStatement statement) {
  final plan = DrePdfDocumentPlan.fromStatement(statement);
  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Página ${context.pageNumber} de ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 9),
        ),
      ),
      build: (context) => [
        pw.Text(
          _pdfText(plan.statement.storeName),
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          'DRE - Demonstrativo de Resultado',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text('Período: ${_pdfText(plan.statement.period.label)}'),
        pw.Text(
          'Gerado em ${formatDreDateTime(plan.statement.generatedAt)}',
          style: const pw.TextStyle(fontSize: 9),
        ),
        pw.SizedBox(height: 16),
        ...plan.rows.map(
          (row) => pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 3),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  child: pw.Text(
                    _pdfText(row.label),
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: row.emphasis
                          ? pw.FontWeight.bold
                          : pw.FontWeight.normal,
                    ),
                  ),
                ),
                pw.Text(
                  row.amount,
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: row.emphasis
                        ? pw.FontWeight.bold
                        : pw.FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
        pw.SizedBox(height: 18),
        pw.Text(
          'Qualidade da DRE',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        ...plan.statement.qualityNotes.map(
          (note) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 3),
            child: pw.Text('- ${_pdfText(note)}', style: const pw.TextStyle(fontSize: 9)),
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          'Lucro líquido não é apresentado nesta fase.',
          style: const pw.TextStyle(fontSize: 9),
        ),
      ],
    ),
  );
  return doc.save();
}

Future<void> printDreStatement(DreStatement statement) {
  return Printing.layoutPdf(
    name: dreFileName(statement),
    onLayout: (_) => buildDrePdf(statement),
  );
}

Future<void> shareDrePdf(DreStatement statement) async {
  final bytes = await buildDrePdf(statement);
  await Printing.sharePdf(bytes: bytes, filename: dreFileName(statement));
}
