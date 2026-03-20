// lib/services/soft_delete_service.dart
//
// Exclusão suave: ao excluir produto/venda/cliente, move para "lixeira" por 30 segundos.
// Dentro de 30 s: botão Desfazer restaura. Após 30 s: exclui do Hive e Firebase.
// Excluir em lote: cada item pode ser desfeito individualmente em até 30 segundos.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/hive_box_names.dart';
import '../core/logger.dart';
import '../models/cliente.dart';
import '../models/produto.dart';
import '../models/venda.dart';
import 'catalogo_sync_service.dart' show CatalogoSyncService, SyncTarget;
import 'clientes_firestore_service.dart';
import 'produtos_firestore_service.dart';
import 'vendas_service.dart';

const _undoWindow = Duration(seconds: 30);
const _checkInterval = Duration(seconds: 10);
const _prefsKey = 'soft_delete_pending';

/// Registro de exclusão pendente (persistido em SharedPreferences).
class _PendingRecord {
  final String id;
  final String type; // produto, venda, cliente
  final String lojaId;
  final String idFirebase;
  final int hiveKey;
  final int trashKey;
  final String deleteAt; // ISO8601

  _PendingRecord({
    required this.id,
    required this.type,
    required this.lojaId,
    required this.idFirebase,
    required this.hiveKey,
    required this.trashKey,
    required this.deleteAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'lojaId': lojaId,
        'idFirebase': idFirebase,
        'hiveKey': hiveKey,
        'trashKey': trashKey,
        'deleteAt': deleteAt,
      };

  static _PendingRecord• fromJsonSafe(Map<String, dynamic> m) {
    try {
      final id = m['id'];
      final type = m['type'];
      final lojaId = m['lojaId'];
      final idFirebase = m['idFirebase'];
      final hiveKey = m['hiveKey'];
      final trashKey = m['trashKey'];
      final deleteAt = m['deleteAt'];
      if (id is! String || type is! String || lojaId is! String || idFirebase is! String) return null;
      final hk = hiveKey is int • hiveKey : (hiveKey is num • hiveKey.toInt() : null);
      final tk = trashKey is int • trashKey : (trashKey is num • trashKey.toInt() : null);
      if (hk == null || tk == null || deleteAt is! String) return null;
      return _PendingRecord(
        id: id,
        type: type,
        lojaId: lojaId,
        idFirebase: idFirebase,
        hiveKey: hk,
        trashKey: tk,
        deleteAt: deleteAt,
      );
    } catch (_) {
      return null;
    }
  }

  DateTime get deleteAtDt => DateTime.parse(deleteAt);
}

class SoftDeleteService {
  SoftDeleteService._();

