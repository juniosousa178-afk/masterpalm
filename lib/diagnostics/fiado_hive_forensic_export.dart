// Read-only forensic export of contas_receber Hive box (no PII).

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../core/client_build_identity.dart';
import '../core/hive_box_names.dart';
import '../models/conta_receber.dart';
import '../services/conta_receber_service.dart';

/// Exports technical fiado cache fields for Incident Center forensics.
abstract final class FiadoHiveForensicExport {
  FiadoHiveForensicExport._();

  static String _hashBaixaId(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '';
    return sha256.convert(utf8.encode(t)).toString().substring(0, 12);
  }

  static Map<String, dynamic> _titleRow(ContaReceber c, {required int localKey}) {
    final hist = c.historicoPagamentos();
    final baixaHashes = <String>[];
    for (final h in hist) {
      final bx = (h['baixaId'] ?? '').toString();
      final hashed = _hashBaixaId(bx);
      if (hashed.isNotEmpty) baixaHashes.add(hashed);
    }
    return {
      'localKey': localKey,
      'idFirebase': (c.idFirebase ?? '').trim(),
      'status': c.status,
      'pago': c.pago,
      'valor': c.valor,
      'saldoAtual': c.saldoRestante,
      'valorPago': c.valorPago,
      'valorOriginal': c.valorOriginal,
      'dataVencimento': c.dataVencimento.toUtc().toIso8601String(),
      'dataVenda': c.dataVenda.toUtc().toIso8601String(),
      'parcelaNumero': c.parcelaNumero,
      'parcelaTotal': c.parcelaTotal,
      'vendaIdFirebase': c.vendaIdFirebase.trim().isEmpty
          ? null
          : c.vendaIdFirebase.trim(),
      'vendaKey': c.vendaKey,
      'paymentHistoryCount': hist.length,
      'baixaIdHashes': baixaHashes,
      // Explicitly omit: clienteNome, observacao, phone, CPF, notes.
    };
  }

  /// Builds a downloadable JSON map. Never includes customer PII.
  static Future<Map<String, dynamic>> build({required String lojaId}) async {
    final loja = lojaId.trim();
    if (loja.isEmpty) {
      throw ArgumentError('lojaId vazio');
    }
    final box = await ContaReceberService.openBoxLoja(loja);
    final titles = <Map<String, dynamic>>[];
    var open = 0;
    var paid = 0;
    var cancelled = 0;
    for (final c in box.values) {
      if (!ContaReceberService.contaPertenceALoja(c, loja)) continue;
      final key = c.key;
      final localKey = key is int ? key : -1;
      titles.add(_titleRow(c, localKey: localKey));
      final st = c.status.trim().toLowerCase();
      if (st == ContaReceberStatus.cancelada) {
        cancelled++;
      } else if (c.pago || c.saldoRestante < 0.01) {
        paid++;
      } else {
        open++;
      }
    }
    return {
      'exportType': 'FIADO_HIVE_FORENSIC',
      'readOnly': true,
      'storeId': loja,
      'hiveBox': HiveBoxNames.contasReceber(loja),
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'CLIENT_BUILD_ID': kClientBuildId,
      'APP_VERSION': kClientAppVersion,
      'CLIENT_GIT_COMMIT': kClientGitCommit,
      'counts': {
        'total': titles.length,
        'open': open,
        'paid': paid,
        'cancelled': cancelled,
      },
      'titles': titles,
      'piiExcluded': true,
    };
  }

  static Future<({String fileName, List<int> bytes, String pretty})> exportBytes({
    required String lojaId,
  }) async {
    final payload = await build(lojaId: lojaId);
    final pretty = const JsonEncoder.withIndent('  ').convert(payload);
    final safeStore = lojaId
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')
        .toUpperCase();
    final ts = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('-', '')
        .replaceAll('.', '');
    final name = 'MASTERPALM_FIADO_HIVE_${safeStore}_$ts.json';
    debugPrint('[FIADO-HIVE-EXPORT] store=$lojaId titles=${payload['counts']}');
    return (fileName: name, bytes: utf8.encode(pretty), pretty: pretty);
  }
}
