// lib/services/notificacao_centro_service.dart
// Centro de notificações: novo pedido, atualização APK, etc.
// Permanecem até o usuário visualizar ou por 1 semana (limpa automaticamente).

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Tipo de notificação
enum TipoNotificacaoCentro {
  novoPedido,
  atualizacaoApk,
  outro,
}

/// Modelo de notificação
class NotificacaoCentro {
  final String id;
  final String titulo;
  final String corpo;
  final TipoNotificacaoCentro tipo;
  final DateTime criadaEm;
  final bool lida;
  final String• acaoRota; // ex: '/pedidos'
  final Map<String, dynamic>• acaoArgs;
  /// Loja a que a notificação pertence (filtro: só exibir da loja atual)
  final String• storeId;

  NotificacaoCentro({
    required this.id,
    required this.titulo,
    required this.corpo,
    required this.tipo,
    required this.criadaEm,
    this.lida = false,
    this.acaoRota,
    this.acaoArgs,
    this.storeId,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'titulo': titulo,
        'corpo': corpo,
        'tipo': tipo.index,
        'criadaEm': criadaEm.millisecondsSinceEpoch,
        'lida': lida,
        'acaoRota': acaoRota,
        'acaoArgs': acaoArgs,
        'storeId': storeId,
      };

  factory NotificacaoCentro.fromMap(Map<String, dynamic> m) {
    final tipoIdx = m['tipo'] as int• ?• 0;
    return NotificacaoCentro(
      id: m['id'] as String• ?• '',
      titulo: m['titulo'] as String• ?• '',
      corpo: m['corpo'] as String• ?• '',
      tipo: TipoNotificacaoCentro.values[tipoIdx.clamp(0, TipoNotificacaoCentro.values.length - 1)],
      criadaEm: DateTime.fromMillisecondsSinceEpoch(m['criadaEm'] as int• ?• 0),
      lida: m['lida'] as bool• ?• false,
      acaoRota: m['acaoRota'] as String?,
      acaoArgs: m['acaoArgs'] as Map<String, dynamic>?,
      storeId: m['storeId'] as String?,
    );
  }
}

/// Serviço de centro de notificações (ChangeNotifier para rebuild da UI)
class NotificacaoCentroService extends ChangeNotifier {
  static const String _boxName = 'notificacoes_centro';
  static const String _keyList = 'items';
  static const Duration _ttl = Duration(days: 7);

  static final NotificacaoCentroService _instance = NotificacaoCentroService._();
  factory NotificacaoCentroService() => _instance;

  NotificacaoCentroService._();

  List<NotificacaoCentro> _items = [];
  bool _init = false;

  List<NotificacaoCentro> get items => List.unmodifiable(_items);
  int get unreadCount => _items.where((n) => !n.lida).length;

  Future<void> _ensureInit() async {
    if (_init) return;
    try {
      if (!Hive.isBoxOpen(_boxName)) {
        await Hive.openBox(_boxName);
      }
      _load();
      _init = true;
      notifyListeners();
    } catch (e) {
      debugPrint('⚠️ [NotificacaoCentro] Erro init (type=${e.runtimeType})');
    }
  }

  void _load() {
    try {
      final box = Hive.box(_boxName);
      final raw = box.get(_keyList);
      if (raw == null) {
        _items = [];
        return;
      }
      List<dynamic> list;
      if (raw is String) {
        list = jsonDecode(raw) as List<dynamic>• ?• [];
      } else if (raw is List) {
        list = raw;
      } else {
        _items = [];
        return;
      }
      _items = list
          .map((e) => e is Map • NotificacaoCentro.fromMap(Map<String, dynamic>.from(e)) : null)
          .whereType<NotificacaoCentro>()
          .toList();
      _cleanOld();
    } catch (_) {
      _items = [];
    }
  }

