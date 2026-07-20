// lib/services/notificacao_vendas_service.dart
// Serviço de notificações para vendas
// - Admin: recebe notificação de TODA nova venda
// - Vendedor: recebe notificação quando SUA venda é CONFIRMADA ou CANCELADA

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/logger.dart';

/// Tipos de notificação
enum TipoNotificacao {
  novaVenda, // Admin: nova venda recebida
  vendaConfirmada, // Vendedor: sua venda foi confirmada
  vendaCancelada, // Vendedor: sua venda foi cancelada
  comissaoGerada, // Vendedor: comissão creditada
}

/// Modelo de notificação
class NotificacaoVenda {
  final String id;
  final String destinatarioUid; // Quem recebe
  final String destinatarioEmail;
  final TipoNotificacao tipo;
  final String titulo;
  final String mensagem;
  final String? pedidoId; // Referência ao pedido
  final String? vendaId; // Referência à venda (após confirmação)
  final String storeId;
  final double? valor; // Valor da venda (apenas para admin)
  final double? comissao; // Valor da comissão (apenas para vendedor)
  final bool lida;
  final DateTime criadaEm;
  final Map<String, dynamic>? dados; // Dados extras

  NotificacaoVenda({
    required this.id,
    required this.destinatarioUid,
    required this.destinatarioEmail,
    required this.tipo,
    required this.titulo,
    required this.mensagem,
    this.pedidoId,
    this.vendaId,
    required this.storeId,
    this.valor,
    this.comissao,
    this.lida = false,
    required this.criadaEm,
    this.dados,
  });

  factory NotificacaoVenda.fromFirestore(Map<String, dynamic> data, String id) {
    return NotificacaoVenda(
      id: id,
      destinatarioUid: data['destinatarioUid'] ?? '',
      destinatarioEmail: data['destinatarioEmail'] ?? '',
      tipo: _parseTipo(data['tipo']),
      titulo: data['titulo'] ?? '',
      mensagem: data['mensagem'] ?? '',
      pedidoId: data['pedidoId'],
      vendaId: data['vendaId'],
      storeId: data['storeId'] ?? '',
      valor: (data['valor'] as num?)?.toDouble(),
      comissao: (data['comissao'] as num?)?.toDouble(),
      lida: data['lida'] ?? false,
      criadaEm: _parseTimestamp(data['criadaEm']),
      dados: data['dados'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'destinatarioUid': destinatarioUid,
      'destinatarioEmail': destinatarioEmail,
      'tipo': tipo.name,
      'titulo': titulo,
      'mensagem': mensagem,
      'pedidoId': pedidoId,
      'vendaId': vendaId,
      'storeId': storeId,
      'valor': valor,
      'comissao': comissao,
      'lida': lida,
      'criadaEm': FieldValue.serverTimestamp(),
      'dados': dados,
    };
  }

  static TipoNotificacao _parseTipo(dynamic raw) {
    if (raw == null) return TipoNotificacao.novaVenda;
    final str = raw.toString().toLowerCase();
    switch (str) {
      case 'vendaconfirmada':
        return TipoNotificacao.vendaConfirmada;
      case 'vendacancelada':
        return TipoNotificacao.vendaCancelada;
      case 'comissaogerada':
        return TipoNotificacao.comissaoGerada;
      default:
        return TipoNotificacao.novaVenda;
    }
  }

  static DateTime _parseTimestamp(dynamic raw) {
    if (raw == null) return DateTime.now();
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return DateTime.now();
  }
}

/// Serviço de notificações de vendas
class NotificacaoVendasService {
  static final NotificacaoVendasService _instance =
      NotificacaoVendasService._internal();
  factory NotificacaoVendasService() => _instance;
  NotificacaoVendasService._internal();

  /// Só testes — FakeFirebaseFirestore / harness.
  @visibleForTesting
  static FirebaseFirestore? debugFirestoreOverride;

  /// Contador de badge (cancelamentos) emitido após gravação local/remota.
  static final ValueNotifier<int> exclusaoBadgeTick = ValueNotifier<int>(0);

  FirebaseFirestore get _db => debugFirestoreOverride ?? FirebaseFirestore.instance;

  static const _prefsExclusaoPrefix = 'm39_notif_exclusao_v1_';

