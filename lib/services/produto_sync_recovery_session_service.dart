// Reparo local e reversível da sessão de loja para recuperação assistida.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import 'produto_sync_recovery_access.dart';
import 'produto_sync_recovery_models.dart';

class ProdutoSyncRecoverySessionService {
  ProdutoSyncRecoverySessionService._();

  static const _historyBoxName = 'produto_sync_recovery_session_history';
  static const _historyListKey = 'repairs';

  /// Atualiza somente sessão local para a loja canônica, com histórico.
  static Future<RecoverySessionRepairRecord?> repararSessaoParaLojaCanonica({
    required String lojaCanonica,
  }) async {
    final canonical = lojaCanonica.trim();
    if (canonical.isEmpty) return null;

    if (!await ProdutoSyncRecoveryAccess.podeAcessarRecuperacao()) {
      return null;
    }

    if (!await ProdutoSyncRecoveryAccess.canonicalPertenceAoUsuario(canonical)) {
      return null;
    }

    final sessaoStoreId = await _readSessionStoreIdLocal();
    if (sessaoStoreId == canonical) return null;

    final record = RecoverySessionRepairRecord(
      storeIdAnterior: sessaoStoreId ?? '',
      storeIdNovo: canonical,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      motivo: 'recuperacao_assistida',
    );

    await _appendHistory(record);

    final sessao =
        Hive.isBoxOpen('sessao') ? Hive.box('sessao') : await Hive.openBox('sessao');
    final cfg =
        Hive.isBoxOpen('config') ? Hive.box('config') : await Hive.openBox('config');

    await sessao.put('store_id', canonical);
    await cfg.put('store_id', canonical);
    await cfg.put('last_loja_id', canonical);

    return record;
  }

  static Future<String?> _readSessionStoreIdLocal() async {
    try {
      final sessao =
          Hive.isBoxOpen('sessao') ? Hive.box('sessao') : await Hive.openBox('sessao');
      final raw = (sessao.get('store_id') ?? '').toString().trim();
      return raw.isEmpty ? null : raw;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _appendHistory(RecoverySessionRepairRecord record) async {
    final box = await _openHistoryBox();
    final raw = box.get(_historyListKey);
    final list = <Map<String, dynamic>>[];
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final e in decoded) {
            if (e is Map) list.add(Map<String, dynamic>.from(e));
          }
        }
      } catch (_) {}
    }
    list.add(record.toMap());
    await box.put(_historyListKey, jsonEncode(list));
  }

  static Future<List<RecoverySessionRepairRecord>> listarHistorico() async {
    final box = await _openHistoryBox();
    final raw = box.get(_historyListKey);
    if (raw is! String) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((e) => RecoverySessionRepairRecord.fromMap(
                Map<String, dynamic>.from(e),
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<Box> _openHistoryBox() async {
    if (Hive.isBoxOpen(_historyBoxName)) return Hive.box(_historyBoxName);
    return Hive.openBox(_historyBoxName);
  }

  @visibleForTesting
  static Future<void> resetHistoryForTests() async {
    if (Hive.isBoxOpen(_historyBoxName)) {
      await Hive.box(_historyBoxName).clear();
    }
  }
}
