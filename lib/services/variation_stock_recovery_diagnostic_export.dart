// iOS Safari–friendly export helpers for variation stock recovery diagnostic.

import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design_system/mp_components.dart';
import '../src/file_saver.dart';
import 'variation_stock_recovery_diagnostic.dart';

class VariationStockRecoveryDiagnosticExportResult {
  const VariationStockRecoveryDiagnosticExportResult({
    required this.copiedToClipboard,
    required this.downloadAttempted,
    required this.downloadOk,
    this.error,
  });

  final bool copiedToClipboard;
  final bool downloadAttempted;
  final bool downloadOk;
  final String? error;
}

class VariationStockRecoveryDiagnosticExporter {
  VariationStockRecoveryDiagnosticExporter._();

  static Future<VariationStockRecoveryDiagnosticExportResult> exportSnapshot(
    BuildContext context,
    VariationStockRecoveryDiagnosticSnapshot snapshot, {
    bool preferClipboardFirst = true,
  }) async {
    final text = snapshot.toPrettyJson();
    var copied = false;
    var downloadAttempted = false;
    var downloadOk = false;
    String? error;

    if (preferClipboardFirst) {
      try {
        await Clipboard.setData(ClipboardData(text: text));
        copied = true;
      } catch (e) {
        error = 'clipboard_${e.runtimeType}';
      }
    }

    // Web/iOS: also try file download (may be ignored by Safari — clipboard is primary).
    if (kIsWeb || !preferClipboardFirst) {
      downloadAttempted = true;
      try {
        final bytes = Uint8List.fromList(utf8.encode(text));
        final name =
            'mp_variation_recovery_diag_${DateTime.now().toUtc().millisecondsSinceEpoch}.json';
        await saveFile(bytes, name);
        downloadOk = true;
      } catch (e) {
        error ??= 'download_${e.runtimeType}';
      }
    }

    if (!copied && !preferClipboardFirst) {
      try {
        await Clipboard.setData(ClipboardData(text: text));
        copied = true;
      } catch (e) {
        error ??= 'clipboard_${e.runtimeType}';
      }
    }

    if (context.mounted) {
      if (copied) {
        MpSuccessSnack.show(
          context,
          downloadOk
              ? 'Diagnóstico copiado e arquivo gerado.'
              : 'Diagnóstico copiado. Cole num e-mail ou mensagem.',
        );
      } else if (downloadOk) {
        MpSuccessSnack.show(context, 'Arquivo de diagnóstico gerado.');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Não foi possível exportar (${error ?? 'desconhecido'}).',
            ),
          ),
        );
      }
    }

    return VariationStockRecoveryDiagnosticExportResult(
      copiedToClipboard: copied,
      downloadAttempted: downloadAttempted,
      downloadOk: downloadOk,
      error: error,
    );
  }
}