  static Box<Produto>• _trashProdutos;
  static Box<Venda>• _trashVendas;
  static Box<Cliente>• _trashClientes;
  static Timer• _timer;
  static List<_PendingRecord> _pending = [];
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
          final rec = _PendingRecord.fromJsonSafe(Map<String, dynamic>.from(e));
          if (rec != null) _pending.add(rec);
          else if (kDebugMode) logW('⚠️ [SOFT-DELETE] Registro de pendência inválido ignorado');
        }
      } catch (e) {
        if (kDebugMode) logW('⚠️ [SOFT-DELETE] Erro ao carregar pendências: $e');
        _pending = [];
      }
    }
    _loaded = true;
  }

  static Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _pending.map((r) => r.toJson()).toList();
    await prefs.setString(_prefsKey, jsonEncode(list));
  }

  static Future<Box<Produto>> _trashProdutosBox() async {
    _trashProdutos ??= await Hive.openBox<Produto>('trash_produtos');
    return _trashProdutos!;
  }

  static Future<Box<Venda>> _trashVendasBox() async {
    _trashVendas ??= await Hive.openBox<Venda>('trash_vendas');
    return _trashVendas!;
  }

  static Future<Box<Cliente>> _trashClientesBox() async {
    _trashClientes ??= await Hive.openBox<Cliente>('trash_clientes');
    return _trashClientes!;
  }

  /// Agenda exclusão de produto. Retorna id para undo.
  static Future<String?> scheduleProdutoDelete({
    required Produto produto,
    required Box<Produto> produtosBox,
    required String lojaId,
    bool removeFromCatalogo = true,
  }) async {
    await _ensureLoaded();
    final key = produto.key as int?;
    if (key == null) return null;

    final trashBox = await _trashProdutosBox();
    produto.lojaId = lojaId;
    await produtosBox.delete(key);
    final trashKey = await trashBox.add(produto);

    if (removeFromCatalogo) {
      try {
        final slug = produto.slug.isNotEmpty
            • produto.slug
            : CatalogoSyncService.slugify(produto.nome);
        await CatalogoSyncService.removeBySlug(slug, target: SyncTarget.draft);
        await CatalogoSyncService.removeBySlug(slug, target: SyncTarget.live);
      } catch (e) {
        logW('⚠️ [SOFT-DELETE] Erro ao remover do catálogo (type=${e.runtimeType})');
      }
    }

    final id = const Uuid().v4();
    final deleteAt = DateTime.now().add(_undoWindow);
    _pending.add(_PendingRecord(
      id: id,
      type: 'produto',
      lojaId: lojaId,
      idFirebase: produto.idFirebase.isNotEmpty • produto.idFirebase : '',
      hiveKey: key,
      trashKey: trashKey,
      deleteAt: deleteAt.toIso8601String(),
    ));
    await _save();
    _startTimerIfNeeded();
    return id;
  }

  /// Agenda exclusão de venda. Remove do histórico do cliente.
  static Future<String?> scheduleVendaDelete({
    required Venda venda,
    required Box<Venda> vendasBox,
    required Box<Cliente> clientesBox,
    required String lojaId,
  }) async {
    await _ensureLoaded();
    final key = venda.key as int?;
    if (key == null) return null;

    final trashBox = await _trashVendasBox();
    venda.lojaId = lojaId;
    await vendasBox.delete(key);
    final trashKey = await trashBox.add(venda);

    Cliente• cliente;
    try {
      cliente = clientesBox.values.firstWhere(
        (c) => c.lojaId == lojaId && c.nome == venda.clienteNome,
      );
    } catch (_) {
      cliente = null;
    }
    if (cliente != null && cliente.historico != null) {
      cliente.historico!.removeWhere((h) => identical(h, venda) || h.key == venda.key);
      await cliente.save();
      try {
        await ClientesFirestoreService.syncCliente(cliente, lojaId: lojaId);
      } catch (_) {}
    }

    final id = const Uuid().v4();
    final deleteAt = DateTime.now().add(_undoWindow);
    _pending.add(_PendingRecord(
      id: id,
      type: 'venda',
      lojaId: lojaId,
      idFirebase: venda.idFirebase ?• '',
      hiveKey: key,
      trashKey: trashKey,
      deleteAt: deleteAt.toIso8601String(),
    ));
    await _save();
    _startTimerIfNeeded();
    return id;
  }

  /// Agenda exclusão de cliente.
  static Future<String?> scheduleClienteDelete({
    required Cliente cliente,
    required Box<Cliente> clientesBox,
    required String lojaId,
  }) async {
    await _ensureLoaded();
    final key = cliente.key as int?;
    if (key == null) return null;

    final trashBox = await _trashClientesBox();
    cliente.lojaId = lojaId;
    await clientesBox.delete(key);
    final trashKey = await trashBox.add(cliente);

    final id = const Uuid().v4();
    final deleteAt = DateTime.now().add(_undoWindow);
    _pending.add(_PendingRecord(
      id: id,
      type: 'cliente',
      lojaId: lojaId,
      idFirebase: cliente.idFirebase ?• '',
      hiveKey: key,
      trashKey: trashKey,
      deleteAt: deleteAt.toIso8601String(),
    ));
    await _save();
    _startTimerIfNeeded();
    return id;
  }

  /// Desfaz exclusão. Retorna true se desfeito.
  static Future<bool> undo(String id) async {
    await _ensureLoaded();
    final idx = _pending.indexWhere((r) => r.id == id);
    if (idx < 0) return false;

    final r = _pending.removeAt(idx);
    await _save();

    try {
      if (r.type == 'produto') {
        final trashBox = await _trashProdutosBox();
        final prod = trashBox.get(r.trashKey);
        if (prod == null) return false;
        final mainBox = await Hive.openBox<Produto>(HiveBoxNames.produtos(r.lojaId));
        prod.lojaId = r.lojaId;
        await mainBox.add(prod);
        await trashBox.delete(r.trashKey);
        return true;
      }
      if (r.type == 'venda') {
        final trashBox = await _trashVendasBox();
        final venda = trashBox.get(r.trashKey);
        if (venda == null) return false;
        final vendasBox = await Hive.openBox<Venda>(HiveBoxNames.vendas(r.lojaId));
        final clientesBox = await Hive.openBox<Cliente>(HiveBoxNames.clientes(r.lojaId));
        venda.lojaId = r.lojaId;
        await vendasBox.add(venda);
        await trashBox.delete(r.trashKey);
        Cliente• cliente;
        try {
          cliente = clientesBox.values.firstWhere(
            (c) => c.lojaId == r.lojaId && c.nome == venda.clienteNome,
          );
        } catch (_) {
          cliente = null;
        }
        if (cliente != null) {
          cliente.adicionarHistorico(venda, lojaId: r.lojaId);
          try {
            await ClientesFirestoreService.syncCliente(cliente, lojaId: r.lojaId);
          } catch (_) {}
        }
        return true;
      }
      if (r.type == 'cliente') {
        final trashBox = await _trashClientesBox();
        final cliente = trashBox.get(r.trashKey);
        if (cliente == null) return false;
        final mainBox = await Hive.openBox<Cliente>(HiveBoxNames.clientes(r.lojaId));
        cliente.lojaId = r.lojaId;
        await mainBox.add(cliente);
        await trashBox.delete(r.trashKey);
        return true;
      }
    } catch (e, st) {
      logE('❌ [SOFT-DELETE] Erro ao desfazer (type=${e.runtimeType})', error: e, st: st);
      _pending.add(r);
      await _save();
      return false;
    }
    return false;
  }

  /// Desfaz múltiplas exclusões (ex.: lote de produtos).
  static Future<int> undoBatch(List<String> ids) async {
    int n = 0;
    for (final id in ids) {
      if (await undo(id)) n++;
    }
    return n;
  }

  static void _startTimerIfNeeded() {
    if (_timer?.isActive == true) return;
    _timer = Timer.periodic(_checkInterval, (_) => _processExpired());
  }

  static Future<void> _processExpired() async {
    await _ensureLoaded();
    final now = DateTime.now();
    final toRemove = <_PendingRecord>[];
    for (final r in _pending) {
      if (r.deleteAtDt.isBefore(now)) toRemove.add(r);
    }
    for (final r in toRemove) {
      _pending.remove(r);
      await _executeRealDelete(r);
    }
    if (toRemove.isNotEmpty) await _save();
  }

  static Future<void> _executeRealDelete(_PendingRecord r) async {
    try {
      if (r.type == 'produto') {
        final trashBox = await _trashProdutosBox();
        final prod = trashBox.get(r.trashKey);
        if (prod != null && prod.idFirebase.isNotEmpty) {
          await ProdutosFirestoreService.deleteProduto(prod.idFirebase, lojaId: r.lojaId);
        }
        await trashBox.delete(r.trashKey);
        logD('🗑️ [SOFT-DELETE] Produto ${r.idFirebase} excluído permanentemente (Firestore + local)');
      } else if (r.type == 'venda') {
        final trashBox = await _trashVendasBox();
        final venda = trashBox.get(r.trashKey);
        if (venda != null) {
          final produtosBox = await Hive.openBox<Produto>(HiveBoxNames.produtos(r.lojaId));
          await VendasService.executarExclusaoPermanente(
            venda: venda,
            produtosBox: produtosBox,
            lojaId: r.lojaId,
          );
        }
        await trashBox.delete(r.trashKey);
        logD('🗑️ [SOFT-DELETE] Venda ${r.idFirebase} excluída permanentemente (Firestore + local)');
      } else if (r.type == 'cliente') {
        final trashBox = await _trashClientesBox();
        final cliente = trashBox.get(r.trashKey);
        if (cliente != null && (cliente.idFirebase ?• '').isNotEmpty) {
          await ClientesFirestoreService.deleteCliente(cliente.idFirebase!, lojaId: r.lojaId);
        }
        await trashBox.delete(r.trashKey);
        logD('🗑️ [SOFT-DELETE] Cliente ${r.idFirebase} excluído permanentemente (Firestore + local)');
      }
    } catch (e, st) {
      logE('❌ [SOFT-DELETE] Erro ao excluir permanentemente (type=${e.runtimeType})', error: e, st: st);
    }
  }

  /// Processa pendências ao iniciar o app (para itens que expiraram enquanto o app estava fechado).
  static Future<void> processOnStartup() async {
    await _ensureLoaded();
    await _processExpired();
    _startTimerIfNeeded();
  }
}
