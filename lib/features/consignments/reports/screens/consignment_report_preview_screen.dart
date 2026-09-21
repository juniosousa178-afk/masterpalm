import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../../design_system/mp_tokens.dart';
import '../consignment_report_actions.dart';

class ConsignmentReportPreviewScreen extends StatelessWidget {
  const ConsignmentReportPreviewScreen({
    super.key,
    required this.title,
    required this.fileName,
    required this.bytesFuture,
  });

  final String title;
  final String fileName;
  final Future<Uint8List> bytesFuture;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MpColors.background,
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Voltar',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: FutureBuilder<Uint8List>(
        future: bytesFuture,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Não foi possível gerar o relatório.\n${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final bytes = snap.data!;
          return Column(
            children: [
              Expanded(
                child: PdfPreview(
                  build: (_) async => bytes,
                  canChangeOrientation: false,
                  canChangePageFormat: false,
                  allowPrinting: true,
                  allowSharing: true,
                  pdfFileName: fileName,
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Voltar'),
                      ),
                      FilledButton.icon(
                        onPressed: () => ConsignmentReportActions.previewPdf(bytes, fileName: fileName),
                        icon: const Icon(Icons.print),
                        label: const Text('Imprimir'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () => ConsignmentReportActions.sharePdf(bytes, fileName: fileName),
                        icon: const Icon(Icons.picture_as_pdf),
                        label: const Text('Salvar / Compartilhar PDF'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