  static void _trace(String stage, Map<String, Object?> fields) {
    final parts = fields.entries
        .map((e) => '${e.key}=${e.value ?? ''}')
        .join(' ');
    debugPrint('[M39-NOTIFICACAO] stage=$stage $parts');
  }

  // ==========================================================================
  // NOTIFICAÇÕES PARA ADMIN
  // ==========================================================================

  /// Notifica admin sobre nova venda recebida
  /// Chamado quando um pré-pedido é criado via catálogo
  Future<void> notificarAdminNovaVenda({
    required String storeId,
    required String pedidoId,
    required String clienteNome,
    required double valorTotal,
    required String origem, // 'catalogo_web', 'catalogo_vendedor', etc
    String? vendedorNome, // Se veio de link de vendedor
    bool pagamentoConfirmado = false, // Se gateway já confirmou
  }) async {
    try {
      // Buscar admin(s) da loja
      final lojaDoc = await _db.collection('lojas').doc(storeId).get();
      if (!lojaDoc.exists) return;

      final lojaData = lojaDoc.data() ?? {};
      final adminUid = lojaData['ownerUid'] ?? lojaData['adminUid'] ?? '';
      var adminEmail = (lojaData['ownerEmail'] ?? lojaData['adminEmail'] ?? '')
          .toString()
          .trim();
      if (adminEmail.isEmpty) {
        final owner = lojaData['owner'];
        if (owner is Map && owner['email'] != null) {
          adminEmail = owner['email'].toString().trim();
        }
      }

      if (adminUid.isEmpty) {
        logW('⚠️ [NOTIF] Admin não encontrado para loja $storeId');
        return;
      }

      // Montar mensagem motivadora e entusiasmada! 🎉
      String titulo = pagamentoConfirmado
          ? '🎉 Pedido confirmado! Mais uma venda realizada!'
          : '🛍️ Novo pedido pelo catálogo – alguém quer comprar!';
      String mensagem =
          'Cliente: $clienteNome\nValor: R\$ ${valorTotal.toStringAsFixed(2).replaceAll('.', ',')}';

      if (vendedorNome != null && vendedorNome.isNotEmpty) {
        mensagem += '\nVendedor: $vendedorNome';
      }

      if (pagamentoConfirmado) {
        mensagem += '\n\n✅ Pagamento confirmado – aproveite esse momento!';
      } else {
        mensagem +=
            '\n\n⏳ Aguardando confirmação do pagamento – toque para ver detalhes';
      }

      final notificacao = NotificacaoVenda(
        id: '',
        destinatarioUid: adminUid,
        destinatarioEmail: adminEmail,
        tipo: TipoNotificacao.novaVenda,
        titulo: titulo,
        mensagem: mensagem,
        pedidoId: pedidoId,
        storeId: storeId,
        valor: valorTotal,
        criadaEm: DateTime.now(),
        dados: {
          'clienteNome': clienteNome,
          'origem': origem,
          'vendedorNome': vendedorNome,
          'pagamentoConfirmado': pagamentoConfirmado,
        },
      );

      await _db
          .collection('lojas')
          .doc(storeId)
          .collection('notificacoes')
          .add(notificacao.toFirestore());

      logD('✅ [NOTIF] Admin notificado: nova venda $pedidoId');
    } catch (e, st) {
      logE('❌ [NOTIF] Erro ao notificar admin (type=${e.runtimeType})', error: e, st: st);
    }
  }

  // ==========================================================================
  // NOTIFICAÇÕES PARA VENDEDOR
  // ==========================================================================

