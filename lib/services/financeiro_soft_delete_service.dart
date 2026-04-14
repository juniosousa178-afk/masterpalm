// lib/services/financeiro_soft_delete_service.dart
//
// Exclusão com janela de desfazer (30s) para lançamentos, gastos fixos e controle por fornecedor.
// Remove da nuvem na hora (evita reimportação) e restaura no desfazer via upsert.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/logger.dart';
import '../models/gasto_fixo_mensal.dart';
import '../models/lancamento_financeiro.dart';
import 'controle_compras_fornecedor_firestore_service.dart';
import 'controle_compras_fornecedor_service.dart';
import 'financeiro_firestore_service.dart';
import 'financeiro_hive_store.dart';

const _undoWindow = Duration(seconds: 30);
const _checkInterval = Duration(seconds: 10);
const _prefsKey = 'financeiro_soft_delete_pending';

class _Pending {
  final String id;
  final String type;
  final String lojaId;
  final String entityId;
  final int trashKey;
  final String deleteAt;

  _Pending({
    required this.id,
    required this.type,
    required this.lojaId,
    required this.entityId,
    required this.trashKey,
    required this.deleteAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'lojaId': lojaId,
        'entityId': entityId,
        'trashKey': trashKey,
        'deleteAt': deleteAt,
      };

  static _Pending? fromJsonSafe(Map<String, dynamic> m) {
    try {
      final id = m['id'];
      final type = m['type'];
      final lojaId = m['lojaId'];
      final entityId = m['entityId'];
      final trashKey = m['trashKey'];
      final deleteAt = m['deleteAt'];
      if (id is! String ||
          type is! String ||
          lojaId is! String ||
          entityId is! String ||
          deleteAt is! String) {
        return null;
      }
      final tk = trashKey is int ? trashKey : (trashKey is num ? trashKey.toInt() : null);
      if (tk == null) return null;
      return _Pending(
        id: id,
        type: type,
        lojaId: lojaId,
        entityId: entityId,
        trashKey: tk,
        deleteAt: deleteAt,
      );
    } catch (_) {
      return null;
    }
  }

  DateTime get deleteAtDt => DateTime.parse(deleteAt);
}

class FinanceiroSoftDeleteService {
  FinanceiroSoftDeleteService._();

  static Box<LancamentoFinanceiro>? _trashLanc;
  static Box<GastoFixoMensal>? _trashGasto;
  static Box<String>? _trashControleJson;
  static Timer? _timer;
  static List<_Pending> _pending = [];
  static bool _loaded = false;

