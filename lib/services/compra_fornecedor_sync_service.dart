// Sincronização opcional da compra local com Firestore (espelho). Não cria financeiro.

import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/foundation.dart';

import '../models/compra_fornecedor.dart';
import 'compra_fornecedor_firestore_service.dart';
import 'compra_fornecedor_hive_store.dart';

class CompraFornecedorSyncService {
  CompraFornecedorSyncService._();

  /// Compras que ainda precisam de envio ou falharam na última tentativa.
  static bool precisaRetry(CompraFornecedor c) =>
      c.syncPendente || c.syncStatus == 'erro';

  /// Lista no Hive local (por loja) compras com [precisaRetry].
  static Future<List<CompraFornecedor>> listarPendentesOuErro(
    String lojaId,
  ) async {
    final box = await CompraFornecedorHiveStore.openBox(lojaId);
    if (box == null) return [];
    return box.values.where(precisaRetry).toList();
  }

  /// Retorna true se o documento foi gravado no Firestore.
  /// Falhas de rede/Firebase não rethrow — Hive permanece como verdade operacional.
  static Future<bool> sincronizar(CompraFornecedor compra) async {
    final lid = compra.lojaId.trim();
    if (lid.isEmpty) return false;
    try {
      await CompraFornecedorFirestoreService.upsertCompra(compra);
      return true;
    } catch (e, st) {
      debugPrint(
        '❌ [COMPRA-SYNC] Falha sync compra ${compra.id} (type=${e.runtimeType})',
      );
      if (e is FirebaseException) {
        debugPrint(
          '   [COMPRA-SYNC] Firebase code=${e.code} message=${e.message}',
        );
      }
      debugPrint('$st');
      return false;
    }
  }

  static Future<void> _persistirFlagsSync(
    CompraFornecedor compra,
    bool ok,
  ) async {
    final box = await CompraFornecedorHiveStore.openBox(compra.lojaId);
    if (box == null) return;
    await box.put(
      compra.id,
      compra.copyWith(syncPendente: !ok, syncStatus: ok ? 'ok' : 'erro'),
    );
  }

  /// Uma compra (snapshot ou id): lê o estado atual no Hive, envia com [sincronizar], persiste flags.
  /// Se já estiver ok (sem retry necessário), não chama rede e retorna true.
  static Future<bool> sincronizarUmaEAtualizarHive(CompraFornecedor compra) async {
    final box = await CompraFornecedorHiveStore.openBox(compra.lojaId);
    if (box == null) return false;
    final atual = box.get(compra.id) ?? compra;
    if (!precisaRetry(atual)) return true;
    final ok = await sincronizar(atual);
    await _persistirFlagsSync(atual, ok);
    return ok;
  }

  /// Por [compraId] na loja.
  static Future<bool> sincronizarPorIdEAtualizarHive({
    required String lojaId,
    required String compraId,
  }) async {
    final box = await CompraFornecedorHiveStore.openBox(lojaId);
    if (box == null) return false;
    final atual = box.get(compraId);
    if (atual == null) return false;
    if (!precisaRetry(atual)) return true;
    final ok = await sincronizar(atual);
    await _persistirFlagsSync(atual, ok);
    return ok;
  }

  /// Compras com [precisaRetry] em sequência. Com [fornecedorHiveKey], restringe a esse fornecedor.
  /// Sem o filtro, percorre toda a loja (comportamento anterior).
  static Future<({int sucesso, int falha})> sincronizarTodasPendentesOuErro(
    String lojaId, {
    int? fornecedorHiveKey,
  }) async {
    final box = await CompraFornecedorHiveStore.openBox(lojaId);
    if (box == null) return (sucesso: 0, falha: 0);
    final ids = box.values
        .where((c) {
          if (!precisaRetry(c)) return false;
          if (fornecedorHiveKey != null &&
              c.fornecedorHiveKey != fornecedorHiveKey) {
            return false;
          }
          return true;
        })
        .map((c) => c.id)
        .toList();
    var sucesso = 0;
    var falha = 0;
    for (final id in ids) {
      final atual = box.get(id);
      if (atual == null) continue;
      if (!precisaRetry(atual)) continue;
      final ok = await sincronizar(atual);
      await box.put(
        atual.id,
        atual.copyWith(syncPendente: !ok, syncStatus: ok ? 'ok' : 'erro'),
      );
      if (ok) {
        sucesso++;
      } else {
        falha++;
      }
    }
    return (sucesso: sucesso, falha: falha);
  }
}