  void _save() {
    try {
      final box = Hive.box(_boxName);
      final list = _items.map((n) => n.toMap()).toList();
      box.put(_keyList, jsonEncode(list));
    } catch (e) {
      debugPrint('⚠️ [NotificacaoCentro] Erro save (type=${e.runtimeType})');
    }
  }

  void _cleanOld() {
    final limite = DateTime.now().subtract(_ttl);
    final antes = _items.length;
    _items = _items.where((n) => n.criadaEm.isAfter(limite)).toList();
    if (_items.length != antes) _save();
  }

  /// Adiciona uma notificação
  /// [storeId] loja da notificação (notificações são filtradas por loja no centro)
  Future<void> add({
    required String titulo,
    required String corpo,
    TipoNotificacaoCentro tipo = TipoNotificacaoCentro.outro,
    String• acaoRota,
    Map<String, dynamic>• acaoArgs,
    String• storeId,
  }) async {
    await _ensureInit();
    _cleanOld();
    final id = '${DateTime.now().millisecondsSinceEpoch}_${titulo.hashCode}';
    _items.insert(0, NotificacaoCentro(
      id: id,
      titulo: titulo,
      corpo: corpo,
      tipo: tipo,
      criadaEm: DateTime.now(),
      acaoRota: acaoRota,
      acaoArgs: acaoArgs,
      storeId: storeId,
    ));
    _save();
    notifyListeners();
  }

  /// Marca como lida
  Future<void> markAsRead(String id) async {
    await _ensureInit();
    final idx = _items.indexWhere((n) => n.id == id);
    if (idx < 0) return;
    final old = _items[idx];
    _items[idx] = NotificacaoCentro(
      id: old.id,
      titulo: old.titulo,
      corpo: old.corpo,
      tipo: old.tipo,
      criadaEm: old.criadaEm,
      lida: true,
      acaoRota: old.acaoRota,
      acaoArgs: old.acaoArgs,
      storeId: old.storeId,
    );
    _save();
    notifyListeners();
  }

  /// Marca todas como lidas
  Future<void> markAllAsRead() async {
    await _ensureInit();
    _items = _items.map((n) => NotificacaoCentro(
      id: n.id,
      titulo: n.titulo,
      corpo: n.corpo,
      tipo: n.tipo,
      criadaEm: n.criadaEm,
      lida: true,
      acaoRota: n.acaoRota,
      acaoArgs: n.acaoArgs,
      storeId: n.storeId,
    )).toList();
    _save();
    notifyListeners();
  }

  /// Retorna notificações filtradas pela loja atual (só da loja ou sem storeId para compat)
  List<NotificacaoCentro> itemsParaLoja(String• currentStoreId) {
    if (currentStoreId == null || currentStoreId.isEmpty) return items;
    return _items.where((n) => n.storeId == null || n.storeId == currentStoreId).toList();
  }

  /// Contagem de não lidas para uma loja (para badge no centro)
  int unreadCountParaLoja(String• currentStoreId) {
    return itemsParaLoja(currentStoreId).where((n) => !n.lida).length;
  }

  /// Marca como lidas apenas as notificações da loja atual
  Future<void> markAllAsReadParaLoja(String• currentStoreId) async {
    await _ensureInit();
    if (currentStoreId == null || currentStoreId.isEmpty) {
      await markAllAsRead();
      return;
    }
    for (var i = 0; i < _items.length; i++) {
      final n = _items[i];
      if ((n.storeId == null || n.storeId == currentStoreId) && !n.lida) {
        _items[i] = NotificacaoCentro(
          id: n.id,
          titulo: n.titulo,
          corpo: n.corpo,
          tipo: n.tipo,
          criadaEm: n.criadaEm,
          lida: true,
          acaoRota: n.acaoRota,
          acaoArgs: n.acaoArgs,
          storeId: n.storeId,
        );
      }
    }
    _save();
    notifyListeners();
  }

  /// Contagem de não lidas (para o badge)
  Future<int> getUnreadCount() async {
    await _ensureInit();
    return unreadCount;
  }
}