  /// Notifica vendedor que sua venda foi CONFIRMADA
  Future<void> notificarVendedorVendaConfirmada({
    required String storeId,
    required String vendedorUid,
    required String vendedorEmail,
    required String pedidoId,
    required String vendaId,
    required String clienteNome,
    required double valorVenda,
    required double valorComissao,
  }) async {
    try {
      // ⚠️ NÃO expor valor total da venda para vendedor
      // Só mostrar valor da comissão dele

      final notificacao = NotificacaoVenda(
        id: '',
        destinatarioUid: vendedorUid,
        destinatarioEmail: vendedorEmail,
        tipo: TipoNotificacao.vendaConfirmada,
        titulo: 'Venda confirmada!',
        mensagem:
            'Cliente: $clienteNome\nSua comissão: R\$ ${valorComissao.toStringAsFixed(2).replaceAll('.', ',')}',
        pedidoId: pedidoId,
        vendaId: vendaId,
        storeId: storeId,
        comissao: valorComissao,
        // ❌ NÃO incluir valor total (valor: valorVenda)
        criadaEm: DateTime.now(),
        dados: {
          'clienteNome': clienteNome,
        },
      );

      await _db
          .collection('lojas')
          .doc(storeId)
          .collection('notificacoes')
          .add(notificacao.toFirestore());

      logD(
          '✅ [NOTIF] Vendedor $vendedorUid notificado: venda confirmada');
    } catch (e, st) {
      logE('❌ [NOTIF] Erro ao notificar vendedor (confirmada) (type=${e.runtimeType})', error: e, st: st);
    }
  }

  /// Notifica vendedor que sua venda foi CANCELADA/EXCLUÍDA.
  ///
  /// Idempotente: 1 venda (pedidoId) → no máx. 1 documento por loja/vendedor/ação.
  /// Retorna `true` se gravou (Firestore e/ou espelho local). Não engole falha sem
  /// sinalizar — o SoftDelete só marca `notificacaoEnviada` quando true.
  ///
  /// Nota Rules: `create` em `notificacoes` exige admin. Exclusão pelo vendedor
  /// cai no espelho local para a tela/badge continuarem a funcionar no device.
  Future<bool> notificarVendedorVendaCancelada({
    required String storeId,
    required String vendedorUid,
    required String vendedorEmail,
    required String pedidoId,
    required String clienteNome,
    String? motivo,
    String tipoAcao = 'excluida',
    String? adminUid,
    String? adminNome,
  }) async {
    _trace('start', {
      'tenant': storeId,
      'sellerUid': vendedorUid,
      'vendaId': pedidoId,
      'tipo': tipoAcao,
      'motivo': motivo,
      'admin': adminUid,
    });
    try {
      final acaoLabel =
          tipoAcao.trim().toLowerCase() == 'cancelada' ? 'cancelada' : 'excluída';
      final tipoAcaoNorm =
          acaoLabel == 'cancelada' ? 'cancelada' : 'excluida';
      final motivoTrim = (motivo ?? '').trim();
      final vendaLabel = pedidoId.trim().isEmpty ? '—' : pedidoId.trim();
      var mensagem =
          'Sua venda nº $vendaLabel foi $acaoLabel pelo administrador.';
      if (motivoTrim.isNotEmpty) {
        mensagem += '\nMotivo: $motivoTrim.';
      }

      final docId = _docIdExclusaoIdempotente(
        storeId: storeId,
        vendedorUid: vendedorUid,
        pedidoId: pedidoId,
        tipoAcao: tipoAcaoNorm,
      );
      _trace('prepare', {
        'tenant': storeId,
        'sellerUid': vendedorUid,
        'vendaId': pedidoId,
        'docId': docId,
        'notificationId': docId,
        'tipo': tipoAcaoNorm,
        'motivo': motivoTrim,
        'admin': adminUid,
      });

      final notificacao = NotificacaoVenda(
        id: docId,
        destinatarioUid: vendedorUid,
        destinatarioEmail: vendedorEmail,
        tipo: TipoNotificacao.vendaCancelada,
        titulo: acaoLabel == 'cancelada' ? 'Venda cancelada' : 'Venda excluída',
        mensagem: mensagem,
        pedidoId: pedidoId,
        storeId: storeId,
        criadaEm: DateTime.now(),
        dados: {
          'clienteNome': clienteNome,
          'motivo': motivoTrim.isEmpty ? null : motivoTrim,
          'tipoAcao': tipoAcaoNorm,
          'idempotencyKey': docId,
          if ((adminUid ?? '').trim().isNotEmpty) 'adminUid': adminUid!.trim(),
          if ((adminNome ?? '').trim().isNotEmpty)
            'adminNome': adminNome!.trim(),
        },
      );

      // Espelho local primeiro (sobrevive a Rules deny + Ctrl+F5).
      final localOk = await _salvarEspelhoExclusaoLocal(notificacao);
      _trace('local', {
        'tenant': storeId,
        'sellerUid': vendedorUid,
        'docId': docId,
        'ok': localOk,
      });

      var firestoreOk = false;
      _trace('firestore', {
        'tenant': storeId,
        'sellerUid': vendedorUid,
        'docId': docId,
      });
      try {
        // Sem get() prévio: get de doc inexistente falha para não-admin (Rules).
        // set com docId estável = create ou overwrite idempotente (1 doc).
        final payload = notificacao.toFirestore();
        // criadaEm local também no payload para leitura imediata sem serverTimestamp.
        payload['criadaEm'] = Timestamp.fromDate(notificacao.criadaEm);
        payload['criadaEmServer'] = FieldValue.serverTimestamp();
        await _db
            .collection('lojas')
            .doc(storeId)
            .collection('notificacoes')
            .doc(docId)
            .set(payload, SetOptions(merge: true));
        firestoreOk = true;
        _trace('firestore_ok', {
          'tenant': storeId,
          'sellerUid': vendedorUid,
          'docId': docId,
        });
      } catch (e, st) {
        logW(
          '[M39-NOTIFICACAO] stage=firestore_fail docId=$docId '
          '(type=${e.runtimeType}) — espelho local=$localOk',
        );
        debugPrint('[M39-NOTIFICACAO] stage=firestore_fail st=$st');
      }

      final ok = firestoreOk || localOk;
      if (ok) {
        exclusaoBadgeTick.value = exclusaoBadgeTick.value + 1;
        _trace('badge', {
          'tenant': storeId,
          'sellerUid': vendedorUid,
          'docId': docId,
          'tick': exclusaoBadgeTick.value,
        });
        _trace('done', {
          'tenant': storeId,
          'sellerUid': vendedorUid,
          'docId': docId,
          'firestoreOk': firestoreOk,
          'localOk': localOk,
        });
        logD(
          '✅ [NOTIF] Vendedor $vendedorUid notificado: venda $acaoLabel '
          'fs=$firestoreOk local=$localOk',
        );
      } else {
        _trace('done', {
          'tenant': storeId,
          'sellerUid': vendedorUid,
          'docId': docId,
          'ok': false,
        });
      }
      return ok;
    } catch (e, st) {
      logE(
        '❌ [NOTIF] Erro ao notificar vendedor (cancelada) (type=${e.runtimeType})',
        error: e,
        st: st,
      );
      _trace('done', {
        'tenant': storeId,
        'sellerUid': vendedorUid,
        'vendaId': pedidoId,
        'ok': false,
        'error': e.runtimeType.toString(),
      });
      return false;
    }
  }

