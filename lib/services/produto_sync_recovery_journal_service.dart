// Journal local de backup antes da reidentificação na recuperação assistida.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../models/produto.dart';
import 'produto_sync_recovery_mask_util.dart';
import 'produto_sync_recovery_models.dart';
import 'sync_queue_service.dart';

class ProdutoSyncRecoveryJournalService {
  ProdutoSyncRecoveryJournalService._();

  static const boxName = 'produto_sync_recovery_journal';

  static Future<Box> _openBox() async {
    if (Hive.isBoxOpen(boxName)) return Hive.box(boxName);
    return Hive.openBox(boxName);
  }

  static Future<RecoveryJournalEntry?> buscarPorRecoveryId(String recoveryId) async {
    final box = await _openBox();
    final map = _rawToMap(box.get(recoveryId));
    if (map == null) return null;
    return RecoveryJournalEntry.fromMap(map);
  }

  static Future<bool> jaConcluido({
    required int entityKey,
    required String lojaId,
  }) async {
    final box = await _openBox();
    for (final k in box.keys) {
      final map = _rawToMap(box.get(k));
      if (map == null) continue;
      final entry = RecoveryJournalEntry.fromMap(map);
      if (entry.entityKey == entityKey &&
          entry.lojaId == lojaId &&
          entry.fase == RecoveryJournalFase.concluido) {
        return true;
      }
    }
    return false;
  }

  static Future<RecoveryJournalEntry?> entradaAtivaParaEntity({
    required int entityKey,
    required String lojaId,
  }) async {
    RecoveryJournalEntry? melhor;
    for (final entry in await listarEntradas(lojaId: lojaId)) {
      if (entry.entityKey != entityKey) continue;
      if (entry.fase == RecoveryJournalFase.concluido) continue;
      if (melhor == null || entry.timestampMs > melhor.timestampMs) {
        melhor = entry;
      }
    }
    return melhor;
  }

  static Future<RecoveryJournalEntry> registrarAntesDeAlterar({
    required Produto produto,
    required String lojaId,
    required RecoveryProdutoClassificacao classificacao,
  }) async {
    final key = produto.key;
    if (key is! int) {
      throw StateError('entityKey Hive inválida');
    }

    final ativa = await entradaAtivaParaEntity(entityKey: key, lojaId: lojaId);
    if (ativa != null) {
      return ativa;
    }

    if (await jaConcluido(entityKey: key, lojaId: lojaId)) {
      throw StateError('Produto já processado neste journal');
    }

    String? estadoFila;
    final pending = await SyncQueueService.hasPendingProdutoSync(
      lojaId: lojaId,
      entityKey: key,
      includeDeadLetter: true,
    );
    if (pending) {
      final err = await SyncQueueService.lastProdutoSyncErrorForEntity(
        lojaId: lojaId,
        entityKey: key,
      );
      estadoFila = err ?? 'pendente';
    }

    final entry = RecoveryJournalEntry(
      recoveryId: const Uuid().v4(),
      entityKey: key,
      lojaId: lojaId,
      nomeMascarado: ProdutoSyncRecoveryMaskUtil.mascararNome(produto.nome),
      slugAnterior: produto.slug,
      idFirebaseAnterior: produto.idFirebase,
      sku: produto.sku,
      codigoBarras: produto.codigoBarras,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      classificacao: classificacao,
      estadoDaFila: estadoFila,
      fase: RecoveryJournalFase.prepared,
    );

    final box = await _openBox();
    await box.put(entry.recoveryId, jsonEncode(entry.toMap()));
    return entry;
  }

  static Future<RecoveryJournalEntry> atualizarFase({
    required String recoveryId,
    required RecoveryJournalFase fase,
    String? slugNovo,
    bool marcarIncompleto = false,
  }) async {
    final box = await _openBox();
    final map = _rawToMap(box.get(recoveryId));
    if (map == null) {
      throw StateError('Journal não encontrado');
    }
    final entry = RecoveryJournalEntry.fromMap(map);
    final atualizado = entry.copyWith(
      fase: marcarIncompleto
          ? RecoveryJournalFase.incompletoRequerConfirmacao
          : fase,
      slugNovo: slugNovo ?? entry.slugNovo,
      aplicado: fase == RecoveryJournalFase.concluido,
    );
    await box.put(recoveryId, jsonEncode(atualizado.toMap()));
    return atualizado;
  }

  static Future<void> marcarIncompleto(String recoveryId) async {
    await atualizarFase(
      recoveryId: recoveryId,
      fase: RecoveryJournalFase.incompletoRequerConfirmacao,
      marcarIncompleto: true,
    );
  }

  static Future<List<RecoveryJournalEntry>> listarEntradas({
    String? lojaId,
    bool apenasIncompletas = false,
  }) async {
    final box = await _openBox();
    final out = <RecoveryJournalEntry>[];
    for (final k in box.keys) {
      final map = _rawToMap(box.get(k));
      if (map == null) continue;
      final entry = RecoveryJournalEntry.fromMap(map);
      if (lojaId != null && entry.lojaId != lojaId) continue;
      if (apenasIncompletas && entry.fase == RecoveryJournalFase.concluido) {
        continue;
      }
      out.add(entry);
    }
    out.sort((a, b) => b.timestampMs.compareTo(a.timestampMs));
    return out;
  }

  static Future<RecoveryJournalIncompletoResumo> resumoIncompletos({
    String? lojaId,
  }) async {
    final incompletos =
        await listarEntradas(lojaId: lojaId, apenasIncompletas: true);
    final ativos = incompletos
        .where((e) => e.fase == RecoveryJournalFase.incompletoRequerConfirmacao)
        .toList();
    return RecoveryJournalIncompletoResumo(
      quantidade: ativos.length,
      mensagemSanitizada: ativos.isEmpty
          ? ''
          : '${ativos.length} recuperação(ões) pendente(s) — retome manualmente',
    );
  }

  static Map<String, dynamic>? _rawToMap(dynamic raw) {
    if (raw == null) return null;
    if (raw is String) {
      try {
        return Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } catch (_) {
        return null;
      }
    }
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  @visibleForTesting
  static Future<void> resetForTests() async {
    final box = await _openBox();
    await box.clear();
  }
}
