// lib/services/notificacao_vendas_service.dart
// Serviço de notificações para vendas
// - Admin: recebe notificação de TODA nova venda
// - Vendedor: recebe notificação quando SUA venda é CONFIRMADA ou CANCELADA

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

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

  final _db = FirebaseFirestore.instance;

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
  /// Idempotente: 1 venda (pedidoId) → no máx. 1 documento por loja/vendedor/ação.
  Future<void> notificarVendedorVendaCancelada({
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
    try {
      final acaoLabel =
          tipoAcao.trim().toLowerCase() == 'cancelada' ? 'cancelada' : 'excluída';
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
        tipoAcao: acaoLabel == 'cancelada' ? 'cancelada' : 'excluida',
      );
      final ref = _db
          .collection('lojas')
          .doc(storeId)
          .collection('notificacoes')
          .doc(docId);
      final existing = await ref.get();
      if (existing.exists) {
        logD(
          '[NOTIF] skip duplicata vendaCancelada docId=$docId '
          'vendedor=$vendedorUid',
        );
        return;
      }

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
          'tipoAcao': acaoLabel == 'cancelada' ? 'cancelada' : 'excluida',
          'idempotencyKey': docId,
          if ((adminUid ?? '').trim().isNotEmpty) 'adminUid': adminUid!.trim(),
          if ((adminNome ?? '').trim().isNotEmpty)
            'adminNome': adminNome!.trim(),
        },
      );

      await ref.set(notificacao.toFirestore());

      logD('✅ [NOTIF] Vendedor $vendedorUid notificado: venda $acaoLabel');
    } catch (e, st) {
      logE('❌ [NOTIF] Erro ao notificar vendedor (cancelada) (type=${e.runtimeType})', error: e, st: st);
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

  // ==========================================================================
  // LEITURA DE NOTIFICAÇÕES
  // ==========================================================================

  /// Busca últimas notificações (uma leitura). Usado como fallback quando o stream falha.
  /// Não usa orderBy para evitar dependência do índice composto.
  Future<List<NotificacaoVenda>> getUltimasNotificacoes(
      String uid, String storeId,
      {int limit = 30}) async {
    try {
      final snapshot = await _db
          .collection('lojas')
          .doc(storeId)
          .collection('notificacoes')
          .where('destinatarioUid', isEqualTo: uid)
          .limit(limit)
          .get();

      final list = snapshot.docs
          .map((doc) => NotificacaoVenda.fromFirestore(doc.data(), doc.id))
          .toList();
      list.sort((a, b) => b.criadaEm.compareTo(a.criadaEm));
      return list.take(limit).toList();
    } catch (e) {
      logW('⚠️ [NOTIF] Erro ao buscar últimas (type=${e.runtimeType})');
      return [];
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
      final snapshot = await _db
          .collection('lojas')
          .doc(storeId)
          .collection('notificacoes')
          .where('destinatarioUid', isEqualTo: uid)
          .where('lida', isEqualTo: false)
          .count()
          .get();

      return snapshot.count ?? 0;
    } catch (e) {
      logW('⚠️ [NOTIF] Erro ao contar não lidas (type=${e.runtimeType})');
      return 0;
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