  /// Doc id estável: uma exclusão/cancelamento → uma notificação.
  static String _docIdExclusaoIdempotente({
    required String storeId,
    required String vendedorUid,
    required String pedidoId,
    required String tipoAcao,
  }) {
    final raw =
        '${storeId.trim()}|${vendedorUid.trim()}|${pedidoId.trim()}|${tipoAcao.trim()}';
    final safe = raw.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    if (safe.length <= 700) return 'vx_$safe';
    // Firestore doc id max ~1500; manter prefixo estável.
    return 'vx_${safe.hashCode.toRadixString(16)}_${safe.substring(0, 80)}';
  }

  @visibleForTesting
  static String docIdExclusaoIdempotenteForTest({
    required String storeId,
    required String vendedorUid,
    required String pedidoId,
    required String tipoAcao,
  }) =>
      _docIdExclusaoIdempotente(
        storeId: storeId,
        vendedorUid: vendedorUid,
        pedidoId: pedidoId,
        tipoAcao: tipoAcao,
      );

  static String _prefsKeyExclusao(String storeId, String uid) =>
      '$_prefsExclusaoPrefix${storeId.trim()}_${uid.trim()}';

  Future<bool> _salvarEspelhoExclusaoLocal(NotificacaoVenda n) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _prefsKeyExclusao(n.storeId, n.destinatarioUid);
      final raw = prefs.getString(key);
      final list = <Map<String, dynamic>>[];
      if (raw != null && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final e in decoded) {
            if (e is Map) {
              list.add(Map<String, dynamic>.from(e));
            }
          }
        }
      }
      list.removeWhere((e) => (e['id'] ?? '').toString() == n.id);
      list.insert(0, {
        'id': n.id,
        'destinatarioUid': n.destinatarioUid,
        'destinatarioEmail': n.destinatarioEmail,
        'tipo': n.tipo.name,
        'titulo': n.titulo,
        'mensagem': n.mensagem,
        'pedidoId': n.pedidoId,
        'vendaId': n.vendaId,
        'storeId': n.storeId,
        'lida': n.lida,
        'criadaEm': n.criadaEm.toIso8601String(),
        'dados': n.dados,
      });
      // Limite defensivo.
      while (list.length > 100) {
        list.removeLast();
      }
      await prefs.setString(key, jsonEncode(list));
      return true;
    } catch (e) {
      logW(
        '[M39-NOTIFICACAO] stage=local_fail (type=${e.runtimeType})',
      );
      return false;
    }
  }

  Future<List<NotificacaoVenda>> _lerEspelhoExclusaoLocal(
    String uid,
    String storeId,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKeyExclusao(storeId, uid));
      if (raw == null || raw.trim().isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final out = <NotificacaoVenda>[];
      for (final e in decoded) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        final id = (m['id'] ?? '').toString();
        if (id.isEmpty) continue;
        out.add(
          NotificacaoVenda(
            id: id,
            destinatarioUid: (m['destinatarioUid'] ?? '').toString(),
            destinatarioEmail: (m['destinatarioEmail'] ?? '').toString(),
            tipo: NotificacaoVenda._parseTipo(m['tipo']),
            titulo: (m['titulo'] ?? '').toString(),
            mensagem: (m['mensagem'] ?? '').toString(),
            pedidoId: m['pedidoId']?.toString(),
            vendaId: m['vendaId']?.toString(),
            storeId: (m['storeId'] ?? storeId).toString(),
            lida: m['lida'] == true,
            criadaEm: DateTime.tryParse((m['criadaEm'] ?? '').toString()) ??
                DateTime.now(),
            dados: m['dados'] is Map
                ? Map<String, dynamic>.from(m['dados'] as Map)
                : null,
          ),
        );
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  List<NotificacaoVenda> _mergeNotificacoes(
    List<NotificacaoVenda> remote,
    List<NotificacaoVenda> local,
  ) {
    final byId = <String, NotificacaoVenda>{};
    for (final n in remote) {
      byId[n.id] = n;
    }
    for (final n in local) {
      byId.putIfAbsent(n.id, () => n);
    }
    final list = byId.values.toList()
      ..sort((a, b) => b.criadaEm.compareTo(a.criadaEm));
    return list;
  }

  @visibleForTesting
  static Future<void> clearEspelhoExclusaoForTest({
    required String storeId,
    required String uid,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKeyExclusao(storeId, uid));
  }

  // ==========================================================================
  // LEITURA DE NOTIFICAÇÕES
  // ==========================================================================

  /// Busca últimas notificações (uma leitura). Usado como fallback quando o stream falha.
  /// Não usa orderBy para evitar dependência do índice composto.
  /// Faz merge com espelho local de exclusões (Rules podem negar create ao vendedor).
  Future<List<NotificacaoVenda>> getUltimasNotificacoes(
      String uid, String storeId,
      {int limit = 30}) async {
    try {
      _trace('tela', {'tenant': storeId, 'sellerUid': uid, 'op': 'getUltimas'});
      final snapshot = await _db
          .collection('lojas')
          .doc(storeId)
          .collection('notificacoes')
          .where('destinatarioUid', isEqualTo: uid)
          .limit(limit)
          .get();

      final remote = snapshot.docs
          .map((doc) => NotificacaoVenda.fromFirestore(doc.data(), doc.id))
          .toList();
      final local = await _lerEspelhoExclusaoLocal(uid, storeId);
      final list = _mergeNotificacoes(remote, local);
      _trace('listener', {
        'tenant': storeId,
        'sellerUid': uid,
        'remote': remote.length,
        'local': local.length,
        'merged': list.length,
      });
      return list.take(limit).toList();
    } catch (e) {
      logW('⚠️ [NOTIF] Erro ao buscar últimas (type=${e.runtimeType})');
      // Fallback só local se Firestore falhar.
      final local = await _lerEspelhoExclusaoLocal(uid, storeId);
      local.sort((a, b) => b.criadaEm.compareTo(a.criadaEm));
      return local.take(limit).toList();
    }
  }

  /// Busca notificações não lidas do usuário
  Future<List<NotificacaoVenda>> buscarNaoLidas(
      String uid, String storeId) async {
    try {
      final snapshot = await _db
          .collection('lojas')
          .doc(storeId)
          .collection('notificacoes')
          .where('destinatarioUid', isEqualTo: uid)
          .where('lida', isEqualTo: false)
          .orderBy('criadaEm', descending: true)
          .limit(50)
          .get();

      return snapshot.docs
          .map((doc) => NotificacaoVenda.fromFirestore(doc.data(), doc.id))
          .toList();
    } catch (e) {
      logW('⚠️ [NOTIF] Erro ao buscar não lidas (type=${e.runtimeType})');
      return [];
    }
  }

  /// Conta notificações não lidas
  Future<int> contarNaoLidas(String uid, String storeId) async {
    try {
      final merged = await getUltimasNotificacoes(uid, storeId, limit: 80);
      return merged.where((n) => !n.lida).length;
    } catch (e) {
      logW('⚠️ [NOTIF] Erro ao contar não lidas (type=${e.runtimeType})');
      final local = await _lerEspelhoExclusaoLocal(uid, storeId);
      return local.where((n) => !n.lida).length;
    }
  }

  /// Stream de notificações (tempo real). Em falha (ex.: índice), não quebra o app.
  /// Retorna broadcast para evitar "Stream has already been listened to" em rebuilds.
  Stream<List<NotificacaoVenda>> streamNotificacoes(
      String uid, String storeId) {
    return _db
        .collection('lojas')
        .doc(storeId)
        .collection('notificacoes')
        .where('destinatarioUid', isEqualTo: uid)
        .orderBy('criadaEm', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => NotificacaoVenda.fromFirestore(doc.data(), doc.id))
            .toList())
        .handleError((Object e, StackTrace st) {
      logW('⚠️ [NOTIF] Erro no stream (type=${e.runtimeType})');
    }, test: (_) => true)
        .asBroadcastStream();
  }

  /// Marca notificação como lida
  Future<void> marcarComoLida(String notificacaoId, String storeId) async {
    try {
      await _db
          .collection('lojas')
          .doc(storeId)
          .collection('notificacoes')
          .doc(notificacaoId)
          .update({'lida': true});
    } catch (e) {
      logW('⚠️ [NOTIF] Erro ao marcar como lida (type=${e.runtimeType})');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      // Atualiza espelho em todas as chaves do store (uid desconhecido aqui).
      for (final key in prefs.getKeys()) {
        if (!key.startsWith('$_prefsExclusaoPrefix${storeId.trim()}_')) {
          continue;
        }
        final raw = prefs.getString(key);
        if (raw == null) continue;
        final decoded = jsonDecode(raw);
        if (decoded is! List) continue;
        var changed = false;
        final list = <Map<String, dynamic>>[];
        for (final e in decoded) {
          if (e is! Map) continue;
          final m = Map<String, dynamic>.from(e);
          if ((m['id'] ?? '').toString() == notificacaoId) {
            m['lida'] = true;
            changed = true;
          }
          list.add(m);
        }
        if (changed) {
          await prefs.setString(key, jsonEncode(list));
        }
      }
    } catch (_) {}
  }

  /// Marca todas como lidas
  Future<void> marcarTodasComoLidas(String uid, String storeId) async {
    try {
      final batch = _db.batch();
      final snapshot = await _db
          .collection('lojas')
          .doc(storeId)
          .collection('notificacoes')
          .where('destinatarioUid', isEqualTo: uid)
          .where('lida', isEqualTo: false)
          .get();

      for (final doc in snapshot.docs) {
        batch.update(doc.reference, {'lida': true});
      }

      await batch.commit();
    } catch (e) {
      logW('⚠️ [NOTIF] Erro ao marcar todas como lidas (type=${e.runtimeType})');
    }
  }
}