  static Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        _pending = [];
        for (final e in list) {
          if (e is! Map) continue;
          final rec = _Pending.fromJsonSafe(Map<String, dynamic>.from(e));
          if (rec != null) {
            _pending.add(rec);
          } else if (kDebugMode) {
            logW('[FIN-SOFT-DEL] Registro invalido ignorado');
          }
        }
      } catch (e) {
        if (kDebugMode) logW('[FIN-SOFT-DEL] Erro ao carregar pendencias: $e');
        _pending = [];
      }
    }
    _loaded = true;
  }

  static Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(_pending.map((r) => r.toJson()).toList()),
    );
  }

  static Future<Box<LancamentoFinanceiro>> _trashLancBox() async {
    _trashLanc ??= await Hive.openBox<LancamentoFinanceiro>('trash_fin_lancamentos');
    return _trashLanc!;
  }

  static Future<Box<GastoFixoMensal>> _trashGastoBox() async {
    _trashGasto ??= await Hive.openBox<GastoFixoMensal>('trash_fin_gastos_fixos');
    return _trashGasto!;
  }

  static Future<Box<String>> _trashControleBox() async {
    _trashControleJson ??= await Hive.openBox<String>('trash_fin_controle_compra_json');
    return _trashControleJson!;
  }

  static void _startTimerIfNeeded() {
    if (_timer?.isActive == true) return;
    _timer = Timer.periodic(_checkInterval, (_) => _processExpired());
  }

  static Future<void> _processExpired() async {
    await _ensureLoaded();
    final now = DateTime.now();
    final toRemove = _pending.where((r) => r.deleteAtDt.isBefore(now)).toList();
    for (final r in toRemove) {
      try {
        await _executePermanent(r);
        _pending.remove(r);
      } catch (e, st) {
        logE(
          '[FIN-SOFT-DEL] exclusao definitiva falhou id=${r.id} type=${r.type}',
          error: e,
          st: st,
        );
      }
    }
    if (toRemove.isNotEmpty) await _save();
  }

  static Future<void> _executePermanent(_Pending r) async {
    if (r.type == 'lancamento_financeiro') {
      final trash = await _trashLancBox();
      await trash.delete(r.trashKey);
    } else if (r.type == 'gasto_fixo_mensal') {
      final trash = await _trashGastoBox();
      await trash.delete(r.trashKey);
    } else if (r.type == 'controle_compra_fornecedor') {
      final trash = await _trashControleBox();
      await trash.delete(r.trashKey);
    }
  }

  /// Processa pendências após cold start (ex.: app fechado na janela de desfazer).
  static Future<void> processOnStartup() async {
    await _ensureLoaded();
    await _processExpired();
    _startTimerIfNeeded();
  }

  static Future<String?> scheduleLancamentoDelete({
    required LancamentoFinanceiro l,
    required Box<LancamentoFinanceiro> box,
    required String lojaId,
  }) async {
    await _ensureLoaded();
    final id = l.id;
    if (id.isEmpty) return null;
    final lid = lojaId.trim();
    if (lid.isEmpty) return null;

    final existing = box.get(id);
    if (existing == null) return null;

    await FinanceiroFirestoreService.deleteLancamento(lojaId: lid, id: id);
    await box.delete(id);

    final trash = await _trashLancBox();
    existing.lojaId = lid;
    final trashKey = await trash.add(existing);

    final pendId = const Uuid().v4();
    _pending.add(_Pending(
      id: pendId,
      type: 'lancamento_financeiro',
      lojaId: lid,
      entityId: id,
      trashKey: trashKey,
      deleteAt: DateTime.now().add(_undoWindow).toIso8601String(),
    ));
    await _save();
    _startTimerIfNeeded();
    return pendId;
  }

  static Future<String?> scheduleGastoFixoDelete({
    required GastoFixoMensal g,
    required Box<GastoFixoMensal> box,
    required String lojaId,
  }) async {
    await _ensureLoaded();
    final id = g.id;
    if (id.isEmpty) return null;
    final lid = lojaId.trim();
    if (lid.isEmpty) return null;

    final existing = box.get(id);
    if (existing == null) return null;

    await FinanceiroFirestoreService.deleteGastoFixo(lojaId: lid, id: id);
    await box.delete(id);

    final trash = await _trashGastoBox();
    existing.lojaId = lid;
    final trashKey = await trash.add(existing);

    final pendId = const Uuid().v4();
    _pending.add(_Pending(
      id: pendId,
      type: 'gasto_fixo_mensal',
      lojaId: lid,
      entityId: id,
      trashKey: trashKey,
      deleteAt: DateTime.now().add(_undoWindow).toIso8601String(),
    ));
    await _save();
    _startTimerIfNeeded();
    return pendId;
  }

  static Future<String?> scheduleControleCompraDelete({
    required LinhaControleCompraFornecedor linha,
    required String lojaId,
  }) async {
    await _ensureLoaded();
    final lid = lojaId.trim();
    if (lid.isEmpty || linha.id.isEmpty) return null;

    await ControleComprasFornecedorFirestoreService.deleteLinha(lid, linha.id);
    await ControleComprasFornecedorService.removerApenasHive(lid, linha.id);

    final trash = await _trashControleBox();
    final trashKey = await trash.add(jsonEncode(linha.toJson()));

    final pendId = const Uuid().v4();
    _pending.add(_Pending(
      id: pendId,
      type: 'controle_compra_fornecedor',
      lojaId: lid,
      entityId: linha.id,
      trashKey: trashKey,
      deleteAt: DateTime.now().add(_undoWindow).toIso8601String(),
    ));
    await _save();
    _startTimerIfNeeded();
    return pendId;
  }

  static Future<bool> undo(String id) async {
    await _ensureLoaded();
    final idx = _pending.indexWhere((r) => r.id == id);
    if (idx < 0) return false;
    final r = _pending[idx];

    try {
      if (r.type == 'lancamento_financeiro') {
        final trash = await _trashLancBox();
        final obj = trash.get(r.trashKey);
        if (obj == null) {
          logW('[FIN-SOFT-DEL] undo lancamento ausente trashKey=${r.trashKey}');
          return false;
        }
        final box = await FinanceiroHiveStore.openLancamentosBox(r.lojaId);
        if (box == null) return false;
        obj.lojaId = r.lojaId;
        await trash.delete(r.trashKey);
        await box.put(r.entityId, obj);
        await FinanceiroFirestoreService.upsertLancamento(obj);
        _pending.removeAt(idx);
        await _save();
        return true;
      }
      if (r.type == 'gasto_fixo_mensal') {
        final trash = await _trashGastoBox();
        final obj = trash.get(r.trashKey);
        if (obj == null) {
          logW('[FIN-SOFT-DEL] undo gasto fixo ausente trashKey=${r.trashKey}');
          return false;
        }
        final box = await FinanceiroHiveStore.openGastosFixosBox(r.lojaId);
        if (box == null) return false;
        obj.lojaId = r.lojaId;
        await trash.delete(r.trashKey);
        await box.put(r.entityId, obj);
        await FinanceiroFirestoreService.upsertGastoFixo(obj);
        _pending.removeAt(idx);
        await _save();
        return true;
      }
      if (r.type == 'controle_compra_fornecedor') {
        final trash = await _trashControleBox();
        final raw = trash.get(r.trashKey);
        if (raw == null || raw.isEmpty) {
          logW('[FIN-SOFT-DEL] undo controle ausente trashKey=${r.trashKey}');
          return false;
        }
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final linha = LinhaControleCompraFornecedor.fromJson(map);
        await trash.delete(r.trashKey);
        await ControleComprasFornecedorService.reinserirLinha(r.lojaId, linha);
        _pending.removeAt(idx);
        await _save();
        return true;
      }
    } catch (e, st) {
      logE('[FIN-SOFT-DEL] undo erro (type=${e.runtimeType})', error: e, st: st);
      return false;
    }
    return false;
  }
}
