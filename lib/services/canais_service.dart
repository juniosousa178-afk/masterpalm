// lib/services/canais_service.dart
// Serviço seguro para gerenciar canais de comunicação (WhatsApp, Instagram, etc.)
// Separa dados públicos (exibidos no catálogo) de dados privados (tokens, números)

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/logger.dart';

/// Modelo de canal público (exibido no catálogo)
class CanalPublico {
  final String id;
  final String nome;
  final String tipo; // 'whatsapp', 'instagram', 'messenger', 'telegram'
  final String? iconeUrl;
  final bool ativo;

  CanalPublico({
    required this.id,
    required this.nome,
    required this.tipo,
    this.iconeUrl,
    this.ativo = true,
  });

  factory CanalPublico.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return CanalPublico(
      id: doc.id,
      nome: data['nome']?.toString() ?? '',
      tipo: data['tipo']?.toString() ?? 'whatsapp',
      iconeUrl: data['iconeUrl']?.toString(),
      ativo: data['ativo'] == true,
    );
  }

  Map<String, dynamic> toMap() => {
        'nome': nome,
        'tipo': tipo,
        'iconeUrl': iconeUrl,
        'ativo': ativo,
      };
}

/// Modelo de canal privado (admin only - contém dados sensíveis)
class CanalPrivado {
  final String id;
  final String tipo;
  final String? numero; // WhatsApp number
  final String? token; // API token
  final String? webhookUrl;
  final Map<String, dynamic>? config;

  CanalPrivado({
    required this.id,
    required this.tipo,
    this.numero,
    this.token,
    this.webhookUrl,
    this.config,
  });

  factory CanalPrivado.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return CanalPrivado(
      id: doc.id,
      tipo: data['tipo']?.toString() ?? 'whatsapp',
      numero: data['numero']?.toString(),
      token: data['token']?.toString(),
      webhookUrl: data['webhookUrl']?.toString(),
      config: data['config'] is Map ? Map<String, dynamic>.from(data['config']) : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'tipo': tipo,
        if (numero != null) 'numero': numero,
        if (token != null) 'token': token,
        if (webhookUrl != null) 'webhookUrl': webhookUrl,
        if (config != null) 'config': config,
      };
}

class CanaisService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Flags para evitar spam de logs
  static bool _publicPermissionDeniedLogged = false;
  static bool _privatePermissionDeniedLogged = false;

  // ========== CANAIS PÚBLICOS (Catálogo) ==========

  /// Lista canais públicos ativos (para exibir no catálogo)
  /// Retorna stream vazio se não tiver permissão
  Stream<List<CanalPublico>> listarCanaisPublicos(String lojaId) {
    final controller = StreamController<List<CanalPublico>>();
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? subscription;

    void startListening() {
      subscription = _firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('canais_publicos')
          .where('ativo', isEqualTo: true)
          .limit(20)
          .snapshots()
          .listen(
        (snapshot) {
          _publicPermissionDeniedLogged = false;
          final canais = snapshot.docs
              .map((doc) => CanalPublico.fromFirestore(doc))
              .toList();
          controller.add(canais);
        },
        onError: (error) {
          if (error is FirebaseException && error.code == 'permission-denied') {
            if (!_publicPermissionDeniedLogged) {
              _publicPermissionDeniedLogged = true;
              logW('⚠️ [CanaisService] Sem permissão para canais_publicos - retornando vazio');
            }
            controller.add([]);
            subscription?.cancel();
          } else {
            logE('❌ [CanaisService] Erro ao listar canais públicos (type=${error.runtimeType})', error: error);
            controller.add([]);
          }
        },
        cancelOnError: false,
      );
    }

    controller.onListen = startListening;
    controller.onCancel = () => subscription?.cancel();

    return controller.stream.asBroadcastStream();
  }

  /// Busca canal público por tipo (ex: 'whatsapp')
  Future<CanalPublico?> buscarCanalPublico(String lojaId, String tipo) async {
    try {
      final snapshot = await _firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('canais_publicos')
          .where('tipo', isEqualTo: tipo)
          .where('ativo', isEqualTo: true)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) return null;
      return CanalPublico.fromFirestore(snapshot.docs.first);
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        logW('⚠️ [CanaisService] Sem permissão para buscar canal público');
        return null;
      }
      rethrow;
    }
  }

  // ========== CANAIS PRIVADOS (Admin) ==========

  /// Lista canais privados (admin only)
  /// Retorna stream vazio se não tiver permissão
  Stream<List<CanalPrivado>> listarCanaisPrivados(String lojaId) {
    final controller = StreamController<List<CanalPrivado>>();
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? subscription;

    void startListening() {
      subscription = _firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('canais')
          .limit(20)
          .snapshots()
          .listen(
        (snapshot) {
          _privatePermissionDeniedLogged = false;
          final canais = snapshot.docs
              .map((doc) => CanalPrivado.fromFirestore(doc))
              .toList();
          controller.add(canais);
        },
        onError: (error) {
          if (error is FirebaseException && error.code == 'permission-denied') {
            if (!_privatePermissionDeniedLogged) {
              _privatePermissionDeniedLogged = true;
              logW('⚠️ [CanaisService] Sem permissão para canais privados (admin only)');
            }
            controller.add([]);
            subscription?.cancel();
          } else {
            logE('❌ [CanaisService] Erro ao listar canais privados (type=${error.runtimeType})', error: error);
            controller.add([]);
          }
        },
        cancelOnError: false,
      );
    }

    controller.onListen = startListening;
    controller.onCancel = () => subscription?.cancel();

    return controller.stream.asBroadcastStream();
  }

  /// Busca canal privado por tipo (admin only)
  Future<CanalPrivado?> buscarCanalPrivado(String lojaId, String tipo) async {
    try {
      final snapshot = await _firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('canais')
          .doc(tipo)
          .get();

      if (!snapshot.exists) return null;
      return CanalPrivado.fromFirestore(snapshot);
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        logW('⚠️ [CanaisService] Sem permissão para buscar canal privado');
        return null;
      }
      rethrow;
    }
  }

  // ========== OPERAÇÕES DE ESCRITA (Admin) ==========

  /// Salva canal público (exibido no catálogo)
  Future<bool> salvarCanalPublico(String lojaId, CanalPublico canal) async {
    try {
      await _firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('canais_publicos')
          .doc(canal.id.isNotEmpty ? canal.id : canal.tipo)
          .set(canal.toMap(), SetOptions(merge: true));

      logD('✅ [CanaisService] Canal público salvo: ${canal.tipo}');
      return true;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        logW('⚠️ [CanaisService] Sem permissão para salvar canal público');
        return false;
      }
      rethrow;
    }
  }

  /// Salva canal privado (dados sensíveis - admin only)
  Future<bool> salvarCanalPrivado(String lojaId, CanalPrivado canal) async {
    try {
      await _firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('canais')
          .doc(canal.id.isNotEmpty ? canal.id : canal.tipo)
          .set(canal.toMap(), SetOptions(merge: true));

      logD('✅ [CanaisService] Canal privado salvo: ${canal.tipo}');
      return true;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        logW('⚠️ [CanaisService] Sem permissão para salvar canal privado');
        return false;
      }
      rethrow;
    }
  }

  /// Salva ambos: público (info para catálogo) + privado (dados sensíveis)
  /// Útil quando admin configura um canal completo
  Future<bool> salvarCanalCompleto({
    required String lojaId,
    required String tipo,
    required String nome,
    bool ativo = true,
    String? numero,
    String? token,
    Map<String, dynamic>? config,
  }) async {
    try {
      // 1) Salva versão pública (para catálogo)
      final publicoOk = await salvarCanalPublico(
        lojaId,
        CanalPublico(
          id: tipo,
          nome: nome,
          tipo: tipo,
          ativo: ativo,
        ),
      );

      // 2) Salva versão privada (dados sensíveis)
      final privadoOk = await salvarCanalPrivado(
        lojaId,
        CanalPrivado(
          id: tipo,
          tipo: tipo,
          numero: numero,
          token: token,
          config: config,
        ),
      );

      return publicoOk && privadoOk;
    } catch (e, st) {
      logE('❌ [CanaisService] Erro ao salvar canal completo (type=${e.runtimeType})', error: e, st: st);
      return false;
    }
  }

  /// Remove canal (admin only)
  Future<bool> removerCanal(String lojaId, String tipo) async {
    try {
      // Remove de ambas coleções
      await _firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('canais_publicos')
          .doc(tipo)
          .delete();

      await _firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('canais')
          .doc(tipo)
          .delete();

      logD('🗑️ [CanaisService] Canal removido: $tipo');
      return true;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        logW('⚠️ [CanaisService] Sem permissão para remover canal');
        return false;
      }
      rethrow;
    }
  }

  /// Ativa/desativa canal (toggle)
  Future<bool> toggleCanal(String lojaId, String tipo, bool ativo) async {
    try {
      await _firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('canais_publicos')
          .doc(tipo)
          .update({'ativo': ativo});

      logD('${ativo ? '✅' : '❌'} [CanaisService] Canal $tipo ${ativo ? 'ativado' : 'desativado'}');
      return true;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        logW('⚠️ [CanaisService] Sem permissão para toggle canal');
        return false;
      }
      rethrow;
    }
  }
}
